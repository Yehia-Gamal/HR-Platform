-- V23 §06: KPI Parallel Workflow — HR + Manager review simultaneously.
-- Feature flag: kpi_cycles.use_parallel_flow (default false → V17 sequential).
-- V23 flow: self → parallel_review → secretary_review → executive_review → finalized → closed → archived
-- V17 flow: self → hr_review → manager_review → (manager_final) → finalized → closed → archived
-- Barrier: hr_completed + manager_completed on kpi_evaluations; auto-advance when both true.
-- Optimistic concurrency: version integer on kpi_evaluations.
begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Schema changes
-- ─────────────────────────────────────────────────────────────────────────────

-- Feature flag on cycles
alter table public.kpi_cycles
  add column if not exists use_parallel_flow boolean not null default false;

-- Barrier + concurrency on evaluations
alter table public.kpi_evaluations
  add column if not exists hr_completed boolean not null default false,
  add column if not exists manager_completed boolean not null default false,
  add column if not exists version integer not null default 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Expand CHECK constraints for V23 stages
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_stage_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_stage_check check(stage in (
  'self','manager_review','hr_review','manager_final','finalized','closed','archived',
  'manager','hr','acknowledgement','secretary','executive',
  'parallel_review','secretary_review','executive_review'
));

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_current_stage_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_current_stage_check check(current_stage in (
  'self','manager_review','hr_review','manager_final','finalized','closed','archived',
  'manager','hr','acknowledgement','secretary','executive',
  'parallel_review','secretary_review','executive_review'
));

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_workflow_status_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_workflow_status_check check(workflow_status in (
  'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_HR','SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW',
  'HR_REVIEW','RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL','MANAGER_APPROVED',
  'INCLUDED_IN_MONTHLY_REPORT','CYCLE_CLOSED','ARCHIVED','RETURNED_FOR_REVISION','OVERDUE',
  'NOT_STARTED','EMPLOYEE_INPUT_IN_PROGRESS','HR_DATA_PENDING','SESSION_SCHEDULED',
  'SESSION_COMPLETED','MANAGER_EVALUATION_IN_PROGRESS','HR_EVALUATION_IN_PROGRESS',
  'EMPLOYEE_ACKNOWLEDGEMENT_PENDING','EMPLOYEE_ACKNOWLEDGED','FINAL_REVIEW',
  'SENT_TO_EXECUTIVE_DIRECTOR','APPROVED','CLOSED',
  'PARALLEL_REVIEW_IN_PROGRESS','HR_COMPLETED','MANAGER_COMPLETED',
  'SECRETARY_REVIEW','EXECUTIVE_REVIEW','EXECUTIVE_ACKNOWLEDGED','RETURNED_BY_EXECUTIVE'
));

-- Allow evidence during parallel_review
alter table public.kpi_evidence drop constraint if exists kpi_evidence_submitted_stage_check;
alter table public.kpi_evidence add constraint kpi_evidence_submitted_stage_check check(submitted_stage in (
  'self','manager_review','hr_review','manager_final','manager','hr','secretary','executive',
  'parallel_review','secretary_review','executive_review'
));

