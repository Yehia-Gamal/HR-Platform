-- ===========================================================================
-- 0706: إصلاح مسار الاعتماد واعتماد مدير الموارد البشرية وإزالة تكرار الخطوات
-- ===========================================================================
-- المشكلات المعالجة:
-- 1) اعتماد مدير الموارد البشرية (يحيى جمال السبع) أو الإدارة العليا كان يُحدّث كافة
--    خطوات الطلب (المدير المباشر + مدير التشغيل 1) إلى approved بنفس المعتمِد ونفس
--    التعليق ونفس التوقيت، مما يسبب ظهور اعتماد مكرر ومضلل في سجل المسار.
-- 2) إتاحة استثناء مدير الموارد البشرية (v_is_hr) لإنهاء واعتماد الطلب فوراً في أي خطوة.
-- 3) تعيين حالة الخطوات اللاحقة غير المنجزة إلى 'skipped' (لم يلزم) دون إسناد
--    فاعل أو تعليق مكرر عليها، لتعرض الشارة «لم يلزم» بشكل سليم في شريط المراحل
--    ولا يظهر لها حدث قرار في الخط الزمني (Timeline).
-- 4) توثيق مسمى المعتمِد الفعلي («الموارد البشرية» عند اعتماد HR) بدلاً من نسبة
--    الاعتماد لـ «المدير المباشر» خطأً.
-- 5) إصلاح استرجاعي للطلبات القائمة التي تكررت فيها خطوات الاعتماد بنفس المعتمِد والتعليق.
-- ===========================================================================

begin;

-- ─── 1) تحديث decide_request لإنهاء الطلب عند اعتماد HR ووسم الخطوات الأخرى بـ skipped ───
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
  v_actor_role_name text;
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

  -- الصلاحية الشاملة لاعتماد الطلبات (تشمل الإدارة التنفيذية وإدارة الموارد البشرية والتشغيلية والمدير المباشر)
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

  -- تحديد الدور الفعلي لمتخذ القرار واسمه الوظيفي الواضح
  if public.current_is_full_access() or public.current_has_active_role(array['admin','super-admin']) then
    v_actor_role := 'admin';
    v_actor_role_name := 'إدارة النظام';
  elsif v_is_hr then
    v_actor_role := 'hr-manager';
    v_actor_role_name := 'الموارد البشرية';
  elsif v_is_exec then
    v_actor_role := 'executive';
    v_actor_role_name := 'المدير التنفيذي';
  elsif v_is_operations then
    v_actor_role := 'operations-manager-1';
    v_actor_role_name := 'مدير التشغيل 1';
  elsif v_is_direct_mgr then
    v_actor_role := 'direct_manager';
    v_actor_role_name := 'المدير المباشر';
  else
    v_actor_role := 'manager';
    v_actor_role_name := 'المعتمِد';
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

    if v_step.id is not null then
      update public.request_steps
      set status = v_final_status,
          acted_at = now(),
          acted_by = v_me,
          comment = p_comment,
          updated_at = now()
      where id = v_step.id;
    end if;

    update public.request_steps
    set status = 'skipped',
        updated_at = now()
    where request_id = p_request_id
      and (v_step.id is null or id <> v_step.id)
      and status in ('active', 'escalated', 'pending');

    update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, p_decision, 'pending', v_final_status, p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
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
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  -- فحص ما إذا كان الطلب يحتاج خطوة لاحقة:
  -- القاعدة 1: إذا اعتمد المدير التنفيذي أو الأدمن أو مدير الموارد البشرية أو مدير التشغيل في أي مرحلة -> يُعتمد نهائياً فوراً
  -- القاعدة 2: إذا اعتمد المدير المباشر طلباً تصعّد بالفعل للمرحلة 2 أو أعلى -> يُعتمد نهائياً فوراً
  -- خلاف ذلك (إذا كان المدير المباشر فقط يعتمد المرحلة 1 وتوجد مرحلة 2 متبقية): تُنشّط المرحلة 2
  if exists (
    select 1 from public.request_steps
    where request_id = p_request_id
      and step_order > v_current_step
      and status = 'pending'
  ) and not (public.current_is_full_access() or v_is_exec or v_is_hr or v_is_operations) then
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

  -- اعتماد نهائي للطلب:
  -- أ) الخطوة التي بُتّ فيها: تُعتمد مع الفاعل الفعلي والتعليق
  if v_step.id is not null then
    update public.request_steps
    set status = 'approved',
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        updated_at = now()
    where id = v_step.id;
  end if;

  -- ب) الخطوات المتبقية الأخرى في المسار التي تم تجاوزها أو لم تلزم:
  -- تُسجّل كـ 'skipped' (لم يلزم) دون تكرار فاعل أو تعليق عليها منعاً للازدواجية في السجل
  update public.request_steps
  set status = 'skipped',
      acted_at = null,
      acted_by = null,
      comment = null,
      updated_at = now()
  where request_id = p_request_id
    and (v_step.id is null or id <> v_step.id)
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
  '0706: إصلاح ازدواجية خطوات الاعتماد — وسم المراحل غير الممارسة بـ skipped وتوثيق صفة المعتمِد بدقة.';

