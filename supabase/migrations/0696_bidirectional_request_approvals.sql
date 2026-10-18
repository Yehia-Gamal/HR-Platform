-- ===========================================================================
-- 0696: اعتماد الطلبات ثنائي الاتجاه (المدير التنفيذي + مدير التشغيل 1 + المدير المباشر)
-- ===========================================================================
-- المتطلبات:
-- 1) "وحتي لو عند المدير المباشر يقدر يعتمد المدير التنفيذي":
--    - للمدير التنفيذي ومدير التشغيل 1 والأدمن الصلاحية الكاملة لاعتماد أي طلب فوراً
--      في المرحلة الأولى (عند المدير المباشر) دون الحاجة لانتظار التصعيد أو مرور المهلة.
--    - اعتماد الإدارة العليا أو مدير التشغيل في المرحلة الأولى يُنهي الطلب ويعتمده نهائياً.
-- 2) "و ايضا حتي بعد ما يترفع للمدير التنفيذي ومدير تشغيل 1 عادي يقدر المدير العادي يقبل لموظفينه بدون اي مشاكل":
--    - للمدير المباشر الصلاحية الكاملة لاعتماد وقبول طلبات موظفيه حتى بعد تصعيدها
--      أو انتقالها للمرحلة الثانية (عند مدير التشغيل 1 أو المدير التنفيذي).
--    - اعتماد المدير المباشر بعد التصعيد يُعتمد بنجاح ويُغلق الطلب كمعتمد نهائياً.
-- ===========================================================================

begin;

-- ─── 1) تحديث request_decision_flags لتفعيل canDecide و awaitingMe بالاتجاهين ───
create or replace function public.request_decision_flags(
  p_req   public.requests,
  p_me    uuid,
  p_full  boolean,
  p_roles text[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_roles         text[] := coalesce(p_roles, '{}'::text[]);
  v_step          public.request_steps;
  v_is_clinic_mgr boolean;
  v_is_mgr        boolean;
  v_is_ops        boolean;
  v_override      boolean;
  v_can           boolean;
  v_awaiting      boolean;
begin
  -- لا قرار على طلب غير معلّق
  if p_me is null or p_req.id is null or p_req.status <> 'pending' then
    return jsonb_build_object('canDecide', false, 'awaitingMe', false);
  end if;

  v_override := coalesce(p_full, false)
    or v_roles && array['executive', 'executive-director', 'general-manager',
                        'executive-secretary', 'operations-manager-1', 'operations-manager',
                        'hr-manager', 'hr-specialist', 'hr-officer',
                        'admin', 'super-admin'];

  -- حظر الاعتماد الذاتي إلا لمن يملك صلاحية إدارية عليا
  if p_req.employee_id = p_me and not v_override then
    return jsonb_build_object('canDecide', false, 'awaitingMe', false);
  end if;

  -- الخطوة الحالية: النشطة أولاً ثم أول معلقة أو مصعدة
  select * into v_step
    from public.request_steps
   where request_id = p_req.id
     and status in ('active', 'escalated', 'pending')
   order by (status = 'active') desc, step_order
   limit 1;

  v_is_clinic_mgr := (
    p_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  v_is_mgr := p_req.manager_employee_id is not distinct from p_me
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(p_req.employee_id)
        or p_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = p_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
       where mr.employee_id = p_req.employee_id
         and mr.manager_employee_id = p_me
         and mr.relation_type = 'primary'
         and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  v_is_ops := v_roles && array['operations-manager-1', 'operations-manager'];

  -- canDecide:
  -- 1) الإدارة التنفيذية والتشغيلية (v_override): دائماً نعم، في أي مرحلة حتى لو عند المدير المباشر.
  -- 2) المدير المباشر لموظفيه (v_is_mgr): دائماً نعم، في أي مرحلة حتى لو تصعّد لمدير التشغيل أو التنفيذي.
  -- 3) المسند إليه بالاسم أو الدور.
  v_can := v_override
    or v_is_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = p_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
      or (v_step.assignee_role_slug is not null and v_step.assignee_role_slug = any(v_roles))
    ));

  -- awaitingMe:
  -- الطلب بانتظار قرار المستخدم إذا كان مديراً مباشراً للموظف أو إدارة تنفيذية/تشغيلية أو مسنداً له
  v_awaiting := v_can and (
       v_override
    or v_is_mgr
    or (v_step.id is not null and (
         v_step.assignee_employee_id = p_me
         or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
         or (v_step.assignee_role_slug is not null and v_step.assignee_role_slug = any(v_roles))
       ))
    or (v_step.id is null and (v_is_mgr or v_override))
  );

  return jsonb_build_object('canDecide', v_can, 'awaitingMe', coalesce(v_awaiting, false));
