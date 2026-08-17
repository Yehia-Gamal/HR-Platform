-- 0355: Ù„ÙˆØ­Ø© Ø§Ù„Ø­Ø¶ÙˆØ± ØªØ­ØµÙŠ ÙƒÙ„ Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† Ø§Ù„Ù†Ø´Ø·ÙŠÙ† (Ø§Ø´ØªÙ‚Ø§Ù‚ Ø¨Ø¯Ù„ ØµÙÙˆÙ attendance_daily
-- ÙÙ‚Ø·) + Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ ÙŠÙ†Ø´Ø¦ Ø·Ù„Ø¨Ù‹Ø§ Ù…Ø¹ØªÙ…Ø¯Ù‹Ø§ ÙˆÙŠØ®ØµÙ… Ø±ØµÙŠØ¯ Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© (Migration 0355).
--
-- ÙŠØºØ·ÙŠ:
--   (1) get_attendance_dashboard: no-show ÙŠÙØ¹Ø¯ ØºØ§Ø¦Ø¨Ù‹Ø§ØŒ ÙˆÙØ¦Ø§Øª on_leave/on_mission/
--       missing_checkout Ø§Ø´ØªÙ‚Ø§Ù‚ÙŠØ© Ø¬Ø¯ÙŠØ¯Ø©.
--   (2) get_attendance_day_roster: ÙØ¦Ø§Øª on_leave/on_mission/missing_checkout.
--   (3) set_employee_attendance_day_admin: p_leave_type + Ø·Ù„Ø¨ Ù…Ø¹ØªÙ…Ø¯ + Ø®ØµÙ… Ø±ØµÙŠØ¯ØŒ
--       Ø§Ù„Ø§ÙØªØ±Ø§Ø¶ÙŠ (ØºÙŠØ§Ø¨ â† unpaid)ØŒ Ø±ÙØ¶ Ø§Ù„Ù†ÙˆØ¹ ØºÙŠØ± Ø§Ù„Ù…Ø¯Ø¹ÙˆÙ…ØŒ ÙˆØ§Ù„Ø±ÙØ¶ Ù„ØºÙŠØ± Ø§Ù„Ù…ØµØ±Ø­.
--   (4) Ø³Ù‚ÙˆØ· Ø§Ù„ØªÙˆÙ‚ÙŠØ¹ Ø§Ù„Ù‚Ø¯ÙŠÙ… (9 Ø¨Ø§Ø±Ø§Ù…ØªØ±Ø§Øª) Ø­ØªÙ‰ Ù„Ø§ ÙŠÙØªØ¬Ø§ÙˆØ² Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¬Ø¯ÙŠØ¯.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(29);

-- =====================================================================
-- Fixture: ÙƒÙŠØ§Ù† + Ø¥Ø¯Ø§Ø±Ø© + ÙˆØ±Ø¯ÙŠØ© + 10 Ù…ÙˆØ¸ÙÙŠÙ† (6 Ù†Ø´Ø·ÙŠÙ† Ù„Ù„Ø§Ø´ØªÙ‚Ø§Ù‚ + Ø£Ù‡Ø¯Ø§Ù Ø¥Ø¯Ø§Ø±ÙŠØ©).
-- =====================================================================
do $fixture$
declare
  v_le      uuid := 'd3550000-0000-4000-8000-000000000001';
  v_dept    uuid := 'd3550000-0000-4000-8000-000000000002';
  v_shift   uuid := 'd3550000-0000-4000-8000-000000000003';
  v_day     date := '2026-08-03'; -- Ø§Ø«Ù†ÙŠÙ† (Ù„ÙŠØ³ Ø§Ù„Ø¬Ù…Ø¹Ø©/Ø§Ù„Ø¹Ø·Ù„Ø©)
  v_annual  uuid;
  v_unpaid  uuid;
  v_admin_role uuid;
