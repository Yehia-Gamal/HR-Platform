-- ============================================================================
-- 0345 — سجل الانضباط: إجراءات تأديبية على الموظفين
-- ============================================================================
-- الفجوة: توجد صلاحيات relations.discipline.create / relations.discipline.approve
-- (مربوطة بدور committee-chair/executive-director) لكن لا يوجد جدول يخزنها —
-- سجل انضباط الموظف (تنبيه/إنذار/خصم/وقف/إنهاء) كان غائباً.
--
-- الميزة:
--   1) employee_discipline_actions: سجل الإجراءات التأديبية على الموظف
--      (action_type: verbal_warning|written_warning|salary_deduction|suspension|termination)
--      مع حالة سير الاعتماد (draft|pending|approved|rejected) وسبب + مرفق.
--   2) RLS: الموظف يقرأ سجل نفسه فقط؛ الحوكمة/اللجنة تقرأ وتنشئ؛
--      الاعتماد لذوي relations.discipline.approve.
--   3) RPCs:
--      • submit_discipline_action  — إنشاء إجراء من قبل صاحب صلاحية create
--      • decide_discipline_action  — اعتماد/رفض من صاحب صلاحية approve
--      • get_my_discipline_record  — سجل الموظف الخاص (مع مؤشر نشط)
--   4) عند الاعتماد تُسجَّل في audit و تُنشأ إشعار للموظف.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) جدول الإجراءات التأديبية
-- ═══════════════════════════════════════════════════════════════════════════

create table if not exists public.employee_discipline_actions (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  action_type text not null check (
    action_type in ('verbal_warning','written_warning','salary_deduction','suspension','termination')
  ),
  title text not null,
  description text not null,
  severity text not null default 'moderate' check (severity in ('low','moderate','high','critical')),
  amount numeric(12,2) check (amount is null or amount >= 0),
  effective_from date,
  effective_to date,
  status text not null default 'pending' check (status in ('draft','pending','approved','rejected')),
  decision_note text,
  decided_by uuid references public.employees(id) on delete set null,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  created_by uuid references auth.users(id)
);

comment on table public.employee_discipline_actions is
  'سجل الإجراءات التأديبية على الموظف (إنذار/خصم/وقف/إنهاء) مع سير اعتماد ثنائي';

create index if not exists ix_discipline_actions_employee on public.employee_discipline_actions(employee_id);
create index if not exists ix_discipline_actions_status on public.employee_discipline_actions(status);
create index if not exists ix_discipline_actions_created on public.employee_discipline_actions(created_at desc);

alter table public.employee_discipline_actions enable row level security;

drop trigger if exists trg_employee_discipline_actions_updated_at on public.employee_discipline_actions;
create trigger trg_employee_discipline_actions_updated_at before update on public.employee_discipline_actions
  for each row execute function public.tg_set_updated_at();

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) RLS — الموظف يقرأ سجله فقط، الحوكمة/اللجنة تدير السجل
-- ═══════════════════════════════════════════════════════════════════════════

drop policy if exists discipline_actions_select on public.employee_discipline_actions;
create policy discipline_actions_select on public.employee_discipline_actions
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.has_permission('relations.discipline.create')
    or public.has_permission('relations.discipline.approve')
    or public.current_is_full_access()
  );

drop policy if exists discipline_actions_insert on public.employee_discipline_actions;
create policy discipline_actions_insert on public.employee_discipline_actions
  for insert to authenticated
  with check (
    public.has_permission('relations.discipline.create')
    or public.current_is_full_access()
  );

drop policy if exists discipline_actions_update on public.employee_discipline_actions;
create policy discipline_actions_update on public.employee_discipline_actions
  for update to authenticated
  using (
    public.has_permission('relations.discipline.create')
    or public.has_permission('relations.discipline.approve')
    or public.current_is_full_access()
  )
  with check (
    public.has_permission('relations.discipline.create')
    or public.has_permission('relations.discipline.approve')
    or public.current_is_full_access()
  );

drop policy if exists discipline_actions_delete on public.employee_discipline_actions;
create policy discipline_actions_delete on public.employee_discipline_actions
  for delete to authenticated
  using (public.has_permission('relations.discipline.approve') or public.current_is_full_access());

