-- 0131_v17_dispute_admin_actions.sql
-- V17 §14: الإجراءات الإدارية لقضايا لجنة المنازعات
-- المسار: اقتراح (مقرر اللجنة) → قرار تنفيذي (المدير التنفيذي) → تنفيذ (HR) → توثيق
-- يطابق shared-contracts/disputes.ts: adminActionTypeSchema, executiveDecisionSchema, disputeAdminActionSchema

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. توسيع قيد الحالة ليشمل مراحل الإجراء الإداري
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.dispute_cases drop constraint if exists dispute_cases_status_check;
alter table public.dispute_cases add constraint dispute_cases_status_check check(status in (
  'draft','submitted','needs_more_information','accepted','rejected','under_review',
  'waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed',
  'committee_deliberation','settlement_pending','escalated_to_executive',
  'returned_to_committee','decision_issued',
  -- V17 §14: مراحل الإجراء الإداري
  'action_proposed','pending_execution','executed',
  'closed','reopened','cancelled_by_employee'
));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. أعمدة الإجراء الإداري على dispute_cases
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.dispute_cases
  -- اقتراح المقرر
  add column if not exists proposed_administrative_action text
    check(proposed_administrative_action is null or proposed_administrative_action in (
      'verbal_warning','written_warning','final_warning','salary_deduction',
      'suspension','demotion','termination','transfer','training_requirement','no_action')),
  add column if not exists proposed_action_detail text,
  add column if not exists proposed_at timestamptz,
  add column if not exists proposed_by uuid references public.employees(id) on delete set null,
  -- قرار المدير التنفيذي
  add column if not exists executive_decision text
    check(executive_decision is null or executive_decision in ('approved','modified','rejected','deferred')),
  add column if not exists executive_decision_reason text,
  add column if not exists executive_decision_at timestamptz,
  add column if not exists executive_decision_by uuid references public.employees(id) on delete set null,
  -- الإجراء المعتمد (قد يختلف عن المقترح إذا عدّله التنفيذي)
  add column if not exists approved_administrative_action text
    check(approved_administrative_action is null or approved_administrative_action in (
      'verbal_warning','written_warning','final_warning','salary_deduction',
      'suspension','demotion','termination','transfer','training_requirement','no_action')),
  add column if not exists approved_action_detail text,
  -- التنفيذ
  add column if not exists executed_at timestamptz,
  add column if not exists executed_by uuid references public.employees(id) on delete set null,
  add column if not exists execution_notes text;

-- فهرس للقضايا المعلقة التنفيذ
create index if not exists ix_dispute_cases_pending_exec
  on public.dispute_cases(status) where status in ('action_proposed','pending_execution');

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. صلاحيات الإجراء الإداري
-- ═══════════════════════════════════════════════════════════════════════════════

insert into public.permissions(code,module,resource,action,description,risk_level,is_sensitive)
values
  ('disputes.admin_action.propose','disputes','admin_action','propose','اقتراح الإجراء الإداري للقضية','critical',true),
  ('disputes.admin_action.decide','disputes','admin_action','decide','اتخاذ قرار تنفيذي بشأن الإجراء المقترح','critical',true),
  ('disputes.admin_action.execute','disputes','admin_action','execute','تنفيذ الإجراء الإداري المعتمد','sensitive',true)
on conflict(code) do update set
  description=excluded.description,risk_level=excluded.risk_level,is_sensitive=excluded.is_sensitive;

-- مقرر اللجنة → اقتراح
insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id, p.id, 'assigned_cases', true
from public.roles r
join public.permissions p on p.code = 'disputes.admin_action.propose'
where r.slug in ('committee-secretary','committee-chair')
on conflict(role_id,permission_id,scope) do nothing;

-- المدير التنفيذي → قرار
insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id, p.id, 'organization', true
from public.roles r
join public.permissions p on p.code = 'disputes.admin_action.decide'
where r.slug = 'executive-secretary'
on conflict(role_id,permission_id,scope) do nothing;

