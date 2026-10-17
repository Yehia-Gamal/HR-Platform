-- ==============================================================================
-- Migration 0684: Order Executive Attendance Today by Hierarchy Rank & Clinic Isolation
-- ==============================================================================
-- 1) ترتيب الحضور اليومي للمدير التنفيذي حسب الهيكل الإداري المعتمد:
--    الرتبة 1: الشيخ محمد يوسف (المدير التنفيذي)
--    الرتبة 2: يحيى السبع (السكرتير التنفيذي)
--    الرتبة 3: أبو عمار (محمد عبدالباسط - مدير تشغيل / أوبريشن 1)
--    الرتبة 4: ياسر (ياسر فتحي نور الدين - مدير تشغيل / أوبريشن 2)
--    الرتبة 5: باقي المديرين (بما فيهم مديرا العيادات مصطفى أحمد ويوسف رسمي)
--    الرتبة 6: باقي الموظفين
--    الرتبة 7: تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
-- 2) تفعيل حماية عزل بنات الطاقم الطبي فلا يظهرن إلا للمصرح لهم.
-- ==============================================================================

begin;

create or replace function public.get_executive_attendance_today(
  p_status text default null::text,
  p_department_id uuid default null::uuid,
  p_search text default null::text
)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_is_executive boolean;
  v_has_attendance_access boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_status_match text := nullif(trim(coalesce(p_status, '')), '');
begin
  select public.current_has_active_role(array['executive-director', 'executive']) into v_is_executive;

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
    raise exception 'صلاحية تنفيذي أو حضور مطلوبة' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(x.item order by x.hierarchy_rank, x.name)
    from (
      select
        jsonb_build_object(
          'id',               e.id,
          'name',             e.full_name_ar,
          'employeeCode',     e.employee_code,
          'jobTitle',         jt.name,
          'department',       d.name,
          'departmentId',     d.id,
          'photoUrl',         e.photo_url,
          'attendanceStatus', s.app_status,
          'firstCheckIn',     b.first_check_in,
          'lastCheckOut',     b.last_check_out,
          'lateMinutes',      b.late_minutes,
          'isOnMission',      (b.board_status = 'assignment'),
          'lastLatitude',     last_loc.latitude,
          'lastLongitude',    last_loc.longitude,
          'lastRecordedAt',   last_loc.recorded_at
        ) as item,
        public.get_employee_hierarchy_rank(e.full_name_ar, jt.name, d.name) as hierarchy_rank,
        e.full_name_ar as name
      from public.attendance_day_board(v_today) b
      cross join lateral (
        select case b.board_status
          when 'late' then 'late'
          when 'present' then 'present'
          when 'checked_out' then 'present'
          when 'left_early' then 'present'
          when 'on_leave' then 'on_leave'
          when 'assignment' then 'on_mission'
          when 'weekend' then case when b.is_holiday then 'holiday' else 'weekend' end
          else 'absent'
        end as app_status
      ) s
      join public.employees e on e.id = b.employee_id
      left join public.job_titles  jt on jt.id = e.job_title_id
      left join public.departments d  on d.id  = e.department_id
      left join lateral (
        select l.latitude, l.longitude, l.recorded_at
        from public.employee_locations l
        where l.employee_id = e.id
        order by l.recorded_at desc limit 1
      ) last_loc on true
      where not b.is_exempt
        and (
          not public.is_employee_isolated(e.id)
          or public.can_view_isolated_employee(e.id)
        )
        and (p_department_id is null or e.department_id = p_department_id)
        and (v_search is null
          or e.full_name_ar ilike '%' || v_search || '%'
          or e.employee_code ilike '%' || v_search || '%')
        and (v_status_match is null or s.app_status = v_status_match)
        and (
          v_is_executive
          or public.current_is_full_access()
          or public.can_access_employee(e.id, 'attendance.record.read')
          or public.can_access_employee(e.id, 'people.employee.read')
        )
    ) x
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.get_executive_attendance_today(text, uuid, text) from public, anon;
grant execute on function public.get_executive_attendance_today(text, uuid, text) to authenticated, service_role;

commit;
