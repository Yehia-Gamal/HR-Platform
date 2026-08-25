-- ============================================================================
-- 0471: تعريب رسائل أخطاء دوال قاعدة البيانات (الجذر — الدفعة الشاملة)
-- ============================================================================
-- الرسائل الإنجليزية كانت تصل الموظف كـ«حدث خطأ غير متوقع» لأن humanizeError
-- يمرر العربية فقط. هذا الملف يعيد تعريف كل دالة تحوي رسائل إنجليزية مترجمة
-- (استبدال نصي حرفي داخل الأجسام — المنطق دون تغيير).
-- ملاحظة: رموز ALL_CAPS (مثل FORBIDDEN) عقود يستهلكها الكود ولم تُترجم.
-- عدد الدوال المعادة تعريفها: 119 | عدد العبارات المترجمة: 192
-- ============================================================================
-- set_employee_status(uuid,text)
CREATE OR REPLACE FUNCTION public.set_employee_status(p_employee_id uuid, p_status text)
 RETURNS employees
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.employees;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('employees.update')
    or public.can_access_employee(p_employee_id)
  ) then
    raise exception 'غير مصرح بتغيير حالة الموظف' using errcode = '42501';
  end if;

  if p_status not in (
    'draft','invited','onboarding','active','suspended',
    'notice_period','terminated','archived','probation_failed'
  ) then
    raise exception 'invalid status value: %', p_status using errcode = '22023';
  end if;

  update public.employees
     set status     = p_status,
         is_active  = (p_status = 'active'),
         updated_at = now()
   where id = p_employee_id
  returning * into v_row;

  if not found then
    raise exception 'employee not found: %', p_employee_id using errcode = 'P0002';
  end if;

  return v_row;
end;
$function$;

-- share_my_location_proactively(double precision,double precision,double precision,integer,text,text,integer)
CREATE OR REPLACE FUNCTION public.share_my_location_proactively(p_latitude double precision, p_longitude double precision, p_accuracy double precision DEFAULT NULL::double precision, p_duration_minutes integer DEFAULT 60, p_reason text DEFAULT NULL::text, p_source text DEFAULT 'mobile'::text, p_battery_level integer DEFAULT NULL::integer)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_exec_role text;
  v_exec_emp uuid;
  v_exec_user uuid;
  v_row public.live_location_requests;
  v_duration integer;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_latitude is null or p_longitude is null then
    raise exception 'الإحداثيات مطلوبة' using errcode = '22023';
  end if;
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'الإحداثيات خارج النطاق' using errcode = '22023';
  end if;

  v_duration := greatest(1, least(coalesce(p_duration_minutes, 60), 1440));

  -- Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù Ø§ÙÙØ³ØªÙØ¯Ù (Ø§ÙØ¥Ø¹Ø¯Ø§Ø¯ leave_escalation_notify_role ØºÙØ± ÙÙØ§Ø³Ø¨ ÙÙØ§ â
  -- ÙØ³ØªØ®Ø¯Ù executive_director_role ÙØ¨Ø§Ø´Ø±Ø© Ø¨Ø¯ÙØ± executive-director)
  v_exec_role := public.get_system_setting_text('executive_director_role', 'executive-director');
  v_exec_emp  := public.first_active_employee_for_role(v_exec_role);

  -- ÙÙØ¹ ØªÙØ±Ø§Ø± Ø·ÙØ¨ ÙÙÙØ¹ ÙØ´Ø· ÙÙÙØ³ Ø§ÙÙÙØ¸Ù (ÙØ´Ø§Ø±ÙØ© ÙÙØªÙØ­Ø© ÙØ§Ø­Ø¯Ø© ÙØ§ÙÙØ©)
  if exists (
    select 1 from public.live_location_requests
    where employee_id = v_me
      and status in ('pending', 'accepted', 'active')
      and (expires_at is null or expires_at > now())
  ) then
    raise exception 'لديك مشاركة موقع نشطة بالفعل' using errcode = '23505';
  end if;

  insert into public.live_location_requests (
    employee_id, requested_by, reason, status, purpose,
    requested_at, starts_at, expires_at, duration_minutes, metadata, created_by
  ) values (
    v_me, v_exec_emp, trim(coalesce(p_reason, 'ÙØ´Ø§Ø±ÙØ© ÙÙÙØ¹ Ø§Ø³ØªØ¨Ø§ÙÙØ©')),
    'active', 'safety',
    now(), now(), now() + make_interval(mins => v_duration), v_duration,
    jsonb_build_object('proactive', true, 'source', p_source),
    auth.uid()
  ) returning * into v_row;

  -- ÙÙØ·Ø© ÙÙÙØ¹ ÙÙØ±ÙØ©
  insert into public.employee_locations (
    employee_id, live_request_id, latitude, longitude, accuracy,
    source, battery_level, is_mock, created_by
  ) values (
    v_me, v_row.id, p_latitude, p_longitude, p_accuracy,
    case when p_source in ('mobile','web','device','manual','geofence') then p_source else 'mobile' end,
    case when p_battery_level between 0 and 100 then p_battery_level else null end,
    false, auth.uid()
  );

  -- Ø¥Ø´Ø¹Ø§Ø± Ø¹Ø§Ø¬Ù ÙÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù
  if v_exec_emp is not null then
    select p.id into v_exec_user from public.profiles p where p.employee_id = v_exec_emp;

    if v_exec_user is not null then
      insert into public.notifications (
        recipient_user_id, recipient_employee_id, title, body, category, priority,
        action_url, entity_type, entity_id, metadata, created_by
      ) values (
        v_exec_user, v_exec_emp,
        'ÙØ´Ø§Ø±ÙØ© ÙÙÙØ¹ Ø­ÙÙØ© ÙÙ ÙÙØ¸Ù',
        format(
          '%s ÙØ´Ø§Ø±ÙÙ ÙÙÙØ¹Ù Ø§ÙØ¢Ù%s',
          coalesce((select full_name_ar from public.employees where id = v_me), 'ÙÙØ¸Ù'),
          case when p_reason is not null then ' â ' || trim(p_reason) else '' end
        ),
        'location', 'urgent',
        'ahlashabab://action/live_location/' || v_row.id::text,
        'live_location_requests', v_row.id,
        jsonb_build_object(
          'proactive', true,
          'employeeId', v_me,
          'requestId', v_row.id,
          'channel', 'urgent_location',
          'sound', 'urgent',
          'deepLink', 'ahlashabab://action/live_location/' || v_row.id::text
        ),
        auth.uid()
      );
    end if;
  end if;

  perform public.log_audit_event(
    'live_location.proactive_shared', 'security', 'notice',
    'live_location_requests', v_row.id,
    'ÙØ´Ø§Ø±ÙØ© ÙÙÙØ¹ Ø§Ø³ØªØ¨Ø§ÙÙØ©', null,
    jsonb_build_object(
      'employeeId', v_me, 'executiveEmployeeId', v_exec_emp,
      'durationMinutes', v_duration, 'purpose', 'safety'
    )
  );

  perform public.nudge_notification_dispatcher();

  return v_row;
end;
$function$;

-- update_employee_admin(uuid,jsonb,text)
CREATE OR REPLACE FUNCTION public.update_employee_admin(p_employee_id uuid, p_changes jsonb, p_reason text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_actor_id uuid := auth.uid();
  v_has_sensitive boolean;
  v_has_basic boolean;
  v_employee public.employees;
  v_basic_fields text[] := array['fullNameAr','fullNameEn','phoneE164','photoUrl'];
  v_sensitive_fields text[] := array[
    'departmentId','teamId','branchId','workSiteId',
    'jobTitleId','positionId','gradeId','employmentTypeId',
    'hireDate','contractEnd','probationEnd','status',
    'jobTitleName','gradeName'
  ];
  v_key text;
  v_has_sensitive_change boolean := false;
  v_old_snapshot jsonb;
  v_jt_name text;
  v_jt_id uuid;
  v_jt_code text;
  v_gr_name text;
  v_gr_id uuid;
  v_gr_code text;
  v_reason_final text;
begin
  if v_actor_id is null then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_changes is null or p_changes = '{}'::jsonb then
    raise exception 'no_changes_provided' using errcode = '22023';
  end if;

  v_reason_final := nullif(trim(coalesce(p_reason, '')), '');
  if v_reason_final is null then
    v_reason_final := 'ØªØ¹Ø¯ÙÙ Ø¨ÙØ§ÙØ§Øª Ø§ÙÙÙØ¸Ù ÙÙ ÙÙØ­Ø© Ø§ÙØ¥Ø¯Ø§Ø±Ø©';
  end if;

  v_has_sensitive := public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive');
  v_has_basic := v_has_sensitive
    or public.has_permission('people.employee.update_basic');

  if not v_has_basic then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;

  if not public.can_access_employee(p_employee_id, 'people.employee.update_basic')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode = '42501';
  end if;

  for v_key in select jsonb_object_keys(p_changes) loop
    if v_key = any(v_sensitive_fields) then
      v_has_sensitive_change := true;
    end if;
    if v_key <> all(v_basic_fields) and v_key <> all(v_sensitive_fields) then
      raise exception 'unknown field: %', v_key using errcode = '22023';
    end if;
  end loop;

  if v_has_sensitive_change and not v_has_sensitive then
    raise exception 'sensitive_field_requires_elevated_permission' using errcode = '42501';
  end if;

  if p_changes ? 'jobTitleName' then
    v_jt_name := nullif(trim(p_changes->>'jobTitleName'), '');
    if v_jt_name is not null then
      select id into v_jt_id
      from public.job_titles
      where lower(name) = lower(v_jt_name) and is_active = true
      limit 1;
      if v_jt_id is null then
        v_jt_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_titles (code, name, is_active, created_by)
        values (v_jt_code, v_jt_name, true, v_actor_id)
        on conflict ((lower(name))) where is_active = true
        do update set updated_at = now()
        returning id into v_jt_id;
      end if;
      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', v_jt_id);
      end if;
    else
      if not (p_changes ? 'jobTitleId') then
        p_changes := p_changes || jsonb_build_object('jobTitleId', null);
      end if;
    end if;
    p_changes := p_changes - 'jobTitleName';
  end if;

  if p_changes ? 'gradeName' then
    v_gr_name := nullif(trim(p_changes->>'gradeName'), '');
    if v_gr_name is not null then
      select id into v_gr_id
      from public.job_grades
      where lower(name) = lower(v_gr_name) and is_active = true
      limit 1;
      if v_gr_id is null then
        v_gr_code := 'GR-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
        insert into public.job_grades (code, name, level, is_active, created_by)
        values (v_gr_code, v_gr_name, 1, true, v_actor_id)
        returning id into v_gr_id;
      end if;
      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', v_gr_id);
      end if;
    else
      if not (p_changes ? 'gradeId') then
        p_changes := p_changes || jsonb_build_object('gradeId', null);
      end if;
    end if;
    p_changes := p_changes - 'gradeName';
  end if;

  select * into v_employee
  from public.employees
  where id = p_employee_id and is_deleted = false
  for update;

  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  v_old_snapshot := jsonb_build_object(
    'fullNameAr', v_employee.full_name_ar,
    'fullNameEn', v_employee.full_name_en,
    'phoneE164', v_employee.phone_e164,
    'photoUrl', v_employee.photo_url,
    'departmentId', v_employee.department_id,
    'teamId', v_employee.team_id,
    'branchId', v_employee.branch_id,
    'workSiteId', v_employee.work_site_id,
    'jobTitleId', v_employee.job_title_id,
    'positionId', v_employee.position_id,
    'gradeId', v_employee.grade_id,
    'employmentTypeId', v_employee.employment_type_id,
    'hireDate', v_employee.hire_date,
    'contractEnd', v_employee.contract_end,
    'probationEnd', v_employee.probation_end,
    'status', v_employee.status
  );

  update public.employees set
    full_name_ar = case when p_changes ? 'fullNameAr'
      then trim(p_changes->>'fullNameAr') else full_name_ar end,
    full_name_en = case when p_changes ? 'fullNameEn'
      then nullif(trim(p_changes->>'fullNameEn'), '') else full_name_en end,
    phone_e164 = case when p_changes ? 'phoneE164'
      then nullif(trim(p_changes->>'phoneE164'), '') else phone_e164 end,
    photo_url = case when p_changes ? 'photoUrl'
      then nullif(trim(p_changes->>'photoUrl'), '') else photo_url end,
    department_id = case when p_changes ? 'departmentId'
      then (p_changes->>'departmentId')::uuid else department_id end,
    team_id = case when p_changes ? 'teamId'
      then (p_changes->>'teamId')::uuid else team_id end,
    branch_id = case when p_changes ? 'branchId'
      then (p_changes->>'branchId')::uuid else branch_id end,
    work_site_id = case when p_changes ? 'workSiteId'
      then (p_changes->>'workSiteId')::uuid else work_site_id end,
    job_title_id = case when p_changes ? 'jobTitleId'
      then (p_changes->>'jobTitleId')::uuid else job_title_id end,
    position_id = case when p_changes ? 'positionId'
      then (p_changes->>'positionId')::uuid else position_id end,
    grade_id = case when p_changes ? 'gradeId'
      then (p_changes->>'gradeId')::uuid else grade_id end,
    employment_type_id = case when p_changes ? 'employmentTypeId'
      then (p_changes->>'employmentTypeId')::uuid else employment_type_id end,
    hire_date = case when p_changes ? 'hireDate'
      then (p_changes->>'hireDate')::date else hire_date end,
    contract_end = case when p_changes ? 'contractEnd'
      then (p_changes->>'contractEnd')::date else contract_end end,
    probation_end = case when p_changes ? 'probationEnd'
      then (p_changes->>'probationEnd')::date else probation_end end,
    status = case when p_changes ? 'status'
      then (p_changes->>'status') else status end,
    updated_at = now()
  where id = p_employee_id;

  if p_changes ? 'phoneE164' and (p_changes->>'phoneE164') is not null then
    if exists (
      select 1 from public.employees
      where phone_e164 = trim(p_changes->>'phoneE164')
        and id <> p_employee_id
        and is_active = true and is_deleted = false
    ) then
      raise exception 'phone number already belongs to an active employee' using errcode = '23505';
    end if;
  end if;

  perform public.log_audit_event(
    'employee.updated', 'data', 'info', 'employees', p_employee_id,
    'ØªØ¹Ø¯ÙÙ Ø¨ÙØ§ÙØ§Øª Ø§ÙÙÙØ¸Ù',
    v_reason_final,
    jsonb_build_object('before', v_old_snapshot, 'after', p_changes)
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'updatedFields', (select jsonb_agg(k) from jsonb_object_keys(p_changes) as k),
    'updatedAt', now()
  );
end;
$function$;

-- decide_request(uuid,text,text)
CREATE OR REPLACE FUNCTION public.decide_request(p_request_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Ø­Ø¸Ø± Ø§ÙÙÙØ§ÙÙØ© Ø§ÙØ°Ø§ØªÙØ© ÙÙØ¬ÙÙØ¹ Ø¥ÙØ§ HR (Ø¥Ø°Ù ØµØ±ÙØ­ ÙÙ Ø§ÙØ¥Ø¯Ø§Ø±Ø© â 0464)
  if v_req.employee_id = v_me
     and not public.current_has_active_role(array['hr-manager','hr-specialist']) then
    raise exception 'الاعتماد الذاتي غير مسموح' using errcode = '42501';
  end if;

  -- Ø§ÙØ®Ø·ÙØ© Ø§ÙØ­Ø§ÙÙØ©: ÙÙØ¶ÙÙ Ø§ÙØ®Ø·ÙØ© Ø§ÙÙØ´Ø·Ø© (active)Ø ÙØ¥Ù ÙÙ ØªÙØ¬Ø¯ ÙØ£Ø®Ø°
  -- Ø£ÙÙ escalated/pending (Ø¥ØµÙØ§Ø­ 0403).
  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated','pending')
  order by (status = 'active') desc, step_order
  limit 1
  for update;

  v_current_step  := coalesce(v_step.step_order, 0);
  v_is_direct_mgr := (v_req.manager_employee_id = v_me);
  -- Ø£Ø¨Ù Ø¹ÙØ§Ø± = ÙØ¯ÙØ± Ø§ÙØªØ´ØºÙÙ 1 ÙÙØ· (ÙØ§ Ø¶Ø§Ø¨Ø· Ø¹ÙÙÙØ§Øª)
  v_is_operations := public.current_has_active_role(array['operations-manager-1']);
  -- 0441: HR ØºÙØ± ÙÙÙØ¯ â ÙØ¹ØªÙØ¯ Ø£Ù Ø·ÙØ¨ ÙÙ Ø£Ù ÙÙØª
  v_is_hr         := public.current_has_active_role(array['hr-manager','hr-specialist']);

  -- ââ Ø§ÙØµÙØ§Ø­ÙØ© ââ
  -- Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø± + HR (0441) + full_access: Ø¯Ø§Ø¦ÙØ§Ù (Ø£Ù ÙØ±Ø­ÙØ©Ø Ø£Ù ÙÙØª)
  -- Ø£Ø¨Ù Ø¹ÙØ§Ø± (operations-manager-1): ÙÙ Ø§ÙØ®Ø·ÙØ© 2 ÙÙØ§ ÙÙÙØ Ø£Ù Ø¹ÙØ¯ÙØ§ ØªÙÙÙ ÙÙÙØ©
  --   Ø§ÙØ®Ø·ÙØ©/Ø§ÙØ·ÙØ¨ ÙØªØ¬Ø§ÙØ²Ø© (Ø·ÙØ¨Ø§Øª ÙØ¯ÙÙØ© Ø¹Ø§ÙÙØ© â 0440).
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

  -- ØªØ­Ø¯ÙØ¯ Ø¯ÙØ± Ø§ÙÙØ§Ø¹Ù ÙÙØ³Ø¬Ù
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

  -- ØªØ³Ø¬ÙÙ Ø¥Ø¬Ø±Ø§Ø¡ Ø§ÙØ®Ø·ÙØ© Ø§ÙØ­Ø§ÙÙØ©
  if v_step.id is not null then
    update public.request_steps
      set status = case p_decision when 'approve' then 'approved' else 'rejected' end,
          acted_at = now(), acted_by = v_me,
          comment = p_comment, updated_at = now()
    where id = v_step.id;
  end if;

  -- Ø¥ØºÙØ§Ù Ø¨Ø§ÙÙ Ø§ÙØ®Ø·ÙØ§Øª (ÙÙØ§ÙÙØ© ÙØ§Ø­Ø¯Ø© ØªÙÙÙÙ Ø§ÙØ·ÙØ¨ â ÙØ§ ÙØ±Ø­ÙØªÙÙ)
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

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙÙØ¸Ù Ø¨Ø§ÙÙØªÙØ¬Ø©
  perform public.notify_employee(
    v_req.employee_id,
    case v_req.status
      when 'approved' then 'ØªÙØª Ø§ÙÙÙØ§ÙÙØ© Ø¹ÙÙ Ø·ÙØ¨Ù'
      when 'rejected' then 'ØªÙ Ø±ÙØ¶ Ø·ÙØ¨Ù'
      else 'ØªÙ Ø¥Ø¹Ø§Ø¯Ø© Ø·ÙØ¨Ù ÙØªØ¹Ø¯ÙÙÙ'
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

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù (ÙØ§ÙÙ Ø§ÙØ´Ø§Ø´Ø©) Ø¹ÙØ¯ ÙÙ ÙØ±Ø§Ø±
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_me then
    perform public.notify_executive_fullscreen(
      'ÙØ±Ø§Ø± Ø·ÙØ¨ â ' || case v_req.status
        when 'approved' then 'ÙÙØ§ÙÙØ©'
        when 'rejected' then 'Ø±ÙØ¶'
        else 'Ø¥Ø¹Ø§Ø¯Ø© Ø·ÙØ¨' end,
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
$function$;

-- submit_employee_day_mark(uuid,text,text,text,jsonb)
CREATE OR REPLACE FUNCTION public.submit_employee_day_mark(p_employee_id uuid, p_request_type text, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_start_date date;
  v_end_date date;
  v_manager uuid;
  v_leave_type text;
  v_leave_type_id uuid;
  v_days numeric := 1;
  v_substitute uuid;
  v_row public.requests;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'الموظف مطلوب' using errcode = '22023';
  end if;

  -- Ø§ÙØµÙØ§Ø­ÙØ©: ÙÙØ³ ØµÙØ§Ø­ÙØ© Ø§ÙØªØ¹Ø¯ÙÙ Ø§ÙØ¥Ø¯Ø§Ø±Ù ÙÙÙÙÙ (0266)
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- ÙÙØ¹ Ø§ÙØªØ¹Ø¯ÙÙ Ø¹ÙÙ Ø´ÙØ± ÙØºÙÙ
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month_start
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- Ø§ÙÙÙØ¹: Ø¥Ø¬Ø§Ø²Ø© Ø£Ù ØªÙØ¬ÙÙ ØªØ´ØºÙÙÙ ÙÙØ·
  if p_request_type not in ('leave','mission','convoy','fundraising') then
    raise exception 'ترميز اليوم يدعم الإجازة والمأمورية والقافلة والفاندي فقط' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  v_start_date := nullif(v_payload->>'startDate', '')::date;
  v_end_date := nullif(v_payload->>'endDate', '')::date;
  if v_start_date is null or v_end_date is null then
    raise exception 'day mark requires a date' using errcode = '22023';
  end if;
  if v_end_date <> v_start_date then
    raise exception 'day marks are single-day only' using errcode = '22023';
  end if;
  if v_start_date < v_month_start then
    raise exception 'day marks are allowed within the current month only' using errcode = '22023';
  end if;
  if v_start_date > v_today then
    raise exception 'future days cannot be marked' using errcode = '22023';
  end if;

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  if p_request_type = 'leave' then
    v_leave_type := v_payload->>'leaveType';
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
    end if;
    select id into v_leave_type_id
    from public.leave_types where code = v_leave_type and is_active = true;
    if v_leave_type_id is null then
      raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
    end if;
    v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
    v_payload := v_payload || jsonb_build_object(
      'leaveType', v_leave_type,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'days', v_days,
      'immediate', (v_leave_type = 'casual'),
      'dayMark', true);
  else
    if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
      raise exception 'assignment location is required' using errcode = '22023';
    end if;
    v_payload := v_payload || jsonb_build_object(
      'startDate', v_start_date,
      'endDate', v_end_date,
      'location', trim(v_payload->>'location'),
      'days', v_days,
      'dayMark', true);
  end if;

  v_row := public._submit_request_for(
    p_employee_id,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- ØµÙ ØªÙØµÙÙ Ø§ÙØ¥Ø¬Ø§Ø²Ø© + ØªÙÙÙØ° ÙÙØ±Ù ÙÙØ¹Ø§Ø±Ø¶Ø© (ÙÙØ³ ÙØ³Ø§Ø± submit_my_request)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, p_employee_id, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© Ø¯ÙÙ ÙÙØ§ÙÙØ©', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© (ÙØ§ ØªØ³ØªÙØ¬Ø¨ ÙÙØ§ÙÙØ© Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø±)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'ØªÙÙÙØ° ÙÙØ±Ù ÙØ¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø©',
        format('ÙÙ %s Ø¥ÙÙ %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
    end if;
  end if;

  return v_row;
end;
$function$;

-- get_my_attendance_history(integer,timestamp with time zone,integer)
CREATE OR REPLACE FUNCTION public.get_my_attendance_history(p_limit integer DEFAULT 60, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_days integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_limit       integer := greatest(1, least(coalesce(p_limit, 60), 200));
  v_cutoff      timestamptz;
  v_result      jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode = '42501';
  end if;

  -- p_days: ØªØµÙÙØ© Ø¥ÙÙ Ø¢Ø®Ø± N ÙÙÙ (Ø§Ø®ØªÙØ§Ø±Ù)
  if p_days is not null and p_days > 0 then
    v_cutoff := now() - make_interval(days => p_days);
  end if;

  select coalesce(jsonb_agg(item order by event_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      ae.event_at,
      jsonb_build_object(
        'id',                 ae.id,
        'eventType',          ae.event_type,
        'eventAt',            ae.event_at,
        'status',             ae.status,
        'verificationStatus', ae.verification_status,
        'lateMinutes',        ae.late_minutes,
        'requiresReview',     ae.requires_review,
        'accuracyMeters',     ae.accuracy_meters,
        'distanceMeters',     ae.distance_meters,
        'source',             ae.source,
        'notes',              ae.notes
      ) as item
    from public.attendance_events ae
    where ae.employee_id = v_employee_id
      and (p_before is null or ae.event_at < p_before)
      and (v_cutoff  is null or ae.event_at >= v_cutoff)
    order by ae.event_at desc
    limit v_limit
  ) history;

  return v_result;
end;
$function$;

-- get_mobile_manager_operations(date,date)
CREATE OR REPLACE FUNCTION public.get_mobile_manager_operations(p_from date DEFAULT ((now() AT TIME ZONE 'Africa/Cairo'::text))::date, p_to date DEFAULT (((now() AT TIME ZONE 'Africa/Cairo'::text))::date + 14))
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 45 then
    raise exception 'نطاق تواريخ العمليات غير صالح' using errcode = '22023';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1
      from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  with team_scope as (
    select e.id, e.employee_code, e.full_name_ar
    from public.manager_relations mr
    join public.employees e on e.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
      and e.is_active = true
      and e.is_deleted = false
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'metrics', jsonb_build_object(
      'scheduledToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status = 'scheduled'
      ),
      'awayToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status in ('leave','mission','rest','holiday')
      ),
      'overdueTasks', (
        select count(*)
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress') and t.due_date < v_today
      ),
      'expiringDocuments', (
        select count(*)
        from public.documents d
        join team_scope ts on ts.id = d.owner_employee_id
        where d.status <> 'archived' and d.expiry_date between v_today and v_today + 60
      ),
      'missingReports', (
        select count(*)
        from team_scope ts
        where not exists (
          select 1 from public.daily_reports dr
          where dr.employee_id = ts.id and dr.report_date = v_today
        )
      )
    ),
    'calendar', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rd.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'workDate', rd.work_date,
        'dayStatus', rd.day_status,
        'shiftName', s.name,
        'startsAt', coalesce(rd.start_override, s.start_time),
        'endsAt', coalesce(rd.end_override, s.end_time),
        'notes', rd.notes
      ) order by rd.work_date, ts.full_name_ar)
      from public.roster_days rd
      join team_scope ts on ts.id = rd.employee_id
      left join public.shifts s on s.id = rd.shift_id
      where rd.work_date between p_from and p_to and rd.day_status <> 'cancelled'
    ), '[]'::jsonb),
    'documentAlerts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'title', d.title,
        'documentType', d.doc_type,
        'expiryDate', d.expiry_date,
        'status', case when d.expiry_date < v_today then 'expired' else d.status end
      ) order by d.expiry_date, ts.full_name_ar)
      from public.documents d
      join team_scope ts on ts.id = d.owner_employee_id
      where d.status <> 'archived' and d.expiry_date <= v_today + 60
    ), '[]'::jsonb),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'employeeId', x.employee_id,
        'employeeName', x.employee_name,
        'title', x.title,
        'priority', x.priority,
        'status', x.status,
        'dueDate', x.due_date,
        'isOverdue', x.due_date is not null and x.due_date < v_today
      ) order by x.is_overdue desc, x.due_date nulls last, x.created_at desc)
      from (
        select t.*, ts.id employee_id, ts.full_name_ar employee_name,
          (t.due_date is not null and t.due_date < v_today) is_overdue
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress')
        order by is_overdue desc, t.due_date nulls last, t.created_at desc
        limit 40
      ) x
    ), '[]'::jsonb),
    'missingReports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code
      ) order by ts.full_name_ar)
      from team_scope ts
      where not exists (
        select 1 from public.daily_reports dr
        where dr.employee_id = ts.id and dr.report_date = v_today
      )
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result;

  return v_result;
end;
$function$;

-- get_system_overview()
CREATE OR REPLACE FUNCTION public.get_system_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['system.settings.read','settings.read','system.manage','system.error.view'])) then
    raise exception 'وصول نظرة النظام مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'enabledFlags', (select count(*) from public.feature_flags where is_enabled = true),
    'totalFlags', (select count(*) from public.feature_flags),
    'unresolvedErrors', (select count(*) from public.app_error_events where resolved = false),
    'fatalErrors', (select count(*) from public.app_error_events where resolved = false and level = 'fatal'),
    'latestBackupStatus', (select status from public.system_backups order by created_at desc limit 1),
    'latestBackupAt', (select coalesce(finished_at, started_at, created_at) from public.system_backups order by created_at desc limit 1),
    'settingsCount', (select count(*) from public.system_settings),
    'recentErrors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id, 'level', q.level, 'source', q.source,
        'message', q.message, 'occurredAt', q.occurred_at
      ) order by q.occurred_at desc)
      from (
        select id, level, source, message, occurred_at
        from public.app_error_events where resolved = false order by occurred_at desc limit 8
      ) q
    ), '[]'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'key', f.flag_key, 'name', f.name_ar,
        'enabled', f.is_enabled, 'rolloutPercent', f.rollout_percent, 'environment', f.environment
      ) order by f.flag_key)
      from public.feature_flags f
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- get_my_access_context()
CREATE OR REPLACE FUNCTION public.get_my_access_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_employee_id uuid;
  v_display_name text;
  v_employee_code text;
  v_photo_url text;
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_operations boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
begin
  if v_user_id is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'ÙØ³ØªØ®Ø¯Ù Ø§ÙÙØ¸Ø§Ù'), e.employee_code, e.photo_url
    into v_employee_id, v_display_name, v_employee_code, v_photo_url
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id
    and p.status in ('active', 'pending');

  if not found then
    raise exception 'لا يوجد ملف موظف نشط' using errcode = '42501';
  end if;

  select coalesce(array_agg(distinct r.slug order by r.slug), '{}'::text[])
    into v_roles
  from public.user_roles ur
  join public.roles r on r.id = ur.role_id
  where ur.user_id = v_user_id
    and ur.effective_from <= now()
    and (ur.effective_to is null or ur.effective_to > now());

  v_is_full := public.current_is_full_access();
  if v_is_full then
    v_permissions := array['*']::text[];
  else
    select coalesce(array_agg(distinct p.code order by p.code), '{}'::text[])
      into v_permissions
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = v_user_id
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now());
  end if;

  v_is_executive := v_roles && array['executive-director', 'executive']::text[];
  v_is_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_manager := v_is_operations or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];

  -- âââ ÙØ³Ø§Ø­Ø§Øª Ø§ÙØ¹ÙÙ âââ
  -- ÙÙ ÙÙ ÙØ¯ÙÙ Ø³Ø¬Ù ÙÙØ¸Ù (ÙØ§ Ø¹Ø¯Ø§ Ø§ÙØªÙÙÙØ°Ù) ÙØ­ØµÙ Ø¹ÙÙ ÙØ³Ø§Ø­Ø© employee
  if v_employee_id is not null and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'manager');
  end if;
  if v_is_operations and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'field_operations');
  end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  -- 0151: Ø§ÙØ£Ø¯ÙÙ Ø§ÙØ±Ø¦ÙØ³Ù ÙØ±Ù ÙÙØ­Ø© HR Ø£ÙØ¶Ø§Ù
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  -- âââ Ø§ÙÙØ³Ø§Ø­Ø© Ø§ÙØ§ÙØªØ±Ø§Ø¶ÙØ© âââ
  if v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_hr then
    v_default_workspace := 'hr';
  elsif v_is_operations then
    v_default_workspace := 'field_operations';
  elsif v_is_manager then
    v_default_workspace := 'manager';
  elsif v_employee_id is not null then
    v_default_workspace := 'employee';
  else
    raise exception 'لا توجد مساحة عمل معينة' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'userId', v_user_id,
    'employeeId', v_employee_id,
    'displayName', v_display_name,
    'employeeCode', v_employee_code,
    'photoUrl', v_photo_url,
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'attendancePolicy', jsonb_build_object(
      -- 0196: Ø§ÙØ¨ØµÙØ© ÙÙÙ Ø§ÙÙÙØ¸ÙÙÙ ÙØ§ Ø¹Ø¯Ø§ Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù ÙÙØ·.
      -- Ø§ÙØ³ÙØ±ØªÙØ± Ø§ÙØªÙÙÙØ°Ù ÙØ§ÙØ£Ø¯ÙÙ ÙÙØ¸ÙÙÙ ÙØ­ØªØ§Ø¬ÙÙ Ø¨ØµÙØ©.
      'attendanceRequired', not v_is_executive and v_employee_id is not null,
      'selfPunchEnabled', not v_is_executive and v_employee_id is not null,
      'liveLocationResponseEnabled', not v_is_executive and v_employee_id is not null
    )
  );
end;
$function$;

-- get_onboarding_admin_catalog(integer)
CREATE OR REPLACE FUNCTION public.get_onboarding_admin_catalog(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['onboarding.journey.read','onboarding.journey.manage'])) then
    raise exception 'وصول كتالوج التهيئة مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'journeys', coalesce((
      select jsonb_agg(q.payload order by q.created_at desc)
      from (
        select j.created_at, jsonb_build_object(
          'id', j.id, 'employeeId', j.employee_id,
          'employeeName', e.full_name_ar, 'employeeCode', e.employee_code,
          'startedAt', j.started_at, 'probationEnd', j.probation_end,
          'status', j.status,
          'progress', case when count(t.id) = 0 then 0 else round(100.0 * (count(t.id) filter (where t.status in ('completed','skipped'))) / count(t.id))::integer end,
          'totalTasks', count(t.id)::integer,
          'completedTasks', (count(t.id) filter (where t.status in ('completed','skipped')))::integer,
          'tasks', coalesce(jsonb_agg(jsonb_build_object(
            'id', t.id, 'title', t.title, 'ownerRole', t.owner_role,
            'assigneeId', t.assignee_id, 'dueOffsetDays', t.due_offset_days,
            'status', t.status, 'completedAt', t.completed_at
          ) order by t.created_at) filter (where t.id is not null), '[]'::jsonb)
        ) payload
        from public.onboarding_journeys j
        join public.employees e on e.id = j.employee_id
        left join public.onboarding_tasks t on t.journey_id = j.id
        group by j.id, e.id
        order by j.created_at desc
        limit greatest(1, least(coalesce(p_limit, 100), 250))
      ) q
    ), '[]'::jsonb),
    'eligibleEmployees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.full_name_ar, 'code', e.employee_code,
        'status', e.status, 'probationEnd', e.probation_end
      ) order by e.full_name_ar)
      from public.employees e
      where e.is_deleted = false and e.status in ('draft','invited','onboarding','active')
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- revoke_managed_device(uuid,text)
CREATE OR REPLACE FUNCTION public.revoke_managed_device(p_device_id uuid, p_reason text)
 RETURNS managed_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.managed_devices;
begin
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'سحب الجهاز مرفوض' using errcode='42501';
  end if;
  update public.managed_devices set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revoke_reason=p_reason
  where id=p_device_id returning * into v_row;
  if not found then raise exception 'لم يتم العثور على الجهاز' using errcode='P0002'; end if;
  perform public.log_security_event('device.revoked','high','blocked',v_row.installation_id,jsonb_build_object('reason',p_reason,'userId',v_row.user_id));
  return v_row;
end;
$function$;

-- get_my_mobile_profile()
CREATE OR REPLACE FUNCTION public.get_my_mobile_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_employee_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'jobTitle', jt.name,
    'position', p.name,
    'grade', g.name,
    'department', d.name,
    'team', t.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id,
        'type', doc.doc_type,
        'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case
          when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired'
          else doc.status
        end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id = e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id,
        'assetName', ai.name_ar,
        'assetType', ai.asset_type,
        'serial', ai.serial,
        'assignedAt', aa.handed_over_at,
        'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id = aa.asset_id
      where aa.employee_id = e.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.job_grades g on g.id = e.grade_id
  left join public.departments d on d.id = e.department_id
  left join public.teams t on t.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = v_employee_id and e.is_deleted = false;

  if v_result is null then
    raise exception 'ملف الموظف غير موجود' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

