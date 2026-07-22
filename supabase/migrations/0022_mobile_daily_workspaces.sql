-- Migration 0022: Complete daily mobile workspaces (profile, tasks, team, notifications)
-- Adds server-scoped RPCs only. No client-side trust and no direct sensitive writes.

begin;

-- -----------------------------------------------------------------------------
-- My mobile profile: personal/job summary, manager, documents and assets.
-- ----------------------------------------------------------------------------
create or replace function public.get_my_mobile_profile()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_employee_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'jobTitle', jt.name,
    'position', p.name,
    'grade', g.name,
    'department', d.name,
    'team', t.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id,
        'type', doc.doc_type,
        'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case
          when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired'
          else doc.status
        end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id = e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id,
        'assetName', ai.name_ar,
        'assetType', ai.asset_type,
        'serial', ai.serial,
        'assignedAt', aa.handed_over_at,
        'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id = aa.asset_id
      where aa.employee_id = e.id
    ), '[]'::jsonb)
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.job_grades g on g.id = e.grade_id
  left join public.departments d on d.id = e.department_id
  left join public.teams t on t.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = v_employee_id and e.is_deleted = false;

  if v_result is null then
    raise exception 'employee profile not found' using errcode = 'P0002';
  end if;

  return v_result;
end;
$$;
revoke all on function public.get_my_mobile_profile() from public;
grant execute on function public.get_my_mobile_profile() to authenticated;

-- -----------------------------------------------------------------------------
-- Personal tasks. Assignees can progress their task; cancellation stays admin-only.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_mobile_tasks(p_limit integer default 100)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with task_rows as (
    select
      t.id,
      'task'::text source_type,
      t.title,
      t.description,
      t.priority,
      t.status,
      t.due_date,
      t.created_at,
      creator.full_name_ar created_by_name
    from public.tasks t
    left join public.employees creator on creator.id = t.created_by_employee_id
    where t.assignee_employee_id = public.current_employee_id()

    union all

    select
      ot.id,
      'onboarding'::text source_type,
      ot.title,
      concat_ws(' · ', 'مهمة ضمن رحلة الإلحاق', nullif(ot.owner_role, '')) description,
      'high'::text priority,
      case ot.status when 'completed' then 'done' when 'skipped' then 'cancelled' else ot.status end status,
      ((coalesce(j.started_at, j.created_at) at time zone 'Africa/Cairo')::date + coalesce(ot.due_offset_days, 0)) due_date,
      ot.created_at,
      coalesce(ot.owner_role, 'Onboarding') created_by_name
    from public.onboarding_tasks ot
    join public.onboarding_journeys j on j.id = ot.journey_id
    where j.status in ('not_started','in_progress','completed')
      and (
        ot.assignee_id = public.current_employee_id()
        or (
          ot.assignee_id is null
          and j.employee_id = public.current_employee_id()
          and lower(coalesce(ot.owner_role, '')) in ('employee','موظف')
        )
      )
  ), limited as (
    select * from task_rows
    order by
      case priority when 'urgent' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
      due_date nulls last,
      created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x.id,
    'sourceType', x.source_type,
    'title', x.title,
    'description', x.description,
    'priority', x.priority,
    'status', x.status,
    'dueDate', x.due_date,
    'createdAt', x.created_at,
    'createdByName', x.created_by_name,
    'isOverdue', (x.due_date is not null and x.due_date < (now() at time zone 'Africa/Cairo')::date and x.status not in ('done','cancelled'))
  ) order by
    case x.priority when 'urgent' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
    x.due_date nulls last,
    x.created_at desc), '[]'::jsonb)
  from limited x;
$$;
revoke all on function public.get_my_mobile_tasks(integer) from public;
grant execute on function public.get_my_mobile_tasks(integer) to authenticated;

