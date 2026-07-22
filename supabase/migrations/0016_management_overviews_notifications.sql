begin;

-- Canonical read models for the remaining operational web workspaces.
-- These functions keep UI queries stable and ensure sensitive overviews are gated server-side.

create or replace function public.get_dashboard_overview(p_workspace text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
begin
  if p_workspace not in ('hr','main_admin') then
    raise exception 'invalid workspace' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'employees', (select count(*) from public.employees),
    'activeEmployees', (select count(*) from public.employees where status = 'active'),
    'pendingRequests', (select count(*) from public.requests where status = 'pending'),
    'attendancePendingReview', (select count(*) from public.attendance_events where requires_review = true),
    'pendingKpi', (select count(*) from public.kpi_evaluations where current_stage <> 'finalized'),
    'openRequisitions', (select count(*) from public.job_requisitions where status in ('pending','approved','posted')),
    'urgentActions', (
      select count(*) from public.requests
      where status = 'pending' and decision_due_at is not null and decision_due_at < now() + interval '4 hours'
    ),
    'publishedDecisions', (select count(*) from public.administrative_decisions where status = 'published'),
    'unresolvedErrors', case when p_workspace = 'main_admin'
      then (select count(*) from public.app_error_events where resolved = false)
      else 0 end,
    'lastUpdatedAt', now()
  );
end;
$$;
grant execute on function public.get_dashboard_overview(text) to authenticated;

create or replace function public.get_organization_overview()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'legalEntities', (select count(*) from public.legal_entities where is_active = true),
    'branches', (select count(*) from public.branches where is_active = true),
    'workSites', (select count(*) from public.work_sites where is_active = true),
    'departments', (select count(*) from public.departments where is_active = true),
    'teams', (select count(*) from public.teams where is_active = true),
    'positions', (select count(*) from public.positions where is_active = true),
    'vacantPositions', (
      select coalesce(sum(greatest(p.headcount - coalesce(x.assigned, 0), 0)), 0)
      from public.positions p
      left join (
        select position_id, count(*)::integer assigned
        from public.employees
        where status = 'active' and position_id is not null
        group by position_id
      ) x on x.position_id = p.id
      where p.is_active = true
    ),
    'managerRelations', (
      select count(*) from public.manager_relations
      where effective_from <= current_date and (effective_to is null or effective_to >= current_date)
    ),
    'recentDepartments', coalesce((
      select jsonb_agg(jsonb_build_object('id', q.id, 'name', q.name, 'active', q.is_active) order by q.created_at desc)
      from (select id, name, is_active, created_at from public.departments order by created_at desc limit 6) q
    ), '[]'::jsonb),
    'recentPositions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id, 'code', q.code, 'title', q.name,
        'status', case when q.is_active then 'active' else 'inactive' end
      ) order by q.created_at desc)
      from (select id, code, name, is_active, created_at from public.positions order by created_at desc limit 6) q
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
$$;
grant execute on function public.get_organization_overview() to authenticated;

create or replace function public.get_access_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.audit.read'])) then
    raise exception 'access overview denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'roles', (select count(*) from public.roles),
    'permissions', (select count(*) from public.permissions),
    'activeAssignments', (select count(*) from public.user_roles where effective_from <= now() and (effective_to is null or effective_to > now())),
    'sensitivePermissions', (select count(*) from public.permissions where is_sensitive = true or risk_level in ('sensitive','critical')),
    'expiringAssignments', (select count(*) from public.user_roles where effective_to between now() and now() + interval '30 days'),
    'rolesList', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'isFullAccess', r.is_full_access,
        'permissionCount', (select count(*) from public.role_permissions rp where rp.role_id = r.id),
        'userCount', (select count(*) from public.user_roles ur where ur.role_id = r.id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now()))
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;
revoke execute on function public.get_access_overview() from public;
grant execute on function public.get_access_overview() to authenticated;

create or replace function public.get_recruitment_overview()
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'requisitions', (select count(*) from public.job_requisitions),
    'pendingRequisitions', (select count(*) from public.job_requisitions where status = 'pending'),
    'openPostings', (select count(*) from public.job_postings where status = 'published' and (closes_at is null or closes_at >= now())),
    'candidates', (select count(*) from public.candidates),
    'activeApplications', (select count(*) from public.applications where status = 'active'),
    'hiredApplications', (select count(*) from public.applications where status = 'hired'),
    'pipeline', coalesce((
      select jsonb_agg(jsonb_build_object('stage', q.status, 'count', q.total) order by q.status)
      from (select status, count(*)::integer total from public.applications group by status) q
    ), '[]'::jsonb),
    'recentRequisitions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id, 'title', q.title, 'department', q.department,
        'headcount', q.headcount, 'status', q.status, 'createdAt', q.created_at
      ) order by q.created_at desc)
      from (
        select r.id, r.title, d.name department, r.headcount, r.status, r.created_at
        from public.job_requisitions r join public.departments d on d.id = r.department_id
        order by r.created_at desc limit 8
      ) q
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
$$;
grant execute on function public.get_recruitment_overview() to authenticated;

create or replace function public.get_system_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['system.settings.read','settings.read','system.manage','system.error.view'])) then
    raise exception 'system overview denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'enabledFlags', (select count(*) from public.feature_flags where is_enabled = true),
    'totalFlags', (select count(*) from public.feature_flags),
    'unresolvedErrors', (select count(*) from public.app_error_events where resolved = false),
    'fatalErrors', (select count(*) from public.app_error_events where resolved = false and level = 'fatal'),
    'latestBackupStatus', (select status from public.system_backups order by created_at desc limit 1),
    'latestBackupAt', (select coalesce(finished_at, started_at, created_at) from public.system_backups order by created_at desc limit 1),
    'settingsCount', (select count(*) from public.system_settings),
    'recentErrors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', q.id, 'level', q.level, 'source', q.source,
        'message', q.message, 'occurredAt', q.occurred_at
      ) order by q.occurred_at desc)
      from (
        select id, level, source, message, occurred_at
        from public.app_error_events where resolved = false order by occurred_at desc limit 8
      ) q
    ), '[]'::jsonb),
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'key', f.flag_key, 'name', f.name_ar,
        'enabled', f.is_enabled, 'rolloutPercent', f.rollout_percent, 'environment', f.environment
      ) order by f.flag_key)
      from public.feature_flags f
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;
revoke execute on function public.get_system_overview() from public;
grant execute on function public.get_system_overview() to authenticated;

create or replace function public.get_my_notifications(p_limit integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', n.id, 'title', n.title, 'body', n.body, 'category', n.category,
    'priority', n.priority, 'actionUrl', n.action_url, 'isRead', n.is_read, 'createdAt', n.created_at
  ) order by n.created_at desc), '[]'::jsonb)
  from (
    select * from public.notifications
    where recipient_user_id = auth.uid() and is_archived = false
    order by created_at desc limit greatest(1, least(coalesce(p_limit, 50), 200))
  ) n;
$$;
grant execute on function public.get_my_notifications(integer) to authenticated;

create or replace function public.mark_my_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
  update public.notifications
  set is_read = true, read_at = coalesce(read_at, now()), updated_at = now()
  where recipient_user_id = auth.uid()
    and is_read = false
    and (p_ids is null or id = any(p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function public.mark_my_notifications_read(uuid[]) to authenticated;

commit;
