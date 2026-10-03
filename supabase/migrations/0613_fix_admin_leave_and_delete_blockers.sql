-- 0613: إصلاح ثلاث عمليات إدارية في لوحة الويب معطّلة منذ إنشائها
-- ===========================================================================
-- فحص ثابت (plpgsql_check) لكل دوال الإنتاج كشف:
--   • admin_create_leave_request (0505): تستدعي public.leave_type_label غير
--     الموجودة عند غياب العنوان — ونموذج «إنشاء إجازة بدل موظف» في الويب لا يرسل
--     عنوانًا أبدًا، فكان يفشل دائمًا (42883). العنوان الآن من leave_types.name_ar.
--   • delete_department_admin (0573) و delete_job_title (0574):
--     v_blockers || 'نص' يفسّر النص كمصفوفة → «malformed array literal» بدل
--     رسالة الموانع الواضحة عند وجود ارتباطات. → array_append.
-- استبدال كنوني كامل لكل دالة (نسخها المصدرية مطابقة للمنشور حرفيًا) بهذه
-- التغييرات فقط.
-- ===========================================================================

begin;

create or replace function public.admin_create_leave_request(
  p_employee_id      uuid,
  p_leave_type       text,
  p_start_date       date,
  p_end_date         date,
  p_reason           text default null,
  p_title            text default null,
  p_handover_notes   text default null,
  p_substitute_employee_id uuid default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me                uuid := public.current_employee_id();
  v_manager           uuid;
  v_leave_type_id     uuid;
  v_days              numeric;
  v_payload           jsonb;
  v_row               public.requests;
  v_today             date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start       date := date_trunc('month', v_today)::date;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_permission('requests.leave.balance.adjust')
    or public.current_has_active_role(array['admin','super-admin','hr-manager'])
  ) then
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

  if p_leave_type = 'emergency' then p_leave_type := 'casual'; end if;
  if p_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
    raise exception 'unsupported leave type' using errcode = '22023';
  end if;

  if p_start_date is null or p_end_date is null then
    raise exception 'leave start and end dates are required' using errcode = '22023';
  end if;
  if p_end_date < p_start_date then
    raise exception 'leave end date cannot precede start date' using errcode = '22023';
  end if;

  -- السماح للإدارة بتسجيل الإجازات عن أي يوم خلال الشهر الحالي
  if p_start_date < v_month_start then
    raise exception 'لا يمكن تسجيل إجازة عن أشهر سابقة' using errcode = '22023';
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

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  v_row := public._submit_request_for(
    p_employee_id,
    'leave',
    null,
    v_manager,
    coalesce(trim(p_title), format('%s — %s',
      coalesce((select lt.name_ar from public.leave_types lt where lt.code = p_leave_type limit 1), 'إجازة'),
      to_char(p_start_date, 'YYYY-MM-DD'))),
    trim(p_reason),
    v_payload);

  insert into public.leave_requests(
    request_id, employee_id, leave_type_id, start_date, end_date,
    days_count, duration_unit, handover_notes, substitute_employee_id, created_by)
  values(
    v_row.id, p_employee_id, v_leave_type_id, p_start_date, p_end_date,
    v_days, 'day', nullif(p_handover_notes,''), p_substitute_employee_id, auth.uid());

  if p_leave_type = 'casual' then
    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
      where id = v_row.id returning * into v_row;
    update public.request_steps
      set status = 'skipped', acted_at = now(), acted_by = v_me,
          comment = 'تنفيذ فوري لإجازة عارضة من الإدارة', updated_at = now()
      where request_id = v_row.id and status in ('active','pending');
    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
      where request_id = v_row.id and status = 'running';
    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
    values(
      v_row.id, v_me, 'system', 'pending', 'approved',
      'تنفيذ فوري لإجازة عارضة مسجلة من الإدارة',
      jsonb_build_object('immediate', true, 'adminCreated', true), auth.uid());
  end if;

  perform public.log_audit_event(
    'leave.admin_created', 'workflow', 'info', 'requests', v_row.id,
    'إنشاء إجازة بدل الموظف',
    format('الموظف: %s | النوع: %s | من %s إلى %s', p_employee_id, p_leave_type, p_start_date, p_end_date),
    jsonb_build_object('employeeId', p_employee_id, 'leaveType', p_leave_type, 'days', v_days));

  return v_row;
