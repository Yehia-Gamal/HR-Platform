-- 0065: V23 §8 — Notification catalog completion tests.
-- Tests: device approval notifications, holiday broadcast, dispute status
-- notifications, role assignment/revocation notifications.
-- Everything rolls back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
declare
  v_le   uuid := 'aa880000-0000-4000-8000-000000000001';
  v_dept uuid := 'aa880000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities (id, code, name)
    values (v_le, 'NC8-LE', 'كيان اختبار الإشعارات');
  insert into public.departments (id, legal_entity_id, code, name)
    values (v_dept, v_le, 'NC8-D1', 'قسم اختبار');

  insert into auth.users (id, email, aud, role) values
    ('aa990000-0000-4000-8000-000000000001', 'nc8-admin@test.local',  'authenticated','authenticated'),
    ('aa990000-0000-4000-8000-000000000002', 'nc8-emp1@test.local',   'authenticated','authenticated'),
    ('aa990000-0000-4000-8000-000000000003', 'nc8-emp2@test.local',   'authenticated','authenticated'),
    ('aa990000-0000-4000-8000-000000000004', 'nc8-emp3@test.local',   'authenticated','authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('aabb0000-0000-4000-8000-000000000001','aa990000-0000-4000-8000-000000000001','NC8-001','مدير النظام',   v_dept,'active',true),
    ('aabb0000-0000-4000-8000-000000000002','aa990000-0000-4000-8000-000000000002','NC8-002','موظف أول',       v_dept,'active',true),
    ('aabb0000-0000-4000-8000-000000000003','aa990000-0000-4000-8000-000000000003','NC8-003','موظف ثاني',      v_dept,'active',true),
    ('aabb0000-0000-4000-8000-000000000004','aa990000-0000-4000-8000-000000000004','NC8-004','موظف ثالث',      v_dept,'active',true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('aa990000-0000-4000-8000-000000000001'::uuid,'aabb0000-0000-4000-8000-000000000001'::uuid),
    ('aa990000-0000-4000-8000-000000000002'::uuid,'aabb0000-0000-4000-8000-000000000002'::uuid),
    ('aa990000-0000-4000-8000-000000000003'::uuid,'aabb0000-0000-4000-8000-000000000003'::uuid),
    ('aa990000-0000-4000-8000-000000000004'::uuid,'aabb0000-0000-4000-8000-000000000004'::uuid)
  ) as t(u,e);

  -- هذا INSERT سيُطلق trg_role_assignment_notify — ننظّف الإشعارات لاحقاً
  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('aa990000-0000-4000-8000-000000000001'::uuid, 'admin'),
    ('aa990000-0000-4000-8000-000000000002'::uuid, 'employee'),
    ('aa990000-0000-4000-8000-000000000003'::uuid, 'employee'),
    ('aa990000-0000-4000-8000-000000000004'::uuid, 'employee')
  ) as t(u, slug)
  join public.roles r on r.slug = t.slug;
end
$fixture$;

-- تنظيف الإشعارات الناتجة عن إدراج الأدوار في الفيكسشر
delete from public.notifications
where recipient_user_id in (
  'aa990000-0000-4000-8000-000000000001',
  'aa990000-0000-4000-8000-000000000002',
  'aa990000-0000-4000-8000-000000000003',
  'aa990000-0000-4000-8000-000000000004'
);

-- Helper to switch persona
create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- 1-4: Trigger existence
-- =====================================================================
select has_trigger('public', 'employee_devices',  'trg_device_pending_notify_admins',
  'trigger: device pending notify admins exists');

select has_trigger('public', 'public_holidays',   'trg_public_holiday_broadcast',
  'trigger: public holiday broadcast exists');

select has_trigger('public', 'dispute_cases',     'trg_dispute_status_notify',
  'trigger: dispute status notify exists');

select has_trigger('public', 'user_roles',        'trg_role_assignment_notify',
  'trigger: role assignment notify exists');

-- =====================================================================
-- 5: Device pending → admin notified
-- =====================================================================
insert into public.employee_devices(
  id, employee_id, user_id, device_identifier_hash, device_name, platform, status
) values (
  'aad00000-0000-4000-8000-000000000001',
  'aabb0000-0000-4000-8000-000000000002',
  'aa990000-0000-4000-8000-000000000002',
  'nc8_hash_test_001', 'هاتف اختبار', 'android', 'pending'
);

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000001'
     and entity_type = 'employee_device'
     and metadata->>'kind' = 'device_pending_approval') >= 1,
  true,
  'device pending: admin receives pending-approval notification');

