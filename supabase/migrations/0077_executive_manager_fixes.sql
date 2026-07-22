-- 0077: Executive Manager fixes

-- Fix get_executive_attendance_today to allow executive managers without full access
create or replace function public.get_executive_attendance_today()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_today date := current_date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
begin
  select exists(select 1 from public.employees where id = v_me and manager_id is null and status = 'active') into v_is_executive;

  if not (public.current_is_full_access() or v_is_executive) then
    raise exception 'executive or full access required' using errcode = '42501';
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
  ), '[]'::jsonb);
end;
$$;
revoke execute on function public.get_executive_attendance_today() from public;
grant  execute on function public.get_executive_attendance_today() to authenticated;
