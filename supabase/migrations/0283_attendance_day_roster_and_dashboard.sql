-- =============================================================================
-- 0283: إعادة تعريف دوال لوحة الحضور بعد إعادة ترقيم الترحيلات.
-- =============================================================================
-- خلفية: أثناء دمج الفروع فقدت الملفات 0270–0276 محتواها (أصبحت placeholders)
-- وتأخرت الدالتان التاليتان خلفاً محلياً رغم تطبيقهما على قاعدة الإنتاج.
-- هذا الترحيل يعيد تعريفهما مطابقاً لما على البعيدة (idempotent: create or replace)
-- حتى تعمل أي قاعدة بيانات جديدة محلياً أو في بيئة تجاوز كاملة مثل الإنتاج.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) لوحة الحضور الموسّعة: تضيف الغياب غير المبرر وعدّادات طلبات الموقع.
-- -----------------------------------------------------------------------------
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
    select d.* from public.attendance_daily d join params p on p.work_date = d.work_date
  ), visible_events as (
    select e.* from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
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
    select employee_id, status, requested_at, responded_at,
           (responded_at is not null or status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
  )
  select jsonb_build_object(
    'scheduled', (select count(*) from visible_employees),
    'present', (select count(*) from daily where status in ('present','late','partial')),
    'late', (select count(*) from daily where status = 'late' or late_minutes > 0),
    'absent', (select count(*) from daily where status = 'absent'),
    'unexcusedAbsent', (select count(*) from daily where status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from daily where status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'lastUpdatedAt', now()
  );
$function$;
grant execute on function public.get_attendance_dashboard(date) to authenticated;

-- -----------------------------------------------------------------------------
-- 2) قائمة الحضور التفصيلية لكل فئة من بطاقات اللوحة (drill-down).
--    أعمدة JSON تطابق attendanceRosterItemSchema في shared-contracts.
-- -----------------------------------------------------------------------------
create or replace function public.get_attendance_day_roster(p_date date default null, p_category text default 'scheduled')
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_result    jsonb;
begin
  if p_category not in (
    'scheduled','present','late','absent','unexcused_absent',
    'incomplete','pending_review','location_requests','location_responded'
  ) then
    raise exception 'invalid attendance roster category: %', p_category
      using errcode = '22023';
  end if;

  with visible_employees as (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url, d.name as department_name
      from public.employees e
      left join public.departments d on d.id = e.department_id
     where e.is_active = true and coalesce(e.is_deleted, false) = false
  ), daily as (
    select d.* from public.attendance_daily d where d.work_date = v_work_date
  ), events_day as (
    select e.* from public.attendance_events e
     where (e.event_at at time zone 'Africa/Cairo')::date = v_work_date
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
  ), excused_absent as (
    select d.employee_id
      from daily d
      left join approved_leaves al on al.employee_id = d.employee_id
      left join events_day e on e.employee_id = d.employee_id
     where d.status = 'absent'
     group by d.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
        or count(e.id) > 0
  ), location_requests_day as (
    select distinct on (llr.employee_id)
           llr.employee_id, llr.status as llr_status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
     where (llr.requested_at at time zone 'Africa/Cairo')::date = v_work_date
        or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = v_work_date)
     order by llr.employee_id, llr.requested_at desc
  ), base as (
    select
      ve.id            as employee_id,
      ve.employee_code,
      ve.full_name_ar,
      ve.photo_url,
      ve.department_name,
      d.status         as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce((select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id), false) as requires_review,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  )
  select coalesce(jsonb_agg(item order by item->>'employeeName'), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
        'employeeId', b.employee_id,
        'employeeCode', b.employee_code,
        'employeeName', b.full_name_ar,
        'departmentName', b.department_name,
        'photoUrl', b.photo_url,
        'status', b.daily_status,
        'firstCheckIn', b.first_check_in,
        'lastCheckOut', b.last_check_out,
        'lateMinutes', b.late_minutes,
        'requiresReview', b.requires_review,
        'locationRequestStatus', b.location_request_status,
        'locationRequestedAt', b.location_requested_at,
        'locationRespondedAt', b.location_responded_at
      ) as item
      from base b
      where case p_category
        when 'scheduled'          then true
        when 'present'            then b.daily_status in ('present','late','partial')
        when 'late'               then b.daily_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.daily_status = 'absent'
        when 'unexcused_absent'   then b.daily_status = 'absent'
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.daily_status in ('partial','pending')
        when 'pending_review'     then b.requires_review = true
        when 'location_requests'  then b.location_requested_at is not null
                                    or b.location_responded_at is not null
        when 'location_responded' then b.location_responded_today = true
        else false
      end
    ) items;

  return v_result;
end;
$function$;
grant execute on function public.get_attendance_day_roster(date, text) to authenticated;