-- get_my_mobile_team(integer)
CREATE OR REPLACE FUNCTION public.get_my_mobile_team(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', ad.status,
    'lateMinutes', coalesce(ad.late_minutes, 0),
    'firstCheckIn', ad.first_check_in,
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      and child.is_active = true
      and child.is_deleted = false
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = (now() at time zone 'Africa/Cairo')::date;

  return v_result;
end;
$function$;

-- get_mobile_action_target(text,text)
CREATE OR REPLACE FUNCTION public.get_mobile_action_target(p_action_id text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_uuid uuid;
  v_prefix text := lower(trim(coalesce(p_kind, '')))||'-';
  v_raw_id text;
  v_allowed boolean := false;
  v_emp uuid;
begin
  if p_action_id is null or p_kind is null or position(v_prefix in lower(p_action_id)) <> 1 then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end if;
  v_raw_id := substring(p_action_id from length(v_prefix) + 1);
  begin
    v_uuid := v_raw_id::uuid;
  exception when others then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end;

  case lower(p_kind)
    when 'request' then
      select exists(
        select 1 from public.requests r
        where r.id = v_uuid
          and (
            r.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(r.employee_id, 'requests.request.approve')
            or public.can_access_employee(r.employee_id, 'requests.request.read')
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','request','recordId',v_uuid,'mobileRoute','request_detail');

    when 'kpi' then
      select exists(
        select 1 from public.kpi_evaluations k
        where k.id = v_uuid
          and (
            k.employee_id = public.current_employee_id()
            or public.current_is_full_access()
            or public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')
            or public.has_any_permission(array[
              'performance.kpi.read','performance.kpi.secretary_review',
              'performance.kpi.executive_review','performance.kpi.finalize'
            ])
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','kpi','recordId',v_uuid,'mobileRoute','kpi_form');

    when 'decision' then
      select exists(
        select 1 from public.administrative_decisions d
        where d.id = v_uuid and d.status = 'published'
          and (
            public.current_is_full_access()
            or public.has_any_permission(array['comms.decision.read','comms.decision.manage'])
            or exists (
              select 1 from public.decision_recipients dr
              where dr.decision_id=d.id and dr.employee_id=public.current_employee_id()
            )
          )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','decision','recordId',v_uuid,'mobileRoute','feed_detail');

    -- Ø­Ø¶ÙØ±/Ø¨ØµÙØ©: Ø£Ù Ø­Ø¯Ø«/ØªØµØ­ÙØ­/Ø·ÙØ¨ ÙØ®ØµÙÙ Ø£Ù Ø£ÙÙÙ ØµÙØ§Ø­ÙØ© ÙØ±Ø§Ø¬Ø¹ØªÙ
    when 'attendance' then
      select (
        exists(select 1 from public.attendance_events e
               where e.id = v_uuid and e.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_corrections c
                  where c.id = v_uuid and c.employee_id = public.current_employee_id())
        or exists(select 1 from public.attendance_punch_attempts pa
                  where pa.attendance_event_id = v_uuid and pa.employee_id = public.current_employee_id())
        or public.current_is_full_access()
        or public.has_any_permission(array[
          'attendance.review','attendance.manage','attendance.admin',
          'attendance.attendance.review','attendance.attendance.manage'
        ])
      ) into v_allowed;
      if not v_allowed then
        -- fallback: Ø¥Ù ÙÙ ÙÙØ¬Ø¯ Ø³Ø¬Ù Ø£ØµÙØ§ÙØ Ø§Ø³ÙØ­ Ø¨Ø§ÙÙØªØ­ ÙØ¹Ø±Ø¶ ØµÙØ­Ø© Ø§ÙØ­Ø¶ÙØ± Ø§ÙØ¹Ø§ÙØ©
        -- (Ø§ÙÙÙÙØ© ÙØ¤ÙØ¯Ø© Ø¹Ø¨Ø± ÙÙÙÙØ§ UUID ØµØ§ÙØ­ â ÙØ§ ØªØ³Ø±ÙØ¨ Ø¨ÙØ§ÙØ§Øª).
        return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');
      end if;
      return jsonb_build_object('kind','attendance','recordId',v_uuid,'mobileRoute','attendance_detail');

    -- ÙØ²Ø§Ø¹: Ø£Ø­Ø¯ Ø§ÙØ£Ø·Ø±Ø§Ù Ø£Ù Ø¹Ø¶Ù ÙØ¬ÙØ© Ø£Ù ÙØ¯ÙØ± ÙØ²Ø§Ø¹Ø§Øª
    when 'dispute' then
      select exists(
        select 1 from public.dispute_cases dc
        where dc.id = v_uuid and (
          dc.actor_employee_id = public.current_employee_id()
          or dc.respondent_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.can_access_dispute(dc.id)
          or public.has_any_permission(array['disputes.case.read','disputes.case.manage'])
        )
      ) into v_allowed;
    if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','dispute','recordId',v_uuid,'mobileRoute','dispute_detail');

    -- ÙÙÙØ©: Ø§ÙÙÙÙÙÙ Ø£Ù Ø§ÙÙÙØ³ÙÙØ¯ Ø£Ù ÙØ¯ÙØ± Ø§ÙÙÙØ§Ù
    when 'task' then
      select exists(
        select 1 from public.tasks t
        where t.id = v_uuid and (
          t.assignee_employee_id = public.current_employee_id()
          or t.created_by_employee_id = public.current_employee_id()
          or public.current_is_full_access()
          or public.has_any_permission(array['tasks.task.read','tasks.task.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','task','recordId',v_uuid,'mobileRoute','task_detail');

    -- Ø¥Ø¹ÙØ§Ù: ÙÙØ´ÙØ± Ø£Ù ÙÙØ¬ÙÙ Ø¥ÙÙÙ
    when 'announcement' then
      select exists(
        select 1 from public.announcements a
        where a.id = v_uuid and (
          a.status = 'published'
          or public.current_is_full_access()
          or public.has_any_permission(array['comms.announcement.read','comms.announcement.manage'])
        )
      ) into v_allowed;
      if not v_allowed then raise exception 'لا تملك صلاحية على هذا الموظف' using errcode='42501'; end if;
      return jsonb_build_object('kind','announcement','recordId',v_uuid,'mobileRoute','feed_detail');

    -- ØªÙØ¯ÙØ±: Ø§ÙÙØ³ØªÙÙ Ø£Ù Ø§ÙÙÙØ±Ø³Ù Ø£Ù Ø§ÙØ¥Ø¯Ø§Ø±Ø©
    when 'recognition' then
      select (
        exists(select 1 from public.recognitions r
               where r.id = v_uuid and (
                 r.recipient_employee_id = public.current_employee_id()
                 or r.nominated_by = public.current_employee_id()
               ))
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      ) into v_allowed;
    if not v_allowed then
        -- Ø§ÙØªÙØ¯ÙØ± Ø§ÙØ¹Ø§Ù ÙØ¸ÙØ± ÙÙ feed Ø­ØªÙ ÙÙ ÙÙ Ø£ÙÙ Ø·Ø±ÙØ§Ù ÙØ¨Ø§Ø´Ø±Ø§Ù
        return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');
      end if;
      return jsonb_build_object('kind','recognition','recordId',v_uuid,'mobileRoute','feed_detail');

    else
      raise exception 'unsupported action kind' using errcode='22023';
  end case;
end;
$function$;

-- activate_verified_passkey_device(uuid,uuid,text,text,bigint,text[],text,text,text,boolean)
CREATE OR REPLACE FUNCTION public.activate_verified_passkey_device(p_employee_id uuid, p_user_id uuid, p_credential_id text, p_public_key text, p_sign_count bigint, p_transports text[], p_device_label text, p_webauthn_user_id text, p_credential_device_type text, p_credential_backed_up boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_credential public.passkey_credentials;
  v_device public.employee_devices;
  v_hash text;
begin
  if p_employee_id is null or p_user_id is null or nullif(trim(p_credential_id), '') is null then
    raise exception 'هوية جهاز موثّق مطلوبة' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.employees
    where id = p_employee_id and user_id = p_user_id
  ) then
    raise exception 'employee/user link mismatch' using errcode = '42501';
  end if;

  -- passkey_credentials ØªØ¨ÙÙ active (ÙÙ credential ÙÙÙØ©Ø ÙÙØ³Øª Ø³ÙØ§Ø³Ø© ÙÙØ§ÙÙØ©)
  insert into public.passkey_credentials(
    employee_id, user_id, credential_id, public_key, sign_count,
    transports, device_label, status, trusted, webauthn_user_id,
    credential_device_type, credential_backed_up, created_by
  ) values (
    p_employee_id, p_user_id, p_credential_id, p_public_key, p_sign_count,
    p_transports, left(coalesce(p_device_label, 'ÙØ§ØªÙ Ø§ÙÙÙØ¸Ù'), 120),
    'active', true, nullif(p_webauthn_user_id, ''),
    p_credential_device_type, p_credential_backed_up, p_user_id
  ) returning * into v_credential;

  v_hash := encode(digest(convert_to(p_credential_id, 'UTF8'), 'sha256'), 'hex');
  -- V18 Â§5: Ø§ÙØ¬ÙØ§Ø² ÙÙØ³Ø¬ÙÙÙ Ø¨Ø­Ø§ÙØ© pending ÙÙÙØªØ¸Ø± ÙÙØ§ÙÙØ© Ø§ÙÙØ³Ø¤ÙÙ
  insert into public.employee_devices(
    employee_id, user_id, device_identifier_hash, credential_id, public_key,
    device_name, platform, status, registered_at, metadata
  ) values (
    p_employee_id, p_user_id, v_hash, p_credential_id, p_public_key,
    left(coalesce(p_device_label, 'ÙØ§ØªÙ Ø§ÙÙÙØ¸Ù'), 120), 'android', 'pending', now(),
    jsonb_build_object(
      'serverVerified', true,
      'credentialDeviceType', p_credential_device_type,
      'credentialBackedUp', p_credential_backed_up,
      'passkeyCredentialId', v_credential.id
    )
  )
  on conflict (employee_id, device_identifier_hash) do update set
    user_id = excluded.user_id,
    credential_id = excluded.credential_id,
    public_key = excluded.public_key,
    device_name = excluded.device_name,
    status = 'pending',
    revoked_at = null,
    registered_at = now(),
    approved_by = null,
    approved_at = null,
    rejection_reason = null,
    metadata = excluded.metadata
  returning * into v_device;

  return jsonb_build_object(
    'id', v_credential.id,
    'credential_id', v_credential.credential_id,
    'device_label', v_credential.device_label,
    'status', 'pending',
    'created_at', v_credential.created_at,
    'device_id', v_device.id,
    'verified', true,
    'requiresApproval', true
  );
end;
$function$;

-- get_organization_admin_catalog()
CREATE OR REPLACE FUNCTION public.get_organization_admin_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'organization.entity.read','organization.org_chart.read',
      'organization.department.manage','organization.position.manage',
      'organization.unit.manage'
    ])
  ) then
    raise exception 'وصول كتالوج الهيكل مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'entities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.code, 'name', e.name,
        'active', e.is_active
      ) order by e.name)
      from public.legal_entities e
    ), '[]'::jsonb),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'entityId', b.legal_entity_id, 'code', b.code,
        'name', b.name, 'active', b.is_active
      ) order by b.name)
      from public.branches b
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'entityId', d.legal_entity_id, 'branchId', d.branch_id,
        'parentId', d.parent_id, 'managerId', d.manager_id,
        'code', d.code, 'name', d.name, 'nameEn', d.name_en,
        'active', d.is_active,
        'employeeCount', (select count(*) from public.employees e where e.department_id = d.id and e.is_deleted = false),
        'positionCount', (select count(*) from public.positions p where p.department_id = d.id and p.is_active = true)
      ) order by d.name)
      from public.departments d
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'departmentId', t.department_id, 'parentId', t.parent_id,
        'leadId', t.lead_id, 'code', t.code, 'name', t.name,
        'active', t.is_active,
        'employeeCount', (select count(*) from public.employees e where e.team_id = t.id and e.is_deleted = false)
      ) order by t.name)
      from public.teams t
    ), '[]'::jsonb),
    'positions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'departmentId', p.department_id, 'teamId', p.team_id,
        'jobTitleId', p.job_title_id, 'gradeId', p.job_grade_id,
        'reportsToId', p.reports_to_position_id,
        'code', p.code, 'name', p.name, 'nameEn', p.name_en,
        'headcount', p.headcount, 'active', p.is_active,
        'assignedCount', (select count(*) from public.employees e where e.position_id = p.id and e.is_deleted = false and e.status <> 'terminated')
      ) order by p.name)
      from public.positions p
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.employee_code, 'name', e.full_name_ar,
        'departmentId', e.department_id, 'teamId', e.team_id,
        'positionId', e.position_id, 'active', e.is_active
      ) order by e.full_name_ar)
      from public.employees e where e.is_deleted = false
    ), '[]'::jsonb),
    'jobTitles', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'name', j.name, 'active', j.is_active) order by j.name)
      from public.job_titles j
    ), '[]'::jsonb),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'level', g.level, 'active', g.is_active) order by g.level, g.name)
      from public.job_grades g
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- enqueue_integration_event(uuid,text,text,uuid,text,jsonb,jsonb,text)
CREATE OR REPLACE FUNCTION public.enqueue_integration_event(p_integration_id uuid, p_event_type text, p_aggregate_type text, p_aggregate_id uuid, p_idempotency_key text, p_payload jsonb, p_headers jsonb DEFAULT '{}'::jsonb, p_correlation_id text DEFAULT NULL::text)
 RETURNS integration_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.integration_outbox;
begin
  if length(trim(coalesce(p_idempotency_key,''))) < 8 then raise exception 'مفتاح منع التكرار مطلوب' using errcode='22023'; end if;
  insert into public.integration_outbox(integration_id,event_type,aggregate_type,aggregate_id,idempotency_key,payload,headers,correlation_id)
  values(p_integration_id,p_event_type,p_aggregate_type,p_aggregate_id,p_idempotency_key,coalesce(p_payload,'{}'::jsonb),coalesce(p_headers,'{}'::jsonb),p_correlation_id)
  on conflict (idempotency_key) do update set idempotency_key=excluded.idempotency_key
  returning * into v_row;
  return v_row;
end;
$function$;

-- create_job_requisition_admin(uuid,text,integer,text,text,boolean)
CREATE OR REPLACE FUNCTION public.create_job_requisition_admin(p_department_id uuid, p_title text, p_headcount integer, p_reason text DEFAULT NULL::text, p_budget_range text DEFAULT NULL::text, p_submit boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.requisition.manage')) then
    raise exception 'إدارة طلبات التعيين مرفوضة' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_title), '') is null or coalesce(p_headcount, 0) <= 0 then
    raise exception 'القسم والمنصب وعدد موجب مطلوبة' using errcode = '22023';
  end if;
  insert into public.job_requisitions(
    department_id, title, headcount, reason, budget_range,
    status, requested_by, current_stage, created_by
  ) values (
    p_department_id, trim(p_title), p_headcount, nullif(trim(p_reason), ''), nullif(trim(p_budget_range), ''),
    case when p_submit then 'pending' else 'draft' end,
    public.current_employee_id(), case when p_submit then 'approval' else 'draft' end, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$function$;

-- resolve_mobile_action_target(text,text)
CREATE OR REPLACE FUNCTION public.resolve_mobile_action_target(p_action_id text, p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_kind text := lower(trim(coalesce(p_kind, '')));
  v_raw text := trim(coalesce(p_action_id, ''));
  v_uuid uuid;
  v_req public.live_location_requests;
  v_resolved_kind text;
begin
  -- ØªØ·Ø¨ÙØ¹ Ø§ÙØ£Ø³ÙØ§Ø¡ Ø§ÙÙØªØ±Ø§Ø¯ÙØ© Ø§ÙÙØ§Ø¯ÙØ© ÙÙ Ø§ÙØ¥Ø´Ø¹Ø§Ø±Ø§Øª ÙÙÙ ØªØ·Ø¨ÙÙ Ø§ÙÙÙØ¨Ø§ÙÙ:
  -- location/location_request/live_location/live_location_request â
  --   live_location_request (Ø¨Ø§ÙØ¥Ø¶Ø§ÙØ© Ø¥ÙÙ Ø§ÙØµÙØºØ© Ø§ÙØ¬ÙØ¹ÙØ© live_location_requests)
  -- attendance_alert/punch_reminder/attendance/attendance_daily/
  --   attendance_event/attendance_corrections/overtime_records/work_rosters â attendance
  -- kpi_evaluation â kpi, request_decision/requests â request, dispute_case â dispute
  v_resolved_kind := case v_kind
    when 'location' then 'live_location_request'
    when 'location_request' then 'live_location_request'
    when 'live_location_request' then 'live_location_request'
    when 'live_location' then 'live_location_request'
    when 'live_location_requests' then 'live_location_request'
    when 'attendance_alert' then 'attendance'
    when 'punch_reminder' then 'attendance'
    when 'attendance' then 'attendance'
    when 'attendance_daily' then 'attendance'
    when 'attendance_event' then 'attendance'
    when 'attendance_corrections' then 'attendance'
    when 'overtime_records' then 'attendance'
    when 'work_rosters' then 'attendance'
    when 'request' then 'request'
    when 'requests' then 'request'
    when 'request_decision' then 'request'
    when 'kpi' then 'kpi'
    when 'kpi_evaluation' then 'kpi'
    when 'decision' then 'decision'
    when 'dispute' then 'dispute'
    when 'dispute_case' then 'dispute'
    when 'task' then 'task'
    when 'announcement' then 'announcement'
    when 'recognition' then 'recognition'
    else null
  end;

  if v_resolved_kind is null then
    raise exception 'unsupported action kind' using errcode = '22023';
  end if;

  -- strip prefix Ø¥Ù ÙÙØ¬Ø¯ (kind-uuid)
  if position(v_resolved_kind || '-' in lower(v_raw)) = 1 then
    v_raw := substring(v_raw from length(v_resolved_kind) + 2);
  end if;

  begin
    v_uuid := v_raw::uuid;
  exception when others then
    raise exception 'معرّف إجراء غير صالح' using errcode = '22023';
  end;

  -- live_location_request: ØªØ®ÙÙÙ Ø®Ø§Øµ (ÙØ§ ÙÙØ± Ø¹Ø¨Ø± get_mobile_action_target)
  if v_resolved_kind = 'live_location_request' then
    select * into v_req from public.live_location_requests where id = v_uuid;
    if not found then
      raise exception 'هدف الإجراء غير موجود' using errcode = 'P0002';
    end if;
    if not (
      v_req.employee_id = public.current_employee_id()
      or v_req.requested_by = public.current_employee_id()
      or public.current_is_full_access()
      or public.can_access_employee(v_req.employee_id, 'live_location.view_response')
    ) then
      raise exception 'لا تملك صلاحية على هذا الموظف' using errcode = '42501';
    end if;

    return jsonb_build_object(
      'kind', v_resolved_kind,
      'recordId', v_uuid,
      'mobileRoute', 'live_location_request'
    );
  end if;

  -- Ø¨ÙÙØ© Ø§ÙØ£ÙÙØ§Ø¹: Ø§ÙÙØ±ÙØ± Ø¹Ø¨Ø± Ø§ÙØ¯Ø§ÙØ© Ø§ÙØ£Ù Ø§ÙØªÙ ØªØ­ÙÙ Ø§ÙØªØ®ÙÙÙ Ø§ÙÙÙØ§Ø³Ø¨
  return public.get_mobile_action_target(v_resolved_kind || '-' || v_uuid::text, v_resolved_kind);
end;
$function$;

-- grant_weekly_rest_credit_bulk(uuid[],date,integer)
CREATE OR REPLACE FUNCTION public.grant_weekly_rest_credit_bulk(p_employee_ids uuid[], p_work_date date, p_days integer DEFAULT 1)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_type_id uuid;
  v_emp     uuid;
  v_year    integer;
  v_day     date;
  v_granted integer := 0;
  v_per_emp integer;
begin
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if p_days < 1 or p_days > 365 then
    raise exception 'INVALID_DAYS' using errcode = '22023';
  end if;
  if p_employee_ids is null or array_length(p_employee_ids, 1) is null then
    raise exception 'موظف واحد على الأقل مطلوب' using errcode = '22023';
  end if;
  if array_length(p_employee_ids, 1) > 500 then
    raise exception 'too many employees (max 500)' using errcode = '22023';
  end if;

  select id into v_type_id
  from public.leave_types
  where code = 'weekly_rest_comp';
  if v_type_id is null then
    raise exception 'LEAVE_TYPE_NOT_FOUND' using errcode = 'P0002';
  end if;

  foreach v_emp in array p_employee_ids loop
    -- ÙØªØ¬Ø§ÙØ² Ø§ÙÙÙØ¸ÙÙÙ ØºÙØ± Ø§ÙÙØ´Ø·ÙÙ/Ø§ÙÙØ­Ø°ÙÙÙÙ Ø¨Ø¯Ù ÙØ´Ù Ø§ÙØ¯ÙØ¹Ø© ÙØ§ÙÙØ©.
    if not exists(
      select 1 from public.employees
      where id = v_emp and is_active and not is_deleted
    ) then
      continue;
    end if;

    v_day := p_work_date;
    v_per_emp := 0;
    while v_per_emp < p_days loop
      v_year := extract(year from v_day)::integer;
      perform public.apply_leave_ledger_entry(
        v_emp, v_type_id, v_year, 'credit', 1,
        'weekly-rest:manual:' || v_emp::text || ':' || v_day::text,
        null,
        'ÙÙØ­ Ø¨Ø¯Ù Ø±Ø§Ø­Ø© ÙØ¯ÙÙ Ø¹Ù ÙÙÙ ' || to_char(v_day, 'YYYY-MM-DD'),
        jsonb_build_object('workDate', v_day::text, 'source', 'manual-grant-bulk'));
      v_per_emp := v_per_emp + 1;
      v_day := v_day + 1;
    end loop;
    v_granted := v_granted + 1;
  end loop;

  return v_granted;
end $function$;

-- mark_notification_read(uuid)
CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
 RETURNS notifications
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.notifications;
begin
  update public.notifications
     set is_read = true,
         read_at = coalesce(read_at, now())
   where id = p_notification_id
     and recipient_user_id = auth.uid()
  returning * into v_row;

  if v_row.id is null then
    raise exception 'الإشعار غير موجود أو ليس لك' using errcode = '42501';
  end if;

  return v_row;
end;
$function$;

-- get_hr_reports_summary()
CREATE OR REPLACE FUNCTION public.get_hr_reports_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_att jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
begin
  -- ÙØ­Øµ Ø§ÙØµÙØ§Ø­ÙØ©
  if not (public.current_is_full_access()
          or public.has_permission('reports.people.read')
          or public.has_permission('attendance.record.read')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- âââ Ø§ÙØ­Ø¶ÙØ± âââ
  -- attendance_events: event_type = 'CHECK_IN'/'CHECK_OUT' (Ø£Ø­Ø±Ù ÙØ¨ÙØ±Ø©)
  -- event_at (timestamptz) â ÙØ§ ÙÙØ¬Ø¯ Ø¹ÙÙØ¯ event_date
  -- requires_review (ÙÙÙØ³ needs_review)
  select jsonb_build_object(
    'totalEvents', count(*),
    'checkIns',    count(*) filter (where event_type = 'CHECK_IN'  and (event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date),
    'checkOuts',   count(*) filter (where event_type = 'CHECK_OUT' and (event_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date),
    'pendingReview', count(*) filter (where requires_review = true),
    'thisMonth',   count(*) filter (where event_at at time zone 'Africa/Cairo' >= date_trunc('month', (now() at time zone 'Africa/Cairo')::date))
  ) into v_att from public.attendance_events;

  -- âââ Ø§ÙØ¥Ø¬Ø§Ø²Ø§Øª âââ
  -- leave_requests ÙØ§ ÙØ­ØªÙÙ Ø¹ÙÙ Ø¹ÙÙØ¯ status â Ø§ÙØ­Ø§ÙØ© ÙÙ Ø¬Ø¯ÙÙ requests Ø¹Ø¨Ø± request_id
  select jsonb_build_object(
    'totalRequests', count(*),
    'approved',  count(*) filter (where r.status = 'approved'),
    'pending',   count(*) filter (where r.status = 'pending'),
    'rejected',  count(*) filter (where r.status = 'rejected'),
    'activeNow', count(*) filter (where r.status = 'approved'
                                    and (now() at time zone 'Africa/Cairo')::date between lr.start_date and lr.end_date)
  ) into v_leaves
  from public.leave_requests lr
  join public.requests r on r.id = lr.request_id;

  -- âââ Ø§ÙØªÙÙÙÙØ§Øª âââ
  -- work_assignments.status Ø¨Ø£Ø­Ø±Ù ÙØ¨ÙØ±Ø©: APPROVED, IN_PROGRESS, COMPLETED, DRAFT, SUBMITTED, PENDING_APPROVAL ...
  select jsonb_build_object(
    'total',     count(*),
    'active',    count(*) filter (where status in ('APPROVED','IN_PROGRESS')),
    'completed', count(*) filter (where status = 'COMPLETED'),
    'pending',   count(*) filter (where status in ('DRAFT','SUBMITTED','PENDING_APPROVAL'))
  ) into v_assignments from public.work_assignments;

  -- âââ ÙØ¤Ø´Ø±Ø§Øª Ø§ÙØ£Ø¯Ø§Ø¡ âââ
  -- kpi_cycles.status: draft, open, in_review, suspended, finalized, locked (Ø£Ø­Ø±Ù ØµØºÙØ±Ø©)
  -- kpi_evaluations ÙØ§ ÙØ­ØªÙÙ Ø¹ÙÙ Ø¹ÙÙØ¯ status â ÙØ³ØªØ®Ø¯Ù workflow_status (Ø£Ø­Ø±Ù ÙØ¨ÙØ±Ø©)
  select jsonb_build_object(
    'activeCycles',         (select count(*) from public.kpi_cycles where status = 'open'),
    'totalEvaluations',     count(*),
    'pendingEvaluations',   count(*) filter (where workflow_status in (
      'DRAFT','OPEN_FOR_SELF_EVALUATION','SUBMITTED_TO_HR','HR_REVIEW',
      'SUBMITTED_TO_DIRECT_MANAGER','MANAGER_REVIEW','PARALLEL_REVIEW_IN_PROGRESS',
      'HR_EVALUATION_IN_PROGRESS','MANAGER_EVALUATION_IN_PROGRESS'
    )),
    'completedEvaluations', count(*) filter (where workflow_status in (
      'APPROVED','CLOSED','CYCLE_CLOSED','ARCHIVED','EXECUTIVE_ACKNOWLEDGED'
    ))
  ) into v_kpi from public.kpi_evaluations;

  -- âââ Ø§ÙÙØ²Ø§Ø¹Ø§Øª âââ
  -- Ø§ÙØ¬Ø¯ÙÙ: dispute_cases (ÙÙÙØ³ disputes)
  select jsonb_build_object(
    'total',     count(*),
    'open',      count(*) filter (where status in (
      'submitted','needs_more_information','accepted','under_review',
      'waiting_for_respondent','waiting_for_witness','session_scheduled',
      'session_completed','committee_deliberation','settlement_pending',
      'returned_to_committee','reopened','action_proposed','pending_execution'
    )),
    'resolved',  count(*) filter (where status in (
      'resolved_friendly','closed','decision_issued','executed',
      'cancelled_by_employee','rejected'
    )),
    'escalated', count(*) filter (where status = 'escalated_to_executive')
  ) into v_disputes from public.dispute_cases;

  -- âââ Ø·ÙØ¨Ø§Øª Ø§ÙÙÙÙØ¹ âââ
  -- location_requests.status: pending, fulfilled, rejected, expired, cancelled
  select jsonb_build_object(
    'totalRequests', count(*),
    'pending',   count(*) filter (where status = 'pending'),
    'responded', count(*) filter (where status = 'fulfilled')
  ) into v_location from public.location_requests;

  return jsonb_build_object(
    'attendance',   v_att,
    'leaves',       v_leaves,
    'assignments',  v_assignments,
    'kpi',          v_kpi,
    'disputes',     v_disputes,
    'location',     v_location,
    'generatedAt',  now()
  );
end;
$function$;

-- admin_create_leave_request(uuid,text,date,date,text,text,text,uuid)
CREATE OR REPLACE FUNCTION public.admin_create_leave_request(p_employee_id uuid, p_leave_type text, p_start_date date, p_end_date date, p_reason text DEFAULT NULL::text, p_title text DEFAULT NULL::text, p_handover_notes text DEFAULT NULL::text, p_substitute_employee_id uuid DEFAULT NULL::uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_leave_type_id     uuid;
  v_days              numeric;
  v_payload           jsonb;
  v_row               public.requests;
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- Ø§ÙØ¨ÙØ§Ø¨Ø©: full access Ø£Ù ØµÙØ§Ø­ÙØ© Ø¶Ø¨Ø· Ø£Ø±ØµØ¯Ø© Ø§ÙØ¥Ø¬Ø§Ø²Ø§Øª (ÙØ·Ø§Ø¨ÙØ© 0429/0026).
  if not (public.current_is_full_access() or public.has_permission('requests.leave.balance.adjust')) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'EMPLOYEE_REQUIRED' using errcode = '22023';
  end if;
  if not exists(
    select 1 from public.employees
    where id = p_employee_id and is_active and not is_deleted
  ) then
    raise exception 'EMPLOYEE_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- ØªÙØ§ÙÙ Ø®ÙÙÙ: emergency â casual (ÙÙØ³ submit_my_request 0401).
  if p_leave_type = 'emergency' then p_leave_type := 'casual'; end if;
  if p_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
    raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'leave start and end dates are required' using errcode = '22023';
  end if;
  if p_end_date < p_start_date then
    raise exception 'leave end date cannot precede start date' using errcode = '22023';
  end if;
  if p_start_date < v_today then
    raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'reason is required (min 3 chars)' using errcode = '22023';
  end if;

  select id into v_leave_type_id
  from public.leave_types
  where code = p_leave_type and is_active = true;
  if v_leave_type_id is null then
    raise exception 'leave type is inactive or unknown: %', p_leave_type using errcode = '22023';
  end if;

  v_days := (p_end_date - p_start_date) + 1;
  v_payload := jsonb_build_object(
    'leaveType', p_leave_type,
    'startDate', p_start_date,
    'endDate', p_end_date,
    'days', v_days,
    'immediate', (p_leave_type = 'casual'),
    'adminCreated', true,
    'handoverNotes', nullif(p_handover_notes,''),
    'substituteEmployeeId', p_substitute_employee_id);

  -- Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ³Ø¤ÙÙ ÙÙ Ø§ÙÙÙÙÙ Ø§ÙØ¥Ø¯Ø§Ø±Ù (ÙØ¹ ÙÙØ¹ Ø§ÙÙÙØ§ÙÙØ© Ø§ÙØ°Ø§ØªÙØ© + ØªÙØ¬ÙÙ Ø§ÙØªØ´ØºÙÙ).
  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  -- Ø¥ÙØ´Ø§Ø¡ Ø§ÙØ·ÙØ¨ ÙÙ ÙØ³Ø§Ø± Ø§ÙÙÙØ§ÙÙØ© Ø§ÙÙØ¹ØªØ§Ø¯ (ÙØ¯ÙØ± ÙØ¨Ø§Ø´Ø± Ø«Ù Ø¹ÙÙÙØ§Øª 1 Ø£Ø¨Ù Ø¹ÙØ§Ø±).
  v_row := public._submit_request_for(
    p_employee_id,
    'leave',
    null,
    v_manager,
    coalesce(nullif(trim(p_title),''), 'Ø¥Ø¬Ø§Ø²Ø© ' || p_leave_type),
    trim(p_reason),
    v_payload);

  -- Ø¥ÙØ´Ø§Ø¡ ØµÙ ØªÙØµÙÙ Ø§ÙØ¥Ø¬Ø§Ø²Ø© (ÙÙÙØ¹ÙÙ Ø­Ø¬Ø² Ø§ÙØ±ØµÙØ¯ Ø¹Ø¨Ø± ØªØ±ÙØºØ± 0026).
  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date,
    days_count, duration_unit, handover_notes, substitute_employee_id, created_by)
  values(
    v_row.id, p_employee_id, v_leave_type_id, p_start_date, p_end_date,
    v_days, 'day',
    nullif(p_handover_notes,''),
    p_substitute_employee_id, auth.uid());

  -- Ø§ÙØ¹Ø§Ø±Ø¶Ø©: ØªÙÙÙÙÙØ° ÙØ¨Ø§Ø´Ø±Ø© Ø¯ÙÙ ÙÙØ§ÙÙØ© (ÙÙØ³ submit_my_request 0401).
  if p_leave_type = 'casual' then
    update public.requests
      set status = 'approved',
          workflow_status = 'completed',
          decided_at = now(),
          decided_by = v_me,
          updated_at = now()
      where id = v_row.id
      returning * into v_row;

    update public.request_steps
      set status = 'skipped', acted_at = now(), acted_by = v_me,
          comment = 'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© Ø¯ÙÙ ÙÙØ§ÙÙØ©', updated_at = now()
      where request_id = v_row.id and status in ('active','pending');

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
      where request_id = v_row.id and status = 'running';

    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
    values(
      v_row.id, v_me, 'system', 'pending', 'approved',
      'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© (Ø£ÙØ´Ø£ÙØ§ HR Ø¨Ø¯Ù Ø§ÙÙÙØ¸Ù)',
      jsonb_build_object('immediate', true, 'leaveType', 'casual', 'adminCreated', true),
      auth.uid());

    perform public.log_audit_event(
      'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
      'ØªÙÙÙØ° ÙÙØ±Ù ÙØ¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø© (Ø¥ÙØ´Ø§Ø¡ Ø¥Ø¯Ø§Ø±Ù)',
      format('ÙÙ %s Ø¥ÙÙ %s', p_start_date, p_end_date),
      jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
  end if;

  perform public.log_audit_event(
    'leave.request.admin_created', 'hr', 'info', 'requests', v_row.id,
    'Ø¥ÙØ´Ø§Ø¡ Ø·ÙØ¨ Ø¥Ø¬Ø§Ø²Ø© Ø¨Ø¯Ù Ø§ÙÙÙØ¸Ù',
    coalesce(v_row.title, ''),
    jsonb_build_object(
      'employeeId', p_employee_id,
      'leaveType', p_leave_type,
      'days', v_days,
      'startDate', p_start_date,
      'endDate', p_end_date));

  return v_row;
end $function$;

-- approve_device(uuid,boolean,text)
CREATE OR REPLACE FUNCTION public.approve_device(p_device_id uuid, p_approved boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
  v_old_user_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('pending', 'blocked') then
    raise exception 'device is not in a reviewable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  if p_approved then
    -- Ø­ÙØ¸ user_id Ø§ÙÙØ¯ÙÙ ÙÙØ¬ÙØ§Ø² Ø§ÙÙØ´Ø· Ø§ÙØ³Ø§Ø¨Ù (ÙØªÙØ¸ÙÙ Ø§ÙØ¬ÙØ³Ø§Øª Ø¹ÙØ¯ ØªØºÙÙØ± Ø§ÙÙØ³ØªØ®Ø¯Ù)
    select user_id into v_old_user_id
    from public.employee_devices
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active'
    limit 1;

    -- ØªØ¹Ø·ÙÙ Ø£Ù Ø¬ÙØ§Ø² active Ø¢Ø®Ø± ÙÙÙØ³ Ø§ÙÙÙØ¸Ù
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        revocation_source = 'replacement',
        metadata = metadata || jsonb_build_object('replacedByApproval', p_device_id)
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active';

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null,
        revocation_source = null
    where id = p_device_id;

    -- ØªÙØ¸ÙÙ Ø§ÙØ¬ÙØ³Ø§Øª Ø¥Ù ØªØºÙÙØ± Ø§ÙÙØ³ØªØ®Ø¯Ù
    if v_old_user_id is not null and v_old_user_id <> v_device.user_id then
      perform public._cleanup_user_sessions_and_push(v_old_user_id, 'device_replaced');
    end if;
  else
    update public.employee_devices
    set status = 'blocked',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = coalesce(p_reason, 'Ø±ÙØ¶ Ø¥Ø¯Ø§Ø±Ù')
    where id = p_device_id;
  end if;

  perform public.log_security_event(
    case when p_approved then 'device.approved' else 'device.rejected' end,
    'medium', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'approved', p_approved,
      'reason', p_reason
    )
  );

  return jsonb_build_object('ok', true, 'status', case when p_approved then 'active' else 'blocked' end);
end;
$function$;

-- admin_revoke_device(uuid,text)
CREATE OR REPLACE FUNCTION public.admin_revoke_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('active', 'pending') then
    raise exception 'device is not in a revocable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- Ø¥ÙØºØ§Ø¡ Ø§ÙØ¬ÙØ§Ø²
  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'admin'
  where id = p_device_id;

  -- Ø¥ÙØºØ§Ø¡ Ø¨ÙØ§ÙØ§Øª Ø§Ø¹ØªÙØ§Ø¯ Ø§ÙØ¨ØµÙØ© Ø§ÙÙØ±ØªØ¨Ø·Ø©
  update public.passkey_credentials
  set status = 'revoked', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'active';

  -- ØªÙØ¸ÙÙ Ø§ÙØ¬ÙØ³Ø§Øª ÙØ§Ø´ØªØ±Ø§ÙØ§Øª Ø§ÙØ¯ÙØ¹
  perform public._cleanup_user_sessions_and_push(v_device.user_id, 'admin_revoke');

  perform public.log_security_event(
    'device.admin_revoked',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'revoked',
    'sessionsCleared', true
  );
end;
$function$;

-- get_executive_attendance_today(text,uuid,text)
CREATE OR REPLACE FUNCTION public.get_executive_attendance_today(p_status text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_status_match text := nullif(trim(coalesce(p_status, '')), '');
begin
  select public.current_has_active_role(array['executive-director', 'executive']) into v_is_executive;

  select public.current_is_full_access()
    or public.has_any_permission(array[
      'attendance.record.read',
      'attendance.history.manage',
      'attendance.roster.manage'
    ])
    or public.has_any_permission(array[
      'people.employee.read'
    ])
  into v_has_attendance_access;

  if not (v_is_executive or v_has_attendance_access) then
    raise exception 'صلاحية تنفيذي أو حضور مطلوبة' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(item order by item->>'name')
    from (
      select jsonb_build_object(
        'id',               e.id,
        'name',             e.full_name_ar,
        'employeeCode',     e.employee_code,
        'jobTitle',         jt.name,
        'department',       d.name,
        'departmentId',     d.id,
        'photoUrl',         e.photo_url,
        'attendanceStatus', coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end),
        'firstCheckIn',     ad.first_check_in,
        'lastCheckOut',     ad.last_check_out,
        'lateMinutes',      coalesce(ad.late_minutes, 0),
        'isOnMission',      (mission.id is not null),
        'lastLatitude',     last_loc.latitude,
        'lastLongitude',    last_loc.longitude,
        'lastRecordedAt',   last_loc.recorded_at
      ) as item,
      -- Ø¹ÙÙØ¯ Ø®ÙÙ ÙÙØªØ±ØªÙØ¨ (ÙØ§ ÙØ¸ÙØ± ÙÙ JSON Ø§ÙÙÙØ§Ø¦Ù)
      case
        when mission.id is not null                     then 1
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'present' then 2
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'late'    then 3
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'partial' then 4
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'absent'  then 8
        else 9
      end as sort_order
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d   on d.id  = e.department_id
    left join public.attendance_daily ad
           on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select wa.id
      from public.work_assignment_participants wap
      join public.work_assignments wa on wa.id = wap.assignment_id
      where wap.employee_id = e.id
        and wa.status in ('APPROVED', 'IN_PROGRESS')
        and wa.counts_as_work_day = true
        and wa.start_at::date <= v_today
        and wa.end_at::date   >= v_today
      limit 1
    ) mission on true
    left join lateral (
      select lr.employee_id
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      where lr.employee_id = e.id
        and v_today between lr.start_date and lr.end_date
      limit 1
    ) alv on true
    left join lateral (
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù
      -- ÙÙØªØ± Ø§ÙÙØ³Ù
      and (p_department_id is null or e.department_id = p_department_id)
      -- ÙÙØªØ± Ø§ÙØ¨Ø­Ø«
      and (v_search is null
        or e.full_name_ar ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%')
      -- ÙÙØªØ± Ø§ÙØ­Ø§ÙØ© (ÙØ·Ø¨ÙÙ Ø¨Ø¹Ø¯ Ø§ÙÙ LATERAL JOINs)
      and (v_status_match is null or
        coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end) = v_status_match)
      and (
        v_is_executive
        or public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
    order by sort_order, e.full_name_ar
    ) items
  ), '[]'::jsonb);
end;
$function$;

-- auto_notify_late_attendance()
CREATE OR REPLACE FUNCTION public.auto_notify_late_attendance()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_today      date      := v_local::date;
  v_isodow     integer   := extract(isodow from v_local)::integer;  -- 1=Ø¥Ø«ÙÙÙ..7=Ø£Ø­Ø¯
  v_sent       integer   := 0;
  v_rec        record;
  v_notif_id   uuid;
begin
  -- Ø§ÙØ§Ø³ØªØ¯Ø¹Ø§Ø¡ Ø§ÙÙØ¯ÙÙ ÙØªØ·ÙØ¨ ØµÙØ§Ø­ÙØ©Ø Ø§ÙÙØ±ÙÙ (auth.uid() is null) ÙØ³ÙÙØ­.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('attendance.record.manage')) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  -- Ø¹Ø·ÙØ© ÙÙØ§ÙØ© Ø§ÙØ£Ø³Ø¨ÙØ¹: Ø§ÙØ¬ÙØ¹Ø©(5) ÙØ§ÙØ³Ø¨Øª(6). ÙØ§ Ø´ÙØ¡ ÙÙÙØ¹ÙÙ.
  if v_isodow in (5, 6) then
    return 0;
  end if;

  for v_rec in
    select
      ad.employee_id,
      ad.late_minutes,
      e.full_name_ar      as employee_name,
      mgr.manager_user_id,
      mgr.manager_employee_id
    from public.attendance_daily ad
    join public.employees e   on e.id = ad.employee_id
    -- Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø± Ø§ÙÙØ­ÙØ¯ ÙÙÙ ÙÙØ¸Ù: ÙÙØ¶ÙÙ 'primary' Ø«Ù Ø£Ù Ø¹ÙØ§ÙØ© ÙØ¹ÙØ§ÙØ©.
    left join lateral (
      select m.user_id as manager_user_id, m.id as manager_employee_id
      from public.manager_relations mr
      join public.employees m on m.id = mr.manager_employee_id
      where mr.employee_id = ad.employee_id
        and mr.effective_from <= current_date
        and (mr.effective_to is null or mr.effective_to >= current_date)
        and m.is_active = true
        and m.user_id is not null
      order by case mr.relation_type
                 when 'primary'    then 1
                 when 'functional' then 2
                 when 'dotted'     then 3
                 else 4
               end
      limit 1
    ) mgr on true
    where ad.work_date = v_today
      and ad.status    = 'late'
      and coalesce(ad.late_minutes, 0) > 0
      and e.is_active  = true
      and e.is_deleted = false
      and mgr.manager_user_id is not null
      and not exists (
        -- ÙÙØ¹ Ø§ÙØªÙØ±Ø§Ø±: Ø¥Ø´Ø¹Ø§Ø± Ø³Ø§Ø¨Ù ÙÙÙØ³ (Ø§ÙÙØ¯ÙØ±/Ø§ÙÙÙØ¸Ù/Ø§ÙÙÙÙ)
        select 1
        from public.notifications n
        where n.recipient_user_id = mgr.manager_user_id
          and n.entity_type = 'late_attendance_alert'
          and (n.metadata->>'employeeId') = ad.employee_id::text
          and (n.metadata->>'workDate')   = v_today::text
      )
    order by e.full_name_ar
  loop
    -- Ø§ÙÙ trigger trg_notifications_queue_jobs ÙÙØ¶ÙÙ notification_jobs ØªÙÙØ§Ø¦ÙØ§Ù.
    insert into public.notifications (
      recipient_user_id,
      recipient_employee_id,
      title,
      body,
      category,
      priority,
      action_url,
      entity_type,
      entity_id,
      metadata
    ) values (
      v_rec.manager_user_id,
      v_rec.manager_employee_id,
      'ØªÙØ¨ÙÙ ØªØ£Ø®Ø± ÙÙØ¸Ù',
      coalesce(v_rec.employee_name, 'Ø§ÙÙÙØ¸Ù') || ' ØªØ£Ø®Ø± Ø¹Ù ÙÙØ§Ø¬ÙØ© Ø§ÙÙØ±Ø¯ÙØ© Ø¨ÙÙØ¯Ø§Ø± ' ||
        v_rec.late_minutes::text || ' Ø¯ÙÙÙØ©',
      'system',
      'urgent',
      '/attendance',
      'late_attendance_alert',
      v_rec.employee_id,
      jsonb_build_object(
        'workDate',     v_today::text,
        'lateMinutes',  v_rec.late_minutes,
        'employeeId',   v_rec.employee_id::text,
        'managerEmployeeId', v_rec.manager_employee_id::text,
        'channel', 'late_attendance',
        'deepLink', 'ahlashabab://action/attendance?date=' || to_char(v_today, 'YYYY-MM-DD')
      )
    ) returning id into v_notif_id;

    v_sent := v_sent + 1;
  end loop;

  return v_sent;
exception
  when others then
    -- ÙØ§ ÙØ¹Ø·ÙÙ Ø§ÙÙØ±ÙÙØ ÙØ³Ø¬ÙÙ Ø§ÙØ­Ø§Ø¯Ø« ÙÙÙØ±Ø¬Ø¹ 0.
    perform public.log_audit_event(
      'attendance.late_alert_failed', 'operations', 'warning',
      'attendance_daily', null, 'ÙØ´Ù ØªÙØ¨ÙÙ Ø§ÙØªØ£Ø®Ø± Ø§ÙØªÙÙØ§Ø¦Ù', null,
      jsonb_build_object('error', sqlerrm, 'workDate', v_today)
    );
    return 0;
end;
$function$;

-- generate_weekly_executive_summary()
CREATE OR REPLACE FUNCTION public.generate_weekly_executive_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_local      timestamp := (now() at time zone 'Africa/Cairo');
  v_end        date      := (v_local::date) - 1;   -- Ø£ÙØ³
  v_start      date      := v_end - 6;            -- Ø¢Ø®Ø± 7 Ø£ÙØ§Ù Ø´Ø§ÙÙØ©
  v_period_id  text      := to_char(v_start, 'YYYY-MM-DD') || '_' || to_char(v_end, 'YYYY-MM-DD');
  v_total_emp  integer;
  v_summary    jsonb;
  v_top_late   jsonb;
  v_absent_gt3 jsonb;
  v_body       text;
  v_notif_id   uuid;
  v_recipients bigint;
  v_sent       integer := 0;
  v_result     jsonb;
begin
  -- Ø§ÙØ§Ø³ØªØ¯Ø¹Ø§Ø¡ Ø§ÙÙØ¯ÙÙ ÙØªØ·ÙØ¨ ØµÙØ§Ø­ÙØ©Ø Ø§ÙÙØ±ÙÙ (auth.uid() is null) ÙØ³ÙÙØ­.
  if auth.uid() is not null
     and not (public.current_is_full_access()
              or public.has_permission('reports.attendance.read')) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  -- Ø¥Ø¬ÙØ§ÙÙ Ø§ÙÙÙØ¸ÙÙÙ Ø§ÙÙØ´Ø·ÙÙ (ÙØ§Ø¹Ø¯Ø© Ø§ÙÙÙØ§Ù ÙÙÙØ³Ø¨).
  select count(*) into v_total_emp
  from public.employees e
  where e.is_active = true
    and e.is_deleted = false
    and e.status = 'active';

  -- Ø§ÙÙÙØ®Øµ: Ø¥Ø¬ÙØ§ÙÙ Ø³Ø¬ÙØ§Øª/Ø£ÙØ§Ù + Ø¹Ø¯Ø¯ ÙÙÙ Ø­Ø§ÙØ©.
  select jsonb_build_object(
    'startDate',     v_start,
    'endDate',       v_end,
    'periodId',      v_period_id,
    'activeEmployees', v_total_emp,
    'totalDayRecords', count(*),
    'present',       count(*) filter (where ad.status = 'present'),
    'late',           count(*) filter (where ad.status = 'late'),
    'absent',         count(*) filter (where ad.status = 'absent'),
    'onLeave',        count(*) filter (where ad.status = 'on_leave'),
    'holiday',        count(*) filter (where ad.status = 'holiday'),
    'weekend',        count(*) filter (where ad.status = 'weekend'),
    'partial',        count(*) filter (where ad.status = 'partial'),
    'totalLateMinutes',  coalesce(sum(ad.late_minutes), 0),
    'totalEarlyLeaveMinutes', coalesce(sum(ad.early_leave_minutes), 0),
    'totalOvertimeMinutes',  coalesce(sum(ad.overtime_minutes), 0)
  ) into v_summary
  from public.attendance_daily ad
  join public.employees e on e.id = ad.employee_id
  where ad.work_date between v_start and v_end
    and e.is_active = true
    and e.is_deleted = false;

  -- ÙØ³Ø¨ ÙØ¹Ø¯ÙÙØ© Ø¹ÙÙ Ø¹Ø¯Ø¯ Ø£ÙØ§Ù Ø§ÙØ¹ÙÙ Ø§ÙÙØ¹ÙÙØ© (present+late+absent+partial)
  v_summary := v_summary || jsonb_build_object(
    'workdayRecords',
      coalesce((v_summary->>'present')::int,0)
      + coalesce((v_summary->>'late')::int,0)
      + coalesce((v_summary->>'absent')::int,0)
      + coalesce((v_summary->>'partial')::int,0),
    'presentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'present')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'lateRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'late')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'absentRate',
      case when coalesce((v_summary->>'present')::int,0)
             + coalesce((v_summary->>'late')::int,0)
             + coalesce((v_summary->>'absent')::int,0)
             + coalesce((v_summary->>'partial')::int,0) = 0 then 0
           else round(100.0 * coalesce((v_summary->>'absent')::int,0) /
             (coalesce((v_summary->>'present')::int,0)
              + coalesce((v_summary->>'late')::int,0)
              + coalesce((v_summary->>'absent')::int,0)
              + coalesce((v_summary->>'partial')::int,0)), 2) end,
    'onLeaveRate',
      case when coalesce(v_total_emp,0) * 7 = 0 then 0
           else round(100.0 * coalesce((v_summary->>'onLeave')::int,0)
             / (coalesce(v_total_emp,0) * 7), 2) end
  );

  -- Ø£Ø¹ÙÙ 5 ÙÙØ¸ÙÙÙ ØªÙØ±Ø§Ø±Ø§Ù ÙÙ Ø§ÙØªØ£Ø®ÙØ±.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'lateDays',     t.late_days,
    'totalLateMinutes', t.total_late_minutes
  ) order by t.late_days desc, t.total_late_minutes desc), '[]'::jsonb) into v_top_late
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'late') as late_days,
      coalesce(sum(ad.late_minutes) filter (where ad.status = 'late'), 0) as total_late_minutes
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'late') > 0
    order by late_days desc, total_late_minutes desc
    limit 5
  ) t;

  -- ÙÙØ¸ÙÙÙ ØªØ¬Ø§ÙØ²ÙØ§ 3 Ø£ÙØ§Ù ØºÙØ§Ø¨ ÙÙ Ø§ÙØ£Ø³Ø¨ÙØ¹.
  select coalesce(jsonb_agg(jsonb_build_object(
    'employeeId',   t.employee_id,
    'employeeName', t.full_name_ar,
    'employeeCode', t.employee_code,
    'department',   t.department,
    'absentDays',   t.absent_days
  ) order by t.absent_days desc, t.full_name_ar), '[]'::jsonb) into v_absent_gt3
  from (
    select
      e.id as employee_id,
      e.full_name_ar,
      e.employee_code,
      d.name as department,
      count(*) filter (where ad.status = 'absent') as absent_days
    from public.employees e
    left join public.attendance_daily ad on ad.employee_id = e.id
      and ad.work_date between v_start and v_end
    left join public.departments d on d.id = e.department_id
    where e.is_active = true and e.is_deleted = false
    group by e.id, e.full_name_ar, e.employee_code, d.name
    having count(*) filter (where ad.status = 'absent') > 3
    order by absent_days desc, full_name_ar
  ) t;

  -- Ø§ÙÙØªÙØ¬Ø© Ø§ÙÙÙØ§Ø¦ÙØ©.
  v_result := jsonb_build_object(
    'generatedAt', now(),
    'summary',     v_summary,
    'topLateEmployees',     v_top_late,
    'absentGt3Employees',   v_absent_gt3
  );

  -- ØµÙØ§ØºØ© Ø¬Ø³Ù Ø§ÙØ¥Ø´Ø¹Ø§Ø± (Ø¹Ø±Ø¨ÙØ ÙØ®ØªØµØ±).
  v_body := 'Ø§ÙÙÙØ®Øµ Ø§ÙØ£Ø³Ø¨ÙØ¹Ù ÙÙØ­Ø¶ÙØ± (' || to_char(v_start, 'DD/MM/YYYY') || ' - '
             || to_char(v_end, 'DD/MM/YYYY') || '): '
             || 'Ø­Ø¶ÙØ± ' || coalesce((v_summary->>'present')::text,'0')
             || 'Ø ØªØ£Ø®Ø± ' || coalesce((v_summary->>'late')::text,'0')
             || 'Ø ØºÙØ§Ø¨ ' || coalesce((v_summary->>'absent')::text,'0')
             || 'Ø Ø¥Ø¬Ø§Ø²Ø© ' || coalesce((v_summary->>'onLeave')::text,'0')
             || '. ÙØ³Ø¨Ø© Ø§ÙØªØ£Ø®Ø± ' || coalesce((v_summary->>'lateRate')::text,'0') || '%'
             || 'Ø ÙØ³Ø¨Ø© Ø§ÙØºÙØ§Ø¨ ' || coalesce((v_summary->>'absentRate')::text,'0') || '%.'
             || ' Ø£Ø¹ÙÙ Ø§ÙÙØªØ£Ø®Ø±ÙÙ: ' || coalesce(
                (select string_agg(x->>'employeeName', 'Ø ')
                 from jsonb_array_elements(v_top_late) as x),
                'ÙØ§ ÙÙØ¬Ø¯')
             || '.';

  -- Ø¥Ø¯Ø±Ø§Ø¬ Ø¥Ø´Ø¹Ø§Ø± ÙÙÙ ÙØ³ØªØ®Ø¯Ù ÙÙÙÙ reports.attendance.read Ø£Ù Ø¯ÙØ± full-access.
  -- ÙÙØ­Ø¯ÙØ¯ Ø§ÙÙØ³ØªØ®Ø¯ÙÙÙ Ø¹Ø¨Ø± user_roles Ø§ÙÙØ±ØªØ¨Ø·Ø© Ø¨Ù role_permissions/permissions
  -- Ø£Ù Ø¨Ù roles.is_full_access=true. ÙÙØ­ÙÙ employee_id Ø¹Ø¨Ø± profiles.
  with recipients as (
    -- full-access
    select distinct ur.user_id
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where r.is_full_access = true
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
    union
    -- ÙØ§ÙÙÙ reports.attendance.read
    select distinct ur.user_id
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p        on p.id = rp.permission_id
    where p.code = 'reports.attendance.read'
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
  ),
  enriched as (
    select
      r.user_id,
      p.employee_id
    from recipients r
    left join public.profiles p on p.id = r.user_id
  )
  insert into public.notifications (
    recipient_user_id,
    recipient_employee_id,
    title,
    body,
    category,
    priority,
    action_url,
    entity_type,
    entity_id,
    metadata
  )
  select
    e.user_id,
    e.employee_id,
    'Ø§ÙÙÙØ®Øµ Ø§ÙØ£Ø³Ø¨ÙØ¹Ù ÙÙØ­Ø¶ÙØ±',
    v_body,
    'system',
    'normal',
    '/reports/attendance',
    'weekly_executive_summary',
    null,
    jsonb_build_object(
      'periodId', v_period_id,
      'startDate', v_start,
      'endDate',   v_end,
      'summary',   v_summary,
      'topLateEmployees',   v_top_late,
      'absentGt3Employees', v_absent_gt3,
      'kind', 'weekly_executive_summary',
      'deepLink', 'ahlashabab://action/reports/attendance?start='
        || to_char(v_start,'YYYY-MM-DD') || '&end=' || to_char(v_end,'YYYY-MM-DD')
    )
  from enriched e
  where not exists (
    -- ÙÙØ¹ Ø§ÙØªÙØ±Ø§Ø±: Ø¥Ø´Ø¹Ø§Ø± Ø³Ø§Ø¨Ù ÙÙÙØ³ (Ø§ÙÙØ³ØªØ®Ø¯Ù/Ø§ÙÙØªØ±Ø©)
    select 1
    from public.notifications n
    where n.recipient_user_id = e.user_id
      and n.entity_type = 'weekly_executive_summary'
      and (n.metadata->>'periodId') = v_period_id
  );

  get diagnostics v_recipients = row_count;
  v_sent := v_recipients::integer;

  perform public.log_audit_event(
    'reports.weekly_executive_summary_generated', 'operations', 'info',
    'attendance_daily', null, 'ØªÙÙÙØ¯ Ø§ÙÙÙØ®Øµ Ø§ÙØªÙÙÙØ°Ù Ø§ÙØ£Ø³Ø¨ÙØ¹Ù ÙÙØ­Ø¶ÙØ±', null,
    jsonb_build_object(
      'periodId', v_period_id,
      'recipientsNotified', v_sent,
      'summary', v_summary
    )
  );

  return v_result || jsonb_build_object(
    'recipientsNotified', v_sent,
    'notificationBody', v_body
  );
