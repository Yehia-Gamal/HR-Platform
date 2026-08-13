-- ============================================================================
-- 0407: إصلاح get_executive_attendance_today (موبايل) — ثلاث مشاكل:
--   (1) الصور الشخصية: الـ RPC لم يكن يُرجع photoUrl إطلاقاً → بطاقات الحضور
--       كانت تعرض الحرف الأول بدل صورة الموظف. أضفنا الحقل.
--   (2) الحاضرون الآن: جملة WHERE كانت تُطبِّق فلتر can_access_employee حتى
--       على المدير التنفيذي، فتستبعد موظفين فعلاً لا يملك عليهم صلاحية
--       مباشرة (رغم أن لوحة الحضور التنفيذية يجب أن تُظهر المنظمة كلها).
--       الحل: المدير التنفيذي (manager_id is null) يرى كل الموظفين النشطين.
--   (3) اشتقاق الحالة: لم يكن يُشتق on_leave/holiday من الإجازات المعتمدة
--       والأعياد الرسمية، فيظهر الموظف في إجازة معتمدة كـ absent. أضفنا
--       الاشتقاق مواكِباً لـ get_attendance_dashboard (0355).
-- ============================================================================

begin;

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
      'photoUrl',         e.photo_url,
      'attendanceStatus', coalesce(ad.status,
        case
          when alv.employee_id is not null then 'on_leave'
          when mission.id is not null      then 'on_mission'
          when public.is_official_holiday(v_today, e.id) then 'holiday'
          when extract(isodow from v_today) = 5 then 'weekend'
          else 'absent'
        end),
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
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'present' then 2
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'late'    then 3
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'partial' then 4
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'absent'  then 8
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
      select lr.employee_id
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      where lr.employee_id = e.id
        and v_today between lr.start_date and lr.end_date
      limit 1
    ) alv on true
    left join lateral (
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      and (
        v_is_executive
        or public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.get_executive_attendance_today() from public;
grant execute on function public.get_executive_attendance_today() to authenticated;
notify pgrst, 'reload schema';

commit;
