-- 0031: Audit remediation runtime proof (migration 0049).
-- Proves the P0/P1 fixes from HR_PLATFORM_DEEP_AUDIT_V8_AR.md actually close the
-- gaps at runtime. Everything runs in a transaction and rolls back.
--
-- Covers:
--   RLS-01   [P0] department-scoped payroll clerk cannot read/write out-of-scope
--                 employee_compensation.
--   LEDGER-01[P1] a duplicate apply_leave_ledger_entry call (same source_key)
--                 does NOT double-apply the balance aggregate.
--   DECISION-01[P1] the author of an administrative decision cannot approve it.
--   ATT-01   [P1] calculate_late_minutes is timezone-correct (a genuinely late
--                 Africa/Cairo check-in is no longer reported as 0).

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(9);

-- =====================================================================
-- Fixture (superuser; RLS not yet in play)
-- =====================================================================
do $fixture$
declare
  v_le      uuid := 'cccccccc-0000-4000-8000-000000000000';
  v_dept_a  uuid := 'cccccccc-0000-4000-8000-00000000000a';
  v_dept_b  uuid := 'cccccccc-0000-4000-8000-00000000000b';
  v_perm    uuid;
  v_role    uuid;
  v_lt      uuid := 'cccccccc-0000-4000-8000-0000000000dd';
  v_struct  uuid := 'cccccccc-0000-4000-8000-0000000000c5';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'REM-LE', 'كيان اختبار الإصلاح');
  insert into public.departments (id, legal_entity_id, code, name) values
    (v_dept_a, v_le, 'REM-A', 'إدارة أ'),
    (v_dept_b, v_le, 'REM-B', 'إدارة ب');

  insert into auth.users (id, email, aud, role) values
    ('44444444-0000-4000-8000-000000000001', 'rem-clerk@test.local', 'authenticated', 'authenticated'),
    ('44444444-0000-4000-8000-000000000002', 'rem-other@test.local', 'authenticated', 'authenticated');

  -- clerk in dept A, target employee in dept B (out of scope)
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active) values
    ('55555555-0000-4000-8000-000000000001', '44444444-0000-4000-8000-000000000001', 'REM-001', 'كاتب رواتب', v_dept_a, 'active', true),
    ('55555555-0000-4000-8000-000000000002', '44444444-0000-4000-8000-000000000002', 'REM-002', 'موظف إدارة ب', v_dept_b, 'active', true);

  insert into public.profiles (id, employee_id, status) values
    ('44444444-0000-4000-8000-000000000001', '55555555-0000-4000-8000-000000000001', 'active'),
    ('44444444-0000-4000-8000-000000000002', '55555555-0000-4000-8000-000000000002', 'active');

  -- a department-scoped payroll.structure.manage role for the clerk
  select id into v_perm from public.permissions where code = 'payroll.structure.manage';
  insert into public.roles (id, slug, name_ar, is_system, is_full_access)
  values (gen_random_uuid(), 'rem-payroll-branch', 'كاتب رواتب مقيّد', false, false)
  returning id into v_role;
  insert into public.role_permissions (role_id, permission_id, scope)
  values (v_role, v_perm, 'department');
  insert into public.user_roles (user_id, role_id)
  values ('44444444-0000-4000-8000-000000000001', v_role);

  -- salary structure (required FK for employee_compensation)
  insert into public.salary_structures (id, code, name_ar, currency, effective_from)
  values (v_struct, 'REM-STR', 'هيكل اختبار', 'SAR', current_date);

  -- compensation rows for BOTH employees (clerk in dept A, target in dept B)
  insert into public.employee_compensation (employee_id, structure_id, base_salary, effective_from)
  values
    ('55555555-0000-4000-8000-000000000001', v_struct, 10000, current_date),
    ('55555555-0000-4000-8000-000000000002', v_struct, 20000, current_date);

  -- leave type + a leave account for LEDGER-01
  insert into public.leave_types (id, code, name_ar, affects_balance)
  values (v_lt, 'REM-LT', 'إجازة اختبار', true);
end
$fixture$;

-- =====================================================================
-- RLS-01 [P0] — department-scoped clerk: in-scope visible, out-of-scope hidden
-- =====================================================================
do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

select is(
  (select count(*)::int from public.employee_compensation
    where employee_id = '55555555-0000-4000-8000-000000000001'),
  1,
  'RLS-01: payroll clerk sees in-scope (own department) compensation');

select is(
  (select count(*)::int from public.employee_compensation
    where employee_id = '55555555-0000-4000-8000-000000000002'),
  0,
  'RLS-01: payroll clerk CANNOT see out-of-scope (other dept) compensation');