exception
  when others then
    perform public.log_audit_event(
      'reports.weekly_executive_summary_failed', 'operations', 'warning',
      'attendance_daily', null, 'ÙØ´Ù ØªÙÙÙØ¯ Ø§ÙÙÙØ®Øµ Ø§ÙØªÙÙÙØ°Ù Ø§ÙØ£Ø³Ø¨ÙØ¹Ù', null,
      jsonb_build_object('error', sqlerrm, 'periodId', v_period_id)
    );
    return jsonb_build_object('error', sqlerrm, 'periodId', v_period_id);
end;
$function$;

-- decide_access_review_item(uuid,text,text)
CREATE OR REPLACE FUNCTION public.decide_access_review_item(p_item_id uuid, p_decision text, p_reason text)
 RETURNS access_review_items
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_item public.access_review_items;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then raise exception 'access review denied' using errcode='42501'; end if;
  if p_decision not in ('keep','revoke') then raise exception 'قرار غير صالح' using errcode='22023'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  select * into v_item from public.access_review_items where id=p_item_id for update;
  if not found then raise exception 'عنصر المراجعة غير موجود' using errcode='P0002'; end if;
  if v_item.decision <> 'pending' then raise exception 'عنصر المراجعة مُقرر عليه بالفعل' using errcode='P0001'; end if;
  update public.access_review_items set decision=p_decision,decision_reason=p_reason,decided_at=now(),reviewer_user_id=auth.uid()
  where id=p_item_id returning * into v_item;
  if p_decision='revoke' then update public.user_roles set effective_to=now() where id=v_item.user_role_id; end if;
  perform public.log_audit_event('access.review.decided','access',case when p_decision='revoke' then 'warning' else 'info' end,
    'access_review_items',v_item.id,'ÙØ±Ø§Ø± ÙØ±Ø§Ø¬Ø¹Ø© ØµÙØ§Ø­ÙØ©',p_reason,jsonb_build_object('decision',p_decision,'userRoleId',v_item.user_role_id));
  perform public.notify_user(
    v_item.user_id,
    case p_decision when 'revoke' then 'Ø£ÙÙØºÙØª ØµÙØ§Ø­ÙØ© ÙÙ Ø­Ø³Ø§Ø¨Ù' else 'ØªØ£ÙÙØ¯ ØµÙØ§Ø­ÙØ© ÙÙ Ø­Ø³Ø§Ø¨Ù' end,
    format('ÙØ±Ø§Ø± ÙØ±Ø§Ø¬Ø¹Ø© Ø§ÙØµÙØ§Ø­ÙØ§Øª: %s.%s', case p_decision when 'revoke' then 'Ø£ÙÙØºÙ Ø¯ÙØ±' else 'Ø£ÙØ¨ÙÙ Ø¹ÙÙ Ø¯ÙØ±' end, E'\n'||p_reason),
    'security', case p_decision when 'revoke' then 'high' else 'normal' end,
    'access_review_items', v_item.id,
    jsonb_build_object('decision', p_decision));
  return v_item;
end;
$function$;

-- get_release_governance_overview()
CREATE OR REPLACE FUNCTION public.get_release_governance_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'system.release.read','system.release.manage','access.review.read','access.review.manage',
      'access.break_glass.request','access.break_glass.approve','privacy.request.manage',
      'system.integration.outbox.read','system.integration.outbox.manage','system.integration.manage'
    ])
  ) then
    raise exception 'وصول الحوكمة مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'policies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'platform',p.platform,'environment',p.environment,
        'latestVersion',p.latest_version,'latestBuild',p.latest_build,
        'minSupportedVersion',p.min_supported_version,
        'minSupportedBuild',p.min_supported_build,'forceUpdate',p.force_update,
        'maintenance',p.maintenance_enabled,
        'maintenanceMessageAr',p.maintenance_message_ar,
        'updateMessageAr',p.update_message_ar,'storeUrl',p.store_url,
        'rolloutPercent',p.rollout_percent,
        'updatedAt',coalesce(p.updated_at,p.created_at)
      ) order by p.platform,p.environment)
      from public.app_release_policies p
    ), '[]'::jsonb),
    'devices', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',d.id,'installationId',d.installation_id,'userId',d.user_id,
        'employeeId',d.employee_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'platform',d.platform,
        'deviceName',d.device_name,'deviceModel',d.device_model,
        'osVersion',d.os_version,'appVersion',d.app_version,
        'appBuild',d.app_build,'environment',d.environment,
        'trusted',d.trusted,'status',d.status,'lastSeenAt',d.last_seen_at
      ) order by d.last_seen_at desc)
      from public.managed_devices d
      left join public.employees e on e.id = d.employee_id
    ), '[]'::jsonb),
    'accessReviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',c.id,'name',c.name,'status',c.status,'startsAt',c.starts_at,
        'dueAt',c.due_at,
        'totalItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id),
        'pendingItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='pending'),
        'revokedItems',(select count(*) from public.access_review_items i where i.campaign_id=c.id and i.decision='revoke')
      ) order by c.created_at desc)
      from public.access_review_campaigns c
    ), '[]'::jsonb),
    'reviewItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',i.id,'campaignId',i.campaign_id,'userRoleId',i.user_role_id,
        'userId',i.user_id,'roleId',i.role_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'roleName',r.name_ar,
        'decision',i.decision,'decisionReason',i.decision_reason,
        'decidedAt',i.decided_at,'snapshot',i.snapshot
      ) order by i.created_at desc)
      from public.access_review_items i
      left join public.profiles pr on pr.id = i.user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = i.role_id
      where i.decision = 'pending'
    ), '[]'::jsonb),
    'breakGlass', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',b.id,'targetUserId',b.target_user_id,
        'targetName',coalesce(e.full_name_ar,e.full_name_en),
        'targetCode',e.employee_code,'roleId',b.requested_role_id,
        'roleName',r.name_ar,'durationMinutes',b.duration_minutes,
        'reason',b.reason,'status',b.status,'requestedBy',b.requested_by,
        'requestedAt',b.requested_at,'activeUntil',b.active_until
      ) order by b.requested_at desc)
      from public.break_glass_requests b
      left join public.profiles pr on pr.id = b.target_user_id
      left join public.employees e on e.id = pr.employee_id
      join public.roles r on r.id = b.requested_role_id
    ), '[]'::jsonb),
    'privacyRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'requestNumber',p.request_number,
        'requesterUserId',p.requester_user_id,
        'employeeName',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'requestType',p.request_type,
        'details',p.details,'status',p.status,'dueAt',p.due_at,
        'decisionReason',p.decision_reason,'createdAt',p.created_at
      ) order by p.created_at desc)
      from public.privacy_requests p
      left join public.employees e on e.id = p.requester_employee_id
    ), '[]'::jsonb),
    'outbox', jsonb_build_object(
      'pending',(select count(*) from public.integration_outbox where status in ('pending','retrying')),
      'failed',(select count(*) from public.integration_outbox where status in ('failed','dead_letter')),
      'delivered',(select count(*) from public.integration_outbox where status='delivered'),
      'oldestPendingAt',(select min(created_at) from public.integration_outbox where status in ('pending','retrying'))
    ),
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'slug',r.slug,'name',r.name_ar,'fullAccess',r.is_full_access
      ) order by r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId',p.id,'employeeId',p.employee_id,
        'name',coalesce(e.full_name_ar,e.full_name_en),
        'employeeCode',e.employee_code,'status',p.status
      ) order by coalesce(e.full_name_ar,e.full_name_en))
      from public.profiles p
      left join public.employees e on e.id = p.employee_id
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- cancel_request(uuid,text)
CREATE OR REPLACE FUNCTION public.cancel_request(p_request_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me   uuid := public.current_employee_id();
  v_req  public.requests;
  v_from text;
  v_assignee uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;

  if v_req.status <> 'pending' then
    raise exception 'only pending requests can be cancelled (current: %)', v_req.status using errcode = '22023';
  end if;

  -- Ø§ÙØªØ®ÙÙÙ: ØµØ§Ø­Ø¨ Ø§ÙØ·ÙØ¨Ø Ø£Ù full-accessØ Ø£Ù ØµÙØ§Ø­ÙØ© approve
  if not (
    v_req.employee_id = v_me
    or public.current_is_full_access()
    or public.has_permission('requests.approve')
  ) then
    raise exception 'غير مصرح لك بإلغاء هذا الطلب' using errcode = '42501';
  end if;

  v_from := v_req.status;

  update public.requests
     set status          = 'cancelled',
         workflow_status = 'terminated',
         cancelled_at    = now(),
         cancelled_by    = v_me,
         cancel_reason   = p_reason,
         updated_at      = now()
   where id = p_request_id
  returning * into v_req;

  update public.request_steps
     set status   = 'skipped',
         acted_at = now(),
         acted_by = v_me,
         updated_at = now()
   where request_id = p_request_id
     and status in ('active','pending','escalated');

  update public.workflow_instances
     set status       = 'cancelled',
         completed_at = now(),
         updated_at   = now()
   where request_id = p_request_id and status = 'running';

  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_me, 'cancel', v_from, 'cancelled', p_reason, auth.uid()
  );

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙØ¹ØªÙÙØ¯ÙÙ Ø¹ÙÙ Ø§ÙØ®Ø·ÙØ§Øª (0316)
  for v_assignee in
    select distinct s.assignee_employee_id
    from public.request_steps s
    where s.request_id = p_request_id
      and s.assignee_employee_id is not null
      and s.assignee_employee_id <> v_me
  loop
    perform public.notify_employee(
      v_assignee,
      'Ø£ÙÙØºÙØª Ø·ÙØ¨',
      format('%s â %s', public.request_type_label(v_req.request_type), coalesce(v_req.title, '')),
      'request', 'normal', 'request', p_request_id,
      jsonb_build_object('requestType', v_req.request_type));
  end loop;

  return v_req;
end;
$function$;

