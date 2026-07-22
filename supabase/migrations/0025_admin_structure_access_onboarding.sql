begin;

-- ============================================================================
-- V8 Build 0.4: admin structure, role builder read model, recruitment and
-- onboarding operations. All writes are server-authoritative and audited.
-- ============================================================================

create or replace function public.get_organization_admin_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'organization.entity.read','organization.org_chart.read',
      'organization.department.manage','organization.position.manage',
      'organization.unit.manage'
    ])
  ) then
    raise exception 'organization catalog denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'entities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.code, 'name', e.name,
        'active', e.is_active
      ) order by e.name)
      from public.legal_entities e
    ), '[]'::jsonb),
    'branches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id, 'entityId', b.legal_entity_id, 'code', b.code,
        'name', b.name, 'active', b.is_active
      ) order by b.name)
      from public.branches b
    ), '[]'::jsonb),
    'departments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'entityId', d.legal_entity_id, 'branchId', d.branch_id,
        'parentId', d.parent_id, 'managerId', d.manager_id,
        'code', d.code, 'name', d.name, 'nameEn', d.name_en,
        'active', d.is_active,
        'employeeCount', (select count(*) from public.employees e where e.department_id = d.id and e.is_deleted = false),
        'positionCount', (select count(*) from public.positions p where p.department_id = d.id and p.is_active = true)
      ) order by d.name)
      from public.departments d
    ), '[]'::jsonb),
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', t.id, 'departmentId', t.department_id, 'parentId', t.parent_id,
        'leadId', t.lead_id, 'code', t.code, 'name', t.name,
        'active', t.is_active,
        'employeeCount', (select count(*) from public.employees e where e.team_id = t.id and e.is_deleted = false)
      ) order by t.name)
      from public.teams t
    ), '[]'::jsonb),
    'positions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'departmentId', p.department_id, 'teamId', p.team_id,
        'jobTitleId', p.job_title_id, 'gradeId', p.job_grade_id,
        'reportsToId', p.reports_to_position_id,
        'code', p.code, 'name', p.name, 'nameEn', p.name_en,
        'headcount', p.headcount, 'active', p.is_active,
        'assignedCount', (select count(*) from public.employees e where e.position_id = p.id and e.is_deleted = false and e.status <> 'terminated')
      ) order by p.name)
      from public.positions p
    ), '[]'::jsonb),
    'employees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'code', e.employee_code, 'name', e.full_name_ar,
        'departmentId', e.department_id, 'teamId', e.team_id,
        'positionId', e.position_id, 'active', e.is_active
      ) order by e.full_name_ar)
      from public.employees e where e.is_deleted = false
    ), '[]'::jsonb),
    'jobTitles', coalesce((
      select jsonb_agg(jsonb_build_object('id', j.id, 'name', j.name, 'active', j.is_active) order by j.name)
      from public.job_titles j
    ), '[]'::jsonb),
    'grades', coalesce((
      select jsonb_agg(jsonb_build_object('id', g.id, 'name', g.name, 'level', g.level, 'active', g.is_active) order by g.level, g.name)
      from public.job_grades g
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

create or replace function public.upsert_department_admin(
  p_id uuid,
  p_legal_entity_id uuid,
  p_branch_id uuid,
  p_parent_id uuid,
  p_manager_id uuid,
  p_code text,
  p_name text,
  p_name_en text default null,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.department.manage') or public.has_permission('organization.unit.manage')) then
    raise exception 'department management denied' using errcode = '42501';
  end if;
  if nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'department code and name are required' using errcode = '22023';
  end if;
  if p_legal_entity_id is null then
    raise exception 'legal entity is required' using errcode = '22023';
  end if;
  if p_id is not null and p_parent_id = p_id then
    raise exception 'department cannot be its own parent' using errcode = '22023';
  end if;

  if p_id is not null and p_parent_id is not null then
    with recursive descendants as (
      select d.id from public.departments d where d.parent_id = p_id
      union all
      select d.id from public.departments d join descendants x on d.parent_id = x.id
    )
    select exists(select 1 from descendants where id = p_parent_id) into v_cycle;
    if v_cycle then
      raise exception 'department hierarchy cycle detected' using errcode = '22023';
    end if;
  end if;

  if p_id is null then
    insert into public.departments(
      legal_entity_id, branch_id, parent_id, manager_id,
      code, name, name_en, is_active, created_by
    ) values (
      p_legal_entity_id, p_branch_id, p_parent_id, p_manager_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.departments set
      legal_entity_id = p_legal_entity_id,
      branch_id = p_branch_id,
      parent_id = p_parent_id,
      manager_id = p_manager_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id
    returning id into v_id;
    if v_id is null then raise exception 'department not found' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.upsert_position_admin(
  p_id uuid,
  p_department_id uuid,
  p_team_id uuid,
  p_job_title_id uuid,
  p_grade_id uuid,
  p_reports_to_id uuid,
  p_code text,
  p_name text,
  p_name_en text default null,
  p_headcount integer default 1,
  p_is_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_cycle boolean := false;
begin
  if not (public.current_is_full_access() or public.has_permission('organization.position.manage')) then
    raise exception 'position management denied' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_code), '') is null or nullif(trim(p_name), '') is null then
    raise exception 'department, position code and name are required' using errcode = '22023';
  end if;
  if coalesce(p_headcount, 0) < 0 then raise exception 'headcount cannot be negative' using errcode = '22023'; end if;
  if p_id is not null and p_reports_to_id = p_id then raise exception 'position cannot report to itself' using errcode = '22023'; end if;

  if p_id is not null and p_reports_to_id is not null then
    with recursive descendants as (
      select p.id from public.positions p where p.reports_to_position_id = p_id
      union all
      select p.id from public.positions p join descendants x on p.reports_to_position_id = x.id
    )
    select exists(select 1 from descendants where id = p_reports_to_id) into v_cycle;
    if v_cycle then raise exception 'position hierarchy cycle detected' using errcode = '22023'; end if;
  end if;

  if p_team_id is not null and not exists (
    select 1 from public.teams t where t.id = p_team_id and t.department_id = p_department_id
  ) then
    raise exception 'team does not belong to selected department' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.positions(
      department_id, team_id, job_title_id, job_grade_id, reports_to_position_id,
      code, name, name_en, headcount, is_active, created_by
    ) values (
      p_department_id, p_team_id, p_job_title_id, p_grade_id, p_reports_to_id,
      upper(trim(p_code)), trim(p_name), nullif(trim(p_name_en), ''), coalesce(p_headcount, 1), coalesce(p_is_active, true), auth.uid()
    ) returning id into v_id;
  else
    update public.positions set
      department_id = p_department_id,
      team_id = p_team_id,
      job_title_id = p_job_title_id,
      job_grade_id = p_grade_id,
      reports_to_position_id = p_reports_to_id,
      code = upper(trim(p_code)),
      name = trim(p_name),
      name_en = nullif(trim(p_name_en), ''),
      headcount = coalesce(p_headcount, headcount),
      is_active = coalesce(p_is_active, is_active),
      updated_at = now()
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'position not found' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.get_access_admin_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['access.role.read','access.role.update','access.role.assign'])) then
    raise exception 'access catalog denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'slug', r.slug, 'name', r.name_ar, 'nameEn', r.name_en,
        'description', r.description, 'color', r.color, 'icon', r.icon,
        'system', r.is_system, 'fullAccess', r.is_full_access,
        'permissions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'permissionId', p.id, 'code', p.code, 'name', coalesce(p.description, p.code),
            'scope', rp.scope, 'requiresMfa', rp.requires_mfa,
            'requiresReason', rp.requires_reason
          ) order by p.module, p.code)
          from public.role_permissions rp join public.permissions p on p.id = rp.permission_id
          where rp.role_id = r.id
        ), '[]'::jsonb),
        'assignments', (select count(*) from public.user_roles ur where ur.role_id = r.id and ur.effective_from <= now() and (ur.effective_to is null or ur.effective_to > now()))
      ) order by r.is_full_access desc, r.name_ar)
      from public.roles r
    ), '[]'::jsonb),
    'permissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'module', p.module, 'resource', p.resource,
        'action', p.action, 'name', coalesce(p.description, p.code), 'description', p.description,
        'riskLevel', p.risk_level, 'sensitive', p.is_sensitive,
        'allowedScopes', array['self','direct_reports','management_descendants','selected_employees','team','department','selected_departments','branch','selected_branches','organization','assigned_cases','workflow_inbox','records_created_by_user','archive_readonly']
      ) order by p.module, p.code)
      from public.permissions p
    ), '[]'::jsonb),
    'users', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', pr.id, 'employeeId', pr.employee_id,
        'name', coalesce(e.full_name_ar, pr.id::text),
        'employeeCode', e.employee_code,
        'status', pr.status,
        'roles', coalesce((
          select jsonb_agg(jsonb_build_object(
            'roleId', r.id, 'slug', r.slug, 'name', r.name_ar,
            'effectiveFrom', ur.effective_from, 'effectiveTo', ur.effective_to,
            'scopeOverride', ur.scope_override
          ) order by r.name_ar)
          from public.user_roles ur join public.roles r on r.id = ur.role_id
          where ur.user_id = pr.id
        ), '[]'::jsonb)
      ) order by coalesce(e.full_name_ar, pr.id::text))
      from public.profiles pr left join public.employees e on e.id = pr.employee_id
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

