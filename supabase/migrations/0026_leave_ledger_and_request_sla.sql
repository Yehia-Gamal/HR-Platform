-- Migration 0026: Leave ledger, reservation, balances and request SLA hardening
-- Single-source implementation; no direct balance mutation from clients.

alter table public.leave_requests
  add column if not exists duration_unit text not null default 'day',
  add column if not exists hours_count numeric(7,2),
  add column if not exists substitute_employee_id uuid references public.employees(id) on delete set null;

do $$ begin
  alter table public.leave_requests add constraint leave_requests_duration_unit_ck
    check (duration_unit in ('day','hour'));
exception when duplicate_object then null; end $$;

do $$ begin
  alter table public.leave_requests add constraint leave_requests_hours_ck
    check (hours_count is null or hours_count > 0);
exception when duplicate_object then null; end $$;

create table if not exists public.leave_balance_accounts (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete restrict,
  balance_year integer not null,
  opening_units numeric(10,2) not null default 0,
  accrued_units numeric(10,2) not null default 0,
  adjusted_units numeric(10,2) not null default 0,
  consumed_units numeric(10,2) not null default 0,
  reserved_units numeric(10,2) not null default 0,
  carryover_units numeric(10,2) not null default 0,
  expires_at date,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id),
  unique(employee_id, leave_type_id, balance_year)
);

create index if not exists ix_leave_balance_accounts_employee
  on public.leave_balance_accounts(employee_id, balance_year);

create table if not exists public.leave_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.leave_balance_accounts(id) on delete cascade,
  employee_id uuid not null references public.employees(id) on delete cascade,
  leave_type_id uuid not null references public.leave_types(id) on delete restrict,
  request_id uuid references public.requests(id) on delete restrict,
  entry_type text not null check (entry_type in ('opening','accrual','carryover','adjustment','reserve','release','consume','refund','expire')),
  units numeric(10,2) not null check (units <> 0),
  effective_date date not null default current_date,
  reason text,
  source_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique(source_key)
);

create index if not exists ix_leave_ledger_employee_date
  on public.leave_ledger_entries(employee_id, effective_date desc);
create index if not exists ix_leave_ledger_request
  on public.leave_ledger_entries(request_id) where request_id is not null;

alter table public.leave_balance_accounts enable row level security;
alter table public.leave_ledger_entries enable row level security;

drop policy if exists leave_balance_accounts_select on public.leave_balance_accounts;
create policy leave_balance_accounts_select on public.leave_balance_accounts
for select to authenticated using (
  public.current_is_full_access()
  or employee_id = public.current_employee_id()
  or public.can_access_employee(employee_id)
  or public.has_any_permission(array['requests.leave.balance.read','requests.leave.balance.adjust'])
);

drop policy if exists leave_ledger_entries_select on public.leave_ledger_entries;
create policy leave_ledger_entries_select on public.leave_ledger_entries
for select to authenticated using (
  public.current_is_full_access()
  or employee_id = public.current_employee_id()
  or public.can_access_employee(employee_id)
  or public.has_any_permission(array['requests.leave.balance.read','requests.leave.balance.adjust'])
);

-- No direct client writes. All mutations are RPC/trigger controlled.
revoke insert, update, delete on public.leave_balance_accounts from authenticated;
revoke insert, update, delete on public.leave_ledger_entries from authenticated;

create or replace function public.leave_request_units(p_leave_request_id uuid)
returns numeric
language sql stable security definer
set search_path = public, pg_temp
as $$
  select case
    when lr.duration_unit = 'hour' then coalesce(lr.hours_count,0)
    else coalesce(lr.days_count,0)
  end
  from public.leave_requests lr where lr.id = p_leave_request_id
$$;

create or replace function public.ensure_leave_account(
  p_employee_id uuid,
  p_leave_type_id uuid,
  p_year integer
) returns public.leave_balance_accounts
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_account public.leave_balance_accounts;
begin
  insert into public.leave_balance_accounts(employee_id, leave_type_id, balance_year, created_by)
  values (p_employee_id, p_leave_type_id, p_year, auth.uid())
  on conflict(employee_id, leave_type_id, balance_year) do nothing;

  select * into strict v_account from public.leave_balance_accounts
  where employee_id=p_employee_id and leave_type_id=p_leave_type_id and balance_year=p_year
  for update;
  return v_account;
end $$;

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
begin
  if p_units = 0 then raise exception 'LEAVE_UNITS_ZERO'; end if;
  v_account := public.ensure_leave_account(p_employee_id,p_leave_type_id,p_year);

  insert into public.leave_ledger_entries(account_id,employee_id,leave_type_id,request_id,entry_type,units,effective_date,reason,source_key,metadata,created_by)
  values(v_account.id,p_employee_id,p_leave_type_id,p_request_id,p_entry_type,p_units,current_date,p_reason,p_source_key,coalesce(p_metadata,'{}'::jsonb),auth.uid())
  on conflict(source_key) do update set source_key=excluded.source_key
  returning * into v_entry;

  -- Only apply aggregates for a newly inserted logical event.
  if v_entry.created_at < clock_timestamp() - interval '5 seconds' then return v_entry; end if;

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

