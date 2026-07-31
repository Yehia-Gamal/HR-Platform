-- =====================================================================
-- 0086: حراس الصلاحيات على RPCs لوحة الإدارة (مهاجرة 0228)
-- التحقق أن get_audit_security_data / get_operations_center_data /
-- get_integration_center_data / get_employee_photo_url ترفض الموظف
-- العادي (ERR_FORBIDDEN / 42501) وتسمح لصاحب الصلاحية.
-- 8 assertions
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(8);

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
  v_le      uuid := 'a6a60000-0000-4000-8000-000000000000';
  v_dept    uuid := 'a6a60000-0000-4000-8000-000000000010';
  v_user_e  uuid := 'a6a60000-0000-4000-8000-000000000001'; -- موظف عادي
  v_user_a  uuid := 'a6a60000-0000-4000-8000-000000000002'; -- مسؤول full-access
  v_emp_e   uuid := 'a6a60000-0000-4000-8000-000000000011';
  v_emp_a   uuid := 'a6a60000-0000-4000-8000-000000000012';
  v_role_emp   uuid;
  v_role_admin uuid;
begin
  insert into public.legal_entities (id, code, name)
  values (v_le, 'A6-LE', 'كيان اختبار الحراس');

  insert into public.departments (id, legal_entity_id, code, name)
  values (v_dept, v_le, 'A6-D1', 'إدارة اختبار الحراس');

  insert into auth.users (id, email, aud, role) values
    (v_user_e, 'a6-emp@test.local',   'authenticated', 'authenticated'),
    (v_user_a, 'a6-admin@test.local', 'authenticated', 'authenticated');

  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    (v_emp_e, v_user_e, 'A6-001', 'موظف عادي',  v_dept, 'active', true),
    (v_emp_a, v_user_a, 'A6-002', 'مسؤول كامل', v_dept, 'active', true);

  insert into public.profiles (id, employee_id, status) values
    (v_user_e, v_emp_e, 'active'),
    (v_user_a, v_emp_a, 'active');

  select id into v_role_emp   from public.roles where slug = 'employee';
  -- دور full-access: نأخذ أعلى دور مُعرّف كـ full access
  select id into v_role_admin from public.roles where is_full_access = true order by slug limit 1;

  insert into public.user_roles (user_id, role_id) values
    (v_user_e, v_role_emp),
    (v_user_a, v_role_admin);
end
$fixture$;

-- =====================================================================
-- الفئة 1: الموظف العادي يُرفض على الدوال الأربع (4 اختبارات)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a6a60000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a6a60000-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select throws_ok(
  $$select public.get_audit_security_data()$$,
  '42501', null,
  '1.1 الموظف العادي لا يستطيع قراءة بيانات التدقيق والأمان'
);

select throws_ok(
  $$select public.get_operations_center_data()$$,
  '42501', null,
  '1.2 الموظف العادي لا يستطيع قراءة بيانات مركز العمليات'
);

select throws_ok(
  $$select public.get_integration_center_data()$$,
  '42501', null,
  '1.3 الموظف العادي لا يستطيع قراءة بيانات مركز التكامل'
);

select throws_ok(
  $$select public.get_employee_photo_url('a6a60000-0000-4000-8000-000000000012')$$,
  '42501', null,
  '1.4 الموظف العادي لا يستطيع قراءة صورة موظف آخر'
);

-- =====================================================================
-- الفئة 2: صاحب الصلاحية الكاملة ينجح على الدوال الثلاث (3 اختبارات)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"a6a60000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',
    'a6a60000-0000-4000-8000-000000000002', true);
end $$;
set local role authenticated;

select lives_ok(
  $$select public.get_audit_security_data()$$,
  '2.1 المسؤول الكامل يقرأ بيانات التدقيق والأمان'
);

select lives_ok(
  $$select public.get_operations_center_data()$$,
  '2.2 المسؤول الكامل يقرأ بيانات مركز العمليات'
);

select lives_ok(
  $$select public.get_integration_center_data()$$,
  '2.3 المسؤول الكامل يقرأ بيانات مركز التكامل'
);

-- =====================================================================
-- الفئة 3: المستخدم المجهول يُرفض (1 اختبار)
-- =====================================================================
reset role;
do $$ begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role anon;

select throws_ok(
  $$select public.get_audit_security_data()$$,
  null, null,
  '3.1 المستخدم المجهول لا يستطيع قراءة بيانات التدقيق'
);

-- =====================================================================
reset role;
select * from finish();
rollback;
