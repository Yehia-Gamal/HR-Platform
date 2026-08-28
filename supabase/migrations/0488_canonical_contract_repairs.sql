-- =====================================================================
-- 0488: إصلاح العقود المعطلة بعد إعادة البناء الكنوني (0483)
-- ---------------------------------------------------------------------
-- 1) update_system_settings: إرجاع صيغة flat-object {key: value} كما في 0343
--    (الويب يرسل Record<string, unknown>؛ rebuild توقع array {key, value} وكسر العقد)
-- 2) _submit_request_for: إضافة فرع العزل (is_employee_isolated → medical_leave_v1) + نص عربي نظيف
-- 3) trg_request_step_activated_notify: إلغاء إشعار step-active عند التفعيل عبر تصعيد SLA
--    (يتجنب التنبيه المزدوج: خطوة نشطة + تصعيد، ليبقى إشعار واحد فقط للمدير)
-- =====================================================================

begin;

-- ─── 1) update_system_settings: flat-object canonical ─────────────────────
create or replace function public.update_system_settings(
  p_updates jsonb
)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_key text;
  v_val jsonb;
  v_updated integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('settings.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'object' then
    raise exception 'التحديثات يجب أن تكون كائن JSON' using errcode='22023';
  end if;

  for v_key, v_val in
    select * from jsonb_each(p_updates)
  loop
    update public.system_settings
       set value = v_val,
           updated_at = now()
     where key = v_key
       and is_editable = true
       and is_secret = false;
    if found then v_updated := v_updated + 1; end if;
  end loop;

  if v_updated > 0 then
    perform public.log_audit_event(
      'settings.updated', 'system', 'info',
      'system_settings', null, 'تحديث إعدادات النظام', null,
      jsonb_build_object('updatedKeys', v_updated));
  end if;

  return v_updated;
end $$;

-- ─── 2) _submit_request_for: مع فرع العزل الطبي + عربي نظيف ───────────────
create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_exec_emp       uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    -- 0474: موظف قسم معزول (الإدارة الطبية) يستخدم تعريفه أحادي الخطوة
    if public.is_employee_isolated(p_employee_id) then
      select * into v_def from public.workflow_definitions
        where code = 'medical_leave_v1' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;
    if v_def.id is null then
      select * into v_def from public.workflow_definitions
        where request_type = p_request_type and is_default = true and is_active = true
        order by version desc limit 1;
    end if;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء خطوات سير العمل
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- إشعار المدير المباشر (أول خطوة نشطة)
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'workflowStatus', 'submitted',
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  -- إشعار المدير التنفيذي (عند إنشاء أي طلب جديد)
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'طلب جديد — للمتابعة',
      v_label,
      'request',
      'request', v_row.id,
      '/requests/' || v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', false
      )
    );
  end if;

  return v_row;
end $$;

-- ─── 3) trg_request_step_activated_notify: لا تنبيه step-active عند تصعيد SLA ───
create or replace function public.trg_request_step_activated_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req public.requests;
begin
  if new.status <> 'active' or old.status = 'active' or new.assignee_employee_id is null then
    return new;
  end if;

  -- 0465/0488: إذا كانت خطوة سابقة في حالة escalated، فهذا تفعيل إثر تصعيد آلي
  -- نتخطى الإشعار العام (step-active) لأن إشعار التصعيد (escalation) يكفي.
  if exists (
    select 1 from public.request_steps s
    where s.request_id = new.request_id
      and s.step_order < new.step_order
      and s.status = 'escalated'
  ) then
    return new;
  end if;

  select * into v_req from public.requests where id = new.request_id;
  if v_req.id is null or new.assignee_employee_id = v_req.employee_id then
    return new;
  end if;

  if not exists (
    select 1 from public.notifications n
    where n.recipient_employee_id = new.assignee_employee_id
      and n.entity_type = 'request'
      and n.entity_id = new.request_id
      and n.metadata->>'eventKey' = 'step-active:' || new.id::text
  ) then
    perform public.notify_employee(
      new.assignee_employee_id,
      'طلب بانتظار مراجعتك',
      format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object(
        'kind', 'request_approval_needed',
        'eventKey', 'step-active:' || new.id::text,
        'requestType', v_req.request_type,
        'stepOrder', new.step_order
      )
    );
  end if;

  return new;
end $$;

commit;