-- approve_break_glass(uuid,text)
CREATE OR REPLACE FUNCTION public.approve_break_glass(p_request_id uuid, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.break_glass_requests; v_user_role public.user_roles; v_role_slug text;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'اعتماد الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  select * into v_req from public.break_glass_requests where id=p_request_id for update;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;
  if v_req.status <> 'pending' then raise exception 'الطلب ليس قيد الانتظار' using errcode='P0001'; end if;
  if v_req.requested_by=auth.uid() then raise exception 'يلزم اعتماد شخصين (أربع عيون)' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'سبب الاعتماد مطلوب' using errcode='22023'; end if;
  if exists (
    select 1 from public.user_roles ur
    where ur.user_id=v_req.target_user_id and ur.role_id=v_req.requested_role_id
      and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'المستخدم يملك الدور المطلوب نشطاً بالفعل' using errcode='P0001';
  end if;
  insert into public.user_roles(user_id,role_id,scope_override,effective_from,effective_to,granted_by)
  values(v_req.target_user_id,v_req.requested_role_id,jsonb_build_object('breakGlassRequestId',v_req.id),now(),now()+make_interval(mins=>v_req.duration_minutes),auth.uid())
  on conflict (user_id,role_id) do update set
    scope_override=excluded.scope_override,effective_from=excluded.effective_from,effective_to=excluded.effective_to,granted_by=excluded.granted_by
  returning * into v_user_role;
  update public.break_glass_requests set status='approved',approved_by=auth.uid(),approved_at=now(),active_from=now(),
    active_until=v_user_role.effective_to,user_role_id=v_user_role.id where id=v_req.id returning * into v_req;
  select r.slug into v_role_slug from public.roles r where r.id=v_req.requested_role_id;
  perform public.log_security_event('break_glass.approved','critical','allowed',v_req.target_user_id::text,
    jsonb_build_object('requestId',v_req.id,'userRoleId',v_user_role.id,'activeUntil',v_req.active_until,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'ØªÙ ÙØ¨ÙÙ Ø·ÙØ¨ Break Glass',
    format('ÙÙÙØ­ ÙØµÙÙ Ø§Ø³ØªØ«ÙØ§Ø¦Ù ÙØ¯ÙØ± %s Ø­ØªÙ %s.', coalesce(v_role_slug,''), v_req.active_until),
    'security', 'normal', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$function$;

-- reject_break_glass(uuid,text)
CREATE OR REPLACE FUNCTION public.reject_break_glass(p_request_id uuid, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.break_glass_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.approve')) then raise exception 'رفض الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  if length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  update public.break_glass_requests set status='rejected',rejected_by=auth.uid(),rejected_at=now(),rejection_reason=p_reason
  where id=p_request_id and status='pending' returning * into v_req;
  if not found then raise exception 'الطلب المعلق غير موجود' using errcode='P0002'; end if;
  perform public.log_security_event('break_glass.rejected','high','blocked',v_req.target_user_id::text,jsonb_build_object('requestId',v_req.id,'reason',p_reason));
  perform public.notify_user(
    v_req.requested_by,
    'ØªÙ Ø±ÙØ¶ Ø·ÙØ¨ Break Glass',
    format('Ø±ÙÙØ¶ Ø·ÙØ¨ Ø§ÙÙØµÙÙ Ø§ÙØ§Ø³ØªØ«ÙØ§Ø¦Ù.%s', E'\n'||p_reason),
    'security', 'high', 'break_glass_requests', v_req.id,
    jsonb_build_object('targetUserId', v_req.target_user_id));
  return v_req;
end;
$function$;

-- submit_privacy_request(text,text)
CREATE OR REPLACE FUNCTION public.submit_privacy_request(p_request_type text, p_details text)
 RETURNS privacy_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.privacy_requests;
begin
  if auth.uid() is null then raise exception 'يلزم تسجيل الدخول أولاً' using errcode='42501'; end if;
  if p_request_type not in ('access','correction','export','restriction','deletion','objection') then raise exception 'نوع طلب خصوصية غير صالح' using errcode='22023'; end if;
  insert into public.privacy_requests(requester_user_id,requester_employee_id,request_type,details,due_at)
  values(auth.uid(),public.current_employee_id(),p_request_type,trim(p_details),now()+interval '30 days') returning * into v_row;
  perform public.log_audit_event('privacy.request.submitted','data','notice','privacy_requests',v_row.id,'ØªÙØ¯ÙÙ Ø·ÙØ¨ Ø®ØµÙØµÙØ©',null,jsonb_build_object('requestType',p_request_type));
  perform public.notify_employees_with_permission(
    'privacy.request.manage',
    'Ø·ÙØ¨ Ø®ØµÙØµÙØ© Ø¬Ø¯ÙØ¯',
    format('Ø·ÙØ¨ %s ÙÙ ÙÙØ¸Ù.', p_request_type),
    'privacy', 'normal', 'privacy_requests', v_row.id,
    jsonb_build_object('requestType', p_request_type), v_row.requester_employee_id);
  return v_row;
end;
$function$;

-- decide_privacy_request(uuid,text,text)
CREATE OR REPLACE FUNCTION public.decide_privacy_request(p_request_id uuid, p_status text, p_reason text)
 RETURNS privacy_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.privacy_requests;
begin
  if not (public.current_is_full_access() or public.has_permission('privacy.request.manage')) then raise exception 'إدارة الخصوصية مرفوضة' using errcode='42501'; end if;
  if p_status not in ('in_review','waiting_requester','approved','rejected','completed') then raise exception 'حالة غير صالحة' using errcode='22023'; end if;
  if p_status in ('rejected','completed') and length(trim(coalesce(p_reason,''))) < 5 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  update public.privacy_requests set status=p_status,decision_reason=p_reason,assigned_to=coalesce(assigned_to,auth.uid()),
    completed_at=case when p_status='completed' then now() else completed_at end where id=p_request_id returning * into v_row;
  if not found then raise exception 'طلب الخصوصية غير موجود' using errcode='P0002'; end if;
  perform public.log_audit_event('privacy.request.updated','data','notice','privacy_requests',v_row.id,'ØªØ­Ø¯ÙØ« Ø·ÙØ¨ Ø®ØµÙØµÙØ©',p_reason,jsonb_build_object('status',p_status));
  perform public.notify_user(
    v_row.requester_user_id,
    'ØªØ­Ø¯ÙØ« Ø­Ø§ÙØ© Ø·ÙØ¨ Ø§ÙØ®ØµÙØµÙØ©',
    format('Ø£ØµØ¨Ø­ Ø·ÙØ¨Ù Ø¨Ø­Ø§ÙØ© %s.%s', p_status, case when p_reason is not null then E'\n'||p_reason else '' end),
    'privacy', case when p_status in ('approved','completed') then 'normal' else 'high' end,
    'privacy_requests', v_row.id,
    jsonb_build_object('status', p_status));
  return v_row;
end;
$function$;

-- provision_employee_record(uuid,uuid,text,text,text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,date,boolean,text,text)
CREATE OR REPLACE FUNCTION public.provision_employee_record(p_actor_user_id uuid, p_user_id uuid, p_full_name_ar text, p_full_name_en text, p_employee_code text, p_phone_e164 text, p_role_slug text, p_manager_employee_id uuid DEFAULT NULL::uuid, p_department_id uuid DEFAULT NULL::uuid, p_team_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_work_site_id uuid DEFAULT NULL::uuid, p_job_title_id uuid DEFAULT NULL::uuid, p_position_id uuid DEFAULT NULL::uuid, p_grade_id uuid DEFAULT NULL::uuid, p_employment_type_id uuid DEFAULT NULL::uuid, p_hire_date date DEFAULT NULL::date, p_invitation_pending boolean DEFAULT true, p_job_title_name text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'pg_temp'
AS $function$
declare
  v_employee_id uuid;
  v_role_id uuid;
  v_profile_status text;
  v_employee_status text;
  v_employee_code text;
  v_job_title_id uuid;
  v_title_name text;
  v_title_code text;
begin
  if p_actor_user_id is null or p_user_id is null then
    raise exception 'المنفّذ والمستخدم مطلوبان';
  end if;

  select id into v_role_id
  from public.roles
  where slug = p_role_slug;

  if v_role_id is null then
    raise exception 'unknown role slug: %', p_role_slug using errcode = '22023';
  end if;

  -- ÙÙØ¯ Ø§ÙÙÙØ¸Ù: ØµØ±ÙØ­ Ø¥Ù ÙÙØ¬Ø¯Ø ÙØ¥ÙØ§ ÙÙØ´ØªÙ ÙÙ Ø±ÙÙ Ø§ÙÙØ§ØªÙ.
  v_employee_code := coalesce(nullif(trim(p_employee_code), ''), nullif(trim(p_phone_e164), ''));
  if v_employee_code is null then
    raise exception 'كود الموظف أو الهاتف مطلوب' using errcode = '22023';
  end if;

  -- ÙØ­Øµ ØªÙØ±Ø§Ø± ÙÙØ¯ Ø§ÙÙÙØ¸Ù Ø¨ÙÙ Ø§ÙÙØ´Ø·ÙÙ.
  if exists (
    select 1 from public.employees
    where employee_code = v_employee_code and is_active = true and is_deleted = false
  ) then
    raise exception 'كود الموظف موجود مسبقاً' using errcode = '23505';
  end if;

  -- ÙØ­Øµ ØªÙØ±Ø§Ø± Ø§ÙÙØ§ØªÙ ØµØ±ÙØ­ ÙØ¹ Ø±Ø³Ø§ÙØ© ÙÙÙÙÙØ© (Ø¨Ø¯Ù Ø§ÙØ§Ø¹ØªÙØ§Ø¯ Ø¹ÙÙ constraint Ø®Ø§Ù).
  if p_phone_e164 is not null and exists (
    select 1 from public.employees
    where phone_e164 = p_phone_e164 and is_active = true and is_deleted = false
  ) then
    raise exception 'phone number already belongs to an active employee' using errcode = '23505';
  end if;

  if p_manager_employee_id is not null and not exists (
    select 1 from public.employees
    where id = p_manager_employee_id and is_active = true and is_deleted = false
  ) then
    raise exception 'المدير ليس موظفاً نشطاً' using errcode = '23503';
  end if;

  -- Ø§ÙÙØ³ÙÙ Ø§ÙÙØ¸ÙÙÙ: Ø£ÙÙÙÙØ© ÙÙÙØ¹Ø±ÙÙ Ø§ÙØµØ±ÙØ­Ø ÙØ¥ÙØ§ ÙØ·Ø§Ø¨ÙØ©/Ø¥ÙØ´Ø§Ø¡ ÙÙ Ø§ÙØ§Ø³Ù Ø§ÙØ­Ø±.
  v_job_title_id := p_job_title_id;
  v_title_name := nullif(trim(p_job_title_name), '');
  if v_job_title_id is null and v_title_name is not null then
    -- ÙØ­Ø§ÙÙØ© Ø§ÙØ¥Ø¯Ø±Ø§Ø¬ Ø£ÙÙØ§Ù ÙØ¹ ON CONFLICT ÙÙÙØ¹ Ø§ÙØªÙØ±Ø§Ø± Ø¹ÙØ¯ Ø§ÙØªØ²Ø§ÙÙ.
    v_title_code := 'JT-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    insert into public.job_titles (code, name, is_active, created_by)
    values (v_title_code, v_title_name, true, p_actor_user_id)
    on conflict ((lower(name))) where is_active = true
    do update set updated_at = now()
    returning id into v_job_title_id;
  end if;

  v_profile_status := case when p_invitation_pending then 'pending' else 'active' end;
  v_employee_status := case when p_invitation_pending then 'invited' else 'active' end;

  insert into public.employees (
    user_id, employee_code, full_name_ar, full_name_en, phone_e164,
    job_title_id, position_id, grade_id, department_id, team_id,
    branch_id, work_site_id, employment_type_id, hire_date,
    status, is_active, is_deleted, photo_url, created_by
  ) values (
    p_user_id, trim(v_employee_code), trim(p_full_name_ar), nullif(trim(p_full_name_en), ''),
    p_phone_e164, v_job_title_id, p_position_id, p_grade_id,
    p_department_id, p_team_id, p_branch_id, p_work_site_id,
    p_employment_type_id, p_hire_date, v_employee_status, true, false,
    nullif(trim(p_photo_url), ''), p_actor_user_id
  ) returning id into v_employee_id;

  insert into public.profiles (
    id, employee_id, primary_role_id, status, temporary_password,
    branch_id, department_id, team_id, created_by
  ) values (
    p_user_id, v_employee_id, v_role_id, v_profile_status, true,
    p_branch_id, p_department_id, p_team_id, p_actor_user_id
  );

  insert into public.user_roles (
    user_id, role_id, effective_from, granted_by
  ) values (
    p_user_id, v_role_id, now(), p_actor_user_id
  );

  if p_manager_employee_id is not null then
    insert into public.manager_relations (
      employee_id, manager_employee_id, relation_type,
      effective_from, created_by
    ) values (
      v_employee_id, p_manager_employee_id, 'primary',
      coalesce(p_hire_date, current_date), p_actor_user_id
    );
  end if;

  return jsonb_build_object(
    'employeeId', v_employee_id,
    'userId', p_user_id
  );
end;
$function$;

-- toggle_daily_report_like(uuid)
CREATE OR REPLACE FUNCTION public.toggle_daily_report_like(p_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_liked boolean;
  v_count integer;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  if exists (
    select 1 from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me
  ) then
    delete from public.daily_report_likes
    where report_id = p_report_id and employee_id = v_me;
    v_liked := false;
  else
    insert into public.daily_report_likes (report_id, employee_id)
    values (p_report_id, v_me);
    v_liked := true;

    -- Ø¥Ø´Ø¹Ø§Ø± ØµØ§Ø­Ø¨ Ø§ÙØªÙØ±ÙØ± (ÙØ§ ÙØ´Ø¹Ø± ÙÙØ³Ù)
    if v_author is distinct from v_me then
      perform public.notify_employee(
        v_author,
        'Ø£ÙØ¹Ø¬Ø¨ Ø´Ø®Øµ Ø¨ØªÙØ±ÙØ±Ù Ø§ÙÙÙÙÙ',
        'Ø£ÙØ¹Ø¬Ø¨ Ø£Ø­Ø¯ Ø²ÙÙØ§Ø¦Ù Ø¨ØªÙØ±ÙØ±Ù Ø§ÙÙÙÙÙ.',
        'general', 'low', 'daily_reports', p_report_id,
        jsonb_build_object('event', 'daily_report_like')
      );
    end if;
  end if;

  select count(*) into v_count
  from public.daily_report_likes
  where report_id = p_report_id;

  return jsonb_build_object('liked', v_liked, 'count', v_count);
end;
$function$;

-- add_daily_report_comment(uuid,text)
CREATE OR REPLACE FUNCTION public.add_daily_report_comment(p_report_id uuid, p_comment text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_author uuid;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_comment, '')), '') is null then
    raise exception 'التعليق مطلوب' using errcode = '22023';
  end if;

  select employee_id into v_author
  from public.daily_reports
  where id = p_report_id;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  insert into public.daily_report_comments (report_id, employee_id, comment)
  values (p_report_id, v_me, trim(p_comment))
  returning id into v_id;

  if v_author is distinct from v_me then
    perform public.notify_employee(
      v_author,
      'ØªØ¹ÙÙÙ Ø¬Ø¯ÙØ¯ Ø¹ÙÙ ØªÙØ±ÙØ±Ù Ø§ÙÙÙÙÙ',
      trim(p_comment),
      'general', 'normal', 'daily_reports', p_report_id,
      jsonb_build_object('event', 'daily_report_comment', 'commentId', v_id)
    );
  end if;

  return v_id;
end;
$function$;

-- delete_daily_report_comment(uuid)
CREATE OR REPLACE FUNCTION public.delete_daily_report_comment(p_comment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_owner uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select employee_id into v_owner
  from public.daily_report_comments
  where id = p_comment_id;
  if not found then
    raise exception 'التعليق غير موجود' using errcode = 'P0002';
  end if;

  if v_owner is distinct from v_me and not public.current_is_full_access() then
    raise exception 'غير مصرح لك بحذف هذا التعليق' using errcode = '42501';
  end if;

  delete from public.daily_report_comments where id = p_comment_id;
end;
$function$;

-- get_mobile_employee_directory(text,integer)
CREATE OR REPLACE FUNCTION public.get_mobile_employee_directory(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 40)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'غير مسجل الدخول' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name,
      'statusToday',  case
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
        when exists (
          select 1 from public.missions m join public.requests r on r.id = m.request_id
          where m.employee_id = e.id and r.status = 'approved'
            and v_today between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
          where c.employee_id = e.id and r.status = 'approved'
            and v_today between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
          where wp.employee_id = e.id and wa.status = 'APPROVED' and coalesce(wa.counts_as_work_day,true)
            and v_today between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id and r.status = 'approved'
            and v_today between lr.start_date and lr.end_date
        ) then 'on_leave'
        else 'absent'
      end
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    where e.is_active  = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù
      and (
        v_search is null
        or e.full_name_ar  ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%'
        or jt.name         ilike '%' || v_search || '%'
        or d.name          ilike '%' || v_search || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$function$;

-- get_mobile_executive_people(text,integer)
CREATE OR REPLACE FUNCTION public.get_mobile_executive_people(p_search text DEFAULT NULL::text, p_limit integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_allowed boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول الموظفين التنفيذي مرفوض' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id,
      'employeeCode', x.employee_code,
      'name', x.full_name_ar,
      'photoUrl', x.photo_url,
      'jobTitle', x.job_title,
      'department', x.department,
      'team', x.team,
      'attendanceStatus', x.attendance_status,
      'pendingRequests', x.pending_requests,
      'openTasks', x.open_tasks,
      'latestKpiScore', x.latest_kpi_score
    ) order by x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        ad.status attendance_status,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1) latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and not public.is_employee_executive(e.id)  -- 0444: Ø§Ø³ØªØ¨Ø¹Ø§Ø¯ Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù
        and public.can_access_employee(e.id,'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$function$;

-- transition_my_task(uuid,text)
CREATE OR REPLACE FUNCTION public.transition_my_task(p_task_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_task public.tasks%rowtype;
  v_onboarding public.onboarding_tasks%rowtype;
  v_journey public.onboarding_journeys%rowtype;
  v_db_status text;
  v_remaining integer;
begin
  if p_status not in ('pending','in_progress','done') then
    raise exception 'حالة مهمة غير مدعومة' using errcode = '22023';
  end if;

  select * into v_task from public.tasks where id = p_task_id for update;
  if found then
    if v_task.assignee_employee_id is distinct from v_employee_id then
      raise exception 'المهمة خارج نطاقك' using errcode = '42501';
    end if;
    if v_task.status = 'cancelled' then
      raise exception 'المهمة الملغاة لا تتغير' using errcode = 'P0001';
    end if;
    if v_task.status = 'done' and p_status <> 'done' then
      raise exception 'إعادة فتح المهمة المكتملة لصاحبها أو الإدارة فقط' using errcode = '42501';
    end if;
    update public.tasks set status = p_status, updated_at = now() where id = p_task_id;
    return jsonb_build_object('id', p_task_id, 'sourceType', 'task', 'status', p_status, 'updatedAt', now());
  end if;

  select ot.* into v_onboarding
  from public.onboarding_tasks ot
  where ot.id = p_task_id
  for update;
  if not found then raise exception 'المهمة غير موجودة' using errcode = 'P0002'; end if;

  select j.* into v_journey
  from public.onboarding_journeys j
  where j.id = v_onboarding.journey_id
  for update;

  if not (
    v_onboarding.assignee_id = v_employee_id
    or (v_onboarding.assignee_id is null and v_journey.employee_id = v_employee_id and lower(coalesce(v_onboarding.owner_role, '')) in ('employee','ÙÙØ¸Ù'))
  ) then
    raise exception 'مهمة التهيئة خارج نطاقك' using errcode = '42501';
  end if;
  if v_onboarding.status in ('completed','skipped') and p_status <> 'done' then
    raise exception 'الموظف لا يعيد فتح مهمة تهيئة مكتملة' using errcode = '42501';
  end if;

  v_db_status := case p_status when 'done' then 'completed' else p_status end;
  update public.onboarding_tasks set
    status = v_db_status,
    completed_at = case when v_db_status = 'completed' then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id;

  select count(*) into v_remaining
  from public.onboarding_tasks
  where journey_id = v_onboarding.journey_id and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_onboarding.journey_id;
    update public.employees set status = 'active', updated_at = now()
    where id = v_journey.employee_id and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_onboarding.journey_id;
  end if;

  return jsonb_build_object(
    'id', p_task_id, 'sourceType', 'onboarding', 'status', p_status,
    'journeyId', v_onboarding.journey_id, 'remainingTasks', v_remaining,
    'updatedAt', now()
  );
end;
$function$;

-- link_fundraising_to_target(uuid,uuid,numeric,text)
CREATE OR REPLACE FUNCTION public.link_fundraising_to_target(p_assignment_id uuid, p_evaluation_id uuid, p_weight numeric DEFAULT 40, p_note text DEFAULT NULL::text)
 RETURNS kpi_assignment_contributions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_asg public.work_assignments;
  v_emp uuid;
  v_goal_id uuid;
  v_achieved numeric;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_weight is null or p_weight <= 0 or p_weight > 40 then
    raise exception 'TARGET_WEIGHT_OUT_OF_RANGE (0..40]' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode='P0002'; end if;
  if v_asg.assignment_type <> 'FUNDRAISING' then
    raise exception 'فقط جمع التبرعات يرتبط بهدف مالي' using errcode='22023';
  end if;
  if v_asg.target_amount is null or v_asg.target_amount <= 0 then
    raise exception 'التكليف بلا هدف مالي' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  -- Ø§ÙÙØ­ÙÙ: ÙØ¬ÙÙØ¹ ÙØ­ÙÙ Ø§ÙÙØ´Ø§Ø±ÙÙÙ Ø¥Ù ÙÙØ¬Ø¯Ø ÙØ¥ÙØ§ achieved_amount Ø¹ÙÙ Ø§ÙØªÙÙÙÙ.
  select coalesce(sum(achieved_amount), 0) into v_achieved
  from public.work_assignment_participants
  where assignment_id = p_assignment_id and employee_id = v_emp;
  if v_achieved = 0 then v_achieved := coalesce(v_asg.achieved_amount, 0); end if;

  -- Ø³Ø¬ÙÙ Ø§ÙÙØ³Ø§ÙÙØ© Ø£ÙÙÙØ§ ÙØ¶ÙØ§Ù ÙÙØ¹ Ø§ÙØªÙØ±Ø§Ø±.
  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, amount, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'TARGET', v_achieved, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (ÙÙØ¹ Ø§ÙØ§Ø­ØªØ³Ø§Ø¨ Ø§ÙÙØ²Ø¯ÙØ¬)' using errcode='23505';
  end if;

  -- Ø£ÙØ´Ø¦/Ø­Ø¯ÙØ« ÙØ¯Ù TARGET Ø§ÙÙØ§ÙÙ.
  insert into public.kpi_goals(
    evaluation_id, title, description, target_value, achieved_value, unit, weight,
    evidence_source, created_by)
  values(
    p_evaluation_id, format('ÙØ³ØªÙØ¯Ù ÙØ§ÙØ¯Ù: %s', v_asg.title), p_note,
    v_asg.target_amount, v_achieved, 'EGP', p_weight,
    'work_assignments', auth.uid())
  returning id into v_goal_id;

  perform public.log_audit_event(
    'kpi.assignment.target.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'Ø±Ø¨Ø· ÙØ§ÙØ¯Ù Ø¨ÙØ³ØªÙØ¯Ù ÙØ§ÙÙ', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'goalId', v_goal_id,
                       'target', v_asg.target_amount, 'achieved', v_achieved));
  return v_row;
end $function$;

-- register_my_device(text,text,text,text,text,text,integer,text,boolean,boolean,jsonb)
CREATE OR REPLACE FUNCTION public.register_my_device(p_installation_id text, p_platform text, p_device_name text, p_device_model text, p_os_version text, p_app_version text, p_app_build integer, p_environment text DEFAULT 'production'::text, p_push_enabled boolean DEFAULT false, p_biometric_available boolean DEFAULT false, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS managed_devices
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_row public.managed_devices;
  v_existing_user uuid;
  v_employee_id uuid := public.current_employee_id();
  v_identifier_hash text;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_installation_id, ''))) < 12 then
    raise exception 'معرّف جهاز غير صالح' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  if p_environment not in ('development', 'staging', 'production') then
    raise exception 'invalid environment' using errcode = '22023';
  end if;

  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  select user_id into v_existing_user
  from public.managed_devices
  where installation_id = p_installation_id;

  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'الجهاز مسجل على حساب آخر' using errcode = '42501';
  end if;

  insert into public.managed_devices(
    installation_id, user_id, employee_id, platform, device_name, device_model,
    os_version, app_version, app_build, environment, push_enabled,
    biometric_available, last_seen_at, metadata
  ) values (
    p_installation_id, auth.uid(), v_employee_id, p_platform,
    nullif(trim(p_device_name), ''), nullif(trim(p_device_model), ''),
    nullif(trim(p_os_version), ''), coalesce(nullif(trim(p_app_version), ''), '0.0.0'),
    greatest(coalesce(p_app_build, 0), 0), p_environment,
    coalesce(p_push_enabled, false), coalesce(p_biometric_available, false),
    now(), coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id = excluded.user_id,
    employee_id = excluded.employee_id,
    platform = excluded.platform,
    device_name = excluded.device_name,
    device_model = excluded.device_model,
    os_version = excluded.os_version,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    environment = excluded.environment,
    push_enabled = excluded.push_enabled,
    biometric_available = excluded.biometric_available,
    last_seen_at = now(),
    metadata = excluded.metadata,
    status = case
      when public.managed_devices.status = 'retired' then 'active'
      else public.managed_devices.status
    end
  returning * into v_row;

  if v_employee_id is not null and p_platform in ('android', 'ios') then
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, device_name,
      platform, status, approved_at, last_used_at, metadata
    ) values (
      v_employee_id, auth.uid(), v_identifier_hash, null,
      coalesce(nullif(trim(p_device_name), ''), nullif(trim(p_device_model), '')),
      p_platform, 'active', now(), now(), jsonb_build_object(
        'kind', 'local_biometric',
        'managedDeviceId', v_row.id,
        'biometricAvailable', coalesce(p_biometric_available, false)
      )
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      device_name = excluded.device_name,
      platform = excluded.platform,
      last_used_at = now(),
      status = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then 'active'
        else public.employee_devices.status
      end,
      approved_at = now(),
      revoked_at = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revoked_at
      end,
      revocation_source = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revocation_source
      end,
      rejection_reason = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.rejection_reason
      end,
      metadata = coalesce(public.employee_devices.metadata, '{}'::jsonb)
        || excluded.metadata
        || case
          when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
            then jsonb_build_object(
              'reregistered', true,
              'reregisteredAt', now(),
              'previousStatus', public.employee_devices.status
            )
          else '{}'::jsonb
        end;
  end if;

  perform public.log_security_event(
    'device.registered', 'low', 'allowed', v_identifier_hash,
    jsonb_build_object(
      'platform', p_platform,
      'appVersion', p_app_version,
      'appBuild', p_app_build,
      'biometricAvailable', p_biometric_available,
      'autoAccepted', true
    )
  );

  return v_row;
end;
$function$;

-- decide_discipline_action(uuid,text,text)
CREATE OR REPLACE FUNCTION public.decide_discipline_action(p_action_id uuid, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS employee_discipline_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.approve')) then
    raise exception 'FORBIDDEN: requires relations.discipline.approve' using errcode = '42501';
  end if;

  select * into v_row from public.employee_discipline_actions where id = p_action_id;
  if not found then
    raise exception 'discipline_action_not_found' using errcode = 'P0002';
  end if;

  if v_row.status <> 'pending' then
    raise exception 'discipline_action_not_pending' using errcode = '22023';
  end if;

  if p_decision not in ('approved','rejected') then
    raise exception 'قرار غير صالح' using errcode = '22023';
  end if;

  update public.employee_discipline_actions
  set status = p_decision,
      decision_note = p_note,
      decided_by = v_me,
      decided_at = now(),
      updated_at = now()
  where id = p_action_id
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.' || p_decision, 'compliance',
    case when p_decision = 'approved' then 'high' else 'info' end,
    'employee_discipline_actions', v_row.id,
    case when p_decision = 'approved' then 'ØªÙ Ø§Ø¹ØªÙØ§Ø¯ Ø§ÙØ¥Ø¬Ø±Ø§Ø¡ Ø§ÙØªØ£Ø¯ÙØ¨Ù' else 'ØªÙ Ø±ÙØ¶ Ø§ÙØ¥Ø¬Ø±Ø§Ø¡ Ø§ÙØªØ£Ø¯ÙØ¨Ù' end,
    null,
    jsonb_build_object('employeeId', v_row.employee_id, 'actionId', v_row.id, 'note', p_note));

  perform public.notify_employee(
    v_row.employee_id,
    case when p_decision = 'approved' then 'ØªÙ Ø§Ø¹ØªÙØ§Ø¯ Ø¥Ø¬Ø±Ø§Ø¡ ØªØ£Ø¯ÙØ¨Ù Ø¹ÙÙ ÙÙÙÙ' else 'ØªÙ Ø±ÙØ¶ Ø¥Ø¬Ø±Ø§Ø¡ ØªØ£Ø¯ÙØ¨Ù ÙØ³Ø¬Ù Ø¹ÙÙ ÙÙÙÙ' end,
    coalesce(nullif(trim(p_note), ''), 'ÙØ±Ø¬Ù ÙØ±Ø§Ø¬Ø¹Ø© Ø³Ø¬ÙÙ ÙÙ ÙØ³Ù Ø§ÙØ§ÙØ¶Ø¨Ø§Ø·.'),
    'general', case when p_decision = 'approved' then 'normal' else 'low' end,
    null, null, '{}'::jsonb
  );

  return v_row;
end;
$function$;

-- upsert_department_admin(uuid,uuid,uuid,uuid,uuid,text,text,text,boolean)
CREATE OR REPLACE FUNCTION public.upsert_department_admin(p_id uuid, p_legal_entity_id uuid, p_branch_id uuid, p_parent_id uuid, p_manager_id uuid, p_code text, p_name text, p_name_en text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.department.manage') or public.has_permission('organization.unit.manage')) then
    raise exception 'إدارة الأقسام مرفوضة' using errcode = '42501';
  end if;
  if nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'كود واسم القسم مطلوبان' using errcode = '22023';
  end if;
  if p_legal_entity_id is null then
    raise exception 'الكيان القانوني مطلوب' using errcode = '22023';
  end if;
  if p_id is not null and p_parent_id = p_id then
    raise exception 'القسم لا يتبع نفسه' using errcode = '22023';
  end if;

  if p_id is not null and p_parent_id is not null then
    with recursive descendants as (
      select d.id from public.departments d where d.parent_id = p_id
      union all
      select d.id from public.departments d join descendants x on d.parent_id = x.id
    )
    select exists(select 1 from descendants where id = p_parent_id) into v_cycle;
    if v_cycle then
      raise exception 'دورة في تسلسل الأقسام' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.departments(
      legal_entity_id, branch_id, parent_id, manager_id,
      code, name, name_en, is_active, created_by
    ) values (
      p_legal_entity_id, p_branch_id, p_parent_id, p_manager_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.departments set
      legal_entity_id = p_legal_entity_id,
      branch_id = p_branch_id,
      parent_id = p_parent_id,
      manager_id = p_manager_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'القسم غير موجود' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$function$;

-- resubmit_my_request(uuid,text,text,jsonb)
CREATE OR REPLACE FUNCTION public.resubmit_my_request(p_request_id uuid, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me      uuid := public.current_employee_id();
  v_req     public.requests;
  v_def     public.workflow_definitions;
  v_manager uuid;
  v_due     timestamptz;
  v_esc     timestamptz;
  v_first_approver uuid;
  v_exec_emp uuid;
  v_label   text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select * into v_req from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;

  -- Ø§ÙÙØ§ÙÙ Ø­ØµØ±Ø§Ù
  if v_req.employee_id <> v_me then
    raise exception 'FORBIDDEN: only the requester may resubmit' using errcode = '42501';
  end if;

  -- ÙÙ Ø§ÙÙØ±ÙÙØ¶/Ø§ÙÙÙØ±Ø¬ÙØ¹ ÙÙØ·
  if v_req.status not in ('rejected', 'returned') then
    raise exception 'ONLY_REJECTED_OR_RETURNED_CAN_RESUBMIT' using errcode = '22023';
  end if;

  -- Ø§ÙØ£ÙÙØ§Ø¹ Ø§ÙÙØ§Ø¨ÙØ© ÙØ¥Ø¹Ø§Ø¯Ø© Ø§ÙØ±ÙØ¹ (ÙÙØ³ Ø£ÙÙØ§Ø¹ submit_my_request Ø¹Ø¯Ø§ Ø§ÙØªØµØ­ÙØ­)
  if v_req.request_type not in
     ('leave','mission','convoy','fundraising','late_permit','early_permit') then
    raise exception 'TYPE_NOT_RESUBMITTABLE' using errcode = '22023';
  end if;

  -- ØªØ­ÙÙ Ø§ÙØ·ÙÙ (ÙØ·Ø§Ø¨Ù ÙÙÙÙØ¯ Ø§ÙØ¬Ø¯ÙÙ)
  if p_title is null or length(trim(p_title)) < 3 or length(trim(p_title)) > 300 then
    raise exception 'INVALID_TITLE_LENGTH' using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 or length(trim(p_reason)) > 300 then
    raise exception 'INVALID_REASON_LENGTH' using errcode = '22023';
  end if;

  -- 0457: Ø§Ø³ØªØ®Ø¯Ø§Ù resolve_request_approver Ø¨Ø¯ÙØ§Ù ÙÙ lookup ÙØ¨Ø§Ø´Ø±.
  -- ÙØ¶ÙÙ Ø§ÙØªÙØ¬ÙÙ Ø§ÙØµØ­ÙØ­ ÙØ·ÙØ¨Ø§Øª Ø§ÙØªØ´ØºÙÙâØªÙÙÙØ°Ù + Ø§ÙØ³ÙÙØ· Ø¹ÙÙ HR + ÙÙØ¹ Ø§ÙÙÙØ§ÙÙØ© Ø§ÙØ°Ø§ØªÙØ©.
  v_manager := public.resolve_request_approver(v_req.employee_id);

  -- ÙÙÙØ§Øª Ø§ÙØ³ÙØ± ÙÙ Ø§ÙØªØ¹Ø±ÙÙ Ø§ÙÙØ´Ø·
  if v_req.workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = v_req.workflow_definition_id;
  end if;
  if v_def.id is null or not v_def.is_active then
    select * into v_def from public.workflow_definitions
      where request_type = v_req.request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;
  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
  else
    v_due := now() + interval '48 hours';
  end if;

  -- 1) ØªØ­Ø¯ÙØ« Ø§ÙØ·ÙØ¨ ÙØªØµÙÙØ± Ø§ÙÙØ±Ø§Ø±
  update public.requests set
    title                = trim(p_title),
    reason               = trim(p_reason),
    payload              = coalesce(p_payload, '{}'::jsonb),
    status               = 'pending',
    workflow_status      = 'submitted',
    current_step_order   = 1,
    manager_employee_id  = coalesce(v_manager, manager_employee_id),
    decision_due_at      = v_due,
    escalation_deadline  = v_esc,
    escalated_at         = null,
    decided_at           = null,
    decided_by           = null,
    updated_at           = now()
  where id = v_req.id
  returning * into v_req;

  -- 2) Ø®Ø·ÙØ§Øª Ø¬Ø¯ÙØ¯Ø© ÙÙ Ø§ÙØªØ¹Ø±ÙÙ (Ø§ÙØ£ÙÙÙ ÙØ´Ø·Ø© Ø¨ÙÙÙØªÙØ§)
  delete from public.request_steps where request_id = v_req.id;

  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_req.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then v_manager
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
           then now() + make_interval(hours := ws.escalate_after_hours) end,
      auth.uid()
    from public.workflow_steps ws
    where ws.definition_id = v_def.id and ws.is_active = true
    order by ws.step_order;

    -- 3) Ø¥Ø¹Ø§Ø¯Ø© ÙØªØ­ ÙØ³Ø®Ø© Ø§ÙØ³ÙØ± ÙÙØ³ÙØ§ (ÙÙØ¯ ÙØ±ÙØ¯: ÙØ³Ø®Ø© ÙØ§Ø­Ø¯Ø© ÙÙÙ Ø·ÙØ¨)
    update public.workflow_instances
      set definition_id      = v_def.id,
          definition_version = coalesce(v_def.version, 1),
          status             = 'running',
          current_step_order = 1,
          updated_at         = now()
      where request_id = v_req.id;

    if not found then
      insert into public.workflow_instances (
        definition_id, request_id, definition_version, status, current_step_order, created_by
      ) values (
        v_def.id, v_req.id, coalesce(v_def.version, 1), 'running', 1, auth.uid()
      );
    end if;
  end if;

  -- 4) ØªÙØ«ÙÙ Ø§ÙØ¥Ø¬Ø±Ø§Ø¡
  insert into public.request_actions (
    request_id, actor_employee_id, action, from_status, to_status, comment, created_by
  ) values (
    v_req.id, v_me, 'submit', 'rejected', 'pending', trim(p_reason), auth.uid()
  );

  -- 5) Ø§ÙØ¥Ø´Ø¹Ø§Ø±Ø§Øª
  v_label := format('%s â %s (ÙÙØ¹Ø§Ø¯Ø© Ø¨Ø¹Ø¯ ØªØ¹Ø¯ÙÙ)',
    public.request_type_label(v_req.request_type), coalesce(v_req.title, ''));

  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_req.id and s.status = 'active'
  order by s.step_order limit 1;
  if v_first_approver is null then
    v_first_approver := v_req.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_req.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'Ø·ÙØ¨ ÙÙØ¹Ø¯ÙÙ Ø¨Ø§ÙØªØ¸Ø§Ø± ÙØ±Ø§Ø¬Ø¹ØªÙ',
      v_label,
      'request', 'high', 'request', v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'workflowStatus', 'submitted',
        'resubmitted', true,
        'deepLink', '/requests/' || v_req.id
      )
    );
  end if;

  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_req.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'Ø·ÙØ¨ ÙÙØ¹Ø¯ÙÙ â ÙÙÙØ±Ø§Ø¬Ø¹Ø©',
      v_label,
      'request',
      'request', v_req.id,
      '/requests/' || v_req.id,
      jsonb_build_object(
        'requestType', v_req.request_type,
        'resubmitted', true,
        'infoOnly', false
      )
    );
  end if;

  return to_jsonb(v_req);
end;
$function$;

-- decide_work_assignment(uuid,text,text)
CREATE OR REPLACE FUNCTION public.decide_work_assignment(p_assignment_id uuid, p_decision text, p_comment text DEFAULT NULL::text)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments; v_to text; v_part uuid;
begin
  if p_decision not in ('approve','reject') then
    raise exception 'قرار غير صالح' using errcode = '22023';
  end if;
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'غير مصرح لك بحسم هذا التكليف' using errcode = '42501';
  end if;
  if v_row.status not in ('SUBMITTED','PENDING_APPROVAL','DRAFT') then
    raise exception 'assignment not in a decidable state (%)', v_row.status using errcode = '22023';
  end if;
  v_to := case when p_decision = 'approve' then 'APPROVED' else 'REJECTED' end;

  update public.work_assignments
    set status = v_to, decided_by = v_me, decided_at = now(),
        decision_comment = p_comment, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.decided', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'ÙØ±Ø§Ø± Ø¹ÙÙ ØªÙÙÙÙ Ø¹ÙÙ', p_decision,
    jsonb_build_object('decision', p_decision, 'type', v_row.assignment_type));

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙØ´Ø§Ø±ÙÙÙ ÙÙÙØ´Ø¦ Ø§ÙØªÙÙÙÙ (0316)
  for v_part in
    select employee_id from public.work_assignment_participants
    where assignment_id = p_assignment_id
  loop
    perform public.notify_employee(
      v_part,
      case p_decision when 'approve' then 'ØªÙ Ø§Ø¹ØªÙØ§Ø¯ ØªÙÙÙÙÙ' else 'ØªÙ Ø±ÙØ¶ ØªÙÙÙÙÙ' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'ÙØ£ÙÙØ±ÙØ©'
                         when 'CONVOY' then 'ÙØ§ÙÙØ©'
                         else 'ÙØ§ÙØ¯Ù' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end loop;
  if v_row.created_by_employee_id is not null and v_row.created_by_employee_id <> v_me then
    perform public.notify_employee(
      v_row.created_by_employee_id,
      case p_decision when 'approve' then 'ØªÙ Ø§Ø¹ØªÙØ§Ø¯ ØªÙÙÙÙ Ø§ÙØ¹ÙÙ' else 'ØªÙ Ø±ÙØ¶ ØªÙÙÙÙ Ø§ÙØ¹ÙÙ' end,
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'ÙØ£ÙÙØ±ÙØ©'
                         when 'CONVOY' then 'ÙØ§ÙÙØ©'
                         else 'ÙØ§ÙØ¯Ù' end, v_row.title),
      'general', case p_decision when 'approve' then 'normal' else 'high' end,
      'work_assignments', p_assignment_id,
      jsonb_build_object('decision', p_decision, 'assignmentType', v_row.assignment_type));
  end if;

  return v_row;
end $function$;

-- submit_assignment_report(uuid,text,text,numeric)
CREATE OR REPLACE FUNCTION public.submit_assignment_report(p_assignment_id uuid, p_report text, p_outcome text DEFAULT NULL::text, p_achieved_amount numeric DEFAULT NULL::numeric)
 RETURNS work_assignment_participants
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignment_participants;
begin
  if length(trim(coalesce(p_report,''))) < 3 then
    raise exception 'التقرير مطلوب' using errcode = '22023';
  end if;
  update public.work_assignment_participants
    set report = p_report, outcome = p_outcome, achieved_amount = p_achieved_amount,
        attendance_status = 'completed', updated_at = now()
    where assignment_id = p_assignment_id and employee_id = v_me
    returning * into v_row;
  if not found then raise exception 'not a participant' using errcode = '42501'; end if;

  update public.work_assignments
    set status = 'REPORT_SUBMITTED', updated_at = now()
    where id = p_assignment_id and needs_report = true and status in ('APPROVED','IN_PROGRESS','COMPLETED','REPORT_PENDING');

  perform public.log_audit_event(
    'assignment.report.submitted', 'workflow', 'info', 'work_assignments', p_assignment_id,
    'Ø¥Ø±Ø³Ø§Ù ØªÙØ±ÙØ± ØªÙÙÙØ° ØªÙÙÙÙ', null,
    jsonb_build_object('employeeId', v_me, 'achievedAmount', p_achieved_amount));
  return v_row;
end $function$;

-- rpc_upsert_role(uuid,text,text,text,text,text,text,boolean)
CREATE OR REPLACE FUNCTION public.rpc_upsert_role(p_id uuid, p_slug text, p_name_ar text, p_name_en text, p_description text, p_color text, p_icon text, p_is_full_access boolean DEFAULT false)
 RETURNS roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.roles; v_existing public.roles;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['access.role.create','access.role.update'])) then
    raise exception 'غير مصرح لك بإدارة الأدوار' using errcode = '42501';
  end if;

  -- ÙÙØ­ full-access ÙØ­ØµÙØ± Ø¨Ùsuper-admin ÙÙØ·
  if p_is_full_access and not public.current_is_super_admin() then
    raise exception 'المدير الأعلى فقط يمنح الوصول الكامل' using errcode = '42501';
  end if;

  if p_id is not null then
    select * into v_existing from public.roles where id = p_id;
    -- ÙÙØ¹ ØªØ¹Ø¯ÙÙ Ø§ÙØ£Ø¯ÙØ§Ø± Ø§ÙÙØ¸Ø§ÙÙØ© ÙÙ ØºÙØ± super-admin
    if v_existing.is_system and not public.current_is_super_admin() then
      raise exception 'system roles are protected' using errcode = '42501';
    end if;
    update public.roles set
      slug = coalesce(p_slug, slug),
      name_ar = coalesce(p_name_ar, name_ar),
      name_en = p_name_en,
      description = p_description,
      color = p_color, icon = p_icon,
      -- is_full_access ÙØªØºÙÙØ± ÙÙØ· Ø¨ÙØ§Ø³Ø·Ø© super-adminØ Ø®ÙØ§Ù Ø°ÙÙ ÙØ¨ÙÙ ÙÙØ§ ÙÙ
      is_full_access = case when public.current_is_super_admin() then p_is_full_access else is_full_access end,
      updated_at = now()
    where id = p_id returning * into v_row;
  else
    insert into public.roles (slug, name_ar, name_en, description, color, icon, is_system, is_full_access, created_by)
    values (p_slug, p_name_ar, p_name_en, p_description, p_color, p_icon, false,
            case when public.current_is_super_admin() then p_is_full_access else false end, auth.uid())
    returning * into v_row;
  end if;
  return v_row;
