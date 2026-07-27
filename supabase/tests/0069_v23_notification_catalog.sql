-- 0069: V23 notification catalog — triggers + approve_device notifications.
-- Tests migration 0160: device pending/approved/rejected, holiday broadcast,
-- dispute status change, role grant/revoke notifications.
-- 12 assertions, all rolled back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(12);

-- =====================================================================
-- Fixture
-- =====================================================================
do $fix$
declare
  v_le   uuid := 'ff880000-0000-4000-8000-000000000001';
  v_dept uuid := 'ff880000-0000-4000-8000-000000000002';
begin
  insert into public.legal_entities (id, code, name) values
    (v_le, 'NTC-LE', 'كيان اختبار الإشعارات');

  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept, v_le, 'NTC-D1', 'إدارة اختبار');

  -- 4 auth users: admin, emp1 (target), emp2 (respondent), emp3 (unrelated)
  insert into auth.users (id, email, aud, role) values
    ('ff990000-0000-4000-8000-000000000001', 'ntc-admin@test.local', 'authenticated','authenticated'),
    ('ff990000-0000-4000-8000-000000000002', 'ntc-emp1@test.local',  'authenticated','authenticated'),
    ('ff990000-0000-4000-8000-000000000003', 'ntc-emp2@test.local',  'authenticated','authenticated'),
    ('ff990000-0000-4000-8000-000000000004', 'ntc-emp3@test.local',  'authenticated','authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('ffbb0000-0000-4000-8000-000000000001','ff990000-0000-4000-8000-000000000001','NTC-001','مسؤول اختبار',  v_dept,'active',true),
    ('ffbb0000-0000-4000-8000-000000000002','ff990000-0000-4000-8000-000000000002','NTC-002','موظف هدف',      v_dept,'active',true),
    ('ffbb0000-0000-4000-8000-000000000003','ff990000-0000-4000-8000-000000000003','NTC-003','موظف مدعى عليه',v_dept,'active',true),
    ('ffbb0000-0000-4000-8000-000000000004','ff990000-0000-4000-8000-000000000004','NTC-004','موظف ثالث',     v_dept,'active',true);

  insert into public.profiles (id, employee_id, status) values
    ('ff990000-0000-4000-8000-000000000001','ffbb0000-0000-4000-8000-000000000001','active'),
    ('ff990000-0000-4000-8000-000000000002','ffbb0000-0000-4000-8000-000000000002','active'),
    ('ff990000-0000-4000-8000-000000000003','ffbb0000-0000-4000-8000-000000000003','active'),
    ('ff990000-0000-4000-8000-000000000004','ffbb0000-0000-4000-8000-000000000004','active');

  -- Admin gets full-access role
  insert into public.user_roles (user_id, role_id)
  select 'ff990000-0000-4000-8000-000000000001'::uuid, r.id
  from public.roles r where r.is_full_access = true limit 1;

  -- emp1 gets employee role
  insert into public.user_roles (user_id, role_id)
  select 'ff990000-0000-4000-8000-000000000002'::uuid, r.id
  from public.roles r where r.slug = 'employee';

  -- emp2 gets employee role
  insert into public.user_roles (user_id, role_id)
  select 'ff990000-0000-4000-8000-000000000003'::uuid, r.id
  from public.roles r where r.slug = 'employee';

  -- emp3 gets employee role
  insert into public.user_roles (user_id, role_id)
  select 'ff990000-0000-4000-8000-000000000004'::uuid, r.id
  from public.roles r where r.slug = 'employee';

  -- Clean up notifications auto-created by role_assignment trigger above
  delete from public.notifications
  where recipient_employee_id in (
    'ffbb0000-0000-4000-8000-000000000001',
    'ffbb0000-0000-4000-8000-000000000002',
    'ffbb0000-0000-4000-8000-000000000003',
    'ffbb0000-0000-4000-8000-000000000004'
  );
end $fix$;

-- Helper: switch persona
create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub',p_user::text,'role','authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- =====================================================================
-- 1-4: Trigger existence
-- =====================================================================
select has_trigger('public','employee_devices','trg_device_pending_notify_admins',
  '1: trigger trg_device_pending_notify_admins exists');

select has_trigger('public','public_holidays','trg_public_holiday_broadcast',
  '2: trigger trg_public_holiday_broadcast exists');

select has_trigger('public','dispute_cases','trg_dispute_status_notify',
  '3: trigger trg_dispute_status_notify exists');

select has_trigger('public','user_roles','trg_role_assignment_notify',
  '4: trigger trg_role_assignment_notify exists');

-- =====================================================================
-- 5: Device pending INSERT -> admin notified
-- =====================================================================
insert into public.employee_devices (
  id, employee_id, user_id, device_identifier_hash, device_name, platform, status
) values (
  'ffd00000-0000-4000-8000-000000000001',
  'ffbb0000-0000-4000-8000-000000000002',
  'ff990000-0000-4000-8000-000000000002',
  'hash-ntc-test-001', 'جهاز اختبار', 'android', 'pending'
);

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000001'
     and metadata->>'kind' = 'device_pending_approval')::int,
  1, '5: device pending -> admin notified (device_pending_approval)');

