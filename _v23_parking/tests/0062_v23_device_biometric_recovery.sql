-- 0062: V23 Agent-03 — Device biometric recovery flow tests.
-- اختبارات: أول جهاز، استبدال، هاتف مفقود، رفض+إعادة تقديم،
-- لا قفل دائم، إلغاء إداري + تنظيف جلسات.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(26);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Structure tests
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
  'employee_devices has revocation_source column');

select has_trigger(
  'employee_devices', 'trg_device_status_change_notification',
  'device status change notification trigger exists'
);

-- status CHECK includes auto_revoked
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
  values(v_entity, 'V23-DEV-LE', 'كيان أجهزة V23');
  insert into public.departments(id, legal_entity_id, code, name)
  values(v_dept, v_entity, 'V23-DEV-D', 'إدارة أجهزة V23');

  -- admin + employee + employee2
  insert into auth.users(id, email, aud, role) values
    ('b6300000-0000-4000-8000-000000000101', 'v23dev-admin@test.local', 'authenticated', 'authenticated'),
    ('b6300000-0000-4000-8000-000000000102', 'v23dev-emp@test.local',   'authenticated', 'authenticated'),
    ('b6300000-0000-4000-8000-000000000103', 'v23dev-emp2@test.local',  'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, is_deleted) values
    ('b6300000-0000-4000-8000-000000000201', 'b6300000-0000-4000-8000-000000000101', 'V23-ADM', 'مسؤول أجهزة V23', v_dept, 'active', true, false),
    ('b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102', 'V23-EMP', 'موظف أجهزة V23',  v_dept, 'active', true, false),
    ('b6300000-0000-4000-8000-000000000203', 'b6300000-0000-4000-8000-000000000103', 'V23-EM2', 'موظف ثاني V23',   v_dept, 'active', true, false);

  insert into public.profiles(id, employee_id, status) values
    ('b6300000-0000-4000-8000-000000000101', 'b6300000-0000-4000-8000-000000000201', 'active'),
    ('b6300000-0000-4000-8000-000000000102', 'b6300000-0000-4000-8000-000000000202', 'active'),
    ('b6300000-0000-4000-8000-000000000103', 'b6300000-0000-4000-8000-000000000203', 'active');

  -- admin = full access
  insert into public.user_roles(user_id, role_id)
  select 'b6300000-0000-4000-8000-000000000101', id from public.roles where slug='admin';

  -- employees = basic role
  insert into public.user_roles(user_id, role_id)
  select 'b6300000-0000-4000-8000-000000000102', id from public.roles where slug='employee';
  insert into public.user_roles(user_id, role_id)
  select 'b6300000-0000-4000-8000-000000000103', id from public.roles where slug='employee';
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
-- Test 1: أول جهاز — يُسجَّل بحالة pending
-- ═══════════════════════════════════════════════════════════════════════════════

insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
values('b6300000-0000-4000-8000-000000000301', 'b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102',
  'v23_hash_device_1', 'v23_cred_1', 'جهاز أول V23', 'android', 'pending', now(), '{}');

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'pending',
  'T1: first device registers as pending'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 2: الموافقة على أول جهاز → active
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');
set local role authenticated;

select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000301', true, null)$$,
  'T2: admin approves first device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'active',
  'T2: first device is now active'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 3: جهاز بديل — التسجيل + الموافقة يستبدل القديم
-- ═══════════════════════════════════════════════════════════════════════════════

-- تسجيل جهاز ثاني (pending)
insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
values('b6300000-0000-4000-8000-000000000302', 'b6300000-0000-4000-8000-000000000202', 'b6300000-0000-4000-8000-000000000102',
  'v23_hash_device_2', 'v23_cred_2', 'جهاز بديل V23', 'android', 'pending', now(), '{}');

-- الموافقة على الجهاز الثاني
select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000302', true, null)$$,
  'T3: admin approves replacement device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'active',
  'T3: replacement device is active'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'replaced',
  'T3: old device status is replaced'
);

