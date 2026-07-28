-- 0151: الأدمن الرئيسي يرى لوحة HR أيضاً
--
-- قبل هذا التغيير، مساحة `hr` كانت تُمنح فقط لأدوار HR (hr-manager / hr-specialist).
-- الأدمن الرئيسي (full-access أو أدوار إدارية) كان يرى مساحة `main_admin` فقط ولا يستطيع
-- التبديل إلى لوحة الموارد البشرية.
--
-- الإصلاح: عندما يكون المستخدم main_admin، يحصل على مساحة `hr` أيضاً.
-- مستخدم HR العادي لا يتأثر — يرى مساحته فقط.

create or replace function public.get_my_access_context()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
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
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code, e.photo_url
    into v_employee_id, v_display_name, v_employee_code, v_photo_url
  from public.profiles p
  left join public.employees e on e.id = p.employee_id
  where p.id = v_user_id
    and p.status in ('active', 'pending');

  if not found then
    raise exception 'active profile not found' using errcode = '42501';
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

  -- ═══ مساحات العمل ═══
  -- كل من لديه سجل موظف (ما عدا التنفيذي) يحصل على مساحة employee
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
  -- 0151: الأدمن الرئيسي يرى لوحة HR أيضاً
  if v_is_hr or v_is_main_admin then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee and not v_is_hr and not v_is_main_admin then
    v_workspaces := array_append(v_workspaces, 'committee');
  end if;

  -- ═══ المساحة الافتراضية ═══
  -- الأدمن يدخل على لوحة الإدارة افتراضياً ويستطيع التبديل إلى HR
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
    raise exception 'no workspace assigned' using errcode = '42501';
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
      -- البصمة تظهر لكل الموظفين ما عدا التنفيذي و الأدمن الرئيسي (سكرتير/مشرف)
      'attendanceRequired', not v_is_executive and not v_is_main_admin and v_employee_id is not null,
      'selfPunchEnabled', not v_is_executive and not v_is_main_admin and v_employee_id is not null,
      'liveLocationResponseEnabled', not v_is_executive and not v_is_main_admin and v_employee_id is not null
    )
  );
end;
$$;

revoke all on function public.get_my_access_context() from public, anon;
grant execute on function public.get_my_access_context() to authenticated;
