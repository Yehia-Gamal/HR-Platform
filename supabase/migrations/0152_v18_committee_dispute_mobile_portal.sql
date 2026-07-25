-- V18: Committee dispute mobile portal
-- Lightweight RPC for committee members / ops managers / executive to see
-- ALL disputes from the mobile app.  get_dispute_operations_catalog() is too
-- heavy (parties, sessions, evidence…); this returns only what a card list needs.
-- Access check mirrors get_dispute_operations_catalog().
-- Depends on: 0059 (disputes), 0131 (admin-action cols), 0141 (catalog update)

begin;

create or replace function public.get_committee_dispute_portal()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_emp uuid := public.current_employee_id();
begin
  -- Same access gate as get_dispute_operations_catalog
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

revoke execute on function public.get_committee_dispute_portal() from public;
grant execute on function public.get_committee_dispute_portal() to authenticated;

commit;
