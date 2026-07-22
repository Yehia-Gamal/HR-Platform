-- Migration 0013: Foundation access context + transactional employee provisioning.
-- This supports the first vertical slice shared by React Web and Flutter.

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
  v_roles text[] := '{}'::text[];
  v_permissions text[] := '{}'::text[];
  v_workspaces text[] := '{}'::text[];
  v_default_workspace text := 'employee';
  v_is_full boolean := false;
  v_is_executive boolean := false;
  v_is_manager boolean := false;
  v_is_hr boolean := false;
  v_is_main_admin boolean := false;
  v_is_committee boolean := false;
  v_is_field_operations boolean := false;
begin
  if v_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  select p.employee_id, coalesce(e.full_name_ar, 'مستخدم النظام'), e.employee_code
    into v_employee_id, v_display_name, v_employee_code
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
  v_is_manager := v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager',
    'operations-manager', 'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_hr := v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];
  v_is_field_operations := v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];

  if v_employee_id is not null and not v_is_executive then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager then v_workspaces := array_append(v_workspaces, 'manager'); end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  if v_is_hr then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee then v_workspaces := array_append(v_workspaces, 'committee'); end if;
  if v_is_field_operations then v_workspaces := array_append(v_workspaces, 'field_operations'); end if;

  if v_is_executive then
    v_default_workspace := 'executive';
  elsif v_is_main_admin then
    v_default_workspace := 'main_admin';
  elsif v_is_hr then
    v_default_workspace := 'hr';
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
    'roles', to_jsonb(v_roles),
    'permissions', to_jsonb(v_permissions),
    'workspaces', to_jsonb(v_workspaces),
    'defaultWorkspace', v_default_workspace,
    'attendancePolicy', jsonb_build_object(
      'attendanceRequired', not v_is_executive and v_employee_id is not null,
      'selfPunchEnabled', not v_is_executive and v_employee_id is not null,
      'liveLocationResponseEnabled', not v_is_executive and v_employee_id is not null
    )
  );
end;
$$;

revoke all on function public.get_my_access_context() from public;
grant execute on function public.get_my_access_context() to authenticated;

create or replace function public.provision_employee_record(
  p_actor_user_id uuid,
  p_user_id uuid,
  p_full_name_ar text,
  p_full_name_en text,
  p_employee_code text,
  p_phone_e164 text,
  p_role_slug text,
  p_manager_employee_id uuid default null,
  p_department_id uuid default null,
  p_team_id uuid default null,
  p_branch_id uuid default null,
  p_work_site_id uuid default null,
  p_job_title_id uuid default null,
  p_position_id uuid default null,
  p_grade_id uuid default null,
  p_employment_type_id uuid default null,
  p_hire_date date default null,
  p_invitation_pending boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_id uuid;
  v_profile_status text;
  v_employee_status text;
begin
  if p_actor_user_id is null or p_user_id is null then
    raise exception 'actor and user are required';
  end if;

  select id into v_role_id
  from public.roles
  where slug = p_role_slug;

  if v_role_id is null then
    raise exception 'unknown role slug: %', p_role_slug using errcode = '22023';
  end if;

  if exists (select 1 from public.employees where employee_code = p_employee_code) then
    raise exception 'employee code already exists' using errcode = '23505';
  end if;

  if p_manager_employee_id is not null and not exists (
    select 1 from public.employees
    where id = p_manager_employee_id and is_active = true and is_deleted = false
  ) then
    raise exception 'manager is not an active employee' using errcode = '23503';
  end if;

  v_profile_status := case when p_invitation_pending then 'pending' else 'active' end;
  v_employee_status := case when p_invitation_pending then 'invited' else 'active' end;

  insert into public.employees (
    user_id, employee_code, full_name_ar, full_name_en, phone_e164,
    job_title_id, position_id, grade_id, department_id, team_id,
    branch_id, work_site_id, employment_type_id, hire_date,
    status, is_active, is_deleted, created_by
  ) values (
    p_user_id, trim(p_employee_code), trim(p_full_name_ar), nullif(trim(p_full_name_en), ''),
    p_phone_e164, p_job_title_id, p_position_id, p_grade_id,
    p_department_id, p_team_id, p_branch_id, p_work_site_id,
    p_employment_type_id, p_hire_date, v_employee_status, true, false, p_actor_user_id
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
$$;

revoke all on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean
) from public, anon, authenticated;
grant execute on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean
) to service_role;

comment on function public.get_my_access_context() is
  'Returns the server-authored roles, permissions, workspaces and attendance policy for the current session.';
comment on function public.provision_employee_record(
  uuid, uuid, text, text, text, text, text, uuid, uuid, uuid, uuid,
  uuid, uuid, uuid, uuid, uuid, date, boolean
) is 'Service-role-only transactional provisioning after creating an auth user.';
