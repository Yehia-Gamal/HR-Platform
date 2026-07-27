-- Migration 0160: منح صلاحية التقييم الذاتي لدور الموظف.
-- الموظف يحتاج performance.kpi.self_assess ليتمكّن من تقييم نفسه.
-- الـ scope = 'self' لأنه يخص الموظف نفسه فقط.

do $$
declare
  v_role_id uuid;
  v_perm_id uuid;
begin
  select id into v_role_id from public.roles where slug = 'employee';
  if v_role_id is null then
    raise notice 'employee role not found — skipping';
    return;
  end if;

  select id into v_perm_id from public.permissions where code = 'performance.kpi.self_assess';
  if v_perm_id is null then
    raise notice 'performance.kpi.self_assess permission not found — skipping';
    return;
  end if;

  insert into public.role_permissions (role_id, permission_id, scope)
  values (v_role_id, v_perm_id, 'self')
  on conflict (role_id, permission_id, scope) do nothing;

  raise notice 'Granted performance.kpi.self_assess (self scope) to employee role';
end;
$$;
