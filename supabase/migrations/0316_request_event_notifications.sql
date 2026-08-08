-- =====================================================================
-- 0316: توسيع تغطية إشعارات الطلبات (كل الأحداث بلا إشعار سابقاً)
-- ---------------------------------------------------------------------
-- أُعيد إنشاء هذا الملف بعد إعادة هيكلة سلسلة migrations 0288-0312 التي
-- استبدلت النسخة الأصلية (0299) بجسر no-op؛ التطبيق على الإنتاج قائم
-- (create or replace idempotent) والمستودع يستعيد العقد.
--
-- التدقيق وجد 20 حدثاً لا يولّد إشعاراً. هذا الملف يضيف إشعارات لكل منها
-- عبر إعادة تعريف الدوال (create or replace) مع الحفاظ على سلوكها:
--
--   1) submit_request             → إشعار أول معتمِد بوصول طلب جديد
--   2) decide_request (خطوة وسيطة) → إشعار المعتمِد التالي في السلسلة
--   3) cancel_request             → إشعار المعتمِدين بإلغاء الطلب
--   4) request_attendance_correction → إشعار المراجعين (correction.review)
--   5) decide_attendance_correction  → إشعار الموظف بنتيجة التصحيح
--   6) decide_overtime_record        → إشعار الموظف + سجل تدقيق
--   7) publish_roster_admin          → إشعار الموظفين بنشر الجدول
--   8) cancel_location_request_as_requester → إشعار الموظف المستهدف
--   9) decide_work_assignment        → إشعار المشاركين ومنشئ التكليف
--  10) decide_kpi_appeal            → إشعار الموظف بقرار اعتراضه
--  11) request_break_glass          → إشعار الموافِقين (break_glass.approve)
--  12) approve_break_glass          → إشعار الطالب بقبول الطلب
--  13) reject_break_glass           → إشعار الطالب برفض الطلب
--  14) decide_access_review_item    → إشعار المستخدم بقرار مراجعة صلاحيته
--  15) submit_privacy_request       → إشعار مسؤولي الخصوصية
--  16) decide_privacy_request       → إشعار الطالب بتغيّر الحالة
--  17) document_signature_requests  → trigger: إشعار الموقّع عند طلب توقيع
--  18) submit_my_service_request    → إشعار فريق الدعم (service.request.manage)
--  19) wellbeing_requests           → trigger: إشعار المسؤولين (wellbeing)
--  20) start_my_mission / end_my_mission → إشعار مدير الموظف
--  21) approve_offboarding_case     → إشعار موظف تسلّم المهام
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0) دوال مساعدة جديدة
-- ---------------------------------------------------------------------
-- 0a) إشعار مستخدم مباشر (user_id) — يحل employee_id من profiles.
create or replace function public.notify_user(
  p_user_id uuid,
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_emp uuid; v_id uuid;
begin
  if p_user_id is null then return null; end if;
  select employee_id into v_emp from public.profiles where id = p_user_id;
  insert into public.notifications(
    recipient_user_id, recipient_employee_id, title, body, category, priority,
    entity_type, entity_id, metadata, created_by)
  values(
    p_user_id, v_emp, p_title, p_body, p_category, p_priority,
    p_entity_type, p_entity_id, coalesce(p_metadata, '{}'::jsonb), auth.uid())
  returning id into v_id;
  return v_id;
end $$;
revoke execute on function public.notify_user(uuid,text,text,text,text,text,uuid,jsonb) from public;
grant execute on function public.notify_user(uuid,text,text,text,text,text,uuid,jsonb) to authenticated, service_role;

-- 0b) إشعار كل الموظفين النشطين الحائزين صلاحية (أو full-access)،
--     مع استثناء اختياري لموظف.
create or replace function public.notify_employees_with_permission(
  p_permission text,
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_entity_type text default null,
  p_entity_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_exclude_employee_id uuid default null
)
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user_id uuid; v_count integer := 0;
begin
  for v_user_id in
    select distinct p.id
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to is null or ur.effective_to > now())
    join public.roles r on r.id = ur.role_id
    where (
        r.is_full_access = true
        or exists (
          select 1 from public.role_permissions rp
          join public.permissions perm on perm.id = rp.permission_id
          where rp.role_id = r.id and perm.code = p_permission
        )
      )
      and not (
        p_exclude_employee_id is not null
        and exists (
          select 1 from public.profiles pp
          where pp.id = p.id and pp.employee_id = p_exclude_employee_id
        )
      )
  loop
    perform public.notify_user(
      v_user_id, p_title, p_body, p_category, p_priority,
      p_entity_type, p_entity_id, p_metadata);
    v_count := v_count + 1;
  end loop;
  return v_count;
end $$;
revoke execute on function public.notify_employees_with_permission(text,text,text,text,text,text,uuid,jsonb,uuid) from public;
grant execute on function public.notify_employees_with_permission(text,text,text,text,text,text,uuid,jsonb,uuid) to authenticated, service_role;

-- 0c) تسمية عربية لنوع الطلب الموحّد.
create or replace function public.request_type_label(p_type text)
returns text
language sql immutable strict
as $$
  select case p_type
    when 'leave' then 'إجازة'
    when 'mission' then 'مأمورية'
    when 'convoy' then 'قافلة'
    when 'late_permit' then 'إذن تأخير'
    when 'early_permit' then 'إذن انصراف مبكر'
    when 'attendance_correction' then 'تصحيح حضور'
    else coalesce(p_type, '')
  end;
$$;
revoke execute on function public.request_type_label(text) from public;
grant execute on function public.request_type_label(text) to authenticated, service_role;