create or replace function public.transition_my_task(
  p_task_id uuid,
  p_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_task public.tasks%rowtype;
  v_onboarding public.onboarding_tasks%rowtype;
  v_journey public.onboarding_journeys%rowtype;
  v_db_status text;
  v_remaining integer;
begin
  if p_status not in ('pending','in_progress','done') then
    raise exception 'unsupported task status' using errcode = '22023';
  end if;

  select * into v_task from public.tasks where id = p_task_id for update;
  if found then
    if v_task.assignee_employee_id is distinct from v_employee_id then
      raise exception 'task is outside your scope' using errcode = '42501';
    end if;
    if v_task.status = 'cancelled' then
      raise exception 'cancelled task cannot be changed' using errcode = 'P0001';
    end if;
    if v_task.status = 'done' and p_status <> 'done' then
      raise exception 'completed task can only be reopened by its owner or administrator' using errcode = '42501';
    end if;
    update public.tasks set status = p_status, updated_at = now() where id = p_task_id;
    return jsonb_build_object('id', p_task_id, 'sourceType', 'task', 'status', p_status, 'updatedAt', now());
  end if;

  select ot.* into v_onboarding
  from public.onboarding_tasks ot
  where ot.id = p_task_id
  for update;
  if not found then raise exception 'task not found' using errcode = 'P0002'; end if;

  select j.* into v_journey
  from public.onboarding_journeys j
  where j.id = v_onboarding.journey_id
  for update;

  if not (
    v_onboarding.assignee_id = v_employee_id
    or (v_onboarding.assignee_id is null and v_journey.employee_id = v_employee_id and lower(coalesce(v_onboarding.owner_role, '')) in ('employee','موظف'))
  ) then
    raise exception 'onboarding task is outside your scope' using errcode = '42501';
  end if;
  if v_onboarding.status in ('completed','skipped') and p_status <> 'done' then
    raise exception 'completed onboarding task cannot be reopened by employee' using errcode = '42501';
  end if;

  v_db_status := case p_status when 'done' then 'completed' else p_status end;
  update public.onboarding_tasks set
    status = v_db_status,
    completed_at = case when v_db_status = 'completed' then coalesce(completed_at, now()) else null end,
    updated_at = now()
  where id = p_task_id;

  select count(*) into v_remaining
  from public.onboarding_tasks
  where journey_id = v_onboarding.journey_id and status not in ('completed','skipped');

  if v_remaining = 0 then
    update public.onboarding_journeys set status = 'completed', updated_at = now() where id = v_onboarding.journey_id;
    update public.employees set status = 'active', updated_at = now()
    where id = v_journey.employee_id and status = 'onboarding';
  else
    update public.onboarding_journeys set status = 'in_progress', updated_at = now() where id = v_onboarding.journey_id;
  end if;

  return jsonb_build_object(
    'id', p_task_id, 'sourceType', 'onboarding', 'status', p_status,
    'journeyId', v_onboarding.journey_id, 'remainingTasks', v_remaining,
    'updatedAt', now()
  );
end;
$$;
revoke all on function public.transition_my_task(uuid,text) from public;
grant execute on function public.transition_my_task(uuid,text) to authenticated;

-- Tasks are read with scope and mutated only through task RPCs.
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks
  for select to authenticated
  using (
    assignee_employee_id = public.current_employee_id()
    or created_by_employee_id = public.current_employee_id()
    or (
      assignee_employee_id is not null
      and public.can_access_employee(assignee_employee_id, 'tasks.read')
    )
  );
drop policy if exists tasks_insert on public.tasks;
drop policy if exists tasks_update on public.tasks;
drop policy if exists tasks_delete on public.tasks;

-- Audit task changes consistently.
drop trigger if exists trg_tasks_audit on public.tasks;
create trigger trg_tasks_audit
  after insert or update or delete on public.tasks
  for each row execute function public.audit_row_change();

-- -----------------------------------------------------------------------------
-- Direct manager team directory and current operating status.
-- ----------------------------------------------------------------------------
create or replace function public.get_my_mobile_team(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager_id uuid := public.current_employee_id();
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'people.employee.read',
      'requests.request.approve',
      'performance.kpi.manager_assess',
      'attendance.record.read'
    ])
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'jobTitle', jt.name,
    'department', d.name,
    'team', tm.name,
    'attendanceStatus', ad.status,
    'lateMinutes', coalesce(ad.late_minutes, 0),
    'firstCheckIn', ad.first_check_in,
    'pendingRequests', (
      select count(*) from public.requests r
      where r.employee_id = e.id and r.status = 'pending'
    ),
    'kpiStage', (
      select ke.current_stage
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    )
  ) order by e.full_name_ar), '[]'::jsonb)
  into v_result
  from (
    select child.*
    from public.manager_relations mr
    join public.employees child on child.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
      and child.is_active = true
      and child.is_deleted = false
    order by child.full_name_ar
    limit greatest(1, least(coalesce(p_limit, 100), 200))
  ) e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = (now() at time zone 'Africa/Cairo')::date;

  return v_result;
end;
$$;
revoke all on function public.get_my_mobile_team(integer) from public;
grant execute on function public.get_my_mobile_team(integer) to authenticated;

-- -----------------------------------------------------------------------------
-- Daily reports visible to the employee or manager according to employee scope.
-- ----------------------------------------------------------------------------
-- Keep explicit review timing without overloading updated_at.
alter table public.daily_reports
  add column if not exists reviewed_at timestamptz;