create or replace function public.get_onboarding_admin_catalog(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not (public.current_is_full_access() or public.has_any_permission(array['onboarding.journey.read','onboarding.journey.manage'])) then
    raise exception 'onboarding catalog denied' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'journeys', coalesce((
      select jsonb_agg(q.payload order by q.created_at desc)
      from (
        select j.created_at, jsonb_build_object(
          'id', j.id, 'employeeId', j.employee_id,
          'employeeName', e.full_name_ar, 'employeeCode', e.employee_code,
          'startedAt', j.started_at, 'probationEnd', j.probation_end,
          'status', j.status,
          'progress', case when count(t.id) = 0 then 0 else round(100.0 * (count(t.id) filter (where t.status in ('completed','skipped'))) / count(t.id))::integer end,
          'totalTasks', count(t.id)::integer,
          'completedTasks', (count(t.id) filter (where t.status in ('completed','skipped')))::integer,
          'tasks', coalesce(jsonb_agg(jsonb_build_object(
            'id', t.id, 'title', t.title, 'ownerRole', t.owner_role,
            'assigneeId', t.assignee_id, 'dueOffsetDays', t.due_offset_days,
            'status', t.status, 'completedAt', t.completed_at
          ) order by t.created_at) filter (where t.id is not null), '[]'::jsonb)
        ) payload
        from public.onboarding_journeys j
        join public.employees e on e.id = j.employee_id
        left join public.onboarding_tasks t on t.journey_id = j.id
        group by j.id, e.id
        order by j.created_at desc
        limit greatest(1, least(coalesce(p_limit, 100), 250))
      ) q
    ), '[]'::jsonb),
    'eligibleEmployees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'name', e.full_name_ar, 'code', e.employee_code,
        'status', e.status, 'probationEnd', e.probation_end
      ) order by e.full_name_ar)
      from public.employees e
      where e.is_deleted = false and e.status in ('draft','invited','onboarding','active')
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

