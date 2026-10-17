-- ===========================================================================
-- 0689: إصلاح إشعارات الطلبات وتخصيص عناوين الوصول بالاسم الثنائي ومنع إشعار الوصول عند طلب المأموريات
-- ===========================================================================
-- 1) تخصيص إشعارات الطلبات:
--    إظهار اسم صاحب الطلب والنوع بوضوح: «طلب مأمورية — إبراهيم سلامة»
--    بدلاً من العنوان المبهم «طلب جديد — للإطلاع».
--
-- 2) تخصيص عنوان الوصول بالاسم الثنائي:
--    «وصل يحيى جمال للعمل بالمجمع» و«وصل مصطفى أحمد للعمل بالمجمع»
--    بدلاً من الاقتصار على الاسم الأول فقط («وصل ساميه»).
--
-- 3) منع إرسال «وصل فلان للعمل بالمجمع» عند مجرد طلب أو بدء مأمورية:
--    إشعار الوصول للمجمع يقتصر فقط وحصراً على من بصم حضوراً فعلياً بالمقر
--    (بصمة حضور CHECK_IN مقبولة في attendance_events).
--
-- 4) تحديث بأثر رجعي لنصوص الإشعارات الحديثة لتصحيح العناوين القديمة.
-- ===========================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) تحديث tg_attendance_notify_manager:
--    - حصر «وصل للمجمع» بالبصمة الفعلية فقط (attendance_events).
--    - استخدام الاسم الثنائي في العنوان (v_two_names).
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.tg_attendance_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
  v_two_names text;
  v_exec_emp uuid;
  v_title text;
  v_body text;
  v_has_actual_punch boolean := false;

  -- متغيرات التعويض والغرامة
  v_target_out timestamptz;
  v_target_out_str text;
  v_penalty numeric(12,2) := 0;
  v_self_title text;
  v_self_body text;
  v_priority text := 'normal';
begin
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  -- ── حماية المأموريات والتعديلات الإدارية ──
  -- إذا كان الحدث تسجيل حضور (check_in)، نتحقق هل توجد بصمة حضور فعلية بالمقر اليوم
  if v_event = 'attendance_check_in' then
    select exists (
      select 1 from public.attendance_events ae
      where ae.employee_id = new.employee_id
        and (ae.event_at at time zone 'Africa/Cairo')::date = new.work_date
        and ae.event_type = 'CHECK_IN'
        and ae.status in ('accepted', 'adjusted')
        and ae.source not in ('mission_auto')
    ) into v_has_actual_punch;

    -- إذا لم تكن هناك بصمة حضور فعلية بالمقر (مثل تقديم مأمورية أو بدء مأمورية خارجية دون بصمة مقر)،
    -- فلا نرسل إشعار «وصل فلان للعمل بالمجمع»!
    if not v_has_actual_punch then
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;
  
  -- استخراج الاسم الثنائي (أول كلمتين)
  v_two_names := trim(split_part(coalesce(v_emp_ar, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_ar, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_ar, ''), 'موظف');
  end if;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'FMHH12:MI'
  ) || case when extract(hour from (
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo')) < 12 then ' ص' else ' م' end;

  if v_event = 'attendance_check_in' then
    v_target_out := new.first_check_in + interval '8 hours';
    v_target_out_str := to_char(v_target_out at time zone 'Africa/Cairo', 'FMHH12:MI') ||
                        case when (v_target_out at time zone 'Africa/Cairo')::time < '12:00' then ' ص' else ' م' end;

    if coalesce(new.late_minutes, 0) > 15 then
      v_penalty := public.calc_instant_penalty_amount(least(120, new.late_minutes));
      v_self_title := '⏰ تسجيل حضور متأخر — فرصة تعويض الغرامة';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة — خصم مقرر ' || v_penalty || ' ج.م).' || chr(10) ||
                      '💡 اقتراح ذكي: إذا استكملت 8 ساعات عمل حتى الساعة ' || v_target_out_str || ' وسجلت بصمة الانصراف بمقر العمل، فسيتم تلقائياً إلغاء الغرامة وإسقاط الخصم كاملاً!';
      v_priority   := 'high';
    elsif coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '⏰ تسجيل حضور (فترة السماح الرسمية)';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' (تأخير ' || new.late_minutes || ' دقيقة ضمن فترة السماح 15 دقيقة — بدون أي غرامة).' || chr(10) ||
                      '💡 موعد إتمام 8 ساعات عمل هو الساعة ' || v_target_out_str || ' وسجل انصرافك حينها.';
      v_priority   := 'normal';
    else
      v_self_title := '✅ تم تسجيل حضورك بنجاح';
      v_self_body  := 'سُجّل حضورك في تمام الساعة ' || v_time || ' بموعدك المنضبط.' || chr(10) ||
                      '💡 موعد نهاية الـ 8 ساعات هو الساعة ' || v_target_out_str || '.';
      v_priority   := 'normal';
    end if;

    -- الاسم ثنائي واضح
    v_title := format('وصل %s للعمل بالمجمع', v_two_names);
    v_body  := format(
      'دخل الساعة %s%s',
      v_time,
      case when coalesce(new.late_minutes, 0) > 0 then format(' (تأخير %s دقيقة)', new.late_minutes) else '' end
    );
  else
    -- checkout
    if coalesce(new.work_minutes, 0) >= 480 and coalesce(new.late_minutes, 0) > 0 then
      v_self_title := '🎉 تم تسجيل انصرافك وإسقاط غرامة التأخير';
      v_self_body  := 'سُجّل انصرافك في تمام الساعة ' || v_time || '. لقد استوفيت 8 ساعات عمل كاملة بنجاح، وتم إلغاء غرامة التأخير الصباحي وإسقاط الخصم بالكامل!';
      v_priority   := 'high';
    else
      v_self_title := 'تم تسجيل انصرافك';
      v_self_body  := format('تم تسجيل انصرافك الساعة %s', v_time);
      v_priority   := 'normal';
    end if;

    -- الاسم ثنائي واضح
    v_title := format('خرج %s من المجمع', v_two_names);
    v_body  := format(
      'انصرف الساعة %s (إجمالي العمل: %s دقيقة%s)',
      v_time,
      coalesce(new.work_minutes, 0),
      case when coalesce(new.overtime_minutes, 0) > 0 then format(' — إضافي: +%s د', new.overtime_minutes) else '' end
    );
  end if;

  -- إشعار الموظف نفسه
  perform public.notify_employee(
    new.employee_id,
    v_self_title,
    v_self_body,
    'attendance', v_priority, 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time,
      'lateMinutes', new.late_minutes,
      'workMinutes', new.work_minutes,
      'overtimeMinutes', new.overtime_minutes,
      'targetCheckoutTime', v_target_out_str,
      'penaltyAmount', v_penalty,
      'deepLink', 'ahlashabab://action/attendance'
    )
  );

  -- إشعار المدير المباشر
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null and v_manager <> new.employee_id then
    perform public.notify_employee(
      v_manager,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- إشعار المدير التنفيذي
  for v_exec_emp in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r on r.id = ur.role_id
    where r.slug in ('executive-director', 'executive')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to is null or ur.effective_to > now())
  loop
    perform public.notify_employee(
      v_exec_emp,
      v_title,
      format('%s — %s', coalesce(v_emp_ar, 'موظف'), v_body),
      'attendance', 'normal', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'executiveNotify', true,
        'time', v_time
      )
    );
  end loop;

  return new;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2) تحديث tg_notify_awareness_on_request_submit:
