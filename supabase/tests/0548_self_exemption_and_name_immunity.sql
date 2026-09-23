-- =====================================================================
-- 0548: منع الإعفاء الذاتي + إزالة الحصانة بالاسم (migration 0548)
-- ---------------------------------------------------------------------
-- يثبت:
--   1) موظف عادي لا يستطيع ضبط is_penalty_exempt / is_attendance_exempt لنفسه
--      (كان ممكناً: سياسة employees_update تسمح بالصف الذاتي، والحارس 0004
--      قائمة حظر لا تعرف هذين العمودين)
--   2) ولا تعديل اسمه/هاتفه ذاتياً (كلاهما يدخل في مطابقة الإعفاء)
--   3) المطابقة بالاسم اختفت: «محمد يوسف» و«يحيى … جمال» العاديان غير معفيين،
--      ولمس سجلّ «يحيى … جمال» لا يمنحه الحصانة
--   4) المقصودون بالمعرّف ما زالوا معفيين (لا تغيير لأي شخص مقصود)
--   5) المسارات الموثوقة تعمل: full-access، والاتصال الداخلي بلا JWT (cron/migrations)
--   6) anon بلا EXECUTE (انحدار 0547)
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(18);

-- =====================================================================
-- Fixture
--   A  = مسؤول full-access
--   E  = موظف عادي (المهاجِم المحتمل)
--   Y  = موظف عادي اسمه «يحيى … جمال» (كان يُحصَّن بالاسم)
--   M  = موظف عادي اسمه «محمد يوسف» (كان يُعفى بالاسم)
--   ADM = صف بمعرّف الحساب الرئيسي (يجب أن يبقى معفياً)
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f5480000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f5480000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f5480000-0000-4000-8000-000000000003';
  v_a      uuid := 'f5480000-0000-4000-8000-000000000011';
  v_e      uuid := 'f5480000-0000-4000-8000-000000000012';
  v_y      uuid := 'f5480000-0000-4000-8000-000000000013';
  v_m      uuid := 'f5480000-0000-4000-8000-000000000014';
  v_adm    uuid := 'b452c987-ae08-4e12-8433-272cc66c85f9';
  v_user_a uuid := 'f5480000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f5480000-0000-4000-8000-000000000022';
  v_role   uuid;
begin
  insert into public.legal_entities(id, code, name) values (v_le, 'LE-0548', 'كيان 0548');
  insert into public.departments(id, legal_entity_id, code, name) values (v_dept, v_le, 'D-0548', 'إدارة 0548');
  insert into public.job_titles(id, code, name) values (v_jt, 'JT-0548', 'وظيفة 0548');

  insert into auth.users(id, email, aud, role) values
    (v_user_a, 'admin-0548@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0548@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
  values
    (v_a,   v_user_a, 'E-0548-A',   'مسؤول 0548',          v_dept, v_jt, 'active', true, current_date - 500, '+201000005480'),
    (v_e,   v_user_e, 'E-0548-E',   'موظف 0548',           v_dept, v_jt, 'active', true, current_date - 300, '+201000005481'),
    (v_y,   null,     'E-0548-Y',   'يحيى أحمد جمال 0548', v_dept, v_jt, 'active', true, current_date - 200, '+201000005482'),
    (v_m,   null,     'E-0548-M',   'محمد يوسف 0548',      v_dept, v_jt, 'active', true, current_date - 100, '+201000005483'),
    (v_adm, null,     'E-0548-ADM', 'حساب رئيسي 0548',     v_dept, v_jt, 'active', true, current_date - 900, '+201000005484');

  insert into public.profiles(id, employee_id, status) values
    (v_user_a, v_a, 'active'),
    (v_user_e, v_e, 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0548', 'أدمن 0548', 'Admin 0548', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0548';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role) on conflict do nothing;
end $fixture$;

-- =====================================================================
-- 1) البنية
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon',
  'public.is_employee_attendance_exempt(uuid)', 'EXECUTE'), false,
  'anon محجوب: is_employee_attendance_exempt (انحدار 0547)');

select is(pg_catalog.has_function_privilege('anon',
  'public.is_employee_penalty_exempt(uuid)', 'EXECUTE'), false,
  'anon محجوب: is_employee_penalty_exempt (انحدار 0547)');

select ok(exists(
  select 1 from pg_trigger
   where tgrelid = 'public.employees'::regclass
     and tgname = 'trg_employees_zz_protect_exemption_identity'
     and not tgisinternal),
  'حارس الإعفاء والهوية مركّب على employees');