begin
  perform set_config('app.t0355_day', to_char(v_day, 'YYYY-MM-DD'), false);

  insert into public.legal_entities(id, code, name)
    values (v_le, 'LE-0355', 'ÙƒÙŠØ§Ù† 0355');
  insert into public.departments(id, legal_entity_id, code, name)
    values (v_dept, v_le, 'D-0355', 'Ø¥Ø¯Ø§Ø±Ø© 0355');
  insert into public.shifts(id, code, name, start_time, end_time,
    crosses_midnight, break_minutes, grace_in_minutes, grace_out_minutes, is_active)
    values (v_shift, 'S-0355', 'ÙˆØ±Ø¯ÙŠØ© 0355', '09:00', '17:00', false, 0, 0, 0, true);

  -- Ø§Ù„Ù…ÙˆØ¸ÙÙˆÙ† Ø§Ù„Ù†Ø´Ø·ÙˆÙ† (6) â€” Ù…Ø±Ø´Ø­Ùˆ Ø§Ù„Ø§Ø´ØªÙ‚Ø§Ù‚ ÙÙŠ Ø§Ù„Ù„ÙˆØ­Ø© ÙˆØ§Ù„Ø±Ø³ØªØ±.
  insert into public.employees(id, employee_code, full_name_ar, department_id,
    status, is_active, hire_date)
  values
    ('d3550000-0000-4000-8000-000000000010', 'E-355-P',  'Ø­Ø§Ø¶Ø± Ø¨Ø¨ØµÙ…ØªÙŠÙ†',    v_dept, 'active', true, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000011', 'E-355-L',  'Ù…ØªØ£Ø®Ø± 15 Ø¯Ù‚ÙŠÙ‚Ø©',  v_dept, 'active', true, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000012', 'E-355-MK', 'Ø¨ØµÙ…Ø© Ø¨Ù„Ø§ Ø§Ù†ØµØ±Ø§Ù', v_dept, 'active', true, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000013', 'E-355-LV', 'ÙÙŠ Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø©', v_dept, 'active', true, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000014', 'E-355-MS', 'ÙÙŠ Ù…Ø£Ù…ÙˆØ±ÙŠØ©',      v_dept, 'active', true, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000015', 'E-355-A',  'Ù„Ù… ÙŠØ­Ø¶Ø± Ø¥Ø·Ù„Ø§Ù‚Ø§Ù‹', v_dept, 'active', true, '2020-01-01');

  -- Ø£Ù‡Ø¯Ø§Ù Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ (ØºÙŠØ± Ù†Ø´Ø·ÙŠÙ† Ø­ØªÙ‰ Ù„Ø§ ÙŠØ²Ø§Ø­Ù…ÙˆØ§ Ø¹Ø¯Ù‘Ø§Ø¯Ø§Øª Ø§Ù„Ù„ÙˆØ­Ø©).
  insert into public.employees(id, employee_code, full_name_ar, department_id,
    status, is_active, hire_date)
  values
    ('d3550000-0000-4000-8000-000000000016', 'E-355-AD',  'Ù‡Ø¯Ù Ø¥Ø¬Ø§Ø²Ø© Ø¥Ø¯Ø§Ø±ÙŠØ©',  v_dept, 'active', false, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000017', 'E-355-AD2', 'Ù‡Ø¯Ù ØºÙŠØ§Ø¨ Ø¥Ø¯Ø§Ø±ÙŠ',    v_dept, 'active', false, '2020-01-01');

  -- Ù…Ø³ØªØ®Ø¯Ù…Ø§Ù†: Ù…Ø³Ø¤ÙˆÙ„ admin (full-access) + Ù…Ø³ØªØ®Ø¯Ù… Ø¹Ø§Ø¯ÙŠ Ø¨Ù„Ø§ Ø£Ø¯ÙˆØ§Ø± (Ù„Ù„Ø±ÙØ¶).
  insert into auth.users(id, email, aud, role) values
    ('d3550000-0000-4000-8000-000000000020', 'adm-0355@test.local',   'authenticated', 'authenticated'),
    ('d3550000-0000-4000-8000-000000000021', 'denied-0355@test.local','authenticated', 'authenticated');

  insert into public.employees(id, user_id, employee_code, full_name_ar,
    department_id, status, is_active, hire_date)
  values
    ('d3550000-0000-4000-8000-000000000018', 'd3550000-0000-4000-8000-000000000020', 'E-355-ADM', 'Ù…Ø´Ø±Ù Ø§Ù„ØªØµØ­ÙŠØ­ Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ', v_dept, 'active', false, '2020-01-01'),
    ('d3550000-0000-4000-8000-000000000019', 'd3550000-0000-4000-8000-000000000021', 'E-355-DN',  'Ù…Ø³ØªØ®Ø¯Ù… Ù…Ø±ÙÙˆØ¶',        v_dept, 'active', false, '2020-01-01');

  insert into public.profiles(id, employee_id, status) values
    ('d3550000-0000-4000-8000-000000000020', 'd3550000-0000-4000-8000-000000000018', 'active'),
    ('d3550000-0000-4000-8000-000000000021', 'd3550000-0000-4000-8000-000000000019', 'active');

  select id into v_admin_role from public.roles where slug = 'admin';
  insert into public.user_roles(user_id, role_id) values
    ('d3550000-0000-4000-8000-000000000020', v_admin_role);

  -- Ø§Ù„Ù…Ø´Ø±Ù Ù…Ø¯ÙŠØ± Ù…Ø¨Ø§Ø´Ø± Ù„Ø£Ù‡Ø¯Ø§Ù Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ (ØªØ­Ø¯ÙŠØ¯ Ù…ÙˆØ«ÙˆÙ‚ Ù„Ù„Ù…Ø¹ØªÙ…ÙØ¯).
  insert into public.manager_relations(employee_id, manager_employee_id, relation_type,
    effective_from, effective_to)
  values
    ('d3550000-0000-4000-8000-000000000016', 'd3550000-0000-4000-8000-000000000018', 'primary', '2026-01-01', null),
    ('d3550000-0000-4000-8000-000000000017', 'd3550000-0000-4000-8000-000000000018', 'primary', '2026-01-01', null);

  -- ØµÙÙˆÙ Ø§Ù„Ø­Ø¶ÙˆØ±: Ø­Ø§Ø¶Ø± / Ù…ØªØ£Ø®Ø± / Ø¨ØµÙ…Ø© ÙˆØ§Ø­Ø¯Ø©.
  insert into public.attendance_daily(employee_id, work_date, shift_id,
    first_check_in, last_check_out, work_minutes, late_minutes, status, is_finalized)
  values
    ('d3550000-0000-4000-8000-000000000010', v_day, v_shift, '2026-08-03 09:00:00+02', '2026-08-03 17:00:00+02', 480, 0, 'present', true),
    ('d3550000-0000-4000-8000-000000000011', v_day, v_shift, '2026-08-03 09:15:00+02', '2026-08-03 17:00:00+02', 465, 15, 'late',   true),
    ('d3550000-0000-4000-8000-000000000012', v_day, v_shift, '2026-08-03 09:00:00+02', null,                         0,   0, 'present', false);

  -- Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø© Ù…Ø¨Ø§Ø´Ø±Ø© (annual) â€” Ù„Ø§ ØµÙ Ø­Ø¶ÙˆØ± Ù„Ù„ÙŠÙˆÙ… â†’ Ø§Ø´ØªÙ‚Ø§Ù‚ on_leave.
  select id into v_annual from public.leave_types where code = 'annual';
  perform public.ensure_leave_account('d3550000-0000-4000-8000-000000000013', v_annual, 2026);
  perform public.apply_leave_ledger_entry(
    'd3550000-0000-4000-8000-000000000013', v_annual, 2026, 'opening', 10,
    'test:0355:open-annual:13', null, 'Ø±ØµÙŠØ¯ Ø§Ø®ØªØ¨Ø§Ø±ÙŠ Ù„Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø¥Ø¬Ø§Ø²Ø©');

  insert into public.requests(request_type, employee_id, status, title, reason, payload)
  values ('leave', 'd3550000-0000-4000-8000-000000000013', 'approved',
          'Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø© 0355', 'Ø³Ø¨Ø¨ Ø§Ø®ØªØ¨Ø§Ø±ÙŠ Ù…Ø¹ØªÙ…Ø¯', '{}'::jsonb);
  insert into public.leave_requests(request_id, employee_id, leave_type_id,
    start_date, end_date, days_count, duration_unit)
  values ((select id from public.requests
           where employee_id = 'd3550000-0000-4000-8000-000000000013'
             and request_type = 'leave' and status = 'approved' limit 1),
          'd3550000-0000-4000-8000-000000000013', v_annual, v_day, v_day, 1, 'day');

  -- Ù…Ø£Ù…ÙˆØ±ÙŠØ© Ù…Ø¹ØªÙ…Ø¯Ø© ØªØºØ·ÙŠ Ø§Ù„ÙŠÙˆÙ… â†’ Ø§Ø´ØªÙ‚Ø§Ù‚ on_mission.
  insert into public.work_assignments(assignment_type, title, status, start_at, end_at)
  values ('MISSION', 'Ù…Ø£Ù…ÙˆØ±ÙŠØ© 0355', 'APPROVED', '2026-08-03 00:00:00+02', '2026-08-03 23:59:00+02');
  insert into public.work_assignment_participants(assignment_id, employee_id)
  values ((select id from public.work_assignments where title = 'Ù…Ø£Ù…ÙˆØ±ÙŠØ© 0355' limit 1),
          'd3550000-0000-4000-8000-000000000014');

  -- Ø±ØµÙŠØ¯ Ø³Ù†ÙˆÙŠØ© Ù„Ù„Ø£Ù‡Ø¯Ø§Ù Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠØ© (ÙŠÙƒÙÙŠ Ø®ØµÙ… ÙŠÙˆÙ… ÙˆØ§Ø­Ø¯ Ø¹Ø¨Ø± reserve/consume).
  perform public.ensure_leave_account('d3550000-0000-4000-8000-000000000016', v_annual, 2026);
  perform public.apply_leave_ledger_entry(
    'd3550000-0000-4000-8000-000000000016', v_annual, 2026, 'opening', 10,
    'test:0355:open-annual:16', null, 'Ø±ØµÙŠØ¯ Ø§Ø®ØªØ¨Ø§Ø±ÙŠ Ù„Ù‡Ø¯Ù Ø§Ù„Ø¥Ø¬Ø§Ø²Ø© Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠØ©');

  select id into v_unpaid from public.leave_types where code = 'unpaid';
  perform public.ensure_leave_account('d3550000-0000-4000-8000-000000000017', v_unpaid, 2026);
end $fixture$;

-- =====================================================================
-- (1) Ø¯ÙˆØ§Ù„ 0355 Ù…ÙˆØ¬ÙˆØ¯Ø© Ø¨Ø§Ù„ØªÙˆÙ‚ÙŠØ¹Ø§Øª Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø©ØŒ ÙˆØ§Ù„Ù‚Ø¯ÙŠÙ… Ø³Ù‚Ø·.
-- =====================================================================
select has_function('public','get_attendance_dashboard',array['date','uuid','uuid','uuid'],
  'get_attendance_dashboard(date,uuid,uuid,uuid) Ù…ÙˆØ¬ÙˆØ¯Ø©');

select has_function('public','get_attendance_day_roster',
  array['date','text','text','uuid','uuid','uuid','text','text','integer','integer'],
  'get_attendance_day_roster Ø¨ÙƒÙ„ Ù…Ø±Ø´Ø­Ø§Øª Ø§Ù„ÙØ¦Ø§Øª Ù…ÙˆØ¬ÙˆØ¯Ø©');

select has_function('public','set_employee_attendance_day_admin',
  array['uuid','date','text','time','time','boolean','boolean','text','text','text'],
  'set_employee_attendance_day_admin Ù…Ø¹ p_leave_type (10 Ø¨Ø§Ø±Ø§Ù…ØªØ±Ø§Øª) Ù…ÙˆØ¬ÙˆØ¯Ø©');

select hasnt_function('public','set_employee_attendance_day_admin',
  array['uuid','date','text','time','time','boolean','boolean','text','text'],
  'Ø§Ù„ØªÙˆÙ‚ÙŠØ¹ Ø§Ù„Ù‚Ø¯ÙŠÙ… (9 Ø¨Ø§Ø±Ø§Ù…ØªØ±Ø§Øª) Ø³Ù‚Ø· Ø­ØªÙ‰ Ù„Ø§ ÙŠÙØªØ¬Ø§ÙˆØ² Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¬Ø¯ÙŠØ¯');

select has_function('public','_admin_approve_request_immediately',array['uuid'],
  'Ø¯Ø§Ù„Ø© Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ Ø§Ù„ÙÙˆØ±ÙŠ Ù…ÙˆØ¬ÙˆØ¯Ø©');

-- ÙØ¦Ø© ØºÙŠØ± Ù…Ø¹Ø±ÙˆÙØ© ØªÙØ±ÙØ¶.
select throws_ok(
  $$ select public.get_attendance_day_roster(
       nullif(current_setting('app.t0355_day', true), '')::date, 'bogus',
       null, 'd3550000-0000-4000-8000-000000000002') $$,
  '22023', null, 'ÙØ¦Ø© Ø±Ø³ØªØ± ØºÙŠØ± Ù…Ø¹Ø±ÙˆÙØ© ØªÙØ±ÙØ¶ (22023)');

-- =====================================================================
-- (2) Ø§Ù„Ù„ÙˆØ­Ø©: Ø§Ø´ØªÙ‚Ø§Ù‚ ÙƒÙ„ Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† Ø§Ù„Ù†Ø´Ø·ÙŠÙ† (Ø§Ù„Ù…ÙÙ„ØªØ±ÙŠÙ† Ø¨Ø§Ù„Ø¥Ø¯Ø§Ø±Ø©).
-- =====================================================================
select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'scheduled')::int,
  6, 'scheduled = ÙƒÙ„ Ø§Ù„Ù…ÙˆØ¸ÙÙŠÙ† Ø§Ù„Ù†Ø´Ø·ÙŠÙ† Ø¨Ø§Ù„Ø¥Ø¯Ø§Ø±Ø© (6) ÙˆÙ„ÙŠØ³ ØµÙÙˆÙ Ø§Ù„Ø­Ø¶ÙˆØ± ÙÙ‚Ø·');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'present')::int,
  3, 'present = Ø­Ø§Ø¶Ø± + Ù…ØªØ£Ø®Ø± + Ø¨ØµÙ…Ø© Ø¨Ù„Ø§ Ø§Ù†ØµØ±Ø§Ù (0431)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'late')::int,
  1, 'late = 1 (15 Ø¯Ù‚ÙŠÙ‚Ø© ØªØ£Ø®ÙŠØ±)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'absent')::int,
  1, 'no-show ÙŠÙØ¹Ø¯ ØºØ§Ø¦Ø¨Ù‹Ø§ (Ù„ÙˆÙ„Ø§ Ø§Ù„Ø§Ø´ØªÙ‚Ø§Ù‚ Ù„Ù…Ø§ Ø¸Ù‡Ø± Ø¥Ø·Ù„Ø§Ù‚Ø§Ù‹)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'unexcusedAbsent')::int,
  1, 'unexcusedAbsent = 1 (Ù„Ø§ Ø¥Ø¬Ø§Ø²Ø© ÙˆÙ„Ø§ Ø­Ø¯Ø« Ù„Ù„ÙŠÙˆÙ…)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'onLeave')::int,
  1, 'onLeave = 1 (Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø© Ø¨Ù„Ø§ ØµÙ Ø­Ø¶ÙˆØ±)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'onMission')::int,
  1, 'onMission = 1 (Ù…Ø£Ù…ÙˆØ±ÙŠØ© Ù…Ø¹ØªÙ…Ø¯Ø© Ø¨Ù„Ø§ ØµÙ Ø­Ø¶ÙˆØ±)');

