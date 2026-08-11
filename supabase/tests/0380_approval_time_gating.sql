-- pgTAP: 0380 — اختبار تقييد صلاحية الموافقة بالزمن + إشعارات التقديم
-- المتطلبات: 0386_approval_time_gating_and_notify_all.sql

begin;
select plan(14);

-- ─── بيانات الاختبار ───────────────────────────────────────────────────────
-- إنشاء موظفين بأدوار مختلفة

-- موظف مقدِّم الطلب
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

-- أدوار
do $$
declare
  v_ops_role  uuid;
  v_hr_role   uuid;
  v_exec_role uuid;
begin
  select id into v_ops_role  from public.roles where slug = 'operations-officer' limit 1;
  select id into v_hr_role   from public.roles where slug = 'hr-manager'         limit 1;
  select id into v_exec_role from public.roles where slug = 'executive-director'  limit 1;

  if v_ops_role is not null then
    insert into public.user_roles(user_id, role_id)
    values ('00000001-0000-0000-0000-000000000003'::uuid, v_ops_role)
    on conflict do nothing;
  end if;
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
end $$;

-- ─── (1) التريغر والإشعارات ─────────────────────────────────────────────────

-- إنشاء طلب ←  يجب أن يُشعر المدير التنفيذي + HR فوراً
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

-- ─── (2) بگ 0380: _request_idempotency_key ──────────────────────────────────

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

-- ─── (3) decide_request — تقييد زمني ───────────────────────────────────────
-- إنشاء طلب بخطوات workflow للاختبار

insert into public.requests (
  id, request_type, employee_id, manager_employee_id,
  status, workflow_status, title
) values (
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'leave',
  'aa000001-0000-0000-0000-000000000001'::uuid,
  'aa000001-0000-0000-0000-000000000002'::uuid,
  'pending', 'submitted', 'طلب لاختبار التقييد الزمني'
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
  'operations-officer', 4
);

-- الخطوة 3: معلقة (HR)
insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_role_slug, sla_hours
) values (
  'cc000001-0000-0000-0000-000000000003'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  3, 'الموارد البشرية', 'approval', 'pending',
  'hr-manager', 48
);

-- اختبار: الأوبريشن لا يستطيع الموافقة قبل تصعيد الخطوة 1
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000003"}';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '42501',
  null,
  '(6) الأوبريشن لا يستطيع الموافقة في مهلة المدير المباشر (قبل 2 ساعة)'
);

-- اختبار: HR لا يستطيع الموافقة قبل تصعيد الخطوة 2
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '42501',
  null,
  '(7) HR لا يستطيع الموافقة في مهلة المدير المباشر'
);

reset role;

-- تصعيد الخطوة 1 (محاكاة مرور 2 ساعة)
update public.request_steps
  set status = 'escalated', escalated_at = now()
where id = 'cc000001-0000-0000-0000-000000000001'::uuid;

-- الآن الأوبريشن يجب أن يستطيع الموافقة
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000003"}';

select lives_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '(8) الأوبريشن يستطيع الموافقة بعد تصعيد الخطوة 1'
);

reset role;

-- إعادة الطلب لحالة pending لاختبار HR
update public.requests
  set status = 'pending', workflow_status = 'escalated', decided_at = null, decided_by = null
where id = 'bb000001-0000-0000-0000-000000000002'::uuid;

update public.request_steps
  set status = 'active'
where id = 'cc000001-0000-0000-0000-000000000002'::uuid;

update public.request_steps
  set status = 'active'
where id = 'cc000001-0000-0000-0000-000000000003'::uuid;

-- HR لا يستطيع بعد (الخطوة 2 لم تُصعَّد بعد)
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000004"}';

select throws_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '42501',
  null,
  '(9) HR لا يستطيع الموافقة — الخطوة 2 (أوبريشن) لم تُصعَّد بعد'
);

reset role;

-- تصعيد الخطوة 2 (محاكاة مرور 4 ساعات على الأوبريشن = 6 ساعات إجمالاً)
update public.request_steps
  set status = 'escalated', escalated_at = now()
where id = 'cc000001-0000-0000-0000-000000000002'::uuid;

-- الآن HR يجب أن يستطيع الموافقة
set local role authenticated;
set local "request.jwt.claims" to '{"sub":"00000001-0000-0000-0000-000000000004"}';

select lives_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000002'::uuid, 'approve') $$,
  '(10) HR يستطيع الموافقة بعد تصعيد الخطوة 2 (6 ساعات)'
);

reset role;

-- التحقق من أن الموافقة الواحدة أغلقت جميع الخطوات
select ok(
  not exists(
    select 1 from public.request_steps
    where request_id = 'bb000001-0000-0000-0000-000000000002'::uuid
      and status in ('pending','active','escalated')
  ),
  '(11) موافقة واحدة تُغلق جميع الخطوات المعلقة (لا مرحلتان)'
);

select is(
  (select status from public.requests
   where id = 'bb000001-0000-0000-0000-000000000002'::uuid),
  'approved',
  '(12) الطلب انتقل لحالة approved بنقرة واحدة'
);

-- ─── (4) المدير المباشر دائماً مخوَّل ──────────────────────────────────────
-- طلب جديد بدون تصعيد
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

select lives_ok(
  $$ select public.decide_request(
    'bb000001-0000-0000-0000-000000000003'::uuid, 'approve') $$,
  '(13) المدير المباشر يستطيع الموافقة فوراً دون انتظار'
);

reset role;

-- التحقق من وجود إشعار للموظف بعد الموافقة
select ok(
  exists(
    select 1 from public.notifications
    where recipient_employee_id = 'aa000001-0000-0000-0000-000000000001'::uuid
      and entity_id = 'bb000001-0000-0000-0000-000000000003'::uuid
      and priority = 'high'
  ),
  '(14) الموظف يتلقى إشعاراً صوتياً (high) عند الموافقة على طلبه'
);

-- ─── تنظيف ────────────────────────────────────────────────────────────────
delete from public.notifications
where entity_id in (
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'bb000001-0000-0000-0000-000000000003'::uuid
);
delete from public.request_actions   where request_id in (
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'bb000001-0000-0000-0000-000000000003'::uuid
);
delete from public.request_steps     where request_id in (
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'bb000001-0000-0000-0000-000000000003'::uuid
);
delete from public.requests          where id in (
  'bb000001-0000-0000-0000-000000000001'::uuid,
  'bb000001-0000-0000-0000-000000000002'::uuid,
  'bb000001-0000-0000-0000-000000000003'::uuid
);
delete from public.user_roles where user_id in (
  '00000001-0000-0000-0000-000000000003'::uuid,
  '00000001-0000-0000-0000-000000000004'::uuid,
  '00000001-0000-0000-0000-000000000005'::uuid
);
delete from public.employees where id in (
  'aa000001-0000-0000-0000-000000000001'::uuid,
  'aa000001-0000-0000-0000-000000000002'::uuid,
  'aa000001-0000-0000-0000-000000000003'::uuid,
  'aa000001-0000-0000-0000-000000000004'::uuid,
  'aa000001-0000-0000-0000-000000000005'::uuid
);

select * from finish();
rollback;
