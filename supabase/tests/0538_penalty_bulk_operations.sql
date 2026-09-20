-- 0538: اختبار العمليات الجماعية على الغرامات
begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(8);

do $fixture$
declare
  v_le uuid := 'f0538000-0000-4000-8000-000000000001';
  v_dept uuid := 'f0538000-0000-4000-8000-000000000002';
  v_jt uuid := 'f0538000-0000-4000-8000-000000000003';
  v_admin uuid := 'f0538000-0000-4000-8000-000000000011';
  v_emp uuid := 'f0538000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f0538000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f0538000-0000-4000-8000-000000000022';
  v_role uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0538', 'كيان 0538');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0538', 'إدارة 0538');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0538', 'وظيفة 0538');
  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'admin-0538@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0538@test.local', 'authenticated', 'authenticated');
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164) values
    (v_admin, v_user_a, 'E-0538-A', 'مسؤول 0538', v_dept, v_jt, 'active', true, current_date - 500, '+201000005381'),
    (v_emp, v_user_e, 'E-0538-B', 'موظف 0538', v_dept, v_jt, 'active', true, current_date - 300, '+201000005382');
  insert into public.profiles(id, employee_id, status) values (v_user_a, v_admin, 'active'), (v_user_e, v_emp, 'active');
  insert into public.roles(id, slug, name_ar, name_en, is_full_access) values (gen_random_uuid(), 'admin-0538', 'أدمن 0538', 'Admin 0538', true) on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0538';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;
  v_p1 := public.generate_instant_penalty(v_emp, current_date, 25);
  v_p2 := public.generate_instant_penalty(v_emp, current_date - 1, 45);
  v_p3 := public.generate_instant_penalty(v_emp, current_date - 2, 35);
  perform set_config('app.t0538_user_a', v_user_a::text, false);
  perform set_config('app.t0538_p1', v_p1::text, false);
  perform set_config('app.t0538_p2', v_p2::text, false);
  perform set_config('app.t0538_p3', v_p3::text, false);
end $fixture$;

-- 1. bulk confirm exists
select has_function('public', 'bulk_confirm_penalty_payments', array['uuid[]','text'], 'bulk_confirm fn exists');
select has_function('public', 'bulk_cancel_penalties', array['uuid[]','text'], 'bulk_cancel fn exists');

-- 2. bulk confirm as admin
set local role = authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('app.t0538_user_a'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', current_setting('app.t0538_user_a', true), true);

select is(
  (select public.bulk_confirm_penalty_payments(
    ARRAY[current_setting('app.t0538_p1', true)::uuid, current_setting('app.t0538_p2', true)::uuid],
    '批量确认'
  )),
  2,
  'bulk confirm returns 2'
);

select is(
  (select count(*)::int from public.instant_attendance_penalties
   where id in (current_setting('app.t0538_p1', true)::uuid, current_setting('app.t0538_p2', true)::uuid)
   and status = 'paid'),
  2,
  'both penalties paid after bulk confirm'
);

-- 3. bulk cancel
select is(
  (select public.bulk_cancel_penalties(
    ARRAY[current_setting('app.t0538_p3', true)::uuid],
    'إلغاء تجريبي'
  )),
  1,
  'bulk cancel returns 1'
);

select is(
  (select status from public.instant_attendance_penalties where id = current_setting('app.t0538_p3', true)::uuid),
  'cancelled',
  'penalty cancelled after bulk cancel'
);

-- 4. empty array returns 0
select is(
  (select public.bulk_confirm_penalty_payments(ARRAY[]::uuid[], null)),
  0,
  'empty array returns 0'
);

select is(
  (select public.bulk_cancel_penalties(ARRAY[]::uuid[], 'لا شيء')),
  0,
  'empty cancel returns 0'
);

select * from finish();
rollback;
