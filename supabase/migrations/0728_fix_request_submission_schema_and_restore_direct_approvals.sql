-- ============================================================================
-- 0728_fix_request_submission_schema_and_restore_direct_approvals.sql
--
-- 1. إصلاح دالة _submit_request_for وتصحيح أسماء أعمدة workflow_steps:
--    - ws.approver_type (بدلاً من ws.assignee_type غير الموجود)
--    - ws.approver_employee_id (بدلاً من ws.specific_employee_id)
--    - ws.approver_role_slug (بدلاً من ws.role_slug)
--    - (ws.escalate_after_hours is not null) (بدلاً من ws.auto_escalate)
--    - workflow_instances (definition_id, request_id, definition_version, ...)
--    - requests: ضبط current_step_order = 1 (بدلاً من current_step_id غير الموجود)
--    - حساب مهلة تشغيلية عادلة ومحمية (لا تقل عن 24 ساعة عمل رسمية) ومنع تصعيد الـ 5 دقائق.
--
-- 2. تحديث decide_request لتمكين المديرين المباشرين من البت في طلبات موظفيهم دائماً،
--    وتحديث سجل الخطوة request_steps بوضوح عند الاعتماد (status = 'approved').
--
-- 3. إلغاء التصعيد الخاطئ واستعادة الطلبات الـ 13 التي صُعّدت ظلماً بعد دقائق قليلة:
--    - إعادة الخطوة الأولى إلى 'active' وحذف وسم "صُعّد لتأخر الرد".
--    - إعادة الخطوة الثانية إلى 'pending'.
--    - تصفير إجراءات التصعيد الخاطئة من request_actions.
--
-- 4. إسناد دور 'direct-manager' في user_roles لـ أ/ عبد القادر جمال عبد القادر
--    ولكافة المديرين المعتمدين في manager_relations.
-- ============================================================================

