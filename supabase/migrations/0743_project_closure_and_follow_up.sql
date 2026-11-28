alter table public.association_projects
  add column plan_revision integer not null default 0,
  add column closed_at timestamptz,
  add column closed_by uuid references public.employees(id) on delete set null;

alter table public.association_project_steps add column blocker_reason text;

-- Project writes already use the checked RPCs. Keep review metadata server-owned.
revoke insert, update, delete on public.association_projects, public.association_project_steps,
  public.association_project_updates from anon, authenticated;

create function public.tg_guard_association_project_closure()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'completed' then
      raise exception 'اعتمد إغلاق المشروع بعد مراجعة خطوات التنفيذ' using errcode = '22023';
    end if;
  elsif new.status = 'completed' and old.status <> 'completed' then
    if new.closed_at is null or new.closed_at is not distinct from old.closed_at or new.closed_by is null then
      raise exception 'اعتمد إغلاق المشروع بعد مراجعة خطوات التنفيذ' using errcode = '22023';
    end if;
  elsif old.status = 'completed' and new.status <> 'completed' then
    new.closed_at := null;
    new.closed_by := null;
  end if;
  if tg_op = 'UPDATE' and
      (new.name, new.description, new.owner_employee_id, new.start_date, new.target_end_date) is distinct from
      (old.name, old.description, old.owner_employee_id, old.start_date, old.target_end_date) then
    new.plan_revision := old.plan_revision + 1;
  end if;
  return new;
end;
$$;

create trigger guard_association_project_closure
before insert or update of status, name, description, owner_employee_id, start_date, target_end_date on public.association_projects
for each row execute function public.tg_guard_association_project_closure();

-- Serialize step changes and closure on the parent row. Closure reads steps
-- without locking the child rows, so concurrent step edits cannot deadlock it.
create function public.tg_guard_association_project_steps()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  select status into v_status from public.association_projects
    where id = coalesce(new.project_id, old.project_id) for update;
  if v_status in ('completed', 'cancelled') then
    raise exception 'خطوات المشروع المغلق لا تقبل التعديل' using errcode = '22023';
  end if;
  if tg_op <> 'DELETE' and new.status <> 'blocked' then
    new.blocker_reason := null;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create trigger guard_association_project_steps
before insert or update or delete on public.association_project_steps
for each row execute function public.tg_guard_association_project_steps();

create or replace function public.tg_association_step_touch_project()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid := coalesce(new.project_id, old.project_id);
  v_total integer;
  v_done integer;
  v_started boolean;
begin
  select count(*), count(*) filter (where status = 'done'), bool_or(status in ('in_progress', 'done'))
    into v_total, v_done, v_started from public.association_project_steps where project_id = v_project;

  update public.association_projects set
    last_activity_at = now(), critical_notified_at = null, plan_revision = plan_revision + 1,
    progress = case when v_total > 0 then round(100.0 * v_done / v_total, 2) else progress end,
    status = case when status = 'planned' and approval_status = 'approved' and coalesce(v_started, false)
                  then 'active' else status end
  where id = v_project;
  return null;
end;
$$;

