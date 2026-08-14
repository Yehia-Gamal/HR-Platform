-- 0421: Live-location push repeat loop regression (Migration 0421).
-- Verifies the V25 fix: no push re-queue after the employee responded, a
-- generous accept session window, and push-job cancellation when a request
-- leaves 'pending'. Everything rolls back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(10);

-- =====================================================================
-- Fixture: target employee + executive requester
-- =====================================================================
do $fixture$
declare
  v_le uuid := 'c1410000-0000-4000-8000-000000000000';
  v_da uuid := 'c1410000-0000-4000-8000-00000000000a';
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'V25-LE', 'كيان اختبار V25');
  insert into public.departments (id, legal_entity_id, code, name)
  values (v_da, v_le, 'V25-A', 'إدارة V25');

  insert into auth.users (id, email, aud, role) values
    ('d1410000-0000-4000-8000-000000000001', 'v25-emp@test.local',  'authenticated','authenticated'),
    ('d1410000-0000-4000-8000-000000000002', 'v25-exec@test.local', 'authenticated','authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('e1410000-0000-4000-8000-000000000001','d1410000-0000-4000-8000-000000000001','V25-001','موظف الهدف V25',  v_da,'active',true),
    ('e1410000-0000-4000-8000-000000000002','d1410000-0000-4000-8000-000000000002','V25-002','المدير التنفيذي V25',v_da,'active',true);

  insert into public.profiles (id, employee_id, status) values
    ('d1410000-0000-4000-8000-000000000001','e1410000-0000-4000-8000-000000000001','active'),
    ('d1410000-0000-4000-8000-000000000002','e1410000-0000-4000-8000-000000000002','active');

  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('d1410000-0000-4000-8000-000000000001'::uuid,'employee'),
    ('d1410000-0000-4000-8000-000000000002'::uuid,'executive-director')
  ) as t(u,slug)
  join public.roles r on r.slug=t.slug;
end
$fixture$;

-- Helper: يبني طلباً بإشعار + push job بحالة معينة، ويعيد id الطلب.
-- ملاحظة: trigger الإشعارات ينشئ push job (queued) تلقائياً عند الإدراج،
-- لذلك نعدّل حالته بدل إدراج صف مكرر.
create or replace function pg_temp.make_request_with_job(
  p_status text,
  p_job_status text,
  out out_request_id uuid,
  out out_notification_id uuid
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_emp uuid := 'e1410000-0000-4000-8000-000000000001';
  v_exec uuid := 'e1410000-0000-4000-8000-000000000002';
  v_uuid uuid := gen_random_uuid();
begin
  insert into public.live_location_requests (
    id, employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_uuid, v_emp, v_exec, 'اختبار V25', p_status, 'verification',
    now(), now() + interval '5 minutes', 1, '{"mode":"snapshot"}'::jsonb,
    'd1410000-0000-4000-8000-000000000002'
  );
  insert into public.notifications (
    recipient_user_id, title, body, category, priority,
    entity_type, entity_id, metadata
  ) values (
    'd1410000-0000-4000-8000-000000000001', 'طلب تحقق من الموقع',
    'اختبار V25', 'system', 'urgent',
    'live_location_request', v_uuid,
    jsonb_build_object('requestId', v_uuid)
  ) returning id into out_notification_id;

  update public.notification_jobs j
  set status = p_job_status
  where j.idempotency_key = out_notification_id::text || ':push';

  out_request_id := v_uuid;
end;
$$;

-- =====================================================================
-- 1) upsert_my_push_token: الاسترداد للطلبات المعلّقة فقط
-- =====================================================================
select set_config('request.jwt.claims',
  '{"sub":"d1410000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select set_config('request.jwt.claim.sub',
  'd1410000-0000-4000-8000-000000000001', true);

do $setup$
declare
  v_pending uuid; v_pending_n uuid;
  v_active uuid;  v_active_n uuid;
  v_rejected uuid; v_rejected_n uuid;
begin
  -- طلب pending مع job فاشل → يجب أن يُعاد جدولته بعد upsert.
  select out_request_id, out_notification_id into v_pending, v_pending_n
  from pg_temp.make_request_with_job('pending', 'failed');
  -- طلب active (سبق أن ردّ الموظف) مع job فاشل → يجب ألا يُعاد.
  select out_request_id, out_notification_id into v_active, v_active_n
  from pg_temp.make_request_with_job('active', 'failed');
  -- طلب rejected مع job فاشل → يجب ألا يُعاد.
  select out_request_id, out_notification_id into v_rejected, v_rejected_n
  from pg_temp.make_request_with_job('rejected', 'failed');
  perform public.upsert_my_push_token('v25-token-00000000000000000001', 'android');
end
$setup$;

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = (
     select r.id from public.live_location_requests r
     join public.notifications n2 on n2.entity_id = r.id
     where n2.title = 'طلب تحقق من الموقع' and r.status = 'pending'
     limit 1
   ) and j.channel = 'push' and j.status = 'queued'),
  1,
  'V25: pending request push job is recovered to queued'
);

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id in (
     select id from public.live_location_requests
     where status in ('active', 'rejected')
   ) and j.channel = 'push' and j.status = 'queued'),
  0,
  'V25: responded requests are never push-recovered'
);

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id in (
     select id from public.live_location_requests
     where status in ('active', 'rejected')
   ) and j.channel = 'push' and j.status = 'failed'),
  2,
  'V25: responded requests keep their failed jobs untouched'
);

