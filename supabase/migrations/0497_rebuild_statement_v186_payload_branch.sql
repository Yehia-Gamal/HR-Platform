-- 0497: إعادة بناء _build_attendance_statement_v186 — استعادة فرع payload وترتيب الفحوصات
-- مقتبس كنونياً من 0432 (الباني الأساسي للكشف الشهري): تمرير ترتيب الفحوصات
-- تكليفات ← مأموريات قديمة ← payload ← إجازة ← صف الحضور ← غائب

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
  -- بيانات الموظف
  select e.id, e.employee_code, e.full_name_ar, e.full_name_en,
    e.hire_date, e.birth_date,
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
      if v_shift_start is not null then
        v_scheduled_minutes := greatest(0,
          case when v_shift_crosses
               then extract(epoch from ((v_shift_end + interval '24 hours') - v_shift_start))/60
               else extract(epoch from (v_shift_end - v_shift_start))/60
          end - v_shift_break)::integer;
      end if;
    end if;

    v_required_hours := round(v_scheduled_minutes / 60.0, 2);
    v_work_hours := round(coalesce(v_row.work_minutes, 0) / 60.0, 2);

    -- تحديد حالة اليوم المفصّلة
    v_status := coalesce(v_row.status, 'absent');

    -- هل هو يوم عطلة رسمية؟
    if exists (select 1 from public.public_holidays h
               where h.is_active and v_day between h.holiday_date and coalesce(h.end_date, h.holiday_date)) then
      v_status := 'عطلة رسمية';
      v_holiday_days := v_holiday_days + 1;
      v_is_holiday := true;
    -- هل هو يوم راحة (الجمعة فقط)؟
    elsif extract(isodow from v_day) = 5 then
      v_status := 'راحة أسبوعية';
      v_rest_days := v_rest_days + 1;
    -- هل هو روستر راحة/عطلة؟
    elsif exists (select 1 from public.roster_days rd
                  where rd.employee_id = p_employee_id and rd.work_date = v_day
                    and rd.day_status in ('rest','holiday')
                    and rd.day_status <> 'cancelled') then
      v_status := case (select rd.day_status from public.roster_days rd
                        where rd.employee_id = p_employee_id and rd.work_date = v_day
                          and rd.day_status <> 'cancelled' limit 1)
                   when 'rest' then 'راحة أسبوعية'
                   else 'عطلة رسمية' end;
      if v_status = 'راحة أسبوعية' then v_rest_days := v_rest_days + 1;
      else
        v_holiday_days := v_holiday_days + 1;
        v_is_holiday := true;
      end if;
    else
      -- يوم مجدول — نحسبه
      v_scheduled_days := v_scheduled_days + 1;
      -- V23: تراكم الدقائق المطلوبة
      v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;

      -- مأمورية عمل (work_assignments)؟
      if exists (
        select 1 from public.work_assignment_participants wp
        join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = p_employee_id and wa.status = 'APPROVED'
          and coalesce(wa.counts_as_work_day, true)
          and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                        and (wa.end_at at time zone 'Africa/Cairo')::date
      ) then
        -- نوع التكليف
        v_status := coalesce(
          (select case wa.assignment_type
                   when 'MISSION' then 'مأمورية عمل'
                   when 'CONVOY' then 'قافلة'
                   when 'FUNDRAISING' then 'فاندي'
                 end
           from public.work_assignment_participants wp
           join public.work_assignments wa on wa.id = wp.assignment_id
           where wp.employee_id = p_employee_id and wa.status = 'APPROVED'
             and v_day between (wa.start_at at time zone 'Africa/Cairo')::date
                           and (wa.end_at at time zone 'Africa/Cairo')::date
           limit 1),
          'مأمورية عمل');
        if v_status = 'مأمورية عمل' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;
      -- مأمورية قديمة (missions table)?
      elsif exists (
        select 1 from public.missions m
        join public.requests r on r.id = m.request_id
        where m.employee_id = p_employee_id and r.status = 'approved'
          and v_day between (m.start_at at time zone 'Africa/Cairo')::date
                        and (m.end_at at time zone 'Africa/Cairo')::date
      ) then
        v_status := 'مأمورية عمل';
        v_mission_days := v_mission_days + 1;
      -- مأمورية/قافلة/فاندي من payload الطلبات (المصدر الحالي للتطبيق)?
      elsif exists (
        select 1 from public.requests r
        where r.employee_id = p_employee_id and r.status = 'approved'
          and r.request_type in ('mission','convoy','fundraising')
          and public._payload_date(r.payload, 'startDate') is not null
          and v_day between public._payload_date(r.payload, 'startDate')
                        and coalesce(public._payload_date(r.payload, 'endDate'),
                                     public._payload_date(r.payload, 'startDate'))
      ) then
        v_status := case (select r.request_type from public.requests r
                          where r.employee_id = p_employee_id and r.status = 'approved'
                            and r.request_type in ('mission','convoy','fundraising')
                            and public._payload_date(r.payload, 'startDate') is not null
                            and v_day between public._payload_date(r.payload, 'startDate')
                                          and coalesce(public._payload_date(r.payload, 'endDate'),
                                                       public._payload_date(r.payload, 'startDate'))
                          limit 1)
                     when 'mission' then 'مأمورية عمل'
                     when 'convoy' then 'قافلة'
                     else 'فاندي' end;
        if v_status = 'مأمورية عمل' then v_mission_days := v_mission_days + 1;
        else v_convoy_fundi_days := v_convoy_fundi_days + 1; end if;
      -- إجازة معتمدة؟
      elsif v_row.status = 'on_leave' or exists (
        select 1 from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        where lr.employee_id = p_employee_id and r.status = 'approved'
          and v_day between lr.start_date and lr.end_date
      ) then
        v_status := 'إجازة معتمدة';
        v_leave_days := v_leave_days + 1;
      -- حاضر/متأخر/جزئي/غائب
      elsif v_row.id is not null then
        v_status := case v_row.status
          when 'present' then 'حاضر'
          when 'late' then 'متأخر'
          when 'partial' then 'حضور ناقص'
          when 'pending' then 'يحتاج مراجعة'
          when 'absent' then 'غائب دون إذن'
          else coalesce(v_row.status, 'غائب دون إذن')
        end;
        if v_row.status = 'absent' then
          v_absent_days := v_absent_days + 1;
          v_is_absent := true;
        elsif v_row.status in ('present','late','partial') then
          v_present_days := v_present_days + 1;
        end if;
      else
        v_status := 'غائب دون إذن';
        v_absent_days := v_absent_days + 1;
        v_is_absent := true;
      end if;
    end if;

    -- V23: إذن تأخير/انصراف مبكر (مفصّل)
    select
      exists(select 1 from public.attendance_permits p
             where p.employee_id = p_employee_id and p.permit_date = v_day
               and p.status = 'approved' and p.kind = 'arrival'),
      exists(select 1 from public.attendance_permits p
             where p.employee_id = p_employee_id and p.permit_date = v_day
               and p.status = 'approved' and p.kind = 'departure')
    into v_has_late_permit, v_has_early_permit;

    -- إذن حضور؟ (عدّاد تجميعي — يشمل الاثنين)
    if v_has_late_permit or v_has_early_permit then
      v_permit_count := v_permit_count + 1;
    end if;

    -- تصحيح معتمد؟
    if exists (select 1 from public.attendance_corrections c
               where c.employee_id = p_employee_id and c.work_date = v_day
                 and c.status = 'approved') then
      v_correction_count := v_correction_count + 1;
      if v_status = 'غائب دون إذن' or v_status = 'يحتاج مراجعة' then
        v_status := 'تصحيح معتمد';
        -- التصحيح يُلغي الغياب
        if v_is_absent then
          v_is_absent := false;
          v_absent_days := greatest(0, v_absent_days - 1);
          v_present_days := v_present_days + 1;
        end if;
      end if;
    end if;

    -- نسيان ختم
    if v_row.id is not null and v_row.status not in ('on_leave','holiday','weekend')
       and v_status not like '%عطلة%' and v_status not like '%راحة%'
       and v_status <> 'إجازة معتمدة' and v_status not like '%مأمورية%'
       and v_status not like '%قافلة%' and v_status not like '%فاندي%' then
      if v_row.first_check_in is null and v_row.status <> 'absent' then
        v_missing_checkin := v_missing_checkin + 1;
      end if;
      if v_row.last_check_out is null and v_row.first_check_in is not null then
        v_missing_checkout := v_missing_checkout + 1;
      end if;
    end if;

    -- تراكمات
    v_total_work_minutes := v_total_work_minutes + coalesce(v_row.work_minutes, 0);
    v_total_late_minutes := v_total_late_minutes + coalesce(v_row.late_minutes, 0);
    v_total_early_minutes := v_total_early_minutes + coalesce(v_row.early_leave_minutes, 0);
    v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_row.overtime_minutes, 0);

    -- بناء صف اليوم (مع حقول V23)
    v_day_obj := jsonb_build_object(
      'date', v_day,
      'dayName', to_char(v_day, 'Dy'),
      'dayNameAr', case extract(isodow from v_day)
        when 1 then 'الاثنين' when 2 then 'الثلاثاء' when 3 then 'الأربعاء'
        when 4 then 'الخميس' when 5 then 'الجمعة' when 6 then 'السبت' when 7 then 'الأحد' end,
      'checkIn', (v_row.first_check_in at time zone 'Africa/Cairo')::time(0),
      'checkOut', (v_row.last_check_out at time zone 'Africa/Cairo')::time(0),
      'shiftName', v_shift_name,
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
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
