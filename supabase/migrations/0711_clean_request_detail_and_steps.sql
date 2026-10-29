-- ==============================================================================
-- 0711_clean_request_detail_and_steps.sql
-- ضبط دالة get_mobile_request_detail وdecide_request لتتطابق مع أعمدة request_steps
-- وتحقيق نجاح 100% في الفحص الصحي run_system_health_check
-- ==============================================================================

begin;

-- ─── 1) تحديث decide_request ─────────────────────────────────────────────────
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
  v_req public.requests;
  v_step public.request_steps;
  v_me uuid := public.current_employee_id();
  v_decision text;
  v_final_status text;
  v_actor_role text;
  v_actor_role_name text;
  v_is_exec boolean := false;
  v_is_hr boolean := false;
  v_is_ops1 boolean := false;
  v_is_direct_mgr boolean := false;
  v_correction_id uuid;
  v_eff_date date;
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
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status not in ('pending', 'under_review') then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;

  v_is_exec := public.current_has_active_role(array['executive','executive-director','general-manager','executive-secretary']);
  v_is_hr   := public.current_has_active_role(array['hr-manager','hr-specialist','hr-officer'])
               or public.current_is_full_access()
               or public.current_has_active_role(array['admin','super-admin']);
  v_is_ops1 := public.current_has_active_role(array['operations-manager-1']);

  v_is_direct_mgr := (
    v_req.manager_employee_id = v_me
    or exists (
      select 1 from public.manager_relations mr
      where mr.employee_id = v_req.employee_id
        and mr.manager_employee_id = v_me
        and mr.relation_type = 'primary'
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
    )
    or exists (
      select 1 from public.request_steps s
      where s.request_id = v_req.id
        and s.assignee_employee_id = v_me
        and s.status in ('active', 'pending', 'escalated')
    )
  );

  if not (auth.role() = 'service_role' or v_is_exec or v_is_hr or v_is_ops1 or v_is_direct_mgr) then
    raise exception 'غير مصرح لك باتخاذ قرار بشأن هذا الطلب' using errcode = '42501';
  end if;

  if v_req.employee_id = v_me and not (auth.role() = 'service_role' or public.current_is_full_access()) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active', 'escalated', 'pending')
  order by (status = 'active') desc, step_order asc
  limit 1;

  if v_step.id is null then
    select * into v_step
    from public.request_steps
    where request_id = p_request_id
    order by step_order desc
    limit 1;
  end if;

  v_actor_role := case
    when auth.role() = 'service_role' then 'service_role'
    when v_is_exec then 'executive'
    when v_is_hr then 'hr'
    when v_is_ops1 then 'operations_manager'
    when v_is_direct_mgr then 'direct_manager'
    else 'authorized_actor'
  end;

  v_actor_role_name := case
    when v_actor_role = 'executive' then 'المدير التنفيذي'
    when v_actor_role = 'hr' then 'الموارد البشرية'
    when v_actor_role = 'operations_manager' then 'مدير العمليات'
    when v_actor_role = 'direct_manager' then 'المدير المباشر'
    else 'معتمد معتمد'
  end;

  if v_step.id is not null then
    update public.request_steps
    set status = case
          when v_decision = 'approve' then 'approved'
          when v_decision = 'reject' then 'rejected'
          when v_decision = 'return' then 'rejected'
        end,
        acted_at = now(),
        acted_by = v_me,
        comment = p_comment,
        assignee_employee_id = coalesce(assignee_employee_id, v_me),
        updated_at = now()
    where id = v_step.id;
  end if;

  if v_decision in ('reject', 'return') then
    v_final_status := case when v_decision = 'reject' then 'rejected' else 'returned' end;

    update public.request_steps
    set status = 'skipped', updated_at = now()
    where request_id = p_request_id
      and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and status in ('active', 'pending', 'escalated');

    insert into public.request_actions (
      request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
    ) values (
      p_request_id, v_step.id, v_me, v_decision, 'pending', v_final_status, p_comment, auth.uid(),
      jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
    );

    update public.requests
    set status = v_final_status,
        workflow_status = case when v_decision = 'reject' then 'terminated' else 'in_review' end,
        decided_at = now(),
        decided_by = v_me,
        review_note = p_comment,
        updated_at = now()
    where id = p_request_id
    returning * into v_req;

    if v_req.request_type = 'attendance_correction' then
      v_correction_id := nullif(v_req.payload->>'correctionId', '')::uuid;
      if v_correction_id is not null then
        update public.attendance_corrections
        set status = case when v_decision = 'reject' then 'rejected' else 'cancelled' end,
            reviewed_by = v_me,
            reviewed_at = now(),
            review_note = coalesce(p_comment, case when v_decision = 'reject' then 'مرفوض مع الطلب' else 'معاد للمراجعة' end),
            updated_at = now()
        where id = v_correction_id and status = 'pending';
      end if;
    end if;

    perform public.notify_employee(
      v_req.employee_id,
      case when v_decision = 'reject' then 'تم رفض طلبك' else 'تمت إعادة طلبك للمراجعة' end,
      coalesce(v_req.title, '') || case when p_comment is not null then ' — ' || p_comment else '' end,
      'request', 'normal', 'request', v_req.id,
      jsonb_build_object('status', v_final_status, 'decision', v_decision, 'requestId', v_req.id)
    );

    return v_req;
  end if;

  -- اعتماد (approve):
  insert into public.request_actions (
    request_id, request_step_id, actor_employee_id, action, from_status, to_status, comment, created_by, metadata
  ) values (
    p_request_id, v_step.id, v_me, 'approve', 'pending', 'approved', p_comment, auth.uid(),
    jsonb_build_object('role', v_actor_role, 'roleName', v_actor_role_name)
  );

  update public.request_steps
  set status = 'skipped', updated_at = now()
  where request_id = p_request_id
    and id <> coalesce(v_step.id, '00000000-0000-0000-0000-000000000000'::uuid)
    and status in ('active', 'pending', 'escalated');

  update public.requests
  set status = 'approved',
      workflow_status = 'completed',
      decided_at = now(),
      decided_by = v_me,
      review_note = p_comment,
      updated_at = now()
  where id = p_request_id
  returning * into v_req;

  -- تنفيذ الآثار الجانبية:
  if v_req.request_type in ('early_permit', 'late_permit', 'permit') then
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

  if v_req.request_type = 'leave' then
    begin
      perform public.activate_approved_leave(v_req.id);
    exception when others then
      null;
    end;
  end if;

  perform public.notify_employee(
    v_req.employee_id,
    '🎉 تم اعتماد طلبك بنجاح',
    coalesce(v_req.title, '') || ' — تم الاعتماد بواسطة ' || v_actor_role_name,
    'request', 'normal', 'request', v_req.id,
    jsonb_build_object('status', 'approved', 'requestId', v_req.id)
  );

  return v_req;
