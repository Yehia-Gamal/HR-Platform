-- V17 §10: KPI flow reversal — eliminate manager_final from active flow.
-- Previous flow (0109): self → manager_review → hr_review → manager_final → finalized
-- New V17 flow:         self → hr_review → manager_review → finalized
--
-- manager_review is now the finalization step: manager scores, validates, and approves.
-- manager_final is kept in CHECK constraints for historical/backward-compat data only.
-- HR reviews FIRST (attendance 20pt, prayer 5pt, halaqa 5pt), then the direct manager
-- scores targets (40pt), competency (20pt), behavior (5pt), initiatives (5pt) and finalizes.
-- Manager CANNOT modify HR scores. Executive Director is EXCLUDED from KPI entirely.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Add SUBMITTED_TO_HR workflow status
-- ─────────────────────────────────────────────────────────────────────────────
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_workflow_status_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_workflow_status_check check(workflow_status in (
  'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_HR','SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW',
  'HR_REVIEW','RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL','MANAGER_APPROVED',
  'INCLUDED_IN_MONTHLY_REPORT','CYCLE_CLOSED','ARCHIVED','RETURNED_FOR_REVISION','OVERDUE',
  'NOT_STARTED','EMPLOYEE_INPUT_IN_PROGRESS','HR_DATA_PENDING','SESSION_SCHEDULED',
  'SESSION_COMPLETED','MANAGER_EVALUATION_IN_PROGRESS','HR_EVALUATION_IN_PROGRESS',
  'EMPLOYEE_ACKNOWLEDGEMENT_PENDING','EMPLOYEE_ACKNOWLEDGED','FINAL_REVIEW',
  'SENT_TO_EXECUTIVE_DIRECTOR','APPROVED','CLOSED'
));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Stage history trigger — V17 stage order (no manager_final in active path)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.tg_kpi_stage_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order text[]:=array['self','hr_review','manager_review','manager_final','finalized','closed','archived'];
begin
 if new.current_stage is distinct from old.current_stage then
  insert into public.kpi_stage_history(evaluation_id,from_stage,to_stage,action,actor_employee_id,actor_user_id)
  values(new.id,old.current_stage,new.current_stage,
   case when coalesce(array_position(v_order,new.current_stage),0)>coalesce(array_position(v_order,old.current_stage),0) then 'advance' else 'return' end,
   public.current_employee_id(),auth.uid());
 end if;
 return new;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Core routing — advance_kpi_stage with V17 flow (no manager_final)
