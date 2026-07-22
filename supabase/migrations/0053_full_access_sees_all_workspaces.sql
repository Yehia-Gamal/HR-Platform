-- Migration 0053: full-access accounts see every workspace.
--
-- Before this change, get_my_access_context() derived the `hr` workspace only
-- from the hr-manager/hr-specialist roles, and `manager`/`executive` only from
-- their specific role slugs. A full-access role (e.g. `admin`, is_full_access)
-- therefore received only `main_admin` (plus `employee`) and could not switch
-- into the HR workspace in the web panel, even though it is authorized for
-- everything.
--
-- Fix: when the session has full access, enable the hr/manager/executive/
-- committee/field-operations workspace flags as well, so a full admin can open
-- every workspace. Non-full accounts are unaffected.

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

  -- A full-access session is authorized for every workspace; grant all the
  -- workspace flags so the panel can switch into any of them.
  v_is_executive := v_is_full or v_roles && array['executive-director', 'executive']::text[];
  v_is_manager := v_is_full or v_roles && array[
    'direct-manager', 'department-manager', 'branch-manager',
    'operations-manager', 'operations-manager-1', 'operations-manager-2'
  ]::text[];
  v_is_hr := v_is_full or v_roles && array['hr-manager', 'hr-specialist']::text[];
  v_is_main_admin := v_is_full or v_roles && array[
    'admin', 'super-admin', 'super_admin', 'system-admin',
    'technical-lead', 'executive-secretary'
  ]::text[];
  v_is_committee := v_is_full or v_roles && array[
    'committee-member', 'committee-chair', 'committee-secretary'
  ]::text[];
  v_is_field_operations := v_is_full or v_roles && array[
    'operations-officer', 'operations-manager',
    'operations-manager-1', 'operations-manager-2'
  ]::text[];

  -- Full-access keeps the employee workspace too (opens everything); otherwise
  -- executives skip it as before.
  if v_employee_id is not null and (v_is_full or not v_is_executive) then
    v_workspaces := array_append(v_workspaces, 'employee');
  end if;
  if v_is_manager then v_workspaces := array_append(v_workspaces, 'manager'); end if;
  if v_is_executive then v_workspaces := array_append(v_workspaces, 'executive'); end if;
  if v_is_hr then v_workspaces := array_append(v_workspaces, 'hr'); end if;
  if v_is_main_admin then v_workspaces := array_append(v_workspaces, 'main_admin'); end if;
  if v_is_committee then v_workspaces := array_append(v_workspaces, 'committee'); end if;
  if v_is_field_operations then v_workspaces := array_append(v_workspaces, 'field_operations'); end if;

  -- Full-access lands on main_admin by default. Otherwise keep the original
  -- precedence (executive > main_admin > hr > manager > employee).
  if v_is_full then
    v_default_workspace := 'main_admin';
  elsif v_is_executive then
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
