-- ═══════════════════════════════════════════════════════════════
-- 0654: إصلاح تقديم الطلبات — كل طلب (إجازة، مأمورية، إذن…) يفشل منذ 0653
--
-- 0653 أعاد كتابة _submit_request_for لتخصيصات طاقم العيادات، لكن النسخة
-- الجديدة تكسر كل تقديم:
--   (1) update requests set current_step_id = … — العمود غير موجود (42703)
--       → يظهر للموظف «تعذر تحميل البيانات. تواصل مع مسؤول النظام».
--   (2) workflow_status = 'in_progress' — قيمة يرفضها requests_workflow_status_check
--       (كانت ستفشل بـ 23514 حتى لو صُحّح اسم العمود).
--   (3) حُذف سطر 'submit' من request_actions → الطلب بلا بداية في سجله.
--   (4) الإشعار صار للمدير المباشر دائماً بدل معتمد الخطوة النشطة الفعلي.
--   (5) is_clinic_team_member الجديدة مكشوفة لـ anon.
--
-- الإصلاح: استبدال كنوني — نسخة ما قبل 0653 (المُتحقق منها مع 0646) + تخصيصات
-- العيادات من 0653 كما هي (المدير المعتمد لطاقم العيادات، مسارات medical_%،
-- لا تصعيد تلقائي لهم، نوع shift_change). لا تحديث لـ requests بعد إنشاء الخطوات:
-- current_step_order افتراضيه 1 وworkflow_status يبقى 'submitted' كما كان.
-- ═══════════════════════════════════════════════════════════════

begin;

create or replace function public._submit_request_for(
  p_employee_id uuid,
  p_request_type text,
  p_workflow_definition_id uuid default null::uuid,
  p_manager_employee_id uuid default null::uuid,
  p_title text default null::text,
  p_reason text default null::text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- 0653: معتمد طلبات طاقم العيادات
  c_clinic_manager constant uuid := '4120ce3a-8999-453e-8d9d-acd8f3b5f04c';
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_label          text;
  v_is_clinic      boolean := false;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in (
    'leave','mission','convoy','fundraising',
    'late_permit','early_permit','attendance_correction',
    'attendance_permit','shift_change','generic'
  ) then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  v_is_clinic := public.is_clinic_team_member(p_employee_id) and p_employee_id <> c_clinic_manager;

  -- طاقم العيادات: المعتمد ثابت (0653). غيرهم: إذا كان المدير فارغاً أو هو
  -- نفس الموظف نحل معتمداً أعلى تلقائياً.
  if v_is_clinic then
    p_manager_employee_id := c_clinic_manager;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
      -- مسارات العيادات الطبية المحصورة (0653)
      select * into v_def from public.workflow_definitions
        where code like 'medical_%' and request_type = p_request_type and is_active = true
        order by version desc limit 1;
    end if;

    if v_def.id is null and public.is_employee_isolated(p_employee_id) then
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
    -- طاقم العيادات لا يخضع للتصعيد التلقائي (0653)
    if v_def.auto_escalate and not v_is_clinic then
      v_esc := v_due;
    end if;
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
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null and not v_is_clinic
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

  -- بداية سجل الطلب (حذفها 0653 فظهرت الطلبات بلا «تقديم» في السجل)
  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, coalesce(v_me, p_employee_id), 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s — %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- إشعار معتمد الخطوة النشطة الفعلي (وإلا المدير المعتمد)
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
        'requestId', v_row.id,
        'employeeId', v_row.employee_id,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;

-- دالة داخلية: تُستدعى من submit_my_request وما يماثلها فقط.
revoke all on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to service_role;

-- 0653 أنشأ is_clinic_team_member قابلة للتنفيذ من anon (فحص 0552 يرفض ذلك):
-- كل مستدعيها SECURITY DEFINER فتعمل بصلاحية المالك — لا حاجة لمنحها للعميل.
revoke all on function public.is_clinic_team_member(uuid) from public, anon, authenticated;
grant execute on function public.is_clinic_team_member(uuid) to service_role;

notify pgrst, 'reload schema';

commit;
