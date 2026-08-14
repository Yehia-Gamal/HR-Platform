-- pgTAP: 0380 — إشعارات الإطلاع عند التقديم + تفويض الموافقة حسب خطوة workflow
-- المتطلبات: 0386_approval_time_gating_and_notify_all.sql (التنفيذ النهائي)
-- ---------------------------------------------------------------------------
-- العقد المطبّق فعلياً في decide_request (0416):
--   · المدير المباشر مخوَّل دائماً (مع أو بلا خطوات)
--   · أبو عمار (operations-manager-1) من الخطوة 2 فما فوق
--   · HR لا دور له في القبول/الرفض
--   · موافقة واحدة تُنهي الطلب وتغلق بقية الخطوات

begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;

select plan(13);

-- ─── بيانات الاختبار ───────────────────────────────────────────────────────

-- مستخدمو المصادقة (مطلوب قبل الموظفين والملفات بسبب FK)
insert into auth.users (id, email, aud, role) values
  ('00000001-0000-0000-0000-000000000001'::uuid, 'test-emp-380@test.local', 'authenticated', 'authenticated'),
  ('00000001-0000-0000-0000-000000000002'::uuid, 'test-mgr-380@test.local', 'authenticated', 'authenticated'),
  ('00000001-0000-0000-0000-000000000003'::uuid, 'test-ops-380@test.local', 'authenticated', 'authenticated'),
  ('00000001-0000-0000-0000-000000000004'::uuid, 'test-hr-380@test.local',  'authenticated', 'authenticated'),
  ('00000001-0000-0000-0000-000000000005'::uuid, 'test-exec-380@test.local','authenticated', 'authenticated')
on conflict (id) do nothing;

-- الملفات الشخصية (notify_employee تعتمد على profiles للعثور على المستلم)
-- تُدرج بعد employees بسبب FK profiles_employee_id_fkey
insert into public.employees (id, user_id, employee_code, full_name_ar, is_active)
values
  ('aa000001-0000-0000-0000-000000000001'::uuid, '00000001-0000-0000-0000-000000000001'::uuid,
   'TEST-EMP', 'موظف تجريبي', true),
  -- مدير مباشر
  ('aa000001-0000-0000-0000-000000000002'::uuid, '00000001-0000-0000-0000-000000000002'::uuid,
   'TEST-MGR', 'مدير تجريبي', true),
  -- موظف أوبريشن
  ('aa000001-0000-0000-0000-000000000003'::uuid, '00000001-0000-0000-0000-000000000003'::uuid,
   'TEST-OPS', 'موظف أوبريشن', true),
  -- موظف HR
  ('aa000001-0000-0000-0000-000000000004'::uuid, '00000001-0000-0000-0000-000000000004'::uuid,
   'TEST-HR', 'موظف HR', true),
  -- مدير تنفيذي
  ('aa000001-0000-0000-0000-000000000005'::uuid, '00000001-0000-0000-0000-000000000005'::uuid,
   'TEST-EXEC', 'مدير تنفيذي تجريبي', true)
on conflict (id) do nothing;

-- الملفات الشخصية (notify_employee تعتمد على profiles للعثور على المستلم)
insert into public.profiles (id, employee_id) values
  ('00000001-0000-0000-0000-000000000001'::uuid, 'aa000001-0000-0000-0000-000000000001'::uuid),
  ('00000001-0000-0000-0000-000000000002'::uuid, 'aa000001-0000-0000-0000-000000000002'::uuid),
  ('00000001-0000-0000-0000-000000000003'::uuid, 'aa000001-0000-0000-0000-000000000003'::uuid),
  ('00000001-0000-0000-0000-000000000004'::uuid, 'aa000001-0000-0000-0000-000000000004'::uuid),
  ('00000001-0000-0000-0000-000000000005'::uuid, 'aa000001-0000-0000-0000-000000000005'::uuid)
on conflict (id) do nothing;

-- أدوار
do $$
declare
  v_hr_role   uuid;
  v_exec_role uuid;
  v_ops_role  uuid;
