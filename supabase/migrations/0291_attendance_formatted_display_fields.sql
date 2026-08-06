-- 0287: Add formatted display fields to the monthly statement.
--
-- The backend already returns raw numbers (totalWorkHours, totalRequiredHours,
-- checkIn, checkOut, etc.). This migration wraps the latest builder to add
-- human-friendly formatted fields so the UI can display them directly:
--
--   summary.totalWorkHoursFormatted   → '200 س و 40 د'
--   summary.totalRequiredHoursFormatted → '208 س'
--   summary.totalDeficitFormatted     → '7 س و 20 د'
--   summary.totalOvertimeFormatted    → '0 س'
--   per-day checkIn12 / checkOut12    → '10:00 ص' / '06:39 م'
--   per-day workHoursFormatted        → '7 س و 40 د'
--
-- This keeps raw numeric fields intact for charts/CSV and adds display strings.

begin;

do $rename$
begin
  if to_regprocedure('public._build_attendance_statement_v286(uuid,integer,integer)') is null then
    alter function public._build_attendance_statement(uuid, integer, integer)
      rename to _build_attendance_statement_v286;
  end if;
end
$rename$;

revoke execute on function public._build_attendance_statement_v286(uuid, integer, integer)
  from public, anon, authenticated;

-- Helper: format minutes into "X س و Y د"
create or replace function public._fmt_minutes_ar(p_minutes integer)
returns text
language sql immutable
as $$
  select case
    when p_minutes is null or p_minutes < 0 then '—'
    when p_minutes = 0 then '0 د'
    when p_minutes < 60 then p_minutes || ' د'
    when p_minutes % 60 = 0 then (p_minutes / 60) || ' س'
    else (p_minutes / 60) || ' س و ' || (p_minutes % 60) || ' د'
  end;
$$;

-- Helper: format time (HH24:MI) into 12h Arabic "10:00 ص" / "06:39 م"
create or replace function public._fmt_time_12h(p_time time)
returns text
language sql immutable
as $$
  select case
    when p_time is null then null
    when extract(hour from p_time) = 0
      then lpad((12)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' ص'
    when extract(hour from p_time) < 12
      then lpad(extract(hour from p_time)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' ص'
    when extract(hour from p_time) = 12
      then '12:' || lpad(extract(minute from p_time)::text, 2, '0') || ' م'
    else lpad((extract(hour from p_time) - 12)::text, 2, '0') || ':' || lpad(extract(minute from p_time)::text, 2, '0') || ' م'
  end;
$$;

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
begin
  v_result := public._build_attendance_statement_v286(p_employee_id, p_year, p_month);

  -- Add formatted fields to each day
  for v_day_obj in select value from jsonb_array_elements(v_result->'days')
  loop
    v_ci := v_day_obj->>'checkIn';
    v_co := v_day_obj->>'checkOut';

    v_day_obj := v_day_obj || jsonb_build_object(
      'checkIn12',  case when v_ci is not null and v_ci <> '' then public._fmt_time_12h(v_ci::time) else null end,
      'checkOut12', case when v_co is not null and v_co <> '' then public._fmt_time_12h(v_co::time) else null end,
      'workHoursFormatted', public._fmt_minutes_ar(
        greatest(0, round(coalesce((v_day_obj->>'workHours')::numeric, 0) * 60))::integer
      )
    );

    v_days := v_days || jsonb_build_array(v_day_obj);
  end loop;

  -- Add formatted fields to summary
  v_result := v_result || jsonb_build_object(
    'days', v_days,
    'summary', (v_result->'summary') || jsonb_build_object(
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

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0287: formatted display fields (Arabic hours, 12h time) on top of v286 logic.';

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

commit;
