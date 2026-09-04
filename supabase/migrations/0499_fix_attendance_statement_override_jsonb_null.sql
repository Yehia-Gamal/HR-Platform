begin;

-- ============================================================================
-- Migration 0499: إصلاح انهيار كشف الحضور الشهري عند وجود تعديل إداري (Day Override)
--
-- السبب الجذري:
-- في _build_attendance_statement كان يتم استدعاء jsonb_set لإضافة leaveType:
--   jsonb_set(v_day_obj, '{adminOverride,leaveType}', to_jsonb((select o.leave_type ...)))
-- وحين يقوم المدير بتعديل يوم عمل (dayType = 'work') أو أي يوم ليس إجازة،
-- فإن o.leave_type يكون NULL.
-- في PostgreSQL: الدالة jsonb_set تعيد NULL فوراً إذا كانت القيمة الجديدة (البارامتر الثالث) NULL!
-- هذا كان يحوّل v_day_obj إلى SQL NULL، ومن ثم يُضاف عنصر null داخل مصفوفة days.
-- وعندما يستقبل المتصفح days وبداخله عنصر null، يفشل Zod validation ويظهر:
-- «تعذّر تحميل البيانات — تعذر تحميل كشف الحضور».
-- بينما أي شهر آخر ليس به تعديلات إدارية يعمل بلا مشاكل لأن كود jsonb_set لا يُستدعى.
--
-- الحل:
-- 1) في _build_attendance_statement_v287: إضافة 'leaveType', v_override.leave_type
--    مباشرة داخل jsonb_build_object لـ adminOverride (تتعامل بأمان مع null دون كسر الكائن).
-- 2) في _build_attendance_statement: استخدام coalesce مع 'null'::jsonb بحيث لا يُمرر
--    SQL NULL أبداً لدالة jsonb_set، مع حماية v_day_obj من أن يُضاف كـ null.
-- ============================================================================