-- out-of-scope UPDATE must affect zero rows (RLS filters it out)
with upd as (
  update public.employee_compensation set base_salary = 99999
  where employee_id = '55555555-0000-4000-8000-000000000002'
  returning 1
)
select is((select count(*)::int from upd), 0,
  'RLS-01: payroll clerk cannot UPDATE out-of-scope compensation');

reset role;
select is(
  (select base_salary::int from public.employee_compensation
    where employee_id = '55555555-0000-4000-8000-000000000002'),
  20000,
  'RLS-01: out-of-scope salary is unchanged after blocked update');

-- =====================================================================
-- LEDGER-01 [P1] — duplicate apply does not double-apply the aggregate
-- =====================================================================
do $$
declare v_acc numeric;
begin
  perform public.apply_leave_ledger_entry(
    '55555555-0000-4000-8000-000000000002'::uuid,
    'cccccccc-0000-4000-8000-0000000000dd'::uuid,
    extract(year from current_date)::int,
    'accrual', 5, 'rem:accrual:2026:test');
  -- duplicate call with the SAME source_key
  perform public.apply_leave_ledger_entry(
    '55555555-0000-4000-8000-000000000002'::uuid,
    'cccccccc-0000-4000-8000-0000000000dd'::uuid,
    extract(year from current_date)::int,
    'accrual', 5, 'rem:accrual:2026:test');
end $$;

select is(
  (select accrued_units::int from public.leave_balance_accounts
    where employee_id = '55555555-0000-4000-8000-000000000002'),
  5,
  'LEDGER-01: duplicate accrual (same source_key) applied once, not twice');

select is(
  (select count(*)::int from public.leave_ledger_entries
    where source_key = 'rem:accrual:2026:test'),
  1,
  'LEDGER-01: only one ledger row exists for the source_key');

-- =====================================================================
-- DECISION-01 [P1] — author cannot approve own administrative decision
-- =====================================================================
-- Give the clerk decision manage+approve, then have them draft->submit->approve.
do $$
declare v_pm uuid; v_pa uuid; v_role uuid;
begin
  insert into public.permissions (code, module, resource, action, description, risk_level)
  values ('comms.decision.manage','comms','decision','manage','إدارة القرارات','sensitive')
  on conflict (code) do nothing;
  insert into public.permissions (code, module, resource, action, description, risk_level)
  values ('comms.decision.approve','comms','decision','approve','اعتماد القرارات','critical')
  on conflict (code) do nothing;
  select id into v_pm from public.permissions where code='comms.decision.manage';
  select id into v_pa from public.permissions where code='comms.decision.approve';
  insert into public.roles (id, slug, name_ar, is_system, is_full_access)
  values (gen_random_uuid(), 'rem-decider', 'صانع قرار اختبار', false, false)
  returning id into v_role;
  insert into public.role_permissions (role_id, permission_id, scope) values
    (v_role, v_pm, 'organization'),
    (v_role, v_pa, 'organization');
  insert into public.user_roles (user_id, role_id)
  values ('44444444-0000-4000-8000-000000000001', v_role);
end $$;

do $$ begin
  perform set_config('request.jwt.claims',
    '{"sub":"44444444-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '44444444-0000-4000-8000-000000000001', true);
end $$;
set local role authenticated;

-- draft + submit succeed; self-approve must raise four-eyes (42501)
select lives_ok(
  $$do $inner$
    declare v_id uuid;
    begin
      v_id := public.create_decision_draft('قرار اختبار الفصل', 'نص قرار اختبار الفصل بين الواجبات', 'general');
      perform public.transition_decision(v_id, 'submit_review');
      perform set_config('rem.decision_id', v_id::text, true);
    end
  $inner$;$$,
  'DECISION-01: author can draft and submit for review');

select throws_ok(
  $$select public.transition_decision(current_setting('rem.decision_id')::uuid, 'approve')$$,
  '42501', null,
  'DECISION-01: author CANNOT approve own decision (four-eyes enforced)');

reset role;

-- =====================================================================
-- ATT-01 [P1] — timezone-correct lateness (Africa/Cairo)
-- =====================================================================
-- Shift starts 09:00 local; a 10:30 Africa/Cairo check-in (08:30 UTC) is ~90 min
-- late. The pre-fix UTC-assuming code returned 0. Assert > 0 now.
select cmp_ok(
  public.calculate_late_minutes(
    (current_date::text || ' 08:30:00+00')::timestamptz,  -- 10:30 Africa/Cairo
    '09:00'::time, 0, current_date),
  '>', 0,
  'ATT-01: a late Africa/Cairo check-in is reported as late, not 0');

select * from finish();
rollback;
