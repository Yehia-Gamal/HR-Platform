-- ============================================================================
-- 0457: إصلاحات أخطاء إنتاج حرجة
-- ============================================================================
-- 1) إعادة رفع الطلبات المُرجعة: استخدام resolve_request_approver بدلاً من
--    lookup مباشر على manager_relations (يفقد توجيه التشغيل→تنفيذي + سقوط HR).
-- 2) تقييم الأداء الذاتي: إزالة قيد DIRECT_MANAGER_NOT_ASSIGNED الذي يمنع
--    الموظف من تقديم تقييمه الذاتي عندما لا يوجد مدير مباشر نشط.
-- 3) تغيير كلمة المرور: إضافة RPC لتحقق القوة على الخادم لت统一 التحقق
--    بين الويب والموبايل.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) إصلاح resubmit_my_request — استخدام resolve_request_approver
-- ═══════════════════════════════════════════════════════════════════════════
-- المشكلة: الدالة تبحث عن المدير المباشر يدوياً عبر manager_relations
-- مباشرة (سطور 86-96 في 0452) مما يفقد:
--   أ) توجيه التشغيل → المدير التنفيذي
--   ب) السقوط على hr-manager / hr-specialist
--   ج) منع الموافقة الذاتية للمدير المباشر
-- الحل: استدعاء resolve_request_approver الذي ي_face كل هذه الحالات.

create or replace function public.resubmit_my_request(
  p_request_id uuid,
  p_title      text,
  p_reason     text,
  p_payload    jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := public.current_employee_id();
  v_req     public.requests;
  v_def     public.workflow_definitions;
  v_manager uuid;
  v_due     timestamptz;
  v_esc     timestamptz;
  v_first_approver uuid;
  v_exec_emp uuid;
  v_label   text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- المالك حصراً
  if v_req.employee_id <> v_me then
    raise exception 'FORBIDDEN: only the requester may resubmit' using errcode = '42501';
  end if;

  -- من المرفوض/المُرجَع فقط
  if v_req.status not in ('rejected', 'returned') then
    raise exception 'ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT' using errcode = '22023';
  end if;

  -- الأنواع القابلة لإعادة الرفع (نفس أنواع submit_my_request عدا التصحيح)
  if v_req.request_type not in
     ('leave','mission','convoy','fundraising','late_permit','early_permit') then
    raise exception 'TYPE_NOT_RESUBMITTABLE' using errcode = '22023';
  end if;

  -- تحقق الطول (مطابق لقيود الجدول)
  if p_title is null or length(trim(p_title)) < 3 or length(trim(p_title)) > 300 then
    raise exception 'INVALID_TITLE_LENGTH' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'INVALID_REASON_LENGTH' using errcode = '22023';
  end if;

  -- 0457: استخدام resolve_request_approver بدلاً من lookup مباشر.
  -- يضمن التوجيه الصحيح لطلبات التشغيل→تنفيذي + السقوط على HR + منع الموافقة الذاتية.
  v_manager := public.resolve_request_approver(v_req.employee_id);

  -- مهلات السير من التعريف النشط
  if v_req.workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = v_req.workflow_definition_id;
  end if;
  if v_def.id is null or not v_def.is_active then
    select * into v_def from public.workflow_definitions
      where request_type = v_req.request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;
  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  -- 1) تحديث الطلب وتصفير القرار
  update public.requests set
    title                = trim(p_title),
    reason               = trim(p_reason),
    payload              = coalesce(p_payload, '{}'::jsonb),
    status               = 'pending',
    workflow_status      = 'submitted',
    current_step_order   = 1,
    manager_employee_id  = coalesce(v_manager, manager_employee_id),
    decision_due_at      = v_due,
    escalation_deadline  = v_esc,
    escalated_at         = null,
    decided_at           = null,
    decided_by           = null,
    updated_at           = now()
  where id = v_req.id
  returning * into v_req;

  -- 2) خطوات جديدة من التعريف (الأولى نشطة بمهلتها)
  delete from public.request_steps where request_id = v_req.id;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_req.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then v_manager
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours := ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    -- 3) إعادة فتح نسخة السير نفسها (قيد فريد: نسخة واحدة لكل طلب)
    update public.workflow_instances
      set definition_id      = v_def.id,
          definition_version = coalesce(v_def.version, 1),
          status             = 'running',
          current_step_order = 1,
          updated_at         = now()
      where request_id = v_req.id;

    if not found then
      insert into public.workflow_instances (
        definition_id, request_id, definition_version, status, current_step_order, created_by
      ) values (
        v_def.id, v_req.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
      );
    end if;
  end if;

  -- 4) توثيق الإجراء
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    v_req.id, v_me, 'submit', 'rejected', 'pending', trim(p_reason), auth.uid()
  );

  -- 5) الإشعارات
  v_label := format('%s — %s (مُعادة بعد تعديل)',
    public.request_type_label(v_req.request_type), coalesce(v_req.title, ''));

  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_req.id and s.status = 'active'
  order by s.step_order limit 1;
  if v_first_approver is null then
    v_first_approver := v_req.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_req.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب مُعدّل بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'workflowStatus', 'submitted',
        'resubmitted', true,
        'deepLink', '/requests/' || v_req.id
      )
    );
  end if;

  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'طلب مُعدّل — للمراجعة',
      v_label,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'resubmitted', true,
        'infoOnly', false
      )
    );
  end if;

  return to_jsonb(v_req);