end;
$$;

revoke all on function public.request_decision_flags(public.requests, uuid, boolean, text[]) from public, anon;
grant execute on function public.request_decision_flags(public.requests, uuid, boolean, text[]) to authenticated, service_role;
comment on function public.request_decision_flags(public.requests, uuid, boolean, text[]) is
  '0696: canDecide و awaitingMe ثنائي الاتجاه للمدير التنفيذي ومدير التشغيل والمدير المباشر بلا قيود.';

-- ─── 2) تحديث decide_request لاعتماد أي مرحلة وتطبيق الإغلاق الكامل ───
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
  v_me              uuid := public.current_employee_id();
  v_req             public.requests;
  v_step            public.request_steps;
  v_authorized      boolean := false;
  v_is_direct_mgr   boolean;
  v_is_operations   boolean;
  v_is_hr           boolean;
  v_is_exec         boolean;
  v_is_clinic_mgr   boolean;
  v_current_step    integer;
  v_final_status    text;
  v_actor_role      text;
  v_correction_id   uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
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

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager','executive-secretary']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer']);
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-manager']);

  -- حظر الاعتماد الذاتي للجميع باستثناء من يملك صلاحية إدارية عليا
  if v_req.employee_id = v_me
     and not (public.current_is_full_access() or v_is_hr or v_is_exec or v_is_operations or public.current_has_active_role(array['admin','super-admin'])) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- الخطوة الحالية: نفضّل الخطوة النشطة (active)، وإن لم توجد نأخذ أول escalated/pending
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step := coalesce(v_step.step_order, 0);

  -- التحقق من كون المعتمِد مدير العيادات
  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or public.current_has_active_role(array['clinics-manager'])
  );

  -- التحقق من صفة المدير المباشر:
  v_is_direct_mgr := (v_req.manager_employee_id = v_me)
    or (
      v_is_clinic_mgr and (
        public.is_clinic_team_member(v_req.employee_id)
        or v_req.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
        or exists (
          select 1 from public.workflow_definitions wd
          where wd.id = v_req.workflow_definition_id and wd.code like 'medical_%'
        )
      )
    )
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    );

  -- الصلاحية الشاملة لاعتماد الطلبات (تشمل الإدارة التنفيذية والتشغيلية والمدير المباشر بدون قيود)
  v_authorized :=
    public.current_is_full_access()
    or v_is_exec
    or v_is_hr
    or v_is_direct_mgr
    or v_is_operations
    or (v_step.id is not null and (
      v_step.assignee_employee_id = v_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
    ))
    or public.current_has_active_role(array['admin','super-admin','executive-secretary']);

  if not v_authorized then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  -- تحديد الدور الفعلي لمتخذ القرار
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
  elsif v_is_exec then
    v_actor_role := 'executive';
  elsif v_is_operations then
    v_actor_role := 'operations';
  elsif v_is_hr then
    v_actor_role := 'hr';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
  else
    v_actor_role := 'manager';
  end if;

  -- 1) إذا كان القرار هو الرفض أو الإرجاع: يُغلق الطلب مباشرة
  if p_decision in ('reject', 'return') then
    v_final_status := case when p_decision = 'reject' then 'rejected' else 'returned' end;

    update public.requests
    set status = v_final_status,
        workflow_status = case when p_decision = 'reject' then 'terminated' else 'in_review' end,
        decided_at = now(),
        decided_by = v_me,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    update public.request_steps
    set status = v_final_status,
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where request_id = p_request_id
      and status in ('active', 'escalated', 'pending');

    update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_step.id, v_me, p_decision, 'pending', v_final_status, p_comment, auth.uid()
    );

    -- تصحيح البصمة عند الرفض أو الإرجاع:
    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        update public.attendance_corrections
        set status = case when p_decision = 'reject' then 'rejected' else 'cancelled' end,
            reviewed_by = v_me,
            reviewed_at = now(),
            review_note = coalesce(p_comment, case when p_decision = 'reject' then 'مرفوض مع الطلب' else 'معاد للمراجعة' end),
            updated_at = now()
        where id = v_correction_id and status = 'pending';
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      case when p_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', p_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- 2) إذا كان القرار هو الموافقة (approve):
  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid()
  );

  -- فحص ما إذا كان الطلب يحتاج خطوة لاحقة:
  -- القاعدة 1: إذا اعتمد المدير التنفيذي أو الأدمن أو مدير التشغيل في أي مرحلة -> يُعتمد نهائياً فوراً
  -- القاعدة 2: إذا اعتمد المدير المباشر طلباً تصعّد بالفعل للمرحلة 2 أو أعلى -> يُعتمد نهائياً فوراً
  -- خلاف ذلك (إذا كان المدير المباشر يعتمد المرحلة 1 وتوجد مرحلة 2 متبقية): تُنشّط المرحلة 2
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec or v_is_operations) then
    -- تنشيط الخطوة التالية
    if v_step.id is not null then
      update public.request_steps
      set status = 'approved',
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'active',
        updated_at = now()
    where request_id = p_request_id
      and step_order = (
        select min(step_order) from public.request_steps
        where request_id = p_request_id and step_order > v_current_step and status = 'pending'
      );

    select * into v_req from public.requests where id = p_request_id;
    return v_req;
  end if;

  -- اعتماد نهائي للطلب ولكافة خطواته (سواء من الإدارة العليا أو من المدير المباشر):
  update public.request_steps
  set status = 'approved',
      acted_at = coalesce(acted_at, now()),
      acted_by = coalesce(acted_by, v_me),
      comment = coalesce(comment, p_comment),
      updated_at = now()
  where request_id = p_request_id
    and status in ('active', 'escalated', 'pending');

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  update public.workflow_instances
  set status = 'completed', completed_at = now(), updated_at = now()
  where request_id = p_request_id and status = 'running';

  -- تطبيق الآثار التلقائية للطلب المعتمد:
  -- أ) تغيير الوردية (shift_change):
  if v_req.request_type = 'shift_change' and v_req.payload->>'shiftId' is not null then
    declare
      v_target_shift_id uuid := nullif(v_req.payload->>'shiftId','')::uuid;
      v_eff_date date := coalesce(nullif(v_req.payload->>'effectiveFrom','')::date, (now() at time zone 'Africa/Cairo')::date);
    begin
      if v_target_shift_id is not null then
        update public.shift_assignments
        set is_active = false,
            effective_to = least(coalesce(effective_to, v_eff_date), v_eff_date),
            updated_at = now()
        where employee_id = v_req.employee_id and is_active = true;

        insert into public.shift_assignments (
          employee_id, shift_id, effective_from, is_active, notes, created_by
        ) values (
          v_req.employee_id, v_target_shift_id, v_eff_date, true,
          'معتمد بطلب تغيير وردية: ' || coalesce(v_req.title, ''), auth.uid()
        );

        update public.attendance_daily
        set shift_id = v_target_shift_id, updated_at = now()
        where employee_id = v_req.employee_id and work_date = v_eff_date;
      end if;
    end;
  end if;

  -- ب) تصحيح البصمة (attendance_correction):
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      perform public.decide_attendance_correction(v_correction_id, 'approved', coalesce(p_comment, 'معتمد مع الطلب'));
    end if;
  end if;

  -- ج) الإجازات (leave):
  if v_req.request_type = 'leave' then
    perform public.activate_approved_leave(v_req.id);
  end if;

  -- إشعار صاحب الطلب بالاعتماد
  perform public.notify_employee(
    v_req.employee_id,
    'تم اعتماد طلبك بنجاح ✓',
    coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'decision', 'approve', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;
comment on function public.decide_request(uuid, text, text) is
  '0696: اعتماد ثنائي الاتجاه — للمدير التنفيذي ومدير التشغيل اعتماد أي مرحلة، وللمدير المباشر اعتماد طلبات موظفيه حتى بعد تصعيدها.';

-- ─── 3) تحديث get_universal_action_center لتغطية الحالتين ───
create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 with actions as (
  select 'request-'||r.id::text id,
         'request'::text kind,
         coalesce(r.title,'طلب رقم '||r.request_number::text) title,
         e.full_name_ar subtitle,
         case when r.decision_due_at<now()+interval '4 hours' then 'urgent' else 'high' end priority,
         r.workflow_status status,
         r.decision_due_at due_at,
         '/hr/requests?request='||r.id::text action_url,
         coalesce(r.updated_at,r.created_at) source_updated_at,
         e.full_name_ar as employee_name,
         e.photo_url as photo_url,
         r.request_type as request_type,
         r.request_number as request_number,
         r.title as request_title,
         r.reason as request_reason
  from public.requests r join public.employees e on e.id=r.employee_id
  where r.status='pending'
    and (
      r.employee_id=public.current_employee_id()
      or r.manager_employee_id=public.current_employee_id()
      or exists (
        select 1 from public.manager_relations mr
        where mr.employee_id = r.employee_id
          and mr.manager_employee_id = public.current_employee_id()
          and mr.relation_type = 'primary'
          and (mr.effective_to is null or mr.effective_to >= current_date)
      )
      or public.can_access_employee(r.employee_id,'requests.request.approve')
      or public.current_is_executive_secretary()
      or public.current_has_active_role(array['executive', 'executive-director', 'general-manager', 'operations-manager-1', 'operations-manager', 'admin', 'super-admin'])
    )
  union all
  select 'kpi-'||k.id::text,
         'kpi',
         'تقييم '||e.full_name_ar||' يحتاج إجراء',
         e.employee_code,
         case when k.current_stage='manager_final' then 'urgent' else 'high' end,
         k.current_stage,
         null::timestamptz,
         '/hr/performance',
         coalesce(k.updated_at,k.created_at),
         e.full_name_ar as employee_name,
         e.photo_url as photo_url,
         'kpi'::text as request_type,
         null::integer as request_number,
         null::text as request_title,
         null::text as request_reason
  from public.kpi_evaluations k join public.employees e on e.id=k.employee_id
  where (k.current_stage='self' and k.employee_id=public.current_employee_id())
     or (k.current_stage in ('manager_review','manager_final') and public.kpi_is_direct_manager(k.employee_id))
     or (k.current_stage='hr_review' and public.current_is_hr_reviewer())
  union all
  select 'decision-'||d.id::text,
         'decision',
         d.title,
         'متابعة قرار رسمي',
         'normal',
         d.status,
         null::timestamptz,
         '/admin/official-feed',
         coalesce(d.updated_at,d.created_at),
         null::text as employee_name,
         null::text as photo_url,
         'decision'::text as request_type,
         null::integer as request_number,
         d.title as request_title,
         null::text as request_reason
  from public.administrative_decisions d where d.status='published' and d.requires_read_receipt=true
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',id,
   'kind',kind,
   'title',title,
   'subtitle',subtitle,
   'priority',priority,
   'status',status,
   'dueAt',due_at,
   'actionUrl',action_url,
   'sourceUpdatedAt',source_updated_at,
   'employeeName',employee_name,
   'photoUrl',photo_url,
   'requestType',request_type,
   'requestNumber',request_number,
   'requestTitle',request_title,
   'requestReason',request_reason
 ) order by source_updated_at desc nulls last),'[]'::jsonb)
 from (select * from actions order by source_updated_at desc limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;

revoke all on function public.get_universal_action_center(integer) from public,anon;
grant execute on function public.get_universal_action_center(integer) to authenticated;
comment on function public.get_universal_action_center(integer) is
  '0696: صندوق الإجراءات الموحد مع تغطية كاملة للمدير التنفيذي ومدير التشغيل والمدير المباشر في كافة مراحل الطلبات.';

-- ─── 4) تحديث get_request_inbox لتشمل v_broad كافة أدوار التشغيل والسكرتير التنفيذي ───
create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me            uuid := public.current_employee_id();
  v_full          boolean := public.current_is_full_access();
  v_roles         text[];
  v_broad         boolean;
  v_is_clinic_mgr boolean;
  v_limit         integer := greatest(1, least(coalesce(p_limit, 100), 500));
