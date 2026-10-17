-- ============================================================================
-- 0641: إعادة قسم employee إلى كشف الحضور الشهري (_build_attendance_statement)
-- ============================================================================
-- المشكلة: كل النسخ v251..v287 والحالية من الدالة بلا مفتاح 'employee' إطلاقاً
--   (الحرف غير موجود في prosrc) — قسم employee كان موجوداً في v186 فقط.
-- الآثار:
--   * الويب: attendanceStatementSchema يتطلب employee.name (z.string() بلا
--     optional) → safeParse يفشل → useMonthlyStatement يرمي خطأ → صفحة الكشف معطلة.
--   * exportAllAttendancePDFs / MonthlyAttendanceReportPage / AttendanceReportsPage
--     تقرأ employee.fullNameAr مباشرة.
--   * اختبار pgTAP 0050 «اسم الموظف في الكشف» = NULL.
-- الإصلاح: تحميل بيانات الموظف مع hire_date + دمج كائن employee (name + fullNameAr
--   معاً لتغطية الطرفين) فوق نتيجة النسخة v286. الصلاحية تبقى كما هي
--   (SECURITY DEFINER + بوابة get_employee_monthly_attendance_statement).

begin;

CREATE OR REPLACE FUNCTION public._build_attendance_statement(p_employee_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_late_grace constant integer := 15;   -- فترة السماح (0576)
  c_late_cap   constant integer := 120;  -- حد احتساب التأخير (0576)
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
  v_summary jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
  v_pending_permit boolean;
  v_has_late_p boolean;
  v_has_early_p boolean;
  v_is_exempt boolean;
  v_hire_date date;
  v_emp_name text;
  v_emp_code text;
  v_emp_photo text;
  v_job_title text;
  v_dept_name text;
  v_override_type text;
  v_scheduled boolean;
  v_on_leave boolean;
  v_offsite boolean;
  v_pending boolean;
  v_exempt_day boolean;
  v_waiting_today boolean;
  v_expected boolean;
  v_attended boolean;
  v_open_today boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_shift_start time;
  v_shift_end time;
  v_late integer;
  v_early integer;
  v_day_work integer;
  v_day_required integer;
  -- المجاميع
  v_pending_days integer := 0;
  v_expected_days integer := 0;
  v_attended_days integer := 0;
  v_offsite_days integer := 0;
  v_excl_leave integer := 0;
  v_excl_pending integer := 0;
  v_excl_exempt integer := 0;
  v_absent_days integer := 0;
  v_open_days integer := 0;
  v_missing_in_count integer := 0;
  v_missing_out_count integer := 0;
  v_hours_days integer := 0;
  v_required_minutes integer := 0;
  v_worked_minutes integer := 0;
  v_deficit_minutes integer := 0;
  v_late_total integer := 0;
  v_late_days integer := 0;
  v_early_total integer := 0;
  v_early_days integer := 0;
begin
  v_is_exempt := public.is_employee_attendance_exempt(p_employee_id);
  select e.hire_date, e.full_name_ar, e.employee_code, e.photo_url,
         jt.name, d.name
    into v_hire_date, v_emp_name, v_emp_code, v_emp_photo, v_job_title, v_dept_name
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
   where e.id = p_employee_id;
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    continue when v_day_obj is null or v_day_obj = 'null'::jsonb;

    v_day := (v_day_obj->>'date')::date;

    -- 0587: أيام ما قبل التعيين ليست أيام عمل مستحقة ولا غياباً (كانت تُعدّ
    -- «غائب دون إذن» لمن عُيّن في منتصف الشهر — 24 يوماً لموظفة عُيّنت 29/9)
    if v_hire_date is not null and v_day < v_hire_date then
      v_days := v_days || jsonb_build_array(v_day_obj || jsonb_build_object(
        'status', 'قبل تاريخ التعيين',
        'isAbsent', false, 'isDue', false, 'isOpenShift', false,
        'missingCheckIn', false, 'missingCheckOut', false,
        'lateMinutes', 0, 'earlyLeaveMinutes', 0));
      continue;
    end if;

    v_ci := nullif(v_day_obj->>'checkIn', '');
    v_co := nullif(v_day_obj->>'checkOut', '');
    v_has_late_p := coalesce((v_day_obj->>'hasLatePermit')::boolean, false);
    v_has_early_p := coalesce((v_day_obj->>'hasEarlyPermit')::boolean, false);

    v_pending_leave := exists (
      select 1 from public.requests r
      join public.leave_requests lr on lr.request_id = r.id
      where lr.employee_id = p_employee_id
        and r.status = 'pending'
        and v_day between lr.start_date and lr.end_date
    );
    v_pending_mission := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type = 'mission'
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_convoy := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('convoy', 'fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );
    v_pending_permit := exists (
      select 1 from public.requests r
      where r.employee_id = p_employee_id
        and r.request_type in ('late_permit', 'early_permit', 'permit', 'permission')
        and r.status = 'pending'
        and coalesce(
          (r.payload->>'permitDate')::date,
          (r.payload->>'date')::date,
          (r.payload->>'startDate')::date,
          (r.payload->>'workDate')::date,
          r.created_at::date
        ) = v_day
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه بصمة → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy or v_pending_permit)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        when v_pending_permit then 'بانتظار اعتماد إذن'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    if v_is_exempt and (v_status in ('غائب دون إذن', 'بانتظار حضور') or v_is_absent) then
      v_status := 'معفى من الحضور';
      v_is_absent := false;
    end if;

    -- adminOverride.leaveType
    if (v_day_obj->'adminOverride') is not null and (v_day_obj->'adminOverride') <> 'null'::jsonb then
      v_day_obj := jsonb_set(
        v_day_obj,
        '{adminOverride,leaveType}',
        coalesce(
          (v_day_obj->'adminOverride'->'leaveType'),
          to_jsonb((
            select o.leave_type
            from public.attendance_day_overrides o
            where o.employee_id = p_employee_id
              and o.work_date = v_day
              and o.is_active
            limit 1
          )),
          'null'::jsonb
        ),
        true
      );
    end if;

    -- ── تصنيف اليوم ──
    v_override_type := coalesce(v_day_obj->'adminOverride'->>'dayType', '');
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_override_type not in ('holiday', 'rest');
    v_on_leave := coalesce((v_day_obj->>'hasLeave')::boolean, false) and v_ci is null;
    v_offsite := coalesce((v_day_obj->>'hasMission')::boolean, false)
              or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_pending := v_status like 'بانتظار اعتماد%';
    v_exempt_day := v_status = 'معفى من الحضور';
    -- اليوم الجاري قبل نهاية الدوام بلا بصمة (v286: «بانتظار حضور») لا يُحتسب بعد
    v_waiting_today := v_day = v_today and v_ci is null and not v_is_absent and not v_offsite;
    v_expected := v_scheduled and v_day <= v_today and not v_on_leave and not v_pending
                  and not v_exempt_day and not v_waiting_today;
    v_attended := v_expected and (v_ci is not null or v_offsite);
    v_open_today := v_day = v_today and v_ci is not null and v_co is null;

    -- ── أعلام النقص من البيانات النهائية (بعد التعديلات الإدارية) ──
    v_missing_out := v_scheduled and v_day < v_today and v_ci is not null and v_co is null
                     and not v_offsite and not v_has_early_p and not v_pending_permit and not v_is_exempt;
    v_missing_in := v_scheduled and v_ci is null
                    and (v_co is not null or coalesce((v_day_obj->>'missingCheckIn')::boolean, false))
                    and not v_has_late_p and not v_pending_permit and not v_is_exempt;

    -- ── التأخير والخروج المبكر (أيام الدوام بالبصمة فقط) ──
    v_late := 0;
    v_early := 0;
    -- 0586: التأخير من الدالة نفسها التي تحسبه البصمة والغرامة (مصدر واحد)
    if v_ci is not null then
      begin
        v_late := public.attendance_policy_late_minutes(
          p_employee_id, v_day, ((v_day + v_ci::time)::timestamp at time zone 'Africa/Cairo'), null);
      exception when others then
        v_late := 0;
      end;
    end if;
    if v_scheduled and v_ci is not null and not v_offsite and not v_is_exempt and not v_pending_permit then
      v_shift_end := nullif(v_day_obj->>'shiftEnd', '')::time;
      if v_shift_end is not null and v_co is not null and not v_has_early_p
         and v_co::time > v_ci::time and v_co::time < v_shift_end then
        v_early := floor(extract(epoch from (v_shift_end - v_co::time)) / 60)::integer;
      end if;
    end if;

    -- ── الساعات: أيام الدوام المستحقة (والمأمورية إن اكتملت بصمتاها) ──
    v_day_work := greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer;
    v_day_required := greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60))::integer;
    if v_day_required = 0 then v_day_required := 480; end if;
    if v_expected and not v_open_today and (not v_offsite or (v_ci is not null and v_co is not null)) then
      v_hours_days := v_hours_days + 1;
      v_required_minutes := v_required_minutes + v_day_required;
      v_worked_minutes := v_worked_minutes + v_day_work;
      v_deficit_minutes := v_deficit_minutes + greatest(0, v_day_required - v_day_work);
    end if;

    -- ── المجاميع ──
    if v_scheduled and v_day <= v_today then
      if v_on_leave then v_excl_leave := v_excl_leave + 1;
      elsif v_pending then v_excl_pending := v_excl_pending + 1;
      elsif v_exempt_day then v_excl_exempt := v_excl_exempt + 1;
      end if;
    end if;
    if v_expected then
      v_expected_days := v_expected_days + 1;
      if v_attended then
        v_attended_days := v_attended_days + 1;
        if v_ci is null then v_offsite_days := v_offsite_days + 1; end if;
      end if;
    end if;
    if v_open_today then v_open_days := v_open_days + 1; end if;
    if v_missing_in then v_missing_in_count := v_missing_in_count + 1; end if;
    if v_missing_out then v_missing_out_count := v_missing_out_count + 1; end if;
    if v_late > 0 then v_late_total := v_late_total + v_late; v_late_days := v_late_days + 1; end if;
    if v_early > 0 then v_early_total := v_early_total + v_early; v_early_days := v_early_days + 1; end if;

    -- يوم ماضٍ بلا انصراف: v287 يسمّيه «بانتظار الانصراف» لكل الأيام
    if v_day < v_today and v_status = 'حاضر — بانتظار الانصراف' then
      v_status := case
        when v_has_early_p then 'حاضر (إذن انصراف)'
        when v_missing_out then 'حضور ناقص — لم يسجل الانصراف'
        else 'حاضر'
      end;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(v_day_work),
      'status', v_status
    )) || jsonb_build_object(
      'isAbsent', v_is_absent,
      'isDue', v_expected,
      'isOpenShift', v_open_today,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy,
      'hasPendingPermit', v_pending_permit,
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out,
      'lateMinutes', v_late,
      'earlyLeaveMinutes', v_early
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_absent_days := (select count(*)::int from jsonb_array_elements(v_days) d
                    where coalesce((d->>'isAbsent')::boolean, false));

  v_summary := coalesce(v_result->'summary', '{}'::jsonb);
  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', v_summary || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'dueScheduledDays', v_expected_days,
      'openShiftDays', v_open_days,
      'missingCheckInCount', v_missing_in_count,
      'missingCheckOutCount', v_missing_out_count,
      'isAttendanceExempt', v_is_exempt,
      'attendanceRate', case when v_expected_days > 0
        then round(least(v_attended_days, v_expected_days) * 100.0 / v_expected_days, 2)
        else 0 end,
      'attendanceRateAvailable', v_expected_days > 0 and not v_is_exempt,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', least(v_attended_days, v_expected_days),
        'dueDays', v_expected_days,
        'presentDays', coalesce((v_summary->>'presentDays')::integer, 0),
        'offsiteDays', v_offsite_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_days,
        'upcomingDays', coalesce((v_summary->>'upcomingDays')::integer, 0),
        'excludedLeaveDays', v_excl_leave,
        'excludedPendingDays', v_excl_pending,
        'excludedExemptDays', v_excl_exempt,
        'basis', 'elapsed_workdays_excluding_leave_pending_exempt'
      ),
      'hoursComplianceAvailable', v_required_minutes > 0 and not v_is_exempt,
      'hoursComplianceRate', case when v_required_minutes > 0
        then least(100, round(v_worked_minutes * 100.0 / v_required_minutes, 2))
        else 0 end,
      'totalRequiredHours', round(v_required_minutes / 60.0, 2),
      'requiredMinutes', v_required_minutes,
      'compliantWorkMinutes', v_worked_minutes,
      'totalDeficitMinutes', v_deficit_minutes,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_worked_minutes,
        'requiredMinutes', v_required_minutes,
        'scheduledDays', v_hours_days,
        'deficitMinutes', v_deficit_minutes,
        'overtimeMinutes', coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0),
        'monthRequiredMinutes', coalesce((v_summary->'hoursRateBasis'->>'requiredMinutes')::integer, 0),
        'basis', 'elapsed_office_days'
      ),
      'totalLateMinutes', v_late_total,
      'lateDays', v_late_days,
      'totalEarlyLeaveMinutes', v_early_total,
      'earlyLeaveDays', v_early_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_summary->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(v_required_minutes),
      'totalDeficitFormatted', public._fmt_minutes_ar(v_deficit_minutes),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_summary->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(v_late_total),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(v_early_total)
    )
  );

  -- 0641: قسم employee — مفقود منذ صياغة 0251 (كل النسخ v251+ بلا حرف employee).
  -- الويب يتطلبه (attendanceStatementSchema employee.name إلزامي)، وتصدير PDF
  -- يقرأ employee.fullNameAr، واختبار 0050 (اسم الموظف في الكشف) يقرؤه.
  v_result := v_result || jsonb_build_object('employee', jsonb_build_object(
    'id', p_employee_id,
    'name', v_emp_name,
    'fullNameAr', v_emp_name,
    'employeeCode', v_emp_code,
    'jobTitle', v_job_title,
    'department', v_dept_name,
    'photoUrl', v_emp_photo
  ));

  return v_result;
end;

$function$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0641: كشف شهري + قسم employee (name/fullNameAr/employeeCode/jobTitle/department/photoUrl) — عاد بعد حذفه في 0251.';

commit;