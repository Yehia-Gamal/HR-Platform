begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(12);

do $fixture$
declare
  v_le uuid := 'fa060000-0000-4000-8000-000000000001';
  v_dept uuid := 'fa060000-0000-4000-8000-000000000002';
  v_emp uuid := 'fa060000-0000-4000-8000-000000000003';
  v_shift uuid := 'fa060000-0000-4000-8000-000000000004';
  v_month date := date_trunc('month', current_date)::date;
  v_open_day date;
  v_closed_day date;
begin
  select d::date into v_open_day
  from generate_series(v_month, current_date, interval '1 day') d
  where extract(isodow from d) <> 5
  order by d desc limit 1;

  select d::date into v_closed_day
  from generate_series(v_month, current_date, interval '1 day') d
  where extract(isodow from d) <> 5 and d::date <> v_open_day
  order by d desc limit 1;

  insert into public.legal_entities(id, code, name)
    values(v_le, 'ATT-FULL-MONTH', 'Full month attendance test');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_le, 'ATT-FULL-MONTH-D', 'Full month attendance department');
  insert into public.employees(
    id, employee_code, full_name_ar, department_id, status, is_active,
    birth_date, hire_date
  ) values(
    v_emp, 'ATT-FULL-MONTH-001', 'موظف اختبار النسبة الشهرية', v_dept,
    'active', true, '1990-01-01', v_month
  );
  insert into public.shifts(
    id, code, name, start_time, end_time, crosses_midnight,
    break_minutes, grace_in_minutes, grace_out_minutes, is_active
  ) values(
    v_shift, 'ATT-FULL-MONTH-S', 'وردية عشر إلى ست', '10:00', '18:00',
    false, 0, 0, 0, true
  );
  insert into public.shift_assignments(
    employee_id, shift_id, effective_from, effective_to, is_active
  ) values(v_emp, v_shift, v_month, null, true);

  -- One completed 8-hour day and one open day. The open day must count as
  -- attendance, but it must not add manufactured work minutes.
  insert into public.attendance_daily(
    employee_id, work_date, shift_id, first_check_in, last_check_out,
    status, work_minutes
  ) values(
    v_emp, v_closed_day, v_shift,
    (v_closed_day + time '09:00') at time zone 'Africa/Cairo',
    (v_closed_day + time '17:00') at time zone 'Africa/Cairo',
    'present', 480
  );
  insert into public.attendance_daily(
    employee_id, work_date, shift_id, first_check_in, status, work_minutes
  ) values(
    v_emp, v_open_day, v_shift,
    (v_open_day + time '10:00') at time zone 'Africa/Cairo',
    'present', 0
  );
end
$fixture$;

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::integer,
  (select count(*)::integer
   from generate_series(date_trunc('month', current_date)::date,
     (date_trunc('month', current_date) + interval '1 month - 1 day')::date,
     interval '1 day') d
   where extract(isodow from d) <> 5),
  'Friday is the only weekly rest day in the full-month denominator'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->'attendanceRateBasis'->>'dueDays')::integer,
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::integer,
  'attendance denominator is all scheduled days in the selected month'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->'attendanceRateBasis'->>'presentInDue')::integer,
  2,
  'completed and open check-ins both count as attendance days'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'attendanceRate')::numeric,
  round(200.0 / (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::numeric, 2),
  'attendance rate is check-in days divided by the full work month'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->'hoursRateBasis'->>'workedMinutes')::integer,
  480,
  'open shift contributes no work minutes before checkout'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->'hoursRateBasis'->>'requiredMinutes')::integer,
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::integer * 480,
  'required minutes cover every 8-hour work day in the month'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'hoursComplianceRate')::numeric,
  round(100.0 / (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::numeric, 2),
  'hours rate is completed minutes divided by full-month required minutes'
);

select is(
  (public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'totalDeficitMinutes')::integer,
  ((public._build_attendance_statement(
    'fa060000-0000-4000-8000-000000000003',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'scheduledDays')::integer * 480) - 480,
  'monthly deficit is total required minutes minus completed work minutes'
);

select is(
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'fa060000-0000-4000-8000-000000000003',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date > current_date
     and coalesce((d->>'isAbsent')::boolean, false)),
  0,
  'future work days remain non-absent'
);

select is(
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'fa060000-0000-4000-8000-000000000003',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where coalesce((d->>'isOpenShift')::boolean, false)),
  1,
  'open punch remains visible as waiting for checkout'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public._build_attendance_statement_v287(uuid,integer,integer)',
    'EXECUTE'
  ),
  'wrapped statement builder stays private'
);

select ok(
  has_function_privilege(
    'service_role',
    'public._build_attendance_statement(uuid,integer,integer)',
    'EXECUTE'
  ),
  'service role retains access to the final statement builder'
);

select * from finish();
rollback;