-- ─── 1) تصحيح دالة _submit_request_for ───
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
  v_me               uuid := public.current_employee_id();
  v_def              public.workflow_definitions;
  v_due              timestamptz;
  v_esc              timestamptz;
  v_row              public.requests;
  v_first_approver   uuid;
  v_label            text;
  v_title_approver   text;
  v_is_clinic        boolean := false;
  v_is_mgr_executive boolean := false;
  v_emp_name         text;
  v_two_names        text;
  v_req_label        text;
  v_ops_emp          uuid;
  v_sla_hours        integer := 24;
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

  select e.full_name_ar into v_emp_name from public.employees e where e.id = p_employee_id;
  v_two_names := trim(split_part(coalesce(v_emp_name, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_name, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_name, ''), 'موظف');
  end if;
  v_req_label := public.request_type_label(p_request_type);

  -- فحص طاقم العيادات المقيد
  v_is_clinic := public.is_clinic_staff_restricted_from_field(p_employee_id);

  -- تحديد المدير المعتمد
  if v_is_clinic then
    if p_manager_employee_id is null or p_manager_employee_id not in (
         '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
         'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
       ) then
      p_manager_employee_id := coalesce(
        public.resolve_request_approver(p_employee_id),
        '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid
      );
    end if;
  elsif p_manager_employee_id is null or p_manager_employee_id = p_employee_id then
    p_manager_employee_id := public.resolve_request_approver(p_employee_id);
  end if;

  -- فحص إذا كان المدير المباشر هو المدير التنفيذي
  v_is_mgr_executive := (
    p_manager_employee_id = '7b0740fa-66ba-4616-8674-3dbd8e14109e'::uuid
    or public.is_employee_executive(p_manager_employee_id)
  );

  -- التعرف التلقائي لتعريف سير العمل
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    if v_is_clinic then
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

  -- حساب المهلة التشغيلية العادلة بساعات العمل الرسمية (لا تقل عن 24 ساعة عمل)
  v_sla_hours := case
    when v_is_mgr_executive then 24
    else coalesce(v_def.default_due_hours, 24)
  end;
  if v_sla_hours < 24 then
    v_sla_hours := 24; -- حماية من المهل شديدة الضيق
  end if;

  v_due := public.calculate_business_deadline(now(), v_sla_hours);

  if coalesce(v_def.auto_escalate, false) and not v_is_clinic then
    -- التصعيد بعد 24 ساعة عمل إضافية من انتهاء مهلة البت
    v_esc := public.calculate_business_deadline(now(), v_sla_hours + 24);
  else
    v_esc := null;
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    current_step_order, payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    1, coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

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
      case
        when ws.approver_type in ('direct_manager', 'department_manager') then p_manager_employee_id
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type = 'operator' then public.first_active_employee_for_role('operations-manager-1')
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case
        when ws.step_order = 1 then v_due
        else null
      end,
      case
        when ws.step_order = 1 and ws.escalate_after_hours is not null and not v_is_clinic then v_esc
        else null
      end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  -- تحديد أول معتمد لإرسال الإشعار
  select rs.assignee_employee_id into v_first_approver
  from public.request_steps rs
  where rs.request_id = v_row.id and rs.step_order = 1;

  if v_first_approver is null then
    v_first_approver := p_manager_employee_id;
  end if;

  -- إرسال إشعار للمعتمد الأول
  if v_first_approver is not null and v_first_approver <> p_employee_id then
    v_title_approver := coalesce(v_two_names, 'موظف') || ' — طلب ' || coalesce(v_req_label, 'جديد');
    perform public.notify_employee(
      v_first_approver,
      'طلب جديد ينتظر قرارك',
      v_title_approver || ': ' || coalesce(p_title, v_req_label),
      'request', 'normal', 'request', v_row.id,
      jsonb_build_object(
        'requestId', v_row.id,
        'requestType', p_request_type,
        'employeeId', p_employee_id,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;

revoke all on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to authenticated, service_role;

-- ─── 2) تحديث decide_request بمرونة كاملة للمديرين المباشرين ───
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
  v_eff_date        date;
  v_chk_start       date;
  v_chk_end         date;
  v_cancelled_pens  int := 0;
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
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
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

  select s.* into v_step
  from public.request_steps s
  where s.request_id = p_request_id and s.status in ('active','escalated')
  order by (s.status = 'active') desc, s.step_order limit 1;

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
    when v_is_operations then 'مدير العمليات'
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

  -- تنفيذ الآثار الجانبية التلقائية للاعتماد:
  -- أ) إعفاء وإلغاء الغرامات فوراً لطلبات الفاندي الترفيهي، المأموريات، الإجازات، والقوافل
  if v_req.request_type in (
    'fundraising', 'fandy', 'fundi',
    'mission', 'external_mission', 'administrative_mission',
    'convoy', 'field_convoy',
    'leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave',
    'remote_work', 'compensation'
  ) or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy', 'convoy', 'mission') then
    v_chk_start := coalesce(
      public.try_cast_date(v_req.payload->>'startDate'),
      public.try_cast_date(v_req.payload->>'start_date'),
      v_req.created_at::date
    );
    v_chk_end := coalesce(
      public.try_cast_date(v_req.payload->>'endDate'),
      public.try_cast_date(v_req.payload->>'end_date'),
      v_chk_start
    );

    if v_chk_start is not null and v_chk_end is not null then
      update public.instant_attendance_penalties
         set status = 'cancelled',
             cancelled_reason = 'اعتماد طلب رسمي (' ||
               case
                 when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy')
                   then 'فاندي ترفيهي'
                 when v_req.request_type in ('mission', 'external_mission') or coalesce(v_req.payload->>'missionType', '') = 'mission'
                   then 'مأمورية عمل'
                 when v_req.request_type in ('convoy', 'field_convoy')
                   then 'قافلة ميدانية'
                 when v_req.request_type like '%leave%'
                   then 'إجازة معتمدة'
                 else v_req.request_type
               end || ') يغطي هذا اليوم',
             notes = coalesce(notes || ' | ', '') || 'أُلغيت الغرامة تلقائياً لاعتماد طلب ' ||
               case
                 when v_req.request_type in ('fundraising', 'fandy', 'fundi') or coalesce(v_req.payload->>'missionType', '') in ('fundraising', 'fandy')
                   then 'فاندي ترفيهي'
                 else v_req.request_type
               end,
             updated_at = now()
       where employee_id = v_req.employee_id
         and work_date between v_chk_start and v_chk_end
         and status in ('pending_payment', 'doubled', 'suspended');

      get diagnostics v_cancelled_pens = row_count;
    end if;
  end if;

  -- ب) إسقاط الغرامات عند إكمال 8 ساعات عمل أو اعتماد أذونات
  if v_req.request_type in ('early_permit', 'late_permit', 'attendance_permit', 'permit') then
    v_eff_date := coalesce(
      public.try_cast_date(v_req.payload->>'permitDate'),
      public.try_cast_date(v_req.payload->>'date'),
      public.try_cast_date(v_req.payload->>'startDate'),
      v_req.created_at::date
    );
    begin
      if v_eff_date is not null then
        perform public.auto_waive_penalty_if_completed_eight_hours(v_req.employee_id, v_eff_date);
      end if;
    exception when others then
      null;
    end;
  end if;

  -- ج) تصحيح البصمة
  if v_req.request_type = 'attendance_correction' then
    v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
    if v_correction_id is not null then
      begin
        perform public.decide_attendance_correction(v_correction_id, 'approved', coalesce(p_comment, 'معتمد مع الطلب'));
      exception when others then
        update public.attendance_corrections
        set status = 'approved',
            reviewed_by = coalesce(reviewed_by, v_me),
            reviewed_at = coalesce(reviewed_at, now()),
            review_note = coalesce(review_note, p_comment)
        where id = v_correction_id;
      end;
    end if;
  end if;

  -- د) تنشيط الإجازة
  if v_req.request_type = 'leave' then
    begin
      perform public.activate_approved_leave(v_req.id);
    exception when others then
      null;
    end;
  end if;

  -- إشعار الموظف بالاعتماد
  perform public.notify_employee(
    v_req.employee_id,
    '🎉 تم اعتماد طلبك بنجاح',
    coalesce(v_req.title, '') || ' — تم الاعتماد بواسطة ' || v_actor_role_name ||
      case when v_cancelled_pens > 0 then ' (وتم إسقاط غرامات التأخير لهذا اليوم تلقائياً)' else '' end,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'requestId', v_req.id, 'penaltiesCancelled', v_cancelled_pens)
  );

  return v_req;
