-- pgTAP test for migration 0439: today's check-in/check-out times in attendance state
-- Validates:
--   ① get_my_attendance_state(text) returns todayCheckInAt / todayCheckOutAt fields
--   ② First CHECK_IN of the day (ascending) and last CHECK_OUT (descending) are selected

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(4);

-- ═══════════════════════════════════════════════════════════════════════════
-- ① get_my_attendance_state — new fields in function definition
-- ═══════════════════════════════════════════════════════════════════════════

select ok(
  position('todayCheckInAt' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0439: attendance state returns todayCheckInAt field');

select ok(
  position('todayCheckOutAt' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0439: attendance state returns todayCheckOutAt field');

-- ═══════════════════════════════════════════════════════════════════════════
-- ② Selection order — first CHECK_IN (asc), last CHECK_OUT (desc)
-- ═══════════════════════════════════════════════════════════════════════════

select ok(
  position('event_type=''CHECK_IN''' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0
  and position('order by event_at asc' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0439: todayCheckInAt picks the FIRST check-in of the day');

select ok(
  position('event_type=''CHECK_OUT''' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0
  and position('order by event_at desc' in pg_get_functiondef(
    'public.get_my_attendance_state(text)'::regprocedure)) > 0,
  '0439: todayCheckOutAt picks the LAST check-out of the day');

select * from finish();
rollback;