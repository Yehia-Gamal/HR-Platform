-- =====================================================================
-- 0666: اختبار إتاحة الورديات الأربع لمصطفى أحمد ويوسف رسمي
--   • مصطفى أحمد ويوسف رسمي: الورديات المتاحة هي الأربع فترات كاملة
--     (9-5، 10-6 الأساسي، 11-7، 3-11 للعيادات).
--   • طاقم العيادات التابع: ورديتان فقط (10-6، 3-11).
--   • التيم الإداري العام: ثلاث فترات فقط (9-5، 10-6، 11-7).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(12);

do $fixture$
declare
  v_le  uuid := 'f6660000-0000-4000-8000-000000000001';
  v_jt  uuid := 'f6660000-0000-4000-8000-000000000004';
  v_user_mostafa uuid := 'f6660000-0000-4000-8000-000000000010';
  v_user_youssef uuid := 'f6660000-0000-4000-8000-000000000011';
  v_user_clinic  uuid := 'f6660000-0000-4000-8000-000000000012';
  v_user_admin   uuid := 'f6660000-0000-4000-8000-000000000013';
  v_role_cm uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0666', 'كيان 0666') on conflict do nothing;
  insert into public.departments(id, legal_entity_id, code, name, is_isolated) values
    ('f6660000-0000-4000-8000-00000000000a', v_le, 'MED-ADMIN', 'إدارة العيادات 0666', true),
    ('f6660000-0000-4000-8000-00000000000b', v_le, 'HQ-ADMIN',  'الإدارة العامة 0666', false)
  on conflict do nothing;
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0666', 'موظف') on conflict do nothing;

  -- التأكد من وجود الورديات الأربع
  insert into public.shifts(code, name, start_time, end_time, grace_in_minutes, is_active) values
    ('SHIFT_9_5', 'وردية 9 إلى 5', '09:00:00', '17:00:00', 15, true),
    ('OFFICIAL', 'الدوام الأساسي 10 إلى 6', '10:00:00', '18:00:00', 15, true),
    ('SHIFT_11_7', 'وردية 11 إلى 7', '11:00:00', '19:00:00', 15, true),
    ('SHIFT_CLINIC_3_11', 'وردية العيادات 3 إلى 11', '15:00:00', '23:00:00', 15, true)
  on conflict (code) do update set is_active = true, start_time = excluded.start_time, end_time = excluded.end_time;

  insert into auth.users(id, email, aud, role) values
    (v_user_mostafa, 'mostafa-0666@test.local', 'authenticated', 'authenticated'),
    (v_user_youssef, 'youssef-0666@test.local', 'authenticated', 'authenticated'),
    (v_user_clinic,  'nurse-0666@test.local',   'authenticated', 'authenticated'),
    (v_user_admin,   'admin-0666@test.local',   'authenticated', 'authenticated')
  on conflict (id) do nothing;

  -- مصطفى أحمد
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c', v_user_mostafa, 'E-0666-M', 'مصطفى أحمد كمال الدين', 'f6660000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000666001')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- يوسف رسمي
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', v_user_youssef, 'E-0666-Y', 'يوسف رسمي شعبان', 'f6660000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000666002')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- موظفة بالعيادات
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values ('f6660000-0000-4000-8000-000000000022', v_user_clinic, 'E-0666-N', 'ممرضة العيادات 0666', 'f6660000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 300, '+201000666003')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- موظف إداري عام
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values ('f6660000-0000-4000-8000-000000000033', v_user_admin, 'E-0666-A', 'إداري عام 0666', 'f6660000-0000-4000-8000-00000000000b', v_jt, 'active', true, current_date - 300, '+201000666004')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  select id into v_role_cm from public.roles where slug = 'clinics-manager';
  if v_role_cm is not null then
    insert into public.user_roles(user_id, role_id) values
      (v_user_mostafa, v_role_cm),
      (v_user_youssef, v_role_cm)
    on conflict do nothing;
  end if;
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- 1) فحص فترات الوردية لمصطفى أحمد (4 فترات: 9-5، 10-6 الأساسي، 11-7، 3-11)
select pg_temp.act_as('f6660000-0000-4000-8000-000000000010');
set local role authenticated;

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  4,
  'مصطفى أحمد يرى الورديات الأربع كاملة'
);

select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' = 'SHIFT_CLINIC_3_11'
  ),
  'مصطفى أحمد متاح له وردية العيادات المسائية 3 إلى 11'
);

select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' = 'OFFICIAL' and (s->>'isDefault')::boolean = true
  ),
  'الدوام الأساسي 10 إلى 6 هو الدوام الأساسي المعتمد'
);

-- 2) فحص فترات الوردية ليوسف رسمي (4 فترات: 9-5، 10-6 الأساسي، 11-7، 3-11)
select pg_temp.act_as('f6660000-0000-4000-8000-000000000011');

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  4,
  'يوسف رسمي يرى الورديات الأربع كاملة'
);

select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' = 'SHIFT_CLINIC_3_11'
  ),
  'يوسف رسمي متاح له وردية العيادات المسائية 3 إلى 11'
);

select ok(
  exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' = 'OFFICIAL' and (s->>'isDefault')::boolean = true
  ),
  'الدوام الأساسي 10 إلى 6 هو الدوام الأساسي المعتمد ليوسف رسمي'
);

-- 3) فحص فترات الوردية لطاقم العيادات التابع (ورديتان فقط: 10-6، 3-11)
select pg_temp.act_as('f6660000-0000-4000-8000-000000000012');

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  2,
  'طاقم العيادات التابع يرى ورديتي العيادات فقط'
);

select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' in ('SHIFT_9_5', 'SHIFT_11_7')
  ),
  'طاقم العيادات التابع محجوب عنه ورديات 9-5 و 11-7'
);

-- 4) فحص فترات الوردية للموظف الإداري العام (3 فترات فقط: 9-5، 10-6، 11-7)
select pg_temp.act_as('f6660000-0000-4000-8000-000000000013');

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  3,
  'الموظف الإداري العام يرى الفترات الإدارية الثلاث فقط'
);

select ok(
  not exists (
    select 1 from jsonb_array_elements(public.get_my_work_shift_info()->'availableShifts') s
    where s->>'code' = 'SHIFT_CLINIC_3_11'
  ),
  'الموظف الإداري العام محجوب عنه وردية العيادات 3-11'
);

-- 5) تقديم طلب تغيير وردية إلى وردية 3 إلى 11 من يوسف رسمي واعتماده
select pg_temp.act_as('f6660000-0000-4000-8000-000000000011');

select lives_ok($$
  select public.request_my_shift_change(
    (select id from public.shifts where code = 'SHIFT_CLINIC_3_11' and is_active limit 1),
    'تنسيق جدول المتابعة الميدانية للعيادات'
  )
$$, 'يوسف رسمي يقدم طلب تغيير وردية إلى وردية العيادات 3 إلى 11 بنجاح');

reset role;

select ok(
  exists (
    select 1 from public.requests
    where employee_id = 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'
      and request_type = 'shift_change'
      and status = 'pending'
  ),
  'طلب تغيير وردية يوسف رسمي مسجل ومعلق بنجاح'
);

select * from finish();
rollback;
