-- 0733: مهلة البت الموحدة ساعتان وتصعيد تلقائي لأبو عمار + حق المدير المباشر الكامل في البت حتى بعد التصعيد
-- ========================================================================================================
-- القواعد المعتمدة:
--   1) المهلة المحددة للمدير المباشر هي ساعتان (2 hours) من تاريخ تقديم الطلب.
--   2) بعد انقضاء الساعتين دون رد، يتم تصعيد الطلب تلقائياً إلى مدير التشغيل 1 (أبو عمار).
--   3) حتى بعد تصعيد الطلب ووجوده عند مدير التشغيل (أبو عمار)، يظل المدير المباشر كامل الصلاحية
--      في قبول (اعتماد) أو رفض أو إرجاع الطلب في أي لحظة قبل أن يبت فيه أبو عمار.
-- ========================================================================================================

begin;

-- 1) تحديث تريجر احتساب مهلة القرار عند إنشاء أو تعديل الطلب (ساعتان بالضبط)
create or replace function public.tg_request_decision_due()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_base timestamptz := coalesce(new.created_at, now());
begin
  -- مهلة البت الموحدة: ساعتان فقط
  if new.decision_due_at is null then
    new.decision_due_at := v_base + interval '2 hours';
  end if;
  -- مهلة التصعيد للمدير المباشر: ساعتان فقط
  if new.escalation_deadline is null then
    new.escalation_deadline := v_base + interval '2 hours';
  end if;
  return new;
end;
$$;

-- 2) تحديث دالة submit_request لضمان مهلة الساعتين
create or replace function public.submit_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_mgr uuid;
  v_req public.requests;
  v_step_id uuid;
  v_created_at timestamptz := now();
  v_due timestamptz;
  v_esc timestamptz;
  v_ops_emp uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- المهلة الموحدة ساعتان
  v_due := v_created_at + interval '2 hours';
  v_esc := v_created_at + interval '2 hours';

  -- جلب المدير المباشر
  select manager_employee_id into v_mgr
  from public.manager_relations
  where employee_id = v_me
    and relation_type = 'primary'
    and (effective_to is null or effective_to >= current_date)
  order by effective_from desc nulls last
  limit 1;

  insert into public.requests (
    request_type,
    employee_id,
    manager_employee_id,
    status,
    workflow_status,
    title,
    reason,
    decision_due_at,
    escalation_deadline,
    payload,
    created_at,
    updated_at
  ) values (
    p_request_type,
    v_me,
    v_mgr,
    'pending',
    'submitted',
    p_title,
    p_reason,
    v_due,
    v_esc,
    coalesce(p_payload, '{}'::jsonb),
    v_created_at,
    v_created_at
  ) returning * into v_req;

  -- إنشاء خطوة المدير المباشر (Step 1)
  insert into public.request_steps (
    request_id,
    step_order,
    name_ar,
    assignee_employee_id,
    status,
    due_at,
    escalation_deadline,
    created_at,
    updated_at
  ) values (
    v_req.id,
    1,
    'المدير المباشر',
    v_mgr,
    'active',
    v_due,
    v_esc,
    v_created_at,
    v_created_at
  ) returning id into v_step_id;

  -- إنشاء خطوة مدير التشغيل 1 (أبو عمار - Step 2)
  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');
  if v_ops_emp is null then
    v_ops_emp := '767eae8e-e7be-458e-a6ca-879414e46b08'::uuid; -- محمد عبدالباسط (أبو عمار)
  end if;

  insert into public.request_steps (
    request_id,
    step_order,
    name_ar,
    assignee_role_slug,
    assignee_employee_id,
    status,
    created_at,
    updated_at
  ) values (
    v_req.id,
    2,
    'مدير التشغيل 1',
    'operations-manager-1',
    v_ops_emp,
    'pending',
    v_created_at,
    v_created_at
  );

  -- تسجيل إجراء التقديم
  insert into public.request_actions (
    request_id,
    request_step_id,
    actor_employee_id,
    action,
    from_status,
    to_status,
    comment,
    created_by
  ) values (
    v_req.id,
    v_step_id,
    v_me,
    'submit',
    null,
    'pending',
    'تقديم الطلب وبدء مهلة الساعتين',
    auth.uid()
  );

  -- إشعار المدير المباشر
  if v_mgr is not null then
    perform public.notify_employee(
      v_mgr,
      'طلب جديد بانتظار قرارك (مهلة ساعتان)',
      coalesce(p_title, '') || ' — يُرجى البت خلال ساعتين قبل التصعيد لمدير التشغيل.',
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('deepLink', '/requests/' || v_req.id)
    );
  end if;

  return v_req;