create function public.close_association_project(
  p_project_id uuid, p_plan_revision integer, p_review_note text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project public.association_projects%rowtype;
  v_employee uuid := public.current_employee_id();
  v_note text := nullif(btrim(p_review_note), '');
begin
  select * into v_project from public.association_projects where id = p_project_id for update;
  if not found or v_employee is null
     or not (v_employee = v_project.owner_employee_id or public.current_is_full_access()) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_project.status = 'completed' then return; end if;
  if v_project.approval_status <> 'approved' or v_project.status not in ('active', 'on_hold') then
    raise exception 'لا يمكن إغلاق مشروع لم يدخل التنفيذ' using errcode = '22023';
  end if;
  if p_plan_revision is distinct from v_project.plan_revision then
    raise exception 'تغيّرت خطة التنفيذ. حدّث المشروع وراجع الخطوات مرة أخرى' using errcode = '22023';
  end if;
  if not exists (select 1 from public.association_project_steps where project_id = p_project_id)
     or exists (select 1 from public.association_project_steps where project_id = p_project_id and status <> 'done') then
    raise exception 'سجّل خطوات التنفيذ وأكملها قبل اعتماد الإغلاق' using errcode = '22023';
  end if;
  if v_note is null then
    raise exception 'دوّن نتيجة مراجعة خطة التنفيذ' using errcode = '22023';
  end if;

  insert into public.association_project_updates(project_id, author_employee_id, note, progress, status_change)
  values (p_project_id, v_employee, v_note, null, 'completed');

  update public.association_projects set status = 'completed', closed_at = now(), closed_by = v_employee,
    last_update_note = v_note, last_update_at = now(), last_activity_at = now(), critical_notified_at = null
  where id = p_project_id;
end;
$$;

revoke all on function public.close_association_project(uuid, integer, text) from public, anon;
grant execute on function public.close_association_project(uuid, integer, text) to authenticated;

create function public.record_project_step_blocker(p_step_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_project uuid;
  v_reason text := nullif(btrim(p_reason), '');
begin
  select project_id into v_project from public.association_project_steps where id = p_step_id;
  if not found or not public._association_project_can_manage(v_project) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'اكتب سبب تعطل الخطوة' using errcode = '22023';
  end if;
  update public.association_project_steps
    set status = 'blocked', blocker_reason = v_reason
    where id = p_step_id and project_id = v_project;
  if not found then raise exception 'STEP_NOT_FOUND' using errcode = 'P0002'; end if;
end;
$$;

revoke all on function public.record_project_step_blocker(uuid, text) from public, anon;
grant execute on function public.record_project_step_blocker(uuid, text) to authenticated;

-- The same status, dates and authority feed the board, project detail and TV.
alter function public._association_project_json(uuid, integer, integer)
  rename to _association_project_json_base;
revoke all on function public._association_project_json_base(uuid, integer, integer) from public, anon, authenticated;

create function public._association_project_json(p_project_id uuid, p_warning_days integer, p_critical_days integer)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public._association_project_json_base(p.id, p_warning_days, p_critical_days)
    || jsonb_build_object(
      'planRevision', p.plan_revision,
      'canReviewClosure', public.current_employee_id() is not null
        and (public.current_is_full_access() or public.current_employee_id() = p.owner_employee_id),
      'closedAt', p.closed_at,
      'interruptionNote', case when p.status = 'on_hold' then (
        select u.note from public.association_project_updates u
        where u.project_id = p.id and u.status_change = 'on_hold'
        order by u.created_at desc, u.id limit 1
      ) end,
      'blockedStepTitle', blocked.title,
      'blockedStepAssignee', blocked.assignee_name,
      'blockedStepReason', blocked.blocker_reason,
      'nextDeadline', deadline.due_date,
      'nextDeadlineTitle', deadline.title
    )
  from public.association_projects p
  left join lateral (
    select s.title, e.full_name_ar as assignee_name, s.blocker_reason
    from public.association_project_steps s
    left join public.employees e on e.id = s.assignee_employee_id
    where s.project_id = p.id and s.status = 'blocked'
    order by s.due_date nulls last, s.sort_order, s.id limit 1
  ) blocked on true
  left join lateral (
    select candidates.due_date, candidates.title
    from (
      select due_date, title from public.association_project_steps
      where project_id = p.id and status <> 'done' and due_date is not null
      union all
      select p.target_end_date, 'الموعد المستهدف للمشروع' where p.target_end_date is not null
    ) candidates
    order by (candidates.due_date < (now() at time zone 'Africa/Cairo')::date),
      case when candidates.due_date >= (now() at time zone 'Africa/Cairo')::date then candidates.due_date end,
      candidates.due_date desc, candidates.title
    limit 1
  ) deadline on p.status not in ('completed', 'cancelled')
  where p.id = p_project_id;
$$;

revoke all on function public._association_project_json(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public._association_project_json(uuid, integer, integer) to service_role;

notify pgrst, 'reload schema';
