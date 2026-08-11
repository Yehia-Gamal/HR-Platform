-- migration: 0378
-- description: mission approver — guaranteed fallback to hr-manager + clear error if none found

begin;

create or replace function public.resolve_request_approver(
  p_employee_id  integer,
  p_request_type text
) returns integer  -- returns approver employee_id or raises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_approver_id integer;
begin
  -- 1. direct manager
  select manager_employee_id into v_approver_id
  from public.employees
  where id = p_employee_id and is_active = true;

  if v_approver_id is not null then
    return v_approver_id;
  end if;

  -- 2. executive-director by seniority
  select e.id into v_approver_id
  from public.employees e
  join public.employee_roles er on er.employee_id = e.id
  join public.roles r on r.id = er.role_id
  where r.slug = 'executive-director'
    and e.is_active = true
  order by e.hire_date asc
  limit 1;

  if v_approver_id is not null then
    return v_approver_id;
  end if;

  -- 3. any employee with requests.approve permission in same org scope
  select e.id into v_approver_id
  from public.employees e
  join public.employee_roles er on er.employee_id = e.id
  join public.roles r on r.id = er.role_id
  join public.role_permissions rp on rp.role_id = r.id
  join public.permissions p on p.id = rp.permission_id
  where p.slug = 'requests.approve'
    and e.is_active = true
  order by e.hire_date asc
  limit 1;

  if v_approver_id is not null then
    return v_approver_id;
  end if;

  -- 4. hr-manager fallback (NEW — guarantees mission never orphaned)
  select e.id into v_approver_id
  from public.employees e
  join public.employee_roles er on er.employee_id = e.id
  join public.roles r on r.id = er.role_id
  where r.slug = 'hr-manager'
    and e.is_active = true
  order by e.hire_date asc
  limit 1;

  if v_approver_id is not null then
    return v_approver_id;
  end if;

  -- 5. hr-specialist fallback
  select e.id into v_approver_id
  from public.employees e
  join public.employee_roles er on er.employee_id = e.id
  join public.roles r on r.id = er.role_id
  where r.slug = 'hr-specialist'
    and e.is_active = true
  order by e.hire_date asc
  limit 1;

  if v_approver_id is not null then
    return v_approver_id;
  end if;

  -- no approver found — raise instead of returning null
  raise exception 'NO_APPROVER_FOUND: no active approver available for employee_id=% request_type=%',
    p_employee_id, p_request_type;
end;
$$;

revoke all on function public.resolve_request_approver(integer,text) from anon, authenticated;
grant execute on function public.resolve_request_approver(integer,text) to authenticated;

commit;
