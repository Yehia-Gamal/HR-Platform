-- 0084: HR-scoped, audited direct-manager changes through one transaction.

create or replace function public.change_employee_manager_admin(
  p_employee_id uuid,
  p_manager_id uuid,
  p_reason text
)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_employee public.employees;
  v_old_manager uuid;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('people.employee.update_sensitive')
  ) then
    raise exception 'employee_update_not_allowed' using errcode = '42501';
  end if;
  if not public.can_access_employee(p_employee_id, 'people.employee.update_sensitive')
     and not public.current_is_full_access() then
    raise exception 'employee_outside_scope' using errcode = '42501';
  end if;
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'change_reason_required' using errcode = '22023';
  end if;
  if p_manager_id = p_employee_id then
    raise exception 'manager_cannot_be_self' using errcode = '22023';
  end if;

  select * into v_employee
  from public.employees
  where id = p_employee_id and is_deleted = false
  for update;
  if not found then
    raise exception 'employee_not_found' using errcode = 'P0002';
  end if;
  v_old_manager := v_employee.manager_id;

  if p_manager_id is not null then
    if not exists (
      select 1 from public.employees
      where id = p_manager_id and is_deleted = false and status = 'active' and is_active = true
    ) then
      raise exception 'manager_not_active' using errcode = '22023';
    end if;
    if exists (
      with recursive manager_chain(id) as (
        select p_manager_id
        union all
        select mr.manager_employee_id
        from public.manager_relations mr
        join manager_chain c on c.id = mr.employee_id
        where mr.relation_type = 'primary' and mr.effective_to is null
      )
      select 1 from manager_chain where id = p_employee_id
    ) then
      raise exception 'manager_cycle_not_allowed' using errcode = '22023';
    end if;
  end if;

  update public.employees
  set manager_id = p_manager_id, updated_at = now()
  where id = p_employee_id;

  update public.manager_relations
  set effective_to = current_date, updated_at = now()
  where employee_id = p_employee_id
    and relation_type = 'primary'
    and effective_to is null;

  if p_manager_id is not null then
    insert into public.manager_relations(
      employee_id, manager_employee_id, relation_type,
      effective_from, created_by
    ) values (
      p_employee_id, p_manager_id, 'primary', current_date, auth.uid()
    );
  end if;

  perform public.log_audit_event(
    'employee_manager_changed', 'people', 'warning', 'employees', p_employee_id,
    'تغيير المدير المباشر',
    jsonb_build_object('managerId', v_old_manager),
    jsonb_build_object('managerId', p_manager_id, 'reason', trim(p_reason))
  );

  return jsonb_build_object(
    'employeeId', p_employee_id,
    'previousManagerId', v_old_manager,
    'managerId', p_manager_id,
    'updatedAt', now()
  );
end;
$$;

revoke execute on function public.change_employee_manager_admin(uuid, uuid, text) from public, anon;
grant execute on function public.change_employee_manager_admin(uuid, uuid, text) to authenticated;
notify pgrst, 'reload schema';
