-- 0626_enhance_get_my_mobile_team.sql
-- Ensure team managers see accurate today status (mission, convoy, fundraising, leave, present, late, absent, not_recorded)
-- with destination activity title.

CREATE OR REPLACE FUNCTION public.get_my_mobile_team(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', case
      when req.request_type = 'convoy' then 'convoy'
      when req.request_type = 'fundraising' then 'fundraising'
      when req.request_type = 'mission' then 'mission'
      when req.request_type = 'leave' then 'on_leave'
      when ad.status = 'on_leave' then 'on_leave'
      when ad.status in ('weekend','holiday') then ad.status
      when coalesce(ad.first_check_in, ae.event_at) is not null then
        case when coalesce(ad.late_minutes, 0) > 0 or ad.status = 'late' then 'late' else 'present' end
      when ad.status = 'absent' then 'absent'
      else 'not_recorded'
    end,
    'statusLabel', case
      when req.request_type = 'convoy' then 'في قافلة'
      when req.request_type = 'fundraising' then 'في فاندي'
      when req.request_type = 'mission' then 'في مأمورية'
      when req.request_type = 'leave' then 'في إجازة'
      when ad.status = 'on_leave' then 'في إجازة'
      when ad.status = 'weekend' then 'إجازة أسبوعية'
      when ad.status = 'holiday' then 'عطلة رسمية'
      when coalesce(ad.first_check_in, ae.event_at) is not null then
        case when coalesce(ad.late_minutes, 0) > 0 or ad.status = 'late' then 'متأخر' else 'حاضر' end
      when ad.status = 'absent' then 'غائب'
      else 'لم يسجل بعد'
    end,
    'activityTitle', req.activity_title,
    'lateMinutes', coalesce(ad.late_minutes, 0),
    'firstCheckIn', coalesce(ad.first_check_in, ae.event_at),
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
      and child.is_active = true
      and child.is_deleted = false
      and (
        not public.is_employee_isolated(child.id)
        or public.can_view_isolated_employee(child.id)
      )
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join lateral (
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
             case r.request_type 
               when 'convoy' then 1
               when 'fundraising' then 2
               when 'mission' then 3
               when 'leave' then 4
               else 5 
             end,
             r.created_at desc
    limit 1
  ) req on true
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
  left join lateral (
    select min(event_at) as event_at
    from public.attendance_events
    where employee_id = e.id and event_type = 'CHECK_IN'
      and (event_at at time zone 'Africa/Cairo')::date = v_today
      and status in ('accepted', 'adjusted')
  ) ae on true;

  return v_result;
end;
$function$;

GRANT EXECUTE ON FUNCTION public.get_my_mobile_team(integer) TO authenticated;
NOTIFY pgrst, 'reload schema';
