-- =====================================================================
-- 0664: اختبار فترات الدوام الإداري والإدارة المشتركة لمصطفى أحمد ويوسف رسمي
--   • مصطفى أحمد ويوسف رسمي: الورديات المتاحة هي الثلاث فترات الإدارية.
--   • طاقم العيادات التابع: الورديات المتاحة له ورديتان فقط (الصباحية 10 ص والمسائية 3 ع).
--   • يوسف رسمي يملك أدوار الإدارة clinics-manager و direct-manager و department-manager.
--   • مصطفى أحمد ويوسف رسمي يمكن لأي منهما اعتماد طلبات طاقم العيادات بنجاح.
--   • كلاهما مصرح له بطلب موقع أفراد طاقم العيادات دون تحويل.
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(12);

do $fixture$
declare
  v_le  uuid := 'f6640000-0000-4000-8000-000000000001';
  v_jt  uuid := 'f6640000-0000-4000-8000-000000000004';
  v_user_mostafa uuid := 'f6640000-0000-4000-8000-000000000010';
  v_user_youssef uuid := 'f6640000-0000-4000-8000-000000000011';
  v_user_clinic  uuid := 'f6640000-0000-4000-8000-000000000012';
  v_role_cm uuid;
  v_role_dm uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0664', 'كيان 0664') on conflict do nothing;
  insert into public.departments(id, legal_entity_id, code, name, is_isolated) values
    ('f6640000-0000-4000-8000-00000000000a', v_le, 'MED-ADMIN', 'إدارة العيادات 0664', true)
  on conflict do nothing;
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0664', 'تمريض') on conflict do nothing;

  insert into auth.users(id, email, aud, role) values
    (v_user_mostafa, 'mostafa-0664@test.local', 'authenticated', 'authenticated'),
    (v_user_youssef, 'youssef-0664@test.local', 'authenticated', 'authenticated'),
    (v_user_clinic,  'nurse-0664@test.local',   'authenticated', 'authenticated')
  on conflict (id) do nothing;

  -- مصطفى أحمد
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c', v_user_mostafa, 'E-0664-M', 'مصطفى أحمد كمال الدين', 'f6640000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000664001')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- يوسف رسمي
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, status, is_active, hire_date, phone_e164)
  values ('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6', v_user_youssef, 'E-0664-Y', 'يوسف رسمي شعبان', 'f6640000-0000-4000-8000-00000000000a', 'active', true, current_date - 900, '+201000664002')
  on conflict (id) do update set user_id = excluded.user_id, is_active = true, status = 'active';

  -- موظفة بالعيادات
  insert into public.employees(id, user_id, employee_code, full_name_ar, department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values ('f6640000-0000-4000-8000-000000000022', v_user_clinic, 'E-0664-N', 'ممرضة العيادات 0664', 'f6640000-0000-4000-8000-00000000000a', v_jt, 'active', true, current_date - 300, '+201000664003')
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

-- 1) فحص دالة is_clinic_team_member
select is(public.is_clinic_team_member('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'),
  false, 'مصطفى أحمد ليس فرداً محصوراً بالعيادات (هو مدير)');

select is(public.is_clinic_team_member('a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'),
  false, 'يوسف رسمي ليس فرداً محصوراً بالعيادات (هو مدير)');

select is(public.is_clinic_team_member('f6640000-0000-4000-8000-000000000022'),
  true, 'ممرضة العيادات تتبع طاقم العيادات');

-- 2) فحص فترات الوردية لمصطفى أحمد (3 فترات إدارية)
select pg_temp.act_as('f6640000-0000-4000-8000-000000000010');
set local role authenticated;

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  3,
  'مصطفى أحمد يرى الورديات الإدارية الثلاث (SHIFT_9_5, OFFICIAL, SHIFT_11_7)'
);

