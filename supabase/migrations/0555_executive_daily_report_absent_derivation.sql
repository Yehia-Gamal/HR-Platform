-- 0555: التقرير التنفيذي اليومي — اشتقاق «غياب» لمن بلا صف attendance_daily
-- ============================================================================
-- المشكلة (كانت):
--   get_v10_executive_daily_report (0111) كانت تعدّ الغياب عبر
--   `count(*) filter (where status='absent')` على صفوف attendance_daily فقط.
--   من لم يُسجّل حضوره أصلاً (no-show) لا صف له → status NULL → لا يدخل
--   «غياب» ولا يخرج من «لم يسجلوا بعد». لذلك كان غياب=0 و«لم يسجلوا»=كل
--   المتعثرين حتى بعد انتهاء اليوم.
--
-- الحل (نفس نمط 0355 لـ get_attendance_dashboard):
--   اشتقاق effective_status لكل موظف نشط مطلوب حضوره:
--     بصمة/صف present|late|partial  → present
--     صريح absent                   → absent
--     رستر rest/holiday/cancelled   → not_required
--     إجازة معتمدة                  → on_leave
--     مأمورية/قافلة/فاندي           → (نوع التكليف)
--     عطلة رسمية                    → holiday
--     الجمعة                        → weekend
--     تاريخ سابق بلا بصمة          → absent   ← الجديد
--     اليوم بعد 10:15 (سماح 15)     → absent   ← الجديد
--     غير ذلك (قبل السماح/يوم مستقبلي) → not_yet
--
-- المخرجات (attendance.absent / attendance.notYet) تحتفظ بنفس المفاتيح —
-- لا تغيير في مخطط Zod أو الواجهة.
-- ============================================================================

begin;