--    إشعار المدير التنفيذي وHR باسم صاحب الطلب ونوعه بوضوح
--    «طلب مأمورية — إبراهيم سلامة» بدلاً من «طلب جديد — للإطلاع»
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.tg_notify_awareness_on_request_submit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_body      text;
  v_title_exec text;
  v_title_hr   text;
  v_emp_id    uuid;
  v_emp_name  text;
  v_two_names text;
  v_req_label text;
begin
  select full_name_ar into v_emp_name from public.employees where id = new.employee_id;
  v_two_names := trim(split_part(coalesce(v_emp_name, ''), ' ', 1) || ' ' || split_part(coalesce(v_emp_name, ''), ' ', 2));
  if v_two_names is null or v_two_names = '' then
    v_two_names := coalesce(nullif(v_emp_name, ''), 'موظف');
  end if;

  v_req_label := public.request_type_label(new.request_type);

  -- عنوان واضح يتضمن نوع الطلب واسم الموظف الثنائي
  v_title_exec := format('طلب %s — %s', v_req_label, v_two_names);
  v_title_hr   := format('طلب %s — %s (للمتابعة)', v_req_label, v_two_names);

  v_body := format('%s: %s%s',
    v_req_label,
    coalesce(nullif(new.title, ''), v_req_label),
    case when new.reason is not null and new.reason <> '' and new.reason <> new.title
         then ' — ' || new.reason else '' end
  );

  -- المدير التنفيذي (للإطلاع والمتابعة الفورية)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('executive-director', 'executive')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      v_title_exec,
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'requestId', new.id,
        'employeeId', new.employee_id,
        'employeeName', v_emp_name,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  -- HR (للمتابعة)
  for v_emp_id in
    select distinct e.id
    from public.employees e
    join public.user_roles ur on ur.user_id = e.user_id
    join public.roles r       on r.id       = ur.role_id
    where r.slug in ('hr-manager', 'hr-specialist')
      and e.is_active = true
      and e.id <> new.employee_id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   > now())
  loop
    perform public.notify_employee(
      v_emp_id,
      v_title_hr,
      v_body,
      'request', 'normal', 'request', new.id,
      jsonb_build_object(
        'requestType', new.request_type,
        'requestId', new.id,
        'employeeId', new.employee_id,
        'employeeName', v_emp_name,
        'awarenessOnly', true,
        'deepLink', '/requests/' || new.id
      )
    );
  end loop;

  return new;
