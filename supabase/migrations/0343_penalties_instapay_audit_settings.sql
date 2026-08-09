-- =====================================================================
-- 0343: مخالفات مالية + دفعات InstaPay + سجل تدقيق تفاعلي + إعدادات نظام
-- ---------------------------------------------------------------------
-- أربع ميزات تطويرية لنظام HR حقيقي:
--   1) employee_penalties: مخالفة مالية على موظف تُخصم من راتبه (تُرفق
--      بدورة رواتب عبر payroll_run_id عند الحجز).
--   2) payroll_instapay_batches / _items: دفعة InstaPay لصرف الرواتب عبر
--      محفظة/رقم جوال الموظف. توليد دفعة من payslips + تعليمها كمدفوعة.
--   3) get_audit_trail_page: سجل تدقيق تفاعلي (pagination + فلاتر) فوق
--      audit_events للمديرين (audit.view).
--   4) get_editable_system_settings / update_system_settings: قراءة وتحديث
--      إعدادات النظام القابلة للتعديل من واجهة (settings.manage).
--
-- Idempotent بالكامل: CREATE TABLE IF NOT EXISTS + CREATE OR REPLACE.
-- =====================================================================

-- ─── 1) المخالفات المالية ──────────────────────────────────────────────
create table if not exists public.employee_penalties (
  id              uuid primary key default gen_random_uuid(),
  employee_id     uuid not null references public.employees(id) on delete cascade,
  penalty_type    text not null check (penalty_type in (
                    'attendance', 'late', 'absence', 'misconduct', 'policy',
                    'damage', 'client_complaint', 'other')),
  amount          numeric(12,2) not null check (amount >= 0),
  currency        text not null default 'EGP',
  reason          text not null,
  evidence_ref    text,
  status          text not null default 'issued' check (status in ('issued', 'deducted', 'waived', 'cancelled')),
  payroll_run_id  uuid references public.payroll_runs(id) on delete set null,
  issued_by       uuid not null references public.employees(id),
  issued_at       timestamptz not null default now(),
  waived_by       uuid references public.employees(id),
  waived_at       timestamptz,
  waive_reason    text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid
);

create index if not exists employee_penalties_employee_idx
  on public.employee_penalties (employee_id);
create index if not exists employee_penalties_status_idx
  on public.employee_penalties (status);
create index if not exists employee_penalties_payroll_idx
  on public.employee_penalties (payroll_run_id);

-- ─── 2) دفعات InstaPay ────────────────────────────────────────────────
create table if not exists public.payroll_instapay_batches (
  id               uuid primary key default gen_random_uuid(),
  payroll_run_id   uuid not null references public.payroll_runs(id) on delete cascade,
  batch_reference  text unique,
  total_amount     numeric(14,2) not null default 0,
  item_count       integer not null default 0,
  status           text not null default 'generated' check (status in ('generated', 'sent', 'partially_paid', 'paid', 'failed')),
  sent_at          timestamptz,
  completed_at     timestamptz,
  created_by       uuid,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table if not exists public.payroll_instapay_items (
  id           uuid primary key default gen_random_uuid(),
  batch_id     uuid not null references public.payroll_instapay_batches(id) on delete cascade,
  employee_id  uuid not null references public.employees(id),
  payslip_id   uuid references public.payslips(id),
  mobile_e164  text,
  amount       numeric(12,2) not null check (amount > 0),
  status       text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  failure_code text,
  paid_at      timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists payroll_instapay_items_batch_idx
  on public.payroll_instapay_items (batch_id);

-- ─── 3) RPC: قائمة المخالفات ───────────────────────────────────────────
create or replace function public.get_employee_penalties(
  p_employee_id uuid default null,
  p_status text default null,
  p_payroll_run_id uuid default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve', 'people.employee.read'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'employeeId', p.employee_id,
      'employeeCode', e.employee_code,
      'employeeName', e.full_name_ar,
      'departmentName', d.name,
      'penaltyType', p.penalty_type,
      'amount', p.amount,
      'currency', p.currency,
      'reason', p.reason,
      'evidenceRef', p.evidence_ref,
      'status', p.status,
      'payrollRunId', p.payroll_run_id,
      'issuedBy', p.issued_by,
      'issuedAt', p.issued_at,
      'waivedBy', p.waived_by,
      'waivedAt', p.waived_at,
      'waiveReason', p.waive_reason)
      order by p.issued_at desc)
    from public.employee_penalties p
    join public.employees e on e.id = p.employee_id
    left join public.departments d on d.id = e.department_id
    where (p_employee_id is null or p.employee_id = p_employee_id)
      and (p_status is null or p.status = p_status)
      and (p_payroll_run_id is null or p.payroll_run_id = p_payroll_run_id)
    limit greatest(0, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end $$;

-- ─── 4) RPC: إضافة مخالفة ──────────────────────────────────────────────
create or replace function public.add_employee_penalty(
  p_employee_id uuid,
  p_penalty_type text,
  p_amount numeric,
  p_reason text,
  p_evidence_ref text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'invalid amount' using errcode='22023'; end if;
  if nullif(trim(p_penalty_type), '') is null then raise exception 'invalid penalty type' using errcode='22023'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists (select 1 from public.employees where id = p_employee_id and not is_deleted) then
    raise exception 'employee not found' using errcode='P0002';
  end if;

  insert into public.employee_penalties(
    employee_id, penalty_type, amount, currency, reason, evidence_ref,
    status, issued_by, issued_at, created_by)
  values (
    p_employee_id, p_penalty_type, p_amount, 'EGP', p_reason, p_evidence_ref,
    'issued', v_me, now(), auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'penalty.issued', 'financial', 'warning',
    'employee_penalties', v_row.id, 'إصدار مخالفة مالية', null,
    jsonb_build_object('employeeId', p_employee_id, 'amount', p_amount, 'type', p_penalty_type));

  return jsonb_build_object(
    'id', v_row.id, 'employeeId', v_row.employee_id, 'amount', v_row.amount,
    'penaltyType', v_row.penalty_type, 'status', v_row.status, 'issuedAt', v_row.issued_at);
end $$;

-- ─── 5) RPC: إلغاء/إسقاط مخالفة ───────────────────────────────────────
create or replace function public.waive_employee_penalty(
  p_penalty_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;

  update public.employee_penalties
     set status = 'waived', waived_by = v_me, waived_at = now(), waive_reason = p_reason,
         updated_at = now()
   where id = p_penalty_id
     and status in ('issued', 'deducted')
  returning * into v_row;

  if v_row.id is null then raise exception 'penalty not found or not waivable' using errcode='P0002'; end if;

  perform public.log_audit_event(
    'penalty.waived', 'financial', 'info',
    'employee_penalties', v_row.id, 'إسقاط مخالفة مالية', null,
    jsonb_build_object('employeeId', v_row.employee_id, 'amount', v_row.amount));

  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'waivedAt', v_row.waived_at);