select is(
  (public.get_attendance_dashboard(
     nullif(current_setting('app.t0355_day', true), '')::date,
     'd3550000-0000-4000-8000-000000000002')->>'missingCheckout')::int,
  1, 'missingCheckout = 1 (Ø¨ØµÙ…Ø© Ø¯Ø®ÙˆÙ„ Ø¨Ù„Ø§ Ø§Ù†ØµØ±Ø§Ù ÙˆØºÙŠØ± Ù…Ù†ØªÙ‡Ù)');

-- =====================================================================
-- (3) Ø§Ù„Ø±Ø³ØªØ±: Ø§Ù„ÙØ¦Ø§Øª Ø§Ù„Ø¬Ø¯ÙŠØ¯Ø© ØªØ¹ÙŠØ¯ Ø§Ù„Ø£ÙØ±Ø§Ø¯ Ø§Ù„ØµØ­ÙŠØ­ÙŠÙ†.
-- =====================================================================
select ok(
  (select public.get_attendance_day_roster(
     nullif(current_setting('app.t0355_day', true), '')::date, 'absent',
     null, 'd3550000-0000-4000-8000-000000000002')->>'total')::int = 1
  and exists (select 1 from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.t0355_day', true), '')::date, 'absent',
         null, 'd3550000-0000-4000-8000-000000000002')->'items') it
     where it->>'employeeId' = 'd3550000-0000-4000-8000-000000000015'),
  'ÙØ¦Ø© absent ØªØ¶Ù… no-show Ø§Ù„ÙˆØ­ÙŠØ¯');

