-- migration: 0382
-- description: apply_leave_ledger_entry — advisory lock + consume balance guard

begin;

create or replace function public.apply_leave_ledger_entry(
  p_employee_id   integer,
  p_leave_type_id integer,
  p_entry_type    text,   -- opening|accrual|carryover|adjustment|reserve|release|consume|refund|expire
  p_units         numeric,
  p_source_key    text,
  p_note          text    default null,
  p_period_month  date    default null
) returns public.leave_ledger_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account  public.leave_balance_accounts%rowtype;
  v_entry    public.leave_ledger_entries%rowtype;
  v_delta    numeric;
  v_lock_id  bigint;
begin
  -- ── advisory lock: serialize per (employee, leave_type) ──────────────────
  -- prevents concurrent reserve/consume race conditions
  v_lock_id := (p_employee_id::bigint << 20) | (p_leave_type_id::bigint & 1048575);
  perform pg_advisory_xact_lock(v_lock_id);

  -- ── idempotency: skip if source_key already processed ────────────────────
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key
    and employee_id = p_employee_id
    and leave_type_id = p_leave_type_id;

  if found then
    return v_entry; -- already applied — idempotent return
  end if;

  -- ── get or create balance account ────────────────────────────────────────
  select * into v_account
  from public.leave_balance_accounts
  where employee_id = p_employee_id and leave_type_id = p_leave_type_id
  for update; -- lock the row for this transaction

  if not found then
    insert into public.leave_balance_accounts(employee_id, leave_type_id, available_units, reserved_units, consumed_units)
    values (p_employee_id, p_leave_type_id, 0, 0, 0)
    returning * into v_account;
  end if;

  -- ── apply entry by type ──────────────────────────────────────────────────
  case p_entry_type
    when 'opening', 'accrual', 'carryover', 'adjustment' then
      v_delta := p_units;
      update public.leave_balance_accounts
      set available_units = available_units + v_delta,
          updated_at = now()
      where id = v_account.id;

    when 'reserve' then
      if v_account.available_units < p_units then
        raise exception 'INSUFFICIENT_LEAVE_BALANCE: available=% requested=%',
          v_account.available_units, p_units;
      end if;
      update public.leave_balance_accounts
      set available_units = available_units - p_units,
          reserved_units  = reserved_units  + p_units,
          updated_at = now()
      where id = v_account.id;
      v_delta := -p_units;

    when 'release' then
      update public.leave_balance_accounts
      set available_units = available_units + least(p_units, reserved_units),
          reserved_units  = greatest(0, reserved_units - p_units),
          updated_at = now()
      where id = v_account.id;
      v_delta := p_units;

    when 'consume' then
      -- FIX #6: guard against consuming more than was reserved
      if v_account.reserved_units < p_units then
        raise exception 'CONSUME_EXCEEDS_RESERVE: reserved=% requested=% (concurrent modification?)',
          v_account.reserved_units, p_units;
      end if;
      update public.leave_balance_accounts
      set reserved_units  = reserved_units  - p_units,
          consumed_units  = consumed_units  + p_units,
          updated_at = now()
      where id = v_account.id;
      v_delta := 0;

    when 'refund' then
      update public.leave_balance_accounts
      set consumed_units  = greatest(0, consumed_units  - p_units),
          available_units = available_units + p_units,
          updated_at = now()
      where id = v_account.id;
      v_delta := p_units;

    when 'expire' then
      update public.leave_balance_accounts
      set available_units = greatest(0, available_units - p_units),
          updated_at = now()
      where id = v_account.id;
      v_delta := -p_units;

    else
      raise exception 'UNKNOWN_ENTRY_TYPE: %', p_entry_type;
  end case;

  -- ── insert audit entry ───────────────────────────────────────────────────
  insert into public.leave_ledger_entries(
    employee_id, leave_type_id, entry_type, units, delta,
    source_key, note, period_month, created_at
  )
  values (
    p_employee_id, p_leave_type_id, p_entry_type, p_units, v_delta,
    p_source_key, p_note, p_period_month, now()
  )
  returning * into v_entry;

  return v_entry;
end;
$$;

revoke all on function public.apply_leave_ledger_entry(integer,integer,text,numeric,text,text,date) from anon, authenticated;
grant execute on function public.apply_leave_ledger_entry(integer,integer,text,numeric,text,text,date) to authenticated;

commit;