end;
$$;

-- 3) تحديث request_decision_flags: ضمان حق المدير المباشر في البت دائماً
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
  v_can           boolean := false;
  v_awaiting      boolean := false;
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

  -- التحقق من كون المستخدم هو المدير المباشر للموظف صاحب الطلب
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
    )
    or exists (
      select 1 from public.employees e
      where e.id = p_req.employee_id and e.department_id is not null
        and exists (
          select 1 from public.employees mgr
          where mgr.id = p_me and mgr.department_id = e.department_id
            and exists (
              select 1 from public.user_roles ur
              join public.roles r on r.id = ur.role_id
              where ur.user_id = mgr.user_id and r.slug in ('direct-manager', 'department-manager')
            )
        )
    );

  v_is_ops := v_roles && array['operations-manager-1', 'operations-manager'];

  -- canDecide:
  -- 1) الإدارة التنفيذية والتشغيلية (v_override): نعم دائماً
  -- 2) المدير المباشر لموظفيه (v_is_mgr): نعم دائماً وأبداً حتى لو صُعّد الطلب لأبو عمار!
  -- 3) المسند إليه بالاسم أو الدور
  v_can := v_override
    or v_is_mgr
    or (v_step.id is not null and (
      v_step.assignee_employee_id = p_me
      or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
      or (v_step.assignee_role_slug is not null and v_step.assignee_role_slug = any(v_roles))
    ));

  -- awaitingMe:
  -- إذا كان المدير المباشر، فالطلب بانتظار قراره حتى لو عند مدير التشغيل
  v_awaiting := v_can and (
       v_is_mgr
    or v_override
    or (v_step.id is not null and (
         v_step.assignee_employee_id = p_me
         or (v_is_clinic_mgr and v_step.assignee_employee_id in ('4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid, 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid))
         or (v_step.assignee_role_slug is not null and v_step.assignee_role_slug = any(v_roles))
       ))
  );

  return jsonb_build_object('canDecide', v_can, 'awaitingMe', coalesce(v_awaiting, false));
end;
$$;

-- 4) تحديث دالة decide_request: ضمان قبول قرار المدير المباشر حتى لو صُعِّد الطلب
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null::text
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
  v_is_direct_mgr   boolean := false;
  v_is_operations   boolean := false;
  v_is_hr           boolean := false;
  v_is_exec         boolean := false;
  v_is_clinic_mgr   boolean := false;
  v_actor_role      text;
  v_actor_role_name text;
  v_correction_id   uuid;
  v_decision        text;
  v_chk_start       date;
  v_chk_end         date;
  v_ops_emp         uuid;
begin
  if v_me is null and auth.role() <> 'service_role' then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  v_decision := case
    when lower(trim(coalesce(p_decision, ''))) in ('approve', 'approved') then 'approve'
    when lower(trim(coalesce(p_decision, ''))) in ('reject', 'rejected') then 'reject'
    when lower(trim(coalesce(p_decision, ''))) in ('return', 'returned') then 'return'
    else lower(trim(coalesce(p_decision, '')))
  end;

  if v_decision not in ('approve','reject','return') then
    raise exception 'invalid_decision: %', p_decision using errcode = '22023';
  end if;
  if v_decision = 'return' and nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'return_requires_comment' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request_not_found' using errcode = 'P0002';
  end if;

  if v_req.status not in ('pending', 'under_review', 'escalated') then
    raise exception 'request_not_actionable: request status is %', v_req.status using errcode = '22023';
  end if;

  -- فحص تداخل الإجازات عند الاعتماد
  if v_decision = 'approve' and v_req.request_type = 'leave' then
    v_chk_start := nullif(coalesce(v_req.payload->>'startDate', v_req.payload->>'start_date'), '')::date;
    v_chk_end   := nullif(coalesce(v_req.payload->>'endDate', v_req.payload->>'end_date'), '')::date;
    if v_chk_start is not null and v_chk_end is not null then
      if exists (
        select 1 from public.requests r
        where r.employee_id = v_req.employee_id
          and r.id <> v_req.id
          and r.request_type = 'leave'
          and r.status = 'approved'
          and nullif(coalesce(r.payload->>'startDate', r.payload->>'start_date'), '')::date <= v_chk_end
          and nullif(coalesce(r.payload->>'endDate', r.payload->>'end_date'), '')::date >= v_chk_start
      ) then
        raise exception 'لا يمكن اعتماد الطلب: يوجد بالفعل إجازة أخرى معتمدة للموظف تغطي نفس الفترة' using errcode = '22023';
      end if;

      -- إلغاء أي أذونات معتمدة أو معلقة في هذا اليوم
      update public.requests
      set status = 'cancelled',
          review_note = 'تم إلغاء الإذن تلقائياً لاعتماد إجازة كاملة للموظف في نفس اليوم',
          updated_at = now()
      where employee_id = v_req.employee_id
        and request_type in ('late_permit', 'early_permit', 'attendance_permit')
        and status in ('pending', 'approved')
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date >= v_chk_start
        and nullif(coalesce(payload->>'permitDate', payload->>'date'), '')::date <= v_chk_end;
    end if;
  end if;

  -- فحص الأدوار والصلاحيات
  v_is_exec := public.is_employee_executive(v_me);
  v_is_hr := public.current_has_active_role(array['admin','super-admin','executive','executive-director','hr-manager']);
  v_is_operations := public.current_has_active_role(array['operations-manager-1','operations-officer']);
  v_is_direct_mgr := (
    v_req.manager_employee_id = v_me
    or public.is_manager_of(v_me, v_req.employee_id)
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
  );

  v_is_clinic_mgr := (
    v_me in (
      '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
      'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
    )
    and public.is_clinic_team_member(v_req.employee_id)
  );

  if auth.role() = 'service_role' or v_is_clinic_mgr or v_is_exec or v_is_hr or v_is_operations or v_is_direct_mgr then
    v_authorized := true;
  end if;

  -- اختيار الخطوة المناسبة لتحديثها:
  -- إذا كان المتصرف مديراً مباشراً، نحدث خطوة المدير المباشر (Step 1)
  -- إذا كان مدير تشغيل، نحدث خطوة مدير التشغيل (Step 2)
  if v_is_direct_mgr then
    select s.* into v_step
    from public.request_steps s
    where s.request_id = p_request_id and s.step_order = 1
    limit 1;
  end if;

  if v_step.id is null then
    select s.* into v_step
    from public.request_steps s
    where s.request_id = p_request_id and s.status in ('active','escalated')
    order by (s.status = 'active') desc, s.step_order limit 1;
  end if;

  if not v_authorized and v_step.id is not null and v_step.assignee_employee_id = v_me then
    v_authorized := true;
  end if;

  if not v_authorized then
    raise exception 'not_authorized_for_step' using errcode = '42501';
  end if;

  v_actor_role := case
    when v_is_exec then 'executive'
    when v_is_clinic_mgr then 'clinic_manager'
    when v_is_direct_mgr then 'direct_manager'
    when v_is_operations then 'operations_manager'
    when v_is_hr then 'hr_manager'
    else 'approver'
  end;

  v_actor_role_name := case
    when v_is_exec then 'المدير التنفيذي'
    when v_is_clinic_mgr then 'مدير العيادات'
    when v_is_direct_mgr then 'المدير المباشر'
    when v_is_operations then 'مدير التشغيل 1 (أبو عمار)'
    when v_is_hr then 'إدارة الموارد البشرية'
    else 'المعتمد'
  end;

  -- ─── قرار الإرجاع للتعديل ───
  if v_decision = 'return' then
    if v_step.id is not null then
      update public.request_steps
      set status = 'returned', acted_at = now(), acted_by = v_me, comment = p_comment, updated_at = now()
      where id = v_step.id;
    end if;

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, 'return', v_req.status, 'returned', p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = 'returned',
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    perform public.notify_employee(
      v_req.employee_id,
      'طلبك بحاجة لتعديل',
      coalesce(v_req.title, '') || ' — تم إرجاعه بواسطة ' || v_actor_role_name || ': ' || coalesce(p_comment, ''),
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', 'returned', 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- ─── قرار الرفض ───
  if v_decision = 'reject' then
    if v_step.id is not null then
      update public.request_steps
      set status = 'rejected', acted_at = now(), acted_by = v_me, comment = p_comment, updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'skipped', updated_at = now()
    where request_id = p_request_id and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and status in ('active', 'pending', 'escalated');

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, 'reject', v_req.status, 'rejected', p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = 'rejected',
        workflow_status = 'terminated',
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        begin
          perform public.decide_attendance_correction(v_correction_id, 'rejected', coalesce(p_comment, 'مرفوض'));
        exception when others then
          update public.attendance_corrections
          set status = 'rejected', reviewed_by = v_me, reviewed_at = now(), review_note = p_comment, updated_at = now()
          where id = v_correction_id;
        end;
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      'تم رفض طلبك',
      coalesce(v_req.title, '') || ' — تم الرفض بواسطة ' || v_actor_role_name || case when p_comment is not null then ': ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', 'rejected', 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- ─── قرار الاعتماد (approve) ───
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  -- تخطي سائر الخطوات لأن الاعتماد نهائي ونافذ
  update public.request_steps
  set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and status in ('active', 'pending', 'escalated');

  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = p_comment,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- إشعار صاحب الطلب
  perform public.notify_employee(
    v_req.employee_id,
    'تم اعتماد طلبك بنجاح',
    coalesce(v_req.title, '') || ' — اعتمد بواسطة ' || v_actor_role_name,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'requestId', v_req.id)
  );

  -- إذا بتّ فيه المدير المباشر وكان الطلب قد صُعِّد لأبو عمار، نشعر أبو عمار بأن الطلب انتهى بالاعتماد
  if v_is_direct_mgr and v_req.workflow_status = 'awaiting_operator' then
    v_ops_emp := public.first_active_employee_for_role('operations-manager-1');
    if v_ops_emp is not null and v_ops_emp <> v_me then
      perform public.notify_employee(
        v_ops_emp,
        'تم البت في طلب مصعّد بواسطة المدير المباشر',
        coalesce(v_req.title, '') || ' — تم اعتماده مباشرة بواسطة المدير المباشر.',
        'request', 'normal', 'request', v_req.id
      );
    end if;
  end if;

  return v_req;
end;
$$;

-- 5) تحديث process_request_sla لتطبيق مهلة الساعتين والتصعيد لأبو عمار
create or replace function public.process_request_sla(p_limit integer default 200)
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_count      integer := 0;
  v_row        record;
  v_next       record;
  v_ops_emp    uuid;
  v_target     uuid;
  v_role       text;
  v_today      date := (now() at time zone 'Africa/Cairo')::date;
  v_due        boolean;
