-- The office display reads approved projects without granting project management.
create or replace function public.get_executive_projects_display()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_warning integer;
  v_critical integer;
begin
  if auth.uid() is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not (coalesce(public.get_my_access_context()->'workspaces', '[]'::jsonb) ? 'executive') then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select warning_days, critical_days into v_warning, v_critical
  from public.association_project_settings where id;

  return jsonb_build_object(
    'projects', coalesce((
      select jsonb_agg(
        (public._association_project_json(p.id, coalesce(v_warning, 7), coalesce(v_critical, 14))
          - array['members', 'departments', 'createdBy'])
        || jsonb_build_object(
          'description', null, 'lastUpdateNote', null, 'approvedBy', null,
          'rejectionReason', null, 'myRole', null, 'canManage', false, 'canEdit', false
        )
        order by coalesce(p.updated_at, p.created_at) desc, p.id
      )
      from public.association_projects p
      where p.approval_status = 'approved' and p.status <> 'cancelled'
    ), '[]'::jsonb),
    'recentUpdates', coalesce((
      select jsonb_agg(result.update_data order by result.created_at desc, result.id)
      from (
        select u.id, u.created_at, jsonb_build_object(
          'id', u.id, 'projectId', p.id, 'projectName', p.name, 'projectCode', p.code,
          'note', u.note, 'progress', u.progress, 'statusChange', u.status_change,
          'authorName', '', 'createdAt', u.created_at
        ) as update_data
        from public.association_project_updates u
        join public.association_projects p on p.id = u.project_id
        where p.approval_status = 'approved' and p.status <> 'cancelled'
        order by u.created_at desc, u.id
        limit 30
      ) result
    ), '[]'::jsonb),
    'lastUpdatedAt', now(),
    'canCreate', false
  );
end;
$$;

revoke all on function public.get_executive_projects_display() from public, anon;
grant execute on function public.get_executive_projects_display() to authenticated;