end;
$function$;

-- add_employee_penalty(uuid,text,numeric,text,text)
CREATE OR REPLACE FUNCTION public.add_employee_penalty(p_employee_id uuid, p_penalty_type text, p_amount numeric, p_reason text, p_evidence_ref text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'لا يوجد ملف موظف لصاحب الطلب' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_amount is null or p_amount < 0 then raise exception 'مبلغ غير صالح' using errcode='22023'; end if;
  if nullif(trim(p_penalty_type), '') is null then raise exception 'نوع جزاء غير صالح' using errcode='22023'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;
  if not exists (select 1 from public.employees where id = p_employee_id and not is_deleted) then
    raise exception 'employee not found' using errcode='P0002';
  end if;

  insert into public.employee_penalties(
    employee_id, penalty_type, amount, currency, reason, evidence_ref,
    status, issued_by, issued_at, created_by)
  values (
    p_employee_id, p_penalty_type, p_amount, 'EGP', p_reason, p_evidence_ref,
    'issued', v_me, now(), auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'penalty.issued', 'financial', 'warning',
    'employee_penalties', v_row.id, 'Ø¥ØµØ¯Ø§Ø± ÙØ®Ø§ÙÙØ© ÙØ§ÙÙØ©', null,
    jsonb_build_object('employeeId', p_employee_id, 'amount', p_amount, 'type', p_penalty_type));

  return jsonb_build_object(
    'id', v_row.id, 'employeeId', v_row.employee_id, 'amount', v_row.amount,
    'penaltyType', v_row.penalty_type, 'status', v_row.status, 'issuedAt', v_row.issued_at);
end $function$;

-- waive_employee_penalty(uuid,text)
CREATE OR REPLACE FUNCTION public.waive_employee_penalty(p_penalty_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_penalties;
begin
  if v_me is null then raise exception 'لا يوجد ملف موظف لصاحب الطلب' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason is required' using errcode='22023'; end if;

  update public.employee_penalties
     set status = 'waived', waived_by = v_me, waived_at = now(), waive_reason = p_reason,
         updated_at = now()
   where id = p_penalty_id
     and status in ('issued', 'deducted')
  returning * into v_row;

  if v_row.id is null then raise exception 'الجزاء غير موجود أو غير قابل للإسقاط' using errcode='P0002'; end if;

  perform public.log_audit_event(
    'penalty.waived', 'financial', 'info',
    'employee_penalties', v_row.id, 'Ø¥Ø³ÙØ§Ø· ÙØ®Ø§ÙÙØ© ÙØ§ÙÙØ©', null,
    jsonb_build_object('employeeId', v_row.employee_id, 'amount', v_row.amount));

  return jsonb_build_object('id', v_row.id, 'status', v_row.status, 'waivedAt', v_row.waived_at);
end $function$;

-- generate_instapay_batch(uuid)
CREATE OR REPLACE FUNCTION public.generate_instapay_batch(p_payroll_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_batch public.payroll_instapay_batches;
  v_count integer;
  v_total numeric;
  v_ref text;
begin
  if not (public.current_is_full_access() or public.has_any_permission(
      array['payroll.run.manage', 'payroll.run.approve'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.payroll_runs
    where id = p_payroll_run_id and status in ('approved', 'posted')
  ) then
    raise exception 'يجب اعتماد أو ترحيل دورة الرواتب' using errcode='P0002';
  end if;

  select count(*), coalesce(sum(pl.net_amount), 0)
    into v_count, v_total
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  if v_count = 0 then raise exception 'لا قسائم قابلة للدفع بأرقام هواتف' using errcode='P0002'; end if;

  v_ref := 'IP-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(replace(p_payroll_run_id::text, '-', ''), 1, 8));

  insert into public.payroll_instapay_batches(
    payroll_run_id, batch_reference, total_amount, item_count, status, created_by)
  values (p_payroll_run_id, v_ref, v_total, v_count, 'generated', auth.uid())
  returning * into v_batch;

  insert into public.payroll_instapay_items(batch_id, employee_id, payslip_id, mobile_e164, amount)
  select v_batch.id, pl.employee_id, pl.id, e.phone_e164, pl.net_amount
  from public.payslips pl
  join public.employees e on e.id = pl.employee_id
  where pl.payroll_run_id = p_payroll_run_id
    and pl.status in ('approved', 'issued')
    and coalesce(e.phone_e164, '') <> '';

  perform public.log_audit_event(
    'instapay.batch_generated', 'financial', 'info',
    'payroll_instapay_batches', v_batch.id, 'ØªÙÙÙØ¯ Ø¯ÙØ¹Ø© InstaPay ÙØµØ±Ù Ø§ÙØ±ÙØ§ØªØ¨', null,
    jsonb_build_object('payrollRunId', p_payroll_run_id, 'reference', v_ref, 'items', v_count, 'total', v_total));

  return jsonb_build_object(
    'id', v_batch.id, 'reference', v_batch.batch_reference,
    'totalAmount', v_batch.total_amount, 'itemCount', v_batch.item_count,
    'status', v_batch.status);
end $function$;

-- request_break_glass(uuid,uuid,integer,text)
CREATE OR REPLACE FUNCTION public.request_break_glass(p_target_user_id uuid, p_role_id uuid, p_duration_minutes integer, p_reason text)
 RETURNS break_glass_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.break_glass_requests; v_role public.roles;
begin
  if not (public.current_is_full_access() or public.has_permission('access.break_glass.request')) then raise exception 'طلب الاستثناء الطارئ مرفوض' using errcode='42501'; end if;
  select * into v_role from public.roles where id=p_role_id;
  if not found then raise exception 'role not found' using errcode='P0002'; end if;
  if p_duration_minutes not between 5 and 240 then raise exception 'المدة خارج النطاق' using errcode='22023'; end if;
  insert into public.break_glass_requests(target_user_id,requested_role_id,duration_minutes,reason,requested_by)
  values(p_target_user_id,p_role_id,p_duration_minutes,trim(p_reason),auth.uid()) returning * into v_row;
  perform public.log_security_event('break_glass.requested','critical','detected',p_target_user_id::text,
    jsonb_build_object('requestId',v_row.id,'role',v_role.slug,'durationMinutes',p_duration_minutes,'reason',p_reason));
  perform public.notify_employees_with_permission(
    'access.break_glass.approve',
    'Ø·ÙØ¨ Break Glass Ø¨Ø§ÙØªØ¸Ø§Ø± Ø§Ø¹ØªÙØ§Ø¯Ù',
    format('Ø·ÙØ¨ ÙØµÙÙ Ø§Ø³ØªØ«ÙØ§Ø¦Ù ÙØ¯ÙØ± %s ÙÙØ¯Ø© %s Ø¯ÙÙÙØ©.', v_role.slug, p_duration_minutes),
    'security', 'high', 'break_glass_requests', v_row.id,
    jsonb_build_object('role', v_role.slug, 'durationMinutes', p_duration_minutes));
  return v_row;
end;
$function$;

-- submit_discipline_action(uuid,text,text,text,text,numeric,date,date)
CREATE OR REPLACE FUNCTION public.submit_discipline_action(p_employee_id uuid, p_action_type text, p_title text, p_description text, p_severity text DEFAULT 'moderate'::text, p_amount numeric DEFAULT NULL::numeric, p_effective_from date DEFAULT NULL::date, p_effective_to date DEFAULT NULL::date)
 RETURNS employee_discipline_actions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.employee_discipline_actions;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not (public.current_is_full_access() or public.has_permission('relations.discipline.create')) then
    raise exception 'FORBIDDEN: requires relations.discipline.create' using errcode = '42501';
  end if;

  if not exists (select 1 from public.employees where id = p_employee_id and is_deleted = false) then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  if p_action_type not in ('verbal_warning','written_warning','salary_deduction','suspension','termination') then
    raise exception 'نوع إجراء غير صالح' using errcode = '22023';
  end if;

  if p_action_type = 'salary_deduction' and (p_amount is null or p_amount <= 0) then
    raise exception 'المبلغ مطلوب للخصم من الراتب' using errcode = '22023';
  end if;

  insert into public.employee_discipline_actions(
    employee_id, action_type, title, description, severity, amount,
    effective_from, effective_to, status, created_by)
  values (
    p_employee_id, p_action_type, trim(p_title), trim(p_description), p_severity, p_amount,
    p_effective_from, p_effective_to, 'pending', auth.uid())
  returning * into v_row;

  perform public.log_audit_event(
    'discipline.submitted', 'compliance', 'warning',
    'employee_discipline_actions', v_row.id,
    'Ø¥Ø¬Ø±Ø§Ø¡ ØªØ£Ø¯ÙØ¨Ù Ø¬Ø¯ÙØ¯ Ø¨Ø§ÙØªØ¸Ø§Ø± Ø§ÙØ§Ø¹ØªÙØ§Ø¯', null,
    jsonb_build_object('employeeId', p_employee_id, 'actionType', p_action_type));

  perform public.notify_employee(
    p_employee_id,
    'Ø¥Ø¬Ø±Ø§Ø¡ ØªØ£Ø¯ÙØ¨Ù Ø¨Ø§ÙØªØ¸Ø§Ø± Ø§ÙÙØ±Ø§Ø¬Ø¹Ø©',
    'ØªÙ ØªØ³Ø¬ÙÙ Ø¥Ø¬Ø±Ø§Ø¡ (' || public.discipline_action_type_label(p_action_type) || ') Ø¹ÙÙ ÙÙÙÙ ÙÙÙ Ø¨Ø§ÙØªØ¸Ø§Ø± Ø§ÙØ§Ø¹ØªÙØ§Ø¯.',
    'general', 'normal', null, null, '{}'::jsonb
  );

  return v_row;
end;
$function$;

-- update_system_settings(jsonb)
CREATE OR REPLACE FUNCTION public.update_system_settings(p_updates jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_item jsonb;
  v_key text;
  v_val text;
  v_updated integer := 0;
begin
  if not (public.current_is_full_access() or public.has_permission('settings.manage')) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'object' then
    raise exception 'التحديثات يجب أن تكون كائن JSON' using errcode='22023';
  end if;

  for v_item in select * from jsonb_each(p_updates)
  loop
    v_key := v_item ->> 'key';
    v_val := (v_item -> 'value')::text;
    update public.system_settings
       set value = v_val,
           updated_at = now()
     where key = v_key
       and is_editable = true
       and is_secret = false;
    if found then v_updated := v_updated + 1; end if;
  end loop;

  if v_updated > 0 then
    perform public.log_audit_event(
      'settings.updated', 'system', 'info',
      'system_settings', null, 'ØªØ­Ø¯ÙØ« Ø¥Ø¹Ø¯Ø§Ø¯Ø§Øª Ø§ÙÙØ¸Ø§Ù', null,
      jsonb_build_object('updatedKeys', v_updated));
  end if;

  return v_updated;
end $function$;

-- request_live_location(uuid,text,text)
CREATE OR REPLACE FUNCTION public.request_live_location(p_employee_id uuid, p_mode text DEFAULT 'snapshot'::text, p_reason text DEFAULT ''::text)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
  v_deep_link text;
begin
  if v_me is null then raise exception 'لا يوجد ملف موظف لصاحب الطلب' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.current_has_active_role(array['executive', 'executive-director'])) then
    raise exception 'المدير التنفيذي فقط يطلب موقع الموظف' using errcode='42501';
  end if;
  if p_employee_id = v_me then raise exception 'لا يمكنك طلب موقعك' using errcode='22023'; end if;

  -- 0444: Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù ÙØ§ ÙÙØ·ÙØ¨ ÙÙÙØ¹Ù â ÙÙ ÙÙØ· ÙÙ ÙØ·ÙØ¨ ÙÙØ§ÙØ¹ Ø§ÙØ¢Ø®Ø±ÙÙ
  if public.is_employee_executive(p_employee_id) then
    raise exception 'لا يمكن طلب موقع المدير التنفيذي' using errcode='22023';
  end if;

  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only'
      using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees where id = p_employee_id
      and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'الموظف غير نشط أو بلا حساب مرتبط' using errcode='P0002';
  end if;

  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = p_employee_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by)
  values(
    p_employee_id, v_me, coalesce(nullif(trim(p_reason),''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V17'),
    auth.uid())
  returning * into v_req;

  update public.live_location_requests
    set metadata = metadata || jsonb_build_object('requestId', v_req.id)
    where id = v_req.id returning * into v_req;

  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by)
    values(
      v_target_user, p_employee_id, 'Ø·ÙØ¨ ØªØ­Ø¯ÙØ¯ ÙÙÙØ¹ ÙÙØ±Ù',
      'Ø§ÙØ³ÙØ±ØªÙØ± Ø§ÙØªÙÙÙØ°Ù Ø£Ù Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù ÙØ·ÙØ¨ ÙÙÙØ¹Ù Ø§ÙØ¢Ù. ÙØ±Ø¬Ù Ø§ÙØ§Ø³ØªØ¬Ø§Ø¨Ø©.',
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id, jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v6',
        'deepLink', v_deep_link),
      auth.uid());
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'ØªÙ Ø·ÙØ¨ Ø§ÙÙÙÙØ¹ Ø§ÙÙØ­Ø¸Ù', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id));
  return v_req;
end $function$;

-- get_live_location_request_by_id(uuid)
CREATE OR REPLACE FUNCTION public.get_live_location_request_by_id(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'id', q.id, 'requesterName', q.requester_name, 'reason', q.reason,
    'status', q.effective_status, 'mode', q.mode,
    'durationMinutes', q.duration_minutes, 'requestedAt', q.requested_at,
    'expiresAt', q.expires_at
  ) into v_result
  from (
    select r.id, req.full_name_ar requester_name, r.reason,
      case when r.status in ('pending','accepted','active') and r.expires_at<now() then 'expired' else r.status end effective_status,
      coalesce(r.metadata->>'mode','snapshot') mode, r.duration_minutes, r.requested_at, r.expires_at
    from public.live_location_requests r
    left join public.employees req on req.id = r.requested_by
    where r.id = p_request_id
      and (
        r.employee_id = public.current_employee_id()
        or r.requested_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.can_access_employee(r.employee_id, 'live_location.view_response')
      )
  ) q;

  if v_result is null then
    raise exception 'طلب الموقع غير موجود أو غير مرئي' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

-- revoke_my_passkey(uuid,text)
CREATE OR REPLACE FUNCTION public.revoke_my_passkey(p_credential_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_credential public.passkey_credentials;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode='42501';
  end if;

  select * into v_credential
  from public.passkey_credentials
  where id=p_credential_id
    and user_id=auth.uid()
    and employee_id=v_employee_id
  for update;

  if v_credential.id is null then
    raise exception 'مفتاح الجهاز غير موجود' using errcode='P0002';
  end if;

  if v_credential.status='revoked' then
    return jsonb_build_object(
      'id',v_credential.id,
      'status','revoked',
      'alreadyRevoked',true
    );
  end if;

  update public.passkey_credentials
  set status='revoked', trusted=false, updated_at=now()
  where id=v_credential.id;

  update public.employee_devices
  set status='revoked', revoked_at=now(), updated_at=now()
  where employee_id=v_employee_id
    and credential_id=v_credential.credential_id
    and status='active';

  perform public.log_audit_event(
    'passkey.revoked',
    'security',
    'warning',
    'passkey_credentials',
    v_credential.id,
    'Ø¥ÙØºØ§Ø¡ Ø¬ÙØ§Ø² Ø¨ØµÙØ© ÙÙØ«ÙÙ',
    nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'deviceLabel',v_credential.device_label,
      'credentialDeviceType',v_credential.credential_device_type,
      'lastUsedAt',v_credential.last_used
    )
  );

  return jsonb_build_object(
    'id',v_credential.id,
    'status','revoked',
    'alreadyRevoked',false
  );
end;
$function$;

-- get_access_admin_catalog()
CREATE OR REPLACE FUNCTION public.get_access_admin_catalog()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.role.update','access.role.assign'])) then
    raise exception 'وصول كتالوج الصلاحيات مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', case
          -- ââ Ø£Ø¯ÙØ§Ø± Ø§ÙÙØµÙÙ Ø§ÙÙØ§ÙÙ: Ø¥Ø±Ø¬Ø§Ø¹ ÙÙ Ø§ÙØµÙØ§Ø­ÙØ§Øª ââ
          when r.is_full_access then
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', 'organization',
                'requiresMfa', false,
                'requiresReason', false
              ) order by p.module, p.code)
              from public.permissions p
            ), '[]'::jsonb)
          -- ââ Ø£Ø¯ÙØ§Ø± Ø¹Ø§Ø¯ÙØ©: ÙÙØ· ÙØ§ ÙÙ role_permissions ââ
          else
            coalesce((
              select jsonb_agg(jsonb_build_object(
                'permissionId', p.id, 'code', p.code,
                'name', coalesce(p.description, p.code),
                'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
                'requiresReason', rp.requires_reason
              ) order by p.module, p.code)
              from public.role_permissions rp
              join public.permissions p on p.id = rp.permission_id
              where rp.role_id = r.id
            ), '[]'::jsonb)
        end,
        'assignments', (
          select count(*)
          from public.user_roles ur
          where ur.role_id = r.id
            and ur.effective_from <= now()
            and (ur.effective_to is null or ur.effective_to > now())
        )
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action, 'name', coalesce(p.description, p.code), 'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'allowedScopes', array[
          'self','direct_reports','management_descendants','selected_employees',
          'team','department','selected_departments','branch','selected_branches',
          'organization','assigned_cases','workflow_inbox',
          'records_created_by_user','archive_readonly'
        ]
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr
      left join public.employees e on e.id = pr.employee_id
      -- ââ Ø¥Ø®ÙØ§Ø¡ Ø§ÙÙØ¤Ø±Ø´ÙÙÙ/Ø§ÙÙØ­Ø°ÙÙÙÙ ÙØ§Ø¹ÙØ§Ù (ÙØ¹ Ø¥Ø¨ÙØ§Ø¡ Ø§ÙÙÙÙØ§Øª Ø§ÙÙØªÙÙØ©) ââ
      where e.id is null
         or (e.is_active = true and e.is_deleted = false)
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- get_mobile_operations_center()
CREATE OR REPLACE FUNCTION public.get_mobile_operations_center()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_tasks    jsonb;
  v_missions jsonb;
  v_convoys  jsonb;
  v_summary  jsonb;
begin
  if auth.uid() is null then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('reports.read')
    or public.has_permission('operations.mission.manage')
    or public.has_permission('operations.convoy.manage')
  ) then
    raise exception 'صلاحية مركز العمليات مطلوبة' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_tasks
  from (
    select jsonb_build_object(
      'id', t.id,
      'title', t.title,
      'description', t.description,
      'assigneeId', t.assignee_employee_id,
      'assigneeName', coalesce(a.full_name_ar, 'ØºÙØ± ÙØ¹ÙÙÙ'),
      'priority', t.priority,
      'dueDate', t.due_date,
      'status', t.status
    ) as j
    from public.tasks t
    left join public.employees a on a.id = t.assignee_employee_id
    where (
      public.current_is_full_access()
      or t.assignee_employee_id = public.current_employee_id()
      or t.created_by_employee_id = public.current_employee_id()
      or public.has_permission('tasks.read')
    )
    order by t.created_at desc
    limit 200
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_missions
  from (
    select jsonb_build_object(
      'id', m.id,
      'employeeName', coalesce(me.full_name_ar, 'ÙÙØ¸Ù'),
      'destination', m.destination,
      'purpose', m.purpose,
      'startAt', m.start_at,
      'endAt', m.end_at,
      'status', coalesce(mr.status, 'pending'),
      'transportMode', m.transport_mode
    ) as j
    from public.missions m
    left join public.employees me on me.id = m.employee_id
    left join public.requests mr on mr.id = m.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or m.employee_id = public.current_employee_id()
      or public.can_access_employee(m.employee_id)
    )
    order by m.start_at desc
    limit 100
  ) s;

  select coalesce(jsonb_agg(s.j), '[]'::jsonb)
  into v_convoys
  from (
    select jsonb_build_object(
      'id', c.id,
      'employeeName', coalesce(ce.full_name_ar, 'ÙÙØ¸Ù'),
      'name', c.convoy_name,
      'origin', c.origin,
      'destination', c.destination,
      'departureAt', c.departure_at,
      'returnAt', c.return_at,
      'passengers', c.passengers_count,
      'vehicles', c.vehicles_count,
      'status', coalesce(cr.status, 'pending')
    ) as j
    from public.convoy_requests c
    left join public.employees ce on ce.id = c.employee_id
    left join public.requests cr on cr.id = c.request_id
    where (
      public.current_is_full_access()
      or public.has_permission('requests.read')
      or c.employee_id = public.current_employee_id()
      or public.can_access_employee(c.employee_id)
    )
    order by c.departure_at desc
    limit 100
  ) s;

  select jsonb_build_object(
    'openTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'status' not in ('done', 'cancelled')),
    'urgentTasks',
      (select count(*) from jsonb_array_elements(v_tasks) x
       where x->>'priority' = 'urgent'
         and x->>'status' not in ('done', 'cancelled')),
    'missions', jsonb_array_length(v_missions),
    'convoys', jsonb_array_length(v_convoys)
  )
  into v_summary;

  return jsonb_build_object(
    'summary', v_summary,
    'tasks', v_tasks,
    'missions', v_missions,
    'convoys', v_convoys,
    'lastUpdatedAt', now()
  );
end;
$function$;

-- register_live_location_map_snapshot(uuid,text)
CREATE OR REPLACE FUNCTION public.register_live_location_map_snapshot(p_request_id uuid, p_storage_path text)
 RETURNS location_request_responses
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.location_request_responses;
begin
  select * into v_req from public.live_location_requests
  where id = p_request_id for update;
  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  if p_storage_path not like v_me::text || '/' || p_request_id::text || '/%.png' then
    raise exception 'مسار لقطة الخريطة غير صالح' using errcode = '42501';
  end if;

  update public.location_request_responses
  set map_snapshot_storage_path = p_storage_path,
      metadata = metadata || jsonb_build_object(
        'mapSnapshotBucket', 'live-location-map-snapshots',
        'mapSnapshotRegisteredAt', now()
      )
  where request_id = p_request_id and employee_id = v_me
  returning * into v_row;
  if not found then
    raise exception 'نقطة الموقع مطلوبة قبل لقطة الخريطة' using errcode = '22023';
  end if;

  perform public.log_audit_event(
    'live_location_map_snapshot_registered', 'security', 'info',
    'location_request_responses', v_row.id, 'ØªØ³Ø¬ÙÙ ÙÙØ·Ø© Ø®Ø±ÙØ·Ø© Ø®Ø§ØµØ©', null,
    jsonb_build_object('requestId', p_request_id)
  );
  return v_row;
end;
$function$;

-- punch_attendance_local(text,text,double precision,double precision,double precision,boolean,text)
CREATE OR REPLACE FUNCTION public.punch_attendance_local(p_event_type text, p_credential_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false, p_device_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_employee record;
  v_credential record;
  v_device record;
  v_event_id uuid;
  v_event record;
  v_result jsonb;
  v_error text;
  v_known_errors constant text[] := array[
    'attendance_outside_complex',
    'attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low',
    'attendance_geofence_not_configured',
    'attendance_location_required',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required'
  ];
begin
  if v_user_id is null then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if nullif(trim(p_credential_id), '') is null then
    raise exception 'credential_required' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid_latitude_or_longitude' using errcode = '22023';
  end if;
  if p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_accuracy' using errcode = '22023';
  end if;

  -- V17 Â§7: Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù ÙØ³ØªØ«ÙÙ ÙÙ Ø§ÙØ­Ø¶ÙØ± Ø§ÙØ¥ÙØ²Ø§ÙÙ
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id = ur.role_id
    where ur.user_id = v_user_id and r.slug in ('executive', 'executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode = '42501';
  end if;

  -- Lookup employee
  select id, status, user_id into v_employee
  from public.employees
  where user_id = v_user_id and status in ('active', 'onboarding');

  if not found then
    raise exception 'employee_not_found' using errcode = '42501';
  end if;

  -- Verify credential
  select * into v_credential
  from public.passkey_credentials
  where credential_id = p_credential_id
    and employee_id = v_employee.id
    and status = 'active';

  if not found then
    raise exception 'credential_not_found' using errcode = '42501';
  end if;

  -- Verify device (match credential to employee_devices)
  select * into v_device
  from public.employee_devices
  where employee_id = v_employee.id
    and user_id = v_user_id
    and status = 'active'
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'device_not_found' using errcode = '42501';
  end if;

  begin
    v_event_id := public.record_attendance_event(
      v_employee.id,
      p_event_type,
      p_latitude,
      p_longitude,
      p_accuracy_meters,
      'passkey',
      null,
      v_credential.id,
      true,
      p_is_mock
    );
  exception
    when others then
      get stacked diagnostics v_error = message_text;
      if v_error = any(v_known_errors) then
        return jsonb_build_object(
          'ok', false,
          'error', v_error,
          'employeeId', v_employee.id
        );
      end if;
      raise;
  end;

  select * into v_event
  from public.attendance_events
  where id = v_event_id;

  return jsonb_build_object(
    'ok', true,
    'eventId', v_event_id,
    'employeeId', v_employee.id,
    'eventType', v_event.event_type,
    'eventAt', v_event.event_at,
    'status', v_event.status,
    'latitude', v_event.latitude,
    'longitude', v_event.longitude,
    'notes', v_event.notes
  );
end;
$function$;

-- send_broadcast_alert(text)
CREATE OR REPLACE FUNCTION public.send_broadcast_alert(p_message text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if not public.has_permission('alerts.broadcast.send') then
    raise exception 'صلاحية التنبيه الشامل مطلوبة' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_message, ''))) < 3
     or length(trim(p_message)) > 300 then
    raise exception 'الرسالة يجب أن تكون بين 3 و300 حرف' using errcode = '22023';
  end if;

  -- ØªÙØ¨ÙÙ ÙØ´Ø· ÙØ§Ø­Ø¯ ÙÙØ· ÙÙ Ø§ÙÙØ±Ø©.
  update public.broadcast_alerts set is_active = false where is_active;

  insert into public.broadcast_alerts(message, created_by)
  values (trim(p_message), v_me)
  returning id into v_id;

  perform public.notify_employee(
    e.id,
    'ØªÙØ¨ÙÙ Ø¹Ø§Ø¬Ù',
    trim(p_message),
    'general',
    'urgent',
    'broadcast_alert',
    v_id,
    jsonb_build_object('alertId', v_id)
  )
    from public.employees e
   where e.is_active = true
     and coalesce(e.is_deleted, false) = false;

  return v_id;
end $function$;

-- complete_my_live_location_request(uuid)
CREATE OR REPLACE FUNCTION public.complete_my_live_location_request(p_request_id uuid)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.live_location_requests;
  v_mode text;
begin
  select * into v_row
  from public.live_location_requests
  where id = p_request_id and employee_id = v_me
  for update;
  if not found then
    raise exception 'لا يوجد طلب نشط' using errcode = 'P0002';
  end if;
  if v_row.status not in ('accepted','active') or v_row.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  v_mode := coalesce(v_row.metadata->>'mode', 'snapshot');
  if v_mode in ('snapshot','location_video') and not exists (
    select 1 from public.employee_locations
    where live_request_id = p_request_id and employee_id = v_me
  ) then
    raise exception 'نقطة الموقع مطلوبة' using errcode = '22023';
  end if;
  if v_mode in ('video_5s','location_video') and not exists (
    select 1 from public.live_location_videos_meta
    where live_request_id = p_request_id
      and employee_id = v_me
      and status = 'ready'
      and duration_seconds between 4 and 7
      and size_bytes > 0
  ) then
    raise exception 'video_required' using errcode = '22023';
  end if;

  update public.live_location_requests
  set status = 'completed',
      expires_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'videoWaived', false,
        'completionMode', 'verified',
        'completedAt', now()
      )
  where id = p_request_id
  returning * into v_row;

  perform public.log_audit_event(
    'live_location_completed', 'security', 'info',
    'live_location_requests', p_request_id,
    'Ø¥ÙÙØ§Ù Ø·ÙØ¨ Ø§ÙÙÙÙØ¹ Ø¨Ø¹Ø¯ Ø§ÙØªØ­ÙÙ ÙÙ Ø§ÙÙØªØ·ÙØ¨Ø§Øª', null,
    jsonb_build_object('mode', v_mode, 'completionMode', 'verified')
  );
  return v_row;
end;
$function$;

-- get_attendance_today_overview(date)
CREATE OR REPLACE FUNCTION public.get_attendance_today_overview(p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
  v_is_friday boolean := (extract(isodow from p_date) = 5);
begin
  if not (public.current_is_full_access()
          or public.has_permission('attendance.record.read')
          or public.has_permission('people.employee.read')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- Ø¥Ø¬ÙØ§ÙÙ Ø§ÙÙÙØ¸ÙÙÙ Ø§ÙÙØ´Ø·ÙÙ (Ø¨Ø¯ÙÙ Ø§ÙØªÙÙÙØ°ÙÙÙ)
  select count(*) into v_total_active
  from public.employees e
  where e.status = 'active'
    and not exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and r.slug in ('executive','executive-director')
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    );

  -- Ø§ÙÙÙØ¸ÙÙÙ ÙÙ Ø¥Ø¬Ø§Ø²Ø© ÙØ¹ØªÙØ¯Ø©
  select count(distinct lr.employee_id) into v_on_leave
  from public.leave_requests lr
  join public.requests req on req.id = lr.request_id
  where req.status = 'approved'
    and p_date between lr.start_date and lr.end_date;

  -- Ø§ÙÙÙØ¸ÙÙÙ ÙÙ ØªÙÙÙÙØ§Øª ÙØ´Ø·Ø©
  select count(distinct wa.responsible_employee_id) into v_on_assignment
  from public.work_assignments wa
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date;

  -- Ø§ÙØ­Ø§Ø¶Ø±ÙÙ (Ø³Ø¬ÙÙÙØ§ Ø­Ø¶ÙØ± Ø§ÙÙÙÙ)
  select count(distinct employee_id) into v_present
  from public.attendance_events
  where event_at::date = p_date and event_type = 'CHECK_IN';

  -- Ø§ÙÙØªØ£Ø®Ø±ÙÙ
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_at::date = p_date
    and ae.event_type = 'CHECK_IN'
    and ae.late_minutes > 0;

  -- ÙÙÙ Ø§ÙØ¬ÙØ¹Ø©: Ø§ÙÙØªÙÙØ¹ = ÙÙ Ø¹ÙÙ ÙØ£ÙÙØ±ÙØ© ÙÙØ· (ÙØ§ ÙÙ Ø§ÙÙÙØ¸ÙÙÙ)
  if v_is_friday then
    v_expected := v_on_assignment;
  else
    v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);
  end if;

  v_not_checked_in := greatest(0, v_expected - v_present);
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', v_total_active,
    'expected', v_expected,
    'present', v_present,
    'late', v_late,
    'notCheckedIn', v_not_checked_in,
    'onLeave', v_on_leave,
    'onAssignment', v_on_assignment,
    'absent', v_absent,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now()
  );
end;
$function$;

-- tg_profiles_protect_sensitive()
CREATE OR REPLACE FUNCTION public.tg_profiles_protect_sensitive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_self_activation boolean;
begin
  -- Ø§ÙØ³ÙØ§ÙØ§Øª Ø§ÙÙÙØ«ÙÙØ© ØªÙØ± ÙØ¨Ø§Ø´Ø±Ø©. ÙØ§ ÙØ³ØªØ®Ø¯Ù current_user ÙÙØ§ ÙØ£ÙÙ Ø¯Ø§Ø®Ù Ø¯Ø§ÙØ©
  -- security definer ÙØ¹ÙØ¯ Ø¨Ø§Ø³Ù Ø§ÙÙØ§ÙÙ (postgres) Ø¯Ø§Ø¦ÙØ§Ù â Ø¨Ù ÙØ³ØªØ®Ø¯Ù auth.role()
  -- Ø§ÙÙØ³ØªØ®Ø±Ø¬Ø© ÙÙ JWT Ø§ÙØ·ÙØ¨ (ÙÙØ· ÙØ·Ø¨ÙÙ ÙÙ 0026/0033).
  if auth.role() = 'service_role'
     or public.current_is_full_access()
     or public.has_permission('profiles.manage') then
    return new;
  end if;

  -- Ø§ÙØ­ÙÙÙ Ø§ÙØ£ÙØ«Ø± Ø­Ø³Ø§Ø³ÙØ© ÙØ­Ø¸ÙØ±Ø© Ø¹ÙÙ Ø£Ù ÙØ³ØªØ®Ø¯Ù ØºÙØ± ÙØ®ÙÙÙ ÙÙÙØ§ ÙØ§Ù.
  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'غير مصرح بتغيير الدور الأساسي' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'غير مصرح بتغيير معرّف الموظف' using errcode = '42501';
  end if;

  -- Ø§ÙØªÙØ¹ÙÙ Ø§ÙØ°Ø§ØªÙ: Ø§ÙÙÙØ¸Ù ÙÙØ¹ÙÙ ÙÙÙÙ Ø¨ÙÙØ³Ù Ø¨Ø¹Ø¯ Ø£ÙÙ Ø¶Ø¨Ø· ÙÙÙØ© ÙØ±ÙØ±
  -- (activate_employee_after_first_login ÙÙ Ø§ÙÙÙØ¨/Ø§ÙÙÙØ¨Ø§ÙÙ) â Ø§ÙÙØ³Ø§Ø± Ø§ÙÙØ­ÙØ¯
  -- Ø§ÙÙØ³ÙÙØ­ ÙØºÙØ± Ø§ÙÙØ®ÙÙÙ ÙØªØºÙÙØ± status/temporary_password.
  v_self_activation :=
       new.id = auth.uid()
       and old.status in ('pending', 'invited', 'onboarding', 'draft')
       and new.status = 'active'
       and new.temporary_password = false;

  if new.status is distinct from old.status and not v_self_activation then
    raise exception 'غير مصرح لك بتغيير الحالة' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password and not v_self_activation then
    raise exception 'غير مصرح بتغيير كلمة المرور المؤقتة' using errcode = '42501';
  end if;

  return new;
end;
$function$;

-- create_team_task(uuid,text,text,text,date)
CREATE OR REPLACE FUNCTION public.create_team_task(p_employee_id uuid, p_title text, p_description text DEFAULT NULL::text, p_priority text DEFAULT 'medium'::text, p_due_date date DEFAULT NULL::date)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_task_id uuid;
begin
  if v_manager_id is null or p_employee_id is null then
    raise exception 'سياق الموظف مطلوب' using errcode = '42501';
  end if;
  if p_employee_id=v_manager_id then
    raise exception 'استخدم مسار المهام الشخصية لمهامك' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'عنوان المهمة مطلوب' using errcode = '22023';
  end if;
  if p_priority not in ('low','medium','high','urgent') then
    raise exception 'أولوية مهمة غير مدعومة' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'tasks.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=p_employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'نطاق إسناد المهام مرفوض' using errcode = '42501';
  end if;

  insert into public.tasks(
    title, description, assignee_employee_id, priority, due_date,
    status, created_by_employee_id, created_by
  ) values (
    trim(p_title), nullif(trim(coalesce(p_description,'')),''), p_employee_id,
    p_priority, p_due_date, 'pending', v_manager_id, auth.uid()
  ) returning id into v_task_id;

  return v_task_id;
end;
$function$;

