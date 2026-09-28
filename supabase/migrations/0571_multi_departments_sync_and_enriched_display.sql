-- =====================================================================
-- 0571: دعم إسناد وتعديل أكثر من إدارة للموظف وعرضها في دليل الموظفين
-- =====================================================================

begin;

-- ─────────────────────────────────────────────────────────────────────
-- 1) دالة المزامنة الشاملة لإدارات الموظف (sync_employee_departments)
-- ─────────────────────────────────────────────────────────────────────
create or replace function public.sync_employee_departments(
  p_employee_id uuid,
  p_department_ids uuid[],
  p_primary_department_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor_id uuid := auth.uid();
  v_primary uuid;
  v_dept_id uuid;
  v_dept_count integer := 0;
begin
  if v_actor_id is null and current_user not in ('postgres', 'service_role') then
    raise exception 'غير مصرح' using errcode = '42501';
  end if;

  if p_employee_id is null then
    raise exception 'employee_id_required' using errcode = '22023';
  end if;

  if v_actor_id is not null and not (
    public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive')
  ) then
    raise exception 'غير مصرح لك بتعديل إدارات الموظف' using errcode = '42501';
  end if;

  -- التحقق من وجود الموظف
  if not exists (select 1 from public.employees where id = p_employee_id and is_deleted = false) then
    raise exception 'الموظف غير موجود أو محذوف' using errcode = 'P0002';
  end if;

  -- تحديد الإدارة الأساسية
  if p_primary_department_id is not null and p_primary_department_id = any(p_department_ids) then
    v_primary := p_primary_department_id;
  elsif array_length(p_department_ids, 1) > 0 then
    v_primary := p_department_ids[1];
  else
    v_primary := null;
  end if;

  -- 1) تحديث الإدارة الأساسية في جدول الموظفين
  update public.employees
     set department_id = v_primary,
         updated_at = now()
   where id = p_employee_id;

  -- 2) حذف أي إدارات مسندة لم تعد موجودة في القائمة المحددة
  if p_department_ids is null or array_length(p_department_ids, 1) is null then
    delete from public.employee_departments where employee_id = p_employee_id;
  else
    delete from public.employee_departments
     where employee_id = p_employee_id
       and not (department_id = any(p_department_ids));

    -- 3) إدخال أو تحديث الإدارات المحددة
    foreach v_dept_id in array p_department_ids loop
      insert into public.employee_departments (
        employee_id,
        department_id,
        is_primary,
        assigned_by,
        assigned_at,
        allocation_percentage,
        start_date
      )
      values (
        p_employee_id,
        v_dept_id,
        (v_dept_id = v_primary),
        v_actor_id,
        now(),
        case when v_dept_id = v_primary then 100 else 50 end,
        current_date
      )
      on conflict (employee_id, department_id) do update set
        is_primary = (excluded.department_id = v_primary);
    end loop;
    v_dept_count := array_length(p_department_ids, 1);
  end if;

  -- 4) تسجيل عملية التدقيق الإداري
  perform public.log_audit_event(
    'employee.sync_departments',
    'security',
    'info',
    'employees',
    p_employee_id,
    'تحديث وتعيين إدارات الموظف المتعددة',
    null,
    jsonb_build_object(
      'employee_id', p_employee_id,
      'department_ids', p_department_ids,
      'primary_department_id', v_primary,
      'count', v_dept_count
    )
  );

  return jsonb_build_object(
    'success', true,
    'primaryDepartmentId', v_primary,
    'count', v_dept_count,
    'message', format('تم تحديث إدارات الموظف بنجاح (%s إدارة)', v_dept_count)
  );
end;
$$;

revoke all on function public.sync_employee_departments(uuid, uuid[], uuid) from public, anon;
grant execute on function public.sync_employee_departments(uuid, uuid[], uuid) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 2) تحديث get_employees_enriched لتجميع كافة الإدارات المسندة
-- ─────────────────────────────────────────────────────────────────────
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
  v_is_org_admin boolean := false;
begin
  if auth.uid() is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  v_is_org_admin := public.current_is_full_access()
    or public.has_permission('organization.org_chart.read');

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
        'department', coalesce(
          (
            select string_agg(d_sub.name, ' / ' order by ed_sub.is_primary desc, d_sub.name)
            from public.employee_departments ed_sub
            join public.departments d_sub on d_sub.id = ed_sub.department_id
            where ed_sub.employee_id = e.id
          ),
          d.name
        ),
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
        and not public.is_employee_executive(e.id)
        and (p_status is null or e.status = p_status)
        and (
          v_search is null
          or lower(e.full_name_ar) like '%' || v_search || '%'
          or lower(coalesce(e.full_name_en, '')) like '%' || v_search || '%'
          or lower(e.employee_code) like '%' || v_search || '%'
          or e.phone_e164 like '%' || v_search || '%'
          or lower(coalesce(d.name, '')) like '%' || v_search || '%'
          or exists (
            select 1 from public.employee_departments ed_srch
            join public.departments d_srch on d_srch.id = ed_srch.department_id
            where ed_srch.employee_id = e.id and lower(d_srch.name) like '%' || v_search || '%'
          )
        )
        and (
          v_is_org_admin
          or public.can_access_employee(e.id, 'people.employee.read')
        )
      order by e.created_at desc
      limit greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_employees_enriched(text, text, integer) from public, anon;
grant execute on function public.get_employees_enriched(text, text, integer) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 3) إسناد إدارة الموارد البشرية لبلال الشاكر بجانب إدارة الميديا
-- ─────────────────────────────────────────────────────────────────────
do $$
declare
  v_belal_id uuid := '6a799235-31c1-4b7c-b0a3-93eaf30ea97a';
  v_media_id uuid := 'f9acdbca-314d-400a-8f0e-ab3054ce7009';
  v_hr_id uuid := 'dd4e1467-1014-4a0c-a05f-d6c56017f183';
begin
  if exists (select 1 from public.employees where id = v_belal_id) then
    -- إسناد الميديا كأساسية
    insert into public.employee_departments (employee_id, department_id, is_primary, assigned_at, allocation_percentage, start_date)
    values (v_belal_id, v_media_id, true, now(), 50, current_date)
    on conflict (employee_id, department_id) do update set is_primary = true;

    -- إسناد الموارد البشرية كإدارة مشتركة
    insert into public.employee_departments (employee_id, department_id, is_primary, assigned_at, allocation_percentage, start_date)
    values (v_belal_id, v_hr_id, false, now(), 50, current_date)
    on conflict (employee_id, department_id) do nothing;
  end if;
end $$;

commit;
