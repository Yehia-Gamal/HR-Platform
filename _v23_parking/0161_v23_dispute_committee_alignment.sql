-- V23 §14: Dispute committee alignment
-- 1. Add 'resolved_friendly' status to dispute_cases
-- 2. Create submit_my_dispute_v23() — simplified 7-param mobile intake
-- 3. Add 'resolve_friendly' transition action
-- 4. Update 'close' to accept resolved_friendly cases
-- 5. Update committee portal summary to count resolved_friendly
-- Depends on: 0059, 0131, 0141, 0152

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Extend status check constraint with 'resolved_friendly'
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.dispute_cases drop constraint if exists dispute_cases_status_check;
alter table public.dispute_cases add constraint dispute_cases_status_check check(status in (
  'draft','submitted','needs_more_information','accepted','rejected','under_review',
  'waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed',
  'committee_deliberation','settlement_pending','escalated_to_executive',
  'returned_to_committee','decision_issued',
  'action_proposed','pending_execution','executed',
  -- V23: حل ودي
  'resolved_friendly',
  'closed','reopened','cancelled_by_employee'
));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. submit_my_dispute_v23() — simplified mobile intake (7 params)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.submit_my_dispute_v23(
  p_title text,
  p_description text,
  p_case_type text,
  p_parties jsonb default '[]'::jsonb,
  p_witnesses jsonb default '[]'::jsonb,
  p_truth_confirmed boolean default false,
  p_confidentiality_accepted boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
begin
  -- Delegate to the full submit_my_dispute with simplified defaults
  return public.submit_my_dispute(
    p_title            := p_title,
    p_description      := p_description,
    p_case_type        := p_case_type,
    p_priority         := 'normal',
    p_incident_at      := null,
    p_incident_location := null,
    p_parties          := p_parties,
    p_witnesses        := p_witnesses,
    p_direct_manager_contacted := null,
    p_amicable_attempted := null,
    p_amicable_result  := null,
    p_requested_action := null,
    p_confidential     := true,
    p_truth_confirmed  := p_truth_confirmed,
    p_confidentiality_accepted := p_confidentiality_accepted
  );
end $$;

revoke execute on function public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean) from public;
grant execute on function public.submit_my_dispute_v23(text,text,text,jsonb,jsonb,boolean,boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Update transition_dispute_case to support 'resolve_friendly' + update 'close'
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.transition_dispute_case(p_case_id uuid,p_action text,p_reason text default null,p_metadata jsonb default '{}'::jsonb)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.dispute_cases; v_next text; v_target uuid; v_priority text; v_role_ok boolean;
begin
 select * into strict v from public.dispute_cases where id=p_case_id for update;
 v_role_ok:=public.current_is_full_access() or public.has_permission('disputes.case.transition');
 if p_action in ('escalate','return_to_committee') then v_role_ok:=v_role_ok or public.has_permission('disputes.case.escalate') or public.has_permission('disputes.executive.manage'); end if;
 if not v_role_ok then raise exception 'FORBIDDEN' using errcode='42501'; end if;

 v_next:=case p_action
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
  -- V23: حل ودي
  when 'resolve_friendly' then 'resolved_friendly'
  when 'close' then 'closed'
  when 'reopen' then 'reopened'
  when 'force_status' then p_metadata->>'status'
  else null end;

 if p_action='extend_review' then
  if v.status not in ('submitted','needs_more_information') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'EXTENSION_NOT_ALLOWED' using errcode='22023'; end if;
  update public.dispute_cases set review_due_at=greatest(coalesce(review_due_at,now()),now())+interval '24 hours',review_extended_at=now(),review_extension_reason=trim(p_reason),updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id) values(p_case_id,'extend_review',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid());
  perform public.log_audit_event('dispute.review_extended','workflow','warning','dispute_cases',p_case_id,'تمديد مهلة مراجعة المشكلة',trim(p_reason));
  return v.status;
 end if;

 if p_action='change_priority' then
  v_priority=p_metadata->>'priority';
  if v_priority not in ('normal','urgent','critical') or length(trim(coalesce(p_reason,'')))<5 then raise exception 'INVALID_PRIORITY_CHANGE' using errcode='22023'; end if;
  update public.dispute_cases set severity=v_priority,updated_at=now() where id=p_case_id;
  insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata) values(p_case_id,'change_priority',v.status,v.status,trim(p_reason),public.current_employee_id(),auth.uid(),jsonb_build_object('from',v.severity,'to',v_priority));
  perform public.log_audit_event('dispute.priority_changed','workflow','warning','dispute_cases',p_case_id,'تغيير أولوية المشكلة',trim(p_reason),jsonb_build_object('from',v.severity,'to',v_priority));
  return v.status;
 end if;

 if v_next is null then raise exception 'UNKNOWN_ACTION' using errcode='22023'; end if;
 if p_action='request_more_information' and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('accept','reject') and v.status not in ('submitted','needs_more_information') then raise exception 'INVALID_STATE'; end if;
 if p_action='start_review' and v.status not in ('accepted','reopened','returned_to_committee') then raise exception 'INVALID_STATE'; end if;
 if p_action in ('request_respondent_statement','request_witness_statement') and v.status not in ('accepted','under_review','waiting_for_respondent','waiting_for_witness') then raise exception 'INVALID_STATE'; end if;
 -- V23: resolve_friendly مسموح من نفس الحالات التي يُسمح فيها بتسوية أو مداولة
 if p_action='resolve_friendly' and v.status not in ('under_review','waiting_for_respondent','waiting_for_witness','committee_deliberation') then raise exception 'INVALID_STATE'; end if;
 if p_action='close' then
  -- V23: السماح بالإغلاق من resolved_friendly + executed
  if v.status not in ('decision_issued','settlement_pending','executed','resolved_friendly') then raise exception 'CLOSE_NOT_ALLOWED'; end if;
  if exists(select 1 from public.dispute_actions where case_id=p_case_id and execution_status in ('pending','in_progress','failed')) or exists(select 1 from public.dispute_settlements where case_id=p_case_id and status='pending') then raise exception 'PENDING_IMPLEMENTATION'; end if;
 end if;
 if p_action='force_status' and (not public.current_is_full_access() or v_next not in ('submitted','needs_more_information','accepted','rejected','under_review','waiting_for_respondent','waiting_for_witness','session_scheduled','session_completed','committee_deliberation','settlement_pending','escalated_to_executive','returned_to_committee','decision_issued','resolved_friendly','closed','reopened','cancelled_by_employee')) then raise exception 'INVALID_FORCE_STATUS'; end if;
 if p_action in ('reject','request_more_information','escalate','return_to_committee','close','reopen','force_status','resolve_friendly') and length(trim(coalesce(p_reason,'')))<5 then raise exception 'REASON_REQUIRED' using errcode='22023'; end if;

 if p_action='accept' then
  update public.dispute_cases set accepted_at=coalesce(accepted_at,now()),accepted_by=public.current_employee_id(),decision_due_at=coalesce(decision_due_at,now()+interval '7 days') where id=p_case_id;
 elsif p_action in ('request_respondent_statement','request_witness_statement') then
  v_target=(p_metadata->>'employeeId')::uuid;
  update public.dispute_parties set notification_status='notified',notified_at=coalesce(notified_at,now()),statement_requested_at=now(),updated_at=now()
  where case_id=p_case_id and employee_id=v_target and party_type=case when p_action='request_witness_statement' then 'witness' else 'respondent' end;
 elsif p_action='resolve_friendly' then
  -- V23: حل ودي — حفظ تاريخ الحل وسبب الحل
  update public.dispute_cases set resolved_at=now(),resolution_summary=trim(p_reason),updated_at=now() where id=p_case_id;
 end if;

 update public.dispute_cases set status=v_next,updated_at=now() where id=p_case_id;
 insert into public.dispute_actions(case_id,action_type,from_status,to_status,note,actor_employee_id,actor_user_id,metadata)
 values(p_case_id,p_action,v.status,v_next,trim(p_reason),public.current_employee_id(),auth.uid(),p_metadata);
 perform public.log_audit_event('dispute.'||p_action,'workflow',case when p_action in ('escalate','force_status') then 'warning' else 'notice' end,'dispute_cases',p_case_id,'تغيير مسار المشكلة',p_reason,jsonb_build_object('from',v.status,'to',v_next));
 return v_next;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Update committee portal summary to count resolved_friendly
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_committee_dispute_portal()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_emp uuid := public.current_employee_id();
begin
  if not(
    public.current_is_full_access()
    or public.has_permission('disputes.portal.access')
    or public.has_permission('disputes.case.read_all')
    or exists(select 1 from public.committee_members where employee_id = v_emp and is_active)
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'cases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'caseNumber', c.case_number,
        'title', c.title,
        'description', c.description,
        'caseType', c.case_type,
        'status', c.status,
        'severity', c.severity,
        'actorName', a.full_name_ar,
        'actorDepartment', ad.name,
        'respondentName', r.full_name_ar,
        'assignedName', ass.full_name_ar,
        'openedAt', c.opened_at,
        'updatedAt', c.updated_at,
        'overdue', (c.status in ('submitted','needs_more_information') and c.review_due_at < now()),
        'proposedAdminAction', c.proposed_administrative_action,
        'proposedActionDetail', c.proposed_action_detail,
        'proposedAt', c.proposed_at,
        'proposedByName', pb.full_name_ar,
        'executiveDecision', c.executive_decision,
        'executiveDecisionReason', c.executive_decision_reason,
        'executiveDecisionAt', c.executive_decision_at,
        'approvedAdminAction', c.approved_administrative_action,
        'approvedActionDetail', c.approved_action_detail,
        'executedAt', c.executed_at,
        'executedByName', exb.full_name_ar,
        'executionNotes', c.execution_notes,
        'partyCount', (select count(*) from public.dispute_parties dp where dp.case_id = c.id),
        'sessionCount', (select count(*) from public.dispute_sessions s where s.case_id = c.id),
        'hasDecision', exists(select 1 from public.dispute_decisions d where d.case_id = c.id)
      ) order by
        case
          when c.status in ('submitted','needs_more_information') then 0
          when c.status = 'action_proposed' then 1
          when c.status = 'pending_execution' then 2
          when c.status in ('under_review','waiting_for_respondent','waiting_for_witness','hearing_scheduled') then 3
          else 4
        end,
        c.review_due_at nulls last,
        c.opened_at desc
      )
      from public.dispute_cases c
      left join public.employees a   on a.id  = c.actor_employee_id
      left join public.departments ad on ad.id = a.department_id
      left join public.employees r   on r.id  = c.respondent_employee_id
      left join public.employees ass on ass.id = c.assigned_to
      left join public.employees pb  on pb.id  = c.proposed_by
      left join public.employees exb on exb.id = c.executed_by
      where public.can_access_dispute(c.id)
    ), '[]'::jsonb),
    'summary', (
      select jsonb_build_object(
        'total', count(*),
        'new', count(*) filter (where status = 'submitted'),
        'underReview', count(*) filter (where status in ('under_review','waiting_for_respondent','waiting_for_witness','hearing_scheduled')),
        'actionProposed', count(*) filter (where status = 'action_proposed'),
        'pendingExecution', count(*) filter (where status = 'pending_execution'),
        'executed', count(*) filter (where status = 'executed'),
        'resolvedFriendly', count(*) filter (where status = 'resolved_friendly'),
        'closed', count(*) filter (where status = 'closed'),
        'overdue', count(*) filter (where status in ('submitted','needs_more_information') and review_due_at < now()),
        'urgent', count(*) filter (where severity in ('urgent','critical') and status not in ('closed','rejected','cancelled_by_employee'))
      )
      from public.dispute_cases
      where public.can_access_dispute(id)
    ),
    'lastUpdatedAt', now()
  );
end $$;

commit;