end;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3) تحديث _submit_request_for:
--    إشعار المعتمِد الأول بعنوان مفصل «طلب مأمورية — إبراهيم سلامة»
-- ─────────────────────────────────────────────────────────────────────────────

drop function if exists public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb);

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
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_label          text;
  v_title_approver text;
  v_is_clinic      boolean := false;
  v_emp_name       text;
  v_two_names      text;
  v_req_label      text;
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

  -- فحص طاقم العيادات (الموظفون غير المديرين)
  v_is_clinic := public.is_clinic_team_member(p_employee_id)
                 and p_employee_id not in (
                   '4120ce3a-8999-453e-8d9d-acd8f3b5f04c'::uuid,
                   'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'::uuid
                 );

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

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate and not v_is_clinic then
      v_esc := v_due;
    end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  insert into public.requests (
    request_type, employee_id, manager_employee_id, workflow_definition_id,
    status, workflow_status, title, reason, decision_due_at, escalation_deadline,
    payload, created_by
  ) values (
    p_request_type, p_employee_id, p_manager_employee_id, v_def.id,
    'pending', 'submitted', p_title, p_reason, v_due, v_esc,
    coalesce(p_payload, '{}'::jsonb), auth.uid()
  )
  returning * into v_row;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case
        when ws.approver_type = 'specific_employee' then ws.approver_employee_id
        when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
        else null
      end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null and not v_is_clinic
           then now() + make_interval(hours => ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    insert into public.workflow_instances (
      definition_id, request_id, definition_version, status, current_step_order, created_by
    ) values (
      v_def.id, v_row.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
    );
  end if;

  insert into public.request_actions (
    request_id, actor_employee_id, action, to_status, comment, created_by
  ) values (v_row.id, coalesce(v_me, p_employee_id), 'submit', 'pending', p_reason, auth.uid());

  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  v_title_approver := format('طلب %s — %s', v_req_label, v_two_names);
  v_label := format('%s: %s%s',
    v_req_label,
    coalesce(nullif(v_row.title, ''), v_req_label),
    case when p_reason is not null and p_reason <> '' and p_reason <> p_title
         then ' — ' || p_reason else '' end
  );

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      v_title_approver,
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'requestId', v_row.id,
        'employeeId', v_row.employee_id,
        'employeeName', v_emp_name,
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  return v_row;
end;
$$;

revoke execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4) تحديث بأثر رجعي للإشعارات المسجلة اليوم والأيام السابقة:
-- ─────────────────────────────────────────────────────────────────────────────

-- أ) تصحيح عناوين إشعارات الطلبات غير الواضحة (مثل «طلب جديد — للإطلاع»)
update public.notifications n
set title = format('طلب %s — %s',
      public.request_type_label(r.request_type),
      trim(split_part(coalesce(e.full_name_ar, ''), ' ', 1) || ' ' || split_part(coalesce(e.full_name_ar, ''), ' ', 2))
    ),
    body = format('%s: %s%s',
      public.request_type_label(r.request_type),
      coalesce(nullif(r.title, ''), public.request_type_label(r.request_type)),
      case when r.reason is not null and r.reason <> '' and r.reason <> r.title
           then ' — ' || r.reason else '' end
    )
from public.requests r
join public.employees e on e.id = r.employee_id
where n.entity_type = 'request'
  and n.entity_id = r.id
  and (
    n.title in ('طلب جديد — للإطلاع', 'طلب جديد — للمتابعة', 'طلب جديد بانتظار مراجعتك', 'طلب جديد - للإطلاع', 'طلب جديد - للمتابعة')
    or n.title like 'طلب جديد%'
  );

-- ب) تصحيح عناوين الوصول بالاسم الثنائي لجميع إشعارات الحضور
update public.notifications n
set title = format('وصل %s للعمل بالمجمع',
      trim(split_part(coalesce(e.full_name_ar, ''), ' ', 1) || ' ' || split_part(coalesce(e.full_name_ar, ''), ' ', 2))
    )
from public.employees e
where (n.category in ('attendance', 'attendance_manager_notify') or n.entity_type = 'attendance_daily')
  and n.title like 'وصل % للعمل بالمجمع'
  and (
    n.metadata->>'employeeId' = e.id::text
    or exists (select 1 from public.attendance_daily ad where ad.id = n.entity_id and ad.employee_id = e.id)
  );

-- ج) تصحيح عناوين الانصراف بالاسم الثنائي لجميع إشعارات الحضور
update public.notifications n
set title = format('خرج %s من المجمع',
      trim(split_part(coalesce(e.full_name_ar, ''), ' ', 1) || ' ' || split_part(coalesce(e.full_name_ar, ''), ' ', 2))
    )
from public.employees e
where (n.category in ('attendance', 'attendance_manager_notify') or n.entity_type = 'attendance_daily')
  and n.title like 'خرج % من المجمع'
  and (
    n.metadata->>'employeeId' = e.id::text
    or exists (select 1 from public.attendance_daily ad where ad.id = n.entity_id and ad.employee_id = e.id)
  );

commit;
