-- 0101: Fix mobile RPC scoping
-- Problem: get_kpi_inbox returns [] on mobile because RLS + security invoker
-- blocks non-admin users. get_executive_attendance_today blocks managers
-- who aren't top-level executives.

-- 1. get_kpi_inbox: switch to security definer with explicit role-based scoping
create or replace function public.get_kpi_inbox(p_limit integer default 100)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid;
  v_is_full boolean;
  v_limit int := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  v_me := public.current_employee_id();
  v_is_full := public.current_is_full_access();

  return coalesce((
    select jsonb_agg(item order by item->>'updatedAt' desc)
    from (
      select jsonb_build_object(
        'id', k.id,
        'employeeId', k.employee_id,
        'employeeName', e.full_name_ar,
        'employeeCode', e.employee_code,
        'cycleId', k.cycle_id,
        'periodMonth', c.period_month,
        'currentStage', k.current_stage,
        'workflowStatus', k.workflow_status,
        'cycleStatus', c.status,
        'deadlineAt', public.kpi_effective_deadline(c),
        'finalScore', k.final_score,
        'finalRating', k.final_rating,
        'locked', k.locked or c.status <> 'open',
        'updatedAt', coalesce(k.updated_at, k.created_at)
      ) item
      from public.kpi_evaluations k
      join public.employees e on e.id = k.employee_id
      join public.kpi_cycles c on c.id = k.cycle_id
      where
        -- Full access: see everything
        v_is_full
        -- Has performance.kpi.read with organization scope: see everything
        or exists (
          select 1
          from public.user_roles ur
          join public.role_permissions rp on rp.role_id = ur.role_id
          join public.permissions p on p.id = rp.permission_id
          where ur.user_id = auth.uid()
            and p.code in ('performance.kpi.read', 'performance.kpi.manager_assess', 'performance.kpi.hr_review')
            and rp.scope = 'organization'
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
        -- Has performance.kpi.read with direct_reports scope: see direct reports
        or (
          exists (
            select 1
            from public.user_roles ur
            join public.role_permissions rp on rp.role_id = ur.role_id
            join public.permissions p on p.id = rp.permission_id
            where ur.user_id = auth.uid()
              and p.code in ('performance.kpi.read', 'performance.kpi.manager_assess')
              and rp.scope = 'direct_reports'
              and ur.effective_from <= now()
              and (ur.effective_to is null or ur.effective_to > now())
          )
          and exists (
            select 1 from public.manager_relations mr
            where mr.manager_employee_id = v_me
              and mr.employee_id = k.employee_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
          )
        )
        -- Has performance.kpi.read with management_descendants scope: see subtree
        or (
          exists (
            select 1
            from public.user_roles ur
            join public.role_permissions rp on rp.role_id = ur.role_id
            join public.permissions p on p.id = rp.permission_id
            where ur.user_id = auth.uid()
              and p.code in ('performance.kpi.read', 'performance.kpi.manager_assess')
              and rp.scope = 'management_descendants'
              and ur.effective_from <= now()
              and (ur.effective_to is null or ur.effective_to > now())
          )
          and public.is_management_descendant(v_me, k.employee_id)
        )
        -- Has performance.kpi.read with department scope: see same department
        or (
          exists (
            select 1
            from public.user_roles ur
            join public.role_permissions rp on rp.role_id = ur.role_id
            join public.permissions p on p.id = rp.permission_id
            where ur.user_id = auth.uid()
              and p.code in ('performance.kpi.read', 'performance.kpi.manager_assess')
              and rp.scope = 'department'
              and ur.effective_from <= now()
              and (ur.effective_to is null or ur.effective_to > now())
          )
          and e.department_id = (select e2.department_id from public.employees e2 where e2.id = v_me)
        )
        -- Self: see own KPIs only
        or k.employee_id = v_me
      order by coalesce(k.updated_at, k.created_at) desc
      limit v_limit
    ) q
  ), '[]'::jsonb);
end;
$$;

-- 2. get_executive_attendance_today: expand gate to allow managers with attendance permissions
create or replace function public.get_executive_attendance_today()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := current_date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
begin
  select exists(
    select 1 from public.employees
    where id = v_me and manager_id is null and status = 'active'
  ) into v_is_executive;

  select public.current_is_full_access()
    or public.has_any_permission(array[
      'attendance.record.read',
      'attendance.history.manage',
      'attendance.roster.manage'
    ])
    or public.has_any_permission(array[
      'people.employee.read'
    ])
  into v_has_attendance_access;

  if not (v_is_executive or v_has_attendance_access) then
    raise exception 'executive or attendance access required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',               e.id,
      'name',             e.full_name_ar,
      'employeeCode',     e.employee_code,
      'jobTitle',         jt.name,
      'department',       d.name,
      'attendanceStatus', coalesce(ad.status, 'absent'),
      'firstCheckIn',     ad.first_check_in,
      'lastCheckOut',     ad.last_check_out,
      'lateMinutes',      coalesce(ad.late_minutes, 0),
      'isOnMission',      (mission.id is not null),
      'lastLatitude',     last_loc.latitude,
      'lastLongitude',    last_loc.longitude,
      'lastRecordedAt',   last_loc.recorded_at
    ) order by
      case
        when mission.id is not null                     then 1
        when coalesce(ad.status, 'absent') = 'present' then 2
        when coalesce(ad.status, 'absent') = 'late'    then 3
        when coalesce(ad.status, 'absent') = 'partial' then 4
        when coalesce(ad.status, 'absent') = 'on_leave' then 5
        when coalesce(ad.status, 'absent') = 'holiday' then 6
        when coalesce(ad.status, 'absent') = 'weekend' then 7
        when coalesce(ad.status, 'absent') = 'absent'  then 8
        else 9
      end,
      e.full_name_ar
    )
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d   on d.id  = e.department_id
    left join public.attendance_daily ad
           on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select wa.id
      from public.work_assignment_participants wap
      join public.work_assignments wa on wa.id = wap.assignment_id
      where wap.employee_id = e.id
        and wa.status in ('APPROVED', 'IN_PROGRESS')
        and wa.counts_as_work_day = true
        and wa.start_at::date <= v_today
        and wa.end_at::date   >= v_today
      limit 1
    ) mission on true
    left join lateral (
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      -- Non-full-access users can only see employees they can access
      and (
        public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
  ), '[]'::jsonb);
