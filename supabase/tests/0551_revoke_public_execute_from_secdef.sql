-- =====================================================================
-- 0551: إغلاق تسريب EXECUTE على دوال SECDEF من PUBLIC/anon
-- ---------------------------------------------------------------------
-- يثبت:
--   1) anon لا يملك EXECUTE على get_attendance_day_roster(date,uuid,uuid,uuid)
--   2) anon لا يملك EXECUTE على generate_executive_daily_digest
--   3) anon لا يملك EXECUTE على get_penalty_settings / get_penalty_disputes
--   4) PUBLIC لا يملك EXECUTE على أي دالّة SECDEF في public
--      عدا get_public_* و handle_new_user / activate_employee_after_first_login
--   5) authenticated لا يزال يملك EXECUTE على دوال RPC المقصودة
--   6) activate_employee_after_first_login لا يزال متاحاً لـ anon (تصميم)
-- كل شيء ضمن معاملة تُلغى (rollback).
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(14);

-- =====================================================================
-- 1) P0: anon لا ينفّذ get_attendance_day_roster(date,uuid,uuid,uuid)
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_attendance_day_roster(date,uuid,uuid,uuid)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_attendance_day_roster(date,uuid,uuid,uuid)');

-- =====================================================================
-- 2) anon لا ينفّذ generate_executive_daily_digest
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.generate_executive_daily_digest(date)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ generate_executive_daily_digest');

-- =====================================================================
-- 3) anon لا ينفّذ get_punctuality_champions
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_punctuality_champions(date)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_punctuality_champions');

-- =====================================================================
-- 4) anon لا ينفّذ get_penalty_settings
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_penalty_settings()', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_penalty_settings');

-- =====================================================================
-- 5) anon لا ينفّذ get_penalty_disputes
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_penalty_disputes(text)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_penalty_disputes');

-- =====================================================================
-- 6) anon لا ينفّذ get_employee_location_dossier
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_employee_location_dossier(uuid,integer,integer)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_employee_location_dossier');

-- =====================================================================
-- 7) anon لا ينفّذ get_admin_org_chart
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_admin_org_chart()', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ get_admin_org_chart');

-- =====================================================================
-- 8) anon لا ينفّذ withdraw_from_fellowship_fund
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.withdraw_from_fellowship_fund(numeric,text,text,uuid,text)', 'EXECUTE'),
  false,
  'P0: anon لا ينفّذ withdraw_from_fellowship_fund');

-- =====================================================================
-- 9) PUBLIC لا يملك EXECUTE على أي دالّة في public
--     عدا الاستثناءات المقصودة
-- =====================================================================
select is(
  (select count(*)
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname not in (
        'handle_new_user',
        'activate_employee_after_first_login',
        'get_public_release_policy'
      )
      and p.proname not like 'get\_public\_%'
      and p.prorettype <> 'trigger'::regtype
      and not exists (
        select 1 from pg_depend d
        join pg_extension e on d.refobjid = e.oid
       where d.objid = p.oid and d.deptype = 'e'
      )
      and has_function_privilege('public', p.oid, 'EXECUTE')),
  0,
  'P0: لا دالّة في public متاحة لـ PUBLIC عدا الاستثناءات');

-- =====================================================================
-- 10–12) authenticated لا يزال يملك EXECUTE على دوال RPC المقصودة
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('authenticated',
    'public.get_attendance_day_roster(date,uuid,uuid,uuid)', 'EXECUTE'),
  true,
  'authenticated ينفّذ get_attendance_day_roster(date,uuid,uuid,uuid)');

select is(
  pg_catalog.has_function_privilege('authenticated',
    'public.generate_executive_daily_digest(date)', 'EXECUTE'),
  true,
  'authenticated ينفّذ generate_executive_daily_digest');

select is(
  pg_catalog.has_function_privilege('authenticated',
    'public.get_penalty_settings()', 'EXECUTE'),
  true,
  'authenticated ينفّذ get_penalty_settings');

-- =====================================================================
-- 13) activate_employee_after_first_login لا يزال متاحاً لـ anon (تصميم)
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.activate_employee_after_first_login()', 'EXECUTE'),
  true,
  'anon ينفّذ activate_employee_after_first_login (مقصود)');

-- =====================================================================
-- 14) get_public_release_policy لا يزال متاحاً لـ anon (مصمَّم عاماً)
-- =====================================================================
select is(
  pg_catalog.has_function_privilege('anon',
    'public.get_public_release_policy(text,text,text,integer,text)', 'EXECUTE'),
  true,
  'anon ينفّذ get_public_release_policy (مصمَّم عاماً)');

select * from finish();
rollback;
