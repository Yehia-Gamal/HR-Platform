-- V17 §14: Expose admin-action fields in dispute catalog + executive inbox
-- Depends on: 0131 (admin action columns), 0059 (catalog RPC)

begin;

-- ---------------------------------------------------------------------------
-- 1. Enhanced get_dispute_operations_catalog — adds admin-action fields
--    and summary counters for the action_proposed / pending_execution phases.
-- ---------------------------------------------------------------------------

create or replace function public.get_dispute_operations_catalog(p_status text default null)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 if not(public.current_is_full_access() or public.has_permission('disputes.portal.access') or public.has_permission('disputes.case.read_all') or exists(select 1 from public.committee_members where employee_id=public.current_employee_id() and is_active)) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 return jsonb_build_object(
  'cases',coalesce((select jsonb_agg(jsonb_build_object(
   'id',c.id,'caseNumber',c.case_number,'title',c.title,'description',c.description,'caseType',c.case_type,'status',c.status,'priority',c.severity,
   'actorId',c.actor_employee_id,'actorName',a.full_name_ar,'actorDepartment',ad.name,
   'respondentId',c.respondent_employee_id,'respondentName',r.full_name_ar,
   'assignedTo',c.assigned_to,'assignedName',ass.full_name_ar,'openedAt',c.opened_at,'updatedAt',c.updated_at,
   'acceptedAt',c.accepted_at,'reviewDueAt',c.review_due_at,'decisionDueAt',c.decision_due_at,'overdue',(c.status in ('submitted','needs_more_information') and c.review_due_at<now()),
   'incidentAt',c.incident_at,'incidentLocation',c.incident_location,'requestedAction',c.requested_action,
   'directManagerContacted',c.direct_manager_contacted,'amicableAttempted',c.amicable_resolution_attempted,'amicableResult',c.amicable_resolution_result,
   'confidential',c.is_confidential,'privacyLevel',c.privacy_level,'quorum',c.committee_quorum,'closureReason',c.closure_reason,
   -- V17 admin-action fields (mig 0131 columns) ─────────────────────────────
   'proposedAdminAction',c.proposed_administrative_action,
   'proposedActionDetail',c.proposed_action_detail,
   'proposedAt',c.proposed_at,
   'proposedByName',pb.full_name_ar,
   'executiveDecision',c.executive_decision,
   'executiveDecisionReason',c.executive_decision_reason,
   'executiveDecisionAt',c.executive_decision_at,
   'executiveDecisionByName',edb.full_name_ar,
   'approvedAdminAction',c.approved_administrative_action,
   'approvedActionDetail',c.approved_action_detail,
   'executedAt',c.executed_at,
   'executedByName',exb.full_name_ar,
   'executionNotes',c.execution_notes,
   -- ────────────────────────────────────────────────────────────────────────
   'parties',coalesce((select jsonb_agg(jsonb_build_object('id',dp.id,'employeeId',dp.employee_id,'name',pe.full_name_ar,'type',dp.party_type,'notificationStatus',dp.notification_status,'notifiedAt',dp.notified_at,'statementSubmittedAt',dp.statement_submitted_at) order by dp.party_type,pe.full_name_ar) from public.dispute_parties dp join public.employees pe on pe.id=dp.employee_id where dp.case_id=c.id),'[]'::jsonb),
   'members',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'employeeId',m.employee_id,'name',me.full_name_ar,'role',m.role_in_committee,'active',m.is_active) order by m.role_in_committee) from public.committee_members m join public.employees me on me.id=m.employee_id where m.case_id=c.id),'[]'::jsonb),
   'statements',coalesce((select jsonb_agg(jsonb_build_object('id',st.id,'submittedBy',st.submitted_by,'submittedByName',se.full_name_ar,'type',st.statement_type,'text',st.statement_text,'visibility',st.visibility,'submittedAt',st.submitted_at) order by st.submitted_at desc) from public.dispute_statements st join public.employees se on se.id=st.submitted_by where st.case_id=c.id),'[]'::jsonb),
   'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',ev.id,'title',ev.title,'description',ev.description,'type',ev.evidence_type,'mimeType',ev.mime_type,'storagePath',ev.storage_path,'visibility',ev.visibility,'submittedAt',ev.submitted_at,'submittedByName',ee.full_name_ar) order by ev.submitted_at desc) from public.dispute_evidence ev left join public.employees ee on ee.id=ev.submitted_by where ev.case_id=c.id and ev.deleted_at is null),'[]'::jsonb),
   'sessions',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'type',s.session_type,'scheduledAt',s.scheduled_at,'endsAt',s.ends_at,'heldAt',s.held_at,'status',s.status,'location',s.location,'modality',s.modality,'minutes',s.minutes,'minutesData',s.minutes_data,'outcome',s.outcome,'recommendation',s.recommendation,'followUpAt',s.follow_up_at,
    'attendance',coalesce((select jsonb_agg(jsonb_build_object('committeeMemberId',sa.committee_member_id,'employeeId',cm.employee_id,'name',ae.full_name_ar,'status',sa.attendance_status)) from public.dispute_session_attendance sa join public.committee_members cm on cm.id=sa.committee_member_id join public.employees ae on ae.id=cm.employee_id where sa.session_id=s.id),'[]'::jsonb)) order by s.scheduled_at desc) from public.dispute_sessions s where s.case_id=c.id),'[]'::jsonb),
   'decision',(select jsonb_build_object('id',d.id,'number',d.decision_number,'text',d.decision_text,'rationale',d.rationale,'outcome',d.outcome_type,'status',d.status,'issuedAt',d.issued_at,'ownerId',d.implementation_owner_id,'ownerName',oe.full_name_ar,'dueAt',d.implementation_due_at,'implementedAt',d.implemented_at) from public.dispute_decisions d left join public.employees oe on oe.id=d.implementation_owner_id where d.case_id=c.id order by d.created_at desc limit 1),
   'actions',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'type',x.action_type,'note',x.note,'assignedTo',x.assigned_to,'assignedName',xe.full_name_ar,'dueAt',x.due_at,'status',x.execution_status,'proof',x.completion_proof,'completedAt',x.completed_at,'createdAt',x.created_at) order by x.created_at desc) from public.dispute_actions x left join public.employees xe on xe.id=x.assigned_to where x.case_id=c.id and x.execution_status is not null),'[]'::jsonb),
   'settlements',coalesce((select jsonb_agg(jsonb_build_object('id',z.id,'type',z.settlement_type,'fromName',zf.full_name_ar,'toName',zt.full_name_ar,'text',z.apology_text,'publicationPlace',z.publication_place,'dueAt',z.due_at,'status',z.status,'completedAt',z.completed_at) order by z.created_at desc) from public.dispute_settlements z left join public.employees zf on zf.id=z.apology_from left join public.employees zt on zt.id=z.apology_to where z.case_id=c.id),'[]'::jsonb),
   'appeals',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'decisionId',ap.decision_id,'appellantId',ap.appellant_employee_id,'appellantName',ape.full_name_ar,'reason',ap.reason,'status',ap.status,'submittedAt',ap.submitted_at,'resolution',ap.resolution) order by ap.submitted_at desc) from public.dispute_appeals ap join public.employees ape on ape.id=ap.appellant_employee_id where ap.case_id=c.id),'[]'::jsonb)
  ) order by case when c.status in ('submitted','needs_more_information') then 0 when c.status='action_proposed' then 1 when c.status='pending_execution' then 2 else 3 end,c.review_due_at,c.opened_at desc)
  from public.dispute_cases c
  left join public.employees a on a.id=c.actor_employee_id left join public.departments ad on ad.id=a.department_id
  left join public.employees r on r.id=c.respondent_employee_id left join public.employees ass on ass.id=c.assigned_to
  left join public.employees pb on pb.id=c.proposed_by
  left join public.employees edb on edb.id=c.executive_decision_by
  left join public.employees exb on exb.id=c.executed_by
  where (p_status is null or c.status=p_status) and public.can_access_dispute(c.id)),'[]'::jsonb),
  'summary',jsonb_build_object(
   'new',count(*) filter(where status='submitted'),
   'overdue',count(*) filter(where status in ('submitted','needs_more_information') and review_due_at<now()),
   'urgent',count(*) filter(where severity='urgent' and status not in ('closed','rejected','cancelled_by_employee')),
   'critical',count(*) filter(where severity='critical' and status not in ('closed','rejected','cancelled_by_employee')),
   'waitingStatements',count(*) filter(where status in ('waiting_for_respondent','waiting_for_witness')),
   'escalated',count(*) filter(where status='escalated_to_executive'),
   'pendingExecution',(select count(*) from public.dispute_actions where execution_status in ('pending','in_progress','failed')),
   'actionProposed',count(*) filter(where status='action_proposed'),
   'awaitingExecution',count(*) filter(where status='pending_execution'),
   'executed',count(*) filter(where status='executed'),
   'closed',count(*) filter(where status='closed'),
   'averageResolutionHours',coalesce(round(avg(extract(epoch from (closed_at-opened_at))/3600) filter(where closed_at is not null)::numeric,1),0)
  ),
  'pendingAppeals',(select count(*) from public.dispute_appeals where status in ('submitted','under_review')),
  'lastUpdatedAt',now()
 ) from public.dispute_cases where public.can_access_dispute(id);
