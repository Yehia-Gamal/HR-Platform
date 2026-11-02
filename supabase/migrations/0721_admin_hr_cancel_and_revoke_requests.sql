-- ==============================================================================
-- Migration 0721: Admin and HR ability to cancel or revoke leaves, permits, and missions
-- 1. Update cancel_request: Allow Super-Admin, Executive, and HR to cancel/revoke
--    requests in both 'pending' and 'approved' states (leaves, permits, missions, etc.).
-- 2. Fully handles side-effects of revoking an approved request:
--    - Leaves: leave balance refund via tg_leave_settle_on_request_decision + reset attendance_daily.
--    - Permits: restore late_minutes in attendance_daily and reset on_permit status.
--    - Missions: cancel mission_executions + reset unpunched attendance_daily.
--    - Audit event: request.revoked_by_admin logged.
--    - Notification: employee notified immediately of administrative revocation.
-- 3. Update get_mobile_request_detail: set canCancel = true for Admins/HR on pending & approved requests.
-- ==============================================================================

create or replace function public.cancel_request(
  p_request_id uuid,
  p_reason text default null::text
)
returns public.requests
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_is_full            boolean := public.current_is_full_access();
  v_roles              text[];
  v_is_admin_or_hr     boolean := false;
  v_req                public.requests;
  v_from               text;
  v_lr                 public.leave_requests;
  v_day                date;
  v_start              date;
  v_end                date;
  v_permit_mins        integer;
  v_work_date          date;
  v_actor_name         text;