-- admin_delete_device(uuid,text)
CREATE OR REPLACE FUNCTION public.admin_delete_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  -- ÙØ§ ÙÙØ³ÙØ­ Ø¨Ø­Ø°Ù Ø¬ÙØ§Ø² ÙØ´Ø· Ø£Ù ÙØ¹ÙÙ Ø£Ù ÙØ­Ø¸ÙØ± (ÙØ§Ø¨Ù ÙØ¥Ø¹Ø§Ø¯Ø© Ø§ÙØªÙØ¹ÙÙ)
  if v_device.status not in ('revoked', 'replaced', 'auto_revoked') then
    raise exception 'only terminated devices (revoked/replaced/auto_revoked) can be deleted (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- ØªØ³Ø¬ÙÙ Ø­Ø¯Ø« Ø£ÙÙÙ ÙØ¨Ù Ø§ÙØ­Ø°Ù
  perform public.log_security_event(
    'device.admin_deleted',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'deviceName', v_device.device_name,
      'platform', v_device.platform,
      'previousStatus', v_device.status,
      'reason', p_reason
    )
  );

  -- Ø­Ø°Ù Ø¨ÙØ§ÙØ§Øª Ø§Ø¹ØªÙØ§Ø¯ Ø§ÙØ¨ØµÙØ© Ø§ÙÙØ±ØªØ¨Ø·Ø© Ø¥Ù ÙØ§ÙØª ÙÙØªÙÙØ© ÙÙØ§ ØªØ±Ø¨Ø·ÙØ§ Ø£Ø¬ÙØ²Ø© Ø£Ø®Ø±Ù
  delete from public.passkey_credentials
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked'
    and not exists (
      select 1 from public.employee_devices ed
      where ed.credential_id = v_device.credential_id
        and ed.employee_id = v_device.employee_id
        and ed.id <> p_device_id
        and ed.status in ('pending', 'active', 'blocked')
    );

  -- Ø­Ø°Ù Ø§ÙØ¬ÙØ§Ø² ÙÙØ§Ø¦ÙØ§Ù
  delete from public.employee_devices
  where id = p_device_id;

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'deleted'
  );
end;
$function$;

-- rpc_assign_role(uuid,uuid,jsonb,timestamp with time zone,timestamp with time zone)
CREATE OR REPLACE FUNCTION public.rpc_assign_role(p_user_id uuid, p_role_id uuid, p_scope_override jsonb DEFAULT NULL::jsonb, p_effective_from timestamp with time zone DEFAULT now(), p_effective_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS user_roles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.user_roles; v_role public.roles;
begin
  -- ÙØ­Øµ Ø§ÙØªØ®ÙÙÙ Ø§ÙØ£Ø³Ø§Ø³Ù
  if not (public.current_is_full_access() or public.has_permission('access.role.assign')) then
    raise exception 'غير مصرح لك بإسناد الأدوار' using errcode = '42501';
  end if;

  select * into v_role from public.roles where id = p_role_id;
  if v_role is null then
    raise exception 'role not found' using errcode = '42501';
  end if;

  -- ÙÙØ­ full-access ÙØ­ØµÙØ± Ø¨Ùsuper-admin ÙÙØ·
  if v_role.is_full_access and not public.current_is_super_admin() then
    raise exception 'المدير الأعلى فقط يسند دور الوصول الكامل' using errcode = '42501';
  end if;

  -- ÙÙØ¹ ÙÙØ­ Ø§ÙÙÙØ³ Ø¯ÙØ±Ø§Ù Ø£Ø¹ÙÙ
  if p_user_id = auth.uid() and v_role.is_full_access then
    raise exception 'لا يمكنك منح نفسك الوصول الكامل' using errcode = '42501';
  end if;

  -- V23: ÙØ³ØªØ®Ø¯ÙÙ HR ÙØ­Ø¯ÙØ¯ÙÙ Ø¨Ø£Ø¯ÙØ§Ø± Ø§ÙÙÙØ¸Ù/Ø§ÙÙØ¯ÙØ±/Ø§ÙØªØ´ØºÙÙ ÙÙØ·
  -- Main Admin ÙØ­Ø¯Ù ÙÙÙØ­ Ø§ÙØ£Ø¯ÙØ§Ø± Ø§ÙØ¹ÙÙØ§ ÙØ¹Ø¶ÙÙØ© Ø§ÙÙØ¬ÙØ©
  if public.current_is_hr_only() then
    if v_role.slug = any(array[
      'admin','super-admin','super_admin','system-admin','technical-lead',
      'executive-director','executive','executive-secretary',
      'hr-manager','hr-specialist',
      'committee-member','committee-chair','committee-secretary'
    ]) or v_role.is_full_access or v_role.is_system then
      raise exception 'الموارد البشرية تسند أدوار الموظف/المدير/العمليات فقط'
        using errcode = '42501';
    end if;
  end if;

  insert into public.user_roles (user_id, role_id, scope_override, effective_from, effective_to, granted_by)
  values (p_user_id, p_role_id, p_scope_override, p_effective_from, p_effective_to, auth.uid())
  on conflict (user_id, role_id) do update
    set scope_override = excluded.scope_override,
        effective_from = excluded.effective_from,
        effective_to   = excluded.effective_to,
        granted_by     = auth.uid()
  returning * into v_row;

  -- V23: ØªØ¯ÙÙÙ ÙÙ Ø¹ÙÙÙØ© Ø¥Ø³ÙØ§Ø¯ Ø¯ÙØ±
  perform public.log_audit_event(
    'access.role.assigned',
    'access',
    'notice',
    'user_roles',
    p_role_id,
    'ØªÙ Ø¥Ø³ÙØ§Ø¯ Ø¯ÙØ± Â«' || coalesce(v_role.name_ar, v_role.slug) || 'Â»',
    'Role "' || v_role.slug || '" assigned',
    jsonb_build_object(
      'role_slug', v_role.slug,
      'role_id', p_role_id,
      'target_user_id', p_user_id,
      'is_capability', coalesce(v_role.is_capability, false)
    )
  );

  return v_row;
end;
$function$;

-- punch_attendance_local_biometric_v1(uuid,text,text,double precision,double precision,double precision,boolean)
CREATE OR REPLACE FUNCTION public.punch_attendance_local_biometric_v1(p_operation_id uuid, p_event_type text, p_installation_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_hash text;
  v_managed public.managed_devices;
  v_employee_device public.employee_devices;
  v_operation public.local_attendance_operations;
  v_event_id uuid;
  v_event public.attendance_events;
  v_result jsonb;
  v_error text;
  v_verification_method text;
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required','invalid_attendance_location'
  ];
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode='42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode='22023';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if length(trim(coalesce(p_installation_id,'')))<12 then
    raise exception 'invalid_installation_id' using errcode='22023';
  end if;
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode='42501';
  end if;

  v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

  -- 0226: Return structured JSON instead of RAISE for device-not-active.
  -- This lets Flutter's result-check path show a clear device-specific message.
  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'managed_device_not_active',
      'replayed', false
    );
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'employee_device_not_active',
      'replayed', false
    );
  end if;

  v_verification_method := case
    when v_managed.biometric_available then 'local_biometric'
    else 'device_lock'
  end;

  insert into public.local_attendance_operations(
    operation_id,user_id,employee_id,event_type,credential_id
  ) values (p_operation_id,auth.uid(),v_employee_id,p_event_type,v_hash)
  on conflict (operation_id) do nothing;
  select * into v_operation from public.local_attendance_operations
  where operation_id=p_operation_id for update;
  if v_operation.user_id<>auth.uid()
     or v_operation.employee_id<>v_employee_id
     or v_operation.event_type<>p_event_type
     or v_operation.credential_id<>v_hash then
    raise exception 'attendance_idempotency_conflict' using errcode='22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result,'{}'::jsonb)
      || jsonb_build_object('replayed',true);
  end if;

  begin
    v_event_id := public.record_attendance_local_biometric(
      v_employee_id,p_event_type,p_latitude,p_longitude,
      p_accuracy_meters,p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error=any(v_known_errors) then
      v_result := jsonb_build_object('ok',false,'error',v_error,'replayed',false);
      update public.local_attendance_operations
      set status='rejected',result=v_result,completed_at=now()
      where operation_id=p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  update public.employee_devices set last_used_at=now()
  where id=v_employee_device.id;
  update public.managed_devices set last_seen_at=now()
  where id=v_managed.id;
  select * into v_event from public.attendance_events where id=v_event_id;
  v_result := jsonb_build_object(
    'ok',true,'verified',true,
    'verificationMethod',v_verification_method,
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );
  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;
  return v_result;
end;
$function$;

-- get_mobile_org_chart()
CREATE OR REPLACE FUNCTION public.get_mobile_org_chart()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_result  jsonb;
begin
  if v_user_id is null then
    raise exception 'غير مصرح' using errcode = 'P0001';
  end if;

  with recursive dept_tree as (
    select d.id, d.name, d.parent_id, d.manager_id,
           0 as depth, array[d.id] as path
    from departments d
    where d.parent_id is null
    union all
    select c.id, c.name, c.parent_id, c.manager_id,
           t.depth + 1, t.path || c.id
    from departments c
    join dept_tree t on c.parent_id = t.id
    where not c.id = any(t.path)
  ),
  emp_data as (
    select
      e.id,
      e.full_name_ar,
      e.employee_code,
      coalesce(jt.name, jt.name_en, '') as job_title,
      e.photo_url,
      e.department_id,
      coalesce(d.name, '') as department_name,
      d.manager_id as dept_manager_id,
      e.is_active,
      e.status
    from employees e
    left join job_titles jt on jt.id = e.job_title_id
    left join departments d on d.id = e.department_id
    where e.is_active = true
      and e.is_deleted = false
      and e.status in ('active', 'probation_failed', 'onboarding')
  )
  select jsonb_build_object(
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', dt.id,
        'name', dt.name,
        'parentId', dt.parent_id,
        'managerId', dt.manager_id,
        'depth', dt.depth
      ) order by dt.path)
      from dept_tree dt
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id,
        'fullNameAr', ed.full_name_ar,
        'employeeCode', ed.employee_code,
        'jobTitle', ed.job_title,
        'photoUrl', ed.photo_url,
        'departmentId', ed.department_id,
        'departmentName', ed.department_name,
        'isDeptManager', ed.dept_manager_id = ed.id
      ) order by (ed.dept_manager_id = ed.id) desc, ed.full_name_ar)
      from emp_data ed
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- create_access_review_campaign(text,text,timestamp with time zone)
CREATE OR REPLACE FUNCTION public.create_access_review_campaign(p_name text, p_description text, p_due_at timestamp with time zone)
 RETURNS access_review_campaigns
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_campaign public.access_review_campaigns;
begin
  if not (public.current_is_full_access() or public.has_permission('access.review.manage')) then
    raise exception 'access review denied' using errcode='42501';
  end if;
  if p_due_at is null or p_due_at <= now() then raise exception 'تاريخ استحقاق مستقبلي مطلوب' using errcode='22023'; end if;
  insert into public.access_review_campaigns(name,description,status,starts_at,due_at,created_by)
  values (trim(p_name),p_description,'active',now(),p_due_at,auth.uid()) returning * into v_campaign;
  insert into public.access_review_items(campaign_id,user_role_id,user_id,role_id,reviewer_user_id,snapshot)
  select v_campaign.id,ur.id,ur.user_id,ur.role_id,auth.uid(),jsonb_build_object(
    'roleSlug',r.slug,'roleName',r.name_ar,'effectiveFrom',ur.effective_from,'effectiveTo',ur.effective_to,'scopeOverride',ur.scope_override
  )
  from public.user_roles ur join public.roles r on r.id=ur.role_id
  where ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now());
  perform public.log_audit_event('access.review.started','access','notice','access_review_campaigns',v_campaign.id,'Ø¨Ø¯Ø¡ ÙØ±Ø§Ø¬Ø¹Ø© ØµÙØ§Ø­ÙØ§Øª',p_description,jsonb_build_object('dueAt',p_due_at));
  return v_campaign;
end;
$function$;

-- upsert_my_push_token(text,text)
CREATE OR REPLACE FUNCTION public.upsert_my_push_token(p_fcm_token text, p_platform text DEFAULT 'android'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  declare
    v_user_id uuid := auth.uid();
    v_token text := trim(p_fcm_token);
    v_now timestamptz := now();
    v_recovered integer := 0;
  begin
    if v_user_id is null then
      raise exception 'غير مصرح' using errcode = '42501';
    end if;
    if length(v_token) < 16 then
      raise exception 'token_too_short' using errcode = '22023';
    end if;
    if p_platform not in ('android', 'ios', 'web') then
      raise exception 'invalid_platform' using errcode = '22023';
    end if;

    -- One physical FCM token must never remain active for two signed-in users.
    update public.push_subscriptions
    set is_active = false,
        updated_at = v_now
    where fcm_token = v_token
      and user_id <> v_user_id
      and is_active;

    insert into public.push_subscriptions(
      user_id,
      endpoint,
      p256dh_key,
      auth_key,
      fcm_token,
      platform,
      is_active,
      last_used_at,
      created_by
    ) values (
      v_user_id,
      'fcm://' || v_token,
      '-',
      '-',
      v_token,
      p_platform,
      true,
      v_now,
      v_user_id
    )
    on conflict (user_id, fcm_token) where fcm_token is not null
    do update set
      endpoint = excluded.endpoint,
      p256dh_key = excluded.p256dh_key,
      auth_key = excluded.auth_key,
      platform = excluded.platform,
      is_active = true,
      last_used_at = v_now,
      updated_at = v_now;

    -- A request may have been created before the first successful token upsert.
    -- Insert its missing push job, or retry a previously terminal token_missing
    -- job, while never redelivering a job already marked sent.
    --
    -- V25: ÙÙØ· Ø§ÙØ·ÙØ¨Ø§Øª Ø§ÙØªÙ ÙØ§ Ø²Ø§ÙØª 'pending' - ÙØ¨ÙÙ/Ø±ÙØ¶/Ø¥ÙÙØ§Ù Ø§ÙØ·ÙØ¨ ÙÙÙÙ
    -- Ø£Ù Ø¥Ø¹Ø§Ø¯Ø© Ø¥Ø±Ø³Ø§Ù ÙØ§Ø­ÙØ© (ÙØ§ÙØª 'accepted'/'active' ØªØ³Ø¨Ø¨ Ø§ÙØ±ÙÙÙ Ø§ÙÙØªÙØ±Ø±
    -- Ø¨Ø¹Ø¯ Ø£Ù Ø±Ø¯Ù Ø§ÙÙÙØ¸Ù Ø¨Ø§ÙÙØ¹Ù).
    insert into public.notification_jobs(
      notification_id,
      recipient_user_id,
      channel,
      status,
      available_at,
      attempts,
      idempotency_key
    )
    select
      n.id,
      n.recipient_user_id,
      'push',
      'queued',
      v_now,
      0,
      n.id::text || ':push'
    from public.notifications n
    join public.live_location_requests r
      on r.id = n.entity_id
    where n.recipient_user_id = v_user_id
      and n.entity_type = 'live_location_request'
      and r.status = 'pending'
      and (r.expires_at is null or r.expires_at > v_now)
    on conflict (idempotency_key)
    do update set
      status = 'queued',
      available_at = v_now,
      attempts = 0,
      last_error = null,
      locked_at = null,
      locked_by = null
    where public.notification_jobs.status in ('failed', 'cancelled');

    get diagnostics v_recovered = row_count;
    if v_recovered > 0 then
      perform public.nudge_notification_dispatcher();
    end if;
  end;
  $function$;

-- get_access_overview()
CREATE OR REPLACE FUNCTION public.get_access_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.audit.read'])) then
    raise exception 'وصول النظرة العامة مرفوض' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'roles', (select count(*) from public.roles),
    'permissions', (select count(*) from public.permissions),
    'activeAssignments', (select count(*) from public.user_roles where effective_from <= now() and (effective_to is null or effective_to > now())),
    'sensitivePermissions', (select count(*) from public.permissions where is_sensitive = true or risk_level in ('sensitive','critical')),
    'expiringAssignments', (select count(*) from public.user_roles where effective_to between now() and now() + interval '30 days'),
    'rolesList', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'isFullAccess', r.is_full_access,
        'permissionCount', (select count(*) from public.role_permissions rp where rp.role_id = r.id),
        'userCount', (select count(*) from public.user_roles ur where ur.role_id = r.id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now()))
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- create_work_assignment(text,text,timestamp with time zone,timestamp with time zone,uuid[],text,text,uuid,boolean,timestamp with time zone,jsonb)
CREATE OR REPLACE FUNCTION public.create_work_assignment(p_assignment_type text, p_title text, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_participant_ids uuid[], p_description text DEFAULT NULL::text, p_location text DEFAULT NULL::text, p_responsible_employee_id uuid DEFAULT NULL::uuid, p_needs_report boolean DEFAULT false, p_report_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_row public.work_assignments;
  v_emp uuid;
  v_can_manage boolean;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
begin
  if v_me is null then raise exception 'لا يوجد موظف مرتبط' using errcode = '42501'; end if;
  if p_assignment_type not in ('MISSION','CONVOY','FUNDRAISING') then
    raise exception 'نوع تكليف غير صالح' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'العنوان مطلوب' using errcode = '22023';
  end if;
  if p_start_at is null or p_end_at is null or p_end_at < p_start_at then
    raise exception 'فترة تكليف غير صالحة' using errcode = '22023';
  end if;
  if p_participant_ids is null or array_length(p_participant_ids,1) is null then
    raise exception 'مشارك واحد على الأقل مطلوب' using errcode = '22023';
  end if;
  if array_length(p_participant_ids,1) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;

  v_can_manage := public.can_manage_assignment_type_org_wide(p_assignment_type);

  foreach v_emp in array p_participant_ids loop
    if not (v_can_manage or public.can_access_employee(v_emp)) then
      raise exception 'cannot assign employee outside your team without permission: %', v_emp
        using errcode = '42501';
    end if;
  end loop;

  insert into public.work_assignments(
    assignment_type, subtype, title, description, status,
    created_by_employee_id, responsible_employee_id, start_at, end_at,
    is_full_day, location, transport_mode, instructions, project_id, campaign_name,
    target_amount, needs_report, report_due_at, metadata, created_by)
  values(
    p_assignment_type, nullif(v_payload->>'subtype',''), trim(p_title), p_description,
    'APPROVED',
    v_me, coalesce(p_responsible_employee_id, v_me), p_start_at, p_end_at,
    coalesce((v_payload->>'isFullDay')::boolean, true),
    p_location, nullif(v_payload->>'transportMode',''),
    nullif(v_payload->>'instructions',''),
    nullif(v_payload->>'projectId','')::uuid, nullif(v_payload->>'campaignName',''),
    nullif(v_payload->>'targetAmount','')::numeric,
    coalesce(p_needs_report,false), p_report_due_at, v_payload, auth.uid())
  returning * into v_row;

  foreach v_emp in array p_participant_ids loop
    insert into public.work_assignment_participants(
      assignment_id, employee_id, role_in_assignment, created_by)
    values(v_row.id, v_emp, nullif(v_payload->>'roleInAssignment',''), auth.uid())
    on conflict(assignment_id, employee_id) do nothing;

    perform public.notify_employee(
      v_emp, 'ØªÙÙÙÙ Ø¹ÙÙ Ø¬Ø¯ÙØ¯',
      format('%s: %s', case v_row.assignment_type
                         when 'MISSION' then 'ÙØ£ÙÙØ±ÙØ©'
                         when 'CONVOY' then 'ÙØ§ÙÙØ©'
                         else 'ÙØ§ÙØ¯Ù' end, v_row.title),
      'general', 'normal', 'work_assignments', v_row.id,
      jsonb_build_object('assignmentType', v_row.assignment_type,
                         'startAt', v_row.start_at, 'endAt', v_row.end_at));
  end loop;

  perform public.log_audit_event(
    'assignment.created', 'workflow', 'info', 'work_assignments', v_row.id,
    'Ø¥ÙØ´Ø§Ø¡ ØªÙÙÙÙ Ø¹ÙÙ', v_row.title,
    jsonb_build_object('type', v_row.assignment_type,
                       'participants', array_length(p_participant_ids,1)));
  return v_row;
end $function$;

-- acknowledge_announcement(uuid)
CREATE OR REPLACE FUNCTION public.acknowledge_announcement(p_announcement_id uuid)
 RETURNS announcement_acknowledgements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.announcement_acknowledgements;
begin
  if v_me is null then raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode='42501'; end if;
  if not exists(select 1 from public.announcements a where a.id=p_announcement_id and a.status='published') then
    raise exception 'announcement not available' using errcode='P0002';
  end if;
  insert into public.announcement_acknowledgements(announcement_id,employee_id,created_by)
  values(p_announcement_id,v_me,auth.uid())
  on conflict(announcement_id,employee_id) do update set acknowledged_at=excluded.acknowledged_at,updated_at=now()
  returning * into v_row;
  return v_row;
end;
$function$;

-- upsert_position_admin(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,boolean)
CREATE OR REPLACE FUNCTION public.upsert_position_admin(p_id uuid, p_department_id uuid, p_team_id uuid, p_job_title_id uuid, p_grade_id uuid, p_reports_to_id uuid, p_code text, p_name text, p_name_en text DEFAULT NULL::text, p_headcount integer DEFAULT 1, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.position.manage')) then
    raise exception 'إدارة المناصب مرفوضة' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'القسم وكود واسم المنصب مطلوبة' using errcode = '22023';
  end if;
  if coalesce(p_headcount, 0) < 0 then raise exception 'لا يمكن أن يكون العدد سالباً' using errcode = '22023'; end if;
  if p_id is not null and p_reports_to_id = p_id then raise exception 'لا يمكن أن يتبع المنصب نفسه' using errcode = '22023'; end if;

  if p_id is not null and p_reports_to_id is not null then
    with recursive descendants as (
      select p.id from public.positions p where p.reports_to_position_id = p_id
      union all
      select p.id from public.positions p join descendants x on p.reports_to_position_id = x.id
    )
    select exists(select 1 from descendants where id = p_reports_to_id) into v_cycle;
    if v_cycle then raise exception 'تم رصد دورة في تسلسل المناصب' using errcode = '22023'; end if;
  end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams t where t.id = p_team_id and t.department_id = p_department_id
  ) then
    raise exception 'الفريق لا يتبع القسم المختار' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.positions(
      department_id, team_id, job_title_id, job_grade_id, reports_to_position_id,
      code, name, name_en, headcount, is_active, created_by
    ) values (
      p_department_id, p_team_id, p_job_title_id, p_grade_id, p_reports_to_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_headcount, 1), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.positions set
      department_id = p_department_id,
      team_id = p_team_id,
      job_title_id = p_job_title_id,
      job_grade_id = p_grade_id,
      reports_to_position_id = p_reports_to_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      headcount = coalesce(p_headcount, headcount),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'المنصب غير موجود' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$function$;

-- link_assignment_to_initiatives(uuid,uuid,numeric,text)
CREATE OR REPLACE FUNCTION public.link_assignment_to_initiatives(p_assignment_id uuid, p_evaluation_id uuid, p_points numeric DEFAULT 5, p_note text DEFAULT NULL::text)
 RETURNS kpi_assignment_contributions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_asg public.work_assignments;
  v_emp uuid;
  v_row public.kpi_assignment_contributions;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['performance.kpi.hr_assess','performance.kpi.manager_assess','performance.kpi.hr_review'])) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if p_points is null or p_points < 0 or p_points > 5 then
    raise exception 'INITIATIVES_POINTS_OUT_OF_RANGE (0..5)' using errcode='22023';
  end if;

  select * into v_asg from public.work_assignments where id = p_assignment_id;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode='P0002'; end if;
  if v_asg.assignment_type not in ('CONVOY','FUNDRAISING') then
    raise exception 'only convoy/fundraising contribute to initiatives' using errcode='22023';
  end if;

  select employee_id into v_emp from public.kpi_evaluations where id = p_evaluation_id;
  if v_emp is null then raise exception 'evaluation not found' using errcode='P0002'; end if;

  insert into public.kpi_assignment_contributions(
    assignment_id, evaluation_id, employee_id, contribution_type, points, note, created_by)
  values(p_assignment_id, p_evaluation_id, v_emp, 'INITIATIVES', p_points, p_note, auth.uid())
  on conflict(assignment_id, evaluation_id, contribution_type) do nothing
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ASSIGNMENT_ALREADY_COUNTED (ÙÙØ¹ Ø§ÙØ§Ø­ØªØ³Ø§Ø¨ Ø§ÙÙØ²Ø¯ÙØ¬)' using errcode='23505';
  end if;

  perform public.log_audit_event(
    'kpi.assignment.initiatives.linked', 'workflow', 'info',
    'kpi_evaluations', p_evaluation_id, 'Ø±Ø¨Ø· ØªÙÙÙÙ Ø¨ÙØ¹ÙØ§Ø± Ø§ÙÙØ¨Ø§Ø¯Ø±Ø§Øª', p_note,
    jsonb_build_object('assignmentId', p_assignment_id, 'points', p_points,
                       'assignmentType', v_asg.assignment_type));
  return v_row;
end $function$;

-- get_announcement_acknowledgers(uuid)
CREATE OR REPLACE FUNCTION public.get_announcement_acknowledgers(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_ann_exists boolean;
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- ÙØ§ ÙÙØ´Ù ÙØ§Ø¦ÙØ© Ø§ÙÙÙÙØ±ÙÙÙ Ø¥ÙØ§ ÙØ¥Ø¹ÙØ§Ù ÙÙØ¬ÙØ¯ ÙØ¹ÙØ§Ù
  select exists(
    select 1 from public.announcements a
    where a.id = p_announcement_id and a.status = 'published'
  ) into v_ann_exists;

  if not v_ann_exists then
    raise exception 'announcement not available' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'employeeId',    e.id,
      'employeeCode',  e.employee_code,
      'fullName',      e.full_name_ar,
      'photoUrl',      e.photo_url,
      'acknowledgedAt',ack.acknowledged_at
    )
    order by ack.acknowledged_at asc
  ), '[]'::jsonb)
  into v_result
  from public.announcement_acknowledgements ack
  join public.employees e on e.id = ack.employee_id
  where ack.announcement_id = p_announcement_id
    and (public.current_is_full_access()
         or public.can_access_employee(e.id, 'people.employee.read'));

  return v_result;
end;
$function$;

-- get_mobile_executive_command_center()
CREATE OR REPLACE FUNCTION public.get_mobile_executive_command_center()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_allowed boolean;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'comms.decision.manage',
    'reports.executive.read',
    'reports.schedule.manage',
    'live_location.request',
    'risks.read',
    'incidents.read'
  ]);
  if not v_allowed then
    raise exception 'وصول مركز القيادة التنفيذي مرفوض' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', coalesce(s.name_ar, r.report_type),
        'reportType', r.report_type,
        'scheduleKind', s.schedule_kind,
        'status', r.status,
        'periodStart', r.period_start,
        'periodEnd', r.period_end,
        'storagePath', r.result_storage_path,
        'summary', r.result_summary,
        'attempts', r.attempts,
        'createdAt', r.created_at,
        'completedAt', r.completed_at,
        'errorDetail', r.error_detail
      ) order by r.created_at desc)
      from (
        select * from public.report_runs order by created_at desc limit 60
      ) r
      left join public.scheduled_reports s on s.id = r.scheduled_report_id
    ), '[]'::jsonb),
    'reportSchedules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name_ar,
        'reportType', s.report_type,
        'scheduleKind', s.schedule_kind,
        'active', s.active,
        'nextRunAt', s.next_run_at,
        'lastRunAt', s.last_run_at
      ) order by s.active desc, s.next_run_at nulls last)
      from public.scheduled_reports s
    ), '[]'::jsonb),
    'executionItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'decisionId', x.decision_id,
        'decisionTitle', x.decision_title,
        'title', x.title,
        'ownerName', x.owner_name,
        'dueAt', x.due_at,
        'status', x.status,
        'progressPercent', x.progress_percent,
        'blocker', x.blocker,
        'updatedAt', x.updated_at
      ) order by x.is_overdue desc, x.due_at nulls last, x.updated_at desc nulls last)
      from (
        select i.*, d.title decision_title, e.full_name_ar owner_name,
          (i.due_at is not null and i.due_at < now() and i.status not in ('completed','cancelled')) is_overdue
        from public.decision_execution_items i
        join public.administrative_decisions d on d.id = i.decision_id
        left join public.employees e on e.id = i.owner_employee_id
        where i.status <> 'cancelled'
        order by is_overdue desc, i.due_at nulls last
        limit 80
      ) x
    ), '[]'::jsonb),
    'polls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'decisionId', p.decision_id,
        'decisionTitle', d.title,
        'question', p.question,
        'pollType', p.poll_type,
        'status', p.status,
        'isAnonymous', p.is_anonymous,
        'opensAt', p.opens_at,
        'closesAt', p.closes_at,
        'quorumPercent', p.quorum_percent,
        'approvalThresholdPercent', p.approval_threshold_percent,
        'eligibleCount', (select count(*) from public.decision_poll_eligibility pe where pe.poll_id = p.id),
        'voteCount', (select count(*) from public.decision_poll_votes pv where pv.poll_id = p.id),
        'canVote', exists(select 1 from public.decision_poll_eligibility pe where pe.poll_id = p.id and pe.employee_id = v_employee_id),
        'myOptionIds', coalesce((select to_jsonb(pv.option_ids) from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id), '[]'::jsonb),
        'myRating', (select pv.rating from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id),
        'options', coalesce((
          select jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label) order by o.sort_order, o.label)
          from public.decision_poll_options o where o.poll_id = p.id
        ), '[]'::jsonb)
      ) order by p.status = 'open' desc, p.closes_at)
      from public.decision_polls p
      left join public.administrative_decisions d on d.id = p.decision_id
      where p.status in ('open','closed','certified')
        and (
          public.current_is_full_access()
          or public.has_permission('comms.decision.manage')
          or exists (
            select 1 from public.decision_poll_eligibility pe
            where pe.poll_id = p.id and pe.employee_id = v_employee_id
          )
        )
    ), '[]'::jsonb),
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'likelihood', x.likelihood,
        'impact', x.impact,
        'severity', x.severity,
        'status', x.status,
        'ownerName', x.owner_name,
        'updatedAt', x.updated_at,
        'createdAt', x.created_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select r.*, e.full_name_ar owner_name
        from public.risks r
        left join public.employees e on e.id = r.owner_employee_id
        where r.status in ('open','mitigating','accepted')
        order by r.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'incidents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'severity', x.severity,
        'status', x.status,
        'reporterName', x.reporter_name,
        'createdAt', x.created_at,
        'updatedAt', x.updated_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select i.*, e.full_name_ar reporter_name
        from public.incidents i
        left join public.employees e on e.id = i.reported_by
        where i.status in ('open','investigating')
        order by i.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'scheduledAt', x.scheduled_at,
        'locationOrLink', x.location_or_link,
        'organizerName', x.organizer_name,
        'status', x.status
      ) order by x.scheduled_at)
      from (
        select m.*, e.full_name_ar organizer_name
        from public.meetings m
        left join public.employees e on e.id = m.organizer_employee_id
        where m.status = 'scheduled' and m.scheduled_at >= now() - interval '2 hours'
        order by m.scheduled_at
        limit 40
      ) x
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$function$;

-- reassign_request(uuid,uuid,text)
CREATE OR REPLACE FUNCTION public.reassign_request(p_request_id uuid, p_new_manager_id uuid, p_reason text)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_req public.requests; v_old uuid;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['requests.request.delegate','requests.request.override'])) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;

  select * into v_req from public.requests where id = p_request_id for update;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002'; end if;
  if v_req.status <> 'pending' then
    raise exception 'الطلبات قيد الانتظار فقط تُعاد إسنادها' using errcode = '22023';
  end if;
  if p_new_manager_id = v_req.employee_id then
    raise exception 'لا يمكن تعيين صاحب الطلب معتمداً له' using errcode = '42501';
  end if;
  v_old := v_req.manager_employee_id;

  update public.requests
    set manager_employee_id = p_new_manager_id, updated_at = now(),
        payload = payload || jsonb_build_object('reassignment',
          jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id, 'reason', p_reason))
    where id = p_request_id returning * into v_req;

  update public.request_steps
    set assignee_employee_id = p_new_manager_id, updated_at = now()
    where request_id = p_request_id and status in ('active','pending','escalated');

  insert into public.request_actions(
    request_id, actor_employee_id, action, comment, metadata)
  values(p_request_id, public.current_employee_id(), 'reassign', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));

  perform public.notify_employee(p_new_manager_id, 'Ø£ÙØ³ÙØ¯ Ø¥ÙÙÙ Ø·ÙØ¨ ÙÙÙØ±Ø§Ø±',
    format('ØªÙ ÙÙÙ Ø§ÙØ·ÙØ¨ #%s Ø¥ÙÙÙ.', p_request_id), 'request', 'high', 'requests', p_request_id);

  perform public.log_audit_event('request.reassigned', 'workflow', 'warning',
    'requests', p_request_id, 'ÙÙÙ Ø·ÙØ¨ ÙÙ ÙØ¯ÙØ± Ø¥ÙÙ Ø¢Ø®Ø±', p_reason,
    jsonb_build_object('previousManagerId', v_old, 'newManagerId', p_new_manager_id));
  return v_req;
end $function$;

-- get_mobile_daily_reports(uuid,integer)
CREATE OR REPLACE FUNCTION public.get_mobile_daily_reports(p_employee_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_target uuid := coalesce(p_employee_id, public.current_employee_id());
  v_result jsonb;
begin
  if v_target is null or not public.can_access_employee(v_target, 'reports.read') then
    raise exception 'نطاق التقارير مرفوض' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', dr.employee_id,
    'employeeName', e.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewerName', reviewer.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where employee_id = v_target
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.employees reviewer on reviewer.id = dr.reviewed_by;

  return v_result;
end;
$function$;

-- get_mobile_request_detail(uuid)
CREATE OR REPLACE FUNCTION public.get_mobile_request_detail(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_request public.requests; v_employee public.employees;
  v_can_decide boolean:=false; v_can_cancel boolean:=false; v_can_resubmit boolean:=false;
  v_steps jsonb:='[]'::jsonb; v_attachments jsonb:='[]'::jsonb;
  v_decision_actor text; v_decision_mode text; v_decision_on_behalf boolean:=false;
  v_execution jsonb;
begin
  select * into v_request from public.requests where id=p_request_id;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;
  if not(
    v_request.employee_id=public.current_employee_id()
    or public.current_is_full_access()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.can_access_employee(v_request.employee_id,'requests.request.read')
    or v_request.manager_employee_id=public.current_employee_id()
  ) then raise exception 'وصول الطلب مرفوض' using errcode='42501'; end if;

  select * into v_employee from public.employees where id=v_request.employee_id;
  v_can_cancel:=v_request.status='pending' and v_request.employee_id=public.current_employee_id();
  v_can_decide:=v_request.status='pending' and v_request.employee_id<>public.current_employee_id() and (
    public.current_is_full_access()
    or v_request.manager_employee_id=public.current_employee_id()
    or public.can_access_employee(v_request.employee_id,'requests.request.approve')
    or public.has_permission('requests.request.approve')
  );
  -- 0451: Ø²Ø± Ø§ÙØªØ¹Ø¯ÙÙ ÙØ¥Ø¹Ø§Ø¯Ø© Ø§ÙØ±ÙØ¹ â Ø§ÙÙØ§ÙÙ ÙØ­Ø¯Ù ÙØ¹ÙÙ Ø§ÙØ£ÙÙØ§Ø¹ Ø§ÙÙØ§Ø¨ÙØ© ÙØ¥Ø¹Ø§Ø¯Ø© Ø§ÙØ±ÙØ¹
  v_can_resubmit:=v_request.status in ('rejected','returned')
    and v_request.employee_id=public.current_employee_id()
    and v_request.request_type in ('leave','mission','convoy','fundraising','late_permit','early_permit');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'order',s.step_order,'name',s.name_ar,'status',s.status,
    'decision',case when s.status in ('approved','rejected') then s.status else null end,
    'comment',s.comment,'decidedAt',s.acted_at,'dueAt',s.due_at,
    'actorName',actor.full_name_ar
  ) order by s.step_order),'[]'::jsonb)
  into v_steps from public.request_steps s
  left join public.employees actor on actor.id=s.acted_by
  where s.request_id=p_request_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'path',a.storage_path,'mimeType',a.mime,'sizeBytes',a.size_bytes
  ) order by a.created_at),'[]'::jsonb)
  into v_attachments from public.attachments a
  where a.entity_type='request' and a.entity_id=p_request_id;

  select e.full_name_ar,a.metadata->>'decisionMode',coalesce((a.metadata->>'onBehalfOfExecutive')::boolean,false)
  into v_decision_actor,v_decision_mode,v_decision_on_behalf
  from public.request_actions a left join public.employees e on e.id=a.actor_employee_id
  where a.request_id=p_request_id and a.action in ('approve','reject')
  order by a.created_at desc limit 1;

  -- 0318: Ø³Ø¬Ù ØªÙÙÙØ° Ø§ÙÙØ£ÙÙØ±ÙØ© (Ø¥Ù ÙÙØ¬Ø¯) â 0442: ÙØ´ÙÙ Ø§ÙÙØ§ÙØ¯Ù
  if v_request.request_type in ('mission','convoy','fundraising') then
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
    'id',v_request.id,'requestNumber',v_request.request_number,'requestType',v_request.request_type,
    'employeeId',v_request.employee_id,'employeeName',v_employee.full_name_ar,'employeeCode',v_employee.employee_code,
    'title',v_request.title,'reason',v_request.reason,'status',v_request.status,
    'workflowStatus',v_request.workflow_status,'payload',coalesce(v_request.payload,'{}'::jsonb),
    'currentStepOrder',v_request.current_step_order,'decisionDueAt',v_request.decision_due_at,
    'createdAt',v_request.created_at,'updatedAt',v_request.updated_at,
    'canDecide',v_can_decide,'canCancel',v_can_cancel,'canResubmit',v_can_resubmit,'steps',v_steps,
    'attachments',v_attachments,'decisionContext',public.get_request_decision_context(p_request_id),
    'decisionActorName',v_decision_actor,'decisionMode',v_decision_mode,
    'decisionOnBehalfOfExecutive',v_decision_on_behalf,
    'missionExecution',v_execution
  );
