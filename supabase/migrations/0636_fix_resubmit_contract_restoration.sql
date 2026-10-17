-- ============================================================================
-- 0636: استعادة عقد إعادة الرفع (0452) — action='submit' + إشعار المدير
--       + canResubmit في تفاصيل الموبايل
-- ============================================================================
-- المشكلة: تعديل 0503 لدالة resubmit_my_request أعاد كتابتها بثلاثة انحرافات
--   عن عقد 0452 (ولم يُختبر قط لأن القيد نفسه كان يمنع الإجراء أصلاً):
--   1) سجّل action='resubmit' بلا from_status (0452 يexpects action='submit'
--      من rejected إلى pending) → مخالفة قيد request_actions_action_check
--      (القيمة خارج قائمة 0161) → إعادة الرفع تفشل دائماً بـ 23514.
--   2) لم يُشعر المدير المباشر بإعادة الرفع (0452 اختبار 9:
--      metadata.resubmitted=true).
--   3) get_mobile_request_detail لا ترجع canResubmit (0452 اختباري 13/14).
-- السلامة: الاستبدال كلي بنسخة مطابقة لـ 0503 مع الإصلاحات الثلاث؛
--          التوقيع والصلاحيات (SECURITY DEFINER / STABLE) تبقى كما هي.

-- ─── 1) resubmit_my_request — التوقيع السابق بعقد 0452 ──────────────────────

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
  v_req         public.requests;
  v_def         public.workflow_definitions;
  v_manager     uuid;
  v_due         timestamptz;
  v_esc         timestamptz;
  v_payload     jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today       date := (now() at time zone 'Africa/Cairo')::date;
  v_from_status text;
begin
  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_req.employee_id <> public.current_employee_id() then
    raise exception 'ONLY_REQUEST_OWNER_CAN_RESUBMIT' using errcode = '42501';
  end if;

  if v_req.status not in ('rejected','returned') then
    raise exception 'ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT' using errcode = '22023';
  end if;

  if v_req.request_type not in
     ('leave','mission','convoy','fundraising','late_permit','early_permit') then
    raise exception 'TYPE_NOT_RESUBMITTABLE' using errcode = '22023';
  end if;

  if p_title is null or length(trim(p_title)) < 3 or length(trim(p_title)) > 300 then
    raise exception 'INVALID_TITLE_LENGTH' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'INVALID_REASON_LENGTH' using errcode = '22023';
  end if;

  -- 0636: تثبيت الحالة السابقة قبل التحديث لتوثيق انتقال submit في سجل الإجراءات
  v_from_status := v_req.status;

  if v_req.request_type = 'mission' then
    v_payload := v_payload || jsonb_build_object(
      'startDate', coalesce(nullif(v_payload->>'startDate', '')::date, v_today),
      'endDate', coalesce(nullif(v_payload->>'endDate', '')::date, v_today),
      'days', 1,
      'startTime', coalesce(nullif(trim(coalesce(v_payload->>'startTime','')),''), to_char(now() at time zone 'Africa/Cairo', 'HH24:MI')),
      'startedAtCreation', true
    );
  end if;

  v_manager := public.resolve_request_approver(v_req.employee_id);

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

  update public.requests set
    title                = trim(p_title),
    reason               = trim(p_reason),
    payload              = v_payload,
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
           when ws.approver_type in ('direct_manager','department_manager') then v_req.manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1 then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    update public.workflow_instances set
      status = 'running', current_step_order = 1, completed_at = null, updated_at = now()
    where request_id = v_req.id;
  end if;

  -- 0636: عقد 0452 — action='submit' مع from_status=الحالة السابقة → pending
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    v_req.id, public.current_employee_id(), 'submit', v_from_status, 'pending', p_reason, auth.uid()
  );

  -- 0636: إشعار المدير المباشر بإعادة الرفع (metadata.resubmitted=true)
  if v_manager is not null and v_manager <> v_req.employee_id then
    perform public.notify_employee(
      v_manager,
      'إعادة رفع طلب: ' || coalesce(v_req.title, ''),
      coalesce(v_req.title, '') || E'\n' || coalesce(p_reason, ''),
      'request',
      'normal',
      'request',
      v_req.id,
      jsonb_build_object(
        'resubmitted', true,
        'request_type', v_req.request_type,
        'deepLink', '/requests/' || v_req.id
      )
    );
  end if;

  return to_jsonb(v_req);
end;
$$;

comment on function public.resubmit_my_request(uuid, text, text, jsonb) is
  '0636: إعادة رفع طلب مرفوض/معاد — عقد 0452 (submit من الحالة السابقة + إشعار المدير).';
revoke all on function public.resubmit_my_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.resubmit_my_request(uuid, text, text, jsonb) to authenticated;

-- ─── 2) get_mobile_request_detail — إضافة canResubmit ──────────────────────

create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
declare
  v_request public.requests;
  v_employee public.employees;
  v_steps jsonb;
  v_attachments jsonb;
  v_can_decide boolean;
  v_can_cancel boolean;
  v_can_resubmit boolean;
  v_is_direct_mgr boolean;
  v_decision_actor text;
  v_decision_mode text;
  v_decision_on_behalf boolean;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  v_is_direct_mgr := exists (
    select 1 from public.manager_relations mr
    where mr.employee_id = v_request.employee_id
      and mr.manager_employee_id = public.current_employee_id()
      and mr.relation_type = 'primary'
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
  );

  if not (
    v_request.employee_id = public.current_employee_id()
    or v_is_direct_mgr
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  v_can_cancel := v_request.status = 'pending' and v_request.employee_id = public.current_employee_id();

  -- 0636: عرض زر إعادة الرفع للمالك فقط وعلى طلب مرفوض/معاد
  v_can_resubmit := v_request.status in ('rejected','returned')
    and v_request.employee_id = public.current_employee_id();

  v_can_decide := v_request.status = 'pending' and (
    public.current_is_full_access()
    or v_is_direct_mgr
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.approve')
    or public.has_permission('requests.request.approve')
    or public.has_permission('requests.approve')
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', s.id, 'order', s.step_order, 'name', s.name_ar, 'status', s.status,
    'decision', case when s.status in ('approved','rejected') then s.status else null end,
    'comment', s.comment, 'decidedAt', s.acted_at, 'dueAt', s.due_at,
    'actorName', actor.full_name_ar
  ) order by s.step_order), '[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id = s.acted_by
  where s.request_id = p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
  ) order by a.created_at), '[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type = 'request' and a.entity_id = p_request_id;

  select e.full_name_ar, a.metadata->>'decisionMode', coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
  into v_decision_actor, v_decision_mode, v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id = a.actor_employee_id
  where a.request_id = p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  if v_request.request_type in ('mission','convoy','fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
      from public.mission_executions me
      where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'employeePhotoUrl', v_employee.photo_url,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'canDecide', v_can_decide,
    'canCancel', v_can_cancel,
    'canResubmit', v_can_resubmit,
    'steps', v_steps,
    'attachments', v_attachments,
    -- 0636: decisionContext كان جزءاً من العقد (0045 اختباري 16/17) وتقرأه
    -- واجهة الموبايل (mobile_models.dart substituteName/conflicts) — حذفته صياغة
    -- 0628؛ نعيده عبر الدالة المساعدة المنشورة get_request_decision_context.
    'decisionContext', public.get_request_decision_context(p_request_id),
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;

comment on function public.get_mobile_request_detail(uuid) is
  '0636: تفاصيل طلب الموبايل + canResubmit (المالك على طلب مرفوض/معاد) — عقد 0452.';
