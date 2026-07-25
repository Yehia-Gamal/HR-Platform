-- 0146: V17 §9.2.2 — إشعارات انتقال مراحل تقييم الأداء.
-- يُعيد تعريف advance_kpi_stage و return_kpi_stage مع إضافة notify_employee
-- عند كل انتقال أو إعادة مرحلة:
--   • self → hr_review:       إشعار موظفي HR (hr-manager / hr-specialist)
--   • hr_review → manager_review: إشعار المدير المباشر
--   • finalized:              إشعار الموظف باعتماد تقييمه
--   • إعادة المرحلة:         إشعار الطرف المُعاد إليه
-- ============================================================================

-- ── 1) advance_kpi_stage مع إشعارات المراحل ──

create or replace function public.advance_kpi_stage(
 p_evaluation_id uuid,p_action text,p_scores jsonb default null,p_note text default null
)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_expected text; v_next text; v_workflow text;
 v_row jsonb; v_score numeric; v_criterion public.kpi_criteria; v_errors text[]; v_total numeric; v_rating text;
 v_required_count integer; v_received_count integer;
 v_emp_name text; v_manager_eid uuid;
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

 -- ── §9.2.2: إشعار الطرف التالي بعد انتقال المرحلة ──
 select full_name into v_emp_name from public.employees where id=v_eval.employee_id;

 if v_next='hr_review' then
   -- إشعار موظفي HR (hr-manager, hr-specialist) أن تقييماً بحاجة لمراجعتهم
   insert into public.notifications(
     recipient_user_id, recipient_employee_id, title, body,
     category, priority, entity_type, entity_id, metadata, created_by
   )
   select p.id, e.id,
     'تقييم أداء بحاجة لمراجعة HR',
     coalesce(v_emp_name, 'موظف'),
     'kpi', 'normal', 'kpi_evaluation', v_eval.id,
     jsonb_build_object('action','hr_review_needed','evaluationId',v_eval.id::text),
     coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
   from public.employees e
   join public.profiles p on p.employee_id = e.id
   join public.user_roles ur on ur.user_id = p.id
   join public.roles r on r.id = ur.role_id
   where r.slug in ('hr-manager','hr-specialist')
     and ur.effective_from <= now()
     and (ur.effective_to is null or ur.effective_to > now())
     and e.is_active and not e.is_deleted;

 elsif v_next='manager_review' then
   -- إشعار المدير المباشر أن تقييماً جاهزاً لمراجعته
   select mr.manager_employee_id into v_manager_eid
   from public.manager_relations mr
   where mr.employee_id=v_eval.employee_id and mr.relation_type='primary'
     and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date)
   limit 1;
   perform public.notify_employee(
     v_manager_eid,
     'تقييم أداء بحاجة لمراجعتك',
     coalesce(v_emp_name, 'موظف'),
     'kpi','normal','kpi_evaluation',v_eval.id,
     jsonb_build_object('action','manager_review_needed','evaluationId',v_eval.id::text)
   );

 elsif v_next='finalized' then
   -- إشعار الموظف باعتماد تقييمه
   perform public.notify_employee(
     v_eval.employee_id,
     'تم اعتماد تقييم أدائك',
     'النتيجة: ' || coalesce(v_total::text, '—') || ' — ' || coalesce(v_rating, ''),
     'kpi','normal','kpi_evaluation',v_eval.id,
     jsonb_build_object('action','evaluation_finalized','evaluationId',v_eval.id::text,'finalScore',v_total)
   );
 end if;

 return v_eval;
end $$;

-- ── 2) return_kpi_stage مع إشعار الطرف المُعاد إليه ──

create or replace function public.return_kpi_stage(p_evaluation_id uuid,p_target_stage text,p_note text)
returns public.kpi_evaluations language plpgsql security definer set search_path=public,pg_temp as $$
declare v_eval public.kpi_evaluations; v_cycle public.kpi_cycles; v_from text;
 v_emp_name text; v_manager_eid uuid;
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

 -- ── §9.2.2: إشعار الطرف المُعاد إليه ──
 select full_name into v_emp_name from public.employees where id=v_eval.employee_id;

 if p_target_stage='self' then
   -- إشعار الموظف بأن تقييمه أُعيد للتصحيح
   perform public.notify_employee(
     v_eval.employee_id,
     'تم إعادة تقييمك للتعديل',
     coalesce(trim(p_note), 'يرجى مراجعة التقييم'),
     'kpi','high','kpi_evaluation',v_eval.id,
     jsonb_build_object('action','returned_to_self','from',v_from,'evaluationId',v_eval.id::text)
   );

 elsif p_target_stage='hr_review' then
   -- إشعار موظفي HR بأن التقييم أُعيد لهم
   insert into public.notifications(
     recipient_user_id, recipient_employee_id, title, body,
     category, priority, entity_type, entity_id, metadata, created_by
   )
   select p.id, e.id,
     'تقييم أداء أُعيد لمراجعة HR',
     coalesce(v_emp_name, 'موظف') || ' — ' || coalesce(trim(p_note), ''),
     'kpi', 'high', 'kpi_evaluation', v_eval.id,
     jsonb_build_object('action','returned_to_hr','from',v_from,'evaluationId',v_eval.id::text),
     coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
   from public.employees e
   join public.profiles p on p.employee_id = e.id
   join public.user_roles ur on ur.user_id = p.id
   join public.roles r on r.id = ur.role_id
   where r.slug in ('hr-manager','hr-specialist')
     and ur.effective_from <= now()
     and (ur.effective_to is null or ur.effective_to > now())
     and e.is_active and not e.is_deleted;

 elsif p_target_stage='manager_review' then
   -- إشعار المدير المباشر بأن التقييم أُعيد له
   select mr.manager_employee_id into v_manager_eid
   from public.manager_relations mr
   where mr.employee_id=v_eval.employee_id and mr.relation_type='primary'
     and mr.effective_from<=current_date and (mr.effective_to is null or mr.effective_to>=current_date)
   limit 1;
   perform public.notify_employee(
     v_manager_eid,
     'تقييم أداء أُعيد لمراجعتك',
     coalesce(v_emp_name, 'موظف') || ' — ' || coalesce(trim(p_note), ''),
     'kpi','high','kpi_evaluation',v_eval.id,
     jsonb_build_object('action','returned_to_manager','from',v_from,'evaluationId',v_eval.id::text)
   );
 end if;

 return v_eval;
end $$;

comment on function public.advance_kpi_stage(uuid,text,jsonb,text) is
  'V17 §10+§9.2.2: تقدّم مرحلة تقييم KPI مع إشعار الطرف التالي. 0146: أُضيفت إشعارات HR/مدير/موظف.';
comment on function public.return_kpi_stage(uuid,text,text) is
  'V17 §10+§9.2.2: إعادة مرحلة تقييم KPI مع إشعار الطرف المُعاد إليه. 0146: أُضيفت إشعارات الإعادة.';