end $$;

-- ─── 6) RPC: توليد دفعة InstaPay من دورة رواتب ────────────────────────
create or replace function public.generate_instapay_batch(
  p_payroll_run_id uuid
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_batch public.payroll_instapay_batches;
  v_count integer;
  v_total numeric;
  v_ref text;
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.payroll_runs
    where id = p_payroll_run_id and status in ('approved', 'posted')
  ) then
    raise exception 'payroll run must be approved or posted' using errcode='P0002';
  end if;

  select count(*), coalesce(sum(pl.net_amount), 0)
    into v_count, v_total
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  if v_count = 0 then raise exception 'no payable slips with mobile numbers' using errcode='P0002'; end if;

  v_ref := 'IP-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(p_payroll_run_id::text, '-', ''), 1, 8));

  insert into public.payroll_instapay_batches(
    payroll_run_id, batch_reference, total_amount, item_count, status, created_by)
  values (p_payroll_run_id, v_ref, v_total, v_count, 'generated', auth.uid())
  returning * into v_batch;

  insert into public.payroll_instapay_items(batch_id, employee_id, payslip_id, mobile_e164, amount)
  select v_batch.id, pl.employee_id, pl.id, e.phone_e164, pl.net_amount
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  perform public.log_audit_event(
    'instapay.batch_generated', 'financial', 'info',
    'payroll_instapay_batches', v_batch.id, 'توليد دفعة InstaPay لصرف الرواتب', null,
    jsonb_build_object('payrollRunId', p_payroll_run_id, 'reference', v_ref, 'items', v_count, 'total', v_total));

  return jsonb_build_object(
    'id', v_batch.id, 'reference', v_batch.batch_reference,
    'totalAmount', v_batch.total_amount, 'itemCount', v_batch.item_count,
    'status', v_batch.status);
end $$;

-- ─── 7) RPC: قائمة دفعات InstaPay ─────────────────────────────────────
create or replace function public.list_instapay_batches(
  p_payroll_run_id uuid default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve', 'payroll.payslip.read'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', b.id,
      'payrollRunId', b.payroll_run_id,
      'periodMonth', r.period_month,
      'batchReference', b.batch_reference,
      'totalAmount', b.total_amount,
      'itemCount', b.item_count,
      'status', b.status,
      'sentAt', b.sent_at,
      'completedAt', b.completed_at,
      'createdAt', b.created_at,
      'items', (select coalesce(jsonb_agg(jsonb_build_object(
                  'id', i.id, 'employeeId', i.employee_id,
                  'employeeName', e.full_name_ar,
                  'mobileE164', i.mobile_e164, 'amount', i.amount,
                  'status', i.status, 'paidAt', i.paid_at)), '[]'::jsonb)
               from public.payroll_instapay_items i
               left join public.employees e on e.id = i.employee_id
               where i.batch_id = b.id))
      order by b.created_at desc)
    from public.payroll_instapay_batches b
    join public.payroll_runs r on r.id = b.payroll_run_id
    where (p_payroll_run_id is null or b.payroll_run_id = p_payroll_run_id)
    limit greatest(0, p_limit) offset greatest(0, p_offset)
  ), '[]'::jsonb);
end $$;

