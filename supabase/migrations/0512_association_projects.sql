-- ═══════════════════════════════════════════════════════════════
-- 0512: نظام مشاريع الجمعية — جداول + RPC + RLS
-- شاشة عملاقة تعرض كل المشاريع مع مؤشرات LED
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════
-- 1. الجداول
-- ═══════════════════════════════════════════════

create table if not exists public.association_projects (
  id                uuid primary key default gen_random_uuid(),
  code              text unique not null,
  name              text not null,
  description       text,
  department_id     uuid not null references public.departments(id),
  owner_employee_id uuid not null references public.employees(id),
  status            text not null default 'planned'
                    check (status in ('planned','active','on_hold','completed','cancelled')),
  priority          text not null default 'medium'
                    check (priority in ('low','medium','high','critical')),
  progress          numeric(5,2) not null default 0
                    check (progress >= 0 and progress <= 100),
  start_date        date,
  target_end_date   date,
  last_update_at    timestamptz,
  last_update_note  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  created_by        uuid references auth.users(id)
);

create table if not exists public.association_project_updates (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references public.association_projects(id) on delete cascade,
  author_employee_id  uuid not null references public.employees(id),
  note                text not null,
  progress            numeric(5,2) check (progress >= 0 and progress <= 100),
  status_change       text check (status_change in ('planned','active','on_hold','completed','cancelled')),
  created_at          timestamptz not null default now()
);

create table if not exists public.association_project_steps (
  id                  uuid primary key default gen_random_uuid(),
  project_id          uuid not null references public.association_projects(id) on delete cascade,
  title               text not null,
  description         text,
  sort_order          integer not null default 0,
  status              text not null default 'pending'
                      check (status in ('pending','in_progress','done','blocked')),
  due_date            date,
  assignee_employee_id uuid references public.employees(id),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz
);

-- ═══════════════════════════════════════════════
-- 2. updated_at triggers + RLS enable
-- ═══════════════════════════════════════════════