begin
  if v_me is null and auth.uid() is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug), '{}'::text[]) into v_roles
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
   where ur.user_id = auth.uid()
     and (ur.effective_from is null or ur.effective_from <= now())
     and (ur.effective_to is null or ur.effective_to > now());

  v_is_admin_or_hr := coalesce(v_is_full, false)
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'hr-specialist', 'hr-officer', 'operations-manager-1']
    or public.has_any_permission(array['requests.approve', 'requests.request.approve', 'requests.decide',
                                       'leave.request.manage', 'attendance.record.manage']);

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'الطلب غير موجود: %', p_request_id using errcode = 'P0002';
  end if;

  -- التحقق من الصلاحيات: إما الإدارة / الموارد البشرية، أو صاحب الطلب
  if not (v_is_admin_or_hr or v_req.employee_id = v_me) then
    raise exception 'غير مصرح لك بإلغاء أو سحب هذا الطلب' using errcode = '42501';
  end if;

  -- التحقق من حالة الطلب القابلة للإلغاء:
  -- الإدارة والـ HR: يمكنهم إلغاء أو سحب أي طلب في حالة pending أو approved
  -- الموظف العادي: يمكنه سحب طلبه إذا كان pending فقط، أو مأمورية/قافلة معتمدة قبل إنجازها
  if v_is_admin_or_hr then
    if v_req.status not in ('pending', 'approved') then
      raise exception 'لا يمكن إلغاء الطلب في حالته الحالية (%)', v_req.status using errcode = '22023';
    end if;
  else
    if v_req.request_type in ('mission', 'convoy', 'fundraising') then
      if v_req.status not in ('pending', 'approved') then
        raise exception 'لا يمكن إلغاء المأمورية في حالتها الحالية (%)', v_req.status using errcode = '22023';
      end if;
    else
      if v_req.status <> 'pending' then
        raise exception 'لا يمكن للموظف إلغاء الطلب إلا وهو قيد المراجعة (معلق). لإلغاء طلب معتمد يرجى مراجعة إدارة الموارد البشرية' using errcode = '22023';
      end if;
    end if;
  end if;

  v_from := v_req.status;

  -- 1. تحديث الطلب نفسه
  update public.requests
     set status          = 'cancelled',
         workflow_status = 'terminated',
         cancelled_at    = now(),
         cancelled_by    = v_me,
         cancel_reason   = coalesce(nullif(trim(p_reason), ''), case when v_from = 'approved' then 'تم سحب/إلغاء الطلب المعتمد إدارياً' else 'تم سحب الطلب' end),
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  -- 2. تحديث خطوات المسار
  update public.request_steps
     set status   = 'skipped',
         acted_at = now(),
         acted_by = v_me,
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  -- 3. تحديث سير العمل
  update public.workflow_instances
     set status       = 'cancelled',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status in ('running', 'active');

  -- 4. معالجة الآثار المترتبة إذا كان الطلب مُعتمداً سابقاً (v_from = 'approved'):
  if v_from = 'approved' then

    -- أ) إذا كان إجازة:
    if v_req.request_type = 'leave' then
      update public.leave_requests
         set updated_at = now()
       where request_id = p_request_id;

      -- ملاحظة: التريجر tg_leave_settle_on_request_decision سيتولى تلقائياً
      -- استرداد الرصيد refund وإعادته لرصيد الموظف في leave_ledger_entries!

      -- إعادة ضبط سجل الحضور attendance_daily لأيام الإجازة المسحوبة
      select * into v_lr from public.leave_requests where request_id = p_request_id;
      if found then
        v_day := v_lr.start_date;
        while v_day <= v_lr.end_date loop
          update public.attendance_daily
             set status = case
                   when first_check_in is not null then 'present'
                   when v_day <= current_date then 'unexcused_absent'
                   else 'unexcused_absent'
                 end,
                 updated_at = now()
           where employee_id = v_req.employee_id
             and work_date = v_day
             and status = 'on_leave'
             and is_finalized = false;

          delete from public.attendance_exceptions
           where employee_id = v_req.employee_id
             and work_date = v_day
             and kind = 'leave';

          v_day := v_day + 1;
        end loop;
      end if;
    end if;

    -- ب) إذا كان إذن حضور أو انصراف:
    if v_req.request_type in ('late_permit', 'early_permit', 'permit', 'attendance_permit', 'early_leave_permit', 'temporary_departure_permit') then
      v_work_date := coalesce(
        public.try_cast_date(v_req.payload->>'permitDate'),
        public.try_cast_date(v_req.payload->>'date'),
        public.try_cast_date(v_req.payload->>'startDate'),
        (v_req.created_at at time zone 'Africa/Cairo')::date
      );
      v_permit_mins := coalesce(nullif(v_req.payload->>'minutes', '')::integer, 0);

      if v_work_date is not null then
        -- إذا كان الموظف على حالة on_permit ولم يبصم
        update public.attendance_daily
           set status = case
                 when first_check_in is not null then 'present'
                 when v_work_date <= current_date then 'unexcused_absent'
                 else 'unexcused_absent'
               end,
               updated_at = now()
         where employee_id = v_req.employee_id
           and work_date = v_work_date
           and status = 'on_permit'
           and is_finalized = false;

        -- إذا كان قد بصم ومُنح إعفاء دقائق: نعيد احتساب التأخير
        if v_permit_mins > 0 then
          update public.attendance_daily
             set late_minutes = late_minutes + v_permit_mins,
                 status = case when (late_minutes + v_permit_mins) > 15 then 'late' else status end,
                 updated_at = now()
           where employee_id = v_req.employee_id
             and work_date = v_work_date
             and first_check_in is not null
             and is_finalized = false;
        end if;

        delete from public.attendance_exceptions
         where employee_id = v_req.employee_id
           and work_date = v_work_date
           and (description like '%إذن%' or kind in ('late', 'early_leave'));
      end if;
    end if;

    -- ج) إذا كان مأمورية / قافلة / فاندي:
    if v_req.request_type in ('mission', 'convoy', 'fundraising') then
      update public.mission_executions
         set status = 'cancelled',
             ended_at = now(),
             report = coalesce(p_reason, 'تم إلغاء المأمورية من قِبل الإدارة'),
             updated_at = now()
       where request_id = p_request_id
         and status in ('in_progress', 'not_started');

      v_start := public._payload_date(v_req.payload, 'startDate');
      v_end := coalesce(public._payload_date(v_req.payload, 'endDate'), v_start);
      if v_start is not null then
        v_day := v_start;
        while v_day <= v_end loop
          -- إذا كان السجل present بدون بصمة فعلية (اعتمد على المأمورية فقط)
          update public.attendance_daily
             set status = case
                   when first_check_in is not null then 'present'
                   when v_day <= current_date then 'unexcused_absent'
                   else 'unexcused_absent'
                 end,
                 updated_at = now()
           where employee_id = v_req.employee_id
             and work_date = v_day
             and first_check_in is null
             and is_finalized = false;

          delete from public.attendance_exceptions
           where employee_id = v_req.employee_id
             and work_date = v_day
             and description like '%مأمورية%';

          v_day := v_day + 1;
        end loop;
      end if;
    end if;

    -- د) إذا كان تغيير فترة عمل:
    if v_req.request_type = 'shift_change' then
      update public.shift_assignments
         set is_active = false,
             updated_at = now()
       where employee_id = v_req.employee_id
         and notes like '%' || p_request_id::text || '%';
    end if;

  end if;

  -- 5. توثيق الإجراء في request_actions
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'cancel', v_from, 'cancelled', p_reason, auth.uid()
  );

  -- 6. تسجيل حدث التدقيق
  select full_name_ar into v_actor_name from public.employees where id = v_me;
  perform public.log_audit_event(
    case when v_from = 'approved' then 'request.revoked_by_admin' else 'request.cancelled' end,
    'workflow', 'info', 'requests', v_req.employee_id,
    case
      when v_from = 'approved' then 'تم سحب/إلغاء الطلب المعتمد (' || v_req.request_type || ' #' || v_req.request_number || ') بواسطة ' || coalesce(v_actor_name, 'الإدارة')
      else 'تم إلغاء الطلب (' || v_req.request_type || ' #' || v_req.request_number || ')'
    end,
    p_reason,
    jsonb_build_object('requestId', p_request_id, 'requestType', v_req.request_type, 'previousStatus', v_from, 'reason', p_reason)
  );

  -- 7. إشعار الموظف (إذا كان الملغي شخصاً آخر غير الموظف نفسه)
  if v_req.employee_id is distinct from v_me then
    perform public.notify_employee(
      v_req.employee_id,
      case
        when v_from = 'approved' then '⚠️ تم إلغاء وسحب طلبك المعتمد (' || coalesce(v_req.title, v_req.request_type) || ')'
        else 'تم إلغاء طلبك (' || coalesce(v_req.title, v_req.request_type) || ')'
      end,
      case
        when v_from = 'approved' then 'قامت إدارة الموارد البشرية بسحب اعتماد الطلب #' || v_req.request_number || case when p_reason is not null then '. السبب: ' || p_reason else '' end
        else 'تم إلغاء الطلب #' || v_req.request_number || case when p_reason is not null then '. السبب: ' || p_reason else '' end
      end,
      'attendance', 'urgent', 'request', v_req.id,
      jsonb_build_object('requestId', v_req.id, 'status', 'cancelled', 'reason', p_reason)
    );
  end if;

  return v_req;