select ok(
  (select public.get_attendance_day_roster(
     nullif(current_setting('app.t0355_day', true), '')::date, 'on_leave',
     null, 'd3550000-0000-4000-8000-000000000002')->>'total')::int = 1
  and exists (select 1 from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.t0355_day', true), '')::date, 'on_leave',
         null, 'd3550000-0000-4000-8000-000000000002')->'items') it
     where it->>'employeeId' = 'd3550000-0000-4000-8000-000000000013'
       and it->>'status' = 'on_leave' and it->>'leaveCode' = 'annual'),
  'ÙØ¦Ø© on_leave ØªØ¶Ù… Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø© Ù…Ø¹ leaveCode=annual');

select ok(
  (select public.get_attendance_day_roster(
     nullif(current_setting('app.t0355_day', true), '')::date, 'on_mission',
     null, 'd3550000-0000-4000-8000-000000000002')->>'total')::int = 1
  and exists (select 1 from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.t0355_day', true), '')::date, 'on_mission',
         null, 'd3550000-0000-4000-8000-000000000002')->'items') it
     where it->>'employeeId' = 'd3550000-0000-4000-8000-000000000014'
       and it->>'status' = 'on_mission'),
  'ÙØ¦Ø© on_mission ØªØ¶Ù… Ø§Ù„Ù…ÙˆØ¸Ù ÙÙŠ Ù…Ø£Ù…ÙˆØ±ÙŠØ© Ù…Ø¹ØªÙ…Ø¯Ø©');

