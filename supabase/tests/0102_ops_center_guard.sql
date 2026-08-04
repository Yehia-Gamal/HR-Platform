-- =====================================================================
-- 0102: حارس get_operations_center_data بعد 0261 (P0 إغلاق تسريب)
--   1. الموظف العادي يُرفض (42501) — كان يمر عبر tasks.read في 0256.
--   2. operations-manager يقرأ (يملك operations.mission.manage/convoy).
--   3. صاحب الصلاحية الكاملة يقرأ.
--   4. المستخدم المجهول يُرفض.
-- 4 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(4);

-- تعطيل trigger الإشعارات لتجنب أخطاء الـ fixture
do $$ begin
  execute 'alter table public.user_roles disable trigger trg_role_assignment_notify';
exception when undefined_object then null;
end $$;

-- =====================================================================
-- Fixture (superuser)
-- =====================================================================
do $fixture$
declare
  v_le         uuid := 'a7a70000-0000-4000-8000-000000000000';
  v_dept       uuid := 'a7a70000-0000-4000-8000-000000000010';
  v_user_e     uuid := 'a7a70000-0000-4000-8000-000000000001'; -- موظف عادي
  v_user_op    uuid := 'a7a70000-0000-4000-8000-000000000002'; -- operations-manager
  v_user_a     uuid := 'a7a70000-0000-4000-8000-000000000003'; -- full-access
  v_emp_e      uuid := 'a7a70000-0000-4000-8000-000000000011';
  v_emp_op     uuid := 'a7a70000-0000-4000-8000-000000000012';
  v_emp_a      uuid := 'a7a70000-0000-4000-8000-000000000013';
  v_role_emp   uuid;
  v_role_op    uuid;
  v_role_admin uuid;
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'A7-LE', 'كيان اختبار حارس العمليات');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'A7-D1', 'إدارة اختبار حارس العمليات');

  insert into auth.users (id, email, aud, role) values
    (v_user_e,  'a7-emp@test.local',  'authenticated', 'authenticated'),
    (v_user_op, 'a7-op@test.local',   'authenticated', 'authenticated'),
    (v_user_a,  'a7-admin@test.local','authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    (v_emp_e,  v_user_e,  'A7-001', 'موظف عادي',        v_dept, 'active', true),
    (v_emp_op, v_user_op, 'A7-002', 'مدير عمليات',      v_dept, 'active', true),
    (v_emp_a,  v_user_a,  'A7-003', 'مسؤول كامل',       v_dept, 'active', true);

  insert into public.profiles (id, employee_id, status) values
    (v_user_e,  v_emp_e,  'active'),
    (v_user_op, v_emp_op, 'active'),
    (v_user_a,  v_emp_a,  'active');

  select id into v_role_emp from public.roles where slug = 'employee';
  select id into v_role_op  from public.roles where slug = 'operations-manager';
  select id into v_role_admin from public.roles where is_full_access = true order by slug limit 1;

  insert into public.user_roles (user_id, role_id) values
    (v_user_e,  v_role_emp),
    (v_user_op, v_role_op),
    (v_user_a,  v_role_admin);
end
$fixture$;

-- =====================================================================
-- 1. الموظف العادي يُرفض (42501)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a70000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a70000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_operations_center_data()$$,
  '42501', null,
  '1. الموظف العادي لا يقرأ مركز العمليات (reports.read/operations.* غير ممنوحة له)'
);

-- =====================================================================
-- 2. operations-manager يقرأ (يملك operations.mission.manage)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a70000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a70000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_operations_center_data()$$,
  '2. operations-manager يقرأ مركز العمليات'
);

-- =====================================================================
-- 3. صاحب الصلاحية الكاملة يقرأ
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a7a70000-0000-4000-8000-000000000003","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a7a70000-0000-4000-8000-000000000003', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_operations_center_data()$$,
  '3. صاحب الصلاحية الكاملة يقرأ مركز العمليات'
);

-- =====================================================================
-- 4. المستخدم المجهول يُرفض
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

select throws_ok(
  $$select public.get_operations_center_data()$$,
  null, null,
  '4. المستخدم المجهول لا يقرأ مركز العمليات'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
