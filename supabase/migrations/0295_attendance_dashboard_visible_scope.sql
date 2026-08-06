-- =============================================================================
-- 0295: مطابقة عدّادات لوحة الحضور مع قوائم drill-down (اتساق العدد=القائمة).
-- =============================================================================
-- get_attendance_dashboard في 0294 عدّت الأحداث/الطلبات لكل الصفوف في الجداول،
-- بينما get_attendance_day_roster يعرض الموظفين النشطين فقط. عند وجود بيانات
-- لموظف غير نشط (attendance_daily / attendance_events / live_location_requests)
-- ينفصل الرقم في البطاقة عن عدد نتائج القائمة.
-- هذا الترحيل يقصر عدّادات اللوحة على الموظفين النشطين غير المحذوفين
-- (نفس مجموعة get_attendance_day_roster) لضمان: total(قائمة) = الرقم(البطاقة)
-- دائماً لنفس اليوم وبنفس الفئة.
-- =============================================================================

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
    -- عدد الموظفين المميزين النشطين — يطابق قائمة drill-down.
    'locationRequestsToday', (select count(distinct employee_id) from location_requests_day),
    'locationRespondedToday', (select count(distinct employee_id) from location_requests_day where responded),
    'incomplete', (select count(*) from daily where status in ('partial','pending')),
    'pendingReview', (select count(distinct e.employee_id) from visible_events e where e.requires_review = true),
    'lastUpdatedAt', now()
  );
$function$;
grant execute on function public.get_attendance_dashboard(date) to authenticated;
