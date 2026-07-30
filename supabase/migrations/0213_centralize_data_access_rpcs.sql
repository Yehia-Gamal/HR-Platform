-- Migration 0213 — Centralize direct supabase.from() CRUD into server RPCs
-- Phase 2 code quality audit: TYPE_SAFETY + CENTRALIZATION
-- All functions use SECURITY INVOKER to preserve existing RLS policies.

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. get_organization_lookups() — single RPC replacing 10 parallel SELECTs
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_organization_lookups()
returns jsonb
language plpgsql security invoker stable
as $$
begin
  return jsonb_build_object(
    'roles',
    coalesce((select jsonb_agg(row_to_json(r) order by r.name_ar)
              from (select id, slug, name_ar, is_full_access, is_capability
                    from public.roles) r), '[]'::jsonb),

    'employees',
    coalesce((select jsonb_agg(row_to_json(e) order by e.full_name_ar)
              from (select id, full_name_ar, employee_code
                    from public.employees
                    where is_active and not is_deleted) e), '[]'::jsonb),

    'branches',
    coalesce((select jsonb_agg(row_to_json(b) order by b.name)
              from (select id, name
                    from public.branches
                    where is_active) b), '[]'::jsonb),

    'work_sites',
    coalesce((select jsonb_agg(row_to_json(ws) order by ws.name)
              from (select id, name, branch_id
                    from public.work_sites
                    where is_active) ws), '[]'::jsonb),

    'departments',
    coalesce((select jsonb_agg(row_to_json(d) order by d.name)
              from (select id, name, branch_id
                    from public.departments
                    where is_active) d), '[]'::jsonb),

    'teams',
    coalesce((select jsonb_agg(row_to_json(t) order by t.name)
              from (select id, name, department_id
                    from public.teams
                    where is_active) t), '[]'::jsonb),

    'job_titles',
    coalesce((select jsonb_agg(row_to_json(jt) order by jt.name)
              from (select id, name
                    from public.job_titles
                    where is_active) jt), '[]'::jsonb),

    'positions',
    coalesce((select jsonb_agg(row_to_json(p) order by p.name)
              from (select id, name, department_id
                    from public.positions
                    where is_active) p), '[]'::jsonb),

    'job_grades',
    coalesce((select jsonb_agg(row_to_json(g) order by g.level)
              from (select id, name, level
                    from public.job_grades
                    where is_active) g), '[]'::jsonb),

    'employment_types',
    coalesce((select jsonb_agg(row_to_json(et) order by et.name)
              from (select id, name
                    from public.employment_types
                    where is_active) et), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_organization_lookups() from anon;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Holiday CRUD — public_holidays mutations via RPCs
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.create_public_holiday(
  p_name            text,
  p_holiday_date    date,
  p_end_date        date     default null,
  p_scope           text     default 'all',
  p_legal_entity_id uuid     default null,
  p_department_id   uuid     default null,
  p_excluded_department_ids uuid[] default '{}',
  p_notes           text     default null,
  p_is_recurring    boolean  default false
)
returns uuid
language plpgsql security invoker
as $$
declare
  v_id uuid;
begin
  insert into public.public_holidays (
    name, holiday_date, end_date, scope, legal_entity_id,
    department_id, excluded_department_ids, notes,
    is_recurring, created_by
  ) values (
    p_name, p_holiday_date, p_end_date, p_scope, p_legal_entity_id,
    p_department_id, p_excluded_department_ids, p_notes,
    p_is_recurring, auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_public_holiday(text,date,date,text,uuid,uuid,uuid[],text,boolean) from anon;


create or replace function public.update_public_holiday(
  p_id                      uuid,
  p_name                    text     default null,
  p_holiday_date            date     default null,
  p_end_date                date     default null,
  p_scope                   text     default null,
  p_legal_entity_id         uuid     default null,
  p_department_id           uuid     default null,
  p_excluded_department_ids uuid[]   default null,
  p_notes                   text     default null,
  p_is_recurring            boolean  default null,
  p_is_active               boolean  default null
)
returns void
language plpgsql security invoker
as $$
begin
  update public.public_holidays set
    name                    = coalesce(p_name, name),
    holiday_date            = coalesce(p_holiday_date, holiday_date),
    end_date                = case when p_end_date is distinct from null then p_end_date else end_date end,
    scope                   = coalesce(p_scope, scope),
    legal_entity_id         = case when p_legal_entity_id is distinct from null then p_legal_entity_id else legal_entity_id end,
    department_id           = case when p_department_id is distinct from null then p_department_id else department_id end,
    excluded_department_ids = coalesce(p_excluded_department_ids, excluded_department_ids),
    notes                   = case when p_notes is distinct from null then p_notes else notes end,
    is_recurring            = coalesce(p_is_recurring, is_recurring),
    is_active               = coalesce(p_is_active, is_active),
    updated_at              = now()
  where id = p_id;
end;
$$;

revoke all on function public.update_public_holiday(uuid,text,date,date,text,uuid,uuid,uuid[],text,boolean,boolean) from anon;


create or replace function public.delete_public_holiday(p_id uuid)
returns void
language plpgsql security invoker
as $$
begin
  delete from public.public_holidays where id = p_id;
end;
$$;

revoke all on function public.delete_public_holiday(uuid) from anon;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Task mutations — create + transition
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_create_task(
  p_title       text,
  p_description text default null,
  p_assignee_id uuid default null,
  p_priority    text default 'medium',
  p_due_date    date default null
)
returns uuid
language plpgsql security invoker
as $$
declare
  v_id     uuid;
  v_emp_id uuid;
begin
  select id into v_emp_id
  from public.employees
  where user_id = auth.uid() and is_active
  limit 1;

  insert into public.tasks (
    title, description, assignee_employee_id,
    priority, due_date, created_by_employee_id, created_by
  ) values (
    p_title, p_description, p_assignee_id,
    p_priority, p_due_date, v_emp_id, auth.uid()
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_create_task(text,text,uuid,text,date) from anon;


create or replace function public.admin_transition_task(
  p_id     uuid,
  p_status text
)
returns void
language plpgsql security invoker
as $$
begin
  update public.tasks
  set status = p_status, updated_at = now()
  where id = p_id;
end;
$$;

revoke all on function public.admin_transition_task(uuid,text) from anon;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Security event — mark handled
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_handle_security_event(p_id uuid)
returns void
language plpgsql security invoker
as $$
begin
  update public.security_events
  set handled = true,
      handled_at = now(),
      handled_by = auth.uid(),
      updated_at = now()
  where id = p_id;
end;
$$;

revoke all on function public.admin_handle_security_event(uuid) from anon;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. Integration — toggle enabled/disabled
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_toggle_integration(
  p_id      uuid,
  p_enabled boolean
)
returns void
language plpgsql security invoker
as $$
begin
  update public.integrations
  set is_enabled = p_enabled,
      status = case when p_enabled then 'active' else 'inactive' end,
      updated_at = now()
  where id = p_id;
end;
$$;

revoke all on function public.admin_toggle_integration(uuid,boolean) from anon;