begin
  if auth.uid() is null then
    return '[]'::jsonb;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  v_broad := v_full or v_roles && array['admin', 'super-admin', 'executive',
    'executive-director', 'general-manager', 'executive-secretary', 'hr-manager', 'operations-manager-1', 'operations-manager'];

  v_is_clinic_mgr := (
    v_me in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
    or 'clinics-manager' = any(v_roles)
  );

  return (
    with visible as (
      select r.id, r.status, r.employee_id, r.created_at
        from public.requests r
       where v_broad
          or r.employee_id = v_me
          or r.manager_employee_id = v_me
          or (
            v_is_clinic_mgr and (
              public.is_clinic_team_member(r.employee_id)
              or r.manager_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid)
              or exists (
                select 1 from public.workflow_definitions wd
                where wd.id = r.workflow_definition_id and wd.code like 'medical_%'
              )
            )
          )
          or exists (
            select 1 from public.manager_relations mr
             where mr.employee_id = r.employee_id
               and mr.manager_employee_id = v_me
               and mr.relation_type = 'primary'
               and mr.effective_from <= current_date
               and (mr.effective_to is null or mr.effective_to >= current_date)
          )
    ),
    picked as (
      select v.id
        from visible v
       order by (v.status = 'pending') desc,
                (v.employee_id is not distinct from v_me) desc,
                v.created_at desc
       limit v_limit
    )
    select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb)
      from (
        select p.created_at,
               jsonb_build_object(
                 'id', p.id,
                 'requestNumber', p.request_number,
                 'requestType', p.request_type,
                 'employeeId', p.employee_id,
                 'employeeName', e.full_name_ar,
                 'employeeCode', e.employee_code,
                 'employeePhotoUrl', e.photo_url,
                 'employeeDepartment', d.name,
                 'employeeJobTitle', jt.name,
                 'title', p.title,
                 'reason', p.reason,
                 'status', p.status,
                 'workflowStatus', p.workflow_status,
                 'currentStepOrder', coalesce(p.current_step_order, 0),
                 'activeStepName', cs.name_ar,
                 'activeStepRole', cs.assignee_role_slug,
                 'activeStepStatus', cs.status,
                 'activeStepDueAt', cs.due_at,
                 'decisionDueAt', p.decision_due_at,
                 'decidedAt', p.decided_at,
                 'decidedByName', dec.full_name_ar,
                 'createdAt', p.created_at,
                 'updatedAt', p.updated_at,
                 'payload', p.payload,
                 'isMine', coalesce(p.employee_id = v_me, false),
                 'canDecide', coalesce((fl.flags->>'canDecide')::boolean, false),
                 'awaitingMe', coalesce((fl.flags->>'awaitingMe')::boolean, false),
                 'missionExecution', case when p.request_type in ('mission', 'convoy', 'fundraising') then (
                   select to_jsonb(me) from (
                     select me.id, me.status,
                            me.started_at as "startedAt",
                            me.ended_at as "endedAt",
                            me.actual_minutes as "actualMinutes",
                            me.report, me.outcome
                       from public.mission_executions me
                      where me.request_id = p.id
                   ) me
                 ) end
               ) as item
          from picked k
          join public.requests p on p.id = k.id
          join public.employees e on e.id = p.employee_id
          left join public.departments d on d.id = e.department_id
          left join public.job_titles jt on jt.id = e.job_title_id
          left join public.employees dec on dec.id = p.decided_by
          left join lateral (
            select rs.name_ar, rs.assignee_role_slug, rs.status, rs.due_at
              from public.request_steps rs
             where rs.request_id = p.id
               and p.status = 'pending'
               and rs.status in ('active', 'escalated', 'pending')
             order by (rs.status = 'active') desc, rs.step_order
             limit 1
          ) cs on true
          cross join lateral (
            select public.request_decision_flags(p, v_me, v_full, v_roles) as flags
          ) fl
      ) x
  );
end;
$$;

revoke all on function public.get_request_inbox(integer) from public, anon;
grant execute on function public.get_request_inbox(integer) to authenticated;
comment on function public.get_request_inbox(integer) is
  '0696: صندوق الطلبات — المعلّق ثم طلباتي ثم الأحدث، مع canDecide/awaitingMe ثنائي الاتجاه.';

commit;