end $function$;

-- get_dashboard_overview(text)
CREATE OR REPLACE FUNCTION public.get_dashboard_overview(p_workspace text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if p_workspace not in ('hr','main_admin') then
    raise exception 'مساحة عمل غير صالحة' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'employees', (select count(*) from public.employees),
    'activeEmployees', (select count(*) from public.employees where status = 'active'),
    'pendingRequests', (select count(*) from public.requests where status = 'pending'),
    'attendancePendingReview', (select count(*) from public.attendance_events where requires_review = true),
    'pendingKpi', (select count(*) from public.kpi_evaluations where current_stage <> 'finalized'),
    'openRequisitions', (select count(*) from public.job_requisitions where status in ('pending','approved','posted')),
    'urgentActions', (
      select count(*) from public.requests
      where status = 'pending' and decision_due_at is not null and decision_due_at < now() + interval '4 hours'
    ),
    'publishedDecisions', (select count(*) from public.administrative_decisions where status = 'published'),
    'unresolvedErrors', case when p_workspace = 'main_admin'
      then (select count(*) from public.app_error_events where resolved = false)
      else 0 end,
    'lastUpdatedAt', now()
  );
end;
$function$;

-- rpc_set_role_permissions(uuid,jsonb)
CREATE OR REPLACE FUNCTION public.rpc_set_role_permissions(p_role_id uuid, p_items jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_role public.roles; v_count int := 0; v_item jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('access.role.update')) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_items,'[]'::jsonb)) > 500 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  select * into v_role from public.roles where id = p_role_id;
  if v_role.is_system and not public.current_is_super_admin() then
    raise exception 'system roles are protected' using errcode = '42501';
  end if;
  delete from public.role_permissions where role_id = p_role_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    insert into public.role_permissions (role_id, permission_id, scope, requires_mfa, requires_reason)
    values (p_role_id,
            (v_item->>'permission_id')::uuid,
            coalesce(v_item->>'scope','self'),
            coalesce((v_item->>'requires_mfa')::boolean,false),
            coalesce((v_item->>'requires_reason')::boolean,false));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

-- record_announcement_view(uuid)
CREATE OR REPLACE FUNCTION public.record_announcement_view(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.announcements a
    where a.id = p_announcement_id
      and a.status = 'published'
      and (a.expires_at is null or a.expires_at > now())
  ) then
    raise exception 'announcement not found or not visible' using errcode = 'P0002';
  end if;

  insert into public.announcement_views(
    announcement_id, employee_id, first_viewed_at, last_viewed_at, view_count, created_by
  ) values (
    p_announcement_id, v_me, now(), now(), 1, auth.uid()
  )
  on conflict (announcement_id, employee_id) do update
    set last_viewed_at = now(),
        view_count = public.announcement_views.view_count + 1;

  select jsonb_build_object(
    'viewCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'reactionSummary', coalesce((
      select jsonb_object_agg(x.reaction_type, x.total)
      from (
        select r.reaction_type, count(*)::integer as total
        from public.announcement_reactions r
        where r.announcement_id = p_announcement_id
        group by r.reaction_type
      ) x
    ), '{}'::jsonb),
    'myReaction', (
      select r.reaction_type from public.announcement_reactions r
      where r.announcement_id = p_announcement_id and r.employee_id = v_me
    )
  ) into v_result;

  return v_result;
end;
$function$;

-- update_release_policy(text,text,text,integer,text,integer,boolean,boolean,text,text,text,integer,text)
CREATE OR REPLACE FUNCTION public.update_release_policy(p_platform text, p_environment text, p_latest_version text, p_latest_build integer, p_min_supported_version text, p_min_supported_build integer, p_force_update boolean, p_maintenance_enabled boolean, p_maintenance_message_ar text, p_update_message_ar text, p_store_url text, p_rollout_percent integer DEFAULT 100, p_reason text DEFAULT NULL::text)
 RETURNS app_release_policies
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.app_release_policies;
begin
  if not (public.current_is_full_access() or public.has_permission('system.release.manage')) then
    raise exception 'سياسة الإصدار مرفوضة' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,''))) < 10 then raise exception 'يرجى إدخال السبب' using errcode='22023'; end if;
  if p_latest_build < p_min_supported_build then raise exception 'latest build must be >= minimum build' using errcode='22023'; end if;
  insert into public.app_release_policies(
    platform,environment,latest_version,latest_build,min_supported_version,min_supported_build,
    force_update,maintenance_enabled,maintenance_message_ar,update_message_ar,store_url,
    rollout_percent,created_by,updated_by
  ) values (
    p_platform,p_environment,p_latest_version,p_latest_build,p_min_supported_version,p_min_supported_build,
    coalesce(p_force_update,false),coalesce(p_maintenance_enabled,false),p_maintenance_message_ar,
    p_update_message_ar,p_store_url,greatest(0,least(coalesce(p_rollout_percent,100),100)),auth.uid(),auth.uid()
  )
  on conflict (platform,environment) do update set
    latest_version=excluded.latest_version,latest_build=excluded.latest_build,
    min_supported_version=excluded.min_supported_version,min_supported_build=excluded.min_supported_build,
    force_update=excluded.force_update,maintenance_enabled=excluded.maintenance_enabled,
    maintenance_message_ar=excluded.maintenance_message_ar,update_message_ar=excluded.update_message_ar,
    store_url=excluded.store_url,rollout_percent=excluded.rollout_percent,updated_by=auth.uid(),updated_at=now()
  returning * into v_row;
  perform public.log_audit_event('release.policy.updated','system','warning','app_release_policies',v_row.id,
    'ØªØ­Ø¯ÙØ« Ø³ÙØ§Ø³Ø© Ø¥ØµØ¯Ø§Ø±',p_reason,jsonb_build_object('platform',p_platform,'environment',p_environment,'latestBuild',p_latest_build,'minimumBuild',p_min_supported_build,'maintenance',p_maintenance_enabled));
  return v_row;
end;
$function$;

-- upsert_my_daily_report(date,text,text,text)
CREATE OR REPLACE FUNCTION public.upsert_my_daily_report(p_report_date date, p_achievements text, p_blockers text DEFAULT NULL::text, p_tomorrow_plan text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_employee_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_report_date > (now() at time zone 'Africa/Cairo')::date then
    raise exception 'التقرير اليومي المستقبلي غير مسموح' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_achievements, ''))) < 3 then
    raise exception 'الإنجازات مطلوبة' using errcode = '22023';
  end if;

  select id into v_id
  from public.daily_reports
  where employee_id = v_employee_id and report_date = p_report_date
  order by created_at desc limit 1;

  if v_id is null then
    insert into public.daily_reports (
      employee_id, report_date, achievements, blockers, tomorrow_plan, created_by
    ) values (
      v_employee_id, p_report_date, trim(p_achievements), nullif(trim(coalesce(p_blockers,'')),''),
      nullif(trim(coalesce(p_tomorrow_plan,'')),''), auth.uid()
    ) returning id into v_id;
  else
    update public.daily_reports
    set achievements = trim(p_achievements),
        blockers = nullif(trim(coalesce(p_blockers,'')),''),
        tomorrow_plan = nullif(trim(coalesce(p_tomorrow_plan,'')),''),
        updated_at = now()
    where id = v_id and reviewed_by is null;

    if not found then
      raise exception 'التقرير المُراجَع لا يُعدَّل' using errcode = '42501';
    end if;
  end if;

  return v_id;
end;
$function$;

-- cancel_work_assignment(uuid,text)
CREATE OR REPLACE FUNCTION public.cancel_work_assignment(p_assignment_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS work_assignments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_me uuid := public.current_employee_id(); v_row public.work_assignments;
begin
  select * into v_row from public.work_assignments where id = p_assignment_id for update;
  if not found then raise exception 'لم يتم العثور على التكليف' using errcode = 'P0002'; end if;
  if not (public.can_manage_assignment_type(v_row.assignment_type)
          or v_row.created_by_employee_id = v_me) then
    raise exception 'غير مصرح لك بإلغاء هذا التكليف' using errcode = '42501';
  end if;
  if v_row.status in ('COMPLETED','CANCELLED') then
    raise exception 'assignment already closed (%)', v_row.status using errcode = '22023';
  end if;
  update public.work_assignments
    set status = 'CANCELLED', decision_comment = p_reason, updated_at = now()
    where id = p_assignment_id returning * into v_row;

  perform public.log_audit_event(
    'assignment.cancelled', 'workflow', 'warning', 'work_assignments', p_assignment_id,
    'Ø¥ÙØºØ§Ø¡ ØªÙÙÙÙ Ø¹ÙÙ', p_reason, jsonb_build_object('type', v_row.assignment_type));
  return v_row;
end $function$;

-- get_live_location_response(uuid)
CREATE OR REPLACE FUNCTION public.get_live_location_response(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_req      public.live_location_requests;
  v_emp      public.employees;
  v_result   jsonb;
  v_has_video boolean;
begin
  select * into v_req from public.live_location_requests where id=p_request_id;
  if not found then raise exception 'لم يتم العثور على الطلب' using errcode='P0002'; end if;

  -- Ø§ÙØµÙØ§Ø­ÙØ©: ØµØ§Ø­Ø¨ Ø§ÙØ·ÙØ¨ (Ø§ÙÙÙØ¸Ù) Ø£Ù ÙÙ ÙÙÙÙ view_response Ø¹ÙÙÙ Ø£Ù full-access.
  if not (
    v_req.employee_id = public.current_employee_id()
    or v_req.requested_by = public.current_employee_id()
    or public.can_access_employee(v_req.employee_id,'live_location.view_response')
  ) then
    raise exception 'غير مسموح لك بعرض هذه الاستجابة' using errcode='42501';
  end if;

  select * into v_emp from public.employees where id=v_req.employee_id;

  select exists(select 1 from public.live_location_videos_meta m where m.live_request_id=p_request_id and m.status<>'deleted')
    into v_has_video;

  v_result := jsonb_build_object(
    'request', jsonb_build_object(
      'id',v_req.id,'status',
        case when v_req.status in ('pending','accepted','active') and v_req.expires_at<now() then 'expired' else v_req.status end,
      'mode',coalesce(v_req.metadata->>'mode','snapshot'),
      'reason',v_req.reason,'purpose',v_req.purpose,
      'requestedAt',v_req.requested_at,'respondedAt',v_req.responded_at,
      'startsAt',v_req.starts_at,'expiresAt',v_req.expires_at,
      'durationMinutes',v_req.duration_minutes,
      'needsVideo',coalesce((v_req.metadata->>'needsVideo')::boolean,false),
      'needsPoint',coalesce((v_req.metadata->>'needsPoint')::boolean,true)
    ),
    'employee', jsonb_build_object(
      'id',v_emp.id,'name',v_emp.full_name_ar,'employeeCode',v_emp.employee_code,
      'jobTitle',(select name from public.job_titles where id=v_emp.job_title_id),
      'department',(select name from public.departments where id=v_emp.department_id)
    ),
    'requesterName',(select full_name_ar from public.employees where id=v_req.requested_by),
    'points', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',l.id,'latitude',l.latitude,'longitude',l.longitude,'accuracy',l.accuracy,
        'altitude',l.altitude,'speed',l.speed,'heading',l.heading,'isMock',l.is_mock,
        'source',l.source,'addressAr',l.address_ar,'recordedAt',l.recorded_at,'createdAt',l.created_at
      ) order by l.recorded_at)
      from public.employee_locations l where l.live_request_id=p_request_id
    ),'[]'::jsonb),
    'video', (
      select jsonb_build_object(
        'id',m.id,'durationSeconds',m.duration_seconds,'sizeBytes',m.size_bytes,'mimeType',m.mime_type,
        'capturedLat',m.captured_lat,'capturedLng',m.captured_lng,'capturedAccuracy',m.captured_accuracy,
        'capturedAt',m.captured_at,'status',m.status,
        'retentionDeleteAfter',m.retention_delete_after,'legalHoldUntil',m.legal_hold_until
      )
      from public.live_location_videos_meta m
      where m.live_request_id=p_request_id and m.status<>'deleted'
      order by m.created_at desc limit 1
    )
  );

  perform public.log_audit_event('live_location.response_viewed','security','info','live_location_requests',p_request_id,'Ø§Ø·ÙÙØ§Ø¹ Ø¹ÙÙ ÙØªÙØ¬Ø© Ø·ÙØ¨ Ø§ÙÙÙÙØ¹',null,jsonb_build_object('hasVideo',v_has_video));
  if v_has_video then
    insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action)
    select m.id, auth.uid(), public.current_employee_id(), 'view'
    from public.live_location_videos_meta m
    where m.live_request_id=p_request_id and m.status<>'deleted'
    order by m.created_at desc limit 1;
  end if;

  return v_result;
end;
$function$;

-- acknowledge_decision(uuid,boolean)
CREATE OR REPLACE FUNCTION public.acknowledge_decision(p_decision_id uuid, p_acknowledge boolean DEFAULT true)
 RETURNS decision_reads
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me   uuid := public.current_employee_id();
  v_row  public.decision_reads;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- ÙØ¬Ø¨ Ø£Ù ÙÙÙÙ Ø§ÙÙÙØ¸Ù ÙØ³ØªÙØ¯ÙØ§Ù Ø¨Ø§ÙÙØ±Ø§Ø± (target-scoped)
  if not exists (
    select 1 from public.decision_recipients dr
    where dr.decision_id = p_decision_id and dr.employee_id = v_me
  ) then
    raise exception 'القرار ليس موجهاً لهذا الموظف' using errcode = '42501';
  end if;

  insert into public.decision_reads (
    decision_id, employee_id, read_at, acknowledged, acknowledged_at, created_by
  ) values (
    p_decision_id, v_me, now(), coalesce(p_acknowledge, false),
    case when p_acknowledge then now() else null end, auth.uid()
  )
  on conflict (decision_id, employee_id) do update
    set acknowledged    = greatest(public.decision_reads.acknowledged::int, excluded.acknowledged::int)::boolean,
        acknowledged_at = coalesce(public.decision_reads.acknowledged_at, excluded.acknowledged_at),
        updated_at      = now()
  returning * into v_row;

  return v_row;
end;
$function$;

-- set_employee_attendance_device_status(uuid,text,text)
CREATE OR REPLACE FUNCTION public.set_employee_attendance_device_status(p_device_id uuid, p_status text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('access.account.manage_devices')
  ) then
    raise exception 'صلاحية إدارة الأجهزة مطلوبة' using errcode = '42501';
  end if;
  if p_status not in ('pending','active','blocked','revoked','replaced') then
    raise exception 'حالة جهاز غير صالحة' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'سبب حالة الجهاز مطلوب' using errcode = '22023';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;
  if not found then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  update public.employee_devices
  set status = p_status,
      revoked_at = case
        when p_status in ('revoked','replaced') then coalesce(revoked_at, now())
        else null
      end,
      metadata = metadata || jsonb_build_object(
        'lastStatusReason', trim(p_reason),
        'lastStatusActor', auth.uid(),
        'lastStatusAt', now()
      )
  where id = p_device_id
  returning * into v_device;

  if p_status = 'active' then
    update public.passkey_credentials
    set status = 'active', trusted = true, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  elsif p_status in ('revoked','replaced') then
    update public.passkey_credentials
    set status = 'revoked', trusted = false, updated_at = now()
    where employee_id = v_device.employee_id
      and user_id = v_device.user_id
      and credential_id = v_device.credential_id;
  end if;

  perform public.log_audit_event(
    'attendance.device_status_changed', 'security', 'warning',
    'employee_devices', v_device.id,
    'ØªØºÙÙØ± Ø­Ø§ÙØ© Ø¬ÙØ§Ø² Ø§ÙØ­Ø¶ÙØ±', trim(p_reason),
    jsonb_build_object(
      'employeeId', v_device.employee_id,
      'status', p_status,
      'credentialId', v_device.credential_id
    )
  );

  return jsonb_build_object(
    'id', v_device.id,
    'employeeId', v_device.employee_id,
    'status', v_device.status
  );
end;
$function$;

-- punch_attendance_local_v2(uuid,text,text,double precision,double precision,double precision,boolean)
CREATE OR REPLACE FUNCTION public.punch_attendance_local_v2(p_operation_id uuid, p_event_type text, p_credential_id text, p_latitude double precision, p_longitude double precision, p_accuracy_meters double precision, p_is_mock boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_operation public.local_attendance_operations;
  v_result jsonb;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'يلزم حساب موظف مسجّل الدخول' using errcode = '42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;

  insert into public.local_attendance_operations(
    operation_id, user_id, employee_id, event_type, credential_id
  ) values (
    p_operation_id, auth.uid(), v_employee_id, p_event_type, p_credential_id
  ) on conflict (operation_id) do nothing;

  select * into v_operation
  from public.local_attendance_operations
  where operation_id = p_operation_id
  for update;

  if v_operation.user_id <> auth.uid()
     or v_operation.employee_id <> v_employee_id
     or v_operation.event_type <> p_event_type
     or v_operation.credential_id <> p_credential_id then
    raise exception 'attendance_idempotency_conflict' using errcode = '22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result, '{}'::jsonb)
      || jsonb_build_object('replayed', true);
  end if;

  v_result := public.punch_attendance_local(
    p_event_type,
    p_credential_id,
    p_latitude,
    p_longitude,
    p_accuracy_meters,
    p_is_mock,
    null
  );

  update public.local_attendance_operations
  set status = case when coalesce((v_result->>'ok')::boolean, false)
                    then 'completed' else 'rejected' end,
      result = v_result,
      completed_at = now()
  where operation_id = p_operation_id;

  return v_result || jsonb_build_object('replayed', false);
end;
$function$;

-- mark_my_notification_delivery(uuid,text)
CREATE OR REPLACE FUNCTION public.mark_my_notification_delivery(p_notification_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_log public.notification_delivery_log; v_subscription_id uuid;
begin
  if auth.uid() is null then raise exception 'يلزم مستخدم مسجل الدخول' using errcode='42501'; end if;
  if p_status not in ('delivered','opened') then raise exception 'حالة تسليم غير صالحة' using errcode='22023'; end if;
  if not exists(select 1 from public.notifications n where n.id=p_notification_id and n.recipient_user_id=auth.uid()) then
    raise exception 'الإشعار ليس لك' using errcode='42501';
  end if;
  select * into v_log from public.notification_delivery_log l
  where l.notification_id=p_notification_id and l.recipient_user_id=auth.uid()
    and l.channel='push' order by l.created_at desc limit 1 for update;
  if v_log.id is null then
    select id into v_subscription_id from public.push_subscriptions
    where user_id=auth.uid() and is_active
    order by last_used_at desc nulls last,created_at desc limit 1;
    insert into public.notification_delivery_log(
      notification_id,subscription_id,recipient_user_id,channel,status,
      attempts,sent_at,delivered_at
    ) values(p_notification_id,v_subscription_id,auth.uid(),'push',p_status,1,now(),now());
  elsif v_log.status<>'opened' or p_status='opened' then
    update public.notification_delivery_log set status=p_status,
      delivered_at=coalesce(delivered_at,now()),updated_at=now() where id=v_log.id;
  end if;
end;
$function$;

-- upsert_knowledge_category(uuid,text,text,text,boolean)
CREATE OR REPLACE FUNCTION public.upsert_knowledge_category(p_id uuid DEFAULT NULL::uuid, p_slug text DEFAULT NULL::text, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_is_active boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('knowledge.manage')) then
    raise exception 'FORBIDDEN';
  end if;
  if p_slug is null or p_name is null then
    raise exception 'المعرّف والاسم مطلوبان';
  end if;

  if p_id is null then
    insert into public.knowledge_categories (slug, name, description, is_active, created_by)
    values (lower(btrim(p_slug)), trim(p_name), nullif(btrim(coalesce(p_description,'')),''), p_is_active, auth.uid())
    returning id into v_id;
  else
    update public.knowledge_categories
       set slug = lower(btrim(p_slug)), name = trim(p_name),
           description = nullif(btrim(coalesce(p_description,'')),''),
           is_active = p_is_active
     where id = p_id
    returning id into v_id;
    if v_id is null then
      raise exception 'NOT_FOUND';
    end if;
  end if;
  return v_id;
end $function$;

-- publish_official_announcement(text,text,text,text,boolean,text,text,jsonb,timestamp with time zone)
CREATE OR REPLACE FUNCTION public.publish_official_announcement(p_title text, p_body text, p_category text DEFAULT 'general'::text, p_priority text DEFAULT 'normal'::text, p_requires_acknowledgement boolean DEFAULT false, p_banner_url text DEFAULT NULL::text, p_post_type text DEFAULT 'standard'::text, p_poll_options jsonb DEFAULT NULL::jsonb, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS announcements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row public.announcements;
  v_metadata jsonb;
begin
  -- Ø§ÙØªØ­ÙÙ ÙÙ Ø§ÙØµÙØ§Ø­ÙØ©
  if not (public.current_is_full_access()
          or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'غير مصرح لك بنشر الإعلانات' using errcode = '42501';
  end if;

  -- Ø§ÙØªØ­ÙÙ ÙÙ Ø·ÙÙ Ø§ÙØ¹ÙÙØ§Ù ÙØ§ÙÙØ­ØªÙÙ
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'العنوان أو المحتوى قصير جداً' using errcode = '22023';
  end if;

  -- Ø§ÙØªØ­ÙÙ ÙÙ ÙÙØ¹ Ø§ÙÙÙØ´ÙØ±
  if p_post_type not in ('standard', 'poll', 'announcement') then
    raise exception 'invalid post type: %', p_post_type using errcode = '22023';
  end if;

  -- Ø¨ÙØ§Ø¡ metadata
  v_metadata := jsonb_build_object('postType', p_post_type);
  if p_post_type = 'poll' and p_poll_options is not null then
    v_metadata := v_metadata || jsonb_build_object('pollOptions', p_poll_options);
  end if;

  insert into public.announcements(
    title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, post_type, published_at, expires_at,
    metadata, created_by
  )
  values (
    trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement, false),
    nullif(trim(coalesce(p_banner_url, '')), ''),
    coalesce(p_post_type, 'standard'),
    now(),
    p_expires_at,
    v_metadata,
    auth.uid()
  )
  returning * into v_row;

  perform public.log_audit_event(
    'announcement.published', 'workflow', 'info', 'announcements', v_row.id,
    'ÙØ´Ø± Ø¥Ø¹ÙØ§Ù Ø±Ø³ÙÙ', null,
    jsonb_build_object(
      'title', v_row.title,
      'priority', v_row.priority,
      'postType', v_row.post_type,
      'hasBanner', v_row.banner_url is not null,
      'hasPoll', p_post_type = 'poll'
    )
  );

  return v_row;
end;
$function$;

-- review_daily_report(uuid,text)
CREATE OR REPLACE FUNCTION public.review_daily_report(p_report_id uuid, p_manager_comment text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_manager_id uuid := public.current_employee_id();
  v_report public.daily_reports%rowtype;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_manager_id is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_manager_comment, ''))) < 3 then
    raise exception 'تعليق المدير مطلوب' using errcode = '22023';
  end if;

  select * into v_report from public.daily_reports where id=p_report_id for update;
  if not found then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;
  if v_report.employee_id = v_manager_id then
    raise exception 'التقييم الذاتي غير مسموح هنا' using errcode = '42501';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(v_report.employee_id, 'reports.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=v_report.employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'نطاق مراجعة التقارير مرفوض' using errcode = '42501';
  end if;

  update public.daily_reports
  set manager_comment=trim(p_manager_comment), reviewed_by=v_manager_id, reviewed_at=now(), updated_at=now()
  where id=p_report_id;

  return jsonb_build_object('id', p_report_id, 'reviewedBy', v_manager_id, 'reviewedAt', now(), 'managerComment', trim(p_manager_comment));
end;
$function$;

-- transition_onboarding_task_admin(uuid,text)
CREATE OR REPLACE FUNCTION public.transition_onboarding_task_admin(p_task_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_journey uuid;
  v_remaining integer;
  v_employee uuid;
begin
  if p_status not in ('pending','in_progress','completed','skipped') then
    raise exception 'حالة مهمة تهيئة غير صالحة' using errcode = '22023';
  end if;
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'انتقال مهمة التهيئة مرفوض' using errcode = '42501';
  end if;

  update public.onboarding_tasks set
    status = p_status,
    completed_at = case when p_status in ('completed','skipped') then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id
  returning journey_id into v_journey;
  if v_journey is null then raise exception 'مهمة التهيئة غير موجودة' using errcode = 'P0002'; end if;

  select count(*) into v_remaining from public.onboarding_tasks
  where journey_id = v_journey and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_journey;
    select employee_id into v_employee from public.onboarding_journeys where id = v_journey;
    update public.employees set status = 'active', updated_at = now() where id = v_employee and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_journey;
  end if;

  return jsonb_build_object('journeyId', v_journey, 'remainingTasks', v_remaining, 'completed', v_remaining = 0);
end;
$function$;

-- set_live_location_legal_hold(uuid,timestamp with time zone,text)
CREATE OR REPLACE FUNCTION public.set_live_location_legal_hold(p_video_id uuid, p_hold_until timestamp with time zone, p_reason text)
 RETURNS live_location_videos_meta
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_row public.live_location_videos_meta;
begin
  if not (public.current_is_full_access() or public.has_permission('live_location.manage_retention')) then
    raise exception 'صلاحية إدارة الاستبقاء مطلوبة' using errcode='42501';
  end if;
  if length(trim(coalesce(p_reason,'')))<5 then raise exception 'سبب الحجز القانوني مطلوب' using errcode='22023'; end if;

  update public.live_location_videos_meta
    set legal_hold_until = p_hold_until,
        retention_delete_after = case when p_hold_until is not null then greatest(coalesce(retention_delete_after,now()), p_hold_until) else retention_delete_after end
    where id=p_video_id and status<>'deleted'
    returning * into v_row;
  if not found then raise exception 'الفيديو غير موجود' using errcode='P0002'; end if;

  insert into public.live_location_video_access_logs(video_id,actor_user_id,actor_employee_id,action,reason)
  values(p_video_id, auth.uid(), public.current_employee_id(), case when p_hold_until is null then 'release_hold' else 'legal_hold' end, trim(p_reason));

  perform public.log_audit_event(
    case when p_hold_until is null then 'live_location.hold_released' else 'live_location.legal_hold' end,
    'security','warning','live_location_videos_meta',p_video_id,'Ø­ÙØ¸ Ø¥Ø¯Ø§Ø±Ù ÙÙÙØ¯ÙÙ Ø§ÙØªØ­ÙÙ',null,
    jsonb_build_object('holdUntil',p_hold_until,'reason',trim(p_reason))
  );
  return v_row;
end;
$function$;

-- respond_live_location_request(uuid,boolean)
CREATE OR REPLACE FUNCTION public.respond_live_location_request(p_request_id uuid, p_accept boolean)
 RETURNS live_location_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  declare
    v_me uuid := public.current_employee_id();
    v_row public.live_location_requests;
    v_window_minutes integer;
  begin
    select * into v_row
    from public.live_location_requests
    where id = p_request_id
    for update;

    if not found or v_row.employee_id is distinct from v_me then
      raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
    end if;
    if v_row.status <> 'pending' or v_row.expires_at <= now() then
      raise exception 'الطلب لم يعد قيد الانتظار' using errcode = '22023';
    end if;

    if p_accept then
      -- V25: ÙØ§ ØªÙÙ ÙØ§ÙØ°Ø© Ø§ÙØ¬ÙØ³Ø© Ø¹Ù 5 Ø¯ÙØ§Ø¦Ù Ø­ØªÙ ÙÙ ÙØ§Ù duration_minutes=1
      -- (ÙÙØ·Ø©). ÙØ§ÙØª Ø§ÙØ¯ÙÙÙØ© Ø§ÙÙØ§Ø­Ø¯Ø© ØªÙØ´Ù Ø§ÙØ¥Ø±Ø³Ø§Ù Ø¹ÙØ¯ ØªØ£Ø®Ø± GPS ÙØªØ¨ÙÙ Ø§ÙØ·ÙØ¨
      -- activeØ ÙØªØ³ØªÙØ± Ø¥Ø¹Ø§Ø¯Ø© Ø¥Ø±Ø³Ø§Ù Ø§ÙØ¥Ø´Ø¹Ø§Ø± Ø¥ÙÙ Ø§ÙØ£Ø¨Ø¯.
      v_window_minutes := greatest(coalesce(v_row.duration_minutes, 5), 5);
      update public.live_location_requests
      set status = 'active',
          responded_at = now(),
          starts_at = now(),
          expires_at = now() + make_interval(mins => v_window_minutes)
      where id = p_request_id
      returning * into v_row;
    else
      update public.live_location_requests
      set status = 'rejected',
          responded_at = now()
      where id = p_request_id
      returning * into v_row;
    end if;

    perform public.log_audit_event(
      case when p_accept then 'live_location.accepted' else 'live_location.rejected' end,
      'security',
      'info',
      'live_location_requests',
      v_row.id,
      'Ø±Ø¯ Ø¹ÙÙ Ø·ÙØ¨ ÙÙÙØ¹',
      null,
      jsonb_build_object('accepted', p_accept)
    );
    return v_row;
  end;
  $function$;

-- record_daily_reports_views(uuid[])
CREATE OR REPLACE FUNCTION public.record_daily_reports_views(p_report_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_recorded integer;
begin
  if v_me is null then
    raise exception 'لا يوجد ملف موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_report_ids is null or cardinality(p_report_ids) = 0 then
    return jsonb_build_object('recorded', 0);
  end if;

  with inserted as (
    insert into public.daily_report_views (report_id, employee_id, created_by, view_count)
    select t.id, v_me, auth.uid(), 1
    from unnest(p_report_ids) t(id)
    join public.daily_reports dr on dr.id = t.id
    on conflict (report_id, employee_id)
    do update set
      view_count = public.daily_report_views.view_count + 1,
      last_viewed_at = now()
    returning 1
  )
  select count(*) into v_recorded from inserted;

  return jsonb_build_object('recorded', v_recorded);
end;
$function$;

-- get_public_daily_reports_feed(integer,date)
CREATE OR REPLACE FUNCTION public.get_public_daily_reports_feed(p_limit integer DEFAULT 50, p_before date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', e.id,
    'employeeName', e.full_name_ar,
    'employeeCode', e.employee_code,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'managerName', mgr.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewedByName', rv.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at,
    'likesCount', (select count(*) from public.daily_report_likes l where l.report_id = dr.id),
    'isLikedByMe', exists(
      select 1 from public.daily_report_likes l
      where l.report_id = dr.id and l.employee_id = v_me
    ),
    'viewersCount', (select count(*) from public.daily_report_views v where v.report_id = dr.id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ve.id,
        'name', ve.full_name_ar,
        'photoUrl', ve.photo_url,
        'at', v.last_viewed_at
      ) order by v.last_viewed_at desc)
      from public.daily_report_views v
      join public.employees ve on ve.id = v.employee_id
      where v.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', le.id,
        'name', le.full_name_ar,
        'photoUrl', le.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees le on le.id = l.employee_id
      where l.report_id = dr.id
      limit 3
    ), '[]'::jsonb),
    'comments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'employeeId', c.employee_id,
        'employeeName', ce.full_name_ar,
        'comment', c.comment,
        'createdAt', c.created_at
      ) order by c.created_at asc)
      from public.daily_report_comments c
      join public.employees ce on ce.id = c.employee_id
      where c.report_id = dr.id
    ), '[]'::jsonb)
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where (p_before is null or report_date < p_before)
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 50), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.manager_relations mr on mr.employee_id = e.id
    and mr.relation_type = 'primary' and mr.effective_to is null
  left join public.employees mgr on mgr.id = mr.manager_employee_id
  left join public.employees rv on rv.id = dr.reviewed_by;

  return v_result;
end;
$function$;

-- get_daily_report_engagement(uuid)
CREATE OR REPLACE FUNCTION public.get_daily_report_engagement(p_report_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if not exists (select 1 from public.daily_reports where id = p_report_id) then
    raise exception 'لم يتم العثور على التقرير اليومي' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'reportId', p_report_id,
    'viewersCount', (
      select count(*)::integer from public.daily_report_views v
      where v.report_id = p_report_id
    ),
    'likersCount', (
      select count(*)::integer from public.daily_report_likes l
      where l.report_id = p_report_id
    ),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.daily_report_views v
      join public.employees e on e.id = v.employee_id
      where v.report_id = p_report_id
    ), '[]'::jsonb),
    'likers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', l.created_at
      ) order by l.created_at desc)
      from public.daily_report_likes l
      join public.employees e on e.id = l.employee_id
      where l.report_id = p_report_id
    ), '[]'::jsonb)
  );
end;
$function$;

-- get_employee_360(uuid)
CREATE OR REPLACE FUNCTION public.get_employee_360(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'نطاق الموظف مرفوض' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'email', au.email,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'accountStatus', profile.status,
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', manager_rel.id,
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'latestKpi', (
      select jsonb_build_object(
        'id', ke.id,
        'periodMonth', kc.period_month,
        'currentStage', ke.current_stage,
        'finalScore', ke.final_score,
        'finalRating', ke.final_rating
      )
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id=ke.cycle_id
      where ke.employee_id=e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select *
        from public.requests r
        where r.employee_id=e.id
        order by r.created_at desc
        limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) order by t.created_at desc)
      from (
        select *
        from public.tasks t
        where t.assignee_employee_id=e.id
        order by t.created_at desc
        limit 10
      ) t
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id, 'departmentName', d.name,
        'jobTitle', ed.job_title, 'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) order by ed.is_primary desc, ed.assigned_at desc)
      from public.employee_departments ed
      join public.departments d on d.id=ed.department_id
      where ed.employee_id=e.id
        and (ed.start_date is null or ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        and (ed.end_date is null or ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', e.updated_at
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.employees manager_rel on manager_rel.id = (
    select mr.manager_employee_id
    from public.manager_relations mr
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    limit 1
  )
  left join public.profiles profile on profile.employee_id=e.id
  left join auth.users au on au.id=profile.id
  where e.id=p_employee_id;

  if v_result is null then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$function$;

-- get_announcement_engagement(uuid)
CREATE OR REPLACE FUNCTION public.get_announcement_engagement(p_announcement_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;

  if not exists (select 1 from public.announcements where id = p_announcement_id) then
    raise exception 'الإعلان غير موجود' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'announcementId', p_announcement_id,
    'targetCount', (
      select count(*)::integer
      from public.employees e
      join public.profiles p on p.employee_id = e.id and p.status = 'active'
      where e.is_active and e.status = 'active' and not e.is_deleted
    ),
    'viewerCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'acknowledgedCount', (select count(*)::integer from public.announcement_acknowledgements a where a.announcement_id = p_announcement_id),
    'viewers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', v.last_viewed_at,
        'viewCount', v.view_count
      ) order by v.last_viewed_at desc)
      from public.announcement_views v
      join public.employees e on e.id = v.employee_id
      where v.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'reactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', r.updated_at,
        'reactionType', r.reaction_type
      ) order by r.updated_at desc)
      from public.announcement_reactions r
      join public.employees e on e.id = r.employee_id
      where r.announcement_id = p_announcement_id
    ), '[]'::jsonb),
    'acknowledgements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', e.id,
        'name', e.full_name_ar,
        'photoUrl', e.photo_url,
        'at', a.created_at
      ) order by a.created_at desc)
      from public.announcement_acknowledgements a
      join public.employees e on e.id = a.employee_id
      where a.announcement_id = p_announcement_id
    ), '[]'::jsonb)
  );
end;
$function$;

