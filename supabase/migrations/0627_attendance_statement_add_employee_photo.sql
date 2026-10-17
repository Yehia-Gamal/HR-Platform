-- 0627: إضافة photo_url لكائن employee في كشف الحضور الشهري
--
-- الدالة الأساسية _build_attendance_statement_v186 لا تجلب photo_url من جدول
-- employees ولا تدرجها في كائن employee JSON؛ مما يمنع AppAvatar من عرض
-- صورة الموظف. هنا: نضيف e.photo_url للاستعلام وندرجها في كائن employee.

begin;

create or replace function "public"."_build_attendance_statement_v186"("p_employee_id" "uuid", "p_year" integer, "p_month" integer) RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
declare
  v_emp record;
  v_start date;
  v_end date;
  v_days jsonb := '[]'::jsonb;
  v_day date;
  v_row record;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_day_obj jsonb;
  v_status text;
  v_scheduled_minutes integer;
  v_required_hours numeric;
  v_work_hours numeric;
  -- V23: متغيرات يومية إضافية
  v_is_absent boolean;
  v_is_holiday boolean;
  v_has_late_permit boolean;
  v_has_early_permit boolean;
  -- ملخصات
  v_total_days integer := 0;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_leave_days integer := 0;
  v_permit_count integer := 0;
  v_mission_days integer := 0;
  v_convoy_fundi_days integer := 0;
  v_total_work_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
  v_correction_count integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  -- V23: إجمالي الدقائق المطلوبة
  v_total_required_minutes integer := 0;
