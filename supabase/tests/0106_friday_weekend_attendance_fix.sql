-- =====================================================================
-- 0106: إصلاح غياب يوم الجمعة — دوال الحضور اليومي تحترم يوم الراحة
--   1. get_attendance_dashboard ترجع isWeekend=true و absent=0 يوم الجمعة
--   2. get_attendance_today_overview تتحقق من الجمعة (isWeekend في النتيجة)
--   3. get_executive_attendance_overview تحتوي على فحص isodow=5 → 'weekend'
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(6);

-- 1. get_attendance_dashboard ترجع isWeekend=true يوم الجمعة
select results_eq(
  $$ select (public.get_attendance_dashboard('2026-08-07'))->>'isWeekend' $$,
  $$ values ('true') $$,
  '1. get_attendance_dashboard: isWeekend=true يوم الجمعة (2026-08-07)'
);

-- 2. get_attendance_dashboard ترجع absent=0 يوم الجمعة
select results_eq(
  $$ select (public.get_attendance_dashboard('2026-08-07'))->>'absent' $$,
  $$ values ('0') $$,
  '2. get_attendance_dashboard: absent=0 يوم الجمعة'
);

-- 3. get_attendance_dashboard ترجع isWeekend=false يوم سبت
select results_eq(
  $$ select (public.get_attendance_dashboard('2026-08-08'))->>'isWeekend' $$,
  $$ values ('false') $$,
  '3. get_attendance_dashboard: isWeekend=false يوم السبت (2026-08-08)'
);

-- 4. get_executive_attendance_overview تحتوي على فحص الجمعة
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_executive_attendance_overview'
       and prosrc like '%isodow%v_date%5%weekend%' $$,
  '4. get_executive_attendance_overview: تحتوي على فحص isodow=5 → weekend'
);

-- 5. get_attendance_today_overview تحتوي على فحص الجمعة
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_attendance_today_overview'
       and prosrc like '%isodow%p_date%5%' $$,
  '5. get_attendance_today_overview: تحتوي على فحص isodow=5'
);

-- 6. get_executive_attendance_today (موبايل) تحتوي على فحص الجمعة
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_executive_attendance_today'
       and prosrc like '%isodow%v_today%5%weekend%' $$,
  '6. get_executive_attendance_today (موبايل): تحتوي على فحص isodow=5 → weekend'
);

select * from finish();
rollback;