end;
$$;

-- 3. get_manager_dashboard: add KPI fallback for managers without performance.kpi.manager_assess
create or replace function public.get_manager_dashboard()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid;
  v_pending_kpi bigint;
begin
  v_me := public.current_employee_id();

  -- Try manager_assess first (specific permission)
  select count(*) into v_pending_kpi
  from public.kpi_evaluations k
  where k.current_stage = 'manager'
    and public.can_access_employee(k.employee_id, 'performance.kpi.manager_assess');

  -- Fallback: if 0 and user has no manager_assess permission, check broader read permission
  if v_pending_kpi = 0 and not public.has_any_permission(array['performance.kpi.manager_assess']) then
    select count(*) into v_pending_kpi
    from public.kpi_evaluations k
    where k.current_stage = 'manager'
      and (
        k.employee_id = v_me
        or public.can_access_employee(k.employee_id, 'performance.kpi.read')
        or public.can_access_employee(k.employee_id, 'people.employee.read')
      );
  end if;

  return jsonb_build_object(
    'teamMembers', (select count(*) from public.employees e
      where e.id <> v_me
        and public.can_access_employee(e.id, 'people.employee.read')),
    'pendingRequests', (select count(*) from public.requests r
      where r.status = 'pending'
        and public.can_access_employee(r.employee_id, 'requests.request.approve')),
    'pendingKpi', v_pending_kpi,
    'lateToday', (select count(*) from public.attendance_daily d
      where d.work_date = (now() at time zone 'Africa/Cairo')::date
        and (d.status = 'late' or d.late_minutes > 0)
        and public.can_access_employee(d.employee_id, 'attendance.record.read')),
    'lastUpdatedAt', now()
  );
end;
$$;

-- Ensure grants
revoke execute on function public.get_kpi_inbox(integer) from public;
grant  execute on function public.get_kpi_inbox(integer) to authenticated;

revoke execute on function public.get_manager_dashboard() from public;
grant  execute on function public.get_manager_dashboard() to authenticated;