end;
$$;


-- ─── 2) تحديث get_mobile_request_detail ──────────────────────────────────────
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
  v_insights           jsonb;
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
           'escalatedAt', s.escalated_at
         ) order by s.step_order), '[]'::jsonb)
    into v_steps
    from public.request_steps s
    left join public.employees actor on actor.id = s.acted_by
   where s.request_id = v_request.id;

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
             when x.metadata->>'role' in ('operations', 'operations-manager-1', 'operations-manager') then 'مدير العمليات 1'
             when x.metadata->>'role' = 'direct_manager' then 'المدير المباشر'
             else st.name_ar
           end
         ) order by x.created_at asc), '[]'::jsonb)
    into v_history
    from public.request_actions x
    left join public.employees actor on actor.id = x.actor_employee_id
    left join public.request_steps st on st.id = x.request_step_id
   where x.request_id = v_request.id;

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

  select ea.full_name_ar,
         coalesce(act.metadata->>'roleName', ''),
         coalesce((act.metadata->>'onBehalfOfExecutive')::boolean, false)
    into v_decision_actor, v_decision_mode, v_decision_on_behalf
    from public.request_actions act
    left join public.employees ea on ea.id = act.actor_employee_id
   where act.request_id = v_request.id
     and act.action in ('approve', 'reject', 'return', 'cancel')
   order by act.created_at desc
   limit 1;

  -- insights: سياق قرار المعتمد
  v_insights := jsonb_build_object(
    'monthRequestsCount', (
      select count(*) from public.requests r
       where r.employee_id = v_request.employee_id
         and r.id <> v_request.id
         and r.created_at >= date_trunc('month', current_date)
    ),
    'teamSize', (
      select count(*) from public.employees e
       where v_employee.department_id is not null
         and e.department_id = v_employee.department_id
         and e.id <> v_request.employee_id
         and e.is_active and not coalesce(e.is_deleted, false)
    )
  );

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
    'insights', v_insights,
    'decisionActorName', v_decision_actor,
    'decisionMode', v_decision_mode,
    'decisionOnBehalfOfExecutive', v_decision_on_behalf,
    'missionExecution', v_execution
  );
end;
$$;

commit;