create or replace function public.create_onboarding_journey_admin(
  p_employee_id uuid,
  p_started_at timestamptz default now(),
  p_probation_end date default null,
  p_tasks jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_task jsonb;
begin
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'onboarding management denied' using errcode = '42501';
  end if;
  if not exists(select 1 from public.employees e where e.id = p_employee_id and e.is_deleted = false) then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  if exists(select 1 from public.onboarding_journeys j where j.employee_id = p_employee_id and j.status in ('not_started','in_progress')) then
    raise exception 'employee already has an active onboarding journey' using errcode = '23505';
  end if;

  insert into public.onboarding_journeys(employee_id, started_at, probation_end, status, created_by)
  values (p_employee_id, coalesce(p_started_at, now()), p_probation_end, 'in_progress', auth.uid())
  returning id into v_id;

  for v_task in select * from jsonb_array_elements(coalesce(p_tasks, '[]'::jsonb)) loop
    if nullif(trim(v_task->>'title'), '') is not null then
      insert into public.onboarding_tasks(journey_id, title, owner_role, assignee_id, due_offset_days, status, created_by)
      values (
        v_id,
        trim(v_task->>'title'),
        nullif(trim(v_task->>'ownerRole'), ''),
        nullif(v_task->>'assigneeId', '')::uuid,
        coalesce(nullif(v_task->>'dueOffsetDays', '')::integer, 0),
        'pending', auth.uid()
      );
    end if;
  end loop;

  update public.employees set status = 'onboarding', updated_at = now()
  where id = p_employee_id and status in ('draft','invited');
  return v_id;
end;
$$;

create or replace function public.transition_onboarding_task_admin(p_task_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_journey uuid;
  v_remaining integer;
  v_employee uuid;
begin
  if p_status not in ('pending','in_progress','completed','skipped') then
    raise exception 'invalid onboarding task status' using errcode = '22023';
  end if;
  if not (public.current_is_full_access() or public.has_permission('onboarding.journey.manage')) then
    raise exception 'onboarding task transition denied' using errcode = '42501';
  end if;

  update public.onboarding_tasks set
    status = p_status,
    completed_at = case when p_status in ('completed','skipped') then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id
  returning journey_id into v_journey;
  if v_journey is null then raise exception 'onboarding task not found' using errcode = 'P0002'; end if;

  select count(*) into v_remaining from public.onboarding_tasks
  where journey_id = v_journey and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_journey;
    select employee_id into v_employee from public.onboarding_journeys where id = v_journey;
    update public.employees set status = 'active', updated_at = now() where id = v_employee and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_journey;
  end if;

  return jsonb_build_object('journeyId', v_journey, 'remainingTasks', v_remaining, 'completed', v_remaining = 0);
end;
$$;

create or replace function public.create_job_requisition_admin(
  p_department_id uuid,
  p_title text,
  p_headcount integer,
  p_reason text default null,
  p_budget_range text default null,
  p_submit boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not (public.current_is_full_access() or public.has_permission('recruitment.requisition.manage')) then
    raise exception 'requisition management denied' using errcode = '42501';
  end if;
  if p_department_id is null or nullif(trim(p_title), '') is null or coalesce(p_headcount, 0) <= 0 then
    raise exception 'department, title and positive headcount are required' using errcode = '22023';
  end if;
  insert into public.job_requisitions(
    department_id, title, headcount, reason, budget_range,
    status, requested_by, current_stage, created_by
  ) values (
    p_department_id, trim(p_title), p_headcount, nullif(trim(p_reason), ''), nullif(trim(p_budget_range), ''),
    case when p_submit then 'pending' else 'draft' end,
    public.current_employee_id(), case when p_submit then 'approval' else 'draft' end, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

-- Canonical write paths: the UI writes through the audited RPCs above only.
-- Read policies remain available where the product needs directory/look-up access.
drop policy if exists departments_insert_manage on public.departments;
drop policy if exists departments_update_manage on public.departments;
drop policy if exists departments_delete_manage on public.departments;
drop policy if exists positions_insert_manage on public.positions;
drop policy if exists positions_update_manage on public.positions;
drop policy if exists positions_delete_manage on public.positions;

drop policy if exists job_requisitions_insert on public.job_requisitions;
drop policy if exists job_requisitions_update on public.job_requisitions;
drop policy if exists job_requisitions_delete on public.job_requisitions;
drop policy if exists journeys_insert on public.onboarding_journeys;
drop policy if exists journeys_update on public.onboarding_journeys;
drop policy if exists journeys_delete on public.onboarding_journeys;
drop policy if exists onboarding_tasks_insert on public.onboarding_tasks;
drop policy if exists onboarding_tasks_update on public.onboarding_tasks;
drop policy if exists onboarding_tasks_delete on public.onboarding_tasks;

-- Audit newly operational tables. Existing trigger names are kept idempotent.
drop trigger if exists trg_departments_audit on public.departments;
create trigger trg_departments_audit after insert or update or delete on public.departments
for each row execute function public.audit_row_change();

drop trigger if exists trg_positions_audit on public.positions;
create trigger trg_positions_audit after insert or update or delete on public.positions
for each row execute function public.audit_row_change();

drop trigger if exists trg_onboarding_journeys_audit on public.onboarding_journeys;
create trigger trg_onboarding_journeys_audit after insert or update or delete on public.onboarding_journeys
for each row execute function public.audit_row_change();

drop trigger if exists trg_onboarding_tasks_audit on public.onboarding_tasks;
create trigger trg_onboarding_tasks_audit after insert or update or delete on public.onboarding_tasks
for each row execute function public.audit_row_change();

drop trigger if exists trg_job_requisitions_audit on public.job_requisitions;
create trigger trg_job_requisitions_audit after insert or update or delete on public.job_requisitions
for each row execute function public.audit_row_change();

revoke execute on function public.get_organization_admin_catalog() from public;
revoke execute on function public.upsert_department_admin(uuid,uuid,uuid,uuid,uuid,text,text,text,boolean) from public;
revoke execute on function public.upsert_position_admin(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,boolean) from public;
revoke execute on function public.get_access_admin_catalog() from public;
revoke execute on function public.get_onboarding_admin_catalog(integer) from public;
revoke execute on function public.create_onboarding_journey_admin(uuid,timestamptz,date,jsonb) from public;
revoke execute on function public.transition_onboarding_task_admin(uuid,text) from public;
revoke execute on function public.create_job_requisition_admin(uuid,text,integer,text,text,boolean) from public;

grant execute on function public.get_organization_admin_catalog() to authenticated;
grant execute on function public.upsert_department_admin(uuid,uuid,uuid,uuid,uuid,text,text,text,boolean) to authenticated;
grant execute on function public.upsert_position_admin(uuid,uuid,uuid,uuid,uuid,uuid,text,text,text,integer,boolean) to authenticated;
grant execute on function public.get_access_admin_catalog() to authenticated;
grant execute on function public.get_onboarding_admin_catalog(integer) to authenticated;
grant execute on function public.create_onboarding_journey_admin(uuid,timestamptz,date,jsonb) to authenticated;
grant execute on function public.transition_onboarding_task_admin(uuid,text) to authenticated;
grant execute on function public.create_job_requisition_admin(uuid,text,integer,text,text,boolean) to authenticated;

commit;