end $$;

-- ---------------------------------------------------------------------------
-- 2. Executive dispute inbox — lightweight view for mobile executive
--    Returns only cases requiring executive decision (action_proposed) plus
--    recently decided ones for tracking.
-- ---------------------------------------------------------------------------

create or replace function public.get_executive_dispute_inbox()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not(public.current_is_full_access() or public.has_permission('disputes.admin_action.decide') or public.has_permission('disputes.executive.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  return jsonb_build_object(
    'awaitingDecision', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'caseNumber',c.case_number,'title',c.title,'description',c.description,
        'caseType',c.case_type,'status',c.status,'severity',c.severity,
        'actorName',a.full_name_ar,'respondentName',r.full_name_ar,
        'openedAt',c.opened_at,
        'proposedAdminAction',c.proposed_administrative_action,
        'proposedActionDetail',c.proposed_action_detail,
        'proposedAt',c.proposed_at,
        'proposedByName',pb.full_name_ar
      ) order by c.proposed_at asc)
      from public.dispute_cases c
      left join public.employees a on a.id=c.actor_employee_id
      left join public.employees r on r.id=c.respondent_employee_id
      left join public.employees pb on pb.id=c.proposed_by
      where c.status='action_proposed'
    ),'[]'::jsonb),
    'pendingExecution', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'caseNumber',c.case_number,'title',c.title,
        'status',c.status,'severity',c.severity,
        'actorName',a.full_name_ar,'respondentName',r.full_name_ar,
        'approvedAdminAction',c.approved_administrative_action,
        'approvedActionDetail',c.approved_action_detail,
        'executiveDecision',c.executive_decision,
        'executiveDecisionAt',c.executive_decision_at
      ) order by c.executive_decision_at desc)
      from public.dispute_cases c
      left join public.employees a on a.id=c.actor_employee_id
      left join public.employees r on r.id=c.respondent_employee_id
      where c.status='pending_execution'
    ),'[]'::jsonb),
    'recentlyExecuted', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'caseNumber',c.case_number,'title',c.title,
        'status',c.status,
        'approvedAdminAction',c.approved_administrative_action,
        'executedAt',c.executed_at,
        'executedByName',exb.full_name_ar,
        'executionNotes',c.execution_notes
      ) order by c.executed_at desc)
      from public.dispute_cases c
      left join public.employees exb on exb.id=c.executed_by
      where c.status='executed' and c.executed_at > now() - interval '30 days'
    ),'[]'::jsonb),
    'counts', jsonb_build_object(
      'awaitingDecision',(select count(*) from public.dispute_cases where status='action_proposed'),
      'pendingExecution',(select count(*) from public.dispute_cases where status='pending_execution'),
      'executedLast30Days',(select count(*) from public.dispute_cases where status='executed' and executed_at > now() - interval '30 days')
    )
  );
end $$;

revoke execute on function public.get_executive_dispute_inbox() from public;
grant execute on function public.get_executive_dispute_inbox() to authenticated;

-- Refresh grants on updated catalog
revoke execute on function public.get_dispute_operations_catalog(text) from public;
grant execute on function public.get_dispute_operations_catalog(text) to authenticated;

commit;