-- ═══════════════════════════════════════════════════════════════════════════
-- 2.5) دالة تسمية نوع الإجراء التأديبي
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.discipline_action_type_label(p_type text)
returns text
language sql immutable strict
as $$
  select case p_type
    when 'verbal_warning' then 'تنبيه شفهي'
    when 'written_warning' then 'إنذار كتابي'
    when 'salary_deduction' then 'خصم من الراتب'
    when 'suspension' then 'إيقاف مؤقت'
    when 'termination' then 'إنهاء خدمة'
    else coalesce(p_type, '')
  end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) RPC — إنشاء إجراء تأديبي
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.submit_discipline_action(
  p_employee_id uuid,
  p_action_type text,
  p_title text,
  p_description text,
  p_severity text default 'moderate',
  p_amount numeric(12,2) default null,
  p_effective_from date default null,
  p_effective_to date default null
)
returns public.employee_discipline_actions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.create')) then
    raise exception 'FORBIDDEN: requires relations.discipline.create' using errcode = '42501';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and is_deleted = false) then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if p_action_type not in ('verbal_warning','written_warning','salary_deduction','suspension','termination') then
    raise exception 'invalid action_type' using errcode = '22023';
  end if;

  if p_action_type = 'salary_deduction' and (p_amount is null or p_amount <= 0) then
    raise exception 'amount is required for salary deduction' using errcode = '22023';
  end if;

  insert into public.employee_discipline_actions(
    employee_id, action_type, title, description, severity, amount,
    effective_from, effective_to, status, created_by)
  values (
    p_employee_id, p_action_type, trim(p_title), trim(p_description), p_severity, p_amount,
    p_effective_from, p_effective_to, 'pending', auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.submitted', 'compliance', 'warning',
    'employee_discipline_actions', v_row.id,
    'إجراء تأديبي جديد بانتظار الاعتماد', null,
    jsonb_build_object('employeeId', p_employee_id, 'actionType', p_action_type));

  perform public.notify_employee(
    p_employee_id,
    'إجراء تأديبي بانتظار المراجعة',
    'تم تسجيل إجراء (' || public.discipline_action_type_label(p_action_type) || ') على ملفك وهو بانتظار الاعتماد.',
    'general', 'normal', null, null, '{}'::jsonb
  );

  return v_row;
end;
$$;

revoke execute on function public.submit_discipline_action(
  uuid, text, text, text, text, numeric, date, date) from public, anon;
grant execute on function public.submit_discipline_action(
  uuid, text, text, text, text, numeric, date, date) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) RPC — اعتماد/رفض إجراء تأديبي
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.decide_discipline_action(
  p_action_id uuid,
  p_decision text,
  p_note text default null
)
returns public.employee_discipline_actions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.approve')) then
    raise exception 'FORBIDDEN: requires relations.discipline.approve' using errcode = '42501';
  end if;

  select * into v_row from public.employee_discipline_actions where id = p_action_id;
  if not found then
    raise exception 'discipline_action_not_found' using errcode = 'P0002';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'discipline_action_not_pending' using errcode = '22023';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;

  update public.employee_discipline_actions
  set status = p_decision,
      decision_note = p_note,
      decided_by = v_me,
      decided_at = now(),
      updated_at = now()
  where id = p_action_id
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.' || p_decision, 'compliance',
    case when p_decision = 'approved' then 'high' else 'info' end,
    'employee_discipline_actions', v_row.id,
    case when p_decision = 'approved' then 'تم اعتماد الإجراء التأديبي' else 'تم رفض الإجراء التأديبي' end,
    null,
    jsonb_build_object('employeeId', v_row.employee_id, 'actionId', v_row.id, 'note', p_note));

  perform public.notify_employee(
    v_row.employee_id,
    case when p_decision = 'approved' then 'تم اعتماد إجراء تأديبي على ملفك' else 'تم رفض إجراء تأديبي مسجل على ملفك' end,
    coalesce(nullif(trim(p_note), ''), 'يرجى مراجعة سجلك من قسم الانضباط.'),
    'general', case when p_decision = 'approved' then 'normal' else 'low' end,
    null, null, '{}'::jsonb
  );

  return v_row;
end;
$$;

revoke execute on function public.decide_discipline_action(uuid, text, text) from public, anon;
grant execute on function public.decide_discipline_action(uuid, text, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) RPC — سجل الموظف الخاص (لا يظهر سوى المعتمد والنشط)
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_my_discipline_record(p_limit int default 50)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', d.id,
      'actionType', d.action_type,
      'title', d.title,
      'description', d.description,
      'severity', d.severity,
      'amount', d.amount,
      'effectiveFrom', d.effective_from,
      'effectiveTo', d.effective_to,
      'status', d.status,
      'decidedAt', d.decided_at,
      'createdAt', d.created_at
    ) order by d.created_at desc
  ), '[]'::jsonb)
  from public.employee_discipline_actions d
  where d.employee_id = public.current_employee_id()
    and d.status = 'approved'
  limit p_limit;
$$;

revoke execute on function public.get_my_discipline_record(int) from public, anon;
grant execute on function public.get_my_discipline_record(int) to authenticated;

notify pgrst, 'reload schema';

commit;
