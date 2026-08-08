-- 0110: Ø±Ø¨Ø· Ø§Ø¹ØªÙ…Ø§Ø¯ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ø¨Ø§Ù„Ø­Ø¶ÙˆØ± (0065) â€” Ø§Ø¹ØªÙ…Ø§Ø¯ Ø¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø© ÙŠÙƒØªØ¨
-- attendance_daily.status='on_leave' ÙˆÙŠØ³ØªØ¨Ø¹Ø¯ Ø§Ù„Ù…ÙˆØ¸Ù Ù…Ù† Ø§Ù„ØºÙŠØ§Ø¨ ÙˆØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ†
-- Ø¥Ø°Ù† ÙÙŠ Ù„ÙˆØ­Ø© Ø§Ù„Ø­Ø¶ÙˆØ± ÙˆÙ‚ÙˆØ§Ø¦Ù… drill-down (0294/0295).
-- Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„ÙØ¹Ù„ÙŠ: submit_my_request (0134) Ù„Ù„Ø¹Ø§Ø±Ø¶Ø© â†’ Ø§Ø¹ØªÙ…Ø§Ø¯ ÙÙˆØ±ÙŠ â†’ trigger
-- tg_leave_attendance_on_approval (0065) ÙŠÙˆØ³Ù… Ø§Ù„Ø£ÙŠØ§Ù… â†’ Ø§Ù„Ø­Ø¶ÙˆØ± ÙŠÙ‚Ø±Ø¤Ù‡Ø§ as on_leave.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
set local timezone = 'Africa/Cairo';
select plan(17);

do $fixture$
declare
  v_le      uuid := 'd1200000-0000-4000-8000-000000000001';
  v_dept    uuid := 'd1200000-0000-4000-8000-000000000002';
  v_shift   uuid := 'd1200000-0000-4000-8000-000000000003';
  v_emp_a   uuid := 'd1100000-0000-4000-8000-000000000001'; -- Ø³ÙŠÙ‚Ø¯Ù‘Ù… Ø¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø©
  v_emp_b   uuid := 'd1100000-0000-4000-8000-000000000002'; -- Ø¨Ù„Ø§ Ø¥Ø¬Ø§Ø²Ø©: ØºÙŠØ§Ø¨ Ø¨Ù„Ø§ Ø¹Ø°Ø±
  v_user_a  uuid := 'd1000000-0000-4000-8000-000000000001';
  v_casual  uuid;
  v_day     date := (now() at time zone 'Africa/Cairo')::date;
begin
  perform set_config('app.leave_test_day', to_char(v_day, 'YYYY-MM-DD'), false);

  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0110', 'ÙƒÙŠØ§Ù† 0110');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0110', 'Ø¥Ø¯Ø§Ø±Ø© 0110');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0110', 'ÙˆØ±Ø¯ÙŠØ© 0110', '09:00', '17:00', false, 0, 0, 0, true);

  insert into auth.users(id, email, aud, role)
    values (v_user_a, 'emp-a-0110@test.local', 'authenticated', 'authenticated');
  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, hire_date)
    values
    (v_emp_a, v_user_a, 'E-0110-A', 'Ù…ÙˆØ¸Ù Ø¹Ù„Ù‰ Ø¥Ø¬Ø§Ø²Ø©', v_dept, 'active', true, current_date - 300),
    (v_emp_b, null,     'E-0110-B', 'Ù…ÙˆØ¸Ù ØºØ§Ø¦Ø¨ Ø¨Ù„Ø§ Ø¹Ø°Ø±', v_dept, 'active', true, current_date - 300);
  insert into public.profiles(id, employee_id, status)
    values (v_user_a, v_emp_a, 'active');

  -- ÙƒÙ„Ø§ Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† ØºØ§Ø¦Ø¨ ÙÙŠ Ø§Ù„Ø­Ø¶ÙˆØ± Ø­ØªÙ‰ ÙŠÙØ«Ø¨ÙŽØª ØªØ­ÙˆÙŠÙ„ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ø¥Ù„Ù‰ on_leave.
  insert into public.attendance_daily(employee_id, work_date, shift_id, status)
    values
    (v_emp_a, v_day, v_shift, 'absent'),
    (v_emp_b, v_day, v_shift, 'absent');

  -- Ø±ØµÙŠØ¯ Ø¹Ø§Ø±Ø¶Ø© ÙƒØ§ÙÙ Ø­ØªÙ‰ Ù„Ø§ ÙŠÙØ±ÙØ¶ Ø§Ù„Ø­Ø¬Ø² (0026) Ø£Ø«Ù†Ø§Ø¡ Ø§Ù„ØªÙ‚Ø¯ÙŠÙ…/Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯.
  select id into v_casual from public.leave_types where code = 'casual';
  perform public.ensure_leave_account(v_emp_a, v_casual, extract(year from v_day)::integer);
  perform public.apply_leave_ledger_entry(
    v_emp_a, v_casual, extract(year from v_day)::integer, 'opening', 6,
    'test:open-casual:' || v_emp_a, null, 'Ø±ØµÙŠØ¯ Ø§Ø®ØªØ¨Ø§Ø±ÙŠ Ù„Ù„Ø¹Ø§Ø±Ø¶Ø©');
