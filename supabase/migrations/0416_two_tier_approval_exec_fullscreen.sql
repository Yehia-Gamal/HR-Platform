-- 0416: مسار موافقات من مستويين + إشعارات كاملة الشاشة للمدير التنفيذي
-- ══════════════════════════════════════════════════════════════════════
-- المطلوب:
--   (1) كل طلب (إجازة/مأمورية/انتداب/تصحيح حضور/...) يبدأ عند المدير
--       المباشر، وبعد عدّاد ساعتين من الإنشاء يتصعد تلقائيًا إلى
--       مدير التشغيل 1 (أبو عمار — دور operations-manager-1).
--   (2) لا دور لـ HR في القبول/الرفض — فقط المدير المباشر ثم أبو عمار.
--   (3) لو تجاوز أبو عمار مهلة الخطوة → يبقى الطلب عنده مع تذكير دوري
--       (هو القرار النهائي — لا خطوة أبعد).
--   (4) المدير التنفيذي (executive-director) يناله إنباه كامل الشاشة
--       (priority=urgent → fullScreenIntent → صوت عالٍ + اهتزاز طويل)
--       على كل: طلب جديد، قرار (موافقة/رفض/إعادة)، تصعيد، وكل
--       دخول/انصراف لأي موظف.
--
-- يبني على 0396 (process_request_sla + _submit_request_for) و0403
-- (decide_request) و0366 (تعرّيفات workflow) — كلها أُعيدت كتابتُها هنا.
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ═════════════════════════════════════════════════════════════════════
-- 1) دالة مساعدة: إشعار عاجل كامل الشاشة للمدير التنفيذي
-- ═════════════════════════════════════════════════════════════════════
create or replace function public.notify_executive_fullscreen(
  p_title        text,
  p_body         text default null,
  p_category     text default 'general',
  p_entity_type  text default null,
  p_entity_id    uuid default null,
  p_deep_link    text default null,
  p_extra        jsonb default '{}'::jsonb,
  p_nudge        boolean default true
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_exec uuid;
  v_meta jsonb;
begin
  v_exec := public.first_active_employee_for_role('executive-director');
  if v_exec is null then
    return;
  end if;
  v_meta := jsonb_build_object(
    'executive', true,
    'fullScreen', true,
    'channel',   'urgent_exec',
    'sound',     'urgent',
    'deepLink',  coalesce(p_deep_link, '')
  ) || coalesce(p_extra, '{}'::jsonb);

  perform public.notify_employee(
    v_exec,
    p_title,
    coalesce(p_body, ''),
    coalesce(p_category, 'general'),
    'urgent',
    p_entity_type,
    p_entity_id,
    v_meta
  );

  if p_nudge then
    perform public.nudge_notification_dispatcher();
  end if;
end;
$$;
comment on function public.notify_executive_fullscreen(text, text, text, text, uuid, text, jsonb, boolean) is
  '0406: إشعار عاجل كامل الشاشة للمدير التنفيذي (executive-director) مع اهتزاز.';
revoke all on function public.notify_executive_fullscreen(text, text, text, text, uuid, text, jsonb, boolean)
  from public, anon;
grant execute on function public.notify_executive_fullscreen(text, text, text, text, uuid, text, jsonb, boolean)
  to service_role, authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 2) _submit_request_for — إشعار المدير المباشر + المدير التنفيذي
--    (كامل الشاشة)؛ بدون أي إشعار HR. عدّاد ساعتين يبدأ في الخطوة 1.
-- ═════════════════════════════════════════════════════════════════════
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

  -- إشعار المدير التنفيذي — إنباه كامل الشاشة على كل طلب جديد
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'طلب جديد — للمراجعة',
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
end;
$$;
comment on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) is
  '0406: إنشاء طلب مع إشعار المدير المباشر + المدير التنفيذي (كامل الشاشة)، بدون HR.';
revoke execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb)
  from public, anon;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb)
  to service_role;

