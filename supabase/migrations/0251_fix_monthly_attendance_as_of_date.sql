-- 0251: Make the monthly attendance statement an "as of now" report.
--
-- The previous implementation classified every unrecorded workday in the
-- selected month as absent.  In the current month this made future dates look
-- like absences and divided attendance by the whole month's scheduled days.
-- Keep the V18/V23 builder intact as a private legacy source, then normalize
-- its result with current-date, open-shift, and shift-fallback semantics.

begin;

do $rename$
begin
  if to_regprocedure('public._build_attendance_statement_v186(uuid,integer,integer)') is null then
    alter function public._build_attendance_statement(uuid, integer, integer)
      rename to _build_attendance_statement_v186;
  end if;
end
$rename$;

revoke execute on function public._build_attendance_statement_v186(uuid, integer, integer)
  from public, anon, authenticated;

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
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_now_local timestamp := now() at time zone 'Africa/Cairo';
  v_daily public.attendance_daily%rowtype;
  v_shift_id uuid;
  v_shift_name text;
  v_shift_start time;
  v_shift_end time;
  v_shift_crosses boolean;
  v_shift_break integer;
  v_grace_out integer;
  v_start_override time;
  v_end_override time;
  v_shift_end_at timestamp;
  v_scheduled_minutes integer;
  v_is_scheduled boolean;
  v_is_excused boolean;
  v_is_future boolean;
  v_is_due boolean;
  v_is_open boolean;
  v_is_completed boolean;
  v_missing_in boolean;
  v_missing_out boolean;
  v_status text;
  v_due_days integer := 0;
  v_upcoming_days integer := 0;
  v_present_days integer := 0;
  v_absent_days integer := 0;
  v_open_shift_days integer := 0;
  v_completed_presence_days integer := 0;
  v_completed_work_minutes integer := 0;
  v_compliance_work_minutes integer := 0;
  v_total_work_minutes integer := 0;
  v_total_required_minutes integer := 0;
  v_total_late_minutes integer := 0;
  v_total_early_minutes integer := 0;
  v_total_overtime_minutes integer := 0;
  v_missing_checkin integer := 0;
  v_missing_checkout integer := 0;
