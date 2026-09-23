-- =====================================================================
-- 0542: إغلاق تسريب get_instant_penalties + إصلاح الترقيم (migration 0542)
-- ---------------------------------------------------------------------
-- يثبت:
--   1) anon بلا EXECUTE على get_instant_penalties ودالتي الإعفاء
--      (0536 ثم 0541 منحتاها لـ anon؛ إعادة المنح مستقبلاً تُسقط هذا الاختبار)
--   2) الحارس المقلوب `auth.uid() is not null and not (...)` اختفى — كان
--      يمرّر كل طلب بلا جلسة لأن التقييم يقصُر قبل فحوص الصلاحية
--   3) وقت التشغيل: دور بلا auth.uid() وليس من أدوار النظام يُرفض بـ 42501
--   4) الترقيم يعمل فعلاً: limit/offset كانا على استعلام تجميعي فلا أثر لهما
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(11);

-- =====================================================================
-- Fixture: مسؤول full-access + موظف + 3 غرامات في أيام مختلفة
-- =====================================================================
do $fixture$
declare
  v_le     uuid := 'f5420000-0000-4000-8000-000000000001';
  v_dept   uuid := 'f5420000-0000-4000-8000-000000000002';
  v_jt     uuid := 'f5420000-0000-4000-8000-000000000003';
  v_admin  uuid := 'f5420000-0000-4000-8000-000000000011';
  v_emp    uuid := 'f5420000-0000-4000-8000-000000000012';
  v_user_a uuid := 'f5420000-0000-4000-8000-000000000021';
  v_user_e uuid := 'f5420000-0000-4000-8000-000000000022';
  v_role   uuid;
begin
  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0542', 'كيان 0542');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0542', 'إدارة 0542');
  insert into public.job_titles(id, code, name)
    values (v_jt, 'JT-0542', 'وظيفة 0542');

  insert into auth.users(id, email, aud, role)
    values
    (v_user_a, 'admin-0542@test.local', 'authenticated', 'authenticated'),
    (v_user_e, 'emp-0542@test.local',   'authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, job_title_id, status, is_active, hire_date, phone_e164)
    values
    (v_admin, v_user_a, 'E-0542-A', 'مسؤول 0542', v_dept, v_jt, 'active', true, current_date - 500, '+201000000542'),
    (v_emp,   v_user_e, 'E-0542-B', 'موظف 0542',  v_dept, v_jt, 'active', true, current_date - 300, '+201000000543');

  insert into public.profiles(id, employee_id, status)
    values (v_user_a, v_admin, 'active'), (v_user_e, v_emp, 'active');

  insert into public.roles(id, slug, name_ar, name_en, is_full_access)
    values (gen_random_uuid(), 'admin-0542', 'أدمن 0542', 'Admin 0542', true)
    on conflict (slug) do nothing;
  select id into v_role from public.roles where slug = 'admin-0542';
  insert into public.user_roles(user_id, role_id) values (v_user_a, v_role)
    on conflict do nothing;

  -- 3 غرامات في 3 أيام (القيد الفريد: موظف/يوم)
  insert into public.instant_attendance_penalties(
    employee_id, work_date, late_minutes, original_amount, current_amount, status)
  values
    (v_emp, current_date - 1, 20, 20.00, 20.00, 'pending_payment'),
    (v_emp, current_date - 2, 40, 50.00, 50.00, 'pending_payment'),
    (v_emp, current_date - 3, 70, 150.00, 150.00, 'pending_payment');
end $fixture$;

-- =====================================================================
-- 1) P0: anon بلا EXECUTE
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_instant_penalties(uuid,text,date,date,integer,integer)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_instant_penalties');

select is(
  pg_catalog.has_function_privilege('anon',
    'public.is_employee_attendance_exempt(uuid)', 'EXECUTE'),
  false,
  'anon لا ينفّذ is_employee_attendance_exempt');

select is(
  pg_catalog.has_function_privilege('anon',
    'public.is_employee_penalty_exempt(uuid)', 'EXECUTE'),
  false,
  'anon لا ينفّذ is_employee_penalty_exempt');

select is(
  pg_catalog.has_function_privilege('authenticated',
    'public.get_instant_penalties(uuid,text,date,date,integer,integer)', 'EXECUTE'),
  true,
  'authenticated ما زال ينفّذ get_instant_penalties');

-- =====================================================================
-- 2) الحارس المقلوب اختفى
-- =====================================================================
select ok(
  (select prosrc from pg_proc
    where oid = 'public.get_instant_penalties(uuid,text,date,date,integer,integer)'::regprocedure)
    !~* 'auth\.uid\(\)\s+is\s+not\s+null\s+and\s+not',
  'P0: الحارس المقلوب (auth.uid() is not null and not ...) أُزيل');

select ok(
  (select prosrc from pg_proc
    where oid = 'public.get_instant_penalties(uuid,text,date,date,integer,integer)'::regprocedure)
    ~* 'auth\.uid\(\)\s+is\s+null',
  'الحارس يفحص غياب الجلسة صراحةً');

-- current_user داخل SECURITY DEFINER = مالك الدالة لا المستدعي، فأي حارس
-- مبني عليه لا يُطلق أبداً. يجب ألا يُستخدم هنا.
select ok(
  (select prosrc from pg_proc
    where oid = 'public.get_instant_penalties(uuid,text,date,date,integer,integer)'::regprocedure)
    !~* 'current_user\s+not\s+in',
  'لا حارس مبني على current_user (لا يُطلق داخل SECURITY DEFINER)');

-- search_path مثبّت (دالة SECURITY DEFINER)
select ok(
  (select proconfig::text like '%search_path%' from pg_proc
    where oid = 'public.get_instant_penalties(uuid,text,date,date,integer,integer)'::regprocedure),
  'get_instant_penalties: search_path مثبّت');

-- =====================================================================
-- 3) وقت التشغيل: طلب بلا جلسة من دور غير نظامي يُرفض
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;
set local role authenticated;

select throws_ok(
  $rt$ select public.get_instant_penalties(null, null, null, null, 200, 0) $rt$,
  '42501',
  'P0: استدعاء بلا auth.uid() من دور غير نظامي يُرفض (كان يمرّ ويُرجع كل الصفوف)');

reset role;

-- =====================================================================
-- 4) الترقيم يعمل فعلاً (كان limit/offset على استعلام تجميعي بلا أثر)
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"f5420000-0000-4000-8000-000000000021","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', 'f5420000-0000-4000-8000-000000000021', true);
end $$;

select is(
  jsonb_array_length(public.get_instant_penalties(
    'f5420000-0000-4000-8000-000000000012', null, null, null, 2, 0)),
  2,
  'الترقيم: p_limit=2 يُرجع صفين فقط (كان يُرجع كل الصفوف)');

select is(
  jsonb_array_length(public.get_instant_penalties(
    'f5420000-0000-4000-8000-000000000012', null, null, null, 200, 0)),
  3,
  'بلا تقييد: تُرجع الغرامات الثلاث');

select * from finish();
rollback;