-- toggle_announcement_reaction(uuid,text)
CREATE OR REPLACE FUNCTION public.toggle_announcement_reaction(p_announcement_id uuid, p_reaction_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_existing text;
  v_actor_name text;
  v_publisher_user_id uuid;
  v_publisher_employee_id uuid;
  v_title text;
  v_active boolean := true;
  v_result jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;
  if p_reaction_type not in ('like', 'celebrate', 'support', 'insightful') then
    raise exception 'نوع تفاعل غير صالح' using errcode = '22023';
  end if;

  select a.title, a.created_by, p.employee_id
    into v_title, v_publisher_user_id, v_publisher_employee_id
  from public.announcements a
  left join public.profiles p on p.id = a.created_by and p.status = 'active'
  where a.id = p_announcement_id and a.status = 'published';

  if not found then
    raise exception 'announcement not found or not visible' using errcode = 'P0002';
  end if;

  select reaction_type into v_existing
  from public.announcement_reactions
  where announcement_id = p_announcement_id and employee_id = v_me
  for update;

  if v_existing = p_reaction_type then
    delete from public.announcement_reactions
    where announcement_id = p_announcement_id and employee_id = v_me;
    v_active := false;
  else
    insert into public.announcement_reactions(
      announcement_id, employee_id, reaction_type, reacted_at, updated_at, created_by
    ) values (
      p_announcement_id, v_me, p_reaction_type, now(), now(), auth.uid()
    )
    on conflict (announcement_id, employee_id) do update
      set reaction_type = excluded.reaction_type,
          updated_at = now();

    -- ÙØ§ ÙØ±Ø³Ù Ø¥Ø´Ø¹Ø§Ø±ÙØ§ ÙÙÙØ³ØªØ®Ø¯Ù Ø¹Ù ØªÙØ§Ø¹ÙÙ ÙØ¹ ÙÙØ´ÙØ±Ù ÙÙ.
    if v_publisher_user_id is not null and v_publisher_employee_id is distinct from v_me then
      select full_name_ar into v_actor_name from public.employees where id = v_me;
      perform public.notify_user(
        v_publisher_user_id,
        'ØªÙØ§Ø¹Ù Ø¬Ø¯ÙØ¯ Ø¹ÙÙ Ø¥Ø¹ÙØ§ÙÙ',
        coalesce(v_actor_name, 'Ø£Ø­Ø¯ Ø§ÙÙÙØ¸ÙÙÙ') || ' ØªÙØ§Ø¹Ù ÙØ¹ Â«' || left(v_title, 120) || 'Â».',
        'announcement', 'normal', 'announcement', p_announcement_id,
        jsonb_build_object(
          'kind', 'announcement_reaction',
          'reactionType', p_reaction_type,
          'actorEmployeeId', v_me,
          'announcementId', p_announcement_id
        )
      );
    end if;
  end if;

  select jsonb_build_object(
    'active', v_active,
    'myReaction', case when v_active then p_reaction_type else null end,
    'viewCount', (select count(*)::integer from public.announcement_views v where v.announcement_id = p_announcement_id),
    'reactionCount', (select count(*)::integer from public.announcement_reactions r where r.announcement_id = p_announcement_id),
    'reactionSummary', coalesce((
      select jsonb_object_agg(x.reaction_type, x.total)
      from (
        select r.reaction_type, count(*)::integer as total
        from public.announcement_reactions r
        where r.announcement_id = p_announcement_id
        group by r.reaction_type
      ) x
    ), '{}'::jsonb)
  ) into v_result;

  return v_result;
end;
$function$;

-- request_device_replacement(text)
CREATE OR REPLACE FUNCTION public.request_device_replacement(p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_employee_id uuid := public.current_employee_id();
  v_user_id uuid := auth.uid();
begin
  if v_employee_id is null or v_user_id is null then
    raise exception 'يلزم موظف مسجل الدخول' using errcode = '42501';
  end if;

  -- V24: Do NOT revoke active devices. The old device stays usable until
  -- admin approves the new one. approve_device() (0171) will handle
  -- replacement when it sets the new device to 'active'.

  -- Log the request for audit and admin notification
  perform public.log_security_event(
    'device.replacement_requested',
    'high', 'allowed',
    null,
    jsonb_build_object(
      'employeeId', v_employee_id,
      'reason', p_reason
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', 'Ø¬ÙØ§Ø²Ù Ø§ÙØ­Ø§ÙÙ Ø³ÙØ¨ÙÙ ÙØ´Ø·Ø§Ù Ø­ØªÙ Ø§Ø¹ØªÙØ§Ø¯ Ø§ÙØ¬ÙØ§Ø² Ø§ÙØ¬Ø¯ÙØ¯ ÙÙ ÙØ¨Ù Ø§ÙÙØ³Ø¤ÙÙ.'
  );
end;
$function$;

-- get_mobile_feed_item(text,uuid)
CREATE OR REPLACE FUNCTION public.get_mobile_feed_item(p_kind text, p_item_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_result jsonb;
begin
  if lower(p_kind) = 'announcement' then
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'postType', coalesce(a.post_type, 'announcement'),
      'requiresAcknowledgement', a.requires_acknowledgement,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'myReaction', (select x.reaction_type from public.announcement_reactions x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'viewCount', (select count(*)::integer from public.announcement_views x where x.announcement_id=a.id),
      'reactionCount', (select count(*)::integer from public.announcement_reactions x where x.announcement_id=a.id),
      'reactionSummary', coalesce((
        select jsonb_object_agg(x.reaction_type, x.total)
        from (
          select ar.reaction_type, count(*)::integer total
          from public.announcement_reactions ar
          where ar.announcement_id = a.id
          group by ar.reaction_type
        ) x
      ), '{}'::jsonb),
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'authorName', ae.full_name_ar,
      'authorPhotoUrl', ae.photo_url,
      'attachments', case when a.banner_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',a.banner_url,'type','banner')) end
    ) into v_result
    from public.announcements a
    left join public.employees ae on ae.user_id = a.created_by
    where a.id=p_item_id and a.status='published';
  elsif lower(p_kind) = 'decision' then
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'postType', 'decision',
      'requiresAcknowledgement', d.requires_read_receipt,
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'myReaction', null,
      'viewCount', (select count(*)::integer from public.decision_reads x where x.decision_id=d.id),
      'reactionCount', 0,
      'reactionSummary', '{}'::jsonb,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'decisionNumber', d.decision_number,
      'effectiveDate', d.effective_date,
      'attachments', case when d.attachment_url is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('url',d.attachment_url,'type','attachment')) end
    ) into v_result
    from public.administrative_decisions d where d.id=p_item_id and d.status='published';
  elsif lower(p_kind) = 'recognition' then
    select jsonb_build_object(
      'id', r.id, 'kind', 'recognition', 'title', r.title, 'body', coalesce(r.message,''),
      'category', r.recognition_type, 'priority', coalesce(r.metadata->>'priority','normal'),
      'status', 'published', 'requiresAcknowledgement', false, 'myAcknowledged', false,
      'myReaction', null, 'viewCount', 0, 'reactionCount', 0, 'reactionSummary', '{}'::jsonb,
      'publishedAt', r.awarded_at, 'expiresAt', null, 'imageUrl', null,
      'postType', 'recognition', 'authorName', coalesce(nom.full_name_ar, 'Ø§ÙØ¥Ø¯Ø§Ø±Ø©'),
      'authorPhotoUrl', null, 'attachments', '[]'::jsonb
    ) into v_result
    from public.recognitions r
    left join public.employees nom on nom.id = r.nominated_by
    where r.id = p_item_id
      and (
        r.is_public
        or r.recipient_employee_id = public.current_employee_id()
        or r.nominated_by = public.current_employee_id()
        or public.current_is_full_access()
        or public.has_any_permission(array['recognition.read','recognition.manage'])
      );
  else
    raise exception 'نوع عنصر غير مدعوم' using errcode='22023';
  end if;

  if v_result is null then
    raise exception 'العنصر غير موجود أو غير مرئي' using errcode='P0002';
  end if;
  return v_result;
end;
$function$;

-- submit_my_request(text,text,text,jsonb,uuid)
CREATE OR REPLACE FUNCTION public.submit_my_request(p_request_type text, p_title text, p_reason text, p_payload jsonb DEFAULT '{}'::jsonb, p_idempotency_key uuid DEFAULT NULL::uuid)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_row               public.requests;
  v_payload           jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
  v_day_mark          boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date        date;
  v_end_date          date;
  v_permit_date       date;
  v_minutes           integer;
  v_leave_type        text;
  v_leave_type_id     uuid;
  v_affects           boolean;
  v_days              numeric;
  v_substitute        uuid;
  v_correction_date   date;
  v_correction_type   text;
  v_corrected_time    text;
  v_permit_kind       text;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  -- ââ idempotency (0379): same key within 10 minutes returns the same row ââ
  if p_idempotency_key is not null then
    select * into v_row
    from public.requests
    where employee_id = v_me
      and payload ->> 'clientId' = p_idempotency_key::text
      and created_at > now() - interval '10 minutes';
    if found then
      return v_row;
    end if;
    v_payload := v_payload || jsonb_build_object('clientId', p_idempotency_key::text);
  end if;
  -- ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  -- V17 Â§8 + 0333: request types (legacy + attendance_permit/generic from 0379)
  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction','attendance_permit','generic') then
    raise exception 'نوع طلب غير صالح' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  -- ÙÙØ§Ø¹Ø¯ ØªØ­Ø¯ÙØ¯ Ø§ÙÙÙÙ (dayMark): ÙÙÙ ÙØ§Ø¶Ù ÙÙ ÙÙØ³ Ø§ÙØ´ÙØ± Ø£Ù Ø§ÙÙÙÙ Ø§ÙØ­Ø§ÙÙ ÙÙØ·.
  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'day mark requires a date' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'day marks are single-day only' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'day marks are allowed within the current month only' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'future days cannot be marked' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- âââ Ø¥Ø¬Ø§Ø²Ø© ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- ØªÙØ§ÙÙ Ø®ÙÙÙ: emergency â casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'نوع إجازة غير مدعوم' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        -- Ø£Ø«Ø± Ø±Ø¬Ø¹Ù: ÙØ³ÙÙØ­ ÙÙØ· Ø¹Ø¨Ø± dayMark (ÙÙØ³ Ø§ÙØ´ÙØ±) â ÙØ¥ÙØ§ ÙÙØ¹ ÙØ§ÙÙØ¹ØªØ§Ø¯
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      -- âââ ÙØ£ÙÙØ±ÙØ© / ÙØ§ÙÙØ© / ÙØ§ÙØ¯Ù âââââââââââââââââââââââââââââââââââââââââââ
      when 'mission', 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'تاريخا بداية ونهاية التكليف مطلوبان' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'تاريخ نهاية التكليف لا يسبق تاريخ البداية' using errcode = '22023';
        end if;
        if not v_day_mark and v_start_date < v_today then
          raise exception 'التكليفات بأثر رجعي غير مسموحة' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        -- ÙÙØª ÙØ®Ø·Ø· Ø§Ø®ØªÙØ§Ø±Ù Ø¨ØµÙØºØ© HH:MM â ÙØ±ÙØ¶ "9:00"
        if nullif(trim(coalesce(v_payload->>'startTime','')),'') is not null
           and v_payload->>'startTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'startTime must be in HH:MM format' using errcode = '22023';
        end if;
        if nullif(trim(coalesce(v_payload->>'endTime','')),'') is not null
           and v_payload->>'endTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'endTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1,
          'startTime', nullif(trim(coalesce(v_payload->>'startTime','')),''),
          'endTime', nullif(trim(coalesce(v_payload->>'endTime','')),''));

      -- âââ Ø¥Ø°Ù ØªØ£Ø®ÙØ± (V17 Â§8) ââââââââââââââââââââââââââââââââââââââââââââââââ
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- âââ Ø¥Ø°Ù Ø§ÙØµØ±Ø§Ù ÙØ¨ÙØ± (V17 Â§8) ââââââââââââââââââââââââââââââââââââââââââ
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- âââ Ø¥Ø°Ù Ø­Ø¶ÙØ± ÙÙØ­Ø¯ (0379) âââââââââââââââââââââââââââââââââââââââââââââ
      when 'attendance_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_permit_kind := v_payload->>'permitKind';
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'تاريخ الإذن مطلوب' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'إذن الحضور بأثر رجعي غير مسموح' using errcode = '22023';
        end if;
        if v_permit_kind not in ('late_arrival','early_departure') then
          raise exception 'نوع إذن غير مدعوم' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'دقائق الإذن يجب أن تكون بين 1 و240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', v_permit_kind,
          'minutes', v_minutes);

      -- âââ ØªØµØ­ÙØ­ Ø­Ø¶ÙØ± (V17 Â§8) âââââââââââââââââââââââââââââââââââââââââââââ
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'تاريخ التصحيح مطلوب' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'نوع التصحيح يجب أن يكون حضور أو انصراف أو كلاهما' using errcode = '22023';
        end if;
        if v_corrected_time is null or v_corrected_time !~ '^\d{2}:\d{2}$' then
          raise exception 'correctedTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime', v_corrected_time);

      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'تواريخ أو قيم رقمية غير صالحة' using errcode = '22023';
  end;

  -- Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ³Ø¤ÙÙ ÙÙ Ø§ÙÙÙÙÙ Ø§ÙØ¥Ø¯Ø§Ø±Ù (ÙØ¹ ÙÙØ¹ Ø§ÙÙÙØ§ÙÙØ© Ø§ÙØ°Ø§ØªÙØ© + ØªÙØ¬ÙÙ Ø§ÙØªØ´ØºÙÙ)
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- Ø¥ÙØ´Ø§Ø¡ ØµÙ ØªÙØµÙÙ Ø§ÙØ¥Ø¬Ø§Ø²Ø© (ÙÙÙØ¹ÙÙ Ø­Ø¬Ø² Ø§ÙØ±ØµÙØ¯ Ø¹Ø¨Ø± ØªØ±ÙØºØ± 0026)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    -- Ø§ÙØ¹Ø§Ø±Ø¶Ø©/Ø§ÙØ·Ø§Ø±Ø¦Ø©: ØªÙÙÙÙÙØ° ÙØ¨Ø§Ø´Ø±Ø© Ø¯ÙÙ ÙÙØ§ÙÙØ© Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø±
    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© Ø¯ÙÙ ÙÙØ§ÙÙØ©', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'ØªÙÙÙØ° ÙØ¨Ø§Ø´Ø± ÙÙØ¥Ø¬Ø§Ø²Ø© Ø§ÙØ¹Ø§Ø±Ø¶Ø© (ÙØ§ ØªØ³ØªÙØ¬Ø¨ ÙÙØ§ÙÙØ© Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø±)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'ØªÙÙÙØ° ÙÙØ±Ù ÙØ¥Ø¬Ø§Ø²Ø© Ø¹Ø§Ø±Ø¶Ø©',
        format('ÙÙ %s Ø¥ÙÙ %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  return v_row;
end $function$;

-- admin_reinstate_device(uuid,text)
CREATE OR REPLACE FUNCTION public.admin_reinstate_device(p_device_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'لم يتم العثور على الجهاز' using errcode = 'P0002';
  end if;

  if v_device.status not in ('revoked', 'auto_revoked', 'blocked') then
    raise exception 'device is not in a reinstatable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  update public.employee_devices
  set status = 'pending',
      revoked_at = null,
      revocation_source = null,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'reinstated', true,
        'reinstatedAt', now(),
        'reinstatedBy', auth.uid(),
        'reinstateReason', p_reason,
        'previousStatus', v_device.status
      )
  where id = p_device_id;

  -- Ø¥Ø¹Ø§Ø¯Ø© ØªÙØ´ÙØ· Ø¨ÙØ§ÙØ§Øª Ø§Ø¹ØªÙØ§Ø¯ Ø§ÙØ¨ØµÙØ© Ø§ÙÙØ±ØªØ¨Ø·Ø© (Ø¨ÙØ§ Ø«ÙØ© Ø­ØªÙ ØªÙØ¹ØªÙØ¯ ÙÙ Ø¬Ø¯ÙØ¯).
  update public.passkey_credentials
  set status = 'active', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked';

  perform public.log_security_event(
    'device.reinstated', 'medium', 'allowed', v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'previousStatus', v_device.status,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'pending',
    'previousStatus', v_device.status
  );
end;
$function$;

-- cancel_location_request_as_requester(uuid)
CREATE OR REPLACE FUNCTION public.cancel_location_request_as_requester(p_request_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me  uuid := public.current_employee_id();
  v_req public.live_location_requests;
begin
  select * into v_req from public.live_location_requests where id = p_request_id;
  if not found then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  -- Only the original requester OR a full-access user can cancel.
  if v_req.requested_by is distinct from v_me and not public.current_is_full_access() then
    raise exception 'يمكنك إلغاء طلبات موقعك فقط' using errcode = '42501';
  end if;
  if v_req.status not in ('pending', 'accepted') then
    raise exception 'لا يمكن إلغاء الطلب بحالته الحالية' using errcode = '22023';
  end if;

  update public.live_location_requests
    set status     = 'rejected',
        expires_at = now(),
        metadata   = jsonb_set(
          coalesce(metadata, '{}'::jsonb),
          '{cancelledByRequester}',
          'true'
        )
    where id = p_request_id;

  perform public.log_audit_event(
    'live_location.request_cancelled', 'security', 'info',
    'live_location_requests', p_request_id,
    'Ø¥ÙØºØ§Ø¡ Ø·ÙØ¨ Ø§ÙÙÙÙØ¹ ÙÙ ÙÙØ¨Ù Ø§ÙÙØ¯ÙØ±', null,
    jsonb_build_object('requestId', p_request_id, 'cancelledBy', v_me)
  );

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙÙØ¸Ù Ø§ÙÙØ³ØªÙØ¯Ù Ø¨Ø¥ÙØºØ§Ø¡ Ø§ÙØ·ÙØ¨ (0316)
  if v_req.employee_id is not null and v_req.employee_id <> v_me then
    perform public.notify_employee(
      v_req.employee_id, 'Ø£ÙÙØºÙ Ø·ÙØ¨ ÙØ´Ø§Ø±ÙØ© ÙÙÙØ¹Ù',
      format('Ø£ÙÙØºÙ Ø·ÙØ¨ ÙØ´Ø§Ø±ÙØ© Ø§ÙÙÙÙØ¹ Ø§ÙØ­ÙÙ (Ø§ÙØ­Ø§ÙØ©: %s)', coalesce(v_req.status, '')),
      'location', 'normal', 'live_location_requests', p_request_id,
      jsonb_build_object('cancelledBy', v_me));
  end if;
end;
$function$;

-- _submit_request_for(uuid,text,uuid,uuid,text,text,jsonb)
CREATE OR REPLACE FUNCTION public._submit_request_for(p_employee_id uuid, p_request_type text, p_workflow_definition_id uuid DEFAULT NULL::uuid, p_manager_employee_id uuid DEFAULT NULL::uuid, p_title text DEFAULT NULL::text, p_reason text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me             uuid := public.current_employee_id();
  v_def            public.workflow_definitions;
  v_due            timestamptz;
  v_esc            timestamptz;
  v_row            public.requests;
  v_first_approver uuid;
  v_exec_emp       uuid;
  v_label          text;
begin
  if p_employee_id is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request_type: %', p_request_type using errcode = '22023';
  end if;

  if p_manager_employee_id is not null and p_manager_employee_id = p_employee_id then
    raise exception 'self-approval is not allowed (manager cannot be requester)' using errcode = '42501';
  end if;

  -- Ø§ÙØªØ¹Ø±ÙÙ Ø§ÙØ§ÙØªØ±Ø§Ø¶Ù ÙØ³ÙØ± Ø§ÙØ¹ÙÙ
  if p_workflow_definition_id is not null then
    select * into v_def from public.workflow_definitions where id = p_workflow_definition_id;
  else
    select * into v_def from public.workflow_definitions
      where request_type = p_request_type and is_default = true and is_active = true
      order by version desc limit 1;
  end if;

  if v_def.id is not null then
    v_due := now() + make_interval(hours => coalesce(v_def.default_due_hours, 48));
    if v_def.auto_escalate then v_esc := v_due; end if;
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

  -- Ø¥ÙØ´Ø§Ø¡ Ø®Ø·ÙØ§Øª Ø§ÙØ¬Ø§Ø±ÙØ©
  if v_def.id is not null then
    insert into public.request_steps (
      request_id, workflow_step_id, step_order, name_ar, step_type,
      assignee_employee_id, assignee_role_slug, status, sla_hours,
      due_at, escalation_deadline, created_by
    )
    select
      v_row.id, ws.id, ws.step_order, ws.name_ar, ws.step_type,
      case when ws.approver_type = 'specific_employee' then ws.approver_employee_id
           when ws.approver_type in ('direct_manager','department_manager') then p_manager_employee_id
           else null end,
      ws.approver_role_slug,
      case when ws.step_order = 1 then 'active' else 'pending' end,
      ws.sla_hours,
      case when ws.step_order = 1
           then now() + make_interval(hours => coalesce(ws.sla_hours, 48)) end,
      case when ws.step_order = 1 and ws.escalate_after_hours is not null
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
  ) values (v_row.id, v_me, 'submit', 'pending', p_reason, auth.uid());

  v_label := format('%s â %s',
    public.request_type_label(v_row.request_type),
    coalesce(v_row.title, ''));

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø± (Ø£ÙÙ Ø®Ø·ÙØ© ÙØ´Ø·Ø©)
  select s.assignee_employee_id into v_first_approver
  from public.request_steps s
  where s.request_id = v_row.id and s.status = 'active'
  order by s.step_order limit 1;

  if v_first_approver is null then
    v_first_approver := v_row.manager_employee_id;
  end if;

  if v_first_approver is not null and v_first_approver <> v_row.employee_id then
    perform public.notify_employee(
      v_first_approver,
      'Ø·ÙØ¨ Ø¬Ø¯ÙØ¯ Ø¨Ø§ÙØªØ¸Ø§Ø± ÙØ±Ø§Ø¬Ø¹ØªÙ',
      v_label,
      'request', 'high', 'request', v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'workflowStatus', 'submitted',
        'deepLink', '/requests/' || v_row.id
      )
    );
  end if;

  -- Ø¥Ø´Ø¹Ø§Ø± Ø§ÙÙØ¯ÙØ± Ø§ÙØªÙÙÙØ°Ù â Ø¥ÙØ¨Ø§Ù ÙØ§ÙÙ Ø§ÙØ´Ø§Ø´Ø© Ø¹ÙÙ ÙÙ Ø·ÙØ¨ Ø¬Ø¯ÙØ¯
  v_exec_emp := public.first_active_employee_for_role('executive-director');
  if v_exec_emp is not null
     and v_exec_emp <> v_row.employee_id
     and v_exec_emp is distinct from v_first_approver then
    perform public.notify_executive_fullscreen(
      'Ø·ÙØ¨ Ø¬Ø¯ÙØ¯ â ÙÙÙØ±Ø§Ø¬Ø¹Ø©',
      v_label,
      'request',
      'request', v_row.id,
      '/requests/' || v_row.id,
      jsonb_build_object(
        'requestType', v_row.request_type,
        'infoOnly', false
      )
    );
  end if;

  return v_row;
end;
$function$;

-- get_mobile_executive_employee_summary(uuid)
CREATE OR REPLACE FUNCTION public.get_mobile_executive_employee_summary(p_employee_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_allowed boolean;
  v_result jsonb;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'وصول ملخص الموظفين مرفوض' using errcode = '42501';
  end if;
  -- ÙØ·Ø§Ù ÙØ¹ÙÙ Ø¹ÙÙ Ø§ÙÙÙØ¸Ù Ø§ÙÙØ³ØªÙØ¯Ù â Ø§ÙÙØ¯ÙØ± Ø§ÙÙØ¨Ø§Ø´Ø± ÙØ§ ÙÙØ±Ø£ Ø®Ø§Ø±Ø¬ ÙØ±ÙÙÙ.
  if not (public.current_is_full_access() or public.can_access_employee(p_employee_id,'people.employee.read')) then
    raise exception 'FORBIDDEN: ÙØ§ ØªÙÙÙ ØµÙØ§Ø­ÙØ© Ø±Ø¤ÙØ© ÙÙÙ ÙØ°Ø§ Ø§ÙÙÙØ¸Ù' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'status', e.status,
    'jobTitle', jt.name,
    'position', p.name,
    'department', d.name,
    'team', tm.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'hireDate', e.hire_date,
    'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
    'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
    'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
    'latestKpi', (
      select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'recentAttendance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'workDate', a.work_date,
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'workMinutes', a.work_minutes,
        'firstCheckIn', a.first_check_in,
        'lastCheckOut', a.last_check_out
      ) order by a.work_date desc)
      from (
        select * from public.attendance_daily
        where employee_id = e.id
        order by work_date desc
        limit 14
      ) a
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = p_employee_id;

  return v_result;
end;
$function$;

-- create_onboarding_journey_admin(uuid,timestamp with time zone,date,jsonb)
CREATE OR REPLACE FUNCTION public.create_onboarding_journey_admin(p_employee_id uuid, p_started_at timestamp with time zone DEFAULT now(), p_probation_end date DEFAULT NULL::date, p_tasks jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_task jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'إدارة التهيئة مرفوضة' using errcode = '42501';
  end if;
  if jsonb_array_length(coalesce(p_tasks, '[]'::jsonb)) > 200 then
    raise exception 'ERR_BATCH_TOO_LARGE' using errcode = '22023';
  end if;
  if not exists(select 1 from public.employees e where e.id = p_employee_id and e.is_deleted = false) then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  if exists(select 1 from public.onboarding_journeys j where j.employee_id = p_employee_id and j.status in ('not_started','in_progress')) then
    raise exception 'الموظف لديه رحلة تهيئة نشطة بالفعل' using errcode = '23505';
  end if;

  insert into public.onboarding_journeys(employee_id, started_at, probation_end, status, created_by)
  values (p_employee_id, coalesce(p_started_at, now()), p_probation_end, 'in_progress', auth.uid())
  returning id into v_id;

  for v_task in select * from jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) loop
    if nullif(trim(v_task->>'title'), '') is not null then
      insert into public.onboarding_tasks(journey_id, title, owner_role, assignee_id, due_offset_days, status, created_by)
      values (
        v_id,
        trim(v_task->>'title'),
        nullif(trim(v_task->>'ownerRole'), ''),
        nullif(v_task->>'assigneeId', '')::uuid,
        coalesce(nullif(v_task->>'dueOffsetDays', '')::integer, 0),
        'pending', auth.uid()
      );
    end if;
  end loop;

  update public.employees set status = 'onboarding', updated_at = now()
  where id = p_employee_id and status in ('draft','invited');
  return v_id;
end;
$function$;

-- check_invite_rate_limit(uuid)
CREATE OR REPLACE FUNCTION public.check_invite_rate_limit(p_employee_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_last_invite timestamptz;
begin
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  -- current_user is the function owner inside SECURITY DEFINER and therefore
  -- cannot identify the caller. A JWT-backed caller must be full-access;
  -- trusted server invocations have no end-user auth.uid().
  if auth.uid() is not null
     and not public.current_is_full_access() then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  select max(ae.created_at)
    into v_last_invite
  from public.audit_events ae
  where ae.target_table = 'employees'
    and ae.target_id = p_employee_id
    and ae.event_type in ('employee.invite.resent', 'employee.invite.sent');

  if v_last_invite is not null
     and v_last_invite > now() - interval '60 seconds' then
    raise exception 'invite_rate_limit_exceeded'
      using errcode = '42501',
            hint = 'ÙØ±Ø¬Ù Ø§ÙØ§ÙØªØ¸Ø§Ø± 60 Ø«Ø§ÙÙØ© ÙØ¨Ù Ø¥Ø¹Ø§Ø¯Ø© Ø¥Ø±Ø³Ø§Ù Ø§ÙØ¯Ø¹ÙØ©.';
  end if;
end;
$function$;

-- get_kpi_cycle_evaluations(uuid)
CREATE OR REPLACE FUNCTION public.get_kpi_cycle_evaluations(p_cycle_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '28000';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_permission('performance.kpi.read')
    or public.has_permission('performance.kpi.hr_review')
    or public.has_permission('performance.kpi.manager_assess')
  ) then
    raise exception 'لا تملك صلاحية كافية لهذا الإجراء' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', e.id,
        'employeeId', e.employee_id,
        'employeeName', emp.full_name_ar,
        'employeeCode', emp.employee_code,
        'department', d.name,
        'stage', e.current_stage,
        'workflowStatus', e.workflow_status,
        'selfScore', scores.self_score,
        'managerScore', scores.manager_score,
        'finalScore', e.final_score,
        'finalRating', e.final_rating,
        'locked', e.locked,
        'updatedAt', e.updated_at
      ) order by emp.full_name_ar, e.id
    )
    from public.kpi_evaluations e
    join public.employees emp on emp.id = e.employee_id
    left join public.departments d on d.id = emp.department_id
    left join lateral (
      select
        round(avg(s.score) filter (where s.reviewer_stage = 'self'), 2) as self_score,
        round(avg(s.score) filter (where s.reviewer_stage = 'manager'), 2) as manager_score
      from public.kpi_scores s
      where s.evaluation_id = e.id
    ) scores on true
    where e.cycle_id = p_cycle_id
      and (
        public.current_is_full_access()
        or public.has_permission('performance.kpi.hr_review')
        or e.employee_id = public.current_employee_id()
        or public.kpi_is_direct_manager(e.employee_id)
      )
  ), '[]'::jsonb);
end;
$function$;

-- get_my_attendance_state(text)
CREATE OR REPLACE FUNCTION public.get_my_attendance_state(p_installation_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_local_devices integer := 0;
  v_local_device_status text;
  v_current_device_active boolean := false;
  v_current_device_status text;
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
  v_hash text;
  v_today_check_in timestamptz;
  v_today_check_out timestamptz;
  v_cutoff time;
  v_m_id uuid;
  v_m_type text;
  v_m_start_time text;
  v_m_exec text;
  v_m_started timestamptz;
  v_m_ended timestamptz;
  v_m_auto boolean := false;
  v_can_punch boolean;
  v_mission jsonb;
begin
  if v_me is null then
    raise exception 'لا يوجد موظف مرتبط بحسابك' using errcode = '42501';
  end if;

  select e.is_active and not coalesce(e.is_deleted, false), exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.slug in ('executive','executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_active, v_is_executive
  from public.employees e where e.id = v_me;

  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id=auth.uid() and md.employee_id=v_me
    and md.platform in ('android','ios') and md.status='active'
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

    if exists (
      select 1 from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'active'
    ) then
      select ed.status into v_current_device_status
      from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
      order by ed.created_at desc
      limit 1;

      if v_current_device_status = 'active' then
        v_current_device_active := true;
      end if;
    else
      select md.status into v_current_device_status
      from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
      limit 1;

      if v_current_device_status is null then
        v_current_device_status := 'not_registered';
      end if;
    end if;
  end if;

  if v_local_devices > 0 then
    v_local_device_status := 'active';
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id=v_me and p.user_id=auth.uid()
    and p.status='active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
  order by event_at desc limit 1;
  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;
  if v_last.id is not null and v_last.event_type='CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  end if;

  select event_at into v_today_check_in
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_IN'
  order by event_at asc limit 1;

  select event_at into v_today_check_out
  from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
    and event_type='CHECK_OUT'
  order by event_at desc limit 1;

  -- ââ ÙÙÙ Ø§ÙÙØ£ÙÙØ±ÙØ© (0450 + 0452 Ø£ÙÙÙÙØ© ØªØ¹Ø¯Ø¯ Ø§ÙÙØ£ÙÙØ±ÙØ§Øª) âââââââââââââ
  select coalesce(s.shift_end_time, time '18:00') into v_cutoff
    from public.attendance_settings s where s.singleton_key;
  v_cutoff := coalesce(v_cutoff, time '18:00');

  -- 0453: Ø§ÙØ£Ø³Ø¨ÙÙØ© ÙÙØ¬Ø§Ø±ÙØ©Ø Ø«Ù ØºÙØ± Ø§ÙÙØ¨Ø¯ÙØ¡Ø©Ø Ø«Ù Ø§ÙÙÙØªÙÙØ© â
  -- Ø­ØªÙ ØªØ¸ÙØ± Â«Ø¨Ø¯Ø¡Â» ÙÙÙØ£ÙÙØ±ÙØ© Ø§ÙØªØ§ÙÙØ© Ø¨Ø¹Ø¯ Ø¥ÙÙØ§Ø¡ Ø³Ø§Ø¨ÙØªÙØ§ ÙÙ ÙÙØ³ Ø§ÙÙÙÙ.
  select r.id, r.request_type, nullif(r.payload->>'startTime',''),
         x.exec_status, x.started_at, x.ended_at
    into v_m_id, v_m_type, v_m_start_time, v_m_exec, v_m_started, v_m_ended
    from public.requests r
    left join lateral (
      select m.status as exec_status, m.started_at, m.ended_at
        from public.mission_executions m
       where m.request_id = r.id
       order by m.created_at desc
       limit 1
    ) x on true
   where r.employee_id = v_me
     and r.status = 'approved'
     and r.request_type in ('mission','convoy','fundraising')
     and v_today between coalesce(nullif(r.payload->>'startDate','')::date, v_today)
                     and coalesce(nullif(r.payload->>'endDate','')::date, v_today)
   order by case
              when x.exec_status = 'in_progress' then 0
              when x.exec_status is null        then 1
              else 2
            end,
            x.started_at desc nulls last,
            r.created_at desc
   limit 1;

  if v_m_id is not null then
    v_m_auto := v_m_ended is not null
                and (v_m_ended at time zone 'Africa/Cairo')::time >= v_cutoff;

    if v_today_check_in is null and v_m_started is not null then
      v_today_check_in := v_m_started;
    end if;
    if v_today_check_out is null then
      select d.last_check_out into v_today_check_out
        from public.attendance_daily d
       where d.employee_id=v_me and d.work_date=v_today;
    end if;

    if v_last.id is null then
      if v_m_exec is null then
        v_suggested := 'MISSION_START';
      elsif v_m_exec = 'in_progress' then
        v_suggested := 'MISSION_IN_PROGRESS';
      elsif v_m_exec = 'completed' then
        v_suggested := case when v_m_auto then 'DAY_COMPLETED' else 'CHECK_OUT' end;
      end if;
    elsif v_m_exec = 'completed' and v_m_auto and v_today_check_out is not null then
      v_suggested := 'DAY_COMPLETED';
    end if;

    v_mission := jsonb_build_object(
      'requestId', v_m_id,
      'type', v_m_type,
      'execStatus', coalesce(v_m_exec, 'approved'),
      'startTime', v_m_start_time,
      'startedAt', v_m_started,
      'endedAt', v_m_ended,
      'autoCheckout', v_m_auto
    );
  end if;

  v_can_punch := v_active and not v_is_executive and (
    case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
         then v_current_device_active
         else v_local_devices > 0
    end
  );
  if v_suggested in ('MISSION_START','MISSION_IN_PROGRESS') then
    v_can_punch := false;
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_can_punch,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'todayCheckInAt',v_today_check_in,
    'todayCheckOutAt',v_today_check_out,
    'missionToday',v_mission,
    'lastUpdatedAt',now()
  );
end;
$function$;

-- submit_live_location_point(uuid,double precision,double precision,double precision,double precision,double precision,double precision,boolean,text)
CREATE OR REPLACE FUNCTION public.submit_live_location_point(p_request_id uuid, p_latitude double precision, p_longitude double precision, p_accuracy double precision, p_altitude double precision DEFAULT NULL::double precision, p_speed double precision DEFAULT NULL::double precision, p_heading double precision DEFAULT NULL::double precision, p_is_mock boolean DEFAULT false, p_address_ar text DEFAULT NULL::text)
 RETURNS employee_locations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_row public.employee_locations;
  v_mode text;
  v_needs_video boolean;
  v_has_video boolean := false;
begin
  if p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'إحداثيات غير صالحة' using errcode = '22023';
  end if;
  if p_accuracy is null or p_accuracy < 0 or p_accuracy > 10000 then
    raise exception 'دقة الموقع غير صالحة' using errcode = '22023';
  end if;

  select * into v_req
  from public.live_location_requests
  where id = p_request_id
  for update;

  if not found or v_req.employee_id is distinct from v_me then
    raise exception 'لم يتم العثور على الطلب' using errcode = 'P0002';
  end if;
  if v_req.status <> 'active' or v_req.expires_at <= now() then
    raise exception 'location session is not active' using errcode = '22023';
  end if;

  insert into public.employee_locations(
    employee_id,
    live_request_id,
    latitude,
    longitude,
    accuracy,
    altitude,
    speed,
    heading,
    source,
    is_mock,
    address_ar,
    geocode_source,
    recorded_at,
    created_by
  )
  values(
    v_me,
    p_request_id,
    p_latitude,
    p_longitude,
    p_accuracy,
    p_altitude,
    p_speed,
    p_heading,
    'mobile',
    coalesce(p_is_mock, false),
    nullif(trim(coalesce(p_address_ar, '')), ''),
    case when nullif(trim(coalesce(p_address_ar, '')), '') is not null then 'nominatim' else null end,
    now(),
    auth.uid()
  )
  returning * into v_row;

  v_mode := coalesce(v_req.metadata->>'mode', 'snapshot');
  v_needs_video := coalesce((v_req.metadata->>'needsVideo')::boolean, v_mode in ('video_5s', 'location_video'));

  if v_needs_video then
    select exists(
      select 1
      from public.live_location_videos_meta
      where live_request_id = p_request_id
        and status <> 'deleted'
    ) into v_has_video;
  end if;

  if not v_needs_video or v_has_video then
    update public.live_location_requests
    set status = 'completed',
        expires_at = now(),
        updated_at = now()
    where id = p_request_id;
  end if;

  return v_row;
end $function$;