select ok(
  (select public.get_attendance_day_roster(
     nullif(current_setting('app.t0355_day', true), '')::date, 'missing_checkout',
     null, 'd3550000-0000-4000-8000-000000000002')->>'total')::int = 1
  and exists (select 1 from jsonb_array_elements(
       public.get_attendance_day_roster(
         nullif(current_setting('app.t0355_day', true), '')::date, 'missing_checkout',
         null, 'd3550000-0000-4000-8000-000000000002')->'items') it
     where it->>'employeeId' = 'd3550000-0000-4000-8000-000000000012'
       and it->>'status' = 'missing_checkout'),
  'ÙØ¦Ø© missing_checkout ØªØ¶Ù… ØµØ§Ø­Ø¨ Ø§Ù„Ø¨ØµÙ…Ø© Ø§Ù„ÙˆØ§Ø­Ø¯Ø©');

-- =====================================================================
-- (4) Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ: Ø¥Ø¬Ø§Ø²Ø© Ø³Ù†ÙˆÙŠØ© â† Ø·Ù„Ø¨ Ù…Ø¹ØªÙ…Ø¯ + on_leave + Ø®ØµÙ… Ø§Ù„Ø±ØµÙŠØ¯.
-- =====================================================================
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d3550000-0000-4000-8000-000000000020","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub',
  'd3550000-0000-4000-8000-000000000020', false);

