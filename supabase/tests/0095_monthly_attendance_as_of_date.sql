-- 0095: current-month attendance never treats the future as absence and
-- reports an open current shift without a phantom missing-checkout warning.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(16);

do $fixture$
declare
  v_le uuid := 'f9500000-0000-4000-8000-000000000000';
  v_dept uuid := 'f9500000-0000-4000-8000-000000000001';
  v_emp uuid := 'f9500000-0000-4000-8000-000000000010';
  v_overnight_emp uuid := 'f9500000-0000-4000-8000-000000000011';
  v_shift uuid := 'f9500000-0000-4000-8000-000000000020';
  v_overnight_shift uuid := 'f9500000-0000-4000-8000-000000000021';
  v_leave_type uuid := 'f9500000-0000-4000-8000-000000000030';
  v_leave_request uuid := 'f9500000-0000-4000-8000-000000000040';
  v_leave_day date := case
    when extract(isodow from current_date - 7) = 5 then current_date - 6
    else current_date - 7
  end;
  v_local timestamp := now() at time zone 'Africa/Cairo';
  v_start time := (v_local - interval '1 hour')::time;
  v_end time := (v_local + interval '2 hours')::time;
  v_overnight_end time := (v_local + interval '2 hours')::time;
begin
  insert into public.legal_entities(id, code, name)
    values(v_le, 'ATT-ASOF', 'كيان اختبار الحضور الحالي');
  insert into public.departments(id, legal_entity_id, code, name)
    values(v_dept, v_le, 'ATT-ASOF-D', 'إدارة اختبار الحضور الحالي');
  insert into public.employees(
    id, employee_code, full_name_ar, department_id, status, is_active,
    birth_date, hire_date
  ) values(
    v_emp, 'ATT-ASOF-001', 'موظف اختبار الحضور الحالي', v_dept, 'active', true,
    '1990-01-01', '2020-01-01'
  );
  insert into public.employees(
    id, employee_code, full_name_ar, department_id, status, is_active,
    birth_date, hire_date
  ) values(
    v_overnight_emp, 'ATT-ASOF-002', 'موظف اختبار الوردية الليلية',
    v_dept, 'active', true, '1991-01-01', '2020-01-01'
  );
  insert into public.shifts(
    id, code, name, start_time, end_time, crosses_midnight,
    break_minutes, grace_in_minutes, grace_out_minutes, is_active
  ) values(
    v_shift, 'ATT-ASOF-SHIFT', 'وردية اختبار مفتوحة', v_start, v_end,
    v_end <= v_start, 0, 0, 15, true
  );
  insert into public.shifts(
    id, code, name, start_time, end_time, crosses_midnight,
    break_minutes, grace_in_minutes, grace_out_minutes, is_active
  ) values(
    v_overnight_shift, 'ATT-ASOF-NIGHT', 'وردية ليلية مفتوحة',
    '23:00', v_overnight_end, true, 0, 0, 15, true
  );
  insert into public.shift_assignments(
    employee_id, shift_id, effective_from, effective_to, is_active
  ) values(v_emp, v_shift, date_trunc('month', v_leave_day)::date, null, true);
  insert into public.shift_assignments(
    employee_id, shift_id, effective_from, effective_to, is_active
  ) values(
    v_overnight_emp, v_overnight_shift, current_date - 1, null, true
  );

  insert into public.leave_types(id, code, name_ar, affects_balance)
    values(v_leave_type, 'ATT-ASOF-LT', 'إجازة اختبار الحضور الحالي', false);
  insert into public.requests(
    id, request_type, employee_id, title, status, workflow_status
  ) values(
    v_leave_request, 'leave', v_emp, 'إجازة مستثناة من مقام الحضور',
    'approved', 'completed'
  );
  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date, days_count
  ) values(
    v_leave_request, v_emp, v_leave_type, v_leave_day, v_leave_day, 1
  );

  if extract(isodow from current_date) <> 5 then
    insert into public.attendance_daily(
      employee_id, work_date, shift_id, first_check_in, status, work_minutes
    ) values(v_emp, current_date, v_shift, now() - interval '1 hour', 'present', 0);

    insert into public.attendance_corrections(
      employee_id, attendance_daily_id, work_date, correction_type,
      reason, status
    )
    select
      v_emp, ad.id, current_date, 'wrong_time',
      'تصحيح معتمد لا يجب أن يخفي الوردية المفتوحة', 'approved'
    from public.attendance_daily ad
    where ad.employee_id = v_emp and ad.work_date = current_date;
  end if;

  if extract(isodow from current_date - 1) <> 5 then
    insert into public.attendance_daily(
      employee_id, work_date, shift_id, first_check_in, status, work_minutes
    ) values(
      v_overnight_emp,
      current_date - 1,
      v_overnight_shift,
      ((current_date - 1 + time '23:05') at time zone 'Africa/Cairo'),
      'present',
      0
    );
  end if;
end
$fixture$;

select ok(
  public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000010',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary' ? 'dueScheduledDays',
  'summary exposes dueScheduledDays'
);

select ok(
  public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000010',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary' ? 'upcomingDays',
  'summary exposes upcomingDays'
);

select is(
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date > current_date
     and d->>'status' = 'غائب دون إذن'),
  0,
  'future dates are never shown as unauthorized absence'
);

select is(
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date > current_date
     and coalesce((d->>'isAbsent')::boolean, false)),
  0,
  'future dates never carry isAbsent=true'
);