-- ---------------------------------------------------------------------
-- 1) submit_request — إشعار أول معتمِد (الخطوة النشطة) بوصول طلب جديد
-- ---------------------------------------------------------------------
create or replace function public.submit_request(
  p_request_type          text,
  p_workflow_definition_id uuid    default null,
  p_manager_employee_id    uuid    default null,
  p_title                  text    default null,
  p_reason                 text    default null,
  p_payload                jsonb   default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me       uuid := public.current_employee_id();
  v_def      public.workflow_definitions;
  v_due      timestamptz;
  v_esc      timestamptz;
  v_row      public.requests;
  v_first_approver uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8: 6 أنواع طلبات رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = v_me then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- اختر التعريف الافتراضي إن لم يُمرَّر
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then
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
    p_request_type, v_me, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  -- إنشاء الخطوات الجارية من تعريف سير العمل (إن وُجد)
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id,
      ws.id,
      ws.step_order,
      ws.name_ar,
      ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
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

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  -- سجل إجراء submit
  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (
    v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid()
  );

  -- إشعار أول معتمِد بوصول طلب جديد (لم يكن هناك أي إشعار عند الإنشاء)
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order
  limit 1;

  if v_first_approver is not null and v_first_approver <> v_me then
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد بانتظار مراجعتك',
      format('%s — %s', public.request_type_label(v_row.request_type), coalesce(v_row.title, '')),
      'request', 'normal', 'request', v_row.id,
      jsonb_build_object('requestType', v_row.request_type, 'workflowStatus', 'submitted'));
  end if;

  return v_row;
end;
$$;
comment on function public.submit_request(text, uuid, uuid, text, text, jsonb) is
  'V17 §8: إنشاء طلب موحّد — 6 أنواع رسمية، مع سير عمل وخطوات وتسجيل إجراء وإشعار أول معتمِد.';
revoke execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) from public;
grant  execute on function public.submit_request(text, uuid, uuid, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 2) decide_request — إشعار المعتمِد التالي عند انتقال الطلب لخطوة جديدة
--    (القرار النهائي كان يُشعِر الموظف فقط؛ الوسيطة لم تُشعر المعتمِد التالي)
-- ---------------------------------------------------------------------
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.requests;
  v_step public.request_steps;
  v_next public.request_steps;
  v_step_def public.workflow_steps;
  v_authorized boolean := false;
  v_bypass_hr boolean := false;
  v_notif_title text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  if p_decision = 'return' and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req
  from public.requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;
  if v_req.employee_id = v_me then
    raise exception 'self-approval is not allowed' using errcode = '42501';
  end if;

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated')
  order by step_order
  limit 1
  for update;

  -- ── مسار احتياطي: طلبات بدون تعريف دورة عمل ──
  if not found then
    v_authorized :=
      public.current_is_full_access()
      or v_req.manager_employee_id = v_me
      or public.can_access_employee(v_req.employee_id, 'requests.approve');

    if not v_authorized then
      raise exception 'not authorized to decide this request' using errcode = '42501';
    end if;

    update public.requests
      set status = case p_decision
                     when 'approve' then 'approved'
                     when 'return'  then 'returned'
                     else 'rejected'
                   end,
          workflow_status = 'completed',
          decided_at = now(),
          decided_by = v_me,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;

    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_me, p_decision, 'pending', v_req.status, p_comment, auth.uid()
    );

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
      'request',
      v_req.id,
      jsonb_build_object('decision', p_decision, 'request_type', v_req.request_type)
    );

    return v_req;
  end if;

  if v_step.workflow_step_id is not null then
    select * into v_step_def
    from public.workflow_steps
    where id = v_step.workflow_step_id;
  end if;

  -- الصلاحية الأساسية
  v_authorized := public.current_is_full_access()
    or v_step.assignee_employee_id = v_me
    or (
      v_step.assignee_role_slug is not null
      and exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = auth.uid()
          and r.slug = v_step.assignee_role_slug
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
      and public.can_access_employee(
        v_req.employee_id,
        coalesce(v_step_def.approver_permission, 'requests.approve')
      )
    )
    or (
      v_step_def.approver_permission is not null
      and public.can_access_employee(v_req.employee_id, v_step_def.approver_permission)
    )
    or (
      v_req.manager_employee_id = v_me
      and v_step.step_order = 1
    );

  -- V25: تجاوز المدير بعد 12 ساعة — صلاحية HR للخطوة الأولى المنتهية
  if v_step.step_order = 1
     and v_step.due_at < now()
     and public.current_has_active_role(array['hr-manager', 'hr-specialist'])
     and public.can_access_employee(v_req.employee_id, 'requests.approve') then
    v_authorized := true;
    v_bypass_hr  := true;
  end if;

  if not v_authorized then
    raise exception 'not authorized for the active workflow step' using errcode = '42501';
  end if;

  -- تسجيل إجراء الخطوة الحالية
  update public.request_steps
  set status = case p_decision
                 when 'approve' then 'approved'
                 else 'rejected'
               end,
      acted_at = now(),
      acted_by = v_me,
      comment = case when v_bypass_hr then coalesce(p_comment, 'اعتماد تجاوزي — تجاوز مهلة المدير') else p_comment end,
      updated_at = now()
  where id = v_step.id;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    v_step.status,
    case p_decision
      when 'approve' then 'approved'
      when 'return'  then 'returned'
      else 'rejected'
    end,
    case when v_bypass_hr then coalesce(p_comment, 'اعتماد تجاوزي — تجاوز مهلة المدير') else p_comment end,
    auth.uid()
  );

  -- ── رفض أو إعادة → إنهاء كل الخطوات المعلقة وإغلاق الطلب ──
  if p_decision in ('reject', 'return') then
    update public.request_steps
      set status = 'skipped', updated_at = now()
    where request_id = p_request_id
      and status = 'pending';

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = case p_decision when 'return' then 'returned' else 'rejected' end,
          workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      case v_req.status
        when 'rejected' then 'تم رفض طلبك'
        else 'تم إعادة طلبك لتعديله'
      end,
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'high',
      'request',
      v_req.id,
      jsonb_build_object('decision', p_decision, 'request_type', v_req.request_type)
    );

    return v_req;
  end if;

  -- ── موافقة: الانتقال للخطوة التالية أو الإغلاق ──
  if not v_bypass_hr then
    select * into v_next
    from public.request_steps
    where request_id = p_request_id
      and status = 'pending'
      and step_order > v_step.step_order
    order by step_order
    limit 1
    for update;
  end if;

  if found and v_next.id is not null then
    update public.request_steps
      set status = 'active',
          due_at = now() + make_interval(hours => coalesce(v_next.sla_hours, 48)),
          updated_at = now()
    where id = v_next.id;

    update public.workflow_instances
      set current_step_order = v_next.step_order, updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set workflow_status = 'in_review',
          current_step_order = v_next.step_order,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;

    -- إشعار المعتمِد التالي في السلسلة (0316)
    if v_next.assignee_employee_id is not null and v_next.assignee_employee_id <> v_me then
      perform public.notify_employee(
        v_next.assignee_employee_id,
        'طلب بانتظار مراجعتك',
        format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
        'request', 'normal', 'request', p_request_id,
        jsonb_build_object('requestType', v_req.request_type, 'workflowStatus', 'in_review'));
    end if;
  else
    -- لا توجد خطوة تالية → إكمال الطلب
    if v_bypass_hr then
      -- تجاوز الخطوة الثانية: نسجّل إجراء تلقائي للخطوة الثانية
      select * into v_next
      from public.request_steps
      where request_id = p_request_id
        and status = 'pending'
        and step_order > v_step.step_order
      order by step_order
      limit 1
      for update;

      if found then
        update public.request_steps
          set status = 'approved',
              acted_at = now(),
              acted_by = v_me,
              comment = 'اعتماد تلقائي — تجاوز مهلة المدير',
              updated_at = now()
        where id = v_next.id;

        insert into public.request_actions(
          request_id, request_step_id, actor_employee_id, action,
          from_status, to_status, comment, created_by
        ) values (
          p_request_id, v_next.id, v_me, 'approve',
          'pending', 'approved',
          'اعتماد تلقائي — تجاوز مهلة المدير',
          auth.uid()
        );
      end if;
    end if;

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      'تمت الموافقة على طلبك',
      coalesce(v_req.title, '') ||
        case when p_comment is not null then E'\n' || p_comment else '' end,
      'request',
      'normal',
      'request',
      v_req.id,
      jsonb_build_object(
        'decision', 'approve',
        'request_type', v_req.request_type,
        'bypassHr', v_bypass_hr
      )
    );
  end if;

  return v_req;