begin
  select id into v_hr_role   from public.roles where slug = 'hr-manager'         limit 1;
  select id into v_exec_role from public.roles where slug = 'executive-director'  limit 1;
  select id into v_ops_role  from public.roles where slug = 'operations-manager-1' limit 1;

  if v_hr_role is not null then
    insert into public.user_roles(user_id, role_id)
    values ('00000001-0000-0000-0000-000000000004'::uuid, v_hr_role)
    on conflict do nothing;
  end if;
  if v_exec_role is not null then
    insert into public.user_roles(user_id, role_id)
    values ('00000001-0000-0000-0000-000000000005'::uuid, v_exec_role)
    on conflict do nothing;
  end if;
  if v_ops_role is not null then
    insert into public.user_roles(user_id, role_id)
    values ('00000001-0000-0000-0000-000000000003'::uuid, v_ops_role)
    on conflict do nothing;
  end if;
end $$;

-- ─── (1) إشعارات الإطلاع فور التقديم ───────────────────────────────────────

insert into public.requests (
  id, request_type, employee_id, manager_employee_id,
  status, workflow_status, title
) values (
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'leave',
  'aa000001-0000-0000-0000-000000000001'::uuid,
  'aa000001-0000-0000-0000-000000000002'::uuid,
  'pending', 'submitted', 'طلب إجازة تجريبي'
);

select ok(
  exists(
    select 1 from public.notifications
    where recipient_employee_id = 'aa000001-0000-0000-0000-000000000005'::uuid
      and entity_id = 'bb000001-0000-0000-0000-000000000001'::uuid
      and (metadata->>'awarenessOnly')::boolean = true
  ),
  '(1) المدير التنفيذي يتلقى إشعار إطلاع فور تقديم الطلب'
);

select ok(
  exists(
    select 1 from public.notifications
    where recipient_employee_id = 'aa000001-0000-0000-0000-000000000004'::uuid
      and entity_id = 'bb000001-0000-0000-0000-000000000001'::uuid
      and (metadata->>'awarenessOnly')::boolean = true
  ),
  '(2) HR يتلقى إشعار متابعة فور تقديم الطلب'
);

select ok(
  (select count(*) from public.notifications
   where entity_id = 'bb000001-0000-0000-0000-000000000001'::uuid
     and (metadata->>'awarenessOnly')::boolean = true) = 2,
  '(3) عدد إشعارات الإطلاع = 2 (تنفيذي + HR فقط)'
);

-- ─── (2) _request_idempotency_key ──────────────────────────────────────────

select ok(
  public._request_idempotency_key(
    'aa000001-0000-0000-0000-000000000001'::uuid,
    'leave', '2026-09-01'::date, '2026-09-03'::date
  ) is not null,
  '(4) _request_idempotency_key(uuid,...) تعمل بدون خطأ'
);

select is(
  public._request_idempotency_key(
    'aa000001-0000-0000-0000-000000000001'::uuid,
    'leave', '2026-09-01'::date, '2026-09-03'::date
  ),
  public._request_idempotency_key(
    'aa000001-0000-0000-0000-000000000001'::uuid,
    'leave', '2026-09-01'::date, '2026-09-03'::date
  ),
  '(5) _request_idempotency_key ثابتة (idempotent) — نفس المدخلات = نفس النتيجة'
);

-- ─── (3) تفويض الموافقة حسب خطوة workflow ─────────────────────────────────
-- طلب بثلاث خطوات: 1 مدير مباشر، 2 أوبريشن، 3 أبو عمار (operations-manager-1)

insert into public.requests (
  id, request_type, employee_id, manager_employee_id,
  status, workflow_status, title
) values (
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'leave',
  'aa000001-0000-0000-0000-000000000001'::uuid,
  'aa000001-0000-0000-0000-000000000002'::uuid,
  'pending', 'submitted', 'طلب لاختبار تفويض الخطوات'
);

-- الخطوة 1: نشطة (المدير المباشر)
insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_employee_id, sla_hours, escalation_deadline
) values (
  'cc000001-0000-0000-0000-000000000001'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  1, 'المدير المباشر', 'approval', 'active',
  'aa000001-0000-0000-0000-000000000002'::uuid,
  2, now() + interval '2 hours'
);

-- الخطوة 2: معلقة (الأوبريشن)
insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_role_slug, sla_hours
) values (
  'cc000001-0000-0000-0000-000000000002'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  2, 'الأوبريشن', 'approval', 'pending',
  'operations-manager', 4
);

