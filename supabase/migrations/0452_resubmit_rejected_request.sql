-- ============================================================================
-- 0452: إعادة رفع الطلبات المرفوضة (المأموريات وأسرتها) بعد تعديلها
-- ============================================================================
-- طلب المستخدم: عند رفض المأمورية وإعادتها للموظف يستطيع تعديل أي جزء
-- منها ورفعها مرة أخرى.
--
-- الحالة 'returned' موجودة أصلاً في قيد requests_status_check، والرفض
-- يضع status='rejected' + workflow_status='completed'. هذه الـmigration
-- تضيف المسار الناقص:
--
--   resubmit_my_request(p_request_id, p_title, p_reason, p_payload)
--     1) تحقق: المالك نفسه + الحالة rejected/returned + نوع قابل لإعادة
--        الرفع (leave/mission/convoy/fundraising/late_permit/early_permit).
--     2) تحديث العنوان والسبب وpayload وإعادة الحالة pending/submitted
--        وتصفير حقول القرار وإعادة حلّ المدير المباشر الحالي.
--     3) حذف خطوات السير القديمة وتوليدها من التعريف النشط (الأولى active
--        بمهلتها) وإلغاء نسخة السير القديمة وفتح نسخة جديدة.
--     4) توثيق request_actions بفعل 'submit' (from rejected → to pending).
--     5) إشعار المدير المباشر (high) والمدير التنفيذي (كامل الشاشة).
--
-- كما يُضاف canResubmit إلى get_mobile_request_detail ليُظهر التطبيق
-- زر «تعديل وإعادة رفع» للمالك حصراً.
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) دالة إعادة الرفع
-- ═══════════════════════════════════════════════════════════════════════════
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

  -- المدير المباشر الحالي (قد تغيّر منذ الرفض الأول)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = v_req.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;
  if v_manager = v_req.employee_id then
    v_manager := null;
  end if;

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
  '0452: إعادة رفع طلب مرفوض/مُرجَع بعد تعديله — للمالك حصراً؛ يعيد توليد خطوات السير ويشعر المدير والتنفيذي.';

revoke all on function public.resubmit_my_request(uuid, text, text, jsonb) from public, anon;
grant execute on function public.resubmit_my_request(uuid, text, text, jsonb) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) canResubmit في تفاصيل الطلب (لإظهار الزر للمالك حصراً)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to public, pg_temp
as $function$
declare
  v_request public.requests; v_employee public.employees;
  v_can_decide boolean:=false; v_can_cancel boolean:=false; v_can_resubmit boolean:=false;
  v_steps jsonb:='[]'::jsonb; v_attachments jsonb:='[]'::jsonb;
  v_decision_actor text; v_decision_mode text; v_decision_on_behalf boolean:=false;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id=p_request_id;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;
  if not(
    v_request.employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.can_access_employee(v_request.employee_id,'requests.request.read')
    or v_request.manager_employee_id=public.current_employee_id()
  ) then raise exception 'request access denied' using errcode='42501'; end if;

  select * into v_employee from public.employees where id=v_request.employee_id;
  v_can_cancel:=v_request.status='pending' and v_request.employee_id=public.current_employee_id();
  v_can_decide:=v_request.status='pending' and v_request.employee_id<>public.current_employee_id() and (
    public.current_is_full_access()
    or v_request.manager_employee_id=public.current_employee_id()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.has_permission('requests.request.approve')
  );
  -- 0452: زر التعديل وإعادة الرفع — المالك وحده وعلى الأنواع القابلة لإعادة الرفع
  v_can_resubmit:=v_request.status in ('rejected','returned')
    and v_request.employee_id=public.current_employee_id()
    and v_request.request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'order',s.step_order,'name',s.name_ar,'status',s.status,
    'decision',case when s.status in ('approved','rejected') then s.status else null end,
    'comment',s.comment,'decidedAt',s.acted_at,'dueAt',s.due_at,
    'actorName',actor.full_name_ar
  ) order by s.step_order),'[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id=s.acted_by
  where s.request_id=p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path',a.storage_path,'mimeType',a.mime,'sizeBytes',a.size_bytes
  ) order by a.created_at),'[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type='request' and a.entity_id=p_request_id;

  select e.full_name_ar,a.metadata->>'decisionMode',coalesce((a.metadata->>'onBehalfOfExecutive')::boolean,false)
  into v_decision_actor,v_decision_mode,v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id=a.actor_employee_id
  where a.request_id=p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  -- 0318: سجل تنفيذ المأمورية (إن وُجد) — 0442: يشمل الفاندي
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
    'id',v_request.id,'requestNumber',v_request.request_number,'requestType',v_request.request_type,
    'employeeId',v_request.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
    'title',v_request.title,'reason',v_request.reason,'status',v_request.status,
    'workflowStatus',v_request.workflow_status,'payload',coalesce(v_request.payload,'{}'::jsonb),
    'currentStepOrder',v_request.current_step_order,'decisionDueAt',v_request.decision_due_at,
    'createdAt',v_request.created_at,'updatedAt',v_request.updated_at,
    'canDecide',v_can_decide,'canCancel',v_can_cancel,'canResubmit',v_can_resubmit,'steps',v_steps,
    'attachments',v_attachments,'decisionContext',public.get_request_decision_context(p_request_id),
    'decisionActorName',v_decision_actor,'decisionMode',v_decision_mode,
    'decisionOnBehalfOfExecutive',v_decision_on_behalf,
    'missionExecution',v_execution
  );
end $function$;

comment on function public.get_mobile_request_detail(uuid) is
  '0452: تفاصيل الطلب للتطبيق + canResubmit للمالك على المرفوض/المُرجَع.';

commit;

notify pgrst, 'reload schema';