end;
$$;
comment on function public.decide_request(uuid, text, text) is
  'V25: قرار على الطلب (approve/reject/return) مع سير عمل متعدد الخطوات + إشعار المعتمِد التالي + تجاوز HR.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3) cancel_request — إشعار المعتمِدين بإلغاء الطلب
-- ---------------------------------------------------------------------
create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason     text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.requests;
  v_from text;
  v_assignee uuid;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be cancelled (current: %)', v_req.status using errcode = '22023';
  end if;

  -- التخويل: صاحب الطلب، أو full-access، أو صلاحية approve
  if not (
    v_req.employee_id = v_me
    or public.current_is_full_access()
    or public.has_permission('requests.approve')
  ) then
    raise exception 'not authorized to cancel this request' using errcode = '42501';
  end if;

  v_from := v_req.status;

  update public.requests
     set status          = 'cancelled',
         workflow_status = 'terminated',
         cancelled_at    = now(),
         cancelled_by    = v_me,
         cancel_reason   = p_reason,
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  update public.request_steps
     set status   = 'skipped',
         acted_at = now(),
         acted_by = v_me,
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  update public.workflow_instances
     set status       = 'cancelled',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status = 'running';

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'cancel', v_from, 'cancelled', p_reason, auth.uid()
  );

  -- إشعار المعتمِدين على الخطوات (0316)
  for v_assignee in
    select distinct s.assignee_employee_id
    from public.request_steps s
    where s.request_id = p_request_id
      and s.assignee_employee_id is not null
      and s.assignee_employee_id <> v_me
  loop
    perform public.notify_employee(
      v_assignee,
      'أُلغيت طلب',
      format('%s — %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
      'request', 'normal', 'request', p_request_id,
      jsonb_build_object('requestType', v_req.request_type));
  end loop;

  return v_req;
end;
$$;
comment on function public.cancel_request(uuid, text) is
  'إلغاء طلب pending عبر RPC من صاحب الطلب أو المخوّل، مع إنهاء الخطوات والنسخة وتسجيل الإجراء وإشعار المعتمِدين.';
revoke execute on function public.cancel_request(uuid, text) from public;
grant  execute on function public.cancel_request(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4) request_attendance_correction — إشعار المراجعين بطلب تصحيح جديد
-- ---------------------------------------------------------------------
create or replace function public.request_attendance_correction(p_work_date date,p_type text,p_reason text,p_check_in timestamptz default null,p_check_out timestamptz default null,p_status text default null,p_attachment_path text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_daily uuid;
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 if p_work_date>current_date or length(trim(p_reason))<5 then raise exception 'INVALID_CORRECTION'; end if;
 select id into v_daily from public.attendance_daily where employee_id=v_emp and work_date=p_work_date;
 insert into public.attendance_corrections(employee_id,attendance_daily_id,work_date,correction_type,requested_check_in,requested_check_out,requested_status,reason,attachment_path,created_by)
 values(v_emp,v_daily,p_work_date,p_type,p_check_in,p_check_out,p_status,trim(p_reason),p_attachment_path,auth.uid()) returning id into v_id;
 perform public.notify_employees_with_permission(
   'attendance.correction.review',
   'طلب تصحيح حضور جديد',
   format('طلب تصحيح حضور بتاريخ %s (%s)', p_work_date, coalesce(p_type, '')),
   'attendance', 'normal', 'attendance_corrections', v_id,
   '{}'::jsonb, v_emp);
 return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 5) decide_attendance_correction — إشعار الموظف بنتيجة التصحيح
-- ---------------------------------------------------------------------
create or replace function public.decide_attendance_correction(p_id uuid,p_decision text,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.attendance_corrections; v_daily uuid;
begin
 select * into strict v_row from public.attendance_corrections where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.correction.review')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 if p_decision='rejected' and length(trim(coalesce(p_note,'')))<5 then raise exception 'REASON_REQUIRED'; end if;
 update public.attendance_corrections set status=p_decision,reviewed_by=public.current_employee_id(),reviewed_at=now(),review_note=p_note,updated_at=now() where id=p_id;
 if p_decision='approved' then
  insert into public.attendance_daily(employee_id,work_date,first_check_in,last_check_out,status,is_finalized,created_by)
  values(v_row.employee_id,v_row.work_date,v_row.requested_check_in,v_row.requested_check_out,coalesce(v_row.requested_status,'present'),false,auth.uid())
  on conflict(employee_id,work_date) do update set first_check_in=coalesce(v_row.requested_check_in,attendance_daily.first_check_in),last_check_out=coalesce(v_row.requested_check_out,attendance_daily.last_check_out),status=coalesce(v_row.requested_status,attendance_daily.status),updated_at=now();
 end if;
 perform public.log_audit_event('attendance.correction.'||p_decision,'workflow',case when p_decision='approved' then 'notice' else 'warning' end,'attendance_corrections',p_id,'قرار تصحيح حضور',p_note,jsonb_build_object('employeeId',v_row.employee_id,'workDate',v_row.work_date));
 perform public.notify_employee(
   v_row.employee_id,
   case p_decision when 'approved' then 'تم قبول تصحيح الحضور' else 'تم رفض تصحيح الحضور' end,
   format('تصحيح حضور بتاريخ %s%s', v_row.work_date, case when p_note is not null then E'\n'||p_note else '' end),
   'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
   'attendance_corrections', p_id,
   jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date));
end $$;

-- ---------------------------------------------------------------------
-- 6) decide_overtime_record — إشعار الموظف بقرار الساعات الإضافية + تدقيق
-- ---------------------------------------------------------------------
create or replace function public.decide_overtime_record(p_id uuid,p_decision text,p_approved_minutes integer default null,p_note text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_row public.overtime_records; v_min integer;
begin
 select * into strict v_row from public.overtime_records where id=p_id for update;
 if not(public.current_is_full_access() or public.can_access_employee(v_row.employee_id,'attendance.overtime.approve')) then raise exception 'FORBIDDEN'; end if;
 if v_row.status<>'pending' or p_decision not in ('approved','rejected') then raise exception 'INVALID_DECISION'; end if;
 v_min := case when p_decision='approved' then least(coalesce(p_approved_minutes,v_row.requested_minutes),v_row.requested_minutes) else 0 end;
 update public.overtime_records set status=p_decision,approved_minutes=v_min,approved_by=public.current_employee_id(),approved_at=now(),reason=coalesce(p_note,reason),updated_at=now() where id=p_id;
 perform public.log_audit_event('attendance.overtime.'||p_decision,'workflow',case when p_decision='approved' then 'notice' else 'warning' end,'overtime_records',p_id,'قرار ساعات إضافية',p_note,jsonb_build_object('employeeId',v_row.employee_id,'workDate',v_row.work_date,'approvedMinutes',v_min));
 perform public.notify_employee(
   v_row.employee_id,
   case p_decision when 'approved' then 'تم اعتماد ساعاتك الإضافية' else 'تم رفض ساعاتك الإضافية' end,
   format('ساعات إضافية بتاريخ %s (%s دقيقة)%s', v_row.work_date, v_min, case when p_note is not null then E'\n'||p_note else '' end),
   'attendance', case p_decision when 'approved' then 'normal' else 'high' end,
   'overtime_records', p_id,
   jsonb_build_object('decision', p_decision, 'workDate', v_row.work_date, 'approvedMinutes', v_min));
end $$;

-- ---------------------------------------------------------------------
-- 7) publish_roster_admin — إشعار الموظفين المدرجين بنشر الجدول
-- ---------------------------------------------------------------------
create or replace function public.publish_roster_admin(p_name text,p_period_start date,p_period_end date,p_department_id uuid,p_team_id uuid,p_branch_id uuid,p_days jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_id uuid; v_item jsonb; v_employee uuid; v_date date; v_shift uuid; v_status text; v_code text; v_employees uuid[] := '{}'::uuid[];
begin
 if not(public.current_is_full_access() or public.has_permission('attendance.roster.manage')) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
 if p_period_end<p_period_start or jsonb_typeof(p_days)<>'array' then raise exception 'INVALID_ROSTER'; end if;
 v_code:='RST-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into public.work_rosters(code,name,period_start,period_end,department_id,team_id,branch_id,status,published_at,published_by,notes,created_by)
 values(v_code,trim(p_name),p_period_start,p_period_end,p_department_id,p_team_id,p_branch_id,'published',now(),public.current_employee_id(),p_notes,auth.uid()) returning id into v_id;
 for v_item in select * from jsonb_array_elements(p_days) loop
  v_employee:=(v_item->>'employeeId')::uuid; v_date:=(v_item->>'workDate')::date; v_shift:=nullif(v_item->>'shiftId','')::uuid; v_status:=coalesce(v_item->>'dayStatus','scheduled');
  if v_date<p_period_start or v_date>p_period_end or not public.can_access_employee(v_employee,'attendance.roster.manage') then raise exception 'ROSTER_SCOPE_OR_DATE_INVALID'; end if;
  if not (v_employee = any(v_employees)) then v_employees := v_employees || v_employee; end if;
  insert into public.roster_days(roster_id,employee_id,work_date,shift_id,work_site_id,geofence_id,day_status,start_override,end_override,notes,created_by)
  values(v_id,v_employee,v_date,v_shift,nullif(v_item->>'workSiteId','')::uuid,nullif(v_item->>'geofenceId','')::uuid,v_status,nullif(v_item->>'startOverride','')::time,nullif(v_item->>'endOverride','')::time,v_item->>'notes',auth.uid());
 end loop;
 perform public.log_audit_event('attendance.roster.published','workflow','notice','work_rosters',v_id,'نشر جدول ورديات',null,jsonb_build_object('start',p_period_start,'end',p_period_end));
 foreach v_employee in array v_employees loop
  perform public.notify_employee(
   v_employee, 'جدول ورديات جديد',
   format('نُشر جدول الورديات «%s» للفترة من %s إلى %s', trim(p_name), p_period_start, p_period_end),
   'attendance', 'normal', 'work_rosters', v_id,
   jsonb_build_object('start',p_period_start,'end',p_period_end));
 end loop;
 return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 8) cancel_location_request_as_requester — إشعار الموظف المستهدف بالإلغاء
