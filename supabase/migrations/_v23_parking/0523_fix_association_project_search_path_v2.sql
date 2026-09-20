-- Add SET search_path to match other Supabase functions
-- This is required for PostgREST schema cache on hosted Supabase

CREATE OR REPLACE FUNCTION public.get_association_projects()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $fn$
declare
  v_result jsonb;
  v_emp uuid;
  v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();
  if not v_full and v_emp is null then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  select jsonb_build_object(
    'projects', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'code', p.code, 'name', p.name, 'description', p.description,
        'departmentId', p.department_id, 'departmentName', d.name,
        'ownerId', p.owner_employee_id, 'ownerName', e.full_name_ar,
        'status', p.status, 'approvalStatus', p.approval_status,
        'priority', p.priority, 'progress', p.progress,
        'startDate', p.start_date, 'targetEndDate', p.target_end_date,
        'lastUpdateAt', p.last_update_at, 'lastUpdateNote', p.last_update_note,
        'approvedBy', p.approved_by, 'approvedAt', p.approved_at,
        'rejectionReason', p.rejection_reason,
        'totalSteps', (select count(*) from public.association_project_steps s where s.project_id = p.id),
        'completedSteps', (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'done'),
        'remainingSteps', (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status not in ('done','cancelled')),
        'blockedSteps', (select count(*) from public.association_project_steps s where s.project_id = p.id and s.status = 'blocked'),
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
      ))
      from public.association_projects p
      join public.departments d on d.id = p.department_id
      join public.employees e on e.id = p.owner_employee_id
      where v_full or (p.owner_employee_id = v_emp)
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
$fn$;

CREATE OR REPLACE FUNCTION public.get_association_project_detail(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $fn$
declare v_result jsonb;
declare v_emp uuid;
declare v_full boolean;
begin
  v_emp := public.current_employee_id();
  v_full := public.current_is_full_access();
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
        'departmentId', p.department_id, 'departmentName', d.name,
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
$fn$;

NOTIFY pgrst, 'reload schema';
