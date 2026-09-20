-- FIX: get_association_projects must be STABLE for PostgREST to expose it.
-- PostgREST (Supabase hosted) excludes VOLATILE functions from the schema cache by default.
-- Also: DROP + CREATE to ensure a clean re-registration in PostgREST cache.

DROP FUNCTION IF EXISTS public.get_association_projects();

CREATE FUNCTION public.get_association_projects()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $_$
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
$_$;

GRANT EXECUTE ON FUNCTION public.get_association_projects() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_association_projects() TO service_role;
COMMENT ON FUNCTION public.get_association_projects() IS 'Dashboard v4 - STABLE for PostgREST';
