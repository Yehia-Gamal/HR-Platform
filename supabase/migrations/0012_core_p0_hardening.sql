-- Migration 0012: Core P0 hardening
-- Fixes scope-aware access, multi-stage request decisions, and direct Passkey writes.
-- Must be validated with pgTAP/RLS tests before Production.

begin;

-- =========================================================
-- 1) Recursive management hierarchy
-- =========================================================
create or replace function public.is_management_descendant(
  p_manager_employee_id uuid,
  p_target_employee_id  uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with recursive descendants(employee_id) as (
    select mr.employee_id
    from public.manager_relations mr
    where mr.manager_employee_id = p_manager_employee_id
      and mr.effective_from <= now()
      and (mr.effective_to is null or mr.effective_to > now())
    union
    select mr.employee_id
    from public.manager_relations mr
    join descendants d on d.employee_id = mr.manager_employee_id
    where mr.effective_from <= now()
      and (mr.effective_to is null or mr.effective_to > now())
  )
  select exists(select 1 from descendants where employee_id = p_target_employee_id);
$$;
revoke execute on function public.is_management_descendant(uuid, uuid) from public;
grant execute on function public.is_management_descendant(uuid, uuid) to authenticated;

-- Scope-aware employee access. This supersedes the previous implementation.
create or replace function public.can_access_employee(
  p_employee_id uuid,
  p_code text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid;
  v_scope text;
  v_ovr jsonb;
  v_target_dept uuid;
  v_target_branch uuid;
  v_target_team uuid;
begin
  if p_employee_id is null then return false; end if;
  if public.current_is_full_access() then return true; end if;

  v_me := public.current_employee_id();
  if v_me is null then return false; end if;
  if v_me = p_employee_id then return true; end if;

  if p_code is null then
    return exists (
      select 1
      from public.manager_relations mr
      where mr.manager_employee_id = v_me
        and mr.employee_id = p_employee_id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
    );
  end if;

  select e.department_id, e.branch_id, e.team_id
    into v_target_dept, v_target_branch, v_target_team
  from public.employees e
  where e.id = p_employee_id;

  if not found then return false; end if;

  for v_scope, v_ovr in
    select rp.scope, coalesce(ur.scope_override, '{}'::jsonb)
    from public.user_roles ur
    join public.role_permissions rp on rp.role_id = ur.role_id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = p_code
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to is null or rp.effective_to > now())
  loop
    case v_scope
      when 'organization' then
        return true;
      when 'self' then
        if v_me = p_employee_id then return true; end if;
      when 'direct_reports' then
        if exists (
          select 1 from public.manager_relations mr
          where mr.manager_employee_id = v_me
            and mr.employee_id = p_employee_id
            and mr.effective_from <= now()
            and (mr.effective_to is null or mr.effective_to > now())
        ) then return true; end if;
      when 'management_descendants' then
        if public.is_management_descendant(v_me, p_employee_id) then return true; end if;
      when 'department' then
        if v_target_dept is not null and v_target_dept = (
          select e.department_id from public.employees e where e.id = v_me
        ) then return true; end if;
      when 'branch' then
        if v_target_branch is not null and v_target_branch = (
          select e.branch_id from public.employees e where e.id = v_me
        ) then return true; end if;
      when 'team' then
        if v_target_team is not null and v_target_team = (
          select e.team_id from public.employees e where e.id = v_me
        ) then return true; end if;
      when 'selected_departments' then
        if v_target_dept is not null
           and coalesce(v_ovr->'department_ids', '[]'::jsonb) ? v_target_dept::text then
          return true;
        end if;
      when 'selected_branches' then
        if v_target_branch is not null
           and coalesce(v_ovr->'branch_ids', '[]'::jsonb) ? v_target_branch::text then
          return true;
        end if;
      when 'selected_employees' then
        if coalesce(v_ovr->'employee_ids', '[]'::jsonb) ? p_employee_id::text then
          return true;
        end if;
      else
        null;
    end case;
  end loop;

  return false;
end;
$$;
revoke execute on function public.can_access_employee(uuid, text) from public;
grant execute on function public.can_access_employee(uuid, text) to authenticated;

-- =========================================================
-- 2) Core RLS policies now use permission + scope together
-- =========================================================
drop policy if exists employees_select on public.employees;
create policy employees_select on public.employees
  for select to authenticated
  using (public.can_access_employee(id, 'employees.read'));

drop policy if exists employees_update on public.employees;
create policy employees_update on public.employees
  for update to authenticated
  using (
    id = public.current_employee_id()
    or public.can_access_employee(id, 'people.employee.update_basic')
  )
  with check (
    id = public.current_employee_id()
    or public.can_access_employee(id, 'people.employee.update_basic')
  );

drop policy if exists employees_delete on public.employees;
create policy employees_delete on public.employees
  for delete to authenticated
  using (
    id is distinct from public.current_employee_id()
    and public.can_access_employee(id, 'employees.delete')
  );