end;
$$;

revoke all on function public.decide_request(uuid, text, text) from public, anon;
grant execute on function public.decide_request(uuid, text, text) to authenticated, service_role;

-- ─── 3) إلغاء التصعيد الخاطئ واستعادة الطلبات الـ 13 المعلقة ───
do $$
declare
  r record;
begin
  for r in (
    select id, employee_id, created_at
    from public.requests
    where status = 'pending'
      and workflow_status = 'awaiting_operator'
      and created_at >= (now() - interval '7 days')
  ) loop
    -- إعادة حالة الطلب إلى 'submitted' وإلغاء وقت التصعيد
    update public.requests
       set workflow_status = 'submitted',
           escalated_at = null,
           decision_due_at = public.calculate_business_deadline(r.created_at, 48),
           escalation_deadline = public.calculate_business_deadline(r.created_at, 72),
           updated_at = now()
     where id = r.id;

    -- إعادة الخطوة 1 (المدير المباشر) لتصبح نشطة
    update public.request_steps
       set status = 'active',
           escalated_at = null,
           acted_at = null,
           acted_by = null,
           comment = null,
           due_at = public.calculate_business_deadline(r.created_at, 48),
           escalation_deadline = public.calculate_business_deadline(r.created_at, 72),
           updated_at = now()
     where request_id = r.id and step_order = 1;

    -- إعادة الخطوة 2 لتصبح pending
    update public.request_steps
       set status = 'pending',
           acted_at = null,
           acted_by = null,
           comment = null,
           updated_at = now()
     where request_id = r.id and step_order = 2;

    -- حذف إجراء التصعيد الخاطئ من سجل الأحداث لتطهير مسار الاعتماد
    delete from public.request_actions
     where request_id = r.id and action = 'escalate';
  end loop;
end;
$$;

-- ─── 4) إسناد دور direct-manager لـ أ/ عبد القادر جمال عبد القادر وكافة المديرين المعتمدين ───
do $$
declare
  v_role_id uuid;
  r record;
begin
  select id into v_role_id from public.roles where slug = 'direct-manager' limit 1;
  if v_role_id is not null then
    -- إسناد الدور لـ عبد القادر جمال
    insert into public.user_roles (user_id, role_id)
    values ('0681bcac-9d5b-4be4-ae8a-4dddd83c07be'::uuid, v_role_id)
    on conflict (user_id, role_id) do nothing;

    -- إسناد الدور لأي مدير مسجل في manager_relations ولديه حساب
    for r in (
      select distinct p.id as user_id
      from public.manager_relations mr
      join public.profiles p on p.employee_id = mr.manager_employee_id
    ) loop
      insert into public.user_roles (user_id, role_id)
      values (r.user_id, v_role_id)
      on conflict (user_id, role_id) do nothing;
    end loop;
  end if;
end;
$$;
