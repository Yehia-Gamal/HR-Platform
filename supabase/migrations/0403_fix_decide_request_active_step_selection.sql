-- 0403: إصلاح اختيار الخطوة النشطة في decide_request (V25.3)
-- ══════════════════════════════════════════════════════════════════════
-- المشكلة: 0396 اختار الخطوة الحالية بأصغر step_order بين
--   ('active','escalated','pending'). عند تصعيد الخطوة 1 (status='escalated')
--   وتفعيل الخطوة 2 (status='active')، يبقى v_current_step = 1،
--   فيُرفض الأوبريشن (يتطلب step >= 2) و HR (يتطلب step >= 3) برمز 42501
--   رغم أن التصعيد فعّل خطوتهما — بما يناقض قواعد 0396 الموثقة:
--       الخطوة 2 (2–6س): المدير + الأوبريشن + full_access
--       الخطوة 3 (6س+): المدير + الأوبريشن + HR + full_access
--
-- الإصلاح: تفضيل الخطوة النشطة (status='active') عند اختيار الخطوة الحالية؛
--   وإن لم توجد نشطة نعود إلى أول escalated/pending. فلا تحجب الخطوة
--   المصعّدة الخطوة النشطة التالية.
-- ══════════════════════════════════════════════════════════════════════

begin;

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

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active) مهما كان ترتيبها،
  -- وإن لم توجد نشطة نأخذ أول escalated/pending (إصلاح 0403).
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
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
  '0403: قرار مرحلي — مدير(أي وقت) / أوبريشن(step>=2) / HR(step>=3) / full_access(أي وقت). الخطوة الحالية هي الخطوة النشطة وليس المصعّدة الأقدم.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
