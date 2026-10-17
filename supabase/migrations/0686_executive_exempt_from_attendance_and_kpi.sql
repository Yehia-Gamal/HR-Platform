-- Migration 0686: Executive Director permanent exemption from attendance punches and KPI evaluation
-- 1. get_mobile_executive_employee_summary:
--    - todayStatus: status = 'exempt', statusLabel = 'معفى من البصمة' for executive / exempt employees (NEVER 'absent' / 'غائب').
--    - latestKpi: null for executive (Executive Director is the supreme evaluator, not evaluated).
--    - recentAttendance: empty array for executive (no punches / attendance records).
-- 2. _employee_today_status:
--    - Immediately returns status = 'exempt', statusLabel = 'معفى من البصمة' if is_employee_executive or is_employee_attendance_exempt.
-- 3. get_mobile_executive_people:
--    - attendanceStatus = 'exempt' for executive / exempt employees.
--    - latestKpiScore = null for executive.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث _employee_today_status
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._employee_today_status(p_employee_id uuid, p_detailed boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_board record;
  v_req_status text;
  v_activity text;
  v_work integer;
  v_result jsonb;
begin
  -- استثناء الإدارة العليا والتنفيذية والمعفيين من البصمة بقرار الإدارة
  if public.is_employee_executive(p_employee_id)
     or public.is_employee_attendance_exempt(p_employee_id)
     or exists(select 1 from public.employees where id = p_employee_id and coalesce(is_attendance_exempt, false) = true) then
    return jsonb_build_object(
      'status', 'exempt',
      'statusLabel', 'معفى من البصمة',
      'activityTitle', null,
      'requestStatus', null,
      'lateMinutes', 0,
      'checkInAt', null,
      'checkOutAt', null,
      'workMinutes', 0,
      'dueTime', null
    );
  end if;

  select b.board_status, b.offsite, b.offsite_type, b.is_holiday, b.checked_in,
         b.late_minutes, b.first_check_in, b.last_check_out, b.due_time
    into v_board
  from public.attendance_day_board_scoped(v_today, p_employee_id) b
  limit 1;

  -- طلب نشاط/إجازة اليوم (المعتمد أولًا) — للوجهة ونوع الإجازة وحالة الاعتماد
  select r.status,
         coalesce(
           nullif(r.payload->>'location', ''),
           nullif(r.payload->>'destination', ''),
           nullif(r.title, ''),
           case when r.request_type = 'leave' then
             case coalesce(r.payload->>'leaveType', '')
               when 'annual' then 'إجازة اعتيادية'
               when 'casual' then 'إجازة عارضة'
               when 'sick' then 'إجازة مرضية'
               when 'weekly_rest_comp' then 'بدل راحة أسبوعية'
               else 'إجازة رسمية'
             end
           end)
    into v_req_status, v_activity
  from public.requests r
  where r.employee_id = p_employee_id
    and r.status in ('approved', 'pending')
    and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
    and v_today between
        coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                 (r.created_at at time zone 'Africa/Cairo')::date)
    and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                 public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'),
                 (r.created_at at time zone 'Africa/Cairo')::date)
  order by case when r.status = 'approved' then 1 else 2 end,
           case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 else 4 end,
           r.created_at desc
  limit 1;

  v_result := public._today_status_public(
    v_board.board_status,
    v_board.offsite,
    v_board.offsite_type,
    v_board.is_holiday,
    v_board.checked_in,
    v_board.last_check_out is not null,
    p_detailed
  );

  v_result := v_result || jsonb_build_object('activityTitle', case
    when v_result->>'status' in ('mission', 'convoy', 'fundraising') then v_activity
    when v_result->>'status' = 'on_leave' and p_detailed then v_activity
  end);

  if p_detailed then
    select ad.work_minutes into v_work
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id and ad.work_date = v_today;

    v_result := v_result || jsonb_build_object(
      'requestStatus', case
        when v_result->>'status' in ('mission', 'convoy', 'fundraising', 'on_leave') then v_req_status
      end,
      'lateMinutes', coalesce(v_board.late_minutes, 0),
      'checkInAt', v_board.first_check_in,
      'checkOutAt', v_board.last_check_out,
      'workMinutes', coalesce(v_work, 0),
      'dueTime', to_char(v_board.due_time, 'HH24:MI')
    );
  end if;

  return v_result;