-- الخطوة 3: معلقة (أبو عمار)
insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_role_slug, sla_hours
) values (
  'cc000001-0000-0000-0000-000000000003'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  3, 'الموارد البشرية', 'approval', 'pending',
  'operations-manager-1', 48
);

-- HR لا يستطيع الموافقة والخطوة 1 (مدير مباشر) نشطة
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000004"}';
set local "request.jwt.claim.sub" to '00000001-0000-0000-0000-000000000004';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '42501',
  null,
  '(6) HR لا يستطيع الموافقة في خطوة المدير المباشر (قبل تصعيدها)'
);

-- إغلاق الخطوة 1 وتفعيل الخطوة 2 (أوبريشن) — HR لا يستطيع بعد
reset role;
update public.request_steps
  set status = 'approved', acted_at = now()
where id = 'cc000001-0000-0000-0000-000000000001'::uuid;

update public.request_steps
  set status = 'active'
where id = 'cc000001-0000-0000-0000-000000000002'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000004"}';
set local "request.jwt.claim.sub" to '00000001-0000-0000-0000-000000000004';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '42501',
  null,
  '(7) HR لا يستطيع الموافقة في خطوة الأوبريشن (لا دور له إطلاقاً)'
);

-- إغلاق الخطوة 2 وتفعيل الخطوة 3 (أبو عمار) — الآن يستطيع
reset role;
update public.request_steps
  set status = 'approved', acted_at = now()
where id = 'cc000001-0000-0000-0000-000000000002'::uuid;

update public.request_steps
  set status = 'active'
where id = 'cc000001-0000-0000-0000-000000000003'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000003"}';
set local "request.jwt.claim.sub" to '00000001-0000-0000-0000-000000000003';

select lives_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '(8) أبو عمار (operations-manager-1) يستطيع الموافقة عندما تكون الخطوة 3 نشطة'
);

reset role;

-- التحقق من أن الموافقة الواحدة أغلقت جميع الخطوات
select ok(
  not exists(
    select 1 from public.request_steps
    where request_id = 'bb000001-0000-0000-0000-000000000002'::uuid
      and status in ('pending','active','escalated')
  ),
  '(9) موافقة واحدة تُغلق جميع الخطوات المعلقة (لا مرحلتان)'
);

select is(
  (select status from public.requests
   where id = 'bb000001-0000-0000-0000-000000000002'::uuid),
  'approved',
  '(10) الطلب انتقل لحالة approved بنقرة واحدة'
);

-- ─── (4) المدير المباشر دائماً مخوَّل ──────────────────────────────────────
-- طلب جديد بدون خطوات — المدير المباشر يقرر فوراً

insert into public.requests (
  id, request_type, employee_id, manager_employee_id,
  status, workflow_status, title
) values (
  'bb000001-0000-0000-0000-000000000003'::uuid,
  'leave',
  'aa000001-0000-0000-0000-000000000001'::uuid,
  'aa000001-0000-0000-0000-000000000002'::uuid,
  'pending', 'submitted', 'طلب للتحقق من صلاحية المدير الدائمة'
);

set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000002"}';
set local "request.jwt.claim.sub" to '00000001-0000-0000-0000-000000000002';

select lives_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000003'::uuid, 'approve') $$,
  '(11) المدير المباشر يستطيع الموافقة فوراً دون انتظار'
);

reset role;

-- التحقق من وجود إشعار للموظف بعد الموافقة
select ok(
  exists(
    select 1 from public.notifications
    where recipient_employee_id = 'aa000001-0000-0000-0000-000000000001'::uuid
      and entity_id = 'bb000001-0000-0000-0000-000000000003'::uuid
      and category = 'request'
  ),
  '(12) الموظف يتلقى إشعاراً (request) عند الموافقة على طلبه'
);

-- ─── (5) مجهول محجوب ───────────────────────────────────────────────────────

set local role anon;
set local "request.jwt.claims" to '{"role":"anon"}';
set local "request.jwt.claim.sub" to '';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000003'::uuid, 'approve') $$,
  '42501',
  null,
  '(13) مجهول (anon) محجوب من decide_request'
);

reset role;
select * from finish();
rollback;