begin;

-- Final monthly-rate contract:
--   attendance = every scheduled day that has a check-in / every scheduled
--                work day in the selected month (Friday excluded upstream).
--   hours      = completed punch-to-punch minutes / all required month minutes.
-- An open shift therefore counts as attendance, but contributes zero minutes
-- until checkout. Future days remain in the denominators and are never absence.

do $rename$
begin
  if to_regprocedure('public._build_attendance_statement_v287(uuid,integer,integer)') is null then
    alter function public._build_attendance_statement(uuid, integer, integer)
      rename to _build_attendance_statement_v287;
  end if;
end
$rename$;

revoke execute on function public._build_attendance_statement_v287(uuid, integer, integer)
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
  v_summary jsonb;
  v_scheduled_days integer;
  v_present_days integer;
  v_open_shift_days integer;
  v_required_minutes integer;
  v_worked_minutes integer;
  v_deficit_minutes integer;
  v_days jsonb := '[]'::jsonb;
  v_day_obj jsonb;
  v_day date;
  v_override public.attendance_day_overrides%rowtype;
  v_reversed_absence_days integer := 0;
begin
  v_result := public._build_attendance_statement_v287(p_employee_id, p_year, p_month);
  v_summary := coalesce(v_result->'summary', '{}'::jsonb);

  -- Keep explicit administrative punch clearing visible in the returned JSON.
  -- Also do not label today absent before the assigned shift has ended.
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_day := (v_day_obj->>'date')::date;
    select * into v_override
    from public.attendance_day_overrides o
    where o.employee_id = p_employee_id
      and o.work_date = v_day
      and o.is_active;

    if found and v_override.clear_check_in then
      v_day_obj := v_day_obj || jsonb_build_object('checkIn', null);
    end if;
    if found and v_override.clear_check_out then
      v_day_obj := v_day_obj || jsonb_build_object('checkOut', null);
    end if;

    if v_day = (now() at time zone 'Africa/Cairo')::date
       and coalesce((v_day_obj->>'isAbsent')::boolean, false)
       and nullif(v_day_obj->>'checkIn', '') is null
       and nullif(v_day_obj->>'shiftEnd', '') is not null
       and (now() at time zone 'Africa/Cairo')::time
         <= (v_day_obj->>'shiftEnd')::time then
      v_day_obj := v_day_obj || jsonb_build_object(
        'isAbsent', false,
        'isDue', false,
        'missingCheckIn', false,
        'missingCheckOut', false,
        'status', 'بانتظار الحضور'
      );
      v_reversed_absence_days := v_reversed_absence_days + 1;
    end if;

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  if v_reversed_absence_days > 0 then
    v_summary := v_summary || jsonb_build_object(
      'absentDays', greatest(0,
        coalesce((v_summary->>'absentDays')::integer, 0) - v_reversed_absence_days),
      'dueScheduledDays', greatest(0,
        coalesce((v_summary->>'dueScheduledDays')::integer, 0) - v_reversed_absence_days)
    );
  end if;

  v_scheduled_days := greatest(0, coalesce((v_summary->>'scheduledDays')::integer, 0));
  v_present_days := greatest(0, coalesce((v_summary->>'presentDays')::integer, 0));
  v_open_shift_days := greatest(0, coalesce((v_summary->>'openShiftDays')::integer, 0));
  v_required_minutes := greatest(0, coalesce(
    (v_summary->'hoursRateBasis'->>'requiredMinutes')::integer,
    (v_summary->>'requiredMinutes')::integer,
    round(coalesce((v_summary->>'totalRequiredHours')::numeric, 0) * 60)::integer,
    0
  ));
  v_worked_minutes := greatest(0, coalesce(
    (v_summary->'hoursRateBasis'->>'workedMinutes')::integer,
    (v_summary->>'compliantWorkMinutes')::integer,
    round(coalesce((v_summary->>'totalWorkHours')::numeric, 0) * 60)::integer,
    0
  ));
  v_deficit_minutes := greatest(0, v_required_minutes - v_worked_minutes);

  v_summary := v_summary || jsonb_build_object(
    'attendanceRate', case when v_scheduled_days > 0
      then round(least(v_present_days, v_scheduled_days) * 100.0 / v_scheduled_days, 2)
      else 0
    end,
    'attendanceRateBasis', coalesce(v_summary->'attendanceRateBasis', '{}'::jsonb)
      || jsonb_build_object(
        'presentInDue', least(v_present_days, v_scheduled_days),
        'dueDays', v_scheduled_days,
        'presentDays', v_present_days,
        'openShiftDays', v_open_shift_days,
        'basis', 'full_month_scheduled_days'
      ),
    'hoursComplianceRate', case when v_required_minutes > 0
      then least(100, round(v_worked_minutes * 100.0 / v_required_minutes, 2))
      else 0
    end,
    'totalDeficitMinutes', v_deficit_minutes,
    'hoursRateBasis', coalesce(v_summary->'hoursRateBasis', '{}'::jsonb)
      || jsonb_build_object(
        'workedMinutes', v_worked_minutes,
        'requiredMinutes', v_required_minutes,
        'scheduledDays', v_scheduled_days,
        'deficitMinutes', v_deficit_minutes,
        'basis', 'full_month_required_minutes'
      )
  );

  return v_result || jsonb_build_object('days', v_days, 'summary', v_summary);
end
$$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  'Monthly statement using full-month attendance and required-hour denominators; open shifts count as attendance only.';

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

commit;
