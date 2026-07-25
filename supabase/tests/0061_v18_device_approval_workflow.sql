-- 0061: V18 §5 — Device approval workflow (migration 0145).
-- تسجيل جهاز ← pending ← HR/Admin يوافق أو يرفض ← active / blocked.
-- Tests: RPC existence, columns, trigger, auto-replace, permission guard,
-- approve/reject happy-path, non-reviewable rejection, admin listing.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(18);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Structure — RPCs exist
-- ═══════════════════════════════════════════════════════════════════════════════

select has_function(
  'public', 'approve_device', array['uuid','boolean','text'],
  'approve_device RPC exists'
);
select has_function(
  'public', 'get_pending_devices_admin', array[]::text[],
  'get_pending_devices_admin RPC exists'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Columns on employee_devices
-- ═══════════════════════════════════════════════════════════════════════════════

select has_column('employee_devices', 'approved_by',
  'employee_devices has approved_by');
select has_column('employee_devices', 'approved_at',
  'employee_devices has approved_at');
select has_column('employee_devices', 'rejection_reason',
  'employee_devices has rejection_reason');

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Trigger exists
-- ═══════════════════════════════════════════════════════════════════════════════

select has_trigger(
  'employee_devices', 'trg_employee_devices_auto_replace',
  'auto-replace trigger exists on employee_devices'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Status CHECK includes pending and replaced
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $live$do $t$
  declare v_chk text;
  begin
    select pg_get_constraintdef(c.oid) into v_chk
    from pg_constraint c join pg_class r on c.conrelid=r.oid
    where r.relname='employee_devices' and c.conname='employee_devices_status_check';
    if v_chk not ilike '%pending%' then
      raise exception 'pending not in status CHECK';
    end if;
    if v_chk not ilike '%replaced%' then
      raise exception 'replaced not in status CHECK';
    end if;
  end $t$$live$,
  'status CHECK includes pending and replaced'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Fixtures
-- ═══════════════════════════════════════════════════════════════════════════════

do $fixture$
declare
  v_entity uuid := 'a6100000-0000-4000-8000-000000000001';
  v_dept   uuid := 'a6100000-0000-4000-8000-000000000010';
begin
  insert into public.legal_entities(id, code, name)
  values(v_entity, 'V18-DEV-LE', 'كيان أجهزة V18');
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V18-DEV-D', 'إدارة أجهزة V18');

  -- admin (full-access) + employee (regular)
  insert into auth.users(id, email, aud, role) values
    ('a6100000-0000-4000-8000-000000000101', 'v18dev-admin@test.local', 'authenticated', 'authenticated'),
    ('a6100000-0000-4000-8000-000000000102', 'v18dev-emp@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('a6100000-0000-4000-8000-000000000201', 'a6100000-0000-4000-8000-000000000101', 'DV-ADM', 'مسؤول أجهزة',  v_dept, 'active', true, false),
    ('a6100000-0000-4000-8000-000000000202', 'a6100000-0000-4000-8000-000000000102', 'DV-EMP', 'موظف أجهزة',   v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('a6100000-0000-4000-8000-000000000101', 'a6100000-0000-4000-8000-000000000201', 'active'),
    ('a6100000-0000-4000-8000-000000000102', 'a6100000-0000-4000-8000-000000000202', 'active');

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'a6100000-0000-4000-8000-000000000101', id from public.roles where slug='admin';

  -- employee = basic role
  insert into public.user_roles(user_id, role_id)
  select 'a6100000-0000-4000-8000-000000000102', id from public.roles where slug='employee';

  -- جهاز 1: معلّق (pending) — سيتم الموافقة عليه
  insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
  values('a6100000-0000-4000-8000-000000000301', 'a6100000-0000-4000-8000-000000000202', 'a6100000-0000-4000-8000-000000000102',
    'hash_device_1', null, 'جهاز اختبار 1', 'android', 'pending', now(), '{}');

  -- جهاز 2: معلّق (pending) — سيتم رفضه
  insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
  values('a6100000-0000-4000-8000-000000000302', 'a6100000-0000-4000-8000-000000000202', 'a6100000-0000-4000-8000-000000000102',
    'hash_device_2', null, 'جهاز اختبار 2', 'ios', 'pending', now(), '{}');
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
-- 5. Permission guard — employee cannot approve
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a6100000-0000-4000-8000-000000000102');
set local role authenticated;

select throws_ok(
  $$select public.approve_device(
    'a6100000-0000-4000-8000-000000000301', true, null)$$,
  '42501', null,
  'regular employee cannot approve devices'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. Approve happy path — pending → active
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('a6100000-0000-4000-8000-000000000101');

select lives_ok(
  $$select public.approve_device(
    'a6100000-0000-4000-8000-000000000301', true, null)$$,
  'admin can approve a pending device'
);

select is(
  (select status from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000301'),
  'active',
  'device status becomes active after approval'
);

select ok(
  (select approved_at is not null from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000301'),
  'approved_at is stamped after approval'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. Reject happy path — pending → blocked + reason
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.approve_device(
    'a6100000-0000-4000-8000-000000000302', false, 'جهاز غير معتمد')$$,
  'admin can reject a pending device'
);

select is(
  (select status from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000302'),
  'blocked',
  'device status becomes blocked after rejection'
);

select is(
  (select rejection_reason from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000302'),
  'جهاز غير معتمد',
  'rejection_reason is recorded'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. Non-reviewable state — active device cannot be re-approved
-- ═══════════════════════════════════════════════════════════════════════════════

select throws_ok(
  $$select public.approve_device(
    'a6100000-0000-4000-8000-000000000301', true, null)$$,
  '22023', null,
  'cannot approve a device already in active state'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. Auto-replace — approving new device replaces old active
-- ═══════════════════════════════════════════════════════════════════════════════

-- Re-approve the blocked device → old active (301) should become replaced
select lives_ok(
  $$select public.approve_device(
    'a6100000-0000-4000-8000-000000000302', true, null)$$,
  'approve blocked device succeeds (re-approve path)'
);

select is(
  (select status from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000301'),
  'replaced',
  'previous active device is auto-replaced when new device is approved'
);

select is(
  (select status from public.employee_devices where id = 'a6100000-0000-4000-8000-000000000302'),
  'active',
  'newly approved device is active'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. get_pending_devices_admin — returns empty when no pending/blocked
-- ═══════════════════════════════════════════════════════════════════════════════

select is(
  (select jsonb_array_length(public.get_pending_devices_admin())),
  0,
  'get_pending_devices_admin returns empty after all devices processed'
);

reset role;
select * from finish();
rollback;
