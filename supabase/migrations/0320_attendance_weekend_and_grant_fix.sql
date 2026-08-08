-- =============================================================================
-- 0320: إصلاح لوحة الحضور بعد 0294/0295 — إعادة isWeekend + سحب منح anon.
-- -----------------------------------------------------------------------------
-- (1) 0294 أنشأت get_attendance_day_roster بمنح authenticated فقط دون revoke
--     عن PUBLIC، فبقي anon قادراً على تنفيذها. نسحب المنحة (اختبار 0107).
-- (2) 0294/0295 أعادتا تعريف get_attendance_dashboard وأسقطتا مفتاح isWeekend
--     الذي أضافه 0279 (يوم الراحة = الجمعة). نعيد إضافته كعلامة فقط دون
--     تصفير العدّادات، لأن العدّادات يجب أن تبقى مطابقة لقوائم drill-down
--     (اتساق الرقم=القائمة) حتى في أيام العمل (اختبار 0106 + 0110).
-- =============================================================================

begin;

-- ---------------------------------------------------------------------
-- (1) سحب منحة تنفيذ get_attendance_day_roster من anon/PUBLIC.
-- ---------------------------------------------------------------------
revoke all on function
  public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer)
  from public, anon;

grant execute on function
  public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer)
  to authenticated;

-- ---------------------------------------------------------------------
-- (2) إعادة تعريف get_attendance_dashboard مع isWeekend.
--     نسخة 0295 (النطاق المرئي: موظفون نشطون) + مفتاح isWeekend
--     = (isodow=5) يوم الجمعة، دون تصفير العدّادات.
-- ---------------------------------------------------------------------
create or replace function public.get_attendance_dashboard(p_date date default null)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select id from public.employees where is_active = true and coalesce(is_deleted, false) = false
  ), daily as (
    select d.* from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.* from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
      join params p on p.work_date between lr.start_date and lr.end_date
  ), excused_absent as (
    select d.employee_id
      from daily d
      left join approved_leaves al on al.employee_id = d.employee_id
      left join visible_events e on e.employee_id = d.employee_id
     where d.status = 'absent'
     group by d.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
        or count(e.id) > 0
  ), location_requests_day as (
    select llr.employee_id, llr.status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join visible_employees ve on ve.id = llr.employee_id
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
  )
  select jsonb_build_object(
    'scheduled', (select count(*) from visible_employees),
    'present', (select count(*) from daily where status in ('present','late','partial')),
    'late', (select count(*) from daily where status = 'late' or late_minutes > 0),
    'absent', (select count(*) from daily where status = 'absent'),
    'unexcusedAbsent', (select count(*) from daily where status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'locationRequestsToday', (select count(distinct employee_id) from location_requests_day),
    'locationRespondedToday', (select count(distinct employee_id) from location_requests_day where responded),
    'incomplete', (select count(*) from daily where status in ('partial','pending')),
    'pendingReview', (select count(distinct e.employee_id) from visible_events e where e.requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'lastUpdatedAt', now()
  );
$function$;

revoke all on function public.get_attendance_dashboard(date) from public, anon;
grant execute on function public.get_attendance_dashboard(date) to authenticated;

comment on function public.get_attendance_dashboard(date) is
  'لوحة الحضور اليومية: عدّادات مطابقة لقوائم drill-down (النطاق المرئي) + isWeekend يوم الجمعة (0320).';

commit;
