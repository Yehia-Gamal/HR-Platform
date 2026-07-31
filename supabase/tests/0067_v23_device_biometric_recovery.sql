-- 0067: V23 Agent-03 — Device biometric recovery & admin revocation tests.
-- يختبر: auto_revoked CHECK، revocation_source، إلغاء إداري، طلب استبدال،
-- تنظيف الجلسات، get_all_devices_admin، get_my_device_status، عدم القفل الدائم.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(25);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure — RPCs & columns exist
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'admin_revoke_device', array['uuid','text'],
  'admin_revoke_device RPC exists'
);
select has_function(
  'public', 'request_device_replacement', array['text'],
  'request_device_replacement RPC exists'
);
select has_function(
  'public', 'get_my_device_status', array[]::text[],
  'get_my_device_status RPC exists'
);
select has_function(
  'public', 'get_all_devices_admin', array['text'],
  'get_all_devices_admin RPC exists'
);
select has_column('employee_devices', 'revocation_source',
  'employee_devices has revocation_source column'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. CHECK constraint includes auto_revoked
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='employee_devices' and c.conname='employee_devices_status_check';
    if v_chk not ilike '%auto_revoked%' then
      raise exception 'auto_revoked not in status CHECK';
    end if;
  end $t$$live$,
  'status CHECK includes auto_revoked'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'b6300000-0000-4000-8000-000000000001';
  v_dept   uuid := 'b6300000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V23-BIO-LE', 'كيان بصمة V23');
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-BIO-D', 'إدارة بصمة V23');

  -- admin (full-access) + employee (regular)
  insert into auth.users(id, email, aud, role) values
    ('b6300000-0000-4000-8000-000000000101', 'v23bio-admin@test.local', 'authenticated', 'authenticated'),
    ('b6300000-0000-4000-8000-000000000102', 'v23bio-emp@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('b6300000-0000-4000-8000-000000000201', 'b6300000-0000-4000-8000-000000000101', 'BIO-ADM', 'مسؤول بصمة V23', v_dept, 'active', true, false),
    ('b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102', 'BIO-EMP', 'موظف بصمة V23',  v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('b6300000-0000-4000-8000-000000000101', 'b6300000-0000-4000-8000-000000000201', 'active'),
    ('b6300000-0000-4000-8000-000000000102', 'b6300000-0000-4000-8000-000000000202', 'active');

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'b6300000-0000-4000-8000-000000000101', id from public.roles where slug='admin';

  -- employee = basic role
  insert into public.user_roles(user_id, role_id)
  select 'b6300000-0000-4000-8000-000000000102', id from public.roles where slug='employee';

  -- جهاز 1: نشط (active) — سيتم إلغاؤه إدارياً
  insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, approved_at, metadata)
  values('b6300000-0000-4000-8000-000000000301', 'b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102',
    'hash_bio_dev_1', null, 'جهاز بصمة 1', 'android', 'active', now() - interval '7 days', now() - interval '6 days', '{}');

  -- جهاز 2: معلّق (pending) — للاختبارات اللاحقة
  insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
  values('b6300000-0000-4000-8000-000000000302', 'b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102',
    'hash_bio_dev_2', null, 'جهاز بصمة 2', 'android', 'pending', now(), '{}');
end
$fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Permission guard — employee cannot admin_revoke_device
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $$select public.admin_revoke_device(
    'b6300000-0000-4000-8000-000000000301', 'test')$$,
  '42501', null,
  'regular employee cannot admin_revoke_device'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Permission guard — employee cannot get_all_devices_admin
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select jsonb_array_length(public.get_all_devices_admin(null))),
  0,
  'employee gets empty array from get_all_devices_admin'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. Admin revoke — active → revoked + revocation_source = admin
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');

select lives_ok(
  $$select public.admin_revoke_device(
    'b6300000-0000-4000-8000-000000000301', 'جهاز مفقود')$$,
  'admin can revoke an active device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'revoked',
  'device status becomes revoked after admin revoke'
);

select is(
  (select revocation_source from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'admin',
  'revocation_source is admin'
);

select ok(
  (select revoked_at is not null from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'revoked_at is stamped after admin revoke'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. Cannot revoke already-revoked device
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.admin_revoke_device(
    'b6300000-0000-4000-8000-000000000301', 'مكرر')$$,
  '22023', null,
  'cannot revoke an already-revoked device'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. get_all_devices_admin — admin sees all devices
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  (select jsonb_array_length(public.get_all_devices_admin(null)) >= 2),
  'admin sees all devices via get_all_devices_admin'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. get_all_devices_admin — filter by status
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select jsonb_array_length(public.get_all_devices_admin('pending'))),
  1,
  'get_all_devices_admin(pending) returns only pending devices'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. Approve pending device (device 2) — pending → active
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000302', true, null)$$,
  'admin approves pending device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'active',
  'device 2 becomes active after approval'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. Lost phone flow — employee requests replacement
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000102');

select lives_ok(
  $$select public.request_device_replacement('فقدت الهاتف')$$,
  'employee can request device replacement'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'active',
  'active device remains usable until the replacement is approved'
);

select ok(
  (select revocation_source is null from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'replacement request does not mark the active device as revoked'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. No permanent lockout — after revocation, employee can see they need a new device
-- ═══════════════════════════════════════════════════════════════════════════════

select ok(
  (select (public.get_my_device_status()->>'hasActiveDevice')::boolean = true),
  'get_my_device_status keeps the current active device during replacement review'
);

select ok(
  (select (public.get_my_device_status()->>'canRegisterNew')::boolean = true),
  'employee can register a new device after replacement (no lockout)'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 12. Reject + resubmit — blocked device employee gets canResubmit=true
-- ═══════════════════════════════════════════════════════════════════════════════

-- Insert a new pending device for the employee (needs superuser for direct INSERT)
reset role;
do $new_dev$
begin
  insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
  values('b6300000-0000-4000-8000-000000000303', 'b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102',
    'hash_bio_dev_3', null, 'جهاز بصمة 3', 'android', 'pending', now(), '{}');
end
$new_dev$;

-- Admin rejects it
set local role authenticated;
select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');

select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000303', false, 'جهاز غير مطابق')$$,
  'admin rejects new device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000303'),
  'blocked',
  'rejected device becomes blocked'
);

select is(
  (select rejection_reason from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000303'),
  'جهاز غير مطابق',
  'rejection reason is recorded'
);

reset role;
select * from finish();
rollback;