-- =====================================================================
-- 6: approve_device (approved) → employee notified
-- =====================================================================
select pg_temp.act_as('aa990000-0000-4000-8000-000000000001');
set local role authenticated;

select is(
  (select (public.approve_device(
    'aad00000-0000-4000-8000-000000000001', true))::jsonb->>'ok'),
  'true',
  'approve_device: approval succeeds');

reset role;

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000002'
     and metadata->>'kind' = 'device_approved') >= 1,
  true,
  'approve_device: employee receives approval notification');

-- =====================================================================
-- 7: approve_device (rejected) → employee notified
-- =====================================================================
-- إدراج جهاز ثانٍ بحالة pending للرفض
insert into public.employee_devices(
  id, employee_id, user_id, device_identifier_hash, device_name, platform, status
) values (
  'aad00000-0000-4000-8000-000000000002',
  'aabb0000-0000-4000-8000-000000000003',
  'aa990000-0000-4000-8000-000000000003',
  'nc8_hash_test_002', 'هاتف رفض', 'android', 'pending'
);

select pg_temp.act_as('aa990000-0000-4000-8000-000000000001');
set local role authenticated;

do $rej$ begin
  perform public.approve_device('aad00000-0000-4000-8000-000000000002', false, 'جهاز غير معتمد');
end $rej$;

reset role;

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000003'
     and metadata->>'kind' = 'device_rejected') >= 1,
  true,
  'approve_device: employee receives rejection notification');

-- =====================================================================
-- 8: Holiday broadcast → all 4 employees notified
-- =====================================================================
delete from public.notifications
where recipient_user_id in (
  'aa990000-0000-4000-8000-000000000001',
  'aa990000-0000-4000-8000-000000000002',
  'aa990000-0000-4000-8000-000000000003',
  'aa990000-0000-4000-8000-000000000004'
) and entity_type = 'public_holiday';

insert into public.public_holidays(
  id, legal_entity_id, name, holiday_date, is_active, created_by
) values (
  'aae00000-0000-4000-8000-000000000001',
  'aa880000-0000-4000-8000-000000000001',
  'عطلة اختبار', '2026-12-31', true,
  'aa990000-0000-4000-8000-000000000001'
);

select is(
  (select count(*)::int from public.notifications
   where entity_type = 'public_holiday'
     and entity_id = 'aae00000-0000-4000-8000-000000000001') >= 4,
  true,
  'holiday broadcast: all 4 employees notified');

-- =====================================================================
-- 9-10: Dispute status change → actor + respondent notified
-- =====================================================================
insert into public.dispute_cases(
  id, title, description, case_type, status, severity,
  actor_employee_id, respondent_employee_id, assigned_to,
  created_by
) values (
  'aaf00000-0000-4000-8000-000000000001',
  'نزاع اختبار إشعارات', 'وصف اختبار النزاع لفحص الإشعارات',
  'other', 'submitted', 'normal',
  'aabb0000-0000-4000-8000-000000000002',
  'aabb0000-0000-4000-8000-000000000003',
  'aabb0000-0000-4000-8000-000000000004',
  'aa990000-0000-4000-8000-000000000001'
);

-- تغيير الحالة → يجب أن يُشعَر الأطراف الثلاثة
update public.dispute_cases
set status = 'under_review'
where id = 'aaf00000-0000-4000-8000-000000000001';

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000002'
     and entity_type = 'dispute_case'
     and metadata->>'kind' = 'dispute_status_change'),
  1,
  'dispute status: actor notified on status change');

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000003'
     and entity_type = 'dispute_case'
     and metadata->>'kind' = 'dispute_status_change'),
  1,
  'dispute status: respondent notified on status change');

-- =====================================================================
-- 11-12: Role assignment and revocation
-- =====================================================================
delete from public.notifications
where recipient_user_id = 'aa990000-0000-4000-8000-000000000004'
  and metadata->>'kind' in ('role_granted', 'role_revoked');

-- منح دور جديد لموظف ثالث
insert into public.user_roles (user_id, role_id)
select 'aa990000-0000-4000-8000-000000000004'::uuid, r.id
from public.roles r where r.slug = 'operations-manager';

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000004'
     and metadata->>'kind' = 'role_granted') >= 1,
  true,
  'role assignment: employee notified on role grant');

-- سحب الدور
delete from public.user_roles
where user_id = 'aa990000-0000-4000-8000-000000000004'
  and role_id = (select id from public.roles where slug = 'operations-manager');

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'aabb0000-0000-4000-8000-000000000004'
     and metadata->>'kind' = 'role_revoked') >= 1,
  true,
  'role revocation: employee notified on role revoke');

select * from finish();
rollback;