end $fixture$;

-- =====================================================================
-- Ø¬Ù„Ø³Ø© Ø§Ù„Ù…ÙˆØ¸Ù: ØªÙ‚Ø¯ÙŠÙ… Ø¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø© (ØªÙØ¹ØªÙ…Ø¯ ÙÙˆØ±Ø§Ù‹).
-- =====================================================================
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select set_config(
  'request.jwt.claim.sub',
  'd1000000-0000-4000-8000-000000000001',
  true);

do $submit$
declare
  v_day date := nullif(current_setting('app.leave_test_day', true), '')::date;
  v_req public.requests;
begin
  v_req := public.submit_my_request('leave', 'Ø¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø© 0110', 'Ø¸Ø±Ù Ø¹Ø§Ø¦Ù„ÙŠ Ø·Ø§Ø±Ø¦',
    jsonb_build_object('leaveType', 'casual', 'startDate', v_day, 'endDate', v_day));
  perform set_config('app.leave_test_request', v_req.id::text, false);
end $submit$;

reset role;

-- =====================================================================
-- 1) Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ ÙˆØ§Ù„Ø±Ø¨Ø· Ø¨Ø§Ù„Ø­Ø¶ÙˆØ±.
-- =====================================================================
select is(
  (select status from public.requests
    where id = nullif(current_setting('app.leave_test_request', true), '')::uuid),
  'approved',
  'Ø¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø© ØªÙØ¹ØªÙ…Ø¯ ÙÙˆØ±Ø§Ù‹ Ø¹Ù†Ø¯ Ø§Ù„ØªÙ‚Ø¯ÙŠÙ…');

select ok(
  exists (
    select 1 from public.leave_requests
      where request_id = nullif(current_setting('app.leave_test_request', true), '')::uuid),
  'Ø³Ø·Ø± leave_requests Ø£ÙÙ†Ø´Ø¦ Ù…Ø¹ Ø§Ù„Ø·Ù„Ø¨');

select is(
  (select status from public.attendance_daily
    where employee_id = 'd1100000-0000-4000-8000-000000000001'
      and work_date = nullif(current_setting('app.leave_test_day', true), '')::date),
  'on_leave',
  'Ø§Ø¹ØªÙ…Ø§Ø¯ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© ÙŠØ­ÙˆÙ‘Ù„ ÙŠÙˆÙ… Ø§Ù„Ø­Ø¶ÙˆØ± Ø¥Ù„Ù‰ on_leave');

select is(
  (select status from public.attendance_daily
    where employee_id = 'd1100000-0000-4000-8000-000000000002'
      and work_date = nullif(current_setting('app.leave_test_day', true), '')::date),
  'absent',
  'Ø§Ù„Ù…ÙˆØ¸Ù Ø¨Ù„Ø§ Ø¥Ø¬Ø§Ø²Ø© ÙŠØ¨Ù‚Ù‰ ØºØ§Ø¦Ø¨Ø§Ù‹');

select ok(
  exists (
    select 1 from public.audit_events
      where event_type = 'leave.attendance.marked'),
  'ÙˆØ³Ù… Ø£ÙŠØ§Ù… Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ù…Ø³Ø¬Ù‘Ù„ ÙÙŠ Ø³Ø¬Ù„ Ø§Ù„Ø£Ø­Ø¯Ø§Ø« (audit_events)');

-- =====================================================================
-- 2) Ø§Ù„Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ù…Ù† Ø§Ù„ØºÙŠØ§Ø¨ ÙˆØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ† Ø¥Ø°Ù† ÙÙŠ Ù‚ÙˆØ§Ø¦Ù… drill-down.
-- =====================================================================
select is(
  (public.get_attendance_day_roster(
    nullif(current_setting('app.leave_test_day', true), '')::date, 'absent')->>'total')::int,
  1,
  'Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„ØºÙŠØ§Ø¨ ØªØ¹ØªÙ…Ø¯ Ù…ÙˆØ¸ÙØ§Ù‹ ÙˆØ§Ø­Ø¯Ø§Ù‹ ÙÙ‚Ø· (Ø¨Ù„Ø§ Ø¥Ø¬Ø§Ø²Ø©)');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      public.get_attendance_day_roster(
        nullif(current_setting('app.leave_test_day', true), '')::date, 'absent')->'items') it
      where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000001'),
  'Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø¥Ø¬Ø§Ø²Ø© Ù„Ø§ ÙŠØ¸Ù‡Ø± ÙÙŠ Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„ØºÙŠØ§Ø¨');

