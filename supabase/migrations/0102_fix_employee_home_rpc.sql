-- 0102: Fix get_employee_home — security definer + NULL guard
-- Problem: security invoker means RLS blocks subqueries for users without
-- proper role assignments. Newly activated employees get all zeros silently.
-- Fix: Switch to security definer (data is already scoped to current user)
-- and handle NULL current_employee_id().

create or replace function public.get_employee_home()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid;
begin
  v_me := public.current_employee_id();

  if v_me is null then
    return jsonb_build_object(
      'pendingRequests', 0,
      'activeTasks', 0,
      'kpiStage', null,
      'unreadNotifications', (select count(*) from public.notifications
        where recipient_user_id = auth.uid() and is_read = false),
      'unreadOfficial', 0,
      'pendingLocationRequests', 0,
      'lastUpdatedAt', now()
    );
  end if;

  return jsonb_build_object(
    'pendingRequests', (select count(*) from public.requests
      where employee_id = v_me and status = 'pending'),
    'activeTasks', (select count(*) from public.tasks
      where assignee_employee_id = v_me
        and status not in ('done', 'cancelled')),
    'kpiStage', (select current_stage from public.kpi_evaluations
      where employee_id = v_me order by created_at desc limit 1),
    'unreadNotifications', (select count(*) from public.notifications
      where recipient_user_id = auth.uid() and is_read = false),
    'unreadOfficial', (select count(*) from public.decision_recipients dr
      join public.administrative_decisions d on d.id = dr.decision_id
      left join public.decision_reads rr on rr.decision_id = d.id
        and rr.employee_id = dr.employee_id
      where dr.employee_id = v_me
        and d.status = 'published'
        and coalesce(rr.acknowledged, false) = false),
    'pendingLocationRequests', (select count(*) from public.live_location_requests
      where employee_id = v_me
        and status = 'pending'
        and expires_at > now()),
    'lastUpdatedAt', now()
  );
end;
$$;

revoke execute on function public.get_employee_home() from public;
grant  execute on function public.get_employee_home() to authenticated;