-- ---------------------------------------------------------------------
create or replace function public.cancel_location_request_as_requester(
  p_request_id uuid
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me  uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  select * into v_req from public.live_location_requests where id = p_request_id;
  if not found then
    raise exception 'request not found' using errcode = 'P0002';
  end if;
  -- Only the original requester OR a full-access user can cancel.
  if v_req.requested_by is distinct from v_me and not public.current_is_full_access() then
    raise exception 'can only cancel your own location requests' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'accepted') then
    raise exception 'request cannot be cancelled in its current status' using errcode = '22023';
  end if;

  update public.live_location_requests
    set status     = 'rejected',
        expires_at = now(),
        metadata   = jsonb_set(
          coalesce(metadata, '{}'::jsonb),
          '{cancelledByRequester}',
          'true'
        )
    where id = p_request_id;

  perform public.log_audit_event(
    'live_location.request_cancelled', 'security', 'info',
    'live_location_requests', p_request_id,
    'إلغاء طلب الموقع من قِبل المدير', null,
    jsonb_build_object('requestId', p_request_id, 'cancelledBy', v_me)
  );

  -- إشعار الموظف المستهدف بإلغاء الطلب (0316)
  if v_req.employee_id is not null and v_req.employee_id <> v_me then
    perform public.notify_employee(
      v_req.employee_id, 'أُلغي طلب مشاركة موقعك',
      format('أُلغي طلب مشاركة الموقع الحيّ (الحالة: %s)', coalesce(v_req.status, '')),
      'location', 'normal', 'live_location_requests', p_request_id,
      jsonb_build_object('cancelledBy', v_me));
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- 9) decide_work_assignment — إشعار المشاركين ومنشئ التكليف بالقرار
-- ---------------------------------------------------------------------
create or replace function public.decide_work_assignment(
  p_assignment_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.work_assignments
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments; v_to text; v_part uuid;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'assignment not found' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'not authorized to decide this assignment' using errcode = '42501';
  end if;
  if v_row.status not in ('SUBMITTED','PENDING_APPROVAL','DRAFT') then
    raise exception 'assignment not in a decidable state (%)', v_row.status using errcode = '22023';
  end if;
  v_to := case when p_decision = 'approve' then 'APPROVED' else 'REJECTED' end;

  update public.work_assignments
    set status = v_to, decided_by = v_me, decided_at = now(),
        decision_comment = p_comment, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.decided', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'قرار على تكليف عمل', p_decision,
    jsonb_build_object('decision', p_decision, 'type', v_row.assignment_type));

  -- إشعار المشاركين ومنشئ التكليف (0316)
  for v_part in
    select employee_id from public.work_assignment_participants
    where assignment_id = p_assignment_id
  loop
    perform public.notify_employee(
      v_part,
      case p_decision when 'approve' then 'تم اعتماد تكليفك' else 'تم رفض تكليفك' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end loop;
  if v_row.created_by_employee_id is not null and v_row.created_by_employee_id <> v_me then
    perform public.notify_employee(
      v_row.created_by_employee_id,
      case p_decision when 'approve' then 'تم اعتماد تكليف العمل' else 'تم رفض تكليف العمل' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'مأمورية'
                         when 'CONVOY' then 'قافلة'
                         else 'فاندي' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end if;

  return v_row;
end $$;

-- ---------------------------------------------------------------------
-- 10) decide_kpi_appeal — إشعار الموظف بقرار اعتراضه
-- ---------------------------------------------------------------------
create or replace function public.decide_kpi_appeal(p_appeal_id uuid,p_decision text,p_note text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.kpi_appeals;
begin
 if not (public.current_is_full_access() or public.current_is_executive_secretary()) then raise exception 'FORBIDDEN'; end if;
 if p_decision not in ('accepted','rejected') or length(trim(coalesce(p_note,'')))<8 then raise exception 'INVALID_APPEAL_DECISION'; end if;
 select * into strict v from public.kpi_appeals where id=p_appeal_id for update;
 if v.status not in ('submitted','under_review') then raise exception 'APPEAL_ALREADY_DECIDED'; end if;
 update public.kpi_appeals set status=p_decision,review_note=trim(p_note),reviewed_by=public.current_employee_id(),reviewed_at=now(),updated_at=now() where id=p_appeal_id;
 if p_decision='accepted' then
  -- V17: route to manager_review (the finalization step), not manager_final
  update public.kpi_evaluations set stage='manager_review',current_stage='manager_review',workflow_status='RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',locked=false,final_score=null,final_rating=null,final_breakdown=null,updated_at=now() where id=v.evaluation_id;
 end if;
 perform public.log_audit_event('kpi.appeal.'||p_decision,'workflow','notice','kpi_appeals',p_appeal_id,'قرار اعتراض KPI',trim(p_note),jsonb_build_object('evaluationId',v.evaluation_id));
 perform public.notify_employee(
   v.employee_id,
   case p_decision when 'accepted' then 'تم قبول اعتراضك على تقييم KPI' else 'تم رفض اعتراضك على تقييم KPI' end,
   format('%s%s', case p_decision when 'accepted' then 'أُعيد التقييم للمراجعة النهائية.' else 'بقيت النتيجة كما هي.' end, E'\n'||trim(p_note)),
   'kpi', case p_decision when 'accepted' then 'normal' else 'high' end,
   'kpi_appeals', p_appeal_id,
   jsonb_build_object('decision', p_decision, 'evaluationId', v.evaluation_id));
end $$;

-- ---------------------------------------------------------------------
-- 11) request_break_glass — إشعار الموافِقين بطلب Break Glass جديد
-- ---------------------------------------------------------------------
create or replace function public.request_break_glass(p_target_user_id uuid, p_role_id uuid, p_duration_minutes integer, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.break_glass_requests; v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.request')) then raise exception 'break glass request denied' using errcode='42501'; end if;
  select * into v_role from public.roles where id=p_role_id;
  if not found then raise exception 'role not found' using errcode='P0002'; end if;
  if p_duration_minutes not between 5 and 240 then raise exception 'duration out of range' using errcode='22023'; end if;
  insert into public.break_glass_requests(target_user_id,requested_role_id,duration_minutes,reason,requested_by)
  values(p_target_user_id,p_role_id,p_duration_minutes,trim(p_reason),auth.uid()) returning * into v_row;
  perform public.log_security_event('break_glass.requested','critical','detected',p_target_user_id::text,
    jsonb_build_object('requestId',v_row.id,'role',v_role.slug,'durationMinutes',p_duration_minutes,'reason',p_reason));
  perform public.notify_employees_with_permission(
    'access.break_glass.approve',
    'طلب Break Glass بانتظار اعتمادك',
    format('طلب وصول استثنائي لدور %s لمدة %s دقيقة.', v_role.slug, p_duration_minutes),
    'security', 'high', 'break_glass_requests', v_row.id,
    jsonb_build_object('role', v_role.slug, 'durationMinutes', p_duration_minutes));
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 12) approve_break_glass — إشعار الطالب بقبول الطلب
-- ---------------------------------------------------------------------
create or replace function public.approve_break_glass(p_request_id uuid, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_req public.break_glass_requests; v_user_role public.user_roles; v_role_slug text;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'break glass approval denied' using errcode='42501'; end if;
  select * into v_req from public.break_glass_requests where id=p_request_id for update;
  if not found then raise exception 'request not found' using errcode='P0002'; end if;
  if v_req.status <> 'pending' then raise exception 'request is not pending' using errcode='P0001'; end if;
  if v_req.requested_by=auth.uid() then raise exception 'four-eyes approval required' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'approval reason required' using errcode='22023'; end if;
  if exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_req.target_user_id and ur.role_id=v_req.requested_role_id
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'target user already has the requested active role' using errcode='P0001';
  end if;
  insert into public.user_roles(user_id,role_id,scope_override,effective_from,effective_to,granted_by)
  values(v_req.target_user_id,v_req.requested_role_id,jsonb_build_object('breakGlassRequestId',v_req.id),now(),now()+make_interval(mins=>v_req.duration_minutes),auth.uid())
  on conflict (user_id,role_id) do update set
    scope_override=excluded.scope_override,effective_from=excluded.effective_from,effective_to=excluded.effective_to,granted_by=excluded.granted_by
  returning * into v_user_role;
  update public.break_glass_requests set status='approved',approved_by=auth.uid(),approved_at=now(),active_from=now(),
    active_until=v_user_role.effective_to,user_role_id=v_user_role.id where id=v_req.id returning * into v_req;
  select r.slug into v_role_slug from public.roles r where r.id=v_req.requested_role_id;
  perform public.log_security_event('break_glass.approved','critical','allowed',v_req.target_user_id::text,
    jsonb_build_object('requestId',v_req.id,'userRoleId',v_user_role.id,'activeUntil',v_req.active_until,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'تم قبول طلب Break Glass',
    format('مُنح وصول استثنائي لدور %s حتى %s.', coalesce(v_role_slug,''), v_req.active_until),
    'security', 'normal', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$$;

-- ---------------------------------------------------------------------
-- 13) reject_break_glass — إشعار الطالب برفض الطلب
-- ---------------------------------------------------------------------
create or replace function public.reject_break_glass(p_request_id uuid, p_reason text)
returns public.break_glass_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_req public.break_glass_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'break glass rejection denied' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  update public.break_glass_requests set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=p_reason
  where id=p_request_id and status='pending' returning * into v_req;
  if not found then raise exception 'pending request not found' using errcode='P0002'; end if;
  perform public.log_security_event('break_glass.rejected','high','blocked',v_req.target_user_id::text,jsonb_build_object('requestId',v_req.id,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'تم رفض طلب Break Glass',
    format('رُفض طلب الوصول الاستثنائي.%s', E'\n'||p_reason),
    'security', 'high', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$$;

-- ---------------------------------------------------------------------
-- 14) decide_access_review_item — إشعار المستخدم بقرار مراجعة صلاحيته
-- ---------------------------------------------------------------------
create or replace function public.decide_access_review_item(p_item_id uuid, p_decision text, p_reason text)
returns public.access_review_items
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_item public.access_review_items;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then raise exception 'access review denied' using errcode='42501'; end if;
  if p_decision not in ('keep','revoke') then raise exception 'invalid decision' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  select * into v_item from public.access_review_items where id=p_item_id for update;
  if not found then raise exception 'review item not found' using errcode='P0002'; end if;
  if v_item.decision <> 'pending' then raise exception 'review item already decided' using errcode='P0001'; end if;
  update public.access_review_items set decision=p_decision,decision_reason=p_reason,decided_at=now(),reviewer_user_id=auth.uid()
  where id=p_item_id returning * into v_item;
  if p_decision='revoke' then update public.user_roles set effective_to=now() where id=v_item.user_role_id; end if;
  perform public.log_audit_event('access.review.decided','access',case when p_decision='revoke' then 'warning' else 'info' end,
    'access_review_items',v_item.id,'قرار مراجعة صلاحية',p_reason,jsonb_build_object('decision',p_decision,'userRoleId',v_item.user_role_id));
  perform public.notify_user(
    v_item.user_id,
    case p_decision when 'revoke' then 'أُلغيت صلاحية من حسابك' else 'تأكيد صلاحية من حسابك' end,
    format('قرار مراجعة الصلاحيات: %s.%s', case p_decision when 'revoke' then 'أُلغي دور' else 'أُبقي على دور' end, E'\n'||p_reason),
    'security', case p_decision when 'revoke' then 'high' else 'normal' end,
    'access_review_items', v_item.id,
    jsonb_build_object('decision', p_decision));
  return v_item;
end;
$$;

-- ---------------------------------------------------------------------
-- 15) submit_privacy_request — إشعار مسؤولي الخصوصية
-- ---------------------------------------------------------------------
create or replace function public.submit_privacy_request(p_request_type text, p_details text)
returns public.privacy_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.privacy_requests;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if p_request_type not in ('access','correction','export','restriction','deletion','objection') then raise exception 'invalid privacy request type' using errcode='22023'; end if;
  insert into public.privacy_requests(requester_user_id,requester_employee_id,request_type,details,due_at)
  values(auth.uid(),public.current_employee_id(),p_request_type,trim(p_details),now()+interval '30 days') returning * into v_row;
  perform public.log_audit_event('privacy.request.submitted','data','notice','privacy_requests',v_row.id,'تقديم طلب خصوصية',null,jsonb_build_object('requestType',p_request_type));
  perform public.notify_employees_with_permission(
    'privacy.request.manage',
    'طلب خصوصية جديد',
    format('طلب %s من موظف.', p_request_type),
    'privacy', 'normal', 'privacy_requests', v_row.id,
    jsonb_build_object('requestType', p_request_type), v_row.requester_employee_id);
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 16) decide_privacy_request — إشعار الطالب بتغيّر حالة طلبه
-- ---------------------------------------------------------------------
create or replace function public.decide_privacy_request(p_request_id uuid, p_status text, p_reason text)
returns public.privacy_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.privacy_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('privacy.request.manage')) then raise exception 'privacy management denied' using errcode='42501'; end if;
  if p_status not in ('in_review','waiting_requester','approved','rejected','completed') then raise exception 'invalid status' using errcode='22023'; end if;
  if p_status in ('rejected','completed') and length(trim(coalesce(p_reason,''))) < 5 then raise exception 'reason required' using errcode='22023'; end if;
  update public.privacy_requests set status=p_status,decision_reason=p_reason,assigned_to=coalesce(assigned_to,auth.uid()),
    completed_at=case when p_status='completed' then now() else completed_at end where id=p_request_id returning * into v_row;
  if not found then raise exception 'privacy request not found' using errcode='P0002'; end if;
  perform public.log_audit_event('privacy.request.updated','data','notice','privacy_requests',v_row.id,'تحديث طلب خصوصية',p_reason,jsonb_build_object('status',p_status));
  perform public.notify_user(
    v_row.requester_user_id,
    'تحديث حالة طلب الخصوصية',
    format('أصبح طلبك بحالة %s.%s', p_status, case when p_reason is not null then E'\n'||p_reason else '' end),
    'privacy', case when p_status in ('approved','completed') then 'normal' else 'high' end,
    'privacy_requests', v_row.id,
    jsonb_build_object('status', p_status));
  return v_row;
end;
$$;

-- ---------------------------------------------------------------------
-- 17) document_signature_requests — trigger إشعار الموقّع عند طلب توقيع
-- ---------------------------------------------------------------------
create or replace function public.notify_document_signature_request()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.notify_user(
    new.signer_user_id,
    'طلب توقيع مستند',
    format('يوجد مستند بانتظار توقيعك (%s).', coalesce(new.signer_role, '')),
    'documents', 'normal', 'document_signature_requests', new.id,
    jsonb_build_object('sequenceNo', new.sequence_no));
  return new;