create or replace function public._build_attendance_statement_v287(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_type text;
  v_check_in time;
  v_check_out time;
  v_work_minutes integer;
  v_required_minutes integer;
  v_scheduled boolean;
  v_present boolean;
  v_covered boolean;
  v_is_future boolean;
  v_scheduled_days integer := 0;
  v_present_days integer := 0;
  v_covered_days integer := 0;
  v_total_work_minutes integer := 0;
  v_month_required_minutes integer := 0;
  v_month_deficit_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_open_shift_days integer := 0;
  v_completed_days integer := 0;
  v_absent_days integer := 0;
  v_upcoming_days integer := 0;
  v_leave_days integer := 0;
  v_mission_days integer := 0;
  v_convoy_days integer := 0;
  v_holiday_days integer := 0;
  v_rest_days integer := 0;
  v_due_days integer := 0;
  v_is_due boolean;
  v_is_open boolean;
begin
  v_result := public._build_attendance_statement_v266(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_override := null;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    v_type := coalesce(v_override.day_type, '');
    v_check_in := nullif(v_day_obj->>'checkIn', '')::time;
    v_check_out := nullif(v_day_obj->>'checkOut', '')::time;

    if v_override.id is not null then
      if v_override.clear_check_in then v_check_in := null;
      elsif v_override.check_in_override is not null then v_check_in := v_override.check_in_override;
      end if;
      if v_override.clear_check_out then v_check_out := null;
      elsif v_override.check_out_override is not null then v_check_out := v_override.check_out_override;
      end if;
    end if;

    -- الجمعة والعطل الرسمية ليست أيام عمل شهرية
    v_scheduled := extract(isodow from v_day) <> 5
      and not coalesce((v_day_obj->>'isOfficialHoliday')::boolean, false)
      and v_type not in ('holiday','rest');
    v_is_future := v_scheduled and v_day > (now() at time zone 'Africa/Cairo')::date;

    if v_type in ('leave','mission','convoy','fundraising','holiday','rest','absent') then
      v_check_in := null;
      v_check_out := null;
    end if;

    v_work_minutes := 0;
    if v_check_in is not null and v_check_out is not null then
      v_work_minutes := greatest(0, (extract(epoch from (
        (v_day + v_check_out + case when v_check_out <= v_check_in then interval '1 day' else interval '0' end)
        - (v_day + v_check_in)
      )) / 60)::integer);
    end if;

    v_required_minutes := case when v_scheduled
      then greatest(0, round(coalesce((v_day_obj->>'requiredHours')::numeric, 8) * 60)::integer)
      else 0 end;
    if v_scheduled and v_required_minutes = 0 then v_required_minutes := 480; end if;

    v_present := v_scheduled and v_check_in is not null;
    v_covered := v_scheduled and (
      v_present
      or v_type in ('leave','mission','convoy','fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    v_is_open := v_check_in is not null and v_check_out is null and not v_is_future;
    v_is_due := v_scheduled and not v_is_future and not v_is_open and not (
      v_type in ('leave', 'mission', 'convoy', 'fundraising')
      or (v_override.id is null and (
        coalesce((v_day_obj->>'hasLeave')::boolean, false)
        or coalesce((v_day_obj->>'hasMission')::boolean, false)
        or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
      ))
    );

    if v_scheduled then
      v_scheduled_days := v_scheduled_days + 1;
      v_month_required_minutes := v_month_required_minutes + v_required_minutes;
      if v_present then v_present_days := v_present_days + 1; end if;
      if v_is_due then v_due_days := v_due_days + 1; end if;
      if v_covered then v_covered_days := v_covered_days + 1; end if;
      if v_is_future then v_upcoming_days := v_upcoming_days + 1; end if;
      if not v_is_future and not v_covered and v_type <> 'leave' then
        v_absent_days := v_absent_days + 1;
      end if;
    end if;

    if v_check_in is not null and v_check_out is null and not v_is_future then
      v_open_shift_days := v_open_shift_days + 1;
    end if;
    if v_check_in is not null and v_check_out is not null then
      v_completed_days := v_completed_days + 1;
      v_total_work_minutes := v_total_work_minutes + v_work_minutes;
      v_month_deficit_minutes := v_month_deficit_minutes + greatest(0, v_required_minutes - v_work_minutes);
      v_total_overtime_minutes := v_total_overtime_minutes + greatest(0, v_work_minutes - v_required_minutes);
    end if;

    if v_type = 'leave' or (v_override.id is null and coalesce((v_day_obj->>'hasLeave')::boolean, false)) then
      v_leave_days := v_leave_days + 1;
    end if;
    if v_type = 'mission' or (v_override.id is null and coalesce((v_day_obj->>'hasMission')::boolean, false)) then
      v_mission_days := v_mission_days + 1;
    end if;
    if v_type in ('convoy','fundraising') or (v_override.id is null and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then
      v_convoy_days := v_convoy_days + 1;
    end if;
    if not v_scheduled then
      if extract(isodow from v_day) = 5 or v_type = 'rest' then v_rest_days := v_rest_days + 1;
      else v_holiday_days := v_holiday_days + 1;
      end if;
    end if;

    if v_scheduled then
      v_total_late_minutes := v_total_late_minutes + 0;
      v_total_early_minutes := v_total_early_minutes + 0;
    end if;

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn', case when v_check_in is null then null else to_char(v_check_in, 'HH24:MI') end,
      'checkOut', case when v_check_out is null then null else to_char(v_check_out, 'HH24:MI') end,
      'workHours', round(v_work_minutes / 60.0, 2),
      'requiredHours', round(v_required_minutes / 60.0, 2),
      'lateMinutes', 0,
      'earlyLeaveMinutes', 0,
      'overtimeMinutes', greatest(0, v_work_minutes - v_required_minutes),
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', (v_check_in is not null and v_check_out is not null),
      'isAbsent', (v_scheduled and not v_is_future and not v_covered),
      'hasLeave', case when v_override.id is null then coalesce((v_day_obj->>'hasLeave')::boolean, false) else v_type = 'leave' end,
      'hasMission', case when v_override.id is null then coalesce((v_day_obj->>'hasMission')::boolean, false) else v_type = 'mission' end,
      'hasConvoyFundi', case when v_override.id is null then coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) else v_type in ('convoy','fundraising') end,
      'hasCorrection', (v_override.id is not null) or coalesce((v_day_obj->>'hasCorrection')::boolean, false),
      'correctionNote', coalesce(v_override.notes, v_override.reason, v_day_obj->>'correctionNote'),
      'adminOverride', case when v_override.id is null then null else jsonb_build_object(
        'id', v_override.id,
        'dayType', v_override.day_type,
        'leaveType', v_override.leave_type,
        'reason', v_override.reason,
        'notes', v_override.notes,
        'updatedAt', v_override.updated_at
      ) end,
      'status', case
        when extract(isodow from v_day) = 5 then 'راحة أسبوعية'
        when v_type = 'holiday' then 'عطلة رسمية'
        when v_type = 'rest' then 'راحة أسبوعية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasMission')::boolean, false) then 'مأمورية'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)
             and v_day_obj->>'status' = 'فاندي' then 'فاندي'
        when (v_override.id is null) and coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false) then 'قافلة'
        when v_type = 'leave' then 'إجازة معتمدة'
        when v_type = 'mission' then 'مأمورية'
        when v_type = 'convoy' then 'قافلة'
        when v_type = 'fundraising' then 'فاندي'
        when v_type = 'absent' then 'غائب دون إذن'
        when v_override.id is null
             and (coalesce((v_day_obj->>'hasLeave')::boolean, false)
                  or coalesce((v_day_obj->>'hasMission')::boolean, false)
                  or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false)) then v_day_obj->>'status'
        when v_is_future then 'يوم قادم'
        when v_check_in is not null and v_check_out is null then 'حاضر — بانتظار الانصراف'
        when v_check_in is not null and v_check_out is not null and v_work_minutes < v_required_minutes then 'حاضر — ساعات غير مكتملة'
        when v_check_in is not null and v_check_out is not null then 'حاضر'
        when not v_scheduled then v_day_obj->>'status'
        else 'غائب دون إذن'
      end
    ));

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'capabilities', jsonb_build_object(
      'canEditDays', public.current_is_full_access()
        or public.can_access_employee(p_employee_id, 'attendance.correction.review')
        or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
    ),
    'summary', (v_result->'summary') || jsonb_build_object(
      'scheduledDays', v_scheduled_days,
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_days,
      'leaveDays', v_leave_days,
      'missionDays', v_mission_days,
      'convoyFundiDays', v_convoy_days,
      'holidayDays', v_holiday_days,
      'restDays', v_rest_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_month_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_days > 0 then round(v_total_work_minutes / 60.0 / v_completed_days, 2) else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'totalDeficitMinutes', v_month_deficit_minutes,
      'attendanceRate', case when v_due_days > 0
        then round((v_present_days - v_open_shift_days) * 100.0 / v_due_days, 2)
        else 0 end,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', (v_present_days - v_open_shift_days),
        'dueDays', v_due_days,
        'presentDays', v_present_days,
        'absentDays', v_absent_days,
        'openShiftDays', v_open_shift_days,
        'upcomingDays', v_upcoming_days
      ),
      'coverageRate', case when v_scheduled_days > 0 then round(v_covered_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'coverageDays', v_covered_days,
      'hoursComplianceAvailable', (v_month_required_minutes > 0),
      'hoursComplianceRate', case when v_month_required_minutes > 0
        then least(100, round(v_total_work_minutes * 100.0 / v_month_required_minutes, 2)) else 0 end,
      'hoursRateBasis', jsonb_build_object(
        'workedMinutes', v_total_work_minutes,
        'requiredMinutes', v_month_required_minutes,
        'scheduledDays', v_scheduled_days,
        'deficitMinutes', v_month_deficit_minutes,
        'overtimeMinutes', v_total_overtime_minutes
      ),
      'compliantWorkMinutes', v_total_work_minutes,
      'requiredMinutes', v_month_required_minutes
    )
  );

  return v_result;