select is(
  (public.set_employee_attendance_day_admin(
     'd3550000-0000-4000-8000-000000000016',
     nullif(current_setting('app.t0355_day', true), '')::date,
     'leave', null, null, false, false, 'ØªØ¹Ø¯ÙŠÙ„ Ø¥Ø¯Ø§Ø±ÙŠ Ù„Ø¥Ø¬Ø§Ø²Ø© Ø³Ù†ÙˆÙŠØ© Ù…Ø¹ØªÙ…Ø¯Ø©', 'Ù…Ù„Ø§Ø­Ø¸Ø© Ø¥Ø¯Ø§Ø±ÙŠØ©', 'annual'
   )->>'ok'),
  'true', 'Ø§Ù„ØªØ±Ù…ÙŠØ² Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ Ù„Ø¥Ø¬Ø§Ø²Ø© Ø³Ù†ÙˆÙŠØ© ÙŠÙ†Ø¬Ø­ ÙˆÙŠØ¹ÙŠØ¯ ok');

select ok(
  exists (
    select 1 from public.requests r
    join public.leave_requests lr on lr.request_id = r.id
    where lr.employee_id = 'd3550000-0000-4000-8000-000000000016'
      and r.status = 'approved'
      and nullif(current_setting('app.t0355_day', true), '')::date between lr.start_date and lr.end_date),
  'Ø§Ù„ØªØ±Ù…ÙŠØ² Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ ÙŠÙÙ†Ø´Ø¦ Ø·Ù„Ø¨ Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø§Ù‹ ÙÙˆØ±Ø§Ù‹ (Ù„Ø§ override ÙÙ‚Ø·)');