--    self → hr_review → manager_review → finalized
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid,p_action text,p_scores jsonb default null,p_note text default null
)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_expected text; v_next text; v_workflow text;
 v_row jsonb; v_score numeric; v_criterion public.kpi_criteria; v_errors text[]; v_total numeric; v_rating text;
 v_required_count integer; v_received_count integer;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 -- V17 §10 routing: self → hr_review → manager_review → manager_final → finalized
 case p_action
  when 'self' then v_expected:='self';v_next:='hr_review';v_workflow:='SUBMITTED_TO_HR';
  when 'hr' then v_expected:='hr_review';v_next:='manager_review';v_workflow:='SUBMITTED_TO_DIRECT_MANAGER';
  when 'hr_review' then v_expected:='hr_review';v_next:='manager_review';v_workflow:='SUBMITTED_TO_DIRECT_MANAGER';
  when 'manager' then v_expected:='manager_review';v_next:='manager_final';v_workflow:='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL';
  when 'manager_review' then v_expected:='manager_review';v_next:='manager_final';v_workflow:='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL';
  when 'manager_final' then v_expected:='manager_final';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
  when 'finalize' then v_expected:='manager_final';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
  else raise exception 'INVALID_KPI_ACTION';
 end case;
 if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

 if v_expected='self' then
  if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id() or not public.has_permission('performance.kpi.self_assess') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  -- Verify a direct manager is assigned (needed for later stages)
  if not public.kpi_is_direct_manager(v_eval.employee_id) and not exists(
    select 1 from public.manager_relations mr where mr.employee_id=v_eval.employee_id and mr.relation_type='primary'
      and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date)
  ) then raise exception 'DIRECT_MANAGER_NOT_ASSIGNED'; end if;
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id;
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
  select count(*) into v_received_count from jsonb_array_elements(p_scores);
  if v_received_count<>v_required_count then raise exception 'ALL_SELF_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id;
   if v_criterion.id is null then raise exception 'INVALID_SELF_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'self',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;

 -- V17: HR reviews FIRST (compliance + attendance)
 elsif v_expected='hr_review' then
  if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
  if not exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id)
     or exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id and has_pending_items) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
  if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;

 -- V17: Manager reviews SECOND — scores + pre-validates (final approval at manager_final)
 elsif v_expected='manager_review' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
  -- Save manager comment BEFORE validation (get_kpi_validation_errors checks it on the row)
  update public.kpi_evaluations set manager_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
  -- Save manager scores
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id and evaluator_stage='manager';
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'MANAGER_SCORES_REQUIRED'; end if;
  select count(*) into v_received_count from jsonb_array_elements(p_scores);
  if v_received_count<>v_required_count then raise exception 'ALL_MANAGER_CRITERIA_REQUIRED'; end if;
  for v_row in select * from jsonb_array_elements(p_scores) loop
   select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='manager';
   if v_criterion.id is null then raise exception 'INVALID_MANAGER_CRITERION'; end if;
   v_score:=(v_row->>'score')::numeric;
   if v_score<0 or v_score>v_criterion.max_score then raise exception 'SCORE_OUT_OF_RANGE'; end if;
   insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
   values(v_eval.id,v_criterion.id,v_score,'manager',nullif(trim(v_row->>'note'),''),auth.uid())
   on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
  end loop;
  -- V17: finalization validation runs HERE (was at manager_final in old flow)
  v_errors:=public.get_kpi_validation_errors(v_eval.id);
  if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
  v_total:=public.kpi_total_score(v_eval.id);
  if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
  v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);

 -- Backward compat: manager_final (historical data only — normal V17 flow never reaches here)
 elsif v_expected='manager_final' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  v_errors:=public.get_kpi_validation_errors(v_eval.id);
  if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
  v_total:=public.kpi_total_score(v_eval.id);
  if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
  v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
 end if;

 update public.kpi_evaluations set
  stage=v_next,current_stage=v_next,workflow_status=v_workflow,
  manager_comment=case when v_expected in ('manager_review','manager_final') and nullif(trim(p_note),'') is not null then trim(p_note) else manager_comment end,
  manager_approved_at=case when v_expected in ('manager_review','manager_final') then now() else manager_approved_at end,
  manager_approved_by=case when v_expected in ('manager_review','manager_final') then public.current_employee_id() else manager_approved_by end,
  hr_comment=case when v_expected='hr_review' then nullif(trim(p_note),'') else hr_comment end,
  hr_approved_at=case when v_expected='hr_review' then now() else hr_approved_at end,
  hr_approved_by=case when v_expected='hr_review' then public.current_employee_id() else hr_approved_by end,
  final_score=case when v_next='finalized' then v_total else final_score end,
  final_rating=case when v_next='finalized' then v_rating else final_rating end,
  final_breakdown=case when v_next='finalized' then (select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id)) from public.kpi_criteria c where c.template_id=v_eval.template_id) else final_breakdown end,
  rating_policy_snapshot=case when v_next='finalized' then (select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id) else rating_policy_snapshot end,
  locked=(v_next='finalized'),updated_at=now()
 where id=v_eval.id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,'انتقال مرحلة تقييم الأداء',null,jsonb_build_object('action',p_action,'from',v_expected,'to',v_next,'workflowStatus',v_workflow,'note',p_note,'finalScore',v_total));
 if v_next='finalized' then
  perform public.log_audit_event('kpi.manager.approved','workflow','notice','kpi_evaluations',v_eval.id,'اعتماد المدير المباشر للنتيجة النهائية',p_note,jsonb_build_object('finalScore',v_total));
  perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
 end if;
 return v_eval;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Return stage — V17 return paths
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_from text;
begin
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'RETURN_REASON_REQUIRED'; end if;
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_from:=v_eval.current_stage;
 if v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;

 -- V17 return paths (hr_review comes before manager_review):
 -- hr_review → self (HR sends back to employee)
 if v_from='hr_review' and p_target_stage='self' then
  if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN'; end if;
 -- manager_review → hr_review or self (manager sends back)
 elsif v_from='manager_review' and p_target_stage in ('hr_review','self') then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
 -- Backward compat: manager_final → manager_review, hr_review, or self
 elsif v_from='manager_final' and p_target_stage in ('manager_review','hr_review','self') then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
 -- Executive secretary can return to any active stage
 elsif public.current_is_executive_secretary() and p_target_stage in ('self','hr_review','manager_review') then
  null;
 else raise exception 'INVALID_RETURN_TARGET'; end if;

 update public.kpi_evaluations set stage=p_target_stage,current_stage=p_target_stage,workflow_status='RETURNED_FOR_REVISION',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now()
 where id=p_evaluation_id returning * into v_eval;
 perform public.log_audit_event('kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,'إعادة التقييم للتصحيح',trim(p_note),jsonb_build_object('from',v_from,'to',p_target_stage));
 return v_eval;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Evaluation form — V17 editability (no manager_final in active flow)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles; v_editable text; v_locked boolean; v_criteria jsonb;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);
 if not v_locked then
  if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_editable:='self';
  -- V17: HR reviews before manager
  elsif v_eval.current_stage='hr_review' and public.current_is_hr_reviewer() then v_editable:='hr_review';
  elsif v_eval.current_stage='manager_review' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_review';
  -- Backward compat: if stuck at manager_final, still editable by manager
  elsif v_eval.current_stage='manager_final' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_final';
  end if;
 end if;

 -- V17: HR auto-status transition when HR opens the form
 if v_editable='hr_review' and v_eval.workflow_status='SUBMITTED_TO_HR' then
  update public.kpi_evaluations set workflow_status='HR_REVIEW',updated_at=now() where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.hr.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء HR مراجعة التقييم',null,null);
 end if;

 -- Manager auto-status transition
 if v_editable='manager_review' and v_eval.workflow_status='SUBMITTED_TO_DIRECT_MANAGER' then
  update public.kpi_evaluations set workflow_status='MANAGER_REVIEW',updated_at=now() where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.manager.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء المدير المباشر مراجعة التقييم',null,null);
 end if;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',case when v_editable='self' then true when v_editable='hr_review' then c.evaluator_stage='hr' when v_editable in ('manager_review','manager_final') then c.evaluator_stage='manager' else false end,
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}')
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;

 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'cycle',jsonb_build_object('id',v_cycle.id,'status',v_cycle.status,'scheduledOpenAt',v_cycle.scheduled_open_at,'deadlineAt',v_cycle.deadline_at,'extendedUntil',v_cycle.extended_until,'effectiveDeadline',public.kpi_effective_deadline(v_cycle)),
  'goals',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'title',g.title,'description',g.description,'targetValue',g.target_value,'achievedValue',g.achieved_value,'unit',g.unit,'weight',g.weight,'dueDate',g.due_date,'evidenceSource',g.evidence_source,'employeeNote',g.employee_note,'managerNote',g.manager_note,'status',g.status,'calculatedScore',g.calculated_score) order by g.created_at) from public.kpi_goals g where g.evaluation_id=v_eval.id),'[]'::jsonb),
  'session',(select jsonb_build_object('id',s.id,'scheduledAt',s.scheduled_at,'heldAt',s.held_at,'mode',s.mode,'discussionSummary',s.discussion_summary,'strengths',s.strengths,'improvementPoints',s.improvement_points,'nextMonthGoals',s.next_month_goals,'employeeNotes',s.employee_notes,'managerNotes',s.manager_notes,'employeeAttended',s.employee_attended,'managerAttended',s.manager_attended,'employeeConfirmedAt',s.employee_confirmed_at) from public.kpi_review_sessions s where s.evaluation_id=v_eval.id),
  'compliance',coalesce((select jsonb_agg(jsonb_build_object('metric',r.metric,'requiredCount',r.required_count,'actualCount',r.actual_count,'exemptCount',r.exempt_count,'cancelledCount',r.cancelled_count,'score',r.calculated_score,'note',r.note)) from public.kpi_compliance_records r where r.evaluation_id=v_eval.id),'[]'::jsonb),
  'attendance',(select jsonb_build_object('periodStart',a.period_start,'periodEnd',a.period_end,'lateCount',a.late_count,'earlyLeaveCount',a.early_leave_count,'unexcusedAbsenceCount',a.unexcused_absence_count,'shortagePenalty',a.shortage_penalty,'missingPunchCount',a.missing_punch_count,'score',a.score,'hasPendingItems',a.has_pending_items,'calculatedAt',a.calculated_at) from public.kpi_attendance_snapshots a where a.evaluation_id=v_eval.id),
  'evidence',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'criterionId',x.criterion_id,'type',x.evidence_type,'title',x.title,'description',x.description,'storagePath',x.storage_path,'externalUrl',x.external_url,'submittedStage',x.submitted_stage,'createdAt',x.created_at) order by x.created_at) from public.kpi_evidence x where x.evaluation_id=v_eval.id),'[]'::jsonb),
  'validationErrors',to_jsonb(public.get_kpi_validation_errors(v_eval.id)),
  'lastUpdatedAt',coalesce(v_eval.updated_at,v_eval.created_at)
 );
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Override & appeal — route to manager_review (not manager_final)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.override_kpi_score(p_evaluation_id uuid,p_criterion_id uuid,p_score numeric,p_reason text)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_max numeric; v_old numeric;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if length(trim(coalesce(p_reason,'')))<8 then raise exception 'OVERRIDE_REASON_REQUIRED'; end if;
 select c.max_score into strict v_max from public.kpi_evaluations e join public.kpi_criteria c on c.template_id=e.template_id where e.id=p_evaluation_id and c.id=p_criterion_id;
 if p_score<0 or p_score>v_max then raise exception 'SCORE_OUT_OF_RANGE'; end if;
 select public.kpi_effective_score(p_evaluation_id,p_criterion_id) into v_old;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,p_criterion_id,p_score,'secretary',trim(p_reason),auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 -- V17: route back to manager_review (the finalization step), not manager_final
 update public.kpi_evaluations set final_score=null,final_rating=null,final_breakdown=null,locked=false,
  stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',updated_at=now()
 where id=p_evaluation_id;
 perform public.log_audit_event('kpi.score.overridden','workflow','warning','kpi_evaluations',p_evaluation_id,'تعديل استثنائي موثق لدرجة KPI',trim(p_reason),jsonb_build_object('criterionId',p_criterion_id,'oldScore',v_old,'newScore',p_score));
 return p_score;
end $$;

create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then
  -- V17: route to manager_review (the finalization step), not manager_final
  update public.kpi_evaluations set stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now() where id=v.evaluation_id;
 end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض KPI',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Migrate in-flight evaluations to V17 flow
-- ─────────────────────────────────────────────────────────────────────────────
-- Evals at manager_review in old flow → move to hr_review (in V17, HR reviews first).
-- Manager scores in kpi_scores are preserved; they'll be used when the evaluation
-- reaches manager_review again in the new flow.
update public.kpi_evaluations set
  stage='hr_review',current_stage='hr_review',
  workflow_status='SUBMITTED_TO_HR',
  updated_at=now()
where current_stage='manager_review';

-- Evals at manager_final → move to manager_review (which is now the finalization step).
-- Both HR and manager have already scored, so the manager just needs to re-approve.
update public.kpi_evaluations set
  stage='manager_review',current_stage='manager_review',
  workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',
  updated_at=now()
where current_stage='manager_final';

-- Evals at hr_review stay there — HR will advance to manager_review in new flow.
-- Evals at self, finalized, closed, archived — no change needed.

commit;
