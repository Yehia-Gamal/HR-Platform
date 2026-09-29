-- =====================================================================
-- 0575: رابط طلب عميق في get_universal_action_center
-- ---------------------------------------------------------------------
-- التحقق:
--   1) مصادر الدالة تحتوي '/hr/requests?request='
--   2) لا مojibake في prosrc
--   3) EXECUTE محجوب عن anon/public — محفوظ بعد الاستبدال الكانوني
--   4) authenticated يملك EXECUTE
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(4);

-- =====================================================================
-- 1) action_url يحمل الـ deep link
-- =====================================================================
select matches(
  (select prosrc from pg_proc where proname = 'get_universal_action_center'),
  '/hr/requests\?request=',
  '0575: action_url للطلب يفتح التفاصيل عبر ?request=');

-- =====================================================================
-- 2) لا mojibake
-- =====================================================================
select is(
  (select prosrc ~ '(Ø|Ù|ðŸ|â€)' from pg_proc where proname = 'get_universal_action_center'),
  false,
  '0575: لا فساد UTF-8 في مصادر الدالة');

-- =====================================================================
-- 3) anon بلا EXECUTE
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon', 'public.get_universal_action_center(integer)', 'EXECUTE'),
  false,
  '0575: anon لا يملك EXECUTE');

-- =====================================================================
-- 4) authenticated يملك EXECUTE
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('authenticated', 'public.get_universal_action_center(integer)', 'EXECUTE'),
  true,
  '0575: authenticated يملك EXECUTE');

select * from finish();
rollback;