begin
  if auth.role() <> 'service_role' and not public.current_is_full_access() then
    raise exception 'PERMISSION_DENIED' using errcode = '42501';
  end if;

  v_ops_emp := public.first_active_employee_for_role('operations-manager-1');
  if v_ops_emp is null then
    v_ops_emp := '767eae8e-e7be-458e-a6ca-879414e46b08'::uuid; -- محمد عبدالباسط (أبو عمار)
  end if;

  for v_row in
    select
      rs.id          as step_id,
      rs.request_id,
      rs.step_order,
      rs.status      as step_status,
      rs.assignee_employee_id,
      rs.escalation_deadline,
      r.employee_id,
      r.manager_employee_id,
      r.title,
      r.request_type,
      r.workflow_definition_id
    from public.request_steps rs
    join public.requests r on r.id = rs.request_id
    where r.status = 'pending'
      and rs.status in ('active', 'escalated')
      and rs.escalation_deadline is not null
      and rs.escalation_deadline < now()
    order by rs.escalation_deadline nulls first
    limit greatest(1, least(coalesce(p_limit, 200), 2000))
    for update of rs skip locked
  loop
    -- استثناء طاقم العيادات
    if public.is_clinic_team_member(v_row.employee_id)
       or v_row.manager_employee_id = '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'
       or exists (
         select 1 from public.workflow_definitions wd
         where wd.id = v_row.workflow_definition_id
           and wd.code like 'medical_%'
       ) then
      update public.request_steps
        set escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- الخطوة النهائية (أبو عمار أو أي مرحلة >= 2): لا ترقية أبعد
    if v_row.step_order >= 2 then
      if v_ops_emp is not null then
        update public.request_steps
          set assignee_employee_id = coalesce(assignee_employee_id, v_ops_emp),
              assignee_role_slug   = 'operations-manager-1',
              updated_at = now()
        where id = v_row.step_id;

        perform public.notify_employee(
          v_ops_emp,
          'تذكير: طلب لم يُبتَّ فيه بعد',
          coalesce(v_row.title, '') || ' — يحتاج قرارك الآن. الطلب محوَّل لك كقرار نهائي.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'final_reminder',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      update public.request_steps
        set escalation_deadline = now() + interval '24 hours', updated_at = now()
      where id = v_row.step_id;
      continue;
    end if;

    -- الخطوة 1 (المدير المباشر): تصعيد إلى الخطوة 2 (مدير التشغيل 1 - أبو عمار)
    select * into v_next
    from public.request_steps
    where request_id = v_row.request_id
      and step_order = v_row.step_order + 1
    limit 1;

    update public.request_steps
      set status = 'escalated',
          escalated_at = coalesce(escalated_at, now()),
          escalation_deadline = null,
          updated_at = now()
    where id = v_row.step_id;

    if v_next.id is not null then
      v_target := v_ops_emp;
      v_role   := 'operations-manager-1';

      update public.request_steps
        set status = 'active',
            assignee_employee_id = coalesce(v_target, assignee_employee_id),
            assignee_role_slug = coalesce(v_role, assignee_role_slug),
            due_at = now() + interval '2 hours',
            escalation_deadline = now() + interval '2 hours',
            updated_at = now()
      where id = v_next.id;

      update public.workflow_instances
        set current_step_order = v_next.step_order, updated_at = now()
      where request_id = v_row.request_id and status = 'running';

      update public.requests
        set workflow_status = 'awaiting_operator',
            escalated_at = coalesce(escalated_at, now()),
            decision_due_at = now() + interval '2 hours',
            updated_at = now()
      where id = v_row.request_id;

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata
      ) values (
        v_row.request_id, null, 'escalate', 'pending', 'pending',
        'تصعيد تلقائي — تجاوز مهلة البت للمدير المباشر (ساعتان)',
        jsonb_build_object('tier', v_next.step_order, 'targetRole', v_role)
      );

      if v_target is not null then
        perform public.notify_employee(
          v_target,
          'طلب محوَّل إليك — مدير التشغيل 1 (أبو عمار)',
          coalesce(v_row.title, '') || ' — تجاوز مهلة المدير المباشر (ساعتان)، يمكنك البت فيه الآن.',
          'request', 'high', 'request', v_row.request_id,
          jsonb_build_object(
            'escalation', 'timeout_tier1',
            'deepLink', '/requests/' || v_row.request_id
          )
        );
      end if;

      -- إشعار المدير المباشر بالتصعيد مع تذكيره بحقه في البت
      if v_row.manager_employee_id is not null then
        perform public.notify_employee(
          v_row.manager_employee_id,
          'تم تصعيد طلب إلى مدير التشغيل (أبو عمار)',
          coalesce(v_row.title, '') || ' — انقضت مهلة الساعتين وصُعّد لمدير التشغيل، وما زال بإمكانك قبوله أو رفضه.',
          'request', 'normal', 'request', v_row.request_id,
          jsonb_build_object('deepLink', '/requests/' || v_row.request_id)
        );
      end if;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

-- 6) تحديث الطلبات المعلقة الحالية لتطبيق مهلة الساعتين
update public.requests r
set decision_due_at = r.created_at + interval '2 hours',
    escalation_deadline = r.created_at + interval '2 hours'
where r.status = 'pending'
  and r.workflow_status in ('submitted', 'in_review');

update public.request_steps s
set due_at = s.created_at + interval '2 hours',
    escalation_deadline = s.created_at + interval '2 hours'
from public.requests r
where s.request_id = r.id
  and r.status = 'pending'
  and s.step_order = 1
  and s.status = 'active';

commit;