-- ─── 8) RPC: سجل تدقيق تفاعلي ─────────────────────────────────────────
create or replace function public.get_audit_trail_page(
  p_category text default null,
  p_event_type text default null,
  p_severity text default null,
  p_employee_id uuid default null,
  p_target_table text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_total integer;
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['audit.view', 'audit.log.view', 'audit.event.view', 'system.audit.read'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  select count(*) into v_total
  from public.audit_events a
  where (p_category is null or a.category = p_category)
    and (p_event_type is null or a.event_type = p_event_type)
    and (p_severity is null or a.severity = p_severity)
    and (p_employee_id is null or a.actor_employee_id = p_employee_id)
    and (p_target_table is null or a.target_table = p_target_table)
    and (p_from is null or a.occurred_at >= p_from)
    and (p_to is null or a.occurred_at <= p_to);

  return jsonb_build_object(
    'total', v_total,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'eventType', a.event_type,
        'category', a.category,
        'severity', a.severity,
        'actorUserId', a.actor_user_id,
        'actorEmployeeId', a.actor_employee_id,
        'actorName', e.full_name_ar,
        'targetTable', a.target_table,
        'targetId', a.target_id,
        'summaryAr', a.summary_ar,
        'metadata', a.metadata,
        'occurredAt', a.occurred_at)
        order by a.occurred_at desc)
      from public.audit_events a
      left join public.employees e on e.id = a.actor_employee_id
      where (p_category is null or a.category = p_category)
        and (p_event_type is null or a.event_type = p_event_type)
        and (p_severity is null or a.severity = p_severity)
        and (p_employee_id is null or a.actor_employee_id = p_employee_id)
        and (p_target_table is null or a.target_table = p_target_table)
        and (p_from is null or a.occurred_at >= p_from)
        and (p_to is null or a.occurred_at <= p_to)
      limit greatest(0, p_limit) offset greatest(0, p_offset)
    ), '[]'::jsonb));
end $$;

-- ─── 9) RPC: إعدادات النظام القابلة للتعديل ───────────────────────────
create or replace function public.get_editable_system_settings(
  p_group_name text default null
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['settings.manage', 'settings.read', 'system.settings.read'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'key', s.key,
      'value', s.value,
      'valueType', s.value_type,
      'groupName', s.group_name,
      'labelAr', s.label_ar,
      'description', s.description,
      'isSecret', s.is_secret,
      'isEditable', s.is_editable)
      order by s.group_name, s.key)
    from public.system_settings s
    where s.is_editable = true
      and (p_group_name is null or s.group_name = p_group_name)
  ), '[]'::jsonb);
end $$;

-- ─── 10) RPC: تحديث إعدادات النظام ────────────────────────────────────
create or replace function public.update_system_settings(
  p_updates jsonb
)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_item jsonb;
  v_key text;
  v_val text;
  v_updated integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('settings.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'object' then
    raise exception 'updates must be a json object' using errcode='22023';
  end if;

  for v_item in select * from jsonb_each(p_updates)
  loop
    v_key := v_item ->> 'key';
    v_val := (v_item -> 'value')::text;
    update public.system_settings
       set value = v_val,
           updated_at = now()
     where key = v_key
       and is_editable = true
       and is_secret = false;
    if found then v_updated := v_updated + 1; end if;
  end loop;

  if v_updated > 0 then
    perform public.log_audit_event(
      'settings.updated', 'system', 'info',
      'system_settings', null, 'تحديث إعدادات النظام', null,
      jsonb_build_object('updatedKeys', v_updated));
  end if;

  return v_updated;
end $$;

-- ─── منح الصلاحيات ────────────────────────────────────────────────────
revoke execute on function public.get_employee_penalties(uuid, text, uuid, integer, integer) from public, anon;
revoke execute on function public.add_employee_penalty(uuid, text, numeric, text, text) from public, anon;
revoke execute on function public.waive_employee_penalty(uuid, text) from public, anon;
revoke execute on function public.generate_instapay_batch(uuid) from public, anon;
revoke execute on function public.list_instapay_batches(uuid, integer, integer) from public, anon;
revoke execute on function public.get_audit_trail_page(text, text, text, uuid, text, timestamptz, timestamptz, integer, integer) from public, anon;
revoke execute on function public.get_editable_system_settings(text) from public, anon;
revoke execute on function public.update_system_settings(jsonb) from public, anon;

grant execute on function public.get_employee_penalties(uuid, text, uuid, integer, integer) to authenticated;
grant execute on function public.add_employee_penalty(uuid, text, numeric, text, text) to authenticated;
grant execute on function public.waive_employee_penalty(uuid, text) to authenticated;
grant execute on function public.generate_instapay_batch(uuid) to authenticated;
grant execute on function public.list_instapay_batches(uuid, integer, integer) to authenticated;
grant execute on function public.get_audit_trail_page(text, text, text, uuid, text, timestamptz, timestamptz, integer, integer) to authenticated;
grant execute on function public.get_editable_system_settings(text) to authenticated;
grant execute on function public.update_system_settings(jsonb) to authenticated;