select is(
  (public.get_attendance_day_roster(
    nullif(current_setting('app.leave_test_day', true), '')::date, 'unexcused_absent')->>'total')::int,
  1,
  'Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„ØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ† Ø¥Ø°Ù† ØªØ¹ØªÙ…Ø¯ Ù…ÙˆØ¸ÙØ§Ù‹ ÙˆØ§Ø­Ø¯Ø§Ù‹ (Ø¨Ù„Ø§ Ø¥Ø¬Ø§Ø²Ø©)');

select ok(
  not exists (
    select 1 from jsonb_array_elements(
      public.get_attendance_day_roster(
        nullif(current_setting('app.leave_test_day', true), '')::date, 'unexcused_absent')->'items') it
      where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000001'),
  'Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø¥Ø¬Ø§Ø²Ø© Ù„Ø§ ÙŠØ¸Ù‡Ø± ÙÙŠ Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„ØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ† Ø¥Ø°Ù†');

select ok(
  exists (
    select 1 from jsonb_array_elements(
      public.get_attendance_day_roster(
        nullif(current_setting('app.leave_test_day', true), '')::date, 'unexcused_absent')->'items') it
      where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000002'),
  'Ø§Ù„ØºØ§Ø¦Ø¨ Ø¨Ù„Ø§ Ø¹Ø°Ø± ÙŠØ¨Ù‚Ù‰ Ø¶Ù…Ù† Ù‚Ø§Ø¦Ù…Ø© Ø§Ù„ØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ† Ø¥Ø°Ù†');

-- =====================================================================
-- 3) Ù„ÙˆØ­Ø© Ø§Ù„Ø­Ø¶ÙˆØ±: Ø§Ù„Ø¹Ø¯Ø§Ø¯ = Ø§Ù„Ù‚Ø§Ø¦Ù…Ø©ØŒ ÙˆØ§Ù„Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ø³Ø§Ø±Ù.
-- =====================================================================
select is(
  (public.get_attendance_dashboard(
    nullif(current_setting('app.leave_test_day', true), '')::date)->>'absent')::int,
  1,
  'Ù„ÙˆØ­Ø© Ø§Ù„Ø­Ø¶ÙˆØ±: Ø§Ù„ØºÙŠØ§Ø¨ = 1 Ø¨Ø¹Ø¯ Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø©');

select is(
  (public.get_attendance_dashboard(
    nullif(current_setting('app.leave_test_day', true), '')::date)->>'unexcusedAbsent')::int,
  1,
  'Ù„ÙˆØ­Ø© Ø§Ù„Ø­Ø¶ÙˆØ±: ØºÙŠØ§Ø¨ Ø¨Ø¯ÙˆÙ† Ø¥Ø°Ù† = 1 (Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ø§Ù„Ù…Ø¹ØªÙ…Ø¯Ø© Ù„Ø§ ØªÙØ¹Ø¯Ù‘ Ø¨Ù„Ø§ Ø¹Ø°Ø±)');

select ok(
  (public.get_attendance_dashboard(
    nullif(current_setting('app.leave_test_day', true), '')::date)->>'scheduled')::int >= 2,
  'Ø§Ù„Ù…Ø¬Ø¯ÙˆÙ„ÙˆÙ† ÙŠØ´Ù…Ù„ÙˆÙ† ÙƒÙ„ Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† Ø§Ù„Ù†Ø´Ø·ÙŠÙ† (Ù„Ø§ ÙŠØªØºÙŠØ± Ø¨Ø§Ù„Ø§Ø³ØªØ¨Ø¹Ø§Ø¯)');

-- =====================================================================
-- 4) Ø¥Ø«Ø±Ø§Ø¡ ØµÙ drill-down: Ø¹Ù„Ù… Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ø§Ù„Ù…Ø¯ÙÙˆØ¹Ø© ÙˆØ§Ù„Ø±Ù…Ø² ÙˆØ§Ù„Ø­Ø§Ù„Ø©.
-- =====================================================================
select is(
  (select it->>'hasApprovedLeave'
     from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.leave_test_day', true), '')::date, 'scheduled')->'items') it
     where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000001'),
  'true',
  'ØµÙ Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© ÙŠØ­Ù…Ù„ hasApprovedLeave=true');

select is(
  (select it->>'leaveCode'
     from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.leave_test_day', true), '')::date, 'scheduled')->'items') it
     where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000001'),
  'casual',
  'ØµÙ Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© ÙŠØ­Ù…Ù„ leaveCode=casual');

select is(
  (select it->>'status'
     from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.leave_test_day', true), '')::date, 'scheduled')->'items') it
     where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000001'),
  'on_leave',
  'ØµÙ Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© ÙŠØ­Ù…Ù„ status=on_leave');

select is(
  (select it->>'status'
     from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.leave_test_day', true), '')::date, 'scheduled')->'items') it
     where it->>'employeeId' = 'd1100000-0000-4000-8000-000000000002'),
  'absent',
  'ØµÙ Ø§Ù„ØºØ§Ø¦Ø¨ Ø¨Ù„Ø§ Ø¹Ø°Ø± ÙŠØ­Ù…Ù„ status=absent');

select * from finish();
rollback;

