-- 0396: V25.3 — مسار الموافقات المرحلي بثلاث طبقات (إصلاح نهائي)
-- ══════════════════════════════════════════════════════════════════════
-- المشكلات التي يعالجها:
--   (1) process_request_sla في 0384 استُبدل بنسخة مبسّطة لا تُجري التصعيد الثلاثي.
--   (2) decide_request (0366) يتيح لـ HR الموافقة في أي مرحلة (يجب تقييده للخطوة 3 فقط).
--   (3) _submit_request_for لا يُشعر المدير التنفيذي ولا HR عند إرسال الطلب.
--
-- القواعد الجديدة:
--   • صلاحية decide_request مرحلية:
--       الخطوة 1 (0–2س): المدير المباشر + full_access فقط
--       الخطوة 2 (2–6س): المدير + الأوبريشن + full_access
--       الخطوة 3 (6س+): المدير + الأوبريشن + HR + full_access
--   • عند إرسال أي طلب: إشعار فوري للمدير + للعلم للمدير التنفيذي + HR.
--   • process_request_sla: تصعيد ثلاثي فعلي مع إشعارات صوتية لكل مرتبة.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1. _submit_request_for — إشعار المدير التنفيذي + HR عند الإرسال
-- ─────────────────────────────────────────────────────────────────────
create or replace function public._submit_request_for(
  p_employee_id           uuid,
  p_request_type          text,
  p_workflow_definition_id uuid default null,
  p_manager_employee_id   uuid default null,
  p_title                 text default null,
  p_reason                text default null,
  p_payload               jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_exec_emp       uuid;
  v_hr_emp         uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- التعريف الافتراضي لسير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
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

  -- إنشاء خطوات الجارية
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

  -- إشعار المدير التنفيذي — للعلم فقط، لا إجراء مطلوب
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_employee(
      v_exec_emp,
      'طلب جديد — للعلم',
      v_label,
      'request', 'normal', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', true,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  -- إشعار HR — للعلم فقط؛ يُطلب منه التدخل بعد 6 ساعات إن لم يُعتمد
  v_hr_emp := public.first_active_employee_for_role('hr-manager');
  if v_hr_emp is not null
     and v_hr_emp <> v_row.employee_id
     and v_hr_emp is distinct from v_first_approver
     and v_hr_emp is distinct from v_exec_emp then
    perform public.notify_employee(
      v_hr_emp,
      'طلب جديد — للعلم',
      v_label || ' (تُوجَّه إليك إن لم يُعتمد خلال 6 ساعات)',
      'request', 'normal', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', true,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;
comment on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) is
  '0396: إنشاء طلب مع إشعار المدير المباشر + المدير التنفيذي + HR للعلم عند الإرسال.';
revoke execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb)
  from public, anon;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb)
  to service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2. decide_request — صلاحية مرحلية (مدير دائماً / أوبريشن step≥2 / HR step≥3)