-- 3) فحص فترات الوردية ليوسف رسمي (3 فترات إدارية كباقي التيم الإداري)
select pg_temp.act_as('f6640000-0000-4000-8000-000000000011');

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  3,
  'يوسف رسمي يرى الورديات الإدارية الثلاث كالطاقم الإداري'
);

-- 4) فحص فترات الوردية لطاقم العيادات التابع (ورديتان فقط)
select pg_temp.act_as('f6640000-0000-4000-8000-000000000012');

select is(
  (select jsonb_array_length(public.get_my_work_shift_info()->'availableShifts')),
  2,
  'طاقم العيادات يرى ورديتي العيادات فقط (OFFICIAL, SHIFT_CLINIC_3_11)'
);

-- 5) تقديم طلب من طاقم العيادات واعتماده بواسطة يوسف رسمي
select lives_ok($$
  select public.submit_my_request('late_permit', 'إذن تأخير عيادات', 'ظرف طارئ',
    jsonb_build_object('permitDate', (now() at time zone 'Africa/Cairo')::date + 1, 'minutes', 45))
$$, 'ممرضة العيادات تقدم طلب إذن تأخير');

reset role;

do $test_approval$
declare
  v_req_id uuid;
begin
  select id into v_req_id
  from public.requests
  where employee_id = 'f6640000-0000-4000-8000-000000000022'
  order by created_at desc limit 1;

  -- التمثيل كـ يوسف رسمي لاعتماد الطلب
  perform pg_temp.act_as('f6640000-0000-4000-8000-000000000011');
  execute 'set local role authenticated';

  perform public.decide_request(v_req_id, 'approve', 'معتمد من يوسف رسمي');
end $test_approval$;

reset role;

select is(
  (select status from public.requests where employee_id = 'f6640000-0000-4000-8000-000000000022' order by created_at desc limit 1),
  'approved',
  'يوسف رسمي يعتمد طلب طاقم العيادات بنجاح'
);

-- 6) تقديم طلب آخر واعتماده بواسطة مصطفى أحمد
select pg_temp.act_as('f6640000-0000-4000-8000-000000000012');
set local role authenticated;

select lives_ok($$
  select public.submit_my_request('early_permit', 'إذن انصراف عيادات', 'موعد عائلي',
    jsonb_build_object('permitDate', (now() at time zone 'Africa/Cairo')::date + 1, 'minutes', 60))
$$, 'ممرضة العيادات تقدم طلب إذن انصراف');

reset role;

do $test_approval_mostafa$
declare
  v_req_id uuid;
begin
  select id into v_req_id
  from public.requests
  where employee_id = 'f6640000-0000-4000-8000-000000000022'
  order by created_at desc limit 1;

  -- التمثيل كـ مصطفى أحمد لاعتماد الطلب
  perform pg_temp.act_as('f6640000-0000-4000-8000-000000000010');
  execute 'set local role authenticated';

  perform public.decide_request(v_req_id, 'approve', 'معتمد من مصطفى أحمد');
end $test_approval_mostafa$;

reset role;

select is(
  (select status from public.requests where employee_id = 'f6640000-0000-4000-8000-000000000022' order by created_at desc limit 1),
  'approved',
  'مصطفى أحمد يعتمد طلب طاقم العيادات بنجاح'
);

-- 7) يوسف رسمي يطلب موقع ممرضة العيادات مباشرة
select pg_temp.act_as('f6640000-0000-4000-8000-000000000011');
set local role authenticated;

select lives_ok($$
  select public.request_live_location('f6640000-0000-4000-8000-000000000022', 'snapshot', 'متابعة ميدانية')
$$, 'يوسف رسمي يطلب موقع موظفة العيادات بنجاح وبشكل مباشر');

reset role;

select is(
  (select (metadata->>'isClinicDirectFromMgr')::boolean
   from public.live_location_requests
   where employee_id = 'f6640000-0000-4000-8000-000000000022'
   order by requested_at desc limit 1),
  true,
  'طلب الموقع صادر كطلب مباشر من المدير دون تحويل'
);

select * from finish();
rollback;
