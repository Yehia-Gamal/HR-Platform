-- 0436: مهلة موحدة ساعتان لكل الطلبات + إشعار ذاتي عند تسجيل الحضور/الانصراف
-- يثبت أن:
--   1) كل خطوات الأوبريشن (operations-manager-1) النشطة sla_hours=2.
--   2) كل التعريفات النشطة default_due_hours=2 وtierHours = 2/2.
--   3) تصعيد process_request_sla يفعل الخطوة 2 بمهلة ساعتين ويقصّ
--      decision_due_at إلى ساعتين ويُشعر الأوبريشن.
--   4) تريجر الحضور يُشعر الموظف نفسه عند تسجيل دخوله (self=true).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;

select plan(14);

-- ═════════════════════════════════════════════════════════════════════
-- 1) مهلة الأوبريشن = ساعتان في كل التعريفات
-- ═════════════════════════════════════════════════════════════════════
select is(
  (select count(*)::int from public.workflow_steps
    where is_active = true and step_type = 'approval'
      and approver_role_slug = 'operations-manager-1'
      and sla_hours <> 2),
  0,
  '(1) كل خطوات الأوبريشن النشطة sla_hours=2'
);

select is(
  (select count(*)::int from public.workflow_definitions
    where is_active = true and default_due_hours <> 2),
  0,
  '(2) كل التعريفات النشطة default_due_hours=2'
);

select is(
  (select count(*)::int from public.workflow_definitions
    where is_active = true
      and config->'tierHours'->>'manager' <> '2'),
  0,
  '(3) tierHours.manager = 2 لكل التعريفات'
);

select is(
  (select count(*)::int from public.workflow_definitions
    where is_active = true
      and config->'tierHours'->>'operations' <> '2'),
  0,
  '(4) tierHours.operations = 2 لكل التعريفات'
);

-- ═════════════════════════════════════════════════════════════════════
-- 2) تصعيد 2 ساعة: الخطوة 2 تُفعّل بمهلة ساعتين + إشعار الأوبريشن
-- ═════════════════════════════════════════════════════════════════════
insert into auth.users (id, email, aud, role)
values
  ('04360000-0000-4000-8000-000000000001', 'tst-0436-emp@test.local',   'authenticated', 'authenticated'),
  ('04360000-0000-4000-8000-000000000002', 'tst-0436-mgr@test.local',   'authenticated', 'authenticated'),
  ('04360000-0000-4000-8000-000000000003', 'tst-0436-ops@test.local',   'authenticated', 'authenticated');

insert into public.employees (id, employee_code, full_name_ar, is_active, status)
values
  ('04360000-0000-4000-8000-000000000101', 'TST-0436-EMP', 'موظف اختبار 0436', true, 'active'),
  ('04360000-0000-4000-8000-000000000102', 'TST-0436-MGR', 'مدير اختبار 0436',  true, 'active'),
  ('04360000-0000-4000-8000-000000000103', 'TST-0436-OPS', 'أوبريشن اختبار 0436', true, 'active');

insert into public.profiles (id, employee_id)
values
  ('04360000-0000-4000-8000-000000000001', '04360000-0000-4000-8000-000000000101'),
  ('04360000-0000-4000-8000-000000000002', '04360000-0000-4000-8000-000000000102'),
  ('04360000-0000-4000-8000-000000000003', '04360000-0000-4000-8000-000000000103');

insert into public.roles (slug, name_ar, is_system, is_full_access)
values ('operations-manager-1', 'مدير التشغيل 1', true, false)
on conflict (slug) do nothing;

insert into public.user_roles (user_id, role_id)
select '04360000-0000-4000-8000-000000000003', id
from public.roles where slug = 'operations-manager-1'
on conflict do nothing;

insert into public.manager_relations (
  employee_id, manager_employee_id, relation_type,
  effective_from, effective_to
) values (
  '04360000-0000-4000-8000-000000000101',
  '04360000-0000-4000-8000-000000000102',
  'primary', current_date, null
);