-- Barrier consistency: hr_completed/manager_completed only true when in or past parallel_review
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_barrier_check;
alter table public.kpi_evaluations add constraint kpi_evaluations_barrier_check check(
  (not hr_completed and not manager_completed)
  or current_stage in ('parallel_review','secretary_review','executive_review','finalized','closed','archived')
);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Stage history trigger — V23-aware ordering
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.tg_kpi_stage_history()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_order text[]:=array[
  'self','hr_review','manager_review','parallel_review',
  'manager_final','secretary_review','executive_review',
  'finalized','closed','archived'
];
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
-- 4. Core routing — advance_kpi_stage with dual-path (V17/V23)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid,p_action text,p_scores jsonb default null,p_note text default null
)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_expected text; v_next text; v_workflow text;
 v_row jsonb; v_score numeric; v_criterion public.kpi_criteria; v_errors text[]; v_total numeric; v_rating text;
 v_required_count integer; v_received_count integer;
 v_parallel boolean; v_both_done boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id for update;
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if length(coalesce(p_note,''))>5000 then raise exception 'NOTE_TOO_LONG'; end if;

 v_parallel:=coalesce(v_cycle.use_parallel_flow,false);

 -- ═══════════════════════════════════════════════════════════════════════════
 -- V23 PARALLEL PATH
 -- ═══════════════════════════════════════════════════════════════════════════
 if v_parallel then
  case p_action
   when 'self' then v_expected:='self';v_next:='parallel_review';v_workflow:='PARALLEL_REVIEW_IN_PROGRESS';
   when 'hr_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null; -- barrier decides
   when 'manager_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null; -- barrier decides
   when 'parallel_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null; -- generic fallback
   when 'secretary_review' then v_expected:='secretary_review';v_next:='executive_review';v_workflow:='EXECUTIVE_REVIEW';
   when 'executive_review' then v_expected:='executive_review';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
   else raise exception 'INVALID_KPI_ACTION';
  end case;
  if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

  -- Self assessment (same as V17)
  if p_action='self' then
   if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id() or not public.has_permission('performance.kpi.self_assess') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
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
   -- Advance to parallel_review, reset barrier
   update public.kpi_evaluations set
    stage=v_next,current_stage=v_next,workflow_status=v_workflow,
    hr_completed=false,manager_completed=false,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;

  -- HR submits during parallel_review
  elsif p_action='hr_review' and v_expected='parallel_review' then
   if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   if v_eval.hr_completed then raise exception 'HR_ALREADY_COMPLETED'; end if;
   perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
   if not exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id)
      or exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id and has_pending_items) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
   if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;
   -- Mark HR done
   update public.kpi_evaluations set
    hr_completed=true,
    hr_comment=nullif(trim(p_note),''),
    hr_approved_at=now(),hr_approved_by=public.current_employee_id(),
    workflow_status=case when manager_completed then 'SECRETARY_REVIEW' else 'HR_COMPLETED' end,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;
   -- Check barrier
   v_both_done:=v_eval.hr_completed and v_eval.manager_completed;
   if v_both_done then
    -- Both done — advance to secretary_review
    v_errors:=public.get_kpi_validation_errors(v_eval.id);
    if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
    update public.kpi_evaluations set
     stage='secretary_review',current_stage='secretary_review',
     workflow_status='SECRETARY_REVIEW',
     version=version+1,updated_at=now()
    where id=v_eval.id returning * into v_eval;
   end if;

  -- Manager submits during parallel_review
  elsif p_action in ('manager_review','parallel_review') and v_expected='parallel_review' then
   if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   if v_eval.manager_completed then raise exception 'MANAGER_ALREADY_COMPLETED'; end if;
   if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
   -- Save manager comment
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
   -- Mark manager done
   update public.kpi_evaluations set
    manager_completed=true,
    manager_approved_at=now(),manager_approved_by=public.current_employee_id(),
    workflow_status=case when hr_completed then 'SECRETARY_REVIEW' else 'MANAGER_COMPLETED' end,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;
   -- Check barrier
   v_both_done:=v_eval.hr_completed and v_eval.manager_completed;
   if v_both_done then
    v_errors:=public.get_kpi_validation_errors(v_eval.id);
    if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
    update public.kpi_evaluations set
     stage='secretary_review',current_stage='secretary_review',
     workflow_status='SECRETARY_REVIEW',
     version=version+1,updated_at=now()
    where id=v_eval.id returning * into v_eval;
   end if;

  -- Secretary review → executive_review
  elsif p_action='secretary_review' then
   if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   update public.kpi_evaluations set
    stage=v_next,current_stage=v_next,workflow_status=v_workflow,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;

  -- Executive review → finalized
  elsif p_action='executive_review' then
   if not public.current_has_active_role(array['executive','executive-director']) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   v_errors:=public.get_kpi_validation_errors(v_eval.id);
   if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
   v_total:=public.kpi_total_score(v_eval.id);
   if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
   v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
   update public.kpi_evaluations set
    stage='finalized',current_stage='finalized',workflow_status='INCLUDED_IN_MONTHLY_REPORT',
    final_score=v_total,final_rating=v_rating,
    final_breakdown=(select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id)) from public.kpi_criteria c where c.template_id=v_eval.template_id),
    rating_policy_snapshot=(select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id),
    locked=true,version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;
  end if;

  perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
   'انتقال مرحلة تقييم الأداء (V23)',null,
   jsonb_build_object('action',p_action,'from',v_expected,'to',v_eval.current_stage,
    'workflowStatus',v_eval.workflow_status,'note',p_note,'finalScore',v_eval.final_score,
    'hrCompleted',v_eval.hr_completed,'managerCompleted',v_eval.manager_completed));
  if v_eval.current_stage='finalized' then
   perform public.log_audit_event('kpi.executive.approved','workflow','notice','kpi_evaluations',v_eval.id,
    'اعتماد المدير التنفيذي للنتيجة النهائية (V23)',p_note,jsonb_build_object('finalScore',v_eval.final_score));
   perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,
    'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
  end if;
  return v_eval;

 -- ═══════════════════════════════════════════════════════════════════════════
 -- V17 SEQUENTIAL PATH (unchanged logic)
 -- ═══════════════════════════════════════════════════════════════════════════
 else
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
  elsif v_expected='hr_review' then
   if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
   if not exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id)
      or exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id and has_pending_items) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
   if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;
  elsif v_expected='manager_review' then
   if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
   update public.kpi_evaluations set manager_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
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
   v_errors:=public.get_kpi_validation_errors(v_eval.id);
   if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
   v_total:=public.kpi_total_score(v_eval.id);
   if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
   v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
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
   locked=(v_next='finalized'),version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;
  perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,'انتقال مرحلة تقييم الأداء',null,jsonb_build_object('action',p_action,'from',v_expected,'to',v_next,'workflowStatus',v_workflow,'note',p_note,'finalScore',v_total));
  if v_next='finalized' then
   perform public.log_audit_event('kpi.manager.approved','workflow','notice','kpi_evaluations',v_eval.id,'اعتماد المدير المباشر للنتيجة النهائية',p_note,jsonb_build_object('finalScore',v_total));
   perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
  end if;
  return v_eval;
 end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Return stage — V23 return paths
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_from text; v_parallel boolean;
begin
 if length(trim(coalesce(p_note,'')))<5 then raise exception 'RETURN_REASON_REQUIRED'; end if;
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_from:=v_eval.current_stage;
 if v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;

 v_parallel:=coalesce(v_cycle.use_parallel_flow,false);

 if v_parallel then
  -- V23 return paths:
  -- parallel_review → self (HR or Manager sends back)
  if v_from='parallel_review' and p_target_stage='self' then
   if not (public.current_is_hr_reviewer() or public.kpi_is_direct_manager(v_eval.employee_id)) then raise exception 'FORBIDDEN'; end if;
  -- secretary_review → parallel_review (secretary sends back for re-review)
  elsif v_from='secretary_review' and p_target_stage='parallel_review' then
   if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN'; end if;
  -- executive_review → secretary_review (executive sends back to secretary)
  elsif v_from='executive_review' and p_target_stage='secretary_review' then
   if not public.current_has_active_role(array['executive','executive-director']) then raise exception 'FORBIDDEN'; end if;
  -- Executive secretary can return to any active stage
  elsif public.current_is_executive_secretary() and p_target_stage in ('self','parallel_review','secretary_review') then
   null;
  else raise exception 'INVALID_RETURN_TARGET'; end if;

  update public.kpi_evaluations set
   stage=p_target_stage,current_stage=p_target_stage,
   workflow_status=case when p_target_stage='parallel_review' then 'PARALLEL_REVIEW_IN_PROGRESS' else 'RETURNED_FOR_REVISION' end,
   hr_completed=case when p_target_stage in ('self','parallel_review') then false else hr_completed end,
   manager_completed=case when p_target_stage in ('self','parallel_review') then false else manager_completed end,
   locked=false,final_score=null,final_rating=null,final_breakdown=null,
   version=version+1,updated_at=now()
  where id=p_evaluation_id returning * into v_eval;

 else
  -- V17 return paths (unchanged)
  if v_from='hr_review' and p_target_stage='self' then
   if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN'; end if;
  elsif v_from='manager_review' and p_target_stage in ('hr_review','self') then
   if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
  elsif v_from='manager_final' and p_target_stage in ('manager_review','hr_review','self') then
   if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN'; end if;
  elsif public.current_is_executive_secretary() and p_target_stage in ('self','manager_review','hr_review','manager_final') then
   null;
  else raise exception 'INVALID_RETURN_TARGET'; end if;

  update public.kpi_evaluations set stage=p_target_stage,current_stage=p_target_stage,workflow_status='RETURNED_FOR_REVISION',
   locked=false,final_score=null,final_rating=null,final_breakdown=null,version=version+1,updated_at=now()
  where id=p_evaluation_id returning * into v_eval;
 end if;

 perform public.log_audit_event('kpi.stage_returned','workflow','warning','kpi_evaluations',p_evaluation_id,'إعادة التقييم للتصحيح',trim(p_note),jsonb_build_object('from',v_from,'to',p_target_stage,'parallel',v_parallel));
 return v_eval;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Evaluation form — V23 editability + parallel fields
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_kpi_evaluation_form(p_evaluation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_employee public.employees; v_cycle public.kpi_cycles;
 v_editable text; v_locked boolean; v_criteria jsonb; v_parallel boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if not public.kpi_can_read_evaluation(p_evaluation_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select * into v_employee from public.employees where id=v_eval.employee_id;
 select * into v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_locked:=v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle);
 v_parallel:=coalesce(v_cycle.use_parallel_flow,false);

 if not v_locked then
  if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_editable:='self';
  elsif v_parallel and v_eval.current_stage='parallel_review' then
   -- In V23 parallel: HR and Manager both get editability
   if public.current_is_hr_reviewer() and not v_eval.hr_completed then v_editable:='hr_review';
   elsif public.kpi_is_direct_manager(v_eval.employee_id) and not v_eval.manager_completed then v_editable:='manager_review';
   end if;
  elsif v_eval.current_stage='secretary_review' and public.current_is_executive_secretary() then v_editable:='secretary_review';
  elsif v_eval.current_stage='executive_review' and public.current_has_active_role(array['executive','executive-director']) then v_editable:='executive_review';
  -- V17 sequential stages
  elsif v_eval.current_stage='hr_review' and public.current_is_hr_reviewer() then v_editable:='hr_review';
  elsif v_eval.current_stage='manager_review' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_review';
  elsif v_eval.current_stage='manager_final' and public.kpi_is_direct_manager(v_eval.employee_id) then v_editable:='manager_final';
  end if;
 end if;

 -- Auto-status transitions
 if v_parallel and v_eval.current_stage='parallel_review' and v_eval.workflow_status='PARALLEL_REVIEW_IN_PROGRESS' then
  if v_editable='hr_review' then
   update public.kpi_evaluations set workflow_status='HR_EVALUATION_IN_PROGRESS',updated_at=now() where id=v_eval.id returning * into v_eval;
  elsif v_editable='manager_review' then
   update public.kpi_evaluations set workflow_status='MANAGER_EVALUATION_IN_PROGRESS',updated_at=now() where id=v_eval.id returning * into v_eval;
  end if;
 elsif not v_parallel then
  if v_editable='hr_review' and v_eval.workflow_status='SUBMITTED_TO_HR' then
   update public.kpi_evaluations set workflow_status='HR_REVIEW',updated_at=now() where id=v_eval.id returning * into v_eval;
   perform public.log_audit_event('kpi.hr.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء HR مراجعة التقييم',null,null);
  end if;
  if v_editable='manager_review' and v_eval.workflow_status='SUBMITTED_TO_DIRECT_MANAGER' then
   update public.kpi_evaluations set workflow_status='MANAGER_REVIEW',updated_at=now() where id=v_eval.id returning * into v_eval;
   perform public.log_audit_event('kpi.manager.review_started','workflow','info','kpi_evaluations',v_eval.id,'بدء المدير المباشر مراجعة التقييم',null,null);
  end if;
 end if;

 select coalesce(jsonb_agg(jsonb_build_object(
  'id',c.id,'code',c.code,'name',c.name_ar,'description',c.description,'sectionCode',c.section_code,
  'weight',c.weight,'maxScore',c.max_score,'sortOrder',c.sort_order,'sourceType',c.source_type,
  'evaluatorStage',c.evaluator_stage,'calculationMethod',c.calculation_method,
  'editable',case
    when v_editable='self' then true
    when v_editable='hr_review' then c.evaluator_stage='hr'
    when v_editable in ('manager_review','manager_final') then c.evaluator_stage='manager'
    else false end,
  'effectiveScore',public.kpi_effective_score(v_eval.id,c.id),
  'stageScores',coalesce((select jsonb_object_agg(s.reviewer_stage,jsonb_build_object('score',s.score,'note',s.note)) from public.kpi_scores s where s.evaluation_id=v_eval.id and s.criterion_id=c.id),'{}')
 ) order by c.sort_order),'[]'::jsonb) into v_criteria from public.kpi_criteria c where c.template_id=v_eval.template_id;

 return jsonb_build_object(
  'id',v_eval.id,'employeeId',v_eval.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
  'periodMonth',v_cycle.period_month,'currentStage',v_eval.current_stage,'workflowStatus',v_eval.workflow_status,'editableStage',v_editable,
  'locked',v_locked,'finalScore',v_eval.final_score,'finalRating',v_eval.final_rating,'criteria',v_criteria,
  'parallelFlow',v_parallel,'hrCompleted',v_eval.hr_completed,'managerCompleted',v_eval.manager_completed,'version',v_eval.version,
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
-- 7. save_kpi_goal — allow during parallel_review (manager side)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.save_kpi_goal(
 p_evaluation_id uuid,p_goal_id uuid,p_title text,p_description text,p_target_value numeric,
 p_achieved_value numeric,p_unit text,p_weight numeric,p_due_date date,p_evidence_source text,
 p_employee_note text,p_manager_note text,p_status text
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_id uuid; v_owner boolean; v_manager boolean;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 select * into strict v_cycle from public.kpi_cycles where id=v_eval.cycle_id;
 v_owner:=v_eval.employee_id=public.current_employee_id();
 v_manager:=public.kpi_is_direct_manager(v_eval.employee_id);
 if v_eval.locked or v_cycle.status<>'open' or now()>public.kpi_effective_deadline(v_cycle) then raise exception 'KPI_CYCLE_CLOSED'; end if;
 if p_status not in ('NOT_STARTED','IN_PROGRESS','COMPLETED','PARTIALLY_COMPLETED','BLOCKED','CANCELLED_BY_MANAGEMENT','DEFERRED_WITH_MANAGER_APPROVAL') then raise exception 'INVALID_GOAL_STATUS'; end if;
 -- V23: allow during parallel_review for manager; V17: allow during manager_review
 if v_manager and v_eval.current_stage in ('manager_review','parallel_review') then
  if length(trim(coalesce(p_title,'')))<3 or p_target_value<=0 or p_achieved_value<0 or p_weight<=0 or p_weight>40 then raise exception 'INVALID_GOAL'; end if;
  if p_goal_id is null then
   insert into public.kpi_goals(evaluation_id,title,description,target_value,achieved_value,unit,weight,due_date,evidence_source,employee_note,manager_note,status,created_by)
   values(p_evaluation_id,trim(p_title),p_description,p_target_value,p_achieved_value,trim(p_unit),p_weight,p_due_date,p_evidence_source,p_employee_note,p_manager_note,p_status,auth.uid()) returning id into v_id;
  else
   update public.kpi_goals set title=trim(p_title),description=p_description,target_value=p_target_value,achieved_value=p_achieved_value,unit=trim(p_unit),weight=p_weight,due_date=p_due_date,evidence_source=p_evidence_source,employee_note=p_employee_note,manager_note=p_manager_note,status=p_status,updated_at=now()
   where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
  end if;
 elsif v_owner and v_eval.current_stage='self' and v_eval.workflow_status<>'DRAFT' and p_goal_id is not null then
  update public.kpi_goals set achieved_value=p_achieved_value,evidence_source=p_evidence_source,employee_note=p_employee_note,status=p_status,updated_at=now()
  where id=p_goal_id and evaluation_id=p_evaluation_id returning id into v_id;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_id is null then raise exception 'GOAL_NOT_FOUND'; end if;
 perform public.log_audit_event('kpi.goal.saved','workflow','info','kpi_goals',v_id,'حفظ هدف تقييم الأداء',null,jsonb_build_object('evaluationId',p_evaluation_id,'status',p_status));
 return v_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. save_kpi_review_session — allow during parallel_review (manager side)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.save_kpi_review_session(p_evaluation_id uuid,p_session jsonb)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_manager uuid; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 -- V23: allow during parallel_review; V17: allow during manager_review
 if v_eval.current_stage not in ('manager_review','parallel_review') or not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 v_manager:=public.current_employee_id();
 if coalesce(p_session->>'mode','') not in ('ONSITE','REMOTE') then raise exception 'INVALID_SESSION_MODE'; end if;
 insert into public.kpi_review_sessions(evaluation_id,employee_id,manager_employee_id,scheduled_at,held_at,mode,discussion_summary,strengths,improvement_points,next_month_goals,employee_notes,manager_notes,employee_attended,manager_attended,manager_approved_at,created_by)
 values(p_evaluation_id,v_eval.employee_id,v_manager,nullif(p_session->>'scheduledAt','')::timestamptz,nullif(p_session->>'heldAt','')::timestamptz,p_session->>'mode',nullif(trim(p_session->>'discussionSummary'),''),nullif(trim(p_session->>'strengths'),''),nullif(trim(p_session->>'improvementPoints'),''),nullif(trim(p_session->>'nextMonthGoals'),''),nullif(trim(p_session->>'employeeNotes'),''),nullif(trim(p_session->>'managerNotes'),''),coalesce((p_session->>'employeeAttended')::boolean,false),coalesce((p_session->>'managerAttended')::boolean,false),case when nullif(p_session->>'heldAt','') is not null then now() end,auth.uid())
 on conflict(evaluation_id) do update set scheduled_at=excluded.scheduled_at,held_at=excluded.held_at,mode=excluded.mode,discussion_summary=excluded.discussion_summary,strengths=excluded.strengths,improvement_points=excluded.improvement_points,next_month_goals=excluded.next_month_goals,employee_notes=excluded.employee_notes,manager_notes=excluded.manager_notes,employee_attended=excluded.employee_attended,manager_attended=excluded.manager_attended,manager_approved_at=excluded.manager_approved_at,updated_at=now()
 returning id into v_id;
 perform public.log_audit_event('kpi.session.saved','workflow','notice','kpi_review_sessions',v_id,'تسجيل جلسة تقييم الموظف والمدير',null,jsonb_build_object('evaluationId',p_evaluation_id));
 return v_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. save_kpi_compliance_metric — allow during parallel_review (HR side)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.save_kpi_compliance_metric(
 p_evaluation_id uuid,p_metric text,p_required integer,p_actual integer,p_exempt integer default 0,p_cancelled integer default 0,p_note text default null
)
returns numeric language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_eligible integer; v_score numeric; v_criterion uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 -- V23: allow during parallel_review; V17: allow during hr_review
 if v_eval.current_stage not in ('hr_review','parallel_review') or not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_metric not in ('PRAYER','HALAQA') or least(p_required,p_actual,p_exempt,p_cancelled)<0 then raise exception 'INVALID_COMPLIANCE_INPUT'; end if;
 v_eligible:=greatest(p_required-p_exempt-p_cancelled,0);
 if p_actual>v_eligible then raise exception 'ACTUAL_EXCEEDS_REQUIRED'; end if;
 v_score:=case when v_eligible=0 then 5 else round(p_actual::numeric/v_eligible*5,2) end;
 insert into public.kpi_compliance_records(evaluation_id,metric,required_count,actual_count,exempt_count,cancelled_count,calculated_score,note,approved_at,approved_by,created_by)
 values(p_evaluation_id,p_metric,p_required,p_actual,p_exempt,p_cancelled,v_score,p_note,now(),public.current_employee_id(),auth.uid())
 on conflict(evaluation_id,metric) do update set required_count=excluded.required_count,actual_count=excluded.actual_count,exempt_count=excluded.exempt_count,cancelled_count=excluded.cancelled_count,calculated_score=excluded.calculated_score,note=excluded.note,approved_at=now(),approved_by=public.current_employee_id(),updated_at=now();
 select c.id into strict v_criterion from public.kpi_criteria c where c.template_id=v_eval.template_id and c.code=p_metric;
 insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
 values(p_evaluation_id,v_criterion,v_score,'hr',p_note,auth.uid())
 on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
 perform public.log_audit_event('kpi.compliance.calculated','workflow','info','kpi_evaluations',p_evaluation_id,'احتساب معيار HR',null,jsonb_build_object('metric',p_metric,'score',v_score));
 return v_score;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. add_kpi_evidence — allow during parallel_review
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.add_kpi_evidence(p_evaluation_id uuid,p_criterion_id uuid,p_type text,p_title text,p_description text default null,p_storage_path text default null,p_external_url text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_stage text; v_id uuid;
begin
 select * into strict v_eval from public.kpi_evaluations where id=p_evaluation_id for update;
 if v_eval.locked then raise exception 'EVALUATION_LOCKED'; end if;
 if v_eval.current_stage='self' and v_eval.employee_id=public.current_employee_id() then v_stage:='self';
 elsif v_eval.current_stage in ('manager_review','parallel_review') and public.kpi_is_direct_manager(v_eval.employee_id) then v_stage:=v_eval.current_stage;
 else raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_type not in ('document','link','note','task','report','other') or length(trim(coalesce(p_title,'')))<3 then raise exception 'INVALID_EVIDENCE'; end if;
 if p_criterion_id is not null and not exists(select 1 from public.kpi_criteria where id=p_criterion_id and template_id=v_eval.template_id) then raise exception 'INVALID_CRITERION'; end if;
 insert into public.kpi_evidence(evaluation_id,criterion_id,evidence_type,title,description,storage_path,external_url,submitted_stage,submitted_by,created_by)
 values(p_evaluation_id,p_criterion_id,p_type,trim(p_title),p_description,p_storage_path,p_external_url,v_stage,public.current_employee_id(),auth.uid()) returning id into v_id;
 perform public.log_audit_event('kpi.evidence.added','workflow','info','kpi_evidence',v_id,'إضافة دليل إلى التقييم',null,jsonb_build_object('evaluationId',p_evaluation_id,'criterionId',p_criterion_id));
 return v_id;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. get_kpi_inbox — include V23 fields in summary
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.get_kpi_inbox(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
 return coalesce((
  select jsonb_agg(jsonb_build_object(
   'id',e.id,'employeeId',e.employee_id,'employeeName',emp.full_name_ar,'employeeCode',emp.employee_code,
   'employeePhotoUrl',emp.photo_url,'periodMonth',c.period_month,
   'currentStage',e.current_stage,'workflowStatus',e.workflow_status,
   'finalScore',e.final_score,'finalRating',e.final_rating,
   'hrCompleted',e.hr_completed,'managerCompleted',e.manager_completed,
   'parallelFlow',coalesce(c.use_parallel_flow,false),'version',e.version
  ) order by c.period_month desc,emp.full_name_ar)
  from public.kpi_evaluations e
  join public.employees emp on emp.id=e.employee_id
  join public.kpi_cycles c on c.id=e.cycle_id
  where (
    e.employee_id=public.current_employee_id()
    or public.current_is_hr_reviewer()
    or public.kpi_is_direct_manager(e.employee_id)
    or public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive','executive-director'])
    or public.has_any_permission(array['performance.kpi.read','performance.kpi.report.read'])
  )
  and c.status in ('open','locked')
  limit p_limit
 ),'[]'::jsonb);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. create_kpi_cycle_admin — pass through use_parallel_flow flag
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.create_kpi_cycle_admin(
 p_month date,p_template_id uuid,p_self_due timestamptz,p_manager_due timestamptz,
 p_secretary_due timestamptz,p_executive_due timestamptz,p_open_now boolean default true,
 p_use_parallel_flow boolean default false
)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_id uuid; v_month date:=date_trunc('month',p_month)::date; v_template uuid; v_policy uuid;
 v_open timestamptz; v_deadline timestamptz; v_status text:='draft';
begin
 if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 select id into strict v_template from public.kpi_templates where official_code='OFFICIAL_KPI_100' and is_active;
 if p_template_id is distinct from v_template then raise exception 'ONLY_OFFICIAL_KPI_TEMPLATE_IS_ALLOWED'; end if;
 select id into strict v_policy from public.kpi_policy_versions where is_active;
 v_open:=((v_month+19)::timestamp at time zone 'Africa/Cairo');
 v_deadline:=(((v_month+25)::timestamp at time zone 'Africa/Cairo')-interval '1 second');
 if coalesce(p_open_now,false) and now() between v_open and v_deadline then v_status:='open'; end if;
 insert into public.kpi_cycles(period_month,status,template_id,scheduled_open_at,deadline_at,self_due_at,manager_due_at,secretary_due_at,executive_due_at,opened_at,opened_by,policy_version_id,use_parallel_flow,created_by)
 values(v_month,v_status,v_template,v_open,v_deadline,v_deadline,v_deadline,v_deadline,v_deadline,case when v_status='open' then now() end,case when v_status='open' then public.current_employee_id() end,v_policy,coalesce(p_use_parallel_flow,false),auth.uid())
 on conflict(period_month) do update set
  template_id=excluded.template_id,scheduled_open_at=excluded.scheduled_open_at,deadline_at=excluded.deadline_at,
  self_due_at=excluded.self_due_at,manager_due_at=excluded.manager_due_at,
  secretary_due_at=excluded.secretary_due_at,executive_due_at=excluded.executive_due_at,
  policy_version_id=coalesce(kpi_cycles.policy_version_id,excluded.policy_version_id),
  use_parallel_flow=excluded.use_parallel_flow,updated_at=now()
 returning id into v_id;
 insert into public.kpi_evaluations(employee_id,cycle_id,template_id,stage,current_stage,workflow_status,locked,created_by)
 select e.id,v_id,v_template,'self','self',case when v_status='open' then 'OPEN_FOR_SELF_EVALUATION' else 'DRAFT' end,v_status<>'open',auth.uid()
 from public.employees e
 where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
   and not exists(
     select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
     where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
       and (ur.effective_from is null or ur.effective_from<=now())
       and (ur.effective_to is null or ur.effective_to>now())
   )
 on conflict(employee_id,cycle_id,template_id) do nothing;
 perform public.refresh_kpi_attendance_inputs(v_id);
 perform public.log_audit_event('kpi.cycle.created','workflow','notice','kpi_cycles',v_id,'إنشاء دورة KPI',null,jsonb_build_object('month',v_month,'openAt',v_open,'deadline',v_deadline,'status',v_status,'parallelFlow',p_use_parallel_flow));
 return v_id;
end $$;

commit;