begin
  -- بيانات الموظف (+ photo_url)
  select e.id, e.employee_code, e.full_name_ar, e.full_name_en,
    e.hire_date, e.birth_date, e.photo_url,
    coalesce(d.name, '') as department_name,
    coalesce(jt.name, jt.name_en, '') as job_title,
    coalesce(b.name, '') as branch_name,
    coalesce(mgr.full_name_ar, '') as manager_name
  into v_emp
  from public.employees e
  left join public.departments d on d.id = e.department_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.branches b on b.id = e.branch_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and mr.relation_type = 'primary'
    and (mr.effective_to is null or mr.effective_to >= current_date)
  left join public.employees mgr on mgr.id = mr.manager_employee_id
  where e.id = p_employee_id;

  if v_emp.id is null then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  v_start := make_date(p_year, p_month, 1);
  v_end := (v_start + interval '1 month' - interval '1 day')::date;
  v_total_days := v_end - v_start + 1;

  -- بناء الجدول اليومي
  v_day := v_start;
  while v_day <= v_end loop
    -- تصفير المتغيرات اليومية
    v_is_absent := false;
    v_is_holiday := false;
    v_has_late_permit := false;
    v_has_early_permit := false;

    -- بيانات الحضور اليومي
    select * into v_row from public.attendance_daily a
    where a.employee_id = p_employee_id and a.work_date = v_day;

    -- الوردية
    v_scheduled_minutes := 0;
    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    if v_row.shift_id is not null then
      select s.name, s.start_time, s.end_time, s.crosses_midnight, coalesce(s.break_minutes,0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses, v_shift_break
      from public.shifts s where s.id = v_row.shift_id;
    end if;

    if v_shift_start is not null and v_shift_end is not null then
      if v_shift_crosses then
        v_scheduled_minutes := extract(epoch from ('24:00:00'::time - v_shift_start + v_shift_end))::integer / 60 - v_shift_break;
      else
        v_scheduled_minutes := extract(epoch from (v_shift_end - v_shift_start))::integer / 60 - v_shift_break;
      end if;
    end if;

    v_required_hours := greatest(0, round(v_scheduled_minutes / 60.0, 2));
    v_work_hours := 0;

    -- تحديد الحالة
    if extract(isodow from v_day) = 5 then
      v_status := 'راحة أسبوعية';
      v_rest_days := v_rest_days + 1;
    elsif exists (select 1 from public.official_holidays h
                  where v_day between h.start_date and h.end_date) then
      v_status := 'عطلة رسمية';
      v_is_holiday := true;
      v_holiday_days := v_holiday_days + 1;
    else
      v_scheduled_days := v_scheduled_days + 1;

      -- التكليفات (مأمورية / قافلة / فاندي)
      if exists (
        select 1
        from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id
          and wa.status in ('APPROVED','IN_PROGRESS','PENDING')
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at   at time zone 'Africa/Cairo')::date
          and wa.assignment_type = 'MISSION'
      ) then
        v_status := 'مأمورية عمل';
        v_mission_days := v_mission_days + 1;
      elsif exists (
        select 1
        from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id
          and wa.status in ('APPROVED','IN_PROGRESS','PENDING')
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at   at time zone 'Africa/Cairo')::date
          and wa.assignment_type = 'CONVOY'
      ) then
        v_status := 'قافلة';
        v_convoy_fundi_days := v_convoy_fundi_days + 1;
      elsif exists (
        select 1
        from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id
          and wa.status in ('APPROVED','IN_PROGRESS','PENDING')
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at   at time zone 'Africa/Cairo')::date
          and wa.assignment_type = 'FUNDRAISING'
      ) then
        v_status := 'فاندي';
        v_convoy_fundi_days := v_convoy_fundi_days + 1;
      -- المأموريات القديمة
      elsif exists (
        select 1 from public.missions m
        join public.requests r on r.id = m.request_id
        where m.employee_id = p_employee_id
          and r.status not in ('rejected','cancelled')
          and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                        and (m.end_at   at time zone 'Africa/Cairo')::date
      ) then
        v_status := 'مأمورية عمل';
        v_mission_days := v_mission_days + 1;
      -- payload missions/convoys/fundraising
      elsif exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id
          and r.status not in ('rejected','cancelled')
          and r.request_type in ('mission','convoy','fundraising')
          and v_day between coalesce(
                (r.payload->>'startDate')::date,
                (r.payload->>'startAt')::date,
                r.created_at::date
              ) and coalesce(
                (r.payload->>'endDate')::date,
                (r.payload->>'endAt')::date,
                r.created_at::date
              )
      ) then
        -- تحديد النوع
        if exists (
          select 1 from public.requests r
          where r.employee_id = p_employee_id
            and r.status not in ('rejected','cancelled')
            and r.request_type = 'mission'
            and v_day between coalesce(
                  (r.payload->>'startDate')::date,
                  (r.payload->>'startAt')::date,
                  r.created_at::date
                ) and coalesce(
                  (r.payload->>'endDate')::date,
                  (r.payload->>'endAt')::date,
                  r.created_at::date
                )
        ) then
          v_status := 'مأمورية عمل';
          v_mission_days := v_mission_days + 1;
        elsif exists (
          select 1 from public.requests r
          where r.employee_id = p_employee_id
            and r.status not in ('rejected','cancelled')
            and r.request_type = 'fundraising'
            and v_day between coalesce(
                  (r.payload->>'startDate')::date,
                  (r.payload->>'startAt')::date,
                  r.created_at::date
                ) and coalesce(
                  (r.payload->>'endDate')::date,
                  (r.payload->>'endAt')::date,
                  r.created_at::date
                )
        ) then
          v_status := 'فاندي';
          v_convoy_fundi_days := v_convoy_fundi_days + 1;
        else
          v_status := 'قافلة';
          v_convoy_fundi_days := v_convoy_fundi_days + 1;
        end if;
      -- إجازة
      elsif exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id
          and r.status not in ('rejected','cancelled')
          and v_day between lr.start_date and lr.end_date
      ) then
        v_status := 'إجازة معتمدة';
        v_leave_days := v_leave_days + 1;
      -- بيانات الحضور
      elsif v_row.id is not null then
        if v_row.first_check_in is not null then
          v_work_hours := round(coalesce(v_row.work_minutes, 0) / 60.0, 2);
          v_present_days := v_present_days + 1;
          v_total_work_minutes := v_total_work_minutes + coalesce(v_row.work_minutes, 0);
          if v_scheduled_minutes > 0 then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
          end if;
          v_total_late_minutes := v_total_late_minutes + coalesce(v_row.late_minutes, 0);
          v_total_early_minutes := v_total_early_minutes + coalesce(v_row.early_leave_minutes, 0);
          v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_row.overtime_minutes, 0);
          if coalesce(v_row.late_minutes, 0) > 0 then
            v_status := 'حاضر (متأخر)';
          else
            v_status := 'حاضر';
          end if;
          -- أذونات
          v_has_late_permit := exists (
            select 1 from public.requests r
            where r.employee_id = p_employee_id
              and r.status not in ('rejected','cancelled')
              and r.request_type in ('late_permit','late_excuse')
              and coalesce((r.payload->>'permitDate')::date,(r.payload->>'date')::date,r.created_at::date) = v_day
          );
          v_has_early_permit := exists (
            select 1 from public.requests r
            where r.employee_id = p_employee_id
              and r.status not in ('rejected','cancelled')
              and r.request_type = 'early_permit'
              and coalesce((r.payload->>'permitDate')::date,(r.payload->>'date')::date,r.created_at::date) = v_day
          );
          if v_has_late_permit or v_has_early_permit then
            v_permit_count := v_permit_count + 1;
          end if;
          -- بصمة ناقصة
          if v_row.last_check_out is null then
            v_missing_checkout := v_missing_checkout + 1;
          end if;
          -- تصحيحات
          if exists (select 1 from public.attendance_corrections c
                     where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved') then
            v_correction_count := v_correction_count + 1;
          end if;
        else
          -- لا بصمة دخول → غائب
          v_is_absent := true;
          v_status := 'غائب';
          v_absent_days := v_absent_days + 1;
          v_missing_checkin := v_missing_checkin + 1;
          if v_scheduled_minutes > 0 then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
          end if;
        end if;
      else
        -- لا يوجد سجل → غائب أو يوم لم يأت بعد
        if v_day > (now() at time zone 'Africa/Cairo')::date then
          v_status := 'قادم';
        else
          v_is_absent := true;
          v_status := 'غائب';
          v_absent_days := v_absent_days + 1;
          if v_scheduled_minutes > 0 then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
          end if;
        end if;
      end if;
    end if;

    -- بناء كائن اليوم
    v_day_obj := jsonb_build_object(
      'date', v_day,
      'dayName', to_char(v_day, 'Dy'),
      'shiftName', v_shift_name,
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'checkIn', v_row.first_check_in,
      'checkOut', v_row.last_check_out,
      'workHours', v_work_hours,
      'requiredHours', v_required_hours,
      'lateMinutes', coalesce(v_row.late_minutes, 0),
      'earlyLeaveMinutes', coalesce(v_row.early_leave_minutes, 0),
      'overtimeMinutes', coalesce(v_row.overtime_minutes, 0),
      'status', v_status,
      -- V23: حقول بوليانية مفصّلة
      'isAbsent', v_is_absent,
      'isOfficialHoliday', v_is_holiday,
      'hasLeave', (v_status = 'إجازة معتمدة'),
      'hasLatePermit', v_has_late_permit,
      'hasEarlyPermit', v_has_early_permit,
      'hasPermit', (v_has_late_permit or v_has_early_permit),
      'hasMission', (v_status like '%مأمورية%'),
      'hasConvoyFundi', (v_status like '%قافلة%' or v_status like '%فاندي%'),
      'missingCheckIn', (v_row.first_check_in is null and v_row.status not in ('absent','on_leave','holiday','weekend')
                         and v_status not like '%عطلة%' and v_status not like '%راحة%'
                         and v_status <> 'إجازة معتمدة' and v_status not like '%مأمورية%'
                         and v_status not like '%قافلة%' and v_status not like '%فاندي%'),
      'missingCheckOut', (v_row.last_check_out is null and v_row.first_check_in is not null),
      'hasCorrection', exists(select 1 from public.attendance_corrections c
                              where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved'),
      'correctionNote', (select c.reason from public.attendance_corrections c
                         where c.employee_id = p_employee_id and c.work_date = v_day and c.status = 'approved' limit 1),
      -- V23: ملاحظات وجزاءات
      'notes', null::text,
      'penalties', 0
    );

    v_days := v_days || v_day_obj;
    v_day := v_day + 1;
  end loop;

  return jsonb_build_object(
    'employee', jsonb_build_object(
      'id', v_emp.id,
      'employeeCode', v_emp.employee_code,
      'fullNameAr', v_emp.full_name_ar,
      'photoUrl', v_emp.photo_url,
      'jobTitle', v_emp.job_title,
      'department', v_emp.department_name,
      'manager', v_emp.manager_name,
      'branch', v_emp.branch_name,
      'hireDate', v_emp.hire_date
    ),
    'period', jsonb_build_object(
      'year', p_year, 'month', p_month,
      'startDate', v_start, 'endDate', v_end,
      'generatedAt', (now() at time zone 'Africa/Cairo')
    ),
    'days', v_days,
    'summary', jsonb_build_object(
      'totalDays', v_total_days,
      'scheduledDays', v_scheduled_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'leaveDays', v_leave_days,
      'permitCount', v_permit_count,
      'missionDays', v_mission_days,
      'convoyFundiDays', v_convoy_fundi_days,
      'holidayDays', v_holiday_days,
      'restDays', v_rest_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      -- V23: إجمالي الساعات المطلوبة
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_present_days > 0
        then round(v_total_work_minutes / 60.0 / v_present_days, 2) else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'correctionCount', v_correction_count,
      -- V23: نسب الحضور والالتزام
      'attendanceRate', case when v_scheduled_days > 0
        then round(v_present_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_total_work_minutes * 100.0 / v_total_required_minutes, 2)) else 0 end
    )
  );
end $$;

commit;
