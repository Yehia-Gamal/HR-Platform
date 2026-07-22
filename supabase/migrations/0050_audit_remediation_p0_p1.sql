-- Migration 0050: P0/P1 audit remediation (HR_PLATFORM_DEEP_AUDIT_V8_AR.md)
-- ============================================================================
-- Fixes confirmed by the 2026-07-15 deep audit (adversarially verified):
--   RLS-01  [P0] payroll/loan tables scope collapse (org-wide read+write)
--   RLS-02  [P1] kpi_scores non-self writes ignore employee scope
--   LEDGER-01 [P1] leave ledger 5-second idempotency double-applies aggregates
--   DECISION-01 [P1] transition_decision has no four-eyes (author == approver)
--   ATT-01  [P1] calculate_late_minutes treats shift start_time as UTC
--
-- Each fix is idempotent (drop/replace) and preserves existing function
-- signatures except calculate_late_minutes, which gains an optional timezone
-- parameter (default Africa/Cairo = the operational tz used by the caller).
-- ============================================================================

begin;

-- ============================================================================
-- RLS-01 [P0] — Scope-aware policies on per-employee payroll/loan tables.
-- The 0036 loop applied a scope-blind has_permission('payroll.structure.manage')
-- policy to salary_structures, salary_components (catalogs — OK) AND to
-- employee_compensation, employee_loans, loan_installments (per-employee PII —
-- NOT OK). Replace the three per-employee policies with scope-aware terms that
-- honor role_permissions.scope via can_access_employee(employee_id, code),
-- mirroring the payslips_read pattern (0036:90). Catalog policies are left as-is.
-- ============================================================================

-- employee_compensation: gate on can_access_employee(employee_id, code)
drop policy if exists employee_compensation_payroll_admin on public.employee_compensation;
create policy employee_compensation_payroll_admin on public.employee_compensation
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id, 'payroll.structure.manage')
  )
  with check (
    public.current_is_full_access()
    or public.can_access_employee(employee_id, 'payroll.structure.manage')
  );

-- employee_loans: same scope-aware gate on its own employee_id
drop policy if exists employee_loans_payroll_admin on public.employee_loans;
create policy employee_loans_payroll_admin on public.employee_loans
  for all to authenticated
  using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id, 'payroll.structure.manage')
  )
  with check (
    public.current_is_full_access()
    or public.can_access_employee(employee_id, 'payroll.structure.manage')
  );

-- loan_installments: no employee_id column — scope via the parent loan's employee
drop policy if exists loan_installments_payroll_admin on public.loan_installments;
create policy loan_installments_payroll_admin on public.loan_installments
  for all to authenticated
  using (
    public.current_is_full_access()
    or exists (
      select 1 from public.employee_loans l
      where l.id = loan_id
        and public.can_access_employee(l.employee_id, 'payroll.structure.manage')
    )
  )
  with check (
    public.current_is_full_access()
    or exists (
      select 1 from public.employee_loans l
      where l.id = loan_id
        and public.can_access_employee(l.employee_id, 'payroll.structure.manage')
    )
  );

-- ============================================================================
-- RLS-02 [P1] — kpi_scores non-self writes must be employee-scoped.
-- The SELECT policy already scopes via can_access_employee (0007:249); the
-- INSERT/UPDATE policies scoped only the 'self' branch. Add a per-stage
-- can_access_employee guard so a manager/hr/executive can only write scores for
-- evaluations of employees within their ABAC scope. The unlocked-cycle guard is
-- preserved.
-- ============================================================================

drop policy if exists kpi_scores_insert on public.kpi_scores;
create policy kpi_scores_insert on public.kpi_scores
  for insert to authenticated
  with check (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.manager_assess')))
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary')
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.hr_review')))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.executive_review')))
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.finalize')))
    )
  );

