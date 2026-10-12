-- =====================================================================
-- 0665: اختبار مواءمة صندوق الطلبات وأعلام القرار للإدارة المشتركة
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(8);

do $fixture$
declare
  v_le  uuid := 'f6650000-0000-4000-8000-000000000001';
  v_jt  uuid := 'f6650000-0000-4000-8000-000000000004';
  v_user_mostafa uuid := 'f6650000-0000-4000-8000-000000000010';
  v_user_youssef uuid := 'f6650000-0000-4000-8000-000000000011';
  v_user_clinic  uuid := 'f6650000-0000-4000-8000-000000000012';
  v_role_cm uuid;
  v_role_dm uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0665', 'كيان 0665') on conflict do nothing;
  insert into public.departments(id, legal_entity_id, code, name, is_isolated) values
    ('f6650000-0000-4000-8000-00000000000a', v_le, 'MED-ADMIN', 'إدارة العيادات 0665', true)
  on conflict do nothing;
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0665', 'تمريض') on conflict do nothing;

  insert into auth.users(id, email, aud, role) values
    (v_user_mostafa, 'mostafa-0665@test.local', 'authenticated', 'authenticated'),
    (v_user_youssef, 'youssef-0665@test.local', 'authenticated', 'authenticated'),
    (v_user_clinic,  'nurse-0665@test.local',   'authenticated', 'authenticated')
  on conflict (id) do nothing;

  -- مصطفى أحمد
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c', v_user_mostafa, 'E-0665-M', 'مصطفى أحمد كمال الدين', 'f6650000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000665001')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- يوسف رسمي
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', v_user_youssef, 'E-0665-Y', 'يوسف رسمي شعبان', 'f6650000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000665002')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- موظفة بالعيادات
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values ('f6650000-0000-4000-8000-000000000022', v_user_clinic, 'E-0665-N', 'ممرضة العيادات 0665', 'f6650000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 300, '+201000665003')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  select id into v_role_cm from public.roles where slug = 'clinics-manager';
  select id into v_role_dm from public.roles where slug = 'direct-manager';

  if v_role_cm is not null then
    insert into public.user_roles(user_id, role_id) values
      (v_user_mostafa, v_role_cm),
      (v_user_youssef, v_role_cm)
    on conflict do nothing;
  end if;

  if v_role_dm is not null then
    insert into public.user_roles(user_id, role_id) values
      (v_user_mostafa, v_role_dm),
      (v_user_youssef, v_role_dm)
    on conflict do nothing;
  end if;
end $fixture$;

create or replace function pg_temp.act_as(p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;

-- 1) موظفة العيادات تقدم طلب إذن
select pg_temp.act_as('f6650000-0000-4000-8000-000000000012');
set local role authenticated;

select lives_ok($$
  select public.submit_my_request('late_permit', 'إذن تأخير عيادات 0665', 'موعد طبي',
    jsonb_build_object('permitDate', (now() at time zone 'Africa/Cairo')::date + 1, 'minutes', 30))
$$, 'تقديم إذن تأخير العيادات ينجح');

reset role;

-- 2) فحص ظهور الطلب في صندوق وارد يوسف رسمي مع canDecide و awaitingMe
select pg_temp.act_as('f6650000-0000-4000-8000-000000000011');
set local role authenticated;

select ok(
  exists (
    select 1
    from jsonb_array_elements(public.get_request_inbox(50)) item
    where item->>'employeeId' = 'f6650000-0000-4000-8000-000000000022'
      and (item->>'canDecide')::boolean = true
  ),
  'الطلب يظهر في صندوق وارد يوسف رسمي مع canDecide = true'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(public.get_request_inbox(50)) item
    where item->>'employeeId' = 'f6650000-0000-4000-8000-000000000022'
      and (item->>'awaitingMe')::boolean = true
  ),
  'الطلب يظهر في صندوق وارد يوسف رسمي مع awaitingMe = true'
);

-- 3) فحص ظهور الطلب في صندوق وارد مصطفى أحمد
select pg_temp.act_as('f6650000-0000-4000-8000-000000000010');

select ok(
  exists (
    select 1
    from jsonb_array_elements(public.get_request_inbox(50)) item
    where item->>'employeeId' = 'f6650000-0000-4000-8000-000000000022'
      and (item->>'canDecide')::boolean = true
  ),
  'الطلب يظهر في صندوق وارد مصطفى أحمد مع canDecide = true'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(public.get_request_inbox(50)) item
    where item->>'employeeId' = 'f6650000-0000-4000-8000-000000000022'
      and (item->>'awaitingMe')::boolean = true
  ),
  'الطلب يظهر في صندوق وارد مصطفى أحمد مع awaitingMe = true'
);

-- 4) فحص تفاصيل الطلب عبر get_mobile_request_detail ليوسف رسمي
select pg_temp.act_as('f6650000-0000-4000-8000-000000000011');

do $test_detail$
declare
  v_req_id uuid;
  v_detail jsonb;
begin
  select id into v_req_id
  from public.requests
  where employee_id = 'f6650000-0000-4000-8000-000000000022'
  order by created_at desc limit 1;

  v_detail := public.get_mobile_request_detail(v_req_id);
  if v_detail is null or (v_detail->>'canDecide')::boolean <> true then
    raise exception 'failed to get detail with canDecide=true';
  end if;
end $test_detail$;

select lives_ok($$
  select public.get_mobile_request_detail(
    (select id from public.requests where employee_id = 'f6650000-0000-4000-8000-000000000022' order by created_at desc limit 1)
  )
$$, 'يوسف رسمي يفتح تفاصيل طلب العيادات بنجاح');

select is(
  (select (public.get_mobile_request_detail(
    (select id from public.requests where employee_id = 'f6650000-0000-4000-8000-000000000022' order by created_at desc limit 1)
  )->>'canDecide')::boolean),
  true,
  'تفاصيل الطلب تؤكد canDecide = true ليوسف رسمي'
);

select is(
  (select (public.get_mobile_request_detail(
    (select id from public.requests where employee_id = 'f6650000-0000-4000-8000-000000000022' order by created_at desc limit 1)
  )->>'awaitingMe')::boolean),
  true,
  'تفاصيل الطلب تؤكد awaitingMe = true ليوسف رسمي'
);

select * from finish();
rollback;