select ok(
  (select string_agg(prosrc, ' ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('is_employee_attendance_exempt','is_employee_penalty_exempt','tg_admin_immunity_employees_fn'))
  !~* '\milike\M',
  'لا مطابقة بالاسم (ilike) في دوال الإعفاء والحصانة');

-- =====================================================================
-- 2) المطابقة بالاسم اختفت — والمقصودون بالمعرّف باقون
-- =====================================================================
select is(public.is_employee_attendance_exempt('f5480000-0000-4000-8000-000000000014'), false,
  'موظف عادي اسمه «محمد يوسف» لم يعد معفياً من الحضور');

select is(public.is_employee_attendance_exempt('f5480000-0000-4000-8000-000000000013'), false,
  'موظف عادي اسمه «يحيى … جمال» لم يعد معفياً من الحضور');

select is(public.is_employee_penalty_exempt('f5480000-0000-4000-8000-000000000013'), false,
  'موظف عادي اسمه «يحيى … جمال» لم يعد معفياً من الغرامات');

select is(public.is_employee_attendance_exempt('b452c987-ae08-4e12-8433-272cc66c85f9'), true,
  'الحساب الرئيسي (بالمعرّف) ما زال معفياً من الحضور');

select is(public.is_employee_penalty_exempt('b452c987-ae08-4e12-8433-272cc66c85f9'), true,
  'الحساب الرئيسي (بالمعرّف) ما زال معفياً من الغرامات');

-- لمس سجلّ «يحيى … جمال» لا يُعيد كتابته إلى محصّن (كان trigger الحصانة يفعل).
-- updated_at عمود محايد: ليس في قائمة حظر 0004 (hire_date فيها وكان سيُرفض
-- هنا لأن السياق بلا JWT فلا full-access) ولا في حارس 0548.
update public.employees set updated_at = now()
 where id = 'f5480000-0000-4000-8000-000000000013';

select is(
  (select is_penalty_exempt from public.employees where id = 'f5480000-0000-4000-8000-000000000013'),
  false,
  'تحديث سجلّ «يحيى … جمال» لا يمنحه الحصانة تلقائياً');

-- =====================================================================
-- 3) P0: الموظف العادي لا يُعفي نفسه ولا يعدّل هويته
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5480000-0000-4000-8000-000000000022","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5480000-0000-4000-8000-000000000022', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select throws_ok(
  $rt$ update public.employees set is_penalty_exempt = true
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  '42501',
  'P0: الموظف لا يضبط is_penalty_exempt لنفسه');

select throws_ok(
  $rt$ update public.employees set is_attendance_exempt = true
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  '42501',
  'P0: الموظف لا يضبط is_attendance_exempt لنفسه');

select throws_ok(
  $rt$ update public.employees set full_name_ar = 'يحيى جمال'
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  '42501',
  'الموظف لا يعيد تسمية نفسه (كانت إعادة التسمية تمنح الحصانة)');

select throws_ok(
  $rt$ update public.employees set phone_e164 = '+201000005489'
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  '42501',
  'الموظف لا يغيّر هاتفه ذاتياً');

select lives_ok(
  $rt$ update public.employees set full_name_ar = full_name_ar
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  'تحديث بلا تغيير في الأعمدة المحمية يمرّ (الحارس لا يكسر المسارات العادية)');

reset role;

-- =====================================================================
-- 4) المسارات الموثوقة تعمل
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5480000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub',  'f5480000-0000-4000-8000-000000000021', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
end $$;
set local role authenticated;

select lives_ok(
  $rt$ update public.employees set is_penalty_exempt = true
        where id = 'f5480000-0000-4000-8000-000000000012' $rt$,
  'full-access يضبط الإعفاء لموظف');

reset role;

-- اتصال داخلي بلا JWT (pg_cron / migrations) — يجب ألا ينكسر
do $$ begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);
end $$;

select lives_ok(
  $rt$ update public.employees set is_attendance_exempt = true
        where id = 'f5480000-0000-4000-8000-000000000013' $rt$,
  'الاتصال الداخلي بلا JWT (cron/migrations) يضبط الإعفاء');

select is(
  (select is_attendance_exempt from public.employees where id = 'f5480000-0000-4000-8000-000000000013'),
  true,
  'التعديل الداخلي طُبِّق فعلاً');

select * from finish();
rollback;