-- =====================================================================
-- 2) respond_live_location_request: نافذة قبول لا تقل عن 5 دقائق
-- =====================================================================
do $setup2$
begin
  insert into public.live_location_requests (
    id, employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    'f1410000-0000-4000-8000-000000000001',
    'e1410000-0000-4000-8000-000000000001',
    'e1410000-0000-4000-8000-000000000002',
    'نافذة V25', 'pending', 'verification',
    now(), now() + interval '5 minutes', 1, '{"mode":"snapshot"}'::jsonb,
    'd1410000-0000-4000-8000-000000000002'
  );
end
$setup2$;

select is(
  (select (public.respond_live_location_request(
      'f1410000-0000-4000-8000-000000000001', true)).status),
  'active',
  'V25: accept still returns active'
);

select ok(
  (select expires_at - now() >= interval '4 minutes 59 seconds'
   from public.live_location_requests
   where id = 'f1410000-0000-4000-8000-000000000001'),
  'V25: accept session window is at least 5 minutes even for snapshot'
);

-- =====================================================================
-- 3) trigger: إلغاء push jobs عند خروج الطلب من pending
-- =====================================================================
do $setup3$
declare
  v_id uuid := 'f1410000-0000-4000-8000-000000000002';
  v_n uuid;
begin
  insert into public.live_location_requests (
    id, employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_id, 'e1410000-0000-4000-8000-000000000001',
    'e1410000-0000-4000-8000-000000000002',
    'إلغاء V25', 'pending', 'verification',
    now(), now() + interval '5 minutes', 1, '{"mode":"snapshot"}'::jsonb,
    'd1410000-0000-4000-8000-000000000002'
  );
  insert into public.notifications (
    recipient_user_id, title, body, category, priority,
    entity_type, entity_id, metadata
  ) values (
    'd1410000-0000-4000-8000-000000000001', 'طلب إلغاء V25',
    'اختبار', 'system', 'urgent',
    'live_location_request', v_id,
    jsonb_build_object('requestId', v_id)
  ) returning id into v_n;

  -- trigger الإشعارات أنشأ بالفعل jobs ':push' (queued) و':in_app' (queued)،
  -- لذلك نضيف الحالات الإضافية فقط بمفاتيح مختلفة.
  insert into public.notification_jobs (notification_id, recipient_user_id, channel, status, idempotency_key) values
    (v_n, 'd1410000-0000-4000-8000-000000000001', 'push', 'failed',     v_n::text || ':push:failed'),
    (v_n, 'd1410000-0000-4000-8000-000000000001', 'push', 'processing', v_n::text || ':push:processing'),
    (v_n, 'd1410000-0000-4000-8000-000000000001', 'push', 'sent',       v_n::text || ':push:sent');
end
$setup3$;

-- الرد (قبول) يغيّر الحالة إلى active → يطلق trigger الإلغاء.
do $respond3$
begin
  perform public.respond_live_location_request(
    'f1410000-0000-4000-8000-000000000002', true);
end
$respond3$;

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = 'f1410000-0000-4000-8000-000000000002'
     and j.channel = 'push'
     and j.status in ('queued', 'failed', 'processing')),
  0,
  'V25: non-sent push jobs are cancelled once the request leaves pending'
);

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = 'f1410000-0000-4000-8000-000000000002'
     and j.channel = 'push' and j.status = 'cancelled'),
  3,
  'V25: queued+failed+processing push jobs become cancelled'
);

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = 'f1410000-0000-4000-8000-000000000002'
     and j.channel = 'push' and j.status = 'sent'),
  1,
  'V25: an already-sent job is never cancelled'
);

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = 'f1410000-0000-4000-8000-000000000002'
     and j.channel = 'in_app' and j.status = 'queued'),
  1,
  'V25: in_app jobs are left untouched'
);

-- الرفض أيضاً يلغي jobs المتبقية
do $setup4$
declare
  v_id uuid := 'f1410000-0000-4000-8000-000000000003';
  v_n uuid;
begin
  insert into public.live_location_requests (
    id, employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_id, 'e1410000-0000-4000-8000-000000000001',
    'e1410000-0000-4000-8000-000000000002',
    'رفض V25', 'pending', 'verification',
    now(), now() + interval '5 minutes', 1, '{"mode":"snapshot"}'::jsonb,
    'd1410000-0000-4000-8000-000000000002'
  );
  insert into public.notifications (
    recipient_user_id, title, body, category, priority,
    entity_type, entity_id, metadata
  ) values (
    'd1410000-0000-4000-8000-000000000001', 'طلب رفض V25',
    'اختبار', 'system', 'urgent',
    'live_location_request', v_id,
    jsonb_build_object('requestId', v_id)
  ) returning id into v_n;
  -- الـ trigger أنشأ ':push' (queued) بالفعل — لا نكرره.
  insert into public.notification_jobs (notification_id, recipient_user_id, channel, status, idempotency_key)
  values (v_n, 'd1410000-0000-4000-8000-000000000001', 'push', 'queued', v_n::text || ':push')
  on conflict (idempotency_key) do nothing;
end
$setup4$;

do $respond4$
begin
  perform public.respond_live_location_request(
    'f1410000-0000-4000-8000-000000000003', false);
end
$respond4$;

select is(
  (select count(*)::integer from public.notification_jobs j
   join public.notifications n on n.id = j.notification_id
   where n.entity_id = 'f1410000-0000-4000-8000-000000000003'
     and j.channel = 'push' and j.status = 'cancelled'),
  1,
  'V25: reject also cancels remaining push jobs'
);

select * from finish();
rollback;