-- =====================================================================
-- 6: approve_device (approved) -> employee notified
-- =====================================================================
select pg_temp.act_as('ff990000-0000-4000-8000-000000000001');
set local role authenticated;

select lives_ok(
  $$select public.approve_device('ffd00000-0000-4000-8000-000000000001', true)$$,
  '6: approve_device(approved) succeeds');

reset role;

-- =====================================================================
-- 7: approve_device (rejected) -> employee notified
-- =====================================================================
-- Re-set device to pending for rejection test
update public.employee_devices
set status = 'pending', approved_by = null, approved_at = null, rejection_reason = null
where id = 'ffd00000-0000-4000-8000-000000000001';

select pg_temp.act_as('ff990000-0000-4000-8000-000000000001');
set local role authenticated;

select lives_ok(
  $$select public.approve_device('ffd00000-0000-4000-8000-000000000001', false, 'اختبار رفض')$$,
  '7: approve_device(rejected) succeeds');

reset role;

-- Verify both device_approved and device_rejected notifications exist for emp1
-- Note: mig 0169 removed notification logic from approve_device function,
-- but mig 0177 re-added it via trigger trg_device_approval_notify on employee_devices.
select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000002'
     and metadata->>'kind' in ('device_approved','device_rejected'))::int,
  2, '8: device approval trigger emits approved + rejected notifications (mig 0177)');

-- =====================================================================
-- 9: Holiday broadcast -> all active employees notified
-- =====================================================================
delete from public.notifications
where metadata->>'kind' = 'public_holiday_announced';

insert into public.public_holidays (id, name, holiday_date, is_active, created_by)
values (
  'ffe00000-0000-4000-8000-000000000001',
  'عيد اختبار', '2026-12-31', true,
  'ff990000-0000-4000-8000-000000000001'
);

select cmp_ok(
  (select count(*)::int from public.notifications
   where metadata->>'kind' = 'public_holiday_announced'
     and entity_id = 'ffe00000-0000-4000-8000-000000000001'),
  '>=', 4,
  '9: holiday broadcast reached at least 4 fixture employees');

-- =====================================================================
-- 10-11: Dispute status change -> parties notified
-- =====================================================================
delete from public.notifications
where metadata->>'kind' = 'dispute_status_change';

insert into public.dispute_cases (
  id, title, case_type, status, severity,
  actor_employee_id, respondent_employee_id, assigned_to, created_by
) values (
  'fff00000-0000-4000-8000-000000000001',
  'نزاع اختبار', 'grievance', 'submitted', 'normal',
  'ffbb0000-0000-4000-8000-000000000002',
  'ffbb0000-0000-4000-8000-000000000003',
  'ffbb0000-0000-4000-8000-000000000001',
  'ff990000-0000-4000-8000-000000000001'
);

-- Change status to trigger the notification
update public.dispute_cases
set status = 'under_review'
where id = 'fff00000-0000-4000-8000-000000000001';

select is(
  (select count(*)::int from public.notifications
   where metadata->>'kind' = 'dispute_status_change'
     and recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000002')::int,
  1, '10: dispute status change -> actor notified');

select is(
  (select count(*)::int from public.notifications
   where metadata->>'kind' = 'dispute_status_change'
     and recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000003')::int,
  1, '11: dispute status change -> respondent notified');

-- =====================================================================
-- 12: Role grant/revoke -> employee notified
-- =====================================================================
delete from public.notifications
where metadata->>'kind' in ('role_granted','role_revoked')
  and recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000004';

-- Grant a new role to emp3 (already has 'employee', give another non-full-access role)
do $grant$
declare v_role_id uuid;
begin
  select id into v_role_id from public.roles where slug = 'hr' limit 1;
  if v_role_id is null then
    select id into v_role_id from public.roles where slug <> 'employee' and not is_full_access limit 1;
  end if;
  insert into public.user_roles (user_id, role_id) values
    ('ff990000-0000-4000-8000-000000000004', v_role_id);
  -- Now revoke it
  delete from public.user_roles
  where user_id = 'ff990000-0000-4000-8000-000000000004' and role_id = v_role_id;
end $grant$;

select is(
  (select count(*)::int from public.notifications
   where recipient_employee_id = 'ffbb0000-0000-4000-8000-000000000004'
     and metadata->>'kind' in ('role_granted','role_revoked'))::int,
  2, '12: role grant + revoke -> employee notified twice');

-- =====================================================================
select * from finish();
rollback;