begin
  v_result := public._build_attendance_statement_v186(
    p_employee_id,
    p_year,
    p_month
  );

  for v_day_obj in
    select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    v_status := coalesce(v_day_obj->>'status', '');
    v_is_scheduled := v_status not in ('راحة أسبوعية', 'عطلة رسمية');
    v_is_excused :=
      coalesce((v_day_obj->>'hasLeave')::boolean, false)
      or coalesce((v_day_obj->>'hasMission')::boolean, false)
      or coalesce((v_day_obj->>'hasConvoyFundi')::boolean, false);
    v_is_future := v_is_scheduled and not v_is_excused and v_day > v_today;
    v_is_due := false;
    v_is_open := false;
    v_is_completed := false;
    v_missing_in := false;
    v_missing_out := false;

    select * into v_daily
    from public.attendance_daily ad
    where ad.employee_id = p_employee_id
      and ad.work_date = v_day;

    -- Resolve the effective shift in the same order used by attendance punch:
    -- daily record -> published roster -> active employee assignment -> active
    -- official/default shift.  Roster time overrides win over shift times.
    v_shift_id := v_daily.shift_id;
    v_start_override := null;
    v_end_override := null;

    if v_shift_id is null then
      select rd.shift_id, rd.start_override, rd.end_override
        into v_shift_id, v_start_override, v_end_override
      from public.roster_days rd
      join public.work_rosters wr
        on wr.id = rd.roster_id and wr.status = 'published'
      where rd.employee_id = p_employee_id
        and rd.work_date = v_day
        and rd.day_status = 'scheduled'
      order by wr.published_at desc nulls last, wr.created_at desc
      limit 1;
    end if;

    if v_shift_id is null then
      select sa.shift_id into v_shift_id
      from public.shift_assignments sa
      where sa.employee_id = p_employee_id
        and sa.is_active
        and sa.effective_from <= v_day
        and (sa.effective_to is null or sa.effective_to >= v_day)
      order by sa.effective_from desc, sa.created_at desc
      limit 1;
    end if;

    if v_shift_id is null and v_is_scheduled then
      select s.id into v_shift_id
      from public.shifts s
      where s.is_active
      order by (s.code = 'OFFICIAL') desc,
               s.updated_at desc nulls last,
               s.created_at desc
      limit 1;
    end if;

    v_shift_name := '';
    v_shift_start := null;
    v_shift_end := null;
    v_shift_crosses := false;
    v_shift_break := 0;
    v_grace_out := 0;
    v_scheduled_minutes := 0;

    if v_shift_id is not null then
      select s.name,
             coalesce(v_start_override, s.start_time),
             coalesce(v_end_override, s.end_time),
             s.crosses_midnight or coalesce(v_end_override, s.end_time) <= coalesce(v_start_override, s.start_time),
             coalesce(s.break_minutes, 0),
             coalesce(s.grace_out_minutes, 0)
        into v_shift_name, v_shift_start, v_shift_end, v_shift_crosses,
             v_shift_break, v_grace_out
      from public.shifts s
      where s.id = v_shift_id;

      if v_shift_start is not null and v_shift_end is not null then
        v_scheduled_minutes := greatest(
          0,
          (extract(epoch from (
            (v_day + v_shift_end
              + case when v_shift_crosses then interval '1 day' else interval '0' end)
            - (v_day + v_shift_start)
          )) / 60)::integer - v_shift_break
        );
        v_shift_end_at := v_day + v_shift_end
          + case when v_shift_crosses then interval '1 day' else interval '0' end
          + make_interval(mins => v_grace_out);
      else
        v_shift_end_at := v_day::timestamp + interval '1 day';
      end if;
    else
      -- Without a known shift, never accuse the current day before it ends.
      v_shift_end_at := v_day::timestamp + interval '1 day';
    end if;

    if v_is_scheduled then
      if v_is_future then
        v_upcoming_days := v_upcoming_days + 1;
        if v_status = 'غائب دون إذن' then
          v_status := 'يوم قادم';
        end if;
      else
        -- Approved leave/mission classifications from the legacy builder are
        -- preserved and excluded from attendance/hours denominators. Only
        -- ordinary attendance days are normalized here.
        if not v_is_excused then
          if coalesce((v_day_obj->>'hasCorrection')::boolean, false)
             and not coalesce((v_day_obj->>'isAbsent')::boolean, false) then
            v_is_due := true;
            v_present_days := v_present_days + 1;
            if v_daily.first_check_in is not null and v_daily.last_check_out is not null then
              v_is_completed := true;
              v_completed_presence_days := v_completed_presence_days + 1;
              v_completed_work_minutes :=
                v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
            end if;
          elsif v_daily.first_check_in is not null then
            v_is_due := true;
            v_present_days := v_present_days + 1;

            if v_daily.last_check_out is not null then
              v_is_completed := true;
              v_completed_presence_days := v_completed_presence_days + 1;
              v_completed_work_minutes :=
                v_completed_work_minutes + coalesce(v_daily.work_minutes, 0);
            elsif v_now_local <= v_shift_end_at then
              v_is_open := true;
              v_open_shift_days := v_open_shift_days + 1;
              v_status := 'حاضر — بانتظار الانصراف';
            else
              v_missing_out := true;
              v_missing_checkout := v_missing_checkout + 1;
              v_status := 'حضور ناقص — لم يسجل الانصراف';
            end if;
          elsif v_daily.id is not null and v_daily.status = 'absent' then
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          elsif v_now_local <= v_shift_end_at then
            v_status := 'بانتظار تسجيل الحضور';
          else
            v_is_due := true;
            v_absent_days := v_absent_days + 1;
            v_status := 'غائب دون إذن';
          end if;

          if v_is_due then
            v_due_days := v_due_days + 1;
          end if;

          if v_daily.id is not null
             and v_daily.first_check_in is null
             and v_daily.status <> 'absent'
             and v_now_local > v_shift_end_at then
            v_missing_in := true;
            v_missing_checkin := v_missing_checkin + 1;
          end if;

          v_total_work_minutes := v_total_work_minutes + coalesce(v_daily.work_minutes, 0);
          v_total_late_minutes := v_total_late_minutes + coalesce(v_daily.late_minutes, 0);
          v_total_early_minutes := v_total_early_minutes + coalesce(v_daily.early_leave_minutes, 0);
          v_total_overtime_minutes := v_total_overtime_minutes + coalesce(v_daily.overtime_minutes, 0);

          -- An open shift is excluded from hours compliance until checkout.
          -- Past days, completed current shifts, and overdue current shifts are
          -- due; approved leave/mission days never enter the denominator.
          if v_daily.last_check_out is not null
             or v_now_local > v_shift_end_at then
            v_total_required_minutes := v_total_required_minutes + v_scheduled_minutes;
            v_compliance_work_minutes :=
              v_compliance_work_minutes + coalesce(v_daily.work_minutes, 0);
          end if;
        end if;
      end if;
    end if;

    v_day_obj := v_day_obj || jsonb_build_object(
      'shiftName', coalesce(v_shift_name, ''),
      'shiftStart', v_shift_start,
      'shiftEnd', v_shift_end,
      'requiredHours', round(v_scheduled_minutes / 60.0, 2),
      'status', v_status,
      'isFuture', v_is_future,
      'isDue', v_is_due,
      'isOpenShift', v_is_open,
      'isCompleted', v_is_completed,
      'isAbsent', (v_status = 'غائب دون إذن'),
      'missingCheckIn', v_missing_in,
      'missingCheckOut', v_missing_out,
      'notes', case
        when v_is_open then 'تم تسجيل الحضور والوردية ما زالت مفتوحة'
        else v_day_obj->>'notes'
      end
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
      'dueScheduledDays', v_due_days,
      'upcomingDays', v_upcoming_days,
      'presentDays', v_present_days,
      'absentDays', v_absent_days,
      'openShiftDays', v_open_shift_days,
      'completedPresenceDays', v_completed_presence_days,
      'totalWorkHours', round(v_total_work_minutes / 60.0, 2),
      'totalRequiredHours', round(v_total_required_minutes / 60.0, 2),
      'averageWorkHours', case when v_completed_presence_days > 0
        then round(v_completed_work_minutes / 60.0 / v_completed_presence_days, 2)
        else 0 end,
      'totalLateMinutes', v_total_late_minutes,
      'totalEarlyLeaveMinutes', v_total_early_minutes,
      'totalOvertimeMinutes', v_total_overtime_minutes,
      'missingCheckInCount', v_missing_checkin,
      'missingCheckOutCount', v_missing_checkout,
      'attendanceRate', case when v_due_days > 0
        then round(v_present_days * 100.0 / v_due_days, 2)
        else 0 end,
      'hoursComplianceAvailable', (v_total_required_minutes > 0),
      'hoursComplianceRate', case when v_total_required_minutes > 0
        then least(100, round(v_compliance_work_minutes * 100.0 / v_total_required_minutes, 2))
        else 0 end
    )
  );

  return v_result;
end
$$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0251: monthly attendance as-of-date semantics; future dates are upcoming, current punches can be open, and rates use due days only.';

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

commit;
