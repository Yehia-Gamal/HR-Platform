-- 0139: V17 §4.3 — إضافة حالة "مُعاد" (returned) إلى دورة عمل الطلبات.
-- يعالج:
--   1) إضافة 'returned' إلى قيد CHECK على requests.status.
--   2) تحديث decide_request لقبول قرار 'return' — إعادة الطلب للموظف لتصحيحه.
--      "إعادة" أخف من الرفض: الطلب يُعاد للموظف مع ملاحظة، والموظف يرسل طلبًا جديدًا.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) توسيع قيد CHECK على requests.status ليشمل 'returned'
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.requests drop constraint if exists requests_status_check;
alter table public.requests
  add constraint requests_status_check
  check (status in ('pending','approved','rejected','cancelled','withdrawn','expired','returned'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث decide_request لدعم قرار 'return'
--    المصدر الأصلي: 0012 (آخر create or replace كامل)
-- ─────────────────────────────────────────────────────────────────────────────

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
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  -- V17 §4.3: دعم 'return' بالإضافة إلى 'approve' و 'reject'
  if p_decision not in ('approve','reject','return') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;
  -- 'return' يتطلب تعليقًا إلزاميًا
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

  -- Fallback for legacy/no-definition requests.
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
    return v_req;
  end if;

  if v_step.workflow_step_id is not null then
    select * into v_step_def
    from public.workflow_steps
    where id = v_step.workflow_step_id;
  end if;

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

  if not v_authorized then
    raise exception 'not authorized for the active workflow step' using errcode = '42501';
  end if;

  -- تسجيل إجراء الخطوة الحالية
  update public.request_steps
  set status = case p_decision
                 when 'approve' then 'approved'
                 -- 'return' يُعامَل كـ 'rejected' على مستوى الخطوة (لا يوجد حالة 'returned' في request_steps)
                 else 'rejected'
               end,
      acted_at = now(),
      acted_by = v_me,
      comment = p_comment,
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
    p_comment, auth.uid()
  );

  -- reject أو return → إنهاء كل الخطوات المعلقة وإغلاق الطلب
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

    return v_req;
  end if;

  -- approve: الانتقال للخطوة التالية أو الإغلاق
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
  else
    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;
  end if;

  return v_req;
end;
$$;

comment on function public.decide_request(uuid, text, text) is
  'V17 §4.3: قرار على الطلب (approve/reject/return). 0139: أُضيف قرار "إعادة" (return) للموظف.';