create or replace function public.get_mobile_daily_reports(
  p_employee_id uuid default null,
  p_limit integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_target uuid := coalesce(p_employee_id, public.current_employee_id());
  v_result jsonb;
begin
  if v_target is null or not public.can_access_employee(v_target, 'reports.read') then
    raise exception 'report scope denied' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', dr.id,
    'employeeId', dr.employee_id,
    'employeeName', e.full_name_ar,
    'reportDate', dr.report_date,
    'achievements', dr.achievements,
    'blockers', dr.blockers,
    'tomorrowPlan', dr.tomorrow_plan,
    'managerComment', dr.manager_comment,
    'reviewerName', reviewer.full_name_ar,
    'reviewedAt', dr.reviewed_at,
    'createdAt', dr.created_at
  ) order by dr.report_date desc, dr.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select * from public.daily_reports
    where employee_id = v_target
    order by report_date desc, created_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 100))
  ) dr
  join public.employees e on e.id = dr.employee_id
  left join public.employees reviewer on reviewer.id = dr.reviewed_by;

  return v_result;
end;
$$;
revoke all on function public.get_mobile_daily_reports(uuid,integer) from public;
grant execute on function public.get_mobile_daily_reports(uuid,integer) to authenticated;

create or replace function public.upsert_my_daily_report(
  p_report_date date,
  p_achievements text,
  p_blockers text default null,
  p_tomorrow_plan text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_id uuid;
begin
  if v_employee_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;
  if p_report_date > (now() at time zone 'Africa/Cairo')::date then
    raise exception 'future daily report is not allowed' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_achievements, ''))) < 3 then
    raise exception 'achievements are required' using errcode = '22023';
  end if;

  select id into v_id
  from public.daily_reports
  where employee_id = v_employee_id and report_date = p_report_date
  order by created_at desc limit 1;

  if v_id is null then
    insert into public.daily_reports (
      employee_id, report_date, achievements, blockers, tomorrow_plan, created_by
    ) values (
      v_employee_id, p_report_date, trim(p_achievements), nullif(trim(coalesce(p_blockers,'')),''),
      nullif(trim(coalesce(p_tomorrow_plan,'')),''), auth.uid()
    ) returning id into v_id;
  else
    update public.daily_reports
    set achievements = trim(p_achievements),
        blockers = nullif(trim(coalesce(p_blockers,'')),''),
        tomorrow_plan = nullif(trim(coalesce(p_tomorrow_plan,'')),''),
        updated_at = now()
    where id = v_id and reviewed_by is null;

    if not found then
      raise exception 'reviewed report cannot be edited' using errcode = '42501';
    end if;
  end if;

  return v_id;
end;
$$;
revoke all on function public.upsert_my_daily_report(date,text,text,text) from public;
grant execute on function public.upsert_my_daily_report(date,text,text,text) to authenticated;

-- Daily reports are read through a scope-aware policy and mutated only through
-- the audited RPCs above.
drop policy if exists daily_reports_select on public.daily_reports;
create policy daily_reports_select on public.daily_reports
  for select to authenticated
  using (public.can_access_employee(employee_id, 'reports.read'));

drop policy if exists daily_reports_insert on public.daily_reports;
drop policy if exists daily_reports_update on public.daily_reports;
drop policy if exists daily_reports_delete on public.daily_reports;


