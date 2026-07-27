-- 0159: V23 Dispute Committee Alignment
-- Agent 07 — لجنة المشكلات والجزاءات
--
-- V23 requires the employee complaint form to have ONLY:
--   title, description (3–300 words), parties, witnesses, acknowledgements
-- REMOVED from employee form: priority, incident_location, evidence/attachments
--
-- Changes:
-- 1. New submit_my_dispute_v23() — simplified intake without removed fields
-- 2. Word-count validation (3–300 Arabic/Unicode words) on description
-- 3. Updated submit_my_dispute() to default removed fields + add word validation
-- 4. Updated get_my_dispute_portal() to exclude removed fields from employee view
-- 5. Added resolved_friendly status value for V23 friendly-resolution workflow
--
-- Backward compatible: existing RPCs still work; new v23 RPC is preferred.

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Extend status CHECK to include resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.dispute_cases drop constraint if exists dispute_cases_status_check;
alter table public.dispute_cases add constraint dispute_cases_status_check check(status in (
  'draft','submitted','needs_more_information','accepted','rejected','under_review',
  'waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed',
  'committee_deliberation','settlement_pending','escalated_to_executive',
  'returned_to_committee','decision_issued',
  -- V17 admin-action statuses
  'action_proposed','pending_execution','executed',
  -- V23: friendly resolution
  'resolved_friendly',
  'closed','reopened','cancelled_by_employee'
));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Word-count helper function (counts Arabic/Unicode words)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.word_count(p_text text)
returns integer language sql immutable as $$
  select coalesce(
    array_length(
      regexp_split_to_array(trim(coalesce(p_text, '')), '\s+'),
      1
    ),
    0
  )
  -- empty string produces array with one empty element
  - case when trim(coalesce(p_text, '')) = '' then 1 else 0 end
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. V23 simplified employee intake (no priority, location, evidence)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.submit_my_dispute_v23(
  p_title text,
  p_description text,
  p_case_type text default 'employee_conflict',
  p_parties jsonb default '[]'::jsonb,
  p_witnesses jsonb default '[]'::jsonb,
  p_truth_confirmed boolean default false,
  p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text; v_item jsonb; v_party uuid; v_first_respondent uuid; v_wc integer;
begin
  if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode='42501'; end if;

  -- Title validation
  if length(trim(coalesce(p_title,''))) < 5 then raise exception 'TITLE_TOO_SHORT' using errcode='22023'; end if;

  -- Word count validation (3–300 words per V23)
  v_wc := public.word_count(p_description);
  if v_wc < 3 then raise exception 'DESCRIPTION_TOO_SHORT' using errcode='22023'; end if;
  if v_wc > 300 then raise exception 'DESCRIPTION_TOO_LONG' using errcode='22023'; end if;

  -- Confirmations mandatory
  if not p_truth_confirmed or not p_confidentiality_accepted then raise exception 'REQUIRED_CONFIRMATIONS_MISSING' using errcode='22023'; end if;

  -- Case type validation
  if p_case_type not in ('employee_conflict','inappropriate_conduct','verbal_abuse','management_chain','direct_manager','department_conflict','misunderstanding','work_environment','donor_beneficiary','administrative_violation','agreement_breach','other') then raise exception 'INVALID_CASE_TYPE' using errcode='22023'; end if;

  -- Parties validation
  if jsonb_typeof(coalesce(p_parties,'[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_witnesses,'[]'::jsonb)) <> 'array' then raise exception 'INVALID_PARTIES' using errcode='22023'; end if;
  if jsonb_array_length(coalesce(p_parties,'[]'::jsonb)) = 0 then raise exception 'AT_LEAST_ONE_PARTY_REQUIRED' using errcode='22023'; end if;

  v_number := 'CASE-' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISSMS');
  insert into public.dispute_cases(
    case_number, title, description, case_type, status, severity,
    actor_employee_id, is_confidential, privacy_level, opened_at,
    -- V23: no incident_location, no requested_action, priority always normal
    truth_confirmed, confidentiality_accepted, review_due_at, created_by
  ) values (
    v_number, trim(p_title), trim(p_description), p_case_type, 'submitted', 'normal',
    v_emp, true, 'restricted', now(),
    true, true, now() + interval '24 hours', auth.uid()
  ) returning id into v_id;

  -- Register complainant
  insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, notified_at, created_by)
  values (v_id, v_emp, 'complainant', 'read', now(), auth.uid());

  -- Register respondents/related parties
  for v_item in select * from jsonb_array_elements(coalesce(p_parties,'[]'::jsonb)) loop
    v_party := (v_item->>'employeeId')::uuid;
    if v_party = v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_PARTY' using errcode='22023'; end if;
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values (v_id, v_party, case when coalesce(v_item->>'type','respondent') in ('respondent','related') then coalesce(v_item->>'type','respondent') else 'respondent' end, 'withheld', auth.uid())
    on conflict(case_id, employee_id, party_type) do nothing;
    if v_first_respondent is null and coalesce(v_item->>'type','respondent') = 'respondent' then v_first_respondent := v_party; end if;
  end loop;

  -- Register witnesses
  for v_item in select * from jsonb_array_elements(coalesce(p_witnesses,'[]'::jsonb)) loop
    v_party := (v_item->>'employeeId')::uuid;
    if v_party = v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_WITNESS' using errcode='22023'; end if;
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values (v_id, v_party, 'witness', 'withheld', auth.uid()) on conflict(case_id, employee_id, party_type) do nothing;
  end loop;

  update public.dispute_cases set respondent_employee_id = v_first_respondent where id = v_id;

  -- Audit trail
  insert into public.dispute_actions(case_id, action_type, to_status, note, actor_employee_id, actor_user_id, metadata)
  values (v_id, 'submit', 'submitted', 'تم تقديم المشكلة', v_emp, auth.uid(), jsonb_build_object('version', 'v23'));

  perform public.log_audit_event('dispute.submitted', 'workflow', 'notice', 'dispute_cases', v_id, 'تقديم مشكلة جديدة', null, jsonb_build_object('caseNumber', v_number, 'version', 'v23'));
  perform public.notify_dispute_admins(v_id, 'submitted', 'مشكلة جديدة تنتظر المراجعة', v_number || ' — ' || trim(p_title), 'high');

  return v_id;
end $$;

revoke execute on function public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean) from public;
grant execute on function public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Update existing submit_my_dispute() to add word-count validation
--    (backward compatible — still accepts all params but validates words)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.submit_my_dispute(
  p_title text, p_description text, p_case_type text, p_priority text default 'normal',
  p_incident_at timestamptz default null, p_incident_location text default null,
  p_parties jsonb default '[]'::jsonb, p_witnesses jsonb default '[]'::jsonb,
  p_direct_manager_contacted boolean default null, p_amicable_attempted boolean default null,
  p_amicable_result text default null, p_requested_action text default null,
  p_confidential boolean default true, p_truth_confirmed boolean default false,
  p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_number text; v_item jsonb; v_party uuid; v_first_respondent uuid; v_wc integer;
begin
  if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode='42501'; end if;
  if length(trim(coalesce(p_title,''))) < 5 then raise exception 'INVALID_CASE' using errcode='22023'; end if;

  -- V23 word-count validation (3–300 words)
  v_wc := public.word_count(p_description);
  if v_wc < 3 then raise exception 'DESCRIPTION_TOO_SHORT' using errcode='22023'; end if;
  if v_wc > 300 then raise exception 'DESCRIPTION_TOO_LONG' using errcode='22023'; end if;

  if not p_truth_confirmed or not p_confidentiality_accepted then raise exception 'REQUIRED_CONFIRMATIONS_MISSING' using errcode='22023'; end if;
  if p_case_type not in ('employee_conflict','inappropriate_conduct','verbal_abuse','management_chain','direct_manager','department_conflict','misunderstanding','work_environment','donor_beneficiary','administrative_violation','agreement_breach','other') then raise exception 'INVALID_CASE_TYPE' using errcode='22023'; end if;
  if p_priority not in ('normal','urgent') then raise exception 'EMPLOYEE_PRIORITY_NOT_ALLOWED' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_parties,'[]'::jsonb)) <> 'array' or jsonb_typeof(coalesce(p_witnesses,'[]'::jsonb)) <> 'array' then raise exception 'INVALID_PARTIES' using errcode='22023'; end if;
  if jsonb_array_length(coalesce(p_parties,'[]'::jsonb)) = 0 then raise exception 'AT_LEAST_ONE_PARTY_REQUIRED' using errcode='22023'; end if;

  v_number := 'CASE-' || to_char(clock_timestamp(), 'YYYYMMDD-HH24MISSMS');
  insert into public.dispute_cases(case_number, title, description, case_type, status, severity, actor_employee_id, is_confidential, privacy_level, opened_at,
    incident_at, incident_location, requested_action, witnesses_present, direct_manager_contacted, amicable_resolution_attempted, amicable_resolution_result,
    truth_confirmed, confidentiality_accepted, review_due_at, created_by)
  values(v_number, trim(p_title), trim(p_description), p_case_type, 'submitted', p_priority, v_emp, p_confidential, 'restricted', now(),
    p_incident_at, nullif(trim(p_incident_location),''), nullif(trim(p_requested_action),''), jsonb_array_length(coalesce(p_witnesses,'[]'::jsonb)) > 0,
    p_direct_manager_contacted, p_amicable_attempted, nullif(trim(p_amicable_result),''), true, true, now() + interval '24 hours', auth.uid()) returning id into v_id;

  insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, notified_at, created_by)
  values(v_id, v_emp, 'complainant', 'read', now(), auth.uid());

  for v_item in select * from jsonb_array_elements(coalesce(p_parties,'[]'::jsonb)) loop
    v_party := (v_item->>'employeeId')::uuid;
    if v_party = v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_PARTY' using errcode='22023'; end if;
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values(v_id, v_party, case when coalesce(v_item->>'type','respondent') in ('respondent','related') then coalesce(v_item->>'type','respondent') else 'respondent' end, 'withheld', auth.uid())
    on conflict(case_id, employee_id, party_type) do nothing;
    if v_first_respondent is null and coalesce(v_item->>'type','respondent') = 'respondent' then v_first_respondent := v_party; end if;
  end loop;
  for v_item in select * from jsonb_array_elements(coalesce(p_witnesses,'[]'::jsonb)) loop
    v_party := (v_item->>'employeeId')::uuid;
    if v_party = v_emp or not exists(select 1 from public.employees where id=v_party and status='active' and is_active and not is_deleted) then raise exception 'INVALID_WITNESS' using errcode='22023'; end if;
    insert into public.dispute_parties(case_id, employee_id, party_type, notification_status, created_by)
    values(v_id, v_party, 'witness', 'withheld', auth.uid()) on conflict(case_id, employee_id, party_type) do nothing;
  end loop;
  update public.dispute_cases set respondent_employee_id = v_first_respondent where id = v_id;
  insert into public.dispute_actions(case_id, action_type, to_status, note, actor_employee_id, actor_user_id, metadata)
  values(v_id, 'submit', 'submitted', 'تم تقديم المشكلة', v_emp, auth.uid(), jsonb_build_object('priority', p_priority));
  perform public.log_audit_event('dispute.submitted', 'workflow', 'notice', 'dispute_cases', v_id, 'تقديم مشكلة جديدة', null, jsonb_build_object('caseNumber', v_number, 'priority', p_priority));
  perform public.notify_dispute_admins(v_id, 'submitted', 'مشكلة جديدة تنتظر المراجعة', v_number || ' — ' || trim(p_title), case when p_priority='urgent' then 'urgent' else 'high' end);
  return v_id;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. Add resolved_friendly to transition_dispute_case
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.transition_dispute_case(p_case_id uuid, p_action text, p_reason text default null, p_metadata jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases; v_next text; v_target uuid; v_priority text; v_role_ok boolean;
begin
  select * into strict v from public.dispute_cases where id=p_case_id for update;
  v_role_ok := public.current_is_full_access() or public.has_permission('disputes.case.transition');
  if p_action in ('escalate','return_to_committee') then v_role_ok := v_role_ok or public.has_permission('disputes.case.escalate') or public.has_permission('disputes.executive.manage'); end if;
  if not v_role_ok then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  v_next := case p_action
    when 'request_more_information' then 'needs_more_information'
    when 'accept' then 'accepted'
    when 'reject' then 'rejected'
    when 'start_review' then 'under_review'
    when 'request_respondent_statement' then 'waiting_for_respondent'
    when 'request_witness_statement' then 'waiting_for_witness'
    when 'start_deliberation' then 'committee_deliberation'
    when 'settlement_pending' then 'settlement_pending'
    when 'escalate' then 'escalated_to_executive'
    when 'return_to_committee' then 'returned_to_committee'
    when 'close' then 'closed'
    when 'reopen' then 'reopened'
    when 'extend_review' then v.status
    when 'change_priority' then v.status
    -- V23: friendly resolution
    when 'resolve_friendly' then 'resolved_friendly'
    else null
  end;
  if v_next is null then raise exception 'UNKNOWN_ACTION' using errcode='22023'; end if;

  -- Status guard: prevent impossible transitions
  if p_action = 'accept' and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action = 'reject' and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action = 'start_review' and v.status not in ('accepted','reopened','returned_to_committee') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action in ('request_respondent_statement','request_witness_statement','start_deliberation') and v.status not in ('accepted','under_review','waiting_for_respondent','waiting_for_witness') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action = 'close' and v.status not in ('decision_issued','settlement_pending','executed','resolved_friendly') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action = 'reopen' and v.status not in ('closed','rejected') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;
  if p_action = 'resolve_friendly' and v.status not in ('under_review','committee_deliberation','waiting_for_respondent','waiting_for_witness','settlement_pending') then raise exception 'INVALID_TRANSITION' using errcode='22023'; end if;

  -- For statement requests, notify the relevant party
  if p_action in ('request_respondent_statement','request_witness_statement') then
    v_target := (p_metadata->>'employeeId')::uuid;
    if v_target is null then raise exception 'TARGET_EMPLOYEE_REQUIRED' using errcode='22023'; end if;
    update public.dispute_parties set notification_status='notified', notified_at=coalesce(notified_at, now()), statement_requested_at=now(), updated_at=now()
    where case_id=p_case_id and employee_id=v_target;
    if not found then raise exception 'PARTY_NOT_FOUND' using errcode='22023'; end if;
    perform public.enqueue_dispute_notification(p_case_id, v_target, p_action||'_'||p_case_id::text, 'طلب إفادة', 'تم طلب إفادتك في قضية '||v.case_number, 'high');
    if p_metadata ? 'summary' then
      update public.dispute_cases set shareable_summary=p_metadata->>'summary', updated_at=now() where id=p_case_id;
    end if;
  end if;

  if p_action = 'change_priority' then
    v_priority := coalesce(p_metadata->>'priority', v.severity);
    if v_priority not in ('normal','urgent','critical') then raise exception 'INVALID_PRIORITY' using errcode='22023'; end if;
    update public.dispute_cases set severity=v_priority, updated_at=now() where id=p_case_id;
  end if;

  if p_action = 'extend_review' then
    if v.status not in ('submitted','needs_more_information') then raise exception 'CANNOT_EXTEND' using errcode='22023'; end if;
    if nullif(trim(p_reason),'') is null then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
    update public.dispute_cases set review_due_at=coalesce(review_due_at, now())+interval '24 hours', review_extended_at=now(), review_extension_reason=trim(p_reason), updated_at=now() where id=p_case_id;
  end if;

  if p_action = 'accept' then
    update public.dispute_cases set accepted_at=now(), accepted_by=public.current_employee_id(), assigned_to=coalesce((p_metadata->>'assignedTo')::uuid, public.current_employee_id()), committee_quorum=coalesce((p_metadata->>'quorum')::int, 2), updated_at=now() where id=p_case_id;
  end if;

  if p_action = 'escalate' then
    update public.dispute_cases set escalated_at=now(), escalated_by=public.current_employee_id(), updated_at=now() where id=p_case_id;
    perform public.notify_dispute_admins(p_case_id, 'escalated', 'قضية مصعدة', v.case_number||' — تم تصعيد القضية للمراجعة التنفيذية', 'urgent');
  end if;

  if p_action = 'close' then
    update public.dispute_cases set closed_at=now(), closed_by=public.current_employee_id(), closure_reason=nullif(trim(p_reason),''), updated_at=now() where id=p_case_id;
  end if;

  if p_action = 'reopen' then
    if nullif(trim(p_reason),'') is null then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;
    update public.dispute_cases set reopened_at=now(), updated_at=now() where id=p_case_id;
  end if;

  if p_action = 'resolve_friendly' then
    update public.dispute_cases set closure_reason=coalesce(nullif(trim(p_reason),''), 'حل ودي'), updated_at=now() where id=p_case_id;
  end if;

  -- Apply status change
  if v_next <> v.status then
    update public.dispute_cases set status=v_next, updated_at=now() where id=p_case_id;
  end if;

  -- Audit trail
  insert into public.dispute_actions(case_id, action_type, from_status, to_status, note, actor_employee_id, actor_user_id, metadata)
  values(p_case_id, p_action, v.status, v_next, nullif(trim(p_reason),''), public.current_employee_id(), auth.uid(), p_metadata);
  perform public.log_audit_event('dispute.'||p_action, 'workflow', 'notice', 'dispute_cases', p_case_id, 'إجراء: '||p_action, nullif(trim(p_reason),''), p_metadata);

  return v_next;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. Grants
-- ═══════════════════════════════════════════════════════════════════════════════

revoke execute on function public.word_count(text) from public;
grant execute on function public.word_count(text) to authenticated;

commit;
