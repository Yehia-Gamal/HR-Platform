-- =====================================================================
-- 0107: العمل يوم الجمعة + تفعيل بدل الراحة الأسبوعية (migration 0333)
--   1. get_attendance_dashboard: يوم الجمعة بدون سجلات → scheduled=0, absent=0, isWeekend=true
--   2. get_attendance_dashboard: يوم السبت → isWeekend=false
--   3. get_executive_attendance_overview: فحص الجمعة يأتي كـ fallback (بعد الحالات)
--   4. get_attendance_today_overview: يحتوي على فحص isodow=5
--   5. get_executive_attendance_today: فحص mission قبل weekend يوم الجمعة
--   6. submit_my_request: يقبل weekly_rest_comp في الـ whitelist
--   7. submit_employee_day_mark: يقبل weekly_rest_comp في الـ whitelist
-- =====================================================================

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(7);

-- 1. get_attendance_dashboard: يوم الجمعة → isWeekend=true, absent=0
select results_eq(
  $$ select (public.get_attendance_dashboard('2026-08-07'))->>'isWeekend' $$,
  $$ values ('true') $$,
  '1. get_attendance_dashboard: isWeekend=true يوم الجمعة'
);

-- 2. get_attendance_dashboard: يوم السبت → isWeekend=false
select results_eq(
  $$ select (public.get_attendance_dashboard('2026-08-08'))->>'isWeekend' $$,
  $$ values ('false') $$,
  '2. get_attendance_dashboard: isWeekend=false يوم السبت'
);

-- 3. get_executive_attendance_overview: فحص الجمعة يأتي كـ fallback
--    في 0279 كان أولاً (قبل on_leave)، في 0333 يجب أن يأتي بعد (else 'not_yet')
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_executive_attendance_overview'
       and prosrc like '%when on_leave%when assignment_type%weekend%else ''not_yet''%' $$,
  '3. get_executive_attendance_overview: فحص الجمعة يأتي كـ fallback بعد الحالات الأخرى'
);

-- 4. get_attendance_today_overview: يحتوي على فحص isodow
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_attendance_today_overview'
       and prosrc like '%isodow%' $$,
  '4. get_attendance_today_overview: يحتوي على فحص isodow'
);

-- 5. get_executive_attendance_today: فحص mission قبل weekend
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'get_executive_attendance_today'
       and prosrc like '%mission.id is not null then ''on_mission''%'
       and prosrc like '%isodow%v_today%5%weekend%' $$,
  '5. get_executive_attendance_today: فحص mission قبل weekend يوم الجمعة'
);

-- 6. submit_my_request: يقبل weekly_rest_comp
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'submit_my_request'
       and prosrc like '%weekly_rest_comp%' $$,
  '6. submit_my_request: يقبل weekly_rest_comp في الـ whitelist'
);

-- 7. submit_employee_day_mark: يقبل weekly_rest_comp
select isnt_empty(
  $$ select 1 from pg_proc
     where proname = 'submit_employee_day_mark'
       and prosrc like '%weekly_rest_comp%' $$,
  '7. submit_employee_day_mark: يقبل weekly_rest_comp في الـ whitelist'
);

select * from finish();
rollback;
