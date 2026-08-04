-- 0266: Full-month attendance/hour rates + audited administrative day overrides.
--
-- Business rules:
--   * Friday is the only weekly rest day.
--   * The official shift is 10:00-18:00 (8 hours); the effective assigned
--     shift remains the dynamic source for per-day required hours.
--   * Attendance rate = days with a check-in / all scheduled work days in the
--     selected month. Future days remain in the denominator, never as absence.
--   * Hours rate = completed worked minutes / all required minutes in the
--     selected month. Open shifts never manufacture worked minutes.
--   * Early arrival / early departure is not a violation by itself. The daily
--     duration is what matters; monthly hour deficit is reported explicitly.
--   * Raw punches stay immutable. Admin edits are stored as audited overrides.

begin;

create table if not exists public.attendance_day_overrides (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date date not null,
  day_type text not null default 'work'
    check (day_type in ('work','leave','mission','convoy','fundraising','holiday','rest','absent')),
  check_in_override time,
  check_out_override time,
  clear_check_in boolean not null default false,
  clear_check_out boolean not null default false,
  reason text not null,
  notes text,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint attendance_day_overrides_employee_date_uq unique(employee_id, work_date),
  constraint attendance_day_overrides_reason_chk check (length(btrim(reason)) >= 5),
  constraint attendance_day_overrides_check_in_mode_chk
    check (not (clear_check_in and check_in_override is not null)),
  constraint attendance_day_overrides_check_out_mode_chk
    check (not (clear_check_out and check_out_override is not null))
);

comment on table public.attendance_day_overrides is
  'Audited effective-day overrides. Raw attendance_events and attendance_daily punches are preserved.';

create index if not exists ix_attendance_day_overrides_employee_month
  on public.attendance_day_overrides(employee_id, work_date)
  where is_active;

alter table public.attendance_day_overrides enable row level security;
revoke all on table public.attendance_day_overrides from public, anon, authenticated;
grant select on table public.attendance_day_overrides to service_role;

drop policy if exists attendance_day_overrides_service_role on public.attendance_day_overrides;
create policy attendance_day_overrides_service_role
  on public.attendance_day_overrides
  for all to service_role
  using (true)
  with check (true);

create or replace function public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time default null,
  p_check_out time default null,
  p_clear_check_in boolean default false,
  p_clear_check_out boolean default false,
  p_reason text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_clear_check_in and p_check_in is not null then
    raise exception 'CHECK_IN_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if p_clear_check_out and p_check_out is not null then
    raise exception 'CHECK_OUT_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning id into v_id;

  perform public.log_audit_event(
    'attendance.day.override.saved', 'workflow', 'warning',
    'attendance_day_overrides', v_id,
    'تعديل إداري ليوم حضور', p_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'previous', v_previous,
      'dayType', p_day_type,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'clearCheckIn', coalesce(p_clear_check_in, false),
      'clearCheckOut', coalesce(p_clear_check_out, false)
    )
  );

  return jsonb_build_object('ok', true, 'id', v_id, 'employeeId', p_employee_id, 'workDate', p_work_date);
end
$$;

revoke all on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text)
  from public, anon;
grant execute on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text)
  to authenticated, service_role;

do $rename$
begin
  if to_regprocedure('public._build_attendance_statement_v266(uuid,integer,integer)') is null then
    alter function public._build_attendance_statement(uuid, integer, integer)
      rename to _build_attendance_statement_v266;
  end if;
end
$rename$;

revoke execute on function public._build_attendance_statement_v266(uuid, integer, integer)
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

    -- Friday and official holidays are not monthly work days.
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

    if v_scheduled then
      v_scheduled_days := v_scheduled_days + 1;
      v_month_required_minutes := v_month_required_minutes + v_required_minutes;
      if v_present then v_present_days := v_present_days + 1; end if;
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

    -- Flexible duration policy: no late/early penalty when duration is what matters.
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
      'isOpenShift', (v_check_in is not null and v_check_out is null and not v_is_future),
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
        'reason', v_override.reason,
        'notes', v_override.notes,
        'updatedAt', v_override.updated_at
      ) end,
      'status', case
        when extract(isodow from v_day) = 5 then 'راحة أسبوعية'
        when v_type = 'holiday' then 'عطلة رسمية'
        when v_type = 'rest' then 'راحة أسبوعية'
        when v_type = 'leave' then 'إجازة معتمدة'
        when v_type = 'mission' then 'مأمورية'
        when v_type = 'convoy' then 'قافلة'
        when v_type = 'fundraising' then 'فاندي'
        when v_type = 'absent' then 'غائب دون إذن'
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
      'dueScheduledDays', v_scheduled_days,
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
      'attendanceRate', case when v_scheduled_days > 0 then round(v_present_days * 100.0 / v_scheduled_days, 2) else 0 end,
      'attendanceRateBasis', jsonb_build_object(
        'presentInDue', v_present_days,
        'dueDays', v_scheduled_days,
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
end
$$;

comment on function public._build_attendance_statement(uuid, integer, integer) is
  '0266: full-month attendance and hour denominators, flexible duration, audited day overrides.';

revoke execute on function public._build_attendance_statement(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public._build_attendance_statement(uuid, integer, integer)
  to service_role;

commit;
