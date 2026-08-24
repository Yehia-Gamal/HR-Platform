begin;

-- Migration 0464: HR صلاحية كاملة + المسار الطبيعي + صندوق يرى كل فاعل طلباته.
-- قرار إداري صريح (تصحيح لفهم 0462):
--   1) HR (hr-manager / hr-specialist) صلاحيته كاملة غير مقيدة — يعتمد أي
--      طلب، أي مرحلة، أي وقت، أي يوم (حتى الجمعة)، حتى بعد تصعيد الطلب
--      لأبو عمار، وحتى طلبه الشخصي (إذن صريح من الإدارة — التعديل الوحيد
--      على 0441).
--   2) المدير المباشر يعتمد طلب مرؤوسه في أي وقت وأي يوم — حتى بعد تجاوز
--      المهلة وتصعيد الطلب لمدير التشغيل 1 (أبو عمار) — كما هو في 0441.
--   3) أبو عمار (operations-manager-1): الخطوة 2+ أو مهلة متجاوزة (0440).
--   4) صندوق الإجراءات (نهاية الملف): كل فاعل يرى ما يخصه — إصلاح الصندوق
--      الفارغ مع إعادة شمول HR والسكرتير التنفيذي (شرط 0427 الأصلي).

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
  -- حظر الموافقة الذاتية للجميع إلا HR (إذن صريح من الإدارة — 0464)
  if v_req.employee_id = v_me
     and not public.current_has_active_role(array['hr-manager','hr-specialist']) then
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
  '0464: قرار — HR غير مقيد (أي طلب/مرحلة/وقت/يوم، حتى طلبه الشخصي) + مدير مباشر (أي وقت حتى بعد التصعيد) + أبو عمار operations-manager-1 (خطوة>=2 أو مهلة متجاوزة — 0440) + full_access. موافقة واحدة تُنهي الطلب.';
revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

-- ── مركز الإجراءات الموحد: كل فاعل يرى ما يخصه (0464) ──
-- إصلاح الصندوق الفارغ: كان شرط 0427 يعتمد can_access_employee فقط —
-- فلم يكن أبو عمار يرى طلبات الخطوة 2 إطلاقاً. الآن: طلبي + مديري المباشر
-- + أبو عمار عند دور الخطوة له (خطوة>=2/مهلة متجاوزة/تصعيد) + شرط 0427
-- الأصلي كاملاً (HR عبر can_access_employee + السكرتير التنفيذي).
create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 with actions as (
  select 'request-'||r.id::text id,'request'::text kind,coalesce(r.title,'طلب رقم '||r.request_number::text) title,e.full_name_ar subtitle,
   case when r.decision_due_at<now()+interval '4 hours' then 'urgent' else 'high' end priority,r.workflow_status status,r.decision_due_at due_at,'/hr/requests'::text action_url,coalesce(r.updated_at,r.created_at) source_updated_at
  from public.requests r join public.employees e on e.id=r.employee_id
  left join lateral (
    select rs.step_order, rs.escalation_deadline
      from public.request_steps rs
     where rs.request_id = r.id
       and rs.status in ('active','escalated','pending')
     order by (rs.status = 'active') desc, rs.step_order
     limit 1
  ) cs on true
  where r.status='pending'
    and (
      r.employee_id=public.current_employee_id()
      or r.manager_employee_id=public.current_employee_id()
      or (public.current_has_active_role(array['operations-manager-1'])
          and (
            coalesce(cs.step_order,0) >= 2
            or coalesce(cs.escalation_deadline, r.escalation_deadline) < now()
            or r.workflow_status in ('escalated','awaiting_operator')
          ))
      or public.can_access_employee(r.employee_id,'requests.request.approve')
      or public.current_is_executive_secretary()
    )
  union all
  select 'kpi-'||k.id::text,'kpi','تقييم '||e.full_name_ar||' يحتاج إجراء',e.employee_code,
   case when k.current_stage='manager_final' then 'urgent' else 'high' end,k.current_stage,null::timestamptz,'/hr/performance',coalesce(k.updated_at,k.created_at)
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id
  where (k.current_stage='self' and k.employee_id=public.current_employee_id())
     or (k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id))
     or (k.current_stage='hr_review' and public.current_is_hr_reviewer())
     or (k.current_stage not in ('finalized','closed','archived') and public.current_is_executive_secretary())
  union all
  select 'decision-'||d.id::text,'decision',d.title,'متابعة قرار رسمي','normal',d.status,null::timestamptz,'/admin/official-feed',coalesce(d.updated_at,d.created_at)
  from public.administrative_decisions d where d.status='published' and d.requires_read_receipt=true
 )
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'subtitle',subtitle,'priority',priority,'status',status,'dueAt',due_at,'actionUrl',action_url,'sourceUpdatedAt',source_updated_at) order by source_updated_at desc nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;
revoke all on function public.get_universal_action_center(integer) from public,anon;
grant execute on function public.get_universal_action_center(integer) to authenticated;
comment on function public.get_universal_action_center(integer) is
  '0464: الطلبات المعلقة تُرى وفق الدور — طلبي / مديري المباشر (أي حالة حتى بعد التصعيد) / أبو عمار عند دور الخطوة له / HR والسكرتير عبر صلاحياتهما (0427) — إصلاح الصندوق الفارغ.';

commit;