create or replace function public.review_daily_report(
  p_report_id uuid,
  p_manager_comment text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager_id uuid := public.current_employee_id();
  v_report public.daily_reports%rowtype;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if v_manager_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_manager_comment, ''))) < 3 then
    raise exception 'manager comment is required' using errcode = '22023';
  end if;

  select * into v_report from public.daily_reports where id=p_report_id for update;
  if not found then
    raise exception 'daily report not found' using errcode = 'P0002';
  end if;
  if v_report.employee_id = v_manager_id then
    raise exception 'self review is not allowed' using errcode = '42501';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(v_report.employee_id, 'reports.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=v_report.employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'report review scope denied' using errcode = '42501';
  end if;

  update public.daily_reports
  set manager_comment=trim(p_manager_comment), reviewed_by=v_manager_id, reviewed_at=now(), updated_at=now()
  where id=p_report_id;

  return jsonb_build_object('id', p_report_id, 'reviewedBy', v_manager_id, 'reviewedAt', now(), 'managerComment', trim(p_manager_comment));
end;
$$;
revoke all on function public.review_daily_report(uuid,text) from public;
grant execute on function public.review_daily_report(uuid,text) to authenticated;

create or replace function public.create_team_task(
  p_employee_id uuid,
  p_title text,
  p_description text default null,
  p_priority text default 'medium',
  p_due_date date default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager_id uuid := public.current_employee_id();
  v_task_id uuid;
begin
  if v_manager_id is null or p_employee_id is null then
    raise exception 'employee context is required' using errcode = '42501';
  end if;
  if p_employee_id=v_manager_id then
    raise exception 'use personal task flow for self tasks' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3 then
    raise exception 'task title is required' using errcode = '22023';
  end if;
  if p_priority not in ('low','medium','high','urgent') then
    raise exception 'unsupported task priority' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'tasks.write')
    or exists (
      select 1 from public.manager_relations mr
      where mr.manager_employee_id=v_manager_id
        and mr.employee_id=p_employee_id
        and mr.relation_type='primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    )
  ) then
    raise exception 'task assignment scope denied' using errcode = '42501';
  end if;

  insert into public.tasks(
    title, description, assignee_employee_id, priority, due_date,
    status, created_by_employee_id, created_by
  ) values (
    trim(p_title), nullif(trim(coalesce(p_description,'')),''), p_employee_id,
    p_priority, p_due_date, 'pending', v_manager_id, auth.uid()
  ) returning id into v_task_id;

  return v_task_id;
end;
$$;
revoke all on function public.create_team_task(uuid,text,text,text,date) from public;
grant execute on function public.create_team_task(uuid,text,text,text,date) to authenticated;

-- Keep one daily report row per employee/date going forward.
create unique index if not exists ux_daily_reports_employee_date
  on public.daily_reports(employee_id, report_date);

drop trigger if exists trg_daily_reports_audit on public.daily_reports;
create trigger trg_daily_reports_audit
  after insert or update or delete on public.daily_reports
  for each row execute function public.audit_row_change();



-- -----------------------------------------------------------------------------
-- Employee 360 read model for HR/Admin/manager scopes.
-- -----------------------------------------------------------------------------
create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  if p_employee_id is null or not public.can_access_employee(p_employee_id, 'people.employee.read') then
    raise exception 'employee scope denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'fullNameAr', e.full_name_ar,
    'fullNameEn', e.full_name_en,
    'phoneE164', e.phone_e164,
    'photoUrl', e.photo_url,
    'status', e.status,
    'isActive', e.is_active,
    'hireDate', e.hire_date,
    'contractEnd', e.contract_end,
    'probationEnd', e.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager.full_name_ar,
    'accountStatus', profile.status,
    'roles', coalesce((
      select jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) order by r.name_ar)
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      select count(*)
      from public.manager_relations mr
      where mr.manager_employee_id = e.id
        and mr.relation_type = 'primary'
        and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status in ('present','late')),
      'lateDays', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.late_minutes > 0),
      'absent', (select count(*) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 and a.status='absent'),
      'workMinutes', (select coalesce(sum(a.work_minutes),0) from public.attendance_daily a where a.employee_id=e.id and a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (select count(*) from public.requests r where r.employee_id=e.id and r.status='pending'),
      'approved', (select count(*) from public.requests r where r.employee_id=e.id and r.status='approved'),
      'rejected', (select count(*) from public.requests r where r.employee_id=e.id and r.status='rejected')
    ),
    'latestKpi', (
      select jsonb_build_object(
        'id', ke.id,
        'periodMonth', kc.period_month,
        'currentStage', ke.current_stage,
        'finalScore', ke.final_score,
        'finalRating', ke.final_rating
      )
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id=ke.cycle_id
      where ke.employee_id=e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'documents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', case when doc.expiry_date is not null and doc.expiry_date < (now() at time zone 'Africa/Cairo')::date then 'expired' else doc.status end
      ) order by doc.created_at desc)
      from public.documents doc
      where doc.owner_employee_id=e.id and doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) order by aa.handed_over_at desc nulls last)
      from public.asset_assignments aa
      join public.asset_inventory ai on ai.id=aa.asset_id
      where aa.employee_id=e.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) order by r.created_at desc)
      from (
        select * from public.requests where employee_id=e.id order by created_at desc limit 10
      ) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', task.id, 'title', task.title, 'status', task.status,
        'priority', task.priority, 'dueDate', task.due_date
      ) order by task.created_at desc)
      from (
        select * from public.tasks where assignee_employee_id=e.id order by created_at desc limit 10
      ) task
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  )
  into v_result
  from public.employees e
  left join public.job_titles jt on jt.id=e.job_title_id
  left join public.positions pos on pos.id=e.position_id
  left join public.job_grades grade on grade.id=e.grade_id
  left join public.departments dept on dept.id=e.department_id
  left join public.teams team on team.id=e.team_id
  left join public.branches branch on branch.id=e.branch_id
  left join public.work_sites site on site.id=e.work_site_id
  left join public.profiles profile on profile.employee_id=e.id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id=mr.manager_employee_id
    where mr.employee_id=e.id and mr.relation_type='primary'
      and mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
      and (mr.effective_to is null or mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    order by mr.effective_from desc limit 1
  ) manager on true
  where e.id=p_employee_id and e.is_deleted=false;

  if v_result is null then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;
revoke all on function public.get_employee_360(uuid) from public;
grant execute on function public.get_employee_360(uuid) to authenticated;


commit;
