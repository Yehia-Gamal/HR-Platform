-- Migration 0014: Canonical employee permission namespace and no physical deletion.
-- The canonical permission catalog is people.employee.*. Legacy employees.* codes
-- remain seeded temporarily for older modules but are no longer used by employees RLS.

begin;

-- Reading an employee requires the canonical scoped permission. The employee
-- can still read their own row through can_access_employee's self rule.
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees
  for select to authenticated
  using (public.can_access_employee(id, 'people.employee.read'));

-- Creation must use the trusted provisioning function/Edge Function. No direct
-- authenticated INSERT into employees even when the UI has create permission.
drop policy if exists employees_insert on public.employees;

-- Basic update remains scope-aware. Sensitive columns stay protected by the
-- existing before-update trigger and require people.employee.update_sensitive.
drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees
  for update to authenticated
  using (
    id = public.current_employee_id()
    or public.can_access_employee(id, 'people.employee.update_basic')
  )
  with check (
    id = public.current_employee_id()
    or public.can_access_employee(id, 'people.employee.update_basic')
  );

-- Employee history is never physically deleted by an authenticated account.
-- Termination/archive must be implemented by an audited server-side workflow.
drop policy if exists employees_delete on public.employees;

comment on table public.employees is
  'Master employee record. Authenticated clients cannot INSERT or DELETE directly; creation, termination and archival use audited server-side workflows.';

commit;
