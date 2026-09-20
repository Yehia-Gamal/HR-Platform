-- ═══════════════════════════════════════════════════════════════
-- 0518: سير عمل الموافقات على مشاريع الجمعية
-- أي مسؤول مشروع يستطيع إنشاء مشروع → بانتظار الموافقة
-- المدير التنفيذي يوافق/يرفض → يظهر على الشاشة الرئيسية
-- ═══════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════
-- 1. أعمدة الموافقة على الجدول الرئيسي
-- ═══════════════════════════════════════════════

alter table public.association_projects
  add column if not exists approval_status text not null default 'draft'
    check (approval_status in ('draft','pending_approval','approved','rejected')),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists rejection_reason text;

-- ═══════════════════════════════════════════════
-- 2. تعديل RLS: السماح للمالك بالقراءة/التعديل
-- ═══════════════════════════════════════════════

-- حذف السياسات القديمة
do $$ declare t text; begin
  for t in select unnest(array['association_projects','association_project_updates','association_project_steps']) loop
    execute format('drop policy if exists %I_admin on public.%I', t, t);
  end loop;
end $$;

-- ── association_projects ──
-- full-access: كل شيء
create policy projects_full_access on public.association_projects
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

-- المالك: قراءة مشاريعه + تعديل مشاريعه (draft/rejected فقط)
create policy projects_owner_read on public.association_projects
  for select to authenticated
  using (
    owner_employee_id = public.current_employee_id()
  );

create policy projects_owner_update on public.association_projects
  for update to authenticated
  using (owner_employee_id = public.current_employee_id())
  with check (owner_employee_id = public.current_employee_id());

-- أي مستخدم مسجل: إنشاء مشروع جديد
create policy projects_insert_auth on public.association_projects
  for insert to authenticated
  with check (true);

-- ── association_project_updates ──
-- full-access: كل شيء
create policy updates_full_access on public.association_project_updates
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

