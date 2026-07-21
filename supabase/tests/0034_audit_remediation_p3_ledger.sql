-- 0033: P3 audit remediation runtime proof (migration 0055) — LEDGER-02.
-- Proves that cancelling an ALREADY-APPROVED leave request refunds consumed
-- units (net-zero balance impact) instead of leaving consumed_units inflated.
-- Rolls back.

begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(3);

do $fixture$
declare
  v_le   uuid := 'eeeeeeee-0000-4000-8000-000000000000';
  v_dept uuid := 'eeeeeeee-0000-4000-8000-00000000000a';
  v_lt   uuid := 'eeeeeeee-0000-4000-8000-0000000000dd';
  v_acc  uuid;
  v_req  uuid := 'eeeeeeee-0000-4000-8000-0000000000f1';
begin
  insert into public.legal_entities (id, code, name) values (v_le, 'P3-LE', 'كيان P3');
  insert into public.departments (id, legal_entity_id, code, name) values (v_dept, v_le, 'P3-D', 'إدارة P3');
  insert into auth.users (id, email, aud, role) values
    ('a2000000-0000-4000-8000-000000000001', 'p3-emp@test.local', 'authenticated', 'authenticated');
  insert into public.employees (id, user_id, employee_code, full_name_ar, department_id, status, is_active)
    values ('b3000000-0000-4000-8000-000000000001', 'a2000000-0000-4000-8000-000000000001', 'P3-001', 'موظف P3', v_dept, 'active', true);
  insert into public.profiles (id, employee_id, status)
    values ('a2000000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'active');

  insert into public.leave_types (id, code, name_ar, affects_balance)
    values (v_lt, 'P3-LT', 'إجازة P3', true);

  -- opening balance of 20 days
  perform public.apply_leave_ledger_entry(
    'b3000000-0000-4000-8000-000000000001'::uuid, v_lt, extract(year from current_date)::int,
    'opening', 20, 'p3:opening');

  -- a leave request for 5 days (pending) + detail -> fires reserve trigger
  insert into public.requests (id, request_type, employee_id, status, workflow_status, title)
    values (v_req, 'leave', 'b3000000-0000-4000-8000-000000000001', 'pending', 'submitted', 'طلب إجازة P3');
  insert into public.leave_requests (request_id, employee_id, leave_type_id, start_date, end_date, days_count)
    values (v_req, 'b3000000-0000-4000-8000-000000000001', v_lt, current_date, current_date + 4, 5);
end
$fixture$;

-- After reserve: reserved_units = 5, consumed_units = 0
select is(
  (select reserved_units::int from public.leave_balance_accounts
    where employee_id = 'b3000000-0000-4000-8000-000000000001'),
  5,
  'LEDGER-02 setup: 5 days reserved on submit');

-- Approve -> consume (reserved 5->0, consumed 0->5)
update public.requests set status = 'approved' where id = 'eeeeeeee-0000-4000-8000-0000000000f1';
select is(
  (select consumed_units::int from public.leave_balance_accounts
    where employee_id = 'b3000000-0000-4000-8000-000000000001'),
  5,
  'LEDGER-02 setup: 5 days consumed after approval');

-- Cancel an APPROVED request -> must REFUND consumed (not release a zero reserve)
update public.requests set status = 'cancelled' where id = 'eeeeeeee-0000-4000-8000-0000000000f1';
select is(
  (select consumed_units::int from public.leave_balance_accounts
    where employee_id = 'b3000000-0000-4000-8000-000000000001'),
  0,
  'LEDGER-02: cancelling an approved request refunds consumed_units to 0');

select * from finish();
rollback;