end;
$$;

revoke all on function public.cancel_request(uuid, text) from public, anon;
grant execute on function public.cancel_request(uuid, text) to authenticated;

-- تحديث get_mobile_request_detail لتمكين زر الإلغاء/السحب للإدارة والـ HR
create or replace function public.get_mobile_request_detail(p_request_id uuid)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $$
declare
  v_me                 uuid := public.current_employee_id();
  v_full               boolean := public.current_is_full_access();
  v_roles              text[];
  v_is_admin_or_hr     boolean := false;
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

  v_is_admin_or_hr := coalesce(v_full, false)
    or v_roles && array['admin', 'super-admin', 'executive', 'executive-director',
                        'general-manager', 'hr-manager', 'hr-specialist', 'hr-officer', 'operations-manager-1']
    or public.has_any_permission(array['requests.approve', 'requests.request.approve', 'requests.decide',
                                       'leave.request.manage', 'attendance.record.manage']);

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
    or v_is_admin_or_hr
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
    'canCancel', coalesce(
      (v_request.status = 'pending' and v_request.employee_id = v_me)
      or (
        v_is_admin_or_hr
        and v_request.status in ('pending', 'approved')
      )
      or (
        v_request.employee_id = v_me
        and v_request.request_type in ('mission', 'convoy', 'fundraising')
        and v_request.status in ('pending', 'approved')
      ),
      false
    ),
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
