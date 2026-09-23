-- =====================================================================
-- 0543: دور anon لا يصل إلى الدوال ذات «الحارس المقلوب»
-- ---------------------------------------------------------------------
-- 11 دالة SECURITY DEFINER تحمل النمط:
--     if auth.uid() is not null and not ( ...فحوص الصلاحية... ) then raise ...
-- فعند غياب الجلسة لا يُرفع استثناء. وهذا مقصود: أربع منها مجدولة عبر pg_cron
-- وتعمل بلا auth.uid()، ولا يمكن التمييز داخل الدالة بين anon و service_role
-- لأن current_user داخل SECURITY DEFINER = مالك الدالة لا المستدعي.
--
-- ⇒ طبقة المنح هي الدفاع الفعّال. هذا الاختبار يثبّتها: أي migration مستقبلية
--   تمنح anon (كما فعلت 0536/0541 مع get_instant_penalties بعد أن سحبتها 0511،
--   فحوّلت فخاً كامناً إلى تسريب فعلي) ستُسقط الـ CI.
--
-- لا fixture — فحوص صلاحيات بحتة.
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(16);

-- =====================================================================
-- 1) anon بلا EXECUTE على الدوال الإحدى عشرة
-- =====================================================================
select is(pg_catalog.has_function_privilege('anon',
  'public.check_invite_rate_limit(uuid)', 'EXECUTE'), false,
  'anon محجوب: check_invite_rate_limit');

select is(pg_catalog.has_function_privilege('anon',
  'public.auto_notify_late_attendance()', 'EXECUTE'), false,
  'anon محجوب: auto_notify_late_attendance');

select is(pg_catalog.has_function_privilege('anon',
  'public.generate_weekly_executive_summary()', 'EXECUTE'), false,
  'anon محجوب: generate_weekly_executive_summary');

select is(pg_catalog.has_function_privilege('anon',
  'public.generate_instant_penalty(uuid,date,integer,text)', 'EXECUTE'), false,
  'anon محجوب: generate_instant_penalty');

select is(pg_catalog.has_function_privilege('anon',
  'public.auto_escalate_instant_penalties()', 'EXECUTE'), false,
  'anon محجوب: auto_escalate_instant_penalties');

select is(pg_catalog.has_function_privilege('anon',
  'public.auto_generate_instant_penalties()', 'EXECUTE'), false,
  'anon محجوب: auto_generate_instant_penalties');

select is(pg_catalog.has_function_privilege('anon',
  'public.trigger_check_instant_penalties_now()', 'EXECUTE'), false,
  'anon محجوب: trigger_check_instant_penalties_now');

select is(pg_catalog.has_function_privilege('anon',
  'public.confirm_instant_penalty_payment(uuid,text)', 'EXECUTE'), false,
  'anon محجوب: confirm_instant_penalty_payment (تحويل مالي)');

select is(pg_catalog.has_function_privilege('anon',
  'public.lift_instant_penalty_suspension(uuid,text)', 'EXECUTE'), false,
  'anon محجوب: lift_instant_penalty_suspension');

select is(pg_catalog.has_function_privilege('anon',
  'public.cancel_instant_penalty(uuid,text)', 'EXECUTE'), false,
  'anon محجوب: cancel_instant_penalty');

select is(pg_catalog.has_function_privilege('anon',
  'public.review_instant_penalty_excuse(uuid,text,text)', 'EXECUTE'), false,
  'anon محجوب: review_instant_penalty_excuse');

-- =====================================================================
-- 2) authenticated احتفظ بصلاحيته (سحب PUBLIC يجب ألا يقفل التطبيق)
-- =====================================================================
select is(pg_catalog.has_function_privilege('authenticated',
  'public.confirm_instant_penalty_payment(uuid,text)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ confirm_instant_penalty_payment');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.cancel_instant_penalty(uuid,text)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ cancel_instant_penalty');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.review_instant_penalty_excuse(uuid,text,text)', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ review_instant_penalty_excuse');

select is(pg_catalog.has_function_privilege('authenticated',
  'public.trigger_check_instant_penalties_now()', 'EXECUTE'), true,
  'authenticated ما زال ينفّذ trigger_check_instant_penalties_now');

-- =====================================================================
-- 3) لا دالة من المجموعة ممنوحة لـ anon (حارس شامل ضد أي إضافة لاحقة)
-- =====================================================================
select is(
  (select count(*)::int
     from unnest(array[
       'public.check_invite_rate_limit(uuid)',
       'public.auto_notify_late_attendance()',
       'public.generate_weekly_executive_summary()',
       'public.generate_instant_penalty(uuid,date,integer,text)',
       'public.auto_escalate_instant_penalties()',
       'public.auto_generate_instant_penalties()',
       'public.trigger_check_instant_penalties_now()',
       'public.confirm_instant_penalty_payment(uuid,text)',
       'public.lift_instant_penalty_suspension(uuid,text)',
       'public.cancel_instant_penalty(uuid,text)',
       'public.review_instant_penalty_excuse(uuid,text,text)',
       'public.get_instant_penalties(uuid,text,date,date,integer,integer)',
       'public.is_employee_attendance_exempt(uuid)',
       'public.is_employee_penalty_exempt(uuid)'
     ]) as f
    where pg_catalog.has_function_privilege('anon', f, 'EXECUTE')),
  0,
  'صفر دوال من المجموعة (14) ممنوحة لـ anon');

select * from finish();
rollback;