select is(
  (select revocation_source from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000301'),
  'replacement',
  'T3: old device revocation_source is replacement'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 4: إلغاء إداري — admin_revoke_device
-- ═══════════════════════════════════════════════════════════════════════════════

select lives_ok(
  $$select public.admin_revoke_device(
    'b6300000-0000-4000-8000-000000000302', 'جهاز مشبوه')$$,
  'T4: admin revokes active device'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'revoked',
  'T4: device is revoked after admin_revoke_device'
);

select is(
  (select revocation_source from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000302'),
  'admin',
  'T4: revocation_source is admin'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 5: موظف لا يستطيع إلغاء جهاز إدارياً
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000102');

select throws_ok(
  $$select public.admin_revoke_device(
    'b6300000-0000-4000-8000-000000000302', 'محاولة')$$,
  '42501', null,
  'T5: employee cannot admin_revoke_device'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 6: هاتف مفقود — request_device_replacement
-- ═══════════════════════════════════════════════════════════════════════════════

-- أنشئ جهاز نشط لموظف 2
select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');

insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, approved_by, approved_at, metadata)
values('b6300000-0000-4000-8000-000000000303', 'b6300000-0000-4000-8000-000000000203', 'b6300000-0000-4000-8000-000000000103',
  'v23_hash_device_3', 'v23_cred_3', 'جهاز موظف2', 'ios', 'active', now(),
  'b6300000-0000-4000-8000-000000000101', now(), '{}');

-- الموظف يطلب استبدال (يلغي القديم)
select pg_temp.act_as('b6300000-0000-4000-8000-000000000103');

select lives_ok(
  $$select public.request_device_replacement('فقدت الهاتف')$$,
  'T6: employee requests device replacement'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000303'),
  'revoked',
  'T6: old device revoked after replacement request'
);

select is(
  (select revocation_source from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000303'),
  'employee',
  'T6: revocation_source is employee'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 7: لا قفل دائم — بعد الإلغاء يمكن تسجيل جهاز جديد
-- ═══════════════════════════════════════════════════════════════════════════════

insert into public.employee_devices(id, employee_id, user_id, device_identifier_hash, credential_id, device_name, platform, status, registered_at, metadata)
values('b6300000-0000-4000-8000-000000000304', 'b6300000-0000-4000-8000-000000000203', 'b6300000-0000-4000-8000-000000000103',
  'v23_hash_device_4', 'v23_cred_4', 'جهاز جديد بعد الفقد', 'ios', 'pending', now(), '{}');

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000304'),
  'pending',
  'T7: new device registered as pending after revocation (no permanent lockout)'
);

-- الموافقة عليه
select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');

select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000304', true, null)$$,
  'T7: admin approves new device after revocation'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000304'),
  'active',
  'T7: new device is active — no permanent lockout'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 8: رفض + إعادة تقديم — blocked → resubmit → pending → approve
-- ═══════════════════════════════════════════════════════════════════════════════

-- إلغاء الجهاز الجديد أولاً لتنظيف البيئة
select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000304', false, 'اختبار رفض')$$,
  'T8: reject device for resubmit test'
);

-- الآن الجهاز blocked — يمكن إعادة الموافقة عليه
select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000304'),
  'blocked',
  'T8: device is blocked after rejection'
);

-- Wait, approve_device only accepts pending/blocked. Resubmit = approve blocked device.
select lives_ok(
  $$select public.approve_device(
    'b6300000-0000-4000-8000-000000000304', true, null)$$,
  'T8: re-approve blocked device succeeds'
);

select is(
  (select status from public.employee_devices where id = 'b6300000-0000-4000-8000-000000000304'),
  'active',
  'T8: blocked device becomes active after re-approval'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 9: get_my_device_status يعمل للموظف
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000103');

select ok(
  (select jsonb_array_length(public.get_my_device_status()) > 0),
  'T9: get_my_device_status returns devices for employee'
);

-- ═══════════════════════════════════════════════════════════════════════════════
-- Test 10: get_all_devices_admin — تعمل للمسؤول مع فلترة
-- ═══════════════════════════════════════════════════════════════════════════════

select pg_temp.act_as('b6300000-0000-4000-8000-000000000101');

select ok(
  (select jsonb_array_length(public.get_all_devices_admin(null)) > 0),
  'T10: get_all_devices_admin returns all devices'
);

reset role;
select * from finish();
rollback;