end $$;
revoke execute on function public.notify_document_signature_request() from public;
grant execute on function public.notify_document_signature_request() to authenticated, service_role;

drop trigger if exists trg_document_signature_request_notify on public.document_signature_requests;
create trigger trg_document_signature_request_notify
  after insert on public.document_signature_requests
  for each row execute function public.notify_document_signature_request();

-- ---------------------------------------------------------------------
-- 18) submit_my_service_request — إشعار فريق الدعم
-- ---------------------------------------------------------------------
create or replace function public.submit_my_service_request(p_catalog_item_id uuid,p_title text,p_description text,p_priority text default 'normal',p_payload jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public,auth as $$ declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_sla integer; begin if v_emp is null then raise exception 'EMPLOYEE_CONTEXT_REQUIRED'; end if; select sla_hours into v_sla from public.service_catalog_items where id=p_catalog_item_id and active; if not found then raise exception 'SERVICE_NOT_AVAILABLE'; end if; insert into public.service_requests(catalog_item_id,requester_employee_id,title,description,payload,priority,due_at,created_by) values(p_catalog_item_id,v_emp,trim(p_title),nullif(trim(p_description),''),coalesce(p_payload,'{}'::jsonb),p_priority,now()+make_interval(hours=>v_sla),auth.uid()) returning id into v_id; perform public.notify_employees_with_permission('service.request.manage','طلب خدمة جديد',format('طلب خدمة: %s', trim(p_title)),'service','normal','service_requests',v_id,'{}'::jsonb,v_emp); return v_id; end $$;

-- ---------------------------------------------------------------------
-- 19) wellbeing_requests — trigger إشعار مسؤولي الدعم عند طلب جديد
-- ---------------------------------------------------------------------
create or replace function public.notify_wellbeing_request()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.notify_employees_with_permission(
    'wellbeing.request.manage',
    'طلب دعم جديد',
    format('طلب دعم ورفاهية (تصنيف %s).', coalesce(new.category, '')),
    'wellbeing', 'high', 'wellbeing_requests', new.id,
    jsonb_build_object('category', new.category),
    new.employee_id);
  return new;