end;
$$;

revoke all on function public.admin_create_leave_request(uuid, text, date, date, text, text, text, uuid) from public, anon;
grant execute on function public.admin_create_leave_request(uuid, text, date, date, text, text, text, uuid) to authenticated;

create or replace function public.delete_department_admin(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_blockers text[] := array[]::text[];
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('organization.department.manage')
    or public.has_permission('organization.unit.manage')
  ) then
    raise exception 'إدارة الأقسام مرفوضة' using errcode = '42501';
  end if;

  select d.name into v_name from public.departments d where d.id = p_id;
  if v_name is null then
    raise exception 'الإدارة غير موجودة' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.departments c where c.parent_id = p_id) then
    v_blockers := array_append(v_blockers, 'إدارات فرعية');
  end if;
  if exists (select 1 from public.employees e where e.department_id = p_id and not e.is_deleted) then
    v_blockers := array_append(v_blockers, 'موظفون مسندون');
  end if;
  if exists (select 1 from public.employee_departments ed where ed.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'إسنادات متعددة للموظفين');
  end if;
  if exists (select 1 from public.positions p where p.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'مناصب مرتبطة');
  end if;
  if exists (select 1 from public.teams t where t.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'فرق');
  end if;
  if exists (select 1 from public.job_requisitions j where j.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'طلبات توظيف');
  end if;
  if exists (select 1 from public.association_projects ap where ap.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'مشروعات');
  end if;
  if exists (select 1 from public.workforce_plans wp where wp.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'خطط القوى العاملة');
  end if;
  if exists (select 1 from public.capacity_snapshots cs where cs.department_id = p_id) then
    v_blockers := array_append(v_blockers, 'لقطات السعة');
  end if;

  if array_length(v_blockers, 1) > 0 then
    raise exception 'لا يمكن حذف الإدارة «%» لأنها مرتبطة بـ: %',
      v_name, array_to_string(v_blockers, '، ') using errcode = '23514';
  end if;

  delete from public.departments where id = p_id;
end;
$$;

revoke execute on function public.delete_department_admin(uuid) from public, anon;
grant execute on function public.delete_department_admin(uuid) to authenticated;

create or replace function public.delete_job_title(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_blockers text[] := array[]::text[];
begin
  if not (public.current_is_full_access() or public.has_permission('organization.job_title.manage')) then
    raise exception 'إدارة المسميات الوظيفية مرفوضة' using errcode = '42501';
  end if;

  select jt.name into v_name from public.job_titles jt where jt.id = p_id;
  if v_name is null then
    raise exception 'المسمى الوظيفي غير موجود' using errcode = 'P0002';
  end if;

  if exists (select 1 from public.employees e where e.job_title_id = p_id and not e.is_deleted) then
    v_blockers := array_append(v_blockers, 'موظفون حاملون له');
  end if;
  if exists (select 1 from public.positions p where p.job_title_id = p_id) then
    v_blockers := array_append(v_blockers, 'مناصب مرتبطة به');
  end if;

  if array_length(v_blockers, 1) > 0 then
    raise exception 'لا يمكن حذف المسمى الوظيفي «%» لأنه مرتبط بـ: %',
      v_name, array_to_string(v_blockers, '، ') using errcode = '23514';
  end if;

  delete from public.job_titles where id = p_id;
end;
$$;

revoke execute on function public.delete_job_title(uuid) from public, anon;
grant execute on function public.delete_job_title(uuid) to authenticated;

commit;
