-- ============================================================================
-- Migration 0129: تعديل بيانات الموظف + إثراء قائمة الموظفين
--   • update_employee_admin: تعديل بيانات الموظف الوظيفية والشخصية بنظام patch
--   • get_employee_360: تحديث ليُعيد معرّفات FK خام (للتعديل)
--   • get_employees_enriched: قائمة موظفين مُثراة بالإدارة والمسمى الوظيفي
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) update_employee_admin — تعديل بيانات الموظف بأسلوب JSONB patch
--    يقبل حقول التعديل ككائن JSONB حيث المفاتيح الموجودة فقط تُحدّث.
--    يتطلب صلاحية update_basic أو update_sensitive حسب الحقل.
-- ----------------------------------------------------------------------------
create or replace function public.update_employee_admin(
  p_employee_id uuid,
  p_changes jsonb,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_has_sensitive boolean;
  v_has_basic boolean;
  v_employee public.employees;
  v_updates text[] := '{}';
  -- حقول شخصية (update_basic كافٍ)
  v_basic_fields text[] := array['fullNameAr','fullNameEn','phoneE164','photoUrl'];
  -- حقول وظيفية (تتطلب update_sensitive أو full_access)
  v_sensitive_fields text[] := array[
    'departmentId','teamId','branchId','workSiteId',
    'jobTitleId','positionId','gradeId','employmentTypeId',
    'hireDate','contractEnd','probationEnd','status'
  ];
  v_key text;
  v_has_sensitive_change boolean := false;
  v_old_snapshot jsonb;
begin
  -- التحقق من المُعرّفات
  if v_actor_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;
  if p_changes is null or p_changes = '{}'::jsonb then
    raise exception 'no_changes_provided' using errcode = '22023';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'change_reason_required' using errcode = '22023';
  end if;

  -- التحقق من الصلاحيات
  v_has_sensitive := public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive');
  v_has_basic := v_has_sensitive
    or public.has_permission('people.employee.update_basic');

  if not v_has_basic then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;

  -- التحقق من النطاق
  if not public.can_access_employee(p_employee_id, 'people.employee.update_basic')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode = '42501';
  end if;

  -- فحص ما إذا كانت التغييرات تشمل حقولاً حساسة
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

  -- تحميل الموظف مع قفل
  select * into v_employee
  from public.employees
  where id = p_employee_id and is_deleted = false
  for update;

  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;

  -- حفظ لقطة القيم القديمة
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

  -- تطبيق التغييرات — كل حقل يُبنى ديناميكياً عبر UPDATE مباشر
  -- استخدام CASE لتطبيق الحقول الموجودة فقط في p_changes
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
    -- تغيير الحالة يخضع لفحص إضافي
    status = case when p_changes ? 'status'
      then (p_changes->>'status') else status end,
    updated_at = now()
  where id = p_employee_id;

  -- فحص تكرار الهاتف بعد التحديث (إذا تغيّر)
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

  -- التدقيق
  perform public.log_audit_event(
    'employee_updated', 'people', 'info', 'employees', p_employee_id,
    'تعديل بيانات الموظف',
    trim(p_reason),
    jsonb_build_object('before', v_old_snapshot, 'after', p_changes)
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'updatedFields', (select jsonb_agg(k) from jsonb_object_keys(p_changes) as k),
    'updatedAt', now()
  );
end;
$$;

revoke all on function public.update_employee_admin(uuid, jsonb, text) from public, anon;
grant execute on function public.update_employee_admin(uuid, jsonb, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 2) get_employee_360 — تحديث ليُعيد معرّفات FK خام بجانب الأسماء
--    هذا يسمح لنموذج التعديل بتعبئة القوائم المنسدلة بالقيم الحالية.
-- ----------------------------------------------------------------------------
create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
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
    -- المعرّفات الخام — للاستخدام في نموذج التعديل
    'departmentId', e.department_id,
    'teamId', e.team_id,
    'branchId', e.branch_id,
    'workSiteId', e.work_site_id,
    'jobTitleId', e.job_title_id,
    'positionId', e.position_id,
    'gradeId', e.grade_id,
    'employmentTypeId', e.employment_type_id,
    'managerId', manager_rel.manager_employee_id,
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
        select * from public.requests where employee_id=e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', task.id, 'title', task.title, 'status', task.status,
        'priority', task.priority, 'dueDate', task.due_date
      ) order by task.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id=e.id order by created_at desc limit 10
      ) task
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
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
  left join public.profiles profile on profile.employee_id=e.id
  left join lateral (
    select me.full_name_ar, mr.manager_employee_id
    from public.manager_relations mr
    join public.employees me on me.id=mr.manager_employee_id
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc limit 1
  ) manager_rel on true
  -- تغيير: manager → manager_rel لتضمين manager_employee_id أيضاً
  where e.id=p_employee_id and e.is_deleted=false;

  if v_result is null then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

revoke all on function public.get_employee_360(uuid) from public;
grant execute on function public.get_employee_360(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 3) get_employees_enriched — قائمة موظفين مُثراة بأسماء الإدارة والمسمى الوظيفي
--    تحل محل الاستعلام المباشر للجدول (الذي لا يعيد الأسماء) مع RLS/scope checking.
-- ----------------------------------------------------------------------------
create or replace function public.get_employees_enriched(
  p_search text default null,
  p_status text default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(row_data order by row_data->>'fullNameAr')
    from (
      select jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', d.name,
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at
      ) as row_data
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.teams t on t.id = e.team_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      where e.is_deleted = false
        and (p_status is null or e.status = p_status)
        and (v_search is null
          or lower(e.full_name_ar) like '%' || v_search || '%'
          or lower(coalesce(e.full_name_en, '')) like '%' || v_search || '%'
          or lower(e.employee_code) like '%' || v_search || '%'
          or e.phone_e164 like '%' || v_search || '%')
        and (public.current_is_full_access()
          or public.can_access_employee(e.id, 'people.employee.read'))
      order by e.created_at desc
      limit greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_employees_enriched(text, text, integer) from public, anon;
grant execute on function public.get_employees_enriched(text, text, integer) to authenticated;

notify pgrst, 'reload schema';