-- ═════════════════════════════════════════════════════════════════════
-- 3) decide_request — السلطة: المدير المباشر (أي وقت) + full_access +
--    أبو عمار (operations-manager-1) من الخطوة 2 فما فوق. بدون HR.
--    إشعار المدير التنفيذي (كامل الشاشة) عند كل قرار.
-- ═════════════════════════════════════════════════════════════════════
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
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_exec_emp        uuid;
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

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ
  -- أول escalated/pending (إصلاح 0403).
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);
  v_is_direct_mgr := (v_req.manager_employee_id = v_me);
  -- أبو عمار = مدير التشغيل 1 فقط (لا ضابط عمليات، لا HR)
  v_is_operations := public.current_has_active_role(array['operations-manager-1']);

  -- ── الصلاحية ──
  -- المدير المباشر + full_access: دائماً (أي مرحلة)
  -- أبو عمار (operations-manager-1): من الخطوة 2 فما فوق
  if not found then
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

  -- إشعار المدير التنفيذي (كامل الشاشة) عند كل قرار
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_me then
    perform public.notify_executive_fullscreen(
      'قرار طلب — ' || case v_req.status
        when 'approved' then 'موافقة'
        when 'rejected' then 'رفض'
        else 'إعادة طلب' end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'decision', p_decision,
        'request_type', v_req.request_type,
        'actorRole', v_actor_role
      )
    );
  end if;

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  '0406: قرار — مدير مباشر(أي وقت) / أبو عمار operations-manager-1 (step>=2) / full_access. بدون HR. موافقة واحدة تُنهي الطلب.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ═════════════════════════════════════════════════════════════════════
-- 4) process_request_sla — تصعيد من مستويين:
--    المدير (2س) → أبو عمار (operations-manager-1). بدون HR.
--    الخطوة الأخيرة (أبو عمار) عند تجاوز المهلة → تذكير دوري له.
-- ═════════════════════════════════════════════════════════════════════
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
  v_target   uuid;
  v_role     text;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');

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
    -- ── الخطوة النهائية (أبو عمار، أو أي مرحلة >= 2): لا تصعيد أبعد ──
    --    فقط تذكير دوري لأبو عمار وإعادة ضبط المهلة (24 ساعة).
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        -- أعد توجيه الخطوة إلى أبو عمار إن لم تكن له (طلبات قديمة 3-tier)
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
          where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبَتّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن (المدير).
المدير المباشر لم يبتّ والطلب محوّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
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

    -- ── الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (أبو عمار) ──
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
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      -- فعّل الخطوة التالية (أبو عمار)
      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '4 hours',
            escalation_deadline = now() + interval '4 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        'تصعيد تلقائي — تجاوز مهلة المدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      -- إشعار أبو عمار (الخطوة 2)
      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوّل إليك — مدير التشغيل 1',
          coalesce(v_row.title, '') || ' — يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', v_role,
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير التنفيذي (كامل الشاشة) عند كل تصعيد
      perform public.notify_executive_fullscreen(
        'تصعيد طلب — للمتابعة',
        coalesce(v_row.title, ''),
        'request',
        'request', v_row.request_id,
        '/requests/' || v_row.request_id,
        jsonb_build_object(
          'escalation', 'executive_notify',
          'tier', v_next.step_order
        )
      );
    else
      -- لا توجد خطوة تالية (طلب قديم بلا بنية): تصعيد عام
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
  '0406: تصعيد من مستويين — مدير(2س)→أبو عمار(operations-manager-1). بدون HR؛ الخطوة الأخيرة لها تذكير دوري.';
revoke all on function public.process_request_sla(integer) from public, authenticated;
grant execute on function public.process_request_sla(integer) to service_role;

-- ═════════════════════════════════════════════════════════════════════
-- 5) تحديث تعرّيفات سير العمل: الخطوة 2 → operations-manager-1 (أبو عمار)،
--    وتعطيل الخطوة 3 (HR) حتى تُصاغ الطلبات الجديدة بمستويين.
-- ═════════════════════════════════════════════════════════════════════
do $$
declare
  v_step record;
  v_def  record;
