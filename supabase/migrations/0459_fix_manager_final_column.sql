-- 0459: إصلاح عمود manager_final_comment غير الموجود في advance_kpi_stage
-- الجذر: دالة advance_kpi_stage (0457) تستخدم manager_final_comment في مسار V17
-- لكن الجدول يحتوي فقط على manager_comment (تُستخدم لكلا المرحلتين).
-- الحل: استبدال manager_final_comment بـ manager_comment.

create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid, p_action text, p_scores jsonb default null, p_note text default null
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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
   when 'hr_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null;
   when 'manager_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null;
   when 'parallel_review' then v_expected:='parallel_review';v_next:=null;v_workflow:=null;
   when 'secretary_review' then v_expected:='secretary_review';v_next:='executive_review';v_workflow:='EXECUTIVE_REVIEW';
   when 'executive_review' then v_expected:='executive_review';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
   else raise exception 'INVALID_KPI_ACTION';
  end case;
  if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

  -- self: insert scores and advance
  if p_action='self' then
   if v_eval.employee_id<>public.current_employee_id() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
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
  update public.kpi_evaluations set
   stage=v_next,current_stage=v_next,workflow_status=v_workflow,
   self_completed=true,self_completed_at=now(),self_completed_by=public.current_employee_id(),
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;

 elsif p_action in ('hr_review','manager_review','parallel_review') then
   -- barrier: require both HR and manager completed, then advance to secretary_review
   if not (public.current_is_hr_reviewer() or public.kpi_is_direct_manager(v_eval.employee_id))
     and p_action<>'parallel_review' then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   v_both_done:=coalesce(v_eval.hr_completed,false) and coalesce(v_eval.manager_completed,false);
   if not v_both_done then raise exception 'BARRIER_NOT_MET'; end if;
   v_next:='secretary_review'; v_workflow:='SECRETARY_REVIEW';
   update public.kpi_evaluations set
    stage=v_next,current_stage=v_next,workflow_status=v_workflow,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;

  elsif p_action='secretary_review' then
   if not public.current_is_executive_secretary() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
   if p_scores is not null and jsonb_typeof(p_scores)='array' then
    for v_row in select * from jsonb_array_elements(p_scores) loop
     select * into v_criterion from public.kpi_criteria where id=(v_row->>'criterion_id')::uuid and template_id=v_eval.template_id and evaluator_stage='secretary';
     if v_criterion.id is not null then
      v_score:=(v_row->>'score')::numeric;
      if v_score>=0 and v_score<=v_criterion.max_score then
       insert into public.kpi_scores(evaluation_id,criterion_id,score,reviewer_stage,note,created_by)
       values(v_eval.id,v_criterion.id,v_score,'secretary',nullif(trim(v_row->>'note'),''),auth.uid())
       on conflict(evaluation_id,criterion_id,reviewer_stage) do update set score=excluded.score,note=excluded.note,updated_at=now(),created_by=auth.uid();
      end if;
     end if;
    end loop;
   end if;
   update public.kpi_evaluations set
    stage=v_next,current_stage=v_next,workflow_status=v_workflow,
    version=version+1,updated_at=now()
   where id=v_eval.id returning * into v_eval;

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
    'workflowStatus',v_eval.workflow_status,'note',p_note,'finalScore',v_eval.final_score));
  if v_eval.current_stage='finalized' then
   perform public.log_audit_event('kpi.executive.approved','workflow','notice','kpi_evaluations',v_eval.id,
    'اعتماد المدير التنفيذي للنتيجة النهائية',p_note,jsonb_build_object('finalScore',v_eval.final_score));
   perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,
    'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
  end if;
  return v_eval;
 end if;

 -- ═══════════════════════════════════════════════════════════════════════════
 -- V17 SEQUENTIAL PATH
 -- ═══════════════════════════════════════════════════════════════════════════
 case p_action
  when 'self' then v_expected:='self';v_next:='hr_review';v_workflow:='SUBMITTED_TO_HR';
  when 'hr_review' then v_expected:='hr_review';v_next:='manager_review';v_workflow:='SUBMITTED_TO_DIRECT_MANAGER';
  when 'manager_review' then v_expected:='manager_review';v_next:='manager_final';v_workflow:='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL';
  when 'manager_final' then v_expected:='manager_final';v_next:='finalized';v_workflow:='INCLUDED_IN_MONTHLY_REPORT';
  else raise exception 'INVALID_KPI_ACTION';
 end case;
 if v_eval.current_stage<>v_expected then raise exception 'STAGE_OUT_OF_ORDER expected %, found %',v_expected,v_eval.current_stage; end if;

 -- self: insert scores, advance to hr_review
 if p_action='self' then
  if v_eval.employee_id<>public.current_employee_id() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_scores is null or jsonb_typeof(p_scores)<>'array' then raise exception 'SELF_SCORES_REQUIRED'; end if;
  select count(*) into v_required_count from public.kpi_criteria where template_id=v_eval.template_id;
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
  update public.kpi_evaluations set
   stage=v_next,current_stage=v_next,workflow_status=v_workflow,
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;

 elsif v_expected='hr_review' then
  if not public.current_is_hr_reviewer() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  perform public.refresh_kpi_attendance_inputs(v_eval.cycle_id);
  if not exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id)
     or exists(select 1 from public.kpi_attendance_snapshots where evaluation_id=v_eval.id and has_pending_items) then raise exception 'ATTENDANCE_ITEMS_PENDING'; end if;
  if (select count(*) from public.kpi_compliance_records where evaluation_id=v_eval.id and metric in ('PRAYER','HALAQA'))<>2 then raise exception 'HR_COMPLIANCE_INPUTS_REQUIRED'; end if;
  update public.kpi_evaluations set
   stage=v_next,current_stage=v_next,workflow_status=v_workflow,
   hr_comment=nullif(trim(p_note),''),
   hr_approved_at=now(),hr_approved_by=public.current_employee_id(),
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;

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
  update public.kpi_evaluations set
   stage=v_next,current_stage=v_next,workflow_status=v_workflow,
   manager_approved_at=now(),manager_approved_by=public.current_employee_id(),
   version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;

 elsif v_expected='manager_final' then
  if not public.kpi_is_direct_manager(v_eval.employee_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if length(trim(coalesce(p_note,'')))<3 then raise exception 'MANAGER_COMMENT_REQUIRED'; end if;
  update public.kpi_evaluations set manager_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
  v_errors:=public.get_kpi_validation_errors(v_eval.id);
  if cardinality(v_errors)>0 then raise exception 'KPI_VALIDATION_FAILED: %',array_to_string(v_errors,' | '); end if;
  v_total:=public.kpi_total_score(v_eval.id);
  if v_total<0 or v_total>100 then raise exception 'FINAL_SCORE_OUT_OF_RANGE'; end if;
  v_rating:=public.kpi_rating_for_score(v_cycle.policy_version_id,v_total);
  update public.kpi_evaluations set
   stage=v_next,current_stage=v_next,workflow_status=v_workflow,
   final_score=v_total,final_rating=v_rating,
   final_breakdown=(select jsonb_object_agg(c.code,public.kpi_effective_score(v_eval.id,c.id)) from public.kpi_criteria c where c.template_id=v_eval.template_id),
   rating_policy_snapshot=(select rating_bands from public.kpi_policy_versions where id=v_cycle.policy_version_id),
   locked=true,version=version+1,updated_at=now()
  where id=v_eval.id returning * into v_eval;
 end if;

 perform public.log_audit_event('kpi.stage_advanced','workflow','notice','kpi_evaluations',v_eval.id,
  'انتقال مرحلة تقييم الأداء (V17)',null,
  jsonb_build_object('action',p_action,'from',v_expected,'to',v_eval.current_stage,
   'workflowStatus',v_eval.workflow_status,'note',p_note,'finalScore',v_eval.final_score));
 if v_eval.current_stage='finalized' then
  perform public.log_audit_event('kpi.executive.approved','workflow','notice','kpi_evaluations',v_eval.id,
   'اعتماد المدير التنفيذي للنتيجة النهائية',p_note,jsonb_build_object('finalScore',v_eval.final_score));
  perform public.log_audit_event('kpi.monthly_report.included','workflow','info','kpi_evaluations',v_eval.id,
   'إدراج التقييم في التقرير الشهري',null,jsonb_build_object('cycleId',v_eval.cycle_id));
 end if;
 return v_eval;
end $$;