select is(
  (public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000010',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'upcomingDays')::integer,
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where coalesce((d->>'isFuture')::boolean, false)),
  'upcomingDays equals future scheduled rows'
);

select ok(
  extract(isodow from current_date) = 5 or
  (select d->>'status' = 'حاضر — بانتظار الانصراف'
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date = current_date),
  'an active current shift is shown as waiting for checkout'
);

select ok(
  extract(isodow from current_date) = 5 or not
  (select coalesce((d->>'missingCheckOut')::boolean, false)
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date = current_date),
  'an active current shift has no premature missing-checkout warning'
);

select ok(
  extract(isodow from current_date) = 5 or
  (select (d->>'requiredHours')::numeric > 0
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where (d->>'date')::date = current_date),
  'shift assignment supplies required hours when attendance_daily is sparse'
);

select is(
  (public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000010',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'attendanceRate')::numeric,
  case
    when (public._build_attendance_statement(
      'f9500000-0000-4000-8000-000000000010',
      extract(year from current_date)::integer,
      extract(month from current_date)::integer
    )->'summary'->>'dueScheduledDays')::integer > 0
    then round(
      coalesce(
        (public._build_attendance_statement(
          'f9500000-0000-4000-8000-000000000010',
          extract(year from current_date)::integer,
          extract(month from current_date)::integer
        )->'summary'->'attendanceRateBasis'->>'presentInDue')::numeric,
        (
          (public._build_attendance_statement(
            'f9500000-0000-4000-8000-000000000010',
            extract(year from current_date)::integer,
            extract(month from current_date)::integer
          )->'summary'->>'presentDays')::numeric
          -
          (public._build_attendance_statement(
            'f9500000-0000-4000-8000-000000000010',
            extract(year from current_date)::integer,
            extract(month from current_date)::integer
          )->'summary'->>'openShiftDays')::numeric
        )
      ) * 100 /
      (public._build_attendance_statement(
        'f9500000-0000-4000-8000-000000000010',
        extract(year from current_date)::integer,
        extract(month from current_date)::integer
      )->'summary'->>'dueScheduledDays')::numeric,
      2
    )
    else 0::numeric
  end,
  'attendanceRate uses closed due days and excludes an open shift'
);

select is(
  (public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000010',
    extract(year from current_date)::integer,
    extract(month from current_date)::integer
  )->'summary'->>'dueScheduledDays')::integer,
  (select count(*)::integer
   from jsonb_array_elements(public._build_attendance_statement(
     'f9500000-0000-4000-8000-000000000010',
     extract(year from current_date)::integer,
     extract(month from current_date)::integer
   )->'days') d
   where coalesce((d->>'isDue')::boolean, false)),
  'dueScheduledDays equals rows whose attendance is actually due'
);

select ok(
  not coalesce((
    select (d->>'isDue')::boolean
    from jsonb_array_elements(public._build_attendance_statement(
      'f9500000-0000-4000-8000-000000000010',
      extract(year from (case
        when extract(isodow from current_date - 7) = 5 then current_date - 6
        else current_date - 7
      end))::integer,
      extract(month from (case
        when extract(isodow from current_date - 7) = 5 then current_date - 6
        else current_date - 7
      end))::integer
    )->'days') d
    where (d->>'date')::date = (case
      when extract(isodow from current_date - 7) = 5 then current_date - 6
      else current_date - 7
    end)
  ), true),
  'approved leave is excluded from due attendance days'
);

select ok(
  has_function_privilege(
    'service_role',
    'public._build_attendance_statement(uuid,integer,integer)',
    'EXECUTE'
  ),
  'service_role retains access to the private statement builder'
);

select ok(
  extract(isodow from current_date - 1) = 5
  or (now() at time zone 'Africa/Cairo')::time > time '21:00'
  or coalesce((
    select (d->>'isOpenShift')::boolean
    from jsonb_array_elements(public._build_attendance_statement(
      'f9500000-0000-4000-8000-000000000011',
      extract(year from current_date - 1)::integer,
      extract(month from current_date - 1)::integer
    )->'days') d
    where (d->>'date')::date = current_date - 1
  ), false),
  'a prior-day cross-midnight shift remains open until its effective end'
);

select ok(
  extract(isodow from current_date - 1) = 5
  or (now() at time zone 'Africa/Cairo')::time > time '21:00'
  or not coalesce((
    select (d->>'missingCheckOut')::boolean
    from jsonb_array_elements(public._build_attendance_statement(
      'f9500000-0000-4000-8000-000000000011',
      extract(year from current_date - 1)::integer,
      extract(month from current_date - 1)::integer
    )->'days') d
    where (d->>'date')::date = current_date - 1
  ), true),
  'an open cross-midnight shift has no premature missing-checkout warning'
);

select ok(
  extract(isodow from current_date - 1) = 5
  or (now() at time zone 'Africa/Cairo')::time > time '21:00'
  or
  (public._build_attendance_statement(
    'f9500000-0000-4000-8000-000000000011',
    extract(year from current_date - 1)::integer,
    extract(month from current_date - 1)::integer
  )->'summary'->>'openShiftDays')::integer >= 1,
  'openShiftDays includes an active cross-midnight shift'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public._build_attendance_statement_v186(uuid,integer,integer)',
    'EXECUTE'
  ),
  'legacy builder stays private'
);

select * from finish();
rollback;
