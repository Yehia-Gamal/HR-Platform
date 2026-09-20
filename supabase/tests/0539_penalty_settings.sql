-- 0539: اختبار إعدادات الغرامات الإدارية
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(10);

do $fixture$
declare
  v_le uuid := 'f0539000-0000-4000-8000-000000000001';
  v_dept uuid := 'f0539000-0000-4000-8000-000000000002';
  v_jt uuid := 'f0539000-0000-4000-8000-000000000003';
  v_admin uuid := 'f0539000-0000-4000-8000-000000000011';
  v_emp uuid := 'f0539000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f0539000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f0539000-0000-4000-8000-000000000022';
  v_role uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0539', 'كيان 0539');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0539', 'إدارة 0539');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0539', 'وظيفة 0539');
  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'admin-0539@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0539@test.local', 'authenticated', 'authenticated');
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    (v_admin, v_user_a, 'E-0539-A', 'مسؤول 0539', v_dept, v_jt, 'active', true, current_date - 500, '+201000005391'),
    (v_emp, v_user_e, 'E-0539-B', 'موظف 0539', v_dept, v_jt, 'active', true, current_date - 300, '+201000005392');
  insert into public.profiles(id, employee_id, status) values (v_user_a, v_admin, 'active'), (v_user_e, v_emp, 'active');
  insert into public.roles(id, slug, name_ar, name_en, is_full_access) values (gen_random_uuid(), 'admin-0539', 'أدمن 0539', 'Admin 0539', true) on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0539';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;
  perform set_config('app.t0539_user_a', v_user_a::text, false);
  perform set_config('app.t0539_user_e', v_user_e::text, false);
end $fixture$;

-- 1. البنية
select has_table('public', 'penalty_settings', 'penalty_settings table exists');
select has_function('public', 'get_penalty_settings', array[]::text[], 'get_settings fn exists');
select has_function('public', 'update_penalty_settings', array['jsonb'], 'update_settings fn exists');
select ok((select relrowsecurity from pg_class where relname = 'penalty_settings'), 'RLS enabled');

-- 2. القيم الافتراضية
select ok(
  (select count(*)::int from public.penalty_settings) >= 8,
  'at least 8 default settings seeded'
);

select is(
  (select setting_value from public.penalty_settings where setting_key = 'grace_minutes'),
  '15'::jsonb,
  'grace_minutes defaults to 15'
);

-- 3. admin can read settings
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0539_user_a'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0539_user_a', true), true);

select is(
  (select count(*)::int from public.get_penalty_settings()),
  8,
  'get_penalty_settings returns 8 rows'
);

-- 4. admin can update settings
select lives_ok(
  $$select public.update_penalty_settings('[{"key":"grace_minutes","value":20}]'::jsonb)$$,
  'admin updates settings'
);

select is(
  (select setting_value from public.penalty_settings where setting_key = 'grace_minutes'),
  '20'::jsonb,
  'grace_minutes updated to 20'
);

-- 5. non-admin cannot update
reset role;
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0539_user_e'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0539_user_e', true), true);

select throws_ok(
  $$select public.update_penalty_settings('[{"key":"grace_minutes","value":5}]'::jsonb)$$,
  'non-admin update rejected'
);

select * from finish();
rollback;
