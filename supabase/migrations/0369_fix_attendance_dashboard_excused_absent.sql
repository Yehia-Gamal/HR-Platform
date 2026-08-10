-- ============================================================================
-- 0369: إصلاح منطق excused_absent في get_attendance_dashboard
-- ============================================================================
-- المشكلة (0355):
--   CTE excused_absent يعمل LEFT JOIN مع approved_leaves للموظفين
--   الذين derived_status = 'absent'، لكن منطق derived يُصنِّف أي موظف
--   لديه approved_leave كـ 'on_leave' فوراً — مما يجعل شرط
--   count(al.employee_id) > 0 مستحيل الحدوث (دائماً 0).
--   النتيجة: unexcusedAbsent = absent دائماً، بلا استثناء.
--
-- الإصلاح:
--   حذف JOIN مع approved_leaves من excused_absent (لا فائدة منه).
--   الإبقاء فقط على شرط وجود attendance_event (count(e.id) > 0)
--   للاعتراف بحضور جزئي أو دخول بدون خروج كـ "مبرر".
-- ============================================================================

begin;

create or replace function public.get_attendance_dashboard(
  p_date          date default null,
  p_department_id uuid default null,
  p_branch_id     uuid default null,
  p_manager_id    uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (
         p_manager_id is null or exists (
           select 1
             from public.manager_relations mr
            where mr.employee_id = e.id
              and mr.manager_employee_id = p_manager_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
         )
       )
  ), daily as (
    select d.*
      from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
      join params p on p.work_date between lr.start_date and lr.end_date
      join visible_employees ve on ve.id = lr.employee_id
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
      join params prm on prm.work_date between wa.start_at::date and wa.end_at::date
     where wa.status in ('APPROVED','IN_PROGRESS')
  ), derived as (
    select
      ve.id as employee_id,
      d.id as daily_id,
      d.status as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      d.is_finalized,
      (al.employee_id is not null) as has_approved_leave,
      (am.employee_id is not null) as has_mission,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when am.employee_id is not null then 'on_mission'
        when public.is_official_holiday((select work_date from params), ve.id) then 'holiday'
        when extract(isodow from (select work_date from params)) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
  ), excused_absent as (
    -- موظف غائب لكن له event في هذا اليوم (بصمة جزئية) = مبرر
    select dv.employee_id
      from derived dv
      join visible_events e on e.employee_id = dv.employee_id
     where dv.derived_status = 'absent'
     group by dv.employee_id
    having count(e.id) > 0
  ), location_requests_day as (
    select llr.employee_id, llr.status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
      join visible_employees ve on ve.id = llr.employee_id
  )
  select jsonb_build_object(
    'scheduled',
      case when extract(isodow from (select work_date from params)) = 5
           then (select count(distinct employee_id) from daily)
           else (select count(*) from visible_employees)
      end,
    'present', (select count(*) from derived where derived_status in ('present','late','partial')),
    'late', (select count(*) from derived where derived_status = 'late' or late_minutes > 0),
    'absent', (select count(*) from derived where derived_status = 'absent'),
    'unexcusedAbsent', (select count(*) from derived where derived_status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'onLeave', (select count(*) from derived where derived_status = 'on_leave'),
    'onMission', (select count(*) from derived where derived_status = 'on_mission'),
    'missingCheckout', (select count(*) from derived where derived_status = 'missing_checkout'),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending','missing_checkout')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'lastUpdatedAt', now()
  );
$function$;

grant execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