drop policy if exists kpi_scores_update on public.kpi_scores;
create policy kpi_scores_update on public.kpi_scores
  for update to authenticated
  using (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.manager_assess')))
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary')
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.hr_review')))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.executive_review')))
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.finalize')))
    )
  )
  with check (
    exists (
      select 1 from public.kpi_evaluations e
      join public.kpi_cycles c on c.id = e.cycle_id
      where e.id = evaluation_id and e.locked = false and c.status <> 'locked'
    )
    and (
      public.current_is_full_access()
      or (public.has_permission('performance.kpi.self_assess') and reviewer_stage = 'self'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and e.employee_id = public.current_employee_id()))
      or (public.has_permission('performance.kpi.manager_assess') and reviewer_stage = 'manager'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.manager_assess')))
      or (public.has_permission('performance.kpi.hr_review') and reviewer_stage in ('hr','secretary')
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.hr_review')))
      or (public.has_permission('performance.kpi.executive_review') and reviewer_stage = 'executive'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.executive_review')))
      or (public.has_permission('performance.kpi.finalize') and reviewer_stage = 'finalized'
          and exists (select 1 from public.kpi_evaluations e where e.id = evaluation_id and public.can_access_employee(e.employee_id, 'performance.kpi.finalize')))
    )
  );

-- ============================================================================
-- LEDGER-01 [P1] — Structural idempotency for the leave ledger.
-- Replace the wall-clock (5s) heuristic with: (a) a transaction-level advisory
-- lock keyed on source_key to serialize concurrent duplicates, and (b) an
-- ON CONFLICT DO NOTHING insert whose "was a row actually inserted?" result
-- (FOUND) gates the balance-aggregate mutation. Duplicate calls return the
-- existing entry without re-applying aggregates. Signature unchanged.
-- ============================================================================

create or replace function public.apply_leave_ledger_entry(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_year integer,
  p_entry_type text,
  p_units numeric,
  p_source_key text,
  p_request_id uuid default null,
  p_reason text default null,
  p_metadata jsonb default '{}'::jsonb
) returns public.leave_ledger_entries
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_account public.leave_balance_accounts;
  v_entry public.leave_ledger_entries;
  v_available numeric;
  v_inserted boolean := false;
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;

  -- Serialize concurrent duplicate calls for the same logical event.
  perform pg_advisory_xact_lock(hashtext('leave_ledger:' || p_source_key));

  v_account := public.ensure_leave_account(p_employee_id,p_leave_type_id,p_year);

  -- Structural idempotency: only a genuine INSERT applies aggregates.
  insert into public.leave_ledger_entries(account_id,employee_id,leave_type_id,request_id,entry_type,units,effective_date,reason,source_key,metadata,created_by)
  values(v_account.id,p_employee_id,p_leave_type_id,p_request_id,p_entry_type,p_units,current_date,p_reason,p_source_key,coalesce(p_metadata,'{}'::jsonb),auth.uid())
  on conflict(source_key) do nothing
  returning * into v_entry;

  v_inserted := found;

  if not v_inserted then
    -- Duplicate: return the existing entry, do NOT touch aggregates.
    select * into v_entry from public.leave_ledger_entries where source_key = p_source_key;
    return v_entry;
  end if;

  if p_entry_type='opening' then update public.leave_balance_accounts set opening_units=opening_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='accrual' then update public.leave_balance_accounts set accrued_units=accrued_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='carryover' then update public.leave_balance_accounts set carryover_units=carryover_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='adjustment' then update public.leave_balance_accounts set adjusted_units=adjusted_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='reserve' then
    select opening_units+accrued_units+adjusted_units+carryover_units-consumed_units-reserved_units into v_available
    from public.leave_balance_accounts where id=v_account.id for update;
    if v_available < p_units then raise exception 'INSUFFICIENT_LEAVE_BALANCE'; end if;
    update public.leave_balance_accounts set reserved_units=reserved_units+p_units,updated_at=now() where id=v_account.id;
  elsif p_entry_type='release' then update public.leave_balance_accounts set reserved_units=greatest(0,reserved_units-abs(p_units)),updated_at=now() where id=v_account.id;
  elsif p_entry_type='consume' then update public.leave_balance_accounts set reserved_units=greatest(0,reserved_units-abs(p_units)),consumed_units=consumed_units+abs(p_units),updated_at=now() where id=v_account.id;
  elsif p_entry_type='refund' then update public.leave_balance_accounts set consumed_units=greatest(0,consumed_units-abs(p_units)),updated_at=now() where id=v_account.id;
  elsif p_entry_type='expire' then update public.leave_balance_accounts set adjusted_units=adjusted_units-abs(p_units),updated_at=now() where id=v_account.id;
  end if;
  return v_entry;
end $$;

-- ============================================================================
-- DECISION-01 [P1] — Four-eyes on administrative decision approval.
-- Reject 'approve' when the approver authored or submitted the decision, even
-- for full-access users, mirroring approve_break_glass (0038:562) and
-- decide_request. Only the approve branch changes; all other transitions and
-- the audit/log calls are preserved verbatim.
-- ============================================================================

create or replace function public.transition_decision(
  p_decision_id uuid,p_action text,p_reason text default null,p_scheduled_for timestamptz default null
) returns public.administrative_decisions language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.administrative_decisions; v_from text; v_to text; v_emp uuid:=public.current_employee_id();
begin
  select * into strict v_row from public.administrative_decisions where id=p_decision_id for update;
  v_from:=v_row.status;
  if p_action='submit_review' and v_from='draft' then v_to:='in_review';
  elsif p_action='approve' and v_from='in_review' then
    if not(public.current_is_full_access() or public.has_permission('comms.decision.approve')) then raise exception 'FORBIDDEN'; end if;
    -- Four-eyes: the approver must not be the author or the submitter (SoD).
    if v_emp is not null and (
         v_row.issued_by = v_emp
         or v_row.created_by = auth.uid()
         or exists (
           select 1 from public.decision_actions da
           where da.decision_id = p_decision_id
             and da.action_type in ('create','submit_review')
             and da.actor_employee_id = v_emp
         )
       ) then
      raise exception 'FOUR_EYES_REQUIRED: the approver must differ from the author/submitter' using errcode='42501';
    end if;
    v_to:='approved';
  elsif p_action='return' and v_from='in_review' then v_to:='draft';
  elsif p_action='schedule' and v_from='approved' and p_scheduled_for>now() then v_to:='scheduled';
  elsif p_action='publish' and v_from in ('approved','scheduled') then v_to:='published';
  elsif p_action='archive' and v_from='published' then v_to:='archived';
  elsif p_action='revoke' and v_from in ('approved','scheduled','published') then v_to:='revoked';
  else raise exception 'INVALID_DECISION_TRANSITION'; end if;
  if p_action in ('return','revoke') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
  if p_action not in ('approve') and not(public.current_is_full_access() or public.has_permission('comms.decision.manage')) then raise exception 'FORBIDDEN'; end if;
  update public.administrative_decisions set status=v_to,
    approved_at=case when v_to='approved' then now() else approved_at end,
    approved_by=case when v_to='approved' then v_emp else approved_by end,
    scheduled_for=case when v_to='scheduled' then p_scheduled_for else scheduled_for end,
    published_at=case when v_to='published' then now() else published_at end,
    updated_at=now()
  where id=p_decision_id returning * into v_row;
  insert into public.decision_actions(decision_id,action_type,from_status,to_status,reason,actor_employee_id,actor_user_id)
  values(p_decision_id,p_action,v_from,v_to,nullif(trim(coalesce(p_reason,'')),''),v_emp,auth.uid());
  perform public.log_audit_event('decision.'||p_action,'governance',case when p_action='revoke' then 'warning' else 'info' end,'administrative_decisions',p_decision_id,'انتقال قرار من '||v_from||' إلى '||v_to,p_reason,jsonb_build_object('from',v_from,'to',v_to));
  return v_row;
end $$;

-- ============================================================================
-- ATT-01 [P1] — Timezone-correct lateness calculation.
-- Reinterpret shifts.start_time (a bare local clock time) in a real timezone
-- instead of UTC. Two overloads are provided:
--   * 5-arg: explicit p_timezone (the correct instant is derived in that tz).
--   * 4-arg (the EXISTING signature every current caller uses): REDEFINED to
--     delegate to the 5-arg overload with the operational default Africa/Cairo,
--     so all existing calls become correct with no caller change required.
-- This removes the UTC assumption that under-counted lateness by the branch
-- UTC offset (2-3h).
-- ============================================================================

-- 5-arg: timezone-explicit
create or replace function public.calculate_late_minutes(
  p_event_at   timestamptz,
  p_shift_start time,
  p_grace_minutes integer,
  p_reference_date date,
  p_timezone   text
)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  -- Build the expected shift-start instant by interpreting the local clock
  -- time (reference date + shift start) in the branch/operational timezone.
  select greatest(
    0,
    (
      floor(
        extract(epoch from (
          p_event_at
          - ( ( (coalesce(p_reference_date, (p_event_at at time zone p_timezone)::date))::timestamp + p_shift_start )
                at time zone p_timezone )
        )) / 60.0
      )::integer
    ) - coalesce(p_grace_minutes, 0)
  );
$$;
comment on function public.calculate_late_minutes(timestamptz,time,integer,date,text)
  is 'دقائق التأخير عن بداية الوردية بمنطقة زمنية صريحة بعد خصم السماحية. صفر إن لم يتأخر.';

-- 4-arg (existing signature): redefine to delegate with the operational tz,
-- fixing every current caller (0005 record_attendance_event, 0046) in place.
create or replace function public.calculate_late_minutes(
  p_event_at   timestamptz,
  p_shift_start time,
  p_grace_minutes integer default 0,
  p_reference_date date default null
)
returns integer
language sql
stable
set search_path = public, pg_temp
as $$
  select public.calculate_late_minutes(
    p_event_at, p_shift_start, p_grace_minutes, p_reference_date, 'Africa/Cairo'
  );
$$;
comment on function public.calculate_late_minutes(timestamptz,time,integer,date)
  is 'دقائق التأخير عن بداية الوردية (منطقة التشغيل Africa/Cairo) بعد خصم السماحية. صفر إن لم يتأخر. يفوّض إلى النسخة ذات المنطقة الصريحة.';

revoke execute on function public.calculate_late_minutes(timestamptz,time,integer,date,text) from public;
grant execute on function public.calculate_late_minutes(timestamptz,time,integer,date,text) to authenticated, service_role;
revoke execute on function public.calculate_late_minutes(timestamptz,time,integer,date) from public;
grant execute on function public.calculate_late_minutes(timestamptz,time,integer,date) to authenticated, service_role;

commit;