begin
  -- أي خطوة تحمل دور ضابط العمليات في التصعيد → تُصبح مدير التشغيل 1.
  for v_step in
    select id, definition_id from public.workflow_steps
    where approver_role_slug = 'operations-officer'
      and is_active = true
  loop
    update public.workflow_steps
      set name_ar = 'مدير التشغيل 1',
          approver_role_slug = 'operations-manager-1',
          updated_at = now()
      where id = v_step.id;
  end loop;

  -- أي خطوة HR في سلسلة الاعتماد تُعطَّل (لا دخل لـ HR بالقبول/الرفض).
  update public.workflow_steps
    set is_active = false, updated_at = now()
  where approver_role_slug in ('hr-manager','hr-specialist')
    and step_type = 'approval';

  -- تحديث config التعرّيفات: tierHours مدير/أوبريشن فقط، وبدون hr في الفاعلين.
  for v_def in
    select id from public.workflow_definitions where is_active = true
  loop
    update public.workflow_definitions
      set config = jsonb_build_object(
            'tierHours', jsonb_build_object('manager', 2, 'operations', 4),
            'concurrentActors', jsonb_build_array('direct_manager','operations','executive')
          ),
          name_ar = regexp_replace(name_ar, 'ثم HR', ''),
          description = 'سير من مستويين: مدير مباشر (مهلة ساعتان) → مدير التشغيل 1 (أبو عمار). لا دخل لـ HR.',
          updated_at = now()
      where id = v_def.id;
  end loop;
end $$;

-- ═════════════════════════════════════════════════════════════════════
-- 6) منح صلاحيات الموافقات لـ operations-manager-1 (أبو عمار)
--    (نفس منح 0404 لضابط العمليات — نطاق organization).
-- ═════════════════════════════════════════════════════════════════════
do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
  v_code text;
  v_codes text[];
begin
  v_codes := array[
    'requests.approve','requests.read',
    'requests.request.approve','requests.request.read'
  ];
  select id into v_role_id from public.roles where slug = 'operations-manager-1';
  if v_role_id is not null then
    foreach v_code in array v_codes loop
      select id into v_perm_id from public.permissions where code = v_code;
      if v_perm_id is not null then
        insert into public.role_permissions (role_id, permission_id, scope)
        values (v_role_id, v_perm_id, 'organization')
        on conflict (role_id, permission_id, scope) do nothing;
      end if;
    end loop;
  end if;
end $$;

-- ═════════════════════════════════════════════════════════════════════
-- 7) توسيع تريجر الحضور: إشعار المدير التنفيذي (كامل الشاشة) عند كل
--    دخول/انصراف، إضافةً لإشعار المدير المباشر الحالي.
-- ═════════════════════════════════════════════════════════════════════
create or replace function public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'HH24:MI'
  );

  -- إشعار المدير المباشر (يبقى كما هو — أولوية منخفضة)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
    perform public.notify_employee(
      v_manager,
      case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
           else 'انصراف موظف — تسجيل خروج' end,
      format(
        '%s — %s (%s)',
        coalesce(v_emp_ar, 'موظف'),
        case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
        v_time
      ),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- إشعار المدير التنفيذي (كامل الشاشة) عند كل دخول/انصراف
  perform public.notify_executive_fullscreen(
    case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
         else 'انصراف موظف — تسجيل خروج' end,
    format(
      '%s — %s (%s)',
      coalesce(v_emp_ar, 'موظف'),
      case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
      v_time
    ),
    'attendance',
    'attendance_daily', new.id,
    null,
    jsonb_build_object(
      'event', v_event,
      'employeeId', new.employee_id,
      'workDate', new.work_date,
      'time', v_time
    ),
    false  -- لا nudge على كثافة أحداث الحضور؛ يعتمد على جدولة الـ dispatcher
  );

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  'يُشعر المدير المباشر (low) والمدير التنفيذي (كامل الشاشة) بدخول/انصراف أي موظف.';

drop trigger if exists trg_attendance_daily_notify_manager on public.attendance_daily;
create trigger trg_attendance_daily_notify_manager
  after insert or update of first_check_in, last_check_out on public.attendance_daily
  for each row execute function public.tg_attendance_daily_notify_manager();

notify pgrst, 'reload schema';

commit;