end;
$$;

comment on function public.resubmit_my_request(uuid, text, text, jsonb) is
  '0457: إعادة رفع طلب مرفوض/مُرجَع بعد تعديله — يُستخدم resolve_request_approver للمدير الصحيح.';

revoke all on function public.resubmit_my_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.resubmit_my_request(uuid, text, text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) إصلاح advance_kpi_stage — إزالة DIRECT_MANAGER_NOT_ASSIGNED من مسار التقييم الذاتي
-- ═══════════════════════════════════════════════════════════════════════════
-- المشكلة: قيد DIRECT_MANAGER_NOT_ASSIGNED يمنع الموظف من تقديم تقييمه
-- الذاتي عندما لا يوجد علاقة مدير مباشر نشطة. هذا القيد غير منطقي لمسار
-- التقييم الذاتي لأن الموظف لا يحتاج مديراً ليُقدّم تقييمه — يحتاجه
-- فقط للمراجعة التالية.
-- الحل: إزالة القيد من كلا المسارين (V23 parallel و V17 sequential).

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
   -- 0457: إزالة DIRECT_MANAGER_NOT_ASSIGNED — الموظف لا يحتاج مديراً لتقييم نفسه
   if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id() or not public.has_permission('performance.kpi.self_assess') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
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
 -- V17 SEQUENTIAL PATH
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
   -- 0457: إزالة DIRECT_MANAGER_NOT_ASSIGNED — الموظف لا يحتاج مديراً لتقييم نفسه
   if v_eval.workflow_status='DRAFT' or v_eval.employee_id<>public.current_employee_id() or not public.has_permission('performance.kpi.self_assess') then raise exception 'FORBIDDEN' using errcode='42501'; end if;
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
   -- V17: advance to hr_review
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
   update public.kpi_evaluations set manager_final_comment=nullif(trim(p_note),''),updated_at=now() where id=v_eval.id;
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
 end if;

 return v_eval;
end $$;

comment on function public.advance_kpi_stage(uuid,text,jsonb,text) is
  '0457: إزالة DIRECT_MANAGER_NOT_ASSIGNED من مسار التقييم الذاتي — الموظف لا يحتاج مديراً لتقييم نفسه.';

revoke all on function public.advance_kpi_stage(uuid,text,jsonb,text) from public, anon;
grant execute on function public.advance_kpi_stage(uuid,text,jsonb,text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) RPC للتحقق من قوة كلمة المرور على الخادم
-- ═══════════════════════════════════════════════════════════════════════════
-- ي统一 التحقق بين الويب والموبايل ويمنع تصحيح القواعد المنفصلة.

create or replace function public.validate_password_strength(p_password text)
returns jsonb
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_issues text[] := '{}';
begin
  if p_password is null or length(p_password) < 12 then
    v_issues := array_append(v_issues, 'يجب أن تكون 12 حرفًا على الأقل');
  end if;
  if length(p_password) > 72 then
    v_issues := array_append(v_issues, 'يجب ألا تتجاوز 72 حرفًا');
  end if;
  if p_password !~ '[A-Z]' then
    v_issues := array_append(v_issues, 'حرف كبير واحد على الأقل (A-Z)');
  end if;
  if p_password !~ '[a-z]' then
    v_issues := array_append(v_issues, 'حرف صغير واحد على الأقل (a-z)');
  end if;
  if p_password !~ '[0-9]' then
    v_issues := array_append(v_issues, 'رقم واحد على الأقل (0-9)');
  end if;
  if p_password !~ '[!@#$%^&*()_\-+=[\]{};''":\\|,.<>/?`~]' then
    v_issues := array_append(v_issues, 'رمز خاص واحد على الأقل (!@#$...)');
  end if;
  if p_password ~ '(.)\1{4,}' then
    v_issues := array_append(v_issues, 'تكرار مفرط لنفس الحرف (5+ متتالية)');
  end if;

  return jsonb_build_object(
    'valid', cardinality(v_issues) = 0,
    'issues', to_jsonb(v_issues)
  );
end $$;

comment on function public.validate_password_strength(text) is
  '0457: تحقق من قوة كلمة المرور على الخادم — م统一 للويب والموبايل.';

revoke all on function public.validate_password_strength(text) from public, anon;
grant execute on function public.validate_password_strength(text) to authenticated;

commit;

notify pgrst, 'reload schema';