-- المالك: إضافة تحديثات لمشاريعه
create policy updates_owner_insert on public.association_project_updates
  for insert to authenticated
  with check (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

-- المالك: قراءة تحديثات مشاريعه
create policy updates_owner_read on public.association_project_updates
  for select to authenticated
  using (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

-- ── association_project_steps ──
-- full-access: كل شيء
create policy steps_full_access on public.association_project_steps
  for all to authenticated
  using (public.current_is_full_access())
  with check (public.current_is_full_access());

-- المالك: إضافة/تعديل/حذف خطوات مشاريعه
create policy steps_owner_insert on public.association_project_steps
  for insert to authenticated
  with check (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

create policy steps_owner_update on public.association_project_steps
  for update to authenticated
  using (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  )
  with check (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

create policy steps_owner_delete on public.association_project_steps
  for delete to authenticated
  using (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

-- المالك: قراءة خطوات مشاريعه
create policy steps_owner_read on public.association_project_steps
  for select to authenticated
  using (
    exists (
      select 1 from public.association_projects p
      where p.id = project_id and p.owner_employee_id = public.current_employee_id()
    )
  );

-- ═══════════════════════════════════════════════
-- 3. تعديل get_association_projects
-- full-access يرى كل شيء، المالك يرى مشاريعه فقط
-- ═══════════════════════════════════════════════

create or replace function public.get_association_projects()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_result jsonb;
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full and v_emp is null then
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
        'approvalStatus',  p.approval_status,
        'priority',        p.priority,
        'progress',        p.progress,
        'startDate',       p.start_date,
        'targetEndDate',   p.target_end_date,
        'lastUpdateAt',    p.last_update_at,
        'lastUpdateNote',  p.last_update_note,
        'approvedBy',      p.approved_by,
        'approvedAt',      p.approved_at,
        'rejectionReason', p.rejection_reason,
        'totalSteps',      (select count(*) from public.association_project_steps s where s.project_id = p.id),
        'completedSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'done'),
        'remainingSteps',  (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status not in ('done','cancelled')),
        'blockedSteps',    (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'blocked'),
        'ledStatus',       case
                              when p.approval_status = 'pending_approval' then 'pending'
                              when p.approval_status = 'rejected' then 'rejected'
                              when p.approval_status = 'draft' then 'draft'
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
      where
        -- full-access: كل المشاريع
        v_full
        -- المالك: مشاريعه فقط (مع المعلقة والمرفوضة)
        or (p.owner_employee_id = v_emp)
      order by
        case p.approval_status when 'pending_approval' then 0 when 'draft' then 1 else 2 end,
        case p.priority when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end,
        p.updated_at desc
    ), '[]'::jsonb),
    'lastUpdatedAt', now(),
    'isFullAccess', v_full
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_association_projects() from public;
grant execute on function public.get_association_projects() to authenticated;

-- ═══════════════════════════════════════════════
-- 4. تعديل get_association_project_detail
-- ═══════════════════════════════════════════════

create or replace function public.get_association_project_detail(p_project_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_result jsonb;
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  -- التحقق من الصلاحية
  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id and owner_employee_id = v_emp
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
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
        'status', p.status, 'approvalStatus', p.approval_status,
        'priority', p.priority, 'progress', p.progress,
        'startDate', p.start_date, 'targetEndDate', p.target_end_date,
        'lastUpdateAt', p.last_update_at, 'lastUpdateNote', p.last_update_note,
        'approvedBy', p.approved_by, 'approvedAt', p.approved_at,
        'rejectionReason', p.rejection_reason,
        'ledStatus', case
          when p.approval_status = 'pending_approval' then 'pending'
          when p.approval_status = 'rejected' then 'rejected'
          when p.approval_status = 'draft' then 'draft'
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
-- 5. تعديل create_association_project
-- أي مستخدم مسجل يستطيع إنشاء مشروع (draft)
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
  -- لا حاجة لـ full-access: أي مستخدم يستطيع إنشاء مشروع
  insert into public.association_projects (
    code, name, description, department_id, owner_employee_id,
    status, approval_status, priority, start_date, target_end_date, created_by
  ) values (
    p_code, p_name, p_description, p_department_id, p_owner_employee_id,
    'planned', 'draft', p_priority, p_start_date, p_target_end_date, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) from public;
grant execute on function public.create_association_project_admin(text,text,text,uuid,uuid,text,date,date) to authenticated;

-- ═══════════════════════════════════════════════
-- 6. تعديل update_association_project_admin
-- المالك يستطيع تعديل مشاريعه (draft/rejected فقط)
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
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  -- full-access: يعدل أي مشروع
  -- المالك: يعدل مشاريعه فقط إذا كانت draft/rejected
  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id
        and owner_employee_id = v_emp
        and approval_status in ('draft','rejected')
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
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
-- 7. تعديل add_project_update_admin
-- المالك يستطيع إضافة تحديثات لمشاريعه (approved فقط)
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
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  -- full-access: أي مشروع
  -- المالك: مشاريعه فقط إذا كانت approved
  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id
        and owner_employee_id = v_emp
        and approval_status = 'approved'
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
  end if;

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
-- 8. تعديل upsert_project_step_admin
-- المالك يستطيع إدارة خطوات مشاريعه
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
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_projects
      where id = p_project_id
        and owner_employee_id = v_emp
        and approval_status in ('approved','pending_approval')
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
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
-- 9. تعديل delete_project_step_admin
-- ═══════════════════════════════════════════════

create or replace function public.delete_project_step_admin(p_step_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();

  if not v_full then
    if v_emp is null or not exists (
      select 1 from public.association_project_steps s
      join public.association_projects p on p.id = s.project_id
      where s.id = p_step_id
        and p.owner_employee_id = v_emp
        and p.approval_status in ('approved','pending_approval')
    ) then
      raise exception 'FORBIDDEN' using errcode = '42501';
    end if;
  end if;

  delete from public.association_project_steps where id = p_step_id;
end;
$$;

revoke all on function public.delete_project_step_admin(uuid) from public;
grant execute on function public.delete_project_step_admin(uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 10. RPC جديدة: submit_project_for_approval
-- المالك يقدم مشروعه للموافقة
-- ═══════════════════════════════════════════════

create or replace function public.submit_project_for_approval(p_project_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_emp uuid;
begin
  v_emp := public.current_employee_id();
  if v_emp is null then
    raise exception 'EMPLOYEE_CONTEXT_REQUIRED' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.association_projects
    where id = p_project_id
      and owner_employee_id = v_emp
      and approval_status in ('draft','rejected')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  update public.association_projects set
    approval_status = 'pending_approval',
    rejection_reason = null
  where id = p_project_id;
end;
$$;

revoke all on function public.submit_project_for_approval(uuid) from public;
grant execute on function public.submit_project_for_approval(uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 11. RPC جديدة: approve_project
-- المدير التنفيذي يوافق على مشروع
-- ═══════════════════════════════════════════════

create or replace function public.approve_project(p_project_id uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.association_projects
    where id = p_project_id and approval_status = 'pending_approval'
  ) then
    raise exception 'PROJECT_NOT_PENDING' using errcode = '42P01';
  end if;

  update public.association_projects set
    approval_status = 'approved',
    approved_by = auth.uid(),
    approved_at = now()
  where id = p_project_id;
end;
$$;

revoke all on function public.approve_project(uuid) from public;
grant execute on function public.approve_project(uuid) to authenticated;

-- ═══════════════════════════════════════════════
-- 12. RPC جديدة: reject_project
-- المدير التنفيذي يرفض مشروع
-- ═══════════════════════════════════════════════

create or replace function public.reject_project(
  p_project_id uuid,
  p_reason     text default null
)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not public.current_is_full_access() then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.association_projects
    where id = p_project_id and approval_status = 'pending_approval'
  ) then
    raise exception 'PROJECT_NOT_PENDING' using errcode = '42P01';
  end if;

  update public.association_projects set
    approval_status = 'rejected',
    rejection_reason = p_reason
  where id = p_project_id;
end;
$$;

revoke all on function public.reject_project(uuid,text) from public;
grant execute on function public.reject_project(uuid,text) to authenticated;