end;
$function$;

-- ============================================================================
-- إعادة بناء _build_attendance_statement مع ضمان الأمان المطلق ضد تحول الأيام إلى NULL
-- ============================================================================
create or replace function public._build_attendance_statement(
  p_employee_id uuid,
  p_year integer,
  p_month integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_ci text;
  v_co text;
  v_status text;
  v_is_absent boolean;
  v_pending_days integer := 0;
  v_absent_days integer;
  v_pending_leave boolean;
  v_pending_mission boolean;
  v_pending_convoy boolean;
begin
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';

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
        and r.request_type in ('convoy','fundraising')
        and r.status = 'pending'
        and v_day between (r.payload->>'startDate')::date
                      and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
    );

    v_status := v_day_obj->>'status';
    v_is_absent := coalesce((v_day_obj->>'isAbsent')::boolean, false);

    -- يوم عليه طلب معلّق ولا تغطيه قاعدة أخرى → «بانتظار الاعتماد»
    if (v_pending_leave or v_pending_mission or v_pending_convoy)
       and v_is_absent
       and v_ci is null then
      v_status := case
        when v_pending_leave then 'بانتظار اعتماد إجازة'
        when v_pending_mission then 'بانتظار اعتماد مأمورية'
        else 'بانتظار اعتماد تكليف'
      end;
      v_is_absent := false;
      v_pending_days := v_pending_days + 1;
    end if;

    -- 0362 + 0499: adminOverride.leaveType — ضمان دمج leaveType دون السماح بتمرير SQL NULL إلى jsonb_set
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

    v_day_obj := v_day_obj || jsonb_strip_nulls(jsonb_build_object(
      'checkIn12',  case when v_ci is not null and v_ci <> '' then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null and v_co <> '' then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer
      ),
      'status', v_status,
      'isAbsent', v_is_absent,
      'hasPendingLeave', v_pending_leave,
      'hasPendingMission', v_pending_mission,
      'hasPendingConvoyFundi', v_pending_convoy
    ));

    if v_day_obj is not null then
      v_days := v_days || jsonb_build_array(v_day_obj);
    end if;
  end loop;

  v_absent_days := (select count(*)::int
    from jsonb_array_elements(v_days) d
    where d is not null and coalesce((d->>'isAbsent')::boolean, false));

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'absentDays', v_absent_days,
      'pendingDays', v_pending_days,
      'totalWorkHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalWorkHours')::numeric, 0) * 60))::integer
      ),
      'totalRequiredHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_result->'summary'->>'totalRequiredHours')::numeric, 0) * 60))::integer
      ),
      'totalDeficitFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalDeficitMinutes')::integer, 0))
      ),
      'totalOvertimeFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalOvertimeMinutes')::integer, 0))
      ),
      'totalLateFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalLateMinutes')::integer, 0))
      ),
      'totalEarlyLeaveFormatted', public._fmt_minutes_ar(
        greatest(0, coalesce((v_result->'summary'->>'totalEarlyLeaveMinutes')::integer, 0))
      )
    )
  );

  return v_result;
end
$$;

commit;