-- HR → تنفيذ
insert into public.role_permissions(role_id,permission_id,scope,requires_reason)
select r.id, p.id, 'organization', true
from public.roles r
join public.permissions p on p.code = 'disputes.admin_action.execute'
where r.slug in ('hr-manager','hr-specialist')
on conflict(role_id,permission_id,scope) do nothing;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. RPC: اقتراح الإجراء الإداري
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.propose_admin_action(
  p_case_id uuid,
  p_action  text,
  p_detail  text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v record;
begin
  -- صلاحية: مقرر اللجنة أو رئيسها أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.propose')
    or exists(
      select 1 from public.committee_members
      where case_id = p_case_id
        and employee_id = public.current_employee_id()
        and role_in_committee in ('secretary','chair')
        and is_active
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- تحقق من نوع الإجراء
  if p_action not in (
    'verbal_warning','written_warning','final_warning','salary_deduction',
    'suspension','demotion','termination','transfer','training_requirement','no_action'
  ) then
    raise exception 'INVALID_ACTION_TYPE' using errcode = '22023';
  end if;

  if nullif(trim(p_detail), '') is null then
    raise exception 'DETAIL_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  -- يجب أن تكون القضية في حالة "قرار صادر"
  if v.status <> 'decision_issued' then
    raise exception 'CASE_NOT_IN_DECISION_ISSUED' using errcode = '22023';
  end if;

  update public.dispute_cases set
    proposed_administrative_action = p_action,
    proposed_action_detail         = trim(p_detail),
    proposed_at                    = now(),
    proposed_by                    = public.current_employee_id(),
    status                         = 'action_proposed',
    updated_at                     = now()
  where id = p_case_id;

  -- سجلّ في dispute_actions
  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'propose_admin_action', 'decision_issued', 'action_proposed',
    trim(p_detail), public.current_employee_id(), auth.uid(),
    jsonb_build_object('proposed_action', p_action)
  );

  -- تدقيق
  perform public.log_audit_event(
    'dispute.admin_action_proposed', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'اقتراح إجراء إداري: ' || p_action,
    trim(p_detail),
    jsonb_build_object('action', p_action)
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. RPC: قرار المدير التنفيذي
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.decide_admin_action(
  p_case_id         uuid,
  p_decision        text,
  p_reason          text,
  p_modified_action text default null,
  p_modified_detail text default null
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v record;
  v_approved_action text;
  v_approved_detail text;
  v_new_status      text;
begin
  -- صلاحية: المدير التنفيذي أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.decide')
    or public.has_permission('disputes.executive.manage')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_decision not in ('approved','modified','rejected','deferred') then
    raise exception 'INVALID_DECISION' using errcode = '22023';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  if v.status <> 'action_proposed' then
    raise exception 'CASE_NOT_IN_ACTION_PROPOSED' using errcode = '22023';
  end if;

  -- تحديد الإجراء المعتمد
  if p_decision = 'approved' then
    v_approved_action := v.proposed_administrative_action;
    v_approved_detail := v.proposed_action_detail;
    v_new_status      := 'pending_execution';
  elsif p_decision = 'modified' then
    if p_modified_action is null then
      raise exception 'MODIFIED_ACTION_REQUIRED' using errcode = '22023';
    end if;
    if p_modified_action not in (
      'verbal_warning','written_warning','final_warning','salary_deduction',
      'suspension','demotion','termination','transfer','training_requirement','no_action'
    ) then
      raise exception 'INVALID_ACTION_TYPE' using errcode = '22023';
    end if;
    v_approved_action := p_modified_action;
    v_approved_detail := coalesce(nullif(trim(p_modified_detail), ''), v.proposed_action_detail);
    v_new_status      := 'pending_execution';
  else
    -- rejected / deferred → إعادة إلى decision_issued ليعيد المقرر الاقتراح
    v_new_status := 'decision_issued';
  end if;

  if p_decision in ('approved','modified') then
    update public.dispute_cases set
      executive_decision              = p_decision,
      executive_decision_reason       = trim(p_reason),
      executive_decision_at           = now(),
      executive_decision_by           = public.current_employee_id(),
      approved_administrative_action  = v_approved_action,
      approved_action_detail          = v_approved_detail,
      status                          = v_new_status,
      updated_at                      = now()
    where id = p_case_id;
  else
    update public.dispute_cases set
      executive_decision              = p_decision,
      executive_decision_reason       = trim(p_reason),
      executive_decision_at           = now(),
      executive_decision_by           = public.current_employee_id(),
      -- مسح الاقتراح ليعيد المقرر تقديمه
      proposed_administrative_action  = null,
      proposed_action_detail          = null,
      proposed_at                     = null,
      proposed_by                     = null,
      approved_administrative_action  = null,
      approved_action_detail          = null,
      status                          = v_new_status,
      updated_at                      = now()
    where id = p_case_id;
  end if;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'decide_admin_action', 'action_proposed', v_new_status,
    trim(p_reason), public.current_employee_id(), auth.uid(),
    jsonb_build_object(
      'decision', p_decision,
      'approved_action', v_approved_action,
      'proposed_action', v.proposed_administrative_action
    )
  );

  perform public.log_audit_event(
    'dispute.admin_action_decided', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'قرار تنفيذي: ' || p_decision,
    trim(p_reason),
    jsonb_build_object(
      'decision', p_decision,
      'approved_action', v_approved_action,
      'proposed_action', v.proposed_administrative_action
    )
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. RPC: تنفيذ الإجراء الإداري (HR)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.execute_admin_action(
  p_case_id uuid,
  p_notes   text
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v record;
begin
  -- صلاحية: HR أو full-access
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.admin_action.execute')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if nullif(trim(p_notes), '') is null then
    raise exception 'NOTES_REQUIRED' using errcode = '22023';
  end if;

  select * into strict v from public.dispute_cases where id = p_case_id for update;

  if v.status <> 'pending_execution' then
    raise exception 'CASE_NOT_PENDING_EXECUTION' using errcode = '22023';
  end if;

  if v.approved_administrative_action is null then
    raise exception 'NO_APPROVED_ACTION' using errcode = '22023';
  end if;

  update public.dispute_cases set
    executed_at      = now(),
    executed_by      = public.current_employee_id(),
    execution_notes  = trim(p_notes),
    status           = 'executed',
    updated_at       = now()
  where id = p_case_id;

  insert into public.dispute_actions(
    case_id, action_type, from_status, to_status,
    note, actor_employee_id, actor_user_id, metadata
  ) values (
    p_case_id, 'execute_admin_action', 'pending_execution', 'executed',
    trim(p_notes), public.current_employee_id(), auth.uid(),
    jsonb_build_object('action', v.approved_administrative_action)
  );

  perform public.log_audit_event(
    'dispute.admin_action_executed', 'workflow', 'notice',
    'dispute_cases', p_case_id,
    'تنفيذ إجراء: ' || v.approved_administrative_action,
    trim(p_notes),
    jsonb_build_object(
      'action', v.approved_administrative_action,
      'decision', v.executive_decision
    )
  );
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. صلاحيات التنفيذ — منع anonymous
-- ═══════════════════════════════════════════════════════════════════════════════

revoke execute on function public.propose_admin_action(uuid,text,text) from public, anon;
grant  execute on function public.propose_admin_action(uuid,text,text) to authenticated;

revoke execute on function public.decide_admin_action(uuid,text,text,text,text) from public, anon;
grant  execute on function public.decide_admin_action(uuid,text,text,text,text) to authenticated;

revoke execute on function public.execute_admin_action(uuid,text) from public, anon;
grant  execute on function public.execute_admin_action(uuid,text) to authenticated;