drop policy if exists shift_assign_read on public.shift_assignments;
create policy shift_assign_read on public.shift_assignments
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.shift.read'));

drop policy if exists shift_assign_write on public.shift_assignments;
create policy shift_assign_write on public.shift_assignments
  for all to authenticated
  using (
    public.can_access_employee(employee_id, 'attendance.shift.manage')
    or public.can_access_employee(employee_id, 'attendance.shift.assign')
  )
  with check (
    public.can_access_employee(employee_id, 'attendance.shift.manage')
    or public.can_access_employee(employee_id, 'attendance.shift.assign')
  );

drop policy if exists att_events_read on public.attendance_events;
create policy att_events_read on public.attendance_events
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.record.read'));

-- No raw attendance insert from authenticated users. Use trusted RPC/Edge paths only.
drop policy if exists att_events_insert on public.attendance_events;

drop policy if exists att_events_update on public.attendance_events;
create policy att_events_update on public.attendance_events
  for update to authenticated
  using (
    public.can_access_employee(employee_id, 'attendance.record.manual_create')
    or public.can_access_employee(employee_id, 'attendance.record.review')
  )
  with check (
    public.can_access_employee(employee_id, 'attendance.record.manual_create')
    or public.can_access_employee(employee_id, 'attendance.record.review')
  );

drop policy if exists att_events_delete on public.attendance_events;
create policy att_events_delete on public.attendance_events
  for delete to authenticated
  using (public.can_access_employee(employee_id, 'attendance.record.review'));

drop policy if exists att_daily_read on public.attendance_daily;
create policy att_daily_read on public.attendance_daily
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.record.read'));

drop policy if exists att_idcheck_read on public.attendance_identity_checks;
create policy att_idcheck_read on public.attendance_identity_checks
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.identity.read'));

drop policy if exists att_risk_read on public.attendance_risk_events;
create policy att_risk_read on public.attendance_risk_events
  for select to authenticated
  using (
    employee_id is not null
    and public.can_access_employee(employee_id, 'attendance.risk.read')
  );

drop policy if exists att_exc_read on public.attendance_exceptions;
create policy att_exc_read on public.attendance_exceptions
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.exception.read'));

drop policy if exists att_permit_read on public.attendance_permits;
create policy att_permit_read on public.attendance_permits
  for select to authenticated
  using (public.can_access_employee(employee_id, 'attendance.permit.read'));

-- Requests and request detail rows.
drop policy if exists requests_select on public.requests;
create policy requests_select on public.requests
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or manager_employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id, 'requests.read')
  );

drop policy if exists leave_requests_select on public.leave_requests;
create policy leave_requests_select on public.leave_requests
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id, 'requests.read')
  );

drop policy if exists missions_select on public.missions;
create policy missions_select on public.missions
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id, 'requests.read')
  );

drop policy if exists convoy_requests_select on public.convoy_requests;
create policy convoy_requests_select on public.convoy_requests
  for select to authenticated
  using (
    employee_id = public.current_employee_id()
    or public.can_access_employee(employee_id, 'requests.read')
  );

drop policy if exists request_steps_select on public.request_steps;
create policy request_steps_select on public.request_steps
  for select to authenticated
  using (
    assignee_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.requests r
      where r.id = request_id
        and (
          r.employee_id = public.current_employee_id()
          or r.manager_employee_id = public.current_employee_id()
          or public.can_access_employee(r.employee_id, 'requests.read')
        )
    )
  );

drop policy if exists request_actions_select on public.request_actions;
create policy request_actions_select on public.request_actions
  for select to authenticated
  using (
    actor_employee_id = public.current_employee_id()
    or exists (
      select 1 from public.requests r
      where r.id = request_id
        and (
          r.employee_id = public.current_employee_id()
          or r.manager_employee_id = public.current_employee_id()
          or public.can_access_employee(r.employee_id, 'requests.read')
        )
    )
  );

drop policy if exists workflow_instances_select on public.workflow_instances;
create policy workflow_instances_select on public.workflow_instances
  for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_id
        and (
          r.employee_id = public.current_employee_id()
          or r.manager_employee_id = public.current_employee_id()
          or public.can_access_employee(r.employee_id, 'requests.read')
        )
    )
  );

-- =========================================================
-- 3) Passkey data is server-authored only
-- =========================================================
drop policy if exists passkey_cred_insert on public.passkey_credentials;
drop policy if exists passkey_cred_update on public.passkey_credentials;
drop policy if exists passkey_cred_delete on public.passkey_credentials;

drop policy if exists webauthn_ch_insert on public.webauthn_challenges;
drop policy if exists webauthn_ch_manage on public.webauthn_challenges;
drop policy if exists webauthn_ch_delete on public.webauthn_challenges;

create or replace function public.passkey_credentials_force_untrusted()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_claim_role text := coalesce(
    current_setting('request.jwt.claim.role', true),
    auth.jwt()->>'role',
    ''
  );
  v_is_trusted_server boolean := false;
