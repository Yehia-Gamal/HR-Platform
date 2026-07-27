-- 0063: V23 — اختبار كتالوج الإشعارات (Migration 0163)
-- يتحقق من:
--   1. إشعار الموظف عند قبول/رفض جهاز (approve_device)
--   2. إشعار المسؤولين عند تسجيل جهاز pending
--   3. إشعار جماعي عند إضافة عطلة رسمية
--   4. إشعار أطراف المشكلات عند تغيير الحالة
--   5. إشعار الموظف عند إسناد/سحب دور

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- =====================================================================
-- Fixture
-- =====================================================================
do $fixture$
declare
  v_le   uuid := 'aa630000-0000-4000-8000-000000000000';
  v_dept uuid := 'aa630000-0000-4000-8000-00000000000a';
begin
  insert into public.legal_entities (id, code, name) values
    (v_le, 'NC-LE', 'كيان اختبار الإشعارات');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept, v_le, 'NC-D1', 'إدارة الإشعارات');

  -- 4 users: admin, employee-target, actor (complainant), respondent
  insert into auth.users (id, email, aud, role) values
    ('aa630000-0000-4000-8000-000000000001', 'nc-admin@test.local',      'authenticated','authenticated'),
    ('aa630000-0000-4000-8000-000000000002', 'nc-employee@test.local',   'authenticated','authenticated'),
    ('aa630000-0000-4000-8000-000000000003', 'nc-actor@test.local',      'authenticated','authenticated'),
    ('aa630000-0000-4000-8000-000000000004', 'nc-respondent@test.local', 'authenticated','authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('bb630000-0000-4000-8000-000000000001','aa630000-0000-4000-8000-000000000001','NC-001','مدير الإشعارات', v_dept,'active',true),
    ('bb630000-0000-4000-8000-000000000002','aa630000-0000-4000-8000-000000000002','NC-002','موظف الجهاز',    v_dept,'active',true),
    ('bb630000-0000-4000-8000-000000000003','aa630000-0000-4000-8000-000000000003','NC-003','مقدّم الشكوى',   v_dept,'active',true),
    ('bb630000-0000-4000-8000-000000000004','aa630000-0000-4000-8000-000000000004','NC-004','المشتكى عليه',   v_dept,'active',true);

  insert into public.profiles (id, employee_id, status)
  select u, e, 'active' from (values
    ('aa630000-0000-4000-8000-000000000001'::uuid,'bb630000-0000-4000-8000-000000000001'::uuid),
    ('aa630000-0000-4000-8000-000000000002'::uuid,'bb630000-0000-4000-8000-000000000002'::uuid),
    ('aa630000-0000-4000-8000-000000000003'::uuid,'bb630000-0000-4000-8000-000000000003'::uuid),
    ('aa630000-0000-4000-8000-000000000004'::uuid,'bb630000-0000-4000-8000-000000000004'::uuid)
  ) as t(u,e);

  -- admin role (full-access)
  insert into public.user_roles (user_id, role_id)
  select 'aa630000-0000-4000-8000-000000000001'::uuid, r.id
  from public.roles r where r.slug = 'admin';

  -- employee roles
  insert into public.user_roles (user_id, role_id)
  select t.u, r.id from (values
    ('aa630000-0000-4000-8000-000000000002'::uuid),
    ('aa630000-0000-4000-8000-000000000003'::uuid),
    ('aa630000-0000-4000-8000-000000000004'::uuid)
  ) as t(u)
  cross join public.roles r where r.slug = 'employee';
end
$fixture$;

-- Helper
create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_user::text,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- A. Triggers exist
-- =====================================================================

select has_trigger(
  'public', 'employee_devices', 'trg_employee_devices_pending_notify',
  'device pending admin notification trigger exists'
);

select has_trigger(
  'public', 'public_holidays', 'trg_public_holidays_broadcast',
  'public holiday broadcast trigger exists'
);

select has_trigger(
  'public', 'dispute_cases', 'trg_dispute_cases_status_notify',
  'dispute status notification trigger exists'
);

select has_trigger(
  'public', 'user_roles', 'trg_user_roles_assignment_notify',
  'role assignment notification trigger exists'
);

-- =====================================================================
-- B. Device approval notification
-- =====================================================================
-- Insert a pending device for employee-target.
insert into public.employee_devices (id, employee_id, user_id, device_identifier_hash, device_name, platform, status)
values ('cc630000-0000-4000-8000-000000000001', 'bb630000-0000-4000-8000-000000000002',
        'aa630000-0000-4000-8000-000000000002', 'hash_nc_test_001', 'جهاز اختبار', 'android', 'pending');

-- The trigger should have notified the admin
select ok(
  (select count(*)::integer from public.notifications
   where recipient_employee_id = 'bb630000-0000-4000-8000-000000000001'
     and entity_type = 'employee_device') >= 1,
  'admin notified when device registered as pending'
);

-- Admin approves the device
select pg_temp.act_as('aa630000-0000-4000-8000-000000000001');

select lives_ok(
  $$select public.approve_device('cc630000-0000-4000-8000-000000000001', true)$$,
  'admin can approve pending device'
);

select ok(
  (select count(*)::integer from public.notifications
   where recipient_employee_id = 'bb630000-0000-4000-8000-000000000002'
     and title = 'تمت الموافقة على جهازك') >= 1,
  'employee notified on device approval'
);

-- =====================================================================
-- C. Holiday broadcast
-- =====================================================================
insert into public.public_holidays (id, name, holiday_date, is_active, created_by)
values ('dd630000-0000-4000-8000-000000000001', 'عيد اختبار', '2026-12-25', true,
        'aa630000-0000-4000-8000-000000000001');

-- All 4 active employees should get a notification
select ok(
  (select count(*)::integer from public.notifications
   where entity_type = 'public_holiday'
     and entity_id = 'dd630000-0000-4000-8000-000000000001') = 4,
  'all 4 active employees notified on holiday insert'
);

select ok(
  (select title from public.notifications
   where entity_type = 'public_holiday'
     and entity_id = 'dd630000-0000-4000-8000-000000000001'
   limit 1) like '%عيد اختبار%',
  'holiday notification title contains holiday name'
);

-- =====================================================================
-- D. Dispute status notification
-- =====================================================================
-- Insert a dispute case in draft status (no notification expected)
insert into public.dispute_cases (id, title, description, case_type, status, severity,
                                  actor_employee_id, respondent_employee_id, assigned_to)
values ('ee630000-0000-4000-8000-000000000001', 'قضية اختبار الإشعارات', 'وصف القضية',
        'grievance', 'draft', 'medium',
        'bb630000-0000-4000-8000-000000000003',
        'bb630000-0000-4000-8000-000000000004',
        'bb630000-0000-4000-8000-000000000001');

-- Update status to submitted → should notify actor + respondent + assigned_to
update public.dispute_cases
set status = 'submitted'
where id = 'ee630000-0000-4000-8000-000000000001';

select ok(
  (select count(*)::integer from public.notifications
   where entity_type = 'dispute_case'
     and entity_id = 'ee630000-0000-4000-8000-000000000001') = 3,
  'all 3 dispute parties notified on status change to submitted'
);

-- Update status again to under_review → should create 3 more notifications
update public.dispute_cases
set status = 'under_review'
where id = 'ee630000-0000-4000-8000-000000000001';

select ok(
  (select count(*)::integer from public.notifications
   where entity_type = 'dispute_case'
     and entity_id = 'ee630000-0000-4000-8000-000000000001') = 6,
  'dispute parties notified again on status change to under_review (6 total)'
);

-- =====================================================================
-- E. Role assignment notification
-- =====================================================================
-- Clear previous role-assignment notifications first
delete from public.notifications where entity_type = 'user_role';

-- Assign a new role to actor employee
insert into public.user_roles (id, user_id, role_id)
select 'ff630000-0000-4000-8000-000000000001'::uuid,
       'aa630000-0000-4000-8000-000000000003'::uuid, r.id
from public.roles r where r.slug = 'hr';

select ok(
  (select count(*)::integer from public.notifications
   where recipient_employee_id = 'bb630000-0000-4000-8000-000000000003'
     and title = 'تم إسناد دور جديد') >= 1,
  'employee notified on role assignment'
);

-- Revoke the role
delete from public.user_roles where id = 'ff630000-0000-4000-8000-000000000001';

select ok(
  (select count(*)::integer from public.notifications
   where recipient_employee_id = 'bb630000-0000-4000-8000-000000000003'
     and title = 'تم سحب دور') >= 1,
  'employee notified on role revocation'
);

-- =====================================================================
select * from finish();
rollback;