--    موافقة واحدة تُنهي الطلب بالكامل (لا مرحلتين)
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision   text,
  p_comment    text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return'
     and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;
  if v_req.employee_id = v_me then
    raise exception 'self-approval is not allowed' using errcode = '42501';
  end if;

  -- الخطوة النشطة الحالية (active أو escalated أو أول pending)
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);
  v_is_direct_mgr := (v_req.manager_employee_id = v_me);
  v_is_operations := public.current_has_active_role(
    array['operations-officer','operations-manager','operations-manager-1','operations-manager-2']);
  v_is_hr := public.current_has_active_role(array['hr-manager','hr-specialist']);

  -- ── الصلاحية المرحلية ──
  -- المدير المباشر + full_access: دائماً (أي مرحلة)
  -- الأوبريشن: من الخطوة 2 فما فوق
  -- HR: الخطوة 3 فقط (بعد تجاوز مهلة الأوبريشن)
  if not found then
    -- مسار احتياطي: طلبات بلا خطوات workflow
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or public.can_access_employee(v_req.employee_id, 'requests.approve');
  else
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or (v_is_operations
          and v_current_step >= 2
          and public.can_access_employee(v_req.employee_id, 'requests.approve'))
      or (v_is_hr
          and v_current_step >= 3
          and public.can_access_employee(v_req.employee_id, 'requests.approve'));
  end if;

  if not v_authorized then
    raise exception 'not authorized for the active workflow step (step: %, role required)'
      , v_current_step using errcode = '42501';
  end if;

  -- تحديد دور الفاعل للسجل
  v_actor_role := case
    when public.current_is_full_access() and not v_is_direct_mgr then 'admin'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_operations then 'operations'
    when v_is_hr         then 'hr'
    else 'authorized'
  end;

  v_final_status := case p_decision
    when 'approve' then 'approved'
    when 'return'  then 'returned'
    else 'rejected'
  end;

  -- تسجيل إجراء الخطوة الحالية
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  -- إغلاق باقي الخطوات (موافقة واحدة تُنهي الطلب — لا مرحلتين)
  update public.request_steps
    set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and status in ('pending','active','escalated')
    and id is distinct from v_step.id;

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  update public.requests
    set status = v_final_status,
        workflow_status = 'completed',
        decided_at = now(), decided_by = v_me, updated_at = now()
  where id = p_request_id
  returning * into v_req;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    'pending', v_final_status, p_comment, auth.uid()
  );

  -- إشعار الموظف بالنتيجة
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'تمت الموافقة على طلبك'
      when 'rejected' then 'تم رفض طلبك'
      else 'تم إعادة طلبك لتعديله'
    end,
    coalesce(v_req.title, '') ||
      case when p_comment is not null then E'\n' || p_comment else '' end,
    'request',
    case when v_req.status = 'approved' then 'normal' else 'high' end,
    'request', v_req.id,
    jsonb_build_object(
      'decision', p_decision,
      'request_type', v_req.request_type,
      'actorRole', v_actor_role,
      'deepLink', '/requests/' || v_req.id
    )
  );

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  '0396: قرار مرحلي — مدير(أي وقت) / أوبريشن(step≥2) / HR(step≥3) / full_access(أي وقت). موافقة واحدة تُنهي الطلب.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. process_request_sla — تصعيد ثلاثي فعلي مُصحَّح
--    المدير (2س) → الأوبريشن (4س إضافية) → HR (48س إضافية)
--    مع إشعار لكل مرتبة + إشعار للمدير التنفيذي عند التصعيد
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.process_request_sla(
  p_limit integer default 200
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count    integer := 0;
  v_row      record;
  v_next     record;
  v_ops_emp  uuid;
  v_hr_emp   uuid;
  v_exec_emp uuid;
  v_target   uuid;
  v_role     text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp  := public.first_active_employee_for_role('operations-officer');
  v_hr_emp   := public.first_active_employee_for_role('hr-manager');
  v_exec_emp := public.first_active_employee_for_role('executive-director');

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline
    limit greatest(1, least(p_limit, 2000))
    for update of rs skip locked
  loop
    -- ── الخطوة 3 (HR): لا تصعيد أبعد — فقط تذكير ──
    if v_row.step_order >= 3 then
      if v_hr_emp is not null then
        perform public.notify_employee(
          v_hr_emp,
          'تذكير: طلب لم يُبَتّ فيه بعد (HR)',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'hr_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;
      -- صفّر deadline لمنع تكرار التذكير الفوري (24 ساعة من الآن)
      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- ── ابحث عن الخطوة التالية ──
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    -- وسّم الخطوة الحالية كـ escalated
    update public.request_steps
      set status = 'escalated', escalated_at = now(), updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      -- تحديد المُصعَّد إليه حسب المرتبة
      if v_row.step_order = 1 then
        v_target := v_ops_emp;
        v_role   := 'operations-officer';
      else
        v_target := v_hr_emp;
        v_role   := 'hr-manager';
      end if;

      -- فعّل الخطوة التالية
      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + case
                               when v_row.step_order = 1 then interval '4 hours'
                               else interval '48 hours'
                             end,
            escalation_deadline = case
                                    when v_row.step_order = 1
                                    then now() + interval '4 hours'
                                    else null  -- HR: لا تصعيد أبعد
                                  end,
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = case
                                when v_row.step_order = 1 then 'awaiting_operator'
                                else 'escalated'
                              end,
            escalated_at = coalesce(escalated_at, now()),
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        case when v_row.step_order = 1
          then 'تصعيد تلقائي — تجاوز مهلة المدير المباشر (2 ساعة)'
          else 'تصعيد تلقائي — تجاوز مهلة الأوبريشن (4 ساعات)'
        end,
        jsonb_build_object('tier', v_row.step_order + 1, 'targetRole', v_role)
      );

      -- إشعار المُصعَّد إليه (أوبريشن أو HR)
      if v_target is not null then
        perform public.notify_employee(
          v_target,
          case when v_row.step_order = 1
            then 'طلب محوّل إليك — الأوبريشن'
            else 'طلب محوّل إليك — HR'
          end,
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير التنفيذي عند كل تصعيد
      if v_exec_emp is not null then
        perform public.notify_employee(
          v_exec_emp,
          'تصعيد طلب — للمتابعة',
          coalesce(v_row.title, ''),
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'executive_notify',
            'tier', v_row.step_order + 1,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;
    else
      -- لا توجد خطوة تالية (طلب قديم بلا بنية ثلاثية): تصعيد عام
      update public.requests
        set workflow_status = 'escalated',
            escalated_at = coalesce(escalated_at, now()),
            updated_at = now()
      where id = v_row.request_id;
    end if;

    v_count := v_count + 1;
  end loop;

  -- سجل صحة الـ cron
  insert into public.cron_health_log(job_name, rows_affected, status)
  values ('process_request_sla', v_count, 'ok');

  return v_count;

exception when others then
  insert into public.cron_health_log(job_name, rows_affected, status, detail)
  values ('process_request_sla', 0, 'error', sqlerrm);
  raise;
end;
$$;
comment on function public.process_request_sla(integer) is
  '0396: تصعيد ثلاثي — مدير(2س)→أوبريشن(4س)→HR(48س) مع إشعارات صوتية لكل مرتبة والمدير التنفيذي.';
revoke all on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

notify pgrst, 'reload schema';

commit;
