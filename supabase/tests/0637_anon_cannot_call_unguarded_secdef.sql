-- =====================================================================
-- 0637: دور anon لا يصل إلى الدوال SECURITY DEFINER بلا حارس جلسة
-- ---------------------------------------------------------------------
-- خمس دوال تأخذ أي معرّف موظف وتُرجع بياناته (القسم، الإعفاءات، الطلبات،
-- المهام، حالة اليوم، دقائق الدفع) دون أن تسأل عن auth.uid() أصلاً،
-- فكانت متاحة لأي زائر عبر POST /rest/v1/rpc/<name>.
--
-- هذا الاختبار يثبّت طبقة المنح بعد سحب anon:
--   • anon محجوب عن المجموعة كاملة
--   • authenticated / service_role احتفظا بما يحتاجه التطبيق والمهام المجدولة
--   • حارس شامل: أي migration مستقبلية تعيد منح anon تسقط الـ CI
--     (وهو ما فعلته 0536/0541 مع get_instant_penalties بعد سحبها في 0511)
--
-- لا fixture — فحوص صلاحيات بحتة.
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- المجموعة: الدوال الخمس بلا حارس + دالة الكتالوج + دالة الـ trigger
select is(pg_catalog.has_function_privilege('anon',
  'public.check_employee_penalty_exemption_v2(uuid,date)', 'EXECUTE'), false,
  'anon محجوب: check_employee_penalty_exemption_v2');

select is(pg_catalog.has_function_privilege('anon',
  'public.is_employee_exempt_from_instant_penalty(uuid,date)', 'EXECUTE'), false,
  'anon محجوب: is_employee_exempt_from_instant_penalty');

select is(pg_catalog.has_function_privilege('anon',
  'public.calculate_paired_work_minutes(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE'), false,
  'anon محجوب: calculate_paired_work_minutes');

select is(pg_catalog.has_function_privilege('anon',
  'public.is_employee_split_shift(uuid)', 'EXECUTE'), false,
  'anon محجوب: is_employee_split_shift');

select is(pg_catalog.has_function_privilege('anon',
  'public.match_flexible_shift(timestamp with time zone)', 'EXECUTE'), false,
  'anon محجوب: match_flexible_shift');

select is(pg_catalog.has_function_privilege('anon',
  'public.get_mobile_employees(text,uuid,text,integer,integer)', 'EXECUTE'), false,
  'anon محجوب: get_mobile_employees');

select is(pg_catalog.has_function_privilege('anon',
  'public.handle_new_user()', 'EXECUTE'), false,
  'anon محجوب: handle_new_user (trigger)');

-- authenticated احتفظ بصلاحيته (سحب PUBLIC يجب ألا يقفل التطبيق)
select is(pg_catalog.has_function_privilege('authenticated',
  'public.check_employee_penalty_exemption_v2(uuid,date)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ check_employee_penalty_exemption_v2');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.is_employee_exempt_from_instant_penalty(uuid,date)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ is_employee_exempt_from_instant_penalty');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.calculate_paired_work_minutes(uuid,timestamp with time zone,timestamp with time zone)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ calculate_paired_work_minutes');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.is_employee_split_shift(uuid)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ is_employee_split_shift');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.match_flexible_shift(timestamp with time zone)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ match_flexible_shift');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.get_mobile_employees(text,uuid,text,integer,integer)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ get_mobile_employees');

-- service_role: المهام المجدولة ودوال الاستدعاء الداخلي ما زالت تعمل
select is(
  (select count(*)::int
     from unnest(array[
       'public.check_employee_penalty_exemption_v2(uuid,date)',
       'public.is_employee_exempt_from_instant_penalty(uuid,date)',
       'public.calculate_paired_work_minutes(uuid,timestamp with time zone,timestamp with time zone)',
       'public.is_employee_split_shift(uuid)',
       'public.match_flexible_shift(timestamp with time zone)',
       'public.get_mobile_employees(text,uuid,text,integer,integer)'
     ]) as f
    where pg_catalog.has_function_privilege('service_role', f, 'EXECUTE')),
  6,
  'service_role ما زالت تنفّذ المجموعة الستّ كاملة');

-- حارس شامل ضد أي إعادة منح لاحقة لـ anon
select is(
  (select count(*)::int
     from unnest(array[
       'public.check_employee_penalty_exemption_v2(uuid,date)',
       'public.is_employee_exempt_from_instant_penalty(uuid,date)',
       'public.calculate_paired_work_minutes(uuid,timestamp with time zone,timestamp with time zone)',
       'public.is_employee_split_shift(uuid)',
       'public.match_flexible_shift(timestamp with time zone)',
       'public.get_mobile_employees(text,uuid,text,integer,integer)',
       'public.handle_new_user()'
     ]) as f
    where pg_catalog.has_function_privilege('anon', f, 'EXECUTE')),
  0,
  'صفر دوال من المجموعة (7) ممنوحة لـ anon');

-- تراجع: تسريب digest-champions الذي أغلقه 0540 يجب ألا يعود
select is(pg_catalog.has_function_privilege('anon',
  'public.get_punctuality_champions(date)', 'EXECUTE'), false,
  'anon محجوب: get_punctuality_champions (0540 — تراجع)');

select * from finish();
rollback;