-- ─── 2) تحديث get_mobile_request_detail لقراءة صفة المعتمِد الفعلية من الإجراء ───
create or replace function public.get_mobile_request_detail(p_request_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_request            public.requests;
  v_employee           public.employees;
  v_department         text;
  v_job_title          text;
  v_flags              jsonb;
  v_current_step       uuid;
  v_steps              jsonb;
  v_history            jsonb;
  v_attachments        jsonb;
  v_context            jsonb;
  v_decided_by         text;
  v_cancelled_by       text;
  v_decision_actor     text;
  v_decision_mode      text;
  v_decision_on_behalf boolean;
  v_execution          jsonb;
begin
  select * into v_request from public.requests where id = p_request_id;
  if v_request.id is null then
    return null;
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  if not coalesce(
       v_request.employee_id = v_me
    or v_request.manager_employee_id = v_me
    or exists (
         select 1 from public.manager_relations mr
          where mr.employee_id = v_request.employee_id
            and mr.manager_employee_id = v_me
            and mr.relation_type = 'primary'
            and mr.effective_from <= current_date
            and (mr.effective_to is null or mr.effective_to >= current_date))
    or exists (
         select 1 from public.request_steps s
          where s.request_id = v_request.id and s.assignee_employee_id = v_me)
    or v_full
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'operations-manager-1']
    or public.can_access_employee(v_request.employee_id, 'requests.request.approve')
    or public.can_access_employee(v_request.employee_id, 'requests.request.read')
    or public.can_access_employee(v_request.employee_id, 'requests.read')
    or public.can_access_employee(v_request.employee_id, 'requests.approve'),
    false
  ) then
    raise exception 'request access denied' using errcode = '42501';
  end if;

  select * into v_employee from public.employees where id = v_request.employee_id;
  select d.name into v_department from public.departments d where d.id = v_employee.department_id;
  select jt.name into v_job_title from public.job_titles jt where jt.id = v_employee.job_title_id;

  v_flags := public.request_decision_flags(v_request, v_me, v_full, v_roles);

  if v_request.status = 'pending' then
    select s.id into v_current_step
      from public.request_steps s
     where s.request_id = v_request.id
       and s.status in ('active', 'escalated', 'pending')
     order by (s.status = 'active') desc, s.step_order
     limit 1;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'order', s.step_order,
           'name', s.name_ar,
           'roleSlug', s.assignee_role_slug,
           'status', s.status,
           'decision', case
               when s.status = 'approved' then 'approved'
               when s.status = 'rejected' and v_request.status = 'returned' then 'returned'
               when s.status = 'rejected' then 'rejected'
             end,
           'comment', case when s.status in ('approved', 'rejected') then nullif(trim(s.comment), '') end,
           'decidedAt', case when s.status in ('approved', 'rejected') then s.acted_at end,
           'actorName', case when s.status in ('approved', 'rejected') then actor.full_name_ar end,
           'dueAt', s.due_at,
           'escalatedAt', s.escalated_at,
           'isCurrent', s.id is not distinct from v_current_step
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = p_request_id;

  with base as (
    select a.*,
           sum((a.action = 'submit')::int) over (
             order by a.created_at, a.id
             rows between unbounded preceding and current row) as cycle_no
      from public.request_actions a
     where a.request_id = p_request_id
       and a.action in ('submit', 'approve', 'reject', 'return', 'request_changes',
                        'cancel', 'withdraw', 'escalate', 'expire', 'reassign')
  ),
  ranked as (
    select b.*,
           row_number() over w as rn,
           count(*) over w as cnt
      from base b
    window w as (
      partition by b.cycle_no, b.action,
                   coalesce(b.metadata->>'targetRole', b.metadata->>'escalatedToRole', '')
      order by b.created_at, b.id
      rows between unbounded preceding and unbounded following)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'action', x.action,
           'at', x.created_at,
           'actorName', case when x.action in ('escalate', 'expire') then null else actor.full_name_ar end,
           'comment', case when x.action in ('approve', 'reject', 'return', 'request_changes',
                                             'cancel', 'withdraw', 'reassign')
                           then nullif(trim(x.comment), '') end,
           'stepOrder', st.step_order,
           'stepName', case
             when x.metadata->>'roleName' is not null then x.metadata->>'roleName'
             when x.metadata->>'role' in ('hr', 'hr-manager', 'hr-specialist', 'hr-officer') then 'الموارد البشرية'
             when x.metadata->>'role' in ('executive', 'executive-director', 'general-manager') then 'المدير التنفيذي'
             when x.metadata->>'role' in ('operations', 'operations-manager-1', 'operations-manager') then 'مدير التشغيل 1'
             when x.metadata->>'role' = 'direct_manager' then 'المدير المباشر'
             else st.name_ar
           end,
           'stepRole', coalesce(x.metadata->>'role', st.assignee_role_slug),
           'targetRole', coalesce(x.metadata->>'targetRole', x.metadata->>'escalatedToRole'),
           'repeat', case when x.action = 'escalate' then x.cnt end,
           'isResubmit', x.action = 'submit' and x.from_status in ('rejected', 'returned')
         ) order by x.created_at, x.id), '[]'::jsonb)
    into v_history
    from ranked x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.action <> 'escalate' or x.rn = 1;

  select coalesce(jsonb_agg(jsonb_build_object(
           'path', a.storage_path, 'mimeType', a.mime, 'sizeBytes', a.size_bytes
         ) order by a.created_at), '[]'::jsonb)
    into v_attachments
    from public.attachments a
   where a.entity_type = 'request' and a.entity_id = p_request_id;

  begin
    v_context := public.get_request_decision_context(p_request_id);
  exception when others then
    v_context := null;
  end;

  select e.full_name_ar into v_decided_by from public.employees e where e.id = v_request.decided_by;
  select e.full_name_ar into v_cancelled_by from public.employees e where e.id = v_request.cancelled_by;

  select e.full_name_ar, a.metadata->>'decisionMode',
         coalesce((a.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions a
    left join public.employees e on e.id = a.actor_employee_id
   where a.request_id = p_request_id and a.action in ('approve', 'reject', 'return')
   order by a.created_at desc
   limit 1;

  if v_request.request_type in ('mission', 'convoy', 'fundraising') then
    select to_jsonb(me) into v_execution from (
      select me.id, me.status,
             me.started_at as "startedAt",
             me.ended_at as "endedAt",
             me.actual_minutes as "actualMinutes",
             me.report, me.outcome
        from public.mission_executions me
       where me.request_id = v_request.id
    ) me;
  end if;

  return jsonb_build_object(
    'id', v_request.id,
    'requestNumber', v_request.request_number,
    'requestType', v_request.request_type,
    'employeeId', v_request.employee_id,
    'employeeName', v_employee.full_name_ar,
    'employeeCode', v_employee.employee_code,
    'employeePhotoUrl', v_employee.photo_url,
    'employeeDepartment', v_department,
    'employeeJobTitle', v_job_title,
    'title', v_request.title,
    'reason', v_request.reason,
    'status', v_request.status,
    'workflowStatus', v_request.workflow_status,
    'payload', coalesce(v_request.payload, '{}'::jsonb),
    'currentStepOrder', v_request.current_step_order,
    'decisionDueAt', v_request.decision_due_at,
    'createdAt', v_request.created_at,
    'updatedAt', v_request.updated_at,
    'decidedAt', v_request.decided_at,
    'decidedByName', v_decided_by,
    'cancelledAt', v_request.cancelled_at,
    'cancelReason', v_request.cancel_reason,
    'cancelledByName', v_cancelled_by,
    'canDecide', coalesce((v_flags->>'canDecide')::boolean, false),
    'canCancel', coalesce(v_request.status = 'pending' and v_request.employee_id = v_me, false),
    'canResubmit', coalesce(v_request.status in ('rejected', 'returned')
                            and v_request.employee_id = v_me
                            and v_request.request_type in ('leave', 'mission', 'convoy', 'fundraising',
                                                           'late_permit', 'early_permit', 'attendance_permit', 'attendance_correction'), false),
    'awaitingMe', coalesce((v_flags->>'awaitingMe')::boolean, false),
    'isMine', coalesce(v_request.employee_id = v_me, false),
    'steps', v_steps,
    'history', v_history,
    'attachments', v_attachments,
    'decisionContext', v_context,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;

revoke all on function public.get_mobile_request_detail(uuid) from public, anon;
grant execute on function public.get_mobile_request_detail(uuid) to authenticated;
comment on function public.get_mobile_request_detail(uuid) is
  '0706: تفاصيل الطلب مع قراءة مسمى دور المعتمِد الفعلي (الموارد البشرية/التنفيذي/العمليات) من metadata الإجراء.';

-- ─── 3) إصلاح استرجاعي للطلبات التي تكررت فيها خطوات الاعتماد لنفس الشخص بنفس التعليق ───
update public.request_steps s2
set status = 'skipped',
    acted_by = null,
    comment = null,
    acted_at = null,
    updated_at = now()
from public.request_steps s1
where s1.request_id = s2.request_id
  and s1.step_order < s2.step_order
  and s1.status = 'approved'
  and s2.status = 'approved'
  and s1.acted_by = s2.acted_by
  and s1.acted_at is not null
  and s2.acted_at is not null
  and abs(extract(epoch from (s1.acted_at - s2.acted_at))) <= 120
  and coalesce(s1.comment, '') = coalesce(s2.comment, '');

commit;