insert into public.requests (
  id, request_type, employee_id, manager_employee_id,
  status, workflow_status, title, decision_due_at
) values (
  '04360000-0000-4000-8000-000000000201',
  'leave',
  '04360000-0000-4000-8000-000000000101',
  '04360000-0000-4000-8000-000000000102',
  'pending', 'submitted', 'طلب اختبار مهلة ساعتين',
  now() - interval '10 minutes'
);

insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_employee_id, sla_hours, due_at, escalation_deadline
) values (
  '04360000-0000-4000-8000-000000000301',
  '04360000-0000-4000-8000-000000000201',
  1, 'المدير المباشر', 'approval', 'active',
  '04360000-0000-4000-8000-000000000102',
  2, now() - interval '10 minutes', now() - interval '5 minutes'
);

insert into public.request_steps (
  id, request_id, step_order, name_ar, step_type, status,
  assignee_role_slug, sla_hours
) values (
  '04360000-0000-4000-8000-000000000302',
  '04360000-0000-4000-8000-000000000201',
  2, 'مدير التشغيل 1', 'approval', 'pending',
  'operations-manager-1', 2
);

select ok(
  public.process_request_sla(10) >= 1,
  '(5) process_request_sla يلتقط الطلب المتجاوز مهلة الخطوة 1'
);

select is(
  (select status from public.request_steps
    where id = '04360000-0000-4000-8000-000000000302'),
  'active',
  '(6) الخطوة 2 أصبحت نشطة بعد التصعيد'
);

select is(
  (select assignee_employee_id from public.request_steps
    where id = '04360000-0000-4000-8000-000000000302'),
  '04360000-0000-4000-8000-000000000103',
  '(7) الخطوة 2 مُسندة لأبو عمار (operations-manager-1)'
);

select ok(
  (select due_at from public.request_steps
    where id = '04360000-0000-4000-8000-000000000302')
    between now() + interval '110 minutes' and now() + interval '130 minutes',
  '(8) مهلة الخطوة 2 = ساعتان (due_at ≈ now()+2h)'
);

select ok(
  (select decision_due_at from public.requests
    where id = '04360000-0000-4000-8000-000000000201')
    between now() + interval '110 minutes' and now() + interval '130 minutes',
  '(9) decision_due_at مقصوص إلى ساعتين من الآن'
);

select is(
  (select workflow_status from public.requests
    where id = '04360000-0000-4000-8000-000000000201'),
  'awaiting_operator',
  '(10) حالة الطلب awaiting_operator بعد التصعيد'
);

select is(
  (select count(*)::int from public.notifications n
    join public.profiles p on p.id = n.recipient_user_id
    where p.employee_id = '04360000-0000-4000-8000-000000000103'
      and n.entity_type = 'request'
      and n.entity_id = '04360000-0000-4000-8000-000000000201'
      and n.metadata->>'escalation' = 'operations-manager-1'),
  1,
  '(11) إشعار تصعيد وصل لأبو عمار'
);

select is(
  (select count(*)::int from public.request_actions
    where request_id = '04360000-0000-4000-8000-000000000201'
      and action = 'escalate'),
  1,
  '(12) سُجّل إجراء التصعيد في request_actions'
);

-- ═════════════════════════════════════════════════════════════════════
-- 3) إشعار ذاتي عند تسجيل الحضور
-- ═════════════════════════════════════════════════════════════════════
insert into public.attendance_daily (
  employee_id, work_date, first_check_in
) values (
  '04360000-0000-4000-8000-000000000101',
  current_date, current_timestamp
);

select is(
  (select count(*)::int from public.notifications n
    join public.profiles p on p.id = n.recipient_user_id
    where p.employee_id = '04360000-0000-4000-8000-000000000101'
      and n.entity_type = 'attendance_daily'
      and n.metadata->>'self' = 'true'),
  1,
  '(13) الموظف يتلقى إشعاراً ذاتياً عند تسجيل حضوره'
);

select is(
  (select count(*)::int from public.notifications n
    join public.profiles p on p.id = n.recipient_user_id
    where p.employee_id = '04360000-0000-4000-8000-000000000102'
      and n.entity_type = 'attendance_daily'
      and n.metadata->>'managerId' = '04360000-0000-4000-8000-000000000102'),
  1,
  '(14) مدير الموظف يتلقى إشعار الدخول كما كان سابقاً'
);

select finish();
rollback;