do $$ declare t text; begin
  foreach t in array array['association_projects','association_project_steps'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.tg_set_updated_at()', t, t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
  foreach t in array array['association_project_updates'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ═══════════════════════════════════════════════
-- 3. RLS Policies (full-access only)
-- ═══════════════════════════════════════════════

do $$ declare t text; begin
  foreach t in array array['association_projects','association_project_updates','association_project_steps'] loop
    execute format('create policy %I_admin on public.%I for all to authenticated
      using (public.current_is_full_access())
      with check (public.current_is_full_access())', t, t);
  end loop;
end $$;

-- ═══════════════════════════════════════════════
-- 4. RPC: get_association_projects()
-- ═══════════════════════════════════════════════

create or replace function public.get_association_projects()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_result jsonb;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',              p.id,
        'code',            p.code,
        'name',            p.name,
        'description',     p.description,
        'departmentId',    p.department_id,
        'departmentName',  d.name_ar,
        'ownerId',         p.owner_employee_id,
        'ownerName',       e.full_name_ar,
        'status',          p.status,
        'priority',        p.priority,
        'progress',        p.progress,
        'startDate',       p.start_date,
        'targetEndDate',   p.target_end_date,
        'lastUpdateAt',    p.last_update_at,
        'lastUpdateNote',  p.last_update_note,
        'totalSteps',      (select count(*) from public.association_project_steps s where s.project_id = p.id),
        'completedSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'done'),
        'remainingSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status not in ('done','cancelled')),
        'blockedSteps',    (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'blocked'),
        'ledStatus',       case
                              when p.status in ('completed','cancelled') then 'stale'
                              when p.status = 'on_hold' then 'halted'
                              when p.last_update_at is null then 'stale'
                              when p.last_update_at < now() - interval '30 days' then 'stale'
                              when p.last_update_at < now() - interval '14 days' then 'halted'
                              else 'active'
                            end
      ))
      from public.association_projects p
      join public.departments d on d.id = p.department_id
      join public.employees e on e.id = p.owner_employee_id
      order by
        case p.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
        p.updated_at desc
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_association_projects() from public;
grant execute on function public.get_association_projects() to authenticated;

-- ═══════════════════════════════════════════════
-- 5. RPC: get_association_project_detail(uuid)
-- ═══════════════════════════════════════════════

create or replace function public.get_association_project_detail(p_project_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_result jsonb;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not exists (select 1 from public.association_projects where id = p_project_id) then
    raise exception 'PROJECT_NOT_FOUND' using errcode = '42P01';
  end if;

  select jsonb_build_object(
    'project', (
      select jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'description', p.description,
        'departmentId', p.department_id, 'departmentName', d.name_ar,
        'ownerId', p.owner_employee_id, 'ownerName', e.full_name_ar,
        'status', p.status, 'priority', p.priority, 'progress', p.progress,
        'startDate', p.start_date, 'targetEndDate', p.target_end_date,
        'lastUpdateAt', p.last_update_at, 'lastUpdateNote', p.last_update_note,
        'ledStatus', case
          when p.status in ('completed','cancelled') then 'stale'
          when p.status = 'on_hold' then 'halted'
          when p.last_update_at is null then 'stale'
          when p.last_update_at < now() - interval '30 days' then 'stale'
          when p.last_update_at < now() - interval '14 days' then 'halted'
          else 'active'
        end
      )
      from public.association_projects p
      join public.departments d on d.id = p.department_id
      join public.employees e on e.id = p.owner_employee_id
      where p.id = p_project_id
    ),
    'steps', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id, 'title', s.title, 'description', s.description,
        'sortOrder', s.sort_order, 'status', s.status,
        'dueDate', s.due_date,
        'assigneeId', s.assignee_employee_id,
        'assigneeName', ae.full_name_ar
      ) order by s.sort_order, s.created_at)
      from public.association_project_steps s
      left join public.employees ae on ae.id = s.assignee_employee_id
      where s.project_id = p_project_id
    ), '[]'::jsonb),
    'updates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'note', u.note, 'progress', u.progress,
        'statusChange', u.status_change,
        'authorName', ue.full_name_ar,
        'createdAt', u.created_at
      ) order by u.created_at desc)
      from public.association_project_updates u
      join public.employees ue on ue.id = u.author_employee_id
      where u.project_id = p_project_id
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_association_project_detail(uuid) from public;
grant execute on function public.get_association_project_detail(uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 6. RPC: create_association_project_admin(...)
-- ═══════════════════════════════════════════════

create or replace function public.create_association_project_admin(
  p_code              text,
  p_name              text,
  p_description       text,
  p_department_id     uuid,
  p_owner_employee_id uuid,
  p_priority          text default 'medium',
  p_start_date        date default null,
  p_target_end_date   date default null
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  insert into public.association_projects (
    code, name, description, department_id, owner_employee_id,
    status, priority, start_date, target_end_date, created_by
  ) values (
    p_code, p_name, p_description, p_department_id, p_owner_employee_id,
    'planned', p_priority, p_start_date, p_target_end_date, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) from public;
grant execute on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) to authenticated;

-- ═══════════════════════════════════════════════
-- 7. RPC: update_association_project_admin(...)
-- ═══════════════════════════════════════════════

create or replace function public.update_association_project_admin(
  p_project_id        uuid,
  p_name              text,
  p_description       text,
  p_department_id     uuid,
  p_owner_employee_id uuid,
  p_status            text,
  p_priority          text,
  p_progress          numeric,
  p_start_date        date,
  p_target_end_date   date
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.association_projects set
    name = p_name,
    description = p_description,
    department_id = p_department_id,
    owner_employee_id = p_owner_employee_id,
    status = p_status,
    priority = p_priority,
    progress = p_progress,
    start_date = p_start_date,
    target_end_date = p_target_end_date
  where id = p_project_id;
end;
$$;

revoke all on function public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date) from public;
grant execute on function public.update_association_project_admin(uuid,text,text,uuid,uuid,text,text,numeric,date,date) to authenticated;

-- ═══════════════════════════════════════════════
-- 8. RPC: add_project_update_admin(...)
-- ═══════════════════════════════════════════════

create or replace function public.add_project_update_admin(
  p_project_id     uuid,
  p_note           text,
  p_progress       numeric,
  p_status_change  text default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_emp uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  v_emp := public.current_employee_id();
  if v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;

  insert into public.association_project_updates (project_id, author_employee_id, note, progress, status_change)
  values (p_project_id, v_emp, p_note, p_progress, p_status_change);

  update public.association_projects set
    last_update_at = now(),
    last_update_note = p_note,
    progress = coalesce(p_progress, progress),
    status = coalesce(p_status_change, status)
  where id = p_project_id;
end;
$$;

revoke all on function public.add_project_update_admin(uuid,text,numeric,text) from public;
grant execute on function public.add_project_update_admin(uuid,text,numeric,text) to authenticated;

-- ═══════════════════════════════════════════════
-- 9. RPC: upsert_project_step_admin(...)
-- ═══════════════════════════════════════════════

create or replace function public.upsert_project_step_admin(
  p_project_id           uuid,
  p_step_id              uuid,
  p_title                text,
  p_description          text,
  p_sort_order           integer,
  p_status               text default 'pending',
  p_due_date             date default null,
  p_assignee_employee_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if p_step_id is not null then
    update public.association_project_steps set
      title = p_title, description = p_description, sort_order = p_sort_order,
      status = p_status, due_date = p_due_date, assignee_employee_id = p_assignee_employee_id
    where id = p_step_id and project_id = p_project_id
    returning id into v_id;
  else
    insert into public.association_project_steps (
      project_id, title, description, sort_order, status, due_date, assignee_employee_id
    ) values (
      p_project_id, p_title, p_description, p_sort_order, p_status, p_due_date, p_assignee_employee_id
    ) returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function public.upsert_project_step_admin(uuid,uuid,text,text,integer,text,date,uuid) from public;
grant execute on function public.upsert_project_step_admin(uuid,uuid,text,text,integer,text,date,uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 10. RPC: delete_project_step_admin(uuid)
-- ═══════════════════════════════════════════════

create or replace function public.delete_project_step_admin(p_step_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  delete from public.association_project_steps where id = p_step_id;
end;
$$;

revoke all on function public.delete_project_step_admin(uuid) from public;
grant execute on function public.delete_project_step_admin(uuid) to authenticated;