select is(
  (select status from public.attendance_daily
    where employee_id = 'd3550000-0000-4000-8000-000000000016'
      and work_date = nullif(current_setting('app.t0355_day', true), '')::date),
  'on_leave', 'ØªØ±ÙŠØºØ± Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯ ÙŠÙˆØ³Ù… ÙŠÙˆÙ… Ø§Ù„Ø­Ø¶ÙˆØ± on_leave');

select is(
  (select consumed_units::int from public.leave_balance_accounts
    where employee_id = 'd3550000-0000-4000-8000-000000000016'
      and leave_type_id = (select id from public.leave_types where code = 'annual')
      and balance_year = 2026),
  1, 'Ø§Ù„Ø±ØµÙŠØ¯ Ø§Ù„Ø³Ù†ÙˆÙŠ Ø®ÙØµÙ… ÙŠÙˆÙ… (consume) Ø¨Ø¹Ø¯ Ø§Ù„Ø§Ø¹ØªÙ…Ø§Ø¯');

-- Ø¹ÙˆØ¯Ø© Ø¥Ù„Ù‰ postgres Ù„Ù‚Ø±Ø§Ø¡Ø© Ø¬Ø¯ÙˆÙ„ override (RLS ÙŠÙ…Ù†Ø¹ SELECT Ù„Ù„Ø£Ø¯ÙˆØ§Ø± Ù‡Ù†Ø§).
reset role;
select ok(
  exists (select 1 from public.attendance_day_overrides
    where employee_id = 'd3550000-0000-4000-8000-000000000016'
      and work_date = nullif(current_setting('app.t0355_day', true), '')::date),
  'ØµÙ Ø§Ù„ØªØ±Ù…ÙŠØ² (attendance_day_overrides) Ù…ÙƒØªÙˆØ¨ Ø¨Ù„Ø§ ØªØ¬Ø§ÙˆØ² Ø§Ù„Ù…Ø³Ø§Ø± Ø§Ù„Ø¬Ø¯ÙŠØ¯');

-- Ø§Ø³ØªØ¯Ø¹Ø§Ø¡ Ø«Ø§Ù†Ù Ù„Ù†ÙØ³ Ø§Ù„ÙŠÙˆÙ… Ù„Ø§ ÙŠÙÙ†Ø´Ø¦ Ø·Ù„Ø¨Ø§Ù‹ Ù…ÙƒØ±Ø±Ø§Ù‹ (Ù…Ù†Ø¹ Ø§Ø­ØªØ³Ø§Ø¨ Ù…Ø²Ø¯ÙˆØ¬).
set local role authenticated;
select lives_ok($q$
  select public.set_employee_attendance_day_admin(
    'd3550000-0000-4000-8000-000000000016',
    nullif(current_setting('app.t0355_day', true), '')::date,
    'leave', null, null, false, false, 'ØªØ¹Ø¯ÙŠÙ„ Ø¥Ø¯Ø§Ø±ÙŠ Ù…ÙƒØ±Ø± Ù„Ù†ÙØ³ Ø§Ù„ÙŠÙˆÙ…', null, 'annual')
$q$, 'Ø¥Ø¹Ø§Ø¯Ø© Ø§Ù„ØªØ±Ù…ÙŠØ² Ù„Ù†ÙØ³ Ø§Ù„ÙŠÙˆÙ… Ù„Ø§ ØªÙØ´Ù„');

reset role;
select is(
  (select count(*)::int from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
   where lr.employee_id = 'd3550000-0000-4000-8000-000000000016'
     and nullif(current_setting('app.t0355_day', true), '')::date between lr.start_date and lr.end_date),
  1, 'Ù„Ø§ ÙŠÙÙ†Ø´Ø£ Ø·Ù„Ø¨ Ù…ÙƒØ±Ø± Ù„ÙŠÙˆÙ… Ø¹Ù„ÙŠÙ‡ Ø¥Ø¬Ø§Ø²Ø© Ù…Ø¹ØªÙ…Ø¯Ø©');