create or replace function public.get_v10_executive_daily_report(p_date date default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  v_date     date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_today    date := (now() at time zone 'Africa/Cairo')::date;
  v_now_time time := (now() at time zone 'Africa/Cairo')::time;
  v_result   jsonb;
begin
  if not (
    public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive','executive-director'])
    or public.has_any_permission(array['reports.executive.read','reports.attendance.read','performance.kpi.report.read'])
  ) then raise exception 'EXECUTIVE_REPORT_FORBIDDEN' using errcode='42501'; end if;

  with active_people as (
    select e.id
    from public.employees e
    where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
      and not exists(
        select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
        where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
          and (ur.effective_from is null or ur.effective_from<=now())
          and (ur.effective_to is null or ur.effective_to>now())
      )
  ), facts as (
    select p.id, d.status, d.first_check_in, d.last_check_out, d.late_minutes,
      not exists(
        select 1 from public.roster_days rd
        where rd.employee_id=p.id and rd.work_date=v_date
          and rd.day_status in ('rest','holiday','cancelled')
      ) scheduled,
      exists(
        select 1 from public.leave_requests lr
        join public.requests rq on rq.id=lr.request_id
        where lr.employee_id=p.id and rq.status='approved'
          and v_date between lr.start_date and lr.end_date
      ) on_leave,
      (
        select wa.assignment_type
        from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id=wp.assignment_id
        where wp.employee_id=p.id
          and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between (wa.start_at at time zone 'Africa/Cairo')::date
                         and (wa.end_at   at time zone 'Africa/Cairo')::date
        order by wa.start_at desc limit 1
      ) assignment_type
    from active_people p
    left join public.attendance_daily d on d.employee_id=p.id and d.work_date=v_date
  ), derived as (
    select f.*,
      case
        when f.first_check_in is not null
             or f.status in ('present','late','partial')        then 'present'
        when f.status = 'absent'                                then 'absent'
        when not f.scheduled                                    then 'not_required'
        when f.on_leave                                         then 'on_leave'
        when f.assignment_type is not null                      then lower(f.assignment_type)
        when public.is_official_holiday(v_date, f.id)           then 'holiday'
        when extract(isodow from v_date) = 5                    then 'weekend'
        when v_date < v_today                                   then 'absent'
        when v_date = v_today and v_now_time >= time '10:15:00' then 'absent'
        else 'not_yet'
      end as effective_status
    from facts f
  ), attendance_summary as (
    select count(*) total_active,
      count(*) filter(
        where scheduled and not on_leave and assignment_type is null
          and effective_status not in ('holiday','weekend','not_required')
      ) required_today,
      count(*) filter(where effective_status = 'present') present,
      count(*) filter(where status='late' or coalesce(late_minutes,0)>0) late,
      count(*) filter(where effective_status = 'absent') absent,
      count(*) filter(where effective_status = 'not_yet') not_yet,
      count(*) filter(where last_check_out is not null) checked_out,
      count(*) filter(
        where scheduled and first_check_in is not null and last_check_out is null
      ) missing_checkout,
      count(*) filter(where on_leave) approved_leave,
      count(*) filter(where assignment_type='MISSION') missions,
      count(*) filter(where assignment_type='CONVOY') convoys,
      count(*) filter(where assignment_type='FUNDRAISING') fundraising
    from derived
  ), kpi_summary as (
    select
      count(*) filter(where e.current_stage='self') at_employee,
      count(*) filter(where e.current_stage in ('manager_review','manager_final')) at_manager,
      count(*) filter(where e.current_stage='hr_review') at_hr,
      count(*) filter(where e.current_stage in ('finalized','closed','archived')) ready,
      count(*) filter(where e.workflow_status='OVERDUE') overdue
    from public.kpi_evaluations e
    join public.kpi_cycles c on c.id=e.cycle_id
    where c.period_month = date_trunc('month', v_date)::date
  )
  select jsonb_build_object(
    'date', v_date,
    'employees', jsonb_build_object('active', a.total_active, 'requiredToday', a.required_today),
    'attendance', jsonb_build_object(
      'present', a.present, 'late', a.late, 'absent', a.absent,
      'notYet', a.not_yet, 'checkedOut', a.checked_out, 'missingCheckout', a.missing_checkout
    ),
    'workStatus', jsonb_build_object(
      'approvedLeave', a.approved_leave, 'missions', a.missions,
      'convoys', a.convoys, 'fundraising', a.fundraising
    ),
    'requests', jsonb_build_object(
      'pendingLeave', (select count(*) from public.requests where request_type='leave' and status='pending'),
      'pendingMission', (select count(*) from public.requests where request_type in ('mission','convoy') and status='pending')
    ),
    'kpi', jsonb_build_object(
      'atEmployee', k.at_employee, 'atManager', k.at_manager, 'atHr', k.at_hr,
      'ready', k.ready, 'overdue', k.overdue
    ),
    'cases', jsonb_build_object(
      'new', (select count(*) from public.dispute_cases where status in ('submitted','needs_more_information')),
      'open', (select count(*) from public.dispute_cases where status not in ('closed','rejected','cancelled_by_employee'))
    ),
    'followUp', jsonb_build_object(
      'decisions', (select count(*) from public.administrative_decisions where status in ('draft','in_review','approved')),
      'missingReports', (select count(*) from public.work_assignments where status='REPORT_PENDING'),
      'activeLocationRequests', (select count(*) from public.live_location_requests where status in ('pending','accepted','active') and (expires_at is null or expires_at>now())),
      'unansweredLocationRequests', (select count(*) from public.live_location_requests where status='pending' and (expires_at is null or expires_at>now()))
    ),
    'sources', jsonb_build_object(
      'employees', 'employees + user_roles',
      'attendance', 'attendance_daily + roster_days + derived (0555)',
      'workStatus', 'leave_requests + work_assignments',
      'requests', 'requests',
      'kpi', 'kpi_evaluations + kpi_cycles',
      'cases', 'dispute_cases',
      'followUp', 'administrative_decisions + work_assignments + live_location_requests'
    ),
    'generatedAt', now()
  ) into v_result from attendance_summary a cross join kpi_summary k;

  return v_result;
end $$;

revoke all on function public.get_v10_executive_daily_report(date) from public, anon;
grant execute on function public.get_v10_executive_daily_report(date) to authenticated;

notify pgrst, 'reload schema';

commit;