begin
  v_is_trusted_server :=
    v_claim_role = 'service_role'
    or session_user in ('postgres','supabase_admin','service_role');

  if not v_is_trusted_server then
    new.trusted := false;
    new.sign_count := case when tg_op = 'INSERT' then 0 else old.sign_count end;
    new.last_used := case when tg_op = 'INSERT' then null else old.last_used end;
  end if;

  return new;
end;
$$;

comment on column public.passkey_credentials.public_key is
  'Public key encoded as base64url SPKI DER for the current verification implementation. Registration must normalize WebAuthn COSE keys to SPKI server-side.';

-- =========================================================
-- 4) Multi-stage request decision engine
-- =========================================================
create or replace function public.decide_request(
  p_request_id uuid,
  p_decision text,
  p_comment text default null
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.requests;
  v_step public.request_steps;
  v_next public.request_steps;
  v_step_def public.workflow_steps;
  v_authorized boolean := false;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_decision not in ('approve','reject') then
    raise exception 'invalid decision: %', p_decision using errcode = '22023';
  end if;

  select * into v_req
  from public.requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'request not found: %', p_request_id using errcode = 'P0002';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'request is not pending (current: %)', v_req.status using errcode = '22023';
  end if;
  if v_req.employee_id = v_me then
    raise exception 'self-approval is not allowed' using errcode = '42501';
  end if;

  select * into v_step
  from public.request_steps
  where request_id = p_request_id
    and status in ('active','escalated')
  order by step_order
  limit 1
  for update;

  -- Fallback for legacy/no-definition requests.
  if not found then
    v_authorized :=
      public.current_is_full_access()
      or v_req.manager_employee_id = v_me
      or public.can_access_employee(v_req.employee_id, 'requests.approve');

    if not v_authorized then
      raise exception 'not authorized to decide this request' using errcode = '42501';
    end if;

    update public.requests
      set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
          workflow_status = 'completed',
          decided_at = now(),
          decided_by = v_me,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;

    insert into public.request_actions(
      request_id, actor_employee_id, action, from_status, to_status, comment, created_by
    ) values (
      p_request_id, v_me, p_decision, 'pending', v_req.status, p_comment, auth.uid()
    );
    return v_req;
  end if;

  if v_step.workflow_step_id is not null then
    select * into v_step_def
    from public.workflow_steps
    where id = v_step.workflow_step_id;
  end if;

  v_authorized := public.current_is_full_access()
    or v_step.assignee_employee_id = v_me
    or (
      v_step.assignee_role_slug is not null
      and exists (
        select 1
        from public.user_roles ur
        join public.roles r on r.id = ur.role_id
        where ur.user_id = auth.uid()
          and r.slug = v_step.assignee_role_slug
          and ur.effective_from <= now()
          and (ur.effective_to is null or ur.effective_to > now())
      )
      and public.can_access_employee(
        v_req.employee_id,
        coalesce(v_step_def.approver_permission, 'requests.approve')
      )
    )
    or (
      v_step_def.approver_permission is not null
      and public.can_access_employee(v_req.employee_id, v_step_def.approver_permission)
    )
    or (
      v_req.manager_employee_id = v_me
      and v_step.step_order = 1
    );

  if not v_authorized then
    raise exception 'not authorized for the active workflow step' using errcode = '42501';
  end if;

  update public.request_steps
  set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
      acted_at = now(),
      acted_by = v_me,
      comment = p_comment,
      updated_at = now()
  where id = v_step.id;

  insert into public.request_actions(
    request_id, request_step_id, actor_employee_id, action,
    from_status, to_status, comment, created_by
  ) values (
    p_request_id, v_step.id, v_me, p_decision,
    v_step.status,
    case when p_decision = 'approve' then 'approved' else 'rejected' end,
    p_comment, auth.uid()
  );

  if p_decision = 'reject' then
    update public.request_steps
      set status = 'skipped', updated_at = now()
    where request_id = p_request_id
      and status = 'pending';

    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = 'rejected', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;

    return v_req;
  end if;

  select * into v_next
  from public.request_steps
  where request_id = p_request_id
    and status = 'pending'
    and step_order > v_step.step_order
  order by step_order
  limit 1
  for update;

  if found then
    update public.request_steps
      set status = 'active',
          due_at = now() + make_interval(hours => coalesce(v_next.sla_hours, 48)),
          updated_at = now()
    where id = v_next.id;

    update public.workflow_instances
      set current_step_order = v_next.step_order, updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set workflow_status = 'in_review',
          current_step_order = v_next.step_order,
          updated_at = now()
    where id = p_request_id
    returning * into v_req;
  else
    update public.workflow_instances
      set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = p_request_id and status = 'running';

    update public.requests
      set status = 'approved', workflow_status = 'completed',
          decided_at = now(), decided_by = v_me, updated_at = now()
    where id = p_request_id
    returning * into v_req;
  end if;

  return v_req;
end;
$$;
revoke execute on function public.decide_request(uuid, text, text) from public;
grant execute on function public.decide_request(uuid, text, text) to authenticated;

commit;