-- =====================================================================
-- (5) Ø§Ù„Ø§ÙØªØ±Ø§Ø¶ÙŠ: ØªØ±Ù…ÙŠØ² Â«ØºÙŠØ§Ø¨Â» Ø¨Ù„Ø§ p_leave_type â† unpaid (Ø¨Ù„Ø§ Ø£Ø«Ø± Ø¹Ù„Ù‰ Ø§Ù„Ø±ØµÙŠØ¯).
-- =====================================================================
set local role authenticated;
select lives_ok($q$
  select public.set_employee_attendance_day_admin(
    'd3550000-0000-4000-8000-000000000017',
    nullif(current_setting('app.t0355_day', true), '')::date,
    'absent', null, null, false, false, 'ØªØ±Ù…ÙŠØ² ØºÙŠØ§Ø¨ Ø¥Ø¯Ø§Ø±ÙŠ Ø¨Ù„Ø§ Ù†ÙˆØ¹ Ø¥Ø¬Ø§Ø²Ø©', null, null)
$q$, 'Ø§Ù„ØªØ±Ù…ÙŠØ² Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ Ù„Ù„ØºÙŠØ§Ø¨ (Ø¨Ù„Ø§ p_leave_type) ÙŠÙ†Ø¬Ø­');

reset role;
select is(
  (select lt.code from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    join public.leave_types lt on lt.id = lr.leave_type_id
   where lr.employee_id = 'd3550000-0000-4000-8000-000000000017'
     and nullif(current_setting('app.t0355_day', true), '')::date between lr.start_date and lr.end_date),
  'unpaid',
  'ØªØ±Ù…ÙŠØ² Ø§Ù„ØºÙŠØ§Ø¨ Ø§Ù„Ø¥Ø¯Ø§Ø±ÙŠ Ø¨Ù„Ø§ p_leave_type ÙŠØªØ­ÙˆÙ„ ØªÙ„Ù‚Ø§Ø¦ÙŠØ§Ù‹ Ø¥Ù„Ù‰ unpaid');

-- =====================================================================
-- (6) Ø§Ù„Ù†ÙˆØ¹ ØºÙŠØ± Ø§Ù„Ù…Ø¯Ø¹ÙˆÙ… ÙŠÙØ±ÙØ¶ Ù‚Ø¨Ù„ Ø£ÙŠ Ø£Ø«Ø±.
-- =====================================================================
set local role authenticated;
select throws_ok($q$
  select public.set_employee_attendance_day_admin(
    'd3550000-0000-4000-8000-000000000017',
    nullif(current_setting('app.t0355_day', true), '')::date,
    'leave', null, null, false, false, 'Ø³Ø¨Ø¨ Ø§Ø®ØªØ¨Ø§Ø±ÙŠ ÙƒØ§ÙÙ Ù„Ù„Ù…Ø¯Ù‰', null, 'bogus')
$q$, '22023', null, 'Ù†ÙˆØ¹ Ø¥Ø¬Ø§Ø²Ø© ØºÙŠØ± Ù…Ø¯Ø¹ÙˆÙ… ÙŠÙØ±ÙØ¶ (22023)');

-- =====================================================================
-- (7) ØºÙŠØ± Ø§Ù„Ù…ØµØ±Ø­ (Ø¨Ù„Ø§ Ø£Ø¯ÙˆØ§Ø±) ÙŠÙØ±ÙØ¶.
-- =====================================================================
reset role;
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"d3550000-0000-4000-8000-000000000021","role":"authenticated"}', false);
select set_config('request.jwt.claim.sub',
  'd3550000-0000-4000-8000-000000000021', false);

select throws_ok($q$
  select public.set_employee_attendance_day_admin(
    'd3550000-0000-4000-8000-000000000015',
    nullif(current_setting('app.t0355_day', true), '')::date,
    'leave', null, null, false, false, 'Ù…Ø­Ø§ÙˆÙ„Ø© ØºÙŠØ± Ù…ØµØ±Ø­ Ø¨Ù‡Ø§ Ù„Ù„ØªØ¹Ø¯ÙŠÙ„', null, 'annual')
$q$, '42501', null, 'Ù…Ø³ØªØ®Ø¯Ù… Ø¨Ù„Ø§ ØµÙ„Ø§Ø­ÙŠØ§Øª ÙŠÙØ±ÙØ¶ (FORBIDDEN)');

select * from finish();
rollback;
