begin;

-- Migration 0441: منح HR صلاحية اعتماد غير مقيدة على جميع الطلبات.
-- قرار إداري: HR (hr-manager / hr-specialist) يعتمد أي طلب في أي وقت
--   وبأي مرحلة — بلا شروط مدة أو خطوة (خلافاً لأبو عمار المقيد بـ 0440).
-- يبقى الحظر الوحيد: الموافقة الذاتية على طلب الموظف نفسه (حماية فساد).

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
  -- أبو عمار = مدير التشغيل 1 فقط (لا ضابط عمليات)
  v_is_operations := public.current_has_active_role(array['operations-manager-1']);
  -- 0441: HR غير مقيد — يعتمد أي طلب في أي وقت
  v_is_hr         := public.current_has_active_role(array['hr-manager','hr-specialist']);

  -- ── الصلاحية ──
  -- المدير المباشر + HR (0441) + full_access: دائماً (أي مرحلة، أي وقت)
  -- أبو عمار (operations-manager-1): من الخطوة 2 فما فوق، أو عندما تكون مهلة
  --   الخطوة/الطلب متجاوزة (طلبات قديمة عالقة — 0440).
  if not found then
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or v_is_hr
      or public.can_access_employee(v_req.employee_id, 'requests.approve');
  else
    v_authorized :=
      public.current_is_full_access()
      or v_is_direct_mgr
      or v_is_hr
      or (v_is_operations
          and (
            v_current_step >= 2
            or coalesce(v_step.escalation_deadline, v_req.escalation_deadline) < now()
            or v_req.workflow_status in ('escalated', 'awaiting_operator')
          )
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
    when v_is_hr then 'hr'
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
  '0406: قرار — مدير مباشر/HR (غير مقيد — 0441)/full_access دائماً؛ أبو عمار operations-manager-1 (step>=2 أو مهلة متجاوزة — 0440). موافقة واحدة تُنهي الطلب.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

commit;