end $$;
revoke execute on function public.notify_wellbeing_request() from public;
grant execute on function public.notify_wellbeing_request() to authenticated, service_role;

drop trigger if exists trg_wellbeing_request_notify on public.wellbeing_requests;
create trigger trg_wellbeing_request_notify
  after insert on public.wellbeing_requests
  for each row execute function public.notify_wellbeing_request();

-- ---------------------------------------------------------------------
-- 20) start_my_mission / end_my_mission
-- ---------------------------------------------------------------------
-- ملاحظة: جدول mission_executions ودالتا start_my_mission/end_my_mission
-- يملكهما 0318_mission_executions.sql (تعريف موحّد كامل: status + تقرير +
-- startTime/endTime + إرفاق missionExecution في inbox/detail). كان هذا
-- القسم يعرّفهما بصيغة سابقة مختلفة — حُذف لتجنّب تعارض التوقيع/الجدول
-- بين migration متوازيين (المعرّف الأحدث والأشمل هو 0318_mission_executions).

-- ---------------------------------------------------------------------
-- 21) approve_offboarding_case — إشعار موظف تسلّم المهام بإكمال الإنهاء
-- ---------------------------------------------------------------------
create or replace function public.approve_offboarding_case(p_case_id uuid,p_final_settlement_reference text default null,p_exit_interview_notes text default null)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.offboarding_cases;
begin
 if not(public.current_is_full_access() or public.has_permission('offboarding.case.approve')) then raise exception 'FORBIDDEN'; end if;
 select * into strict v from public.offboarding_cases where id=p_case_id for update;
 if v.status<>'ready_for_approval' or exists(select 1 from public.asset_assignments where employee_id=v.employee_id and status in ('assigned','return_requested')) then raise exception 'CLEARANCE_OR_ASSETS_PENDING'; end if;
 update public.offboarding_cases set status='completed',approved_by=public.current_employee_id(),approved_at=now(),completed_at=now(),final_settlement_reference=p_final_settlement_reference,exit_interview_notes=p_exit_interview_notes,updated_at=now() where id=p_case_id;
 update public.employees set status='terminated',is_active=false,updated_at=now() where id=v.employee_id;
 update public.profiles set status='disabled',updated_at=now() where employee_id=v.employee_id;
 update public.user_roles set effective_to=coalesce(effective_to,now()) where user_id=(select user_id from public.employees where id=v.employee_id) and (effective_to is null or effective_to>now());
 insert into public.offboarding_actions(offboarding_case_id,action_type,from_status,to_status,actor_employee_id,actor_user_id) values(p_case_id,'approve','ready_for_approval','completed',public.current_employee_id(),auth.uid());
 perform public.log_audit_event('offboarding.completed','workflow','warning','offboarding_cases',p_case_id,'اكتمال إنهاء خدمة موظف',null,jsonb_build_object('employeeId',v.employee_id));
 if v.handover_employee_id is not null and v.handover_employee_id <> public.current_employee_id() then
  perform public.notify_employee(
   v.handover_employee_id,
   'اكتمال إنهاء خدمة — تسلّم المهام',
   'اكتمل إنهاء خدمة أحد الزملاء المسلَّمة إليك، راجع مهام التسليم وأكمل إجراءاتك.',
   'offboarding', 'normal', 'offboarding_cases', p_case_id,
   jsonb_build_object('employeeId', v.employee_id));
 end if;
end $$;

-- ---------------------------------------------------------------------
-- الختام
-- ---------------------------------------------------------------------
notify pgrst, 'reload schema';

commit;
