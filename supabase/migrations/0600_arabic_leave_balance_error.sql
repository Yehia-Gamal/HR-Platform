-- 0600_arabic_leave_balance_error.sql
-- تحسين رسائل خطأ نفاد رصيد الإجازات لتظهر باللغة العربية الواضحة بدلاً من رمز الخطأ العام P0001

create or replace function public.apply_leave_ledger_entry(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_year integer,
  p_entry_type text,
  p_units numeric,
  p_source_key text,
  p_request_id uuid default null::uuid,
  p_reason text default null::text,
  p_metadata jsonb default '{}'::jsonb
)
returns public.leave_ledger_entries
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
  if p_units = 0 then
    raise exception 'عدد أيام الإجازة يجب ألا يساوي صفراً' using errcode = '22023';
  end if;
  if p_entry_type not in (
    'opening','accrual','carryover','adjustment','reserve','release',
    'consume','refund','expire','credit'
  ) then
    raise exception 'نوع حركة رصيد غير صالح: %', p_entry_type using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_source_key,'')),'') is null then
    raise exception 'مفتاح قيد الرصيد مطلوب' using errcode = '22023';
  end if;

  -- advisory lock: serialize per (employee, leave_type)
  v_lock_id := hashtextextended(p_employee_id::text || ':' || p_leave_type_id::text, 0);
  perform pg_advisory_xact_lock(v_lock_id);

  v_account := public.ensure_leave_account(p_employee_id, p_leave_type_id, p_year);

  -- idempotency: skip if source_key already processed
  select * into v_entry
  from public.leave_ledger_entries
  where source_key = p_source_key;
  if found then
    return v_entry;
  end if;

  if p_entry_type = 'opening' and v_account.opening_units <> 0 then
    select * into v_entry
    from public.leave_ledger_entries
    where account_id = v_account.id and entry_type = 'opening'
    order by created_at limit 1;
    if found then return v_entry; end if;
  end if;

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

  -- تطبيق القيد حسب النوع
  if p_entry_type = 'opening' then
    update public.leave_balance_accounts set opening_units = opening_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'accrual' then
    update public.leave_balance_accounts set accrued_units = accrued_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'carryover' then
    update public.leave_balance_accounts set carryover_units = carryover_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'adjustment' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'credit' then
    update public.leave_balance_accounts set adjusted_units = adjusted_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'reserve' then
    select opening_units + accrued_units + adjusted_units + carryover_units - consumed_units - reserved_units
      into v_available from public.leave_balance_accounts where id = v_account.id for update;
    if v_available < p_units then
      raise exception 'رصيد الإجازة غير كافٍ: الرصيد المتاح % يوم فقط، بينما المطلوب % يوم.',
        round(v_available, 2)::text,
        round(p_units, 2)::text
        using errcode = '22023';
    end if;
    update public.leave_balance_accounts set reserved_units = reserved_units + p_units, updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'release' then
    update public.leave_balance_accounts set reserved_units = greatest(0, reserved_units - abs(p_units)), updated_at = now() where id = v_account.id;
  elsif p_entry_type = 'consume' then
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