end;
$function$;

revoke all on function public._employee_today_status(uuid, boolean) from public, anon, authenticated;
grant execute on function public._employee_today_status(uuid, boolean) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث get_mobile_executive_employee_summary
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_mobile_executive_employee_summary(
  p_employee_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_allowed boolean;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_is_exec boolean;
  v_is_exempt boolean;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول ملخص الموظفين مرفوض' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'people.employee.read')) then
    raise exception 'FORBIDDEN: لا تملك صلاحية رؤية ملف هذا الموظف' using errcode = '42501';
  end if;

  v_is_exec := public.is_employee_executive(p_employee_id);
  v_is_exempt := v_is_exec
                 or public.is_employee_attendance_exempt(p_employee_id)
                 or exists(select 1 from public.employees where id = p_employee_id and coalesce(is_attendance_exempt, false) = true);

  return (
    select jsonb_build_object(
      'id', e.id,
      'employeeCode', e.employee_code,
      'name', e.full_name_ar,
      'photoUrl', e.photo_url,
      'status', e.status,
      'jobTitle', jt.name,
      'position', p.name,
      'department', d.name,
      'team', tm.name,
      'branch', b.name,
      'workSite', ws.name,
      'managerName', manager.full_name_ar,
      'hireDate', e.hire_date,
      'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
      'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
      'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
      'latestKpi', case
        when v_is_exec then null
        else (
          select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
          from public.kpi_evaluations ke
          join public.kpi_cycles kc on kc.id = ke.cycle_id
          where ke.employee_id = e.id
          order by kc.period_month desc, ke.created_at desc
          limit 1
        )
      end,
      'todayStatus', case
        when v_is_exempt then
          jsonb_build_object(
            'status', 'exempt',
            'statusLabel', 'معفى من البصمة',
            'activityTitle', null,
            'checkInAt', null,
            'checkOutAt', null,
            'lateMinutes', 0,
            'workMinutes', 0
          )
        else (
          with req as (
            select
              r.request_type,
              coalesce(nullif(r.payload->>'location',''), nullif(r.payload->>'destination',''), nullif(r.title,'')) as activity_title
            from public.requests r
            where r.employee_id = e.id
              and r.status in ('approved', 'pending')
              and r.request_type in ('convoy', 'fundraising', 'mission', 'leave')
              and v_today between
                  coalesce((r.payload->>'startDate')::date, (r.payload->>'start_date')::date, r.created_at::date)
              and coalesce((r.payload->>'endDate')::date, (r.payload->>'end_date')::date, (r.payload->>'startDate')::date, r.created_at::date)
            order by case when r.status = 'approved' then 1 else 2 end,
                     case r.request_type when 'convoy' then 1 when 'fundraising' then 2 when 'mission' then 3 when 'leave' then 4 else 5 end,
                     r.created_at desc
            limit 1
          ),
          att as (
            select status, first_check_in, last_check_out, late_minutes, work_minutes
            from public.attendance_daily
            where employee_id = e.id and work_date = v_today
            limit 1
          ),
          ae as (
            select min(event_at) as event_at
            from public.attendance_events
            where employee_id = e.id and event_type = 'CHECK_IN'
              and (event_at at time zone 'Africa/Cairo')::date = v_today
              and status in ('accepted', 'adjusted')
          )
          select jsonb_build_object(
            'status', case
              when (select request_type from req) = 'convoy' then 'convoy'
              when (select request_type from req) = 'fundraising' then 'fundraising'
              when (select request_type from req) = 'mission' then 'mission'
              when (select request_type from req) = 'leave' then 'on_leave'
              when (select status from att) = 'on_leave' then 'on_leave'
              when (select status from att) in ('weekend','holiday') then (select status from att)
              when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
                case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'late' else 'present' end
              when (select status from att) = 'absent' then 'absent'
              when extract(dow from v_today) = 5 then 'weekend'
              when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'holiday'
              when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'absent'
              else 'not_recorded'
            end,
            'statusLabel', case
              when (select request_type from req) = 'convoy' then coalesce((select activity_title from req), 'في قافلة')
              when (select request_type from req) = 'fundraising' then coalesce((select activity_title from req), 'في فاندي')
              when (select request_type from req) = 'mission' then coalesce((select activity_title from req), 'في مأمورية')
              when (select request_type from req) = 'leave' then 'في إجازة'
              when (select status from att) = 'on_leave' then 'في إجازة'
              when (select status from att) = 'weekend' then 'إجازة أسبوعية'
              when (select status from att) = 'holiday' then 'عطلة رسمية'
              when coalesce((select first_check_in from att), (select event_at from ae)) is not null then
                case when coalesce((select late_minutes from att), 0) > 0 or (select status from att) = 'late' then 'متأخر' else 'حاضر' end
              when (select status from att) = 'absent' then 'غائب'
              when extract(dow from v_today) = 5 then 'إجازة أسبوعية'
              when exists (select 1 from public.public_holidays where holiday_date = v_today) then 'عطلة رسمية'
              when (now() at time zone 'Africa/Cairo')::time > '12:00:00'::time then 'غائب'
              else 'لم يسجل'
            end,
            'activityTitle', (select activity_title from req),
            'checkInAt', coalesce((select first_check_in from att), (select event_at from ae)),
            'checkOutAt', (select last_check_out from att),
            'lateMinutes', coalesce((select late_minutes from att), 0),
            'workMinutes', coalesce((select work_minutes from att), 0)
          )
        )
      end,
      'recentAttendance', case
        when v_is_exempt then '[]'::jsonb
        else coalesce((
          select jsonb_agg(jsonb_build_object(
            'workDate', a.work_date,
            'status', a.status,
            'lateMinutes', a.late_minutes,
            'workMinutes', a.work_minutes,
            'firstCheckIn', a.first_check_in,
            'lastCheckOut', a.last_check_out
          ) order by a.work_date desc)
          from (
            select * from public.attendance_daily
            where employee_id = e.id
            order by work_date desc
            limit 14
          ) a
        ), '[]'::jsonb)
      end,
      'lastUpdatedAt', coalesce(e.updated_at, e.created_at, now())
    )
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.positions p on p.id = e.position_id
    left join public.departments d on d.id = e.department_id
    left join public.teams tm on tm.id = e.team_id
    left join public.branches b on b.id = e.branch_id
    left join public.work_sites ws on ws.id = e.work_site_id
    left join public.manager_relations mr on mr.employee_id = e.id and mr.relation_type = 'primary'
    left join public.employees manager on manager.id = mr.manager_employee_id
    where e.id = p_employee_id
  );
end;
$$;

revoke all on function public.get_mobile_executive_employee_summary(uuid) from public;
grant execute on function public.get_mobile_executive_employee_summary(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث get_mobile_executive_people (إعفاء التنفيذي من البصمة والتقييم)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_mobile_executive_people(
  p_search text default null::text,
  p_limit integer default 80
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_allowed boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول الموظفين التنفيذي مرفوض' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id,
      'employeeCode', x.employee_code,
      'name', x.full_name_ar,
      'photoUrl', x.photo_url,
      'jobTitle', x.job_title,
      'department', x.department,
      'team', x.team,
      'attendanceStatus', x.attendance_status,
      'pendingRequests', x.pending_requests,
      'openTasks', x.open_tasks,
      'latestKpiScore', x.latest_kpi_score
    ) order by x.rank, x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        case
          when public.is_employee_executive(e.id) or public.is_employee_attendance_exempt(e.id) or coalesce(e.is_attendance_exempt, false) then 'exempt'
          else ad.status
        end as attendance_status,
        public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) as rank,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        case
          when public.is_employee_executive(e.id) then null
          else (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1)
        end as latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        )
        and public.can_access_employee(e.id, 'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name), e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 80), 120))
    ) x
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_mobile_executive_people(text, integer) from public, anon;
grant execute on function public.get_mobile_executive_people(text, integer) to authenticated, service_role;