create or replace function public.tg_leave_reserve_on_detail()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_affects boolean; v_units numeric; v_year integer;
begin
  select affects_balance into v_affects from public.leave_types where id=new.leave_type_id;
  if not coalesce(v_affects,false) then return new; end if;
  v_units := case when new.duration_unit='hour' then coalesce(new.hours_count,0) else coalesce(new.days_count,0) end;
  if v_units <= 0 then raise exception 'INVALID_LEAVE_DURATION'; end if;
  v_year := extract(year from new.start_date)::integer;
  perform public.apply_leave_ledger_entry(new.employee_id,new.leave_type_id,v_year,'reserve',v_units,'leave:reserve:'||new.request_id,new.request_id,'حجز رصيد عند تقديم الطلب',jsonb_build_object('durationUnit',new.duration_unit));
  return new;
end $$;

drop trigger if exists trg_leave_reserve_on_detail on public.leave_requests;
create trigger trg_leave_reserve_on_detail after insert on public.leave_requests
for each row execute function public.tg_leave_reserve_on_detail();

create or replace function public.tg_leave_settle_on_request_decision()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_lr public.leave_requests; v_affects boolean; v_units numeric; v_year integer;
begin
  if new.request_type <> 'leave' or old.status = new.status then return new; end if;
  select * into v_lr from public.leave_requests where request_id=new.id;
  if not found then return new; end if;
  select affects_balance into v_affects from public.leave_types where id=v_lr.leave_type_id;
  if not coalesce(v_affects,false) then return new; end if;
  v_units := case when v_lr.duration_unit='hour' then coalesce(v_lr.hours_count,0) else coalesce(v_lr.days_count,0) end;
  v_year := extract(year from v_lr.start_date)::integer;
  if new.status='approved' then
    perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'consume',v_units,'leave:consume:'||new.id,new.id,'خصم الرصيد بعد الاعتماد');
  elsif new.status in ('rejected','cancelled','withdrawn','expired') then
    perform public.apply_leave_ledger_entry(v_lr.employee_id,v_lr.leave_type_id,v_year,'release',v_units,'leave:release:'||new.id||':'||new.status,new.id,'تحرير الحجز بعد '||new.status);
  end if;
  return new;
end $$;

drop trigger if exists trg_leave_settle_on_request_decision on public.requests;
create trigger trg_leave_settle_on_request_decision after update of status on public.requests
for each row execute function public.tg_leave_settle_on_request_decision();

create or replace function public.adjust_leave_balance(
  p_employee_id uuid,p_leave_type_id uuid,p_year integer,p_units numeric,p_reason text
) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_entry public.leave_ledger_entries;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then raise exception 'FORBIDDEN'; end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
  v_entry := public.apply_leave_ledger_entry(p_employee_id,p_leave_type_id,p_year,'adjustment',p_units,'leave:adjust:'||gen_random_uuid(),null,p_reason);
  perform public.log_audit_event('leave.balance.adjusted','hr','warning','leave_balance_accounts',v_entry.account_id,'تعديل رصيد إجازة',p_reason,jsonb_build_object('employeeId',p_employee_id,'leaveTypeId',p_leave_type_id,'units',p_units,'year',p_year));
  return v_entry.id;
end $$;

create or replace function public.get_my_leave_balances(p_year integer default extract(year from current_date)::integer)
returns table(leave_type_id uuid,code text,name_ar text,available_units numeric,reserved_units numeric,consumed_units numeric,expires_at date)
language sql stable security definer set search_path=public,pg_temp as $$
  select lt.id,lt.code,lt.name_ar,
    coalesce(a.opening_units+a.accrued_units+a.adjusted_units+a.carryover_units-a.consumed_units-a.reserved_units,0),
    coalesce(a.reserved_units,0),coalesce(a.consumed_units,0),a.expires_at
  from public.leave_types lt
  left join public.leave_balance_accounts a on a.leave_type_id=lt.id and a.employee_id=public.current_employee_id() and a.balance_year=p_year
  where lt.is_active=true order by lt.sort_order,lt.name_ar
$$;

create or replace function public.process_request_sla(p_limit integer default 500)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer:=0; v_row record;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then raise exception 'FORBIDDEN'; end if;
  for v_row in select id from public.requests where status='pending' and workflow_status in ('submitted','in_review','awaiting_manager','awaiting_operator') and decision_due_at is not null and decision_due_at < now() and escalated_at is null order by decision_due_at limit greatest(1,least(p_limit,2000)) for update skip locked
  loop
    update public.requests set workflow_status='escalated',escalated_at=now(),updated_at=now() where id=v_row.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end $$;

revoke execute on function public.ensure_leave_account(uuid,uuid,integer) from public,authenticated;
revoke execute on function public.apply_leave_ledger_entry(uuid,uuid,integer,text,numeric,text,uuid,text,jsonb) from public,authenticated;
revoke execute on function public.adjust_leave_balance(uuid,uuid,integer,numeric,text) from public;
grant execute on function public.adjust_leave_balance(uuid,uuid,integer,numeric,text) to authenticated;
revoke execute on function public.get_my_leave_balances(integer) from public;
grant execute on function public.get_my_leave_balances(integer) to authenticated;
revoke execute on function public.process_request_sla(integer) from public,authenticated;
