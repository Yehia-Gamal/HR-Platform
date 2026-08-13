-- migration: 0382
-- description: apply_leave_ledger_entry — advisory lock + consume balance guard
-- أُعيدت الكتابة على schema الحقيقي (0026/0106): توقيع (uuid,uuid,integer,text,numeric,text,uuid,text,jsonb)
-- مع إبقاء نية الأصل: قفل advisory ضد السباقات + حارس الاستهلاك (consume لا يتجاوز reserved).

begin;

create or replace function public.apply_leave_ledger_entry(
  p_employee_id   uuid,
  p_leave_type_id uuid,
  p_year          integer,
  p_entry_type    text,   -- opening|accrual|carryover|adjustment|reserve|release|consume|refund|expire
  p_units         numeric,
  p_source_key    text,
  p_request_id    uuid default null,
  p_reason        text default null,
  p_metadata      jsonb default '{}'::jsonb
) returns public.leave_ledger_entries
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_account   public.leave_balance_accounts;
  v_entry     public.leave_ledger_entries;
  v_available numeric;
  v_lock_id   bigint;
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire'
  ) then raise exception 'INVALID_LEAVE_ENTRY_TYPE'; end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'LEAVE_SOURCE_KEY_REQUIRED';
  end if;

  -- ── advisory lock: serialize per (employee, leave_type) ──────────────────
  -- يمنع سباقات reserve/consume المتزامنة (0382).
  v_lock_id := hashtextextended(p_employee_id::text || ':' || p_leave_type_id::text, 0);
  perform pg_advisory_xact_lock(v_lock_id);

  v_account := public.ensure_leave_account(p_employee_id, p_leave_type_id, p_year);

  -- ── idempotency: skip if source_key already processed ────────────────────
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key;
  if found then
    return v_entry; -- already applied — idempotent return
  end if;

  if p_entry_type = 'opening' and v_account.opening_units <> 0 then
    select * into v_entry
    from public.leave_ledger_entries
    where account_id = v_account.id and entry_type = 'opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

  -- ── insert audit entry (unique(source_key) يمنع التكرار عند التزامن) ─────
  insert into public.leave_ledger_entries(
    account_id, employee_id, leave_type_id, request_id, entry_type, units,
    effective_date, reason, source_key, metadata, created_by
  ) values (
    v_account.id, p_employee_id, p_leave_type_id, p_request_id, p_entry_type, p_units,
    current_date, p_reason, p_source_key, coalesce(p_metadata, '{}'::jsonb), auth.uid()
  ) on conflict(source_key) do nothing returning * into v_entry;
  if not found then
    select * into strict v_entry from public.leave_ledger_entries
    where source_key = p_source_key;
    return v_entry;
  end if;

  -- ── apply entry by type على الأعمدة الحقيقية للرصيد ──────────────────────
  if p_entry_type = 'opening' then
    update public.leave_balance_accounts set opening_units = opening_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'accrual' then
    update public.leave_balance_accounts set accrued_units = accrued_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'carryover' then
    update public.leave_balance_accounts set carryover_units = carryover_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'adjustment' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'reserve' then
    select opening_units + accrued_units + adjusted_units + carryover_units - consumed_units - reserved_units
      into v_available from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'INSUFFICIENT_LEAVE_BALANCE: available=% requested=%', v_available, p_units;
    end if;
    update public.leave_balance_accounts set reserved_units = reserved_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'release' then
    update public.leave_balance_accounts set reserved_units = greatest(0, reserved_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'consume' then
    -- حارس 0382: لا يستهلك أكثر مما حُجز فعلياً
    select reserved_units into v_available
    from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'CONSUME_EXCEEDS_RESERVE: reserved=% requested=% (concurrent modification?)', v_available, p_units;
    end if;
    update public.leave_balance_accounts
      set reserved_units = greatest(0, reserved_units - abs(p_units)),
          consumed_units = consumed_units + abs(p_units),
          updated_at = now()
      where id = v_account.id;
  elsif p_entry_type = 'refund' then
    update public.leave_balance_accounts set consumed_units = greatest(0, consumed_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'expire' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units - abs(p_units), updated_at = now() where id = v_account.id;
  end if;

  return v_entry;
end;
$$;

revoke all on function public.apply_leave_ledger_entry(
  uuid, uuid, integer, text, numeric, text, uuid, text, jsonb
) from public, anon, authenticated;
grant execute on function public.apply_leave_ledger_entry(
  uuid, uuid, integer, text, numeric, text, uuid, text, jsonb
) to service_role;

commit;
