begin;

-- 0660_approval_speed_report.sql
-- لوحة سرعة الاعتمادات: إحصائيات زمن الرد والوسيط لكل معتمِد ونوع طلب (بند 5 من المرحلة الثانية).

create or replace function public.get_approval_speed_report(
  p_from date default null,
  p_to   date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_from timestamptz := case when p_from is not null then p_from::timestamptz else '-infinity'::timestamptz end;
  v_to   timestamptz := case when p_to is not null then (p_to + interval '1 day')::timestamptz else 'infinity'::timestamptz end;
  v_result jsonb;
begin
  if not (
    coalesce(auth.role(), '') = 'service_role'
    or coalesce(current_setting('role', true), '') = 'service_role'
    or (coalesce(current_setting('role', true), '') = 'none' and session_user = 'postgres')
    or public.current_is_full_access()
    or public.current_has_active_role(array['executive', 'executive-director', 'hr-manager', 'hr-specialist'])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  with acted_steps as (
    select
      s.id,
      s.request_id,
      r.request_type,
      coalesce(e.id, u_emp.id) as approver_employee_id,
      coalesce(e.full_name_ar, u_emp.full_name_ar, 'غير محدد') as approver_name,
      coalesce(e.employee_code, u_emp.employee_code, '') as approver_code,
      s.assignee_role_slug,
      s.status,
      s.created_at,
      s.acted_at,
      s.escalated_at,
      greatest(0.0, extract(epoch from (s.acted_at - s.created_at)) / 3600.0) as turnaround_hours
    from public.request_steps s
    join public.requests r on r.id = s.request_id
    left join public.employees e on e.id = s.acted_by
    left join public.employees u_emp on u_emp.user_id = s.acted_by
    where s.acted_at is not null
      and s.status in ('approved', 'rejected')
      and s.acted_at >= v_from
      and s.acted_at < v_to
  ),
  pending_steps as (
    select
      s.id,
      s.request_id,
      r.request_type,
      coalesce(e.id, s.assignee_employee_id) as approver_employee_id,
      coalesce(e.full_name_ar, 'بانتظار التعيين') as approver_name,
      coalesce(e.employee_code, '') as approver_code,
      s.assignee_role_slug,
      s.created_at,
      greatest(0.0, extract(epoch from (now() - s.created_at)) / 3600.0) as age_hours
    from public.request_steps s
    join public.requests r on r.id = s.request_id
    left join public.employees e on e.id = s.assignee_employee_id
    where s.status in ('pending', 'active')
      and r.status = 'pending'
  ),
  escalated_in_period as (
    select
      coalesce(e.id, s.assignee_employee_id) as approver_employee_id,
      count(*)::int as escalated_count
    from public.request_steps s
    left join public.employees e on e.id = s.assignee_employee_id
    where s.escalated_at is not null
      and s.escalated_at >= v_from
      and s.escalated_at < v_to
    group by coalesce(e.id, s.assignee_employee_id)
  ),
  approver_agg as (
    select
      coalesce(a.approver_employee_id, p.approver_employee_id) as approver_id,
      coalesce(max(a.approver_name), max(p.approver_name), 'غير محدد') as name,
      coalesce(max(a.approver_code), max(p.approver_code), '') as code,
      coalesce(count(a.id), 0)::int as total_decisions,
      coalesce(count(a.id) filter (where a.status = 'approved'), 0)::int as approved_count,
      coalesce(count(a.id) filter (where a.status = 'rejected'), 0)::int as rejected_count,
      round(coalesce(avg(a.turnaround_hours), 0.0)::numeric, 1)::float as avg_hours,
      round(coalesce(percentile_cont(0.5) within group (order by a.turnaround_hours), 0.0)::numeric, 1)::float as median_hours,
      coalesce(max(esc.escalated_count), 0)::int as escalated_count,
      coalesce(count(distinct p.id), 0)::int as pending_count,
      round(coalesce(max(p.age_hours), 0.0)::numeric, 1)::float as oldest_pending_hours
    from acted_steps a
    full outer join pending_steps p on p.approver_employee_id = a.approver_employee_id
    left join escalated_in_period esc on esc.approver_employee_id = coalesce(a.approver_employee_id, p.approver_employee_id)
    group by coalesce(a.approver_employee_id, p.approver_employee_id)
  ),
  overall_summary as (
    select
      coalesce(count(a.id), 0)::int as total_decisions,
      coalesce(count(a.id) filter (where a.status = 'approved'), 0)::int as total_approved,
      coalesce(count(a.id) filter (where a.status = 'rejected'), 0)::int as total_rejected,
      round(coalesce(avg(a.turnaround_hours), 0.0)::numeric, 1)::float as avg_turnaround_hours,
      round(coalesce(percentile_cont(0.5) within group (order by a.turnaround_hours), 0.0)::numeric, 1)::float as median_turnaround_hours,
      (select coalesce(count(*), 0)::int from pending_steps) as total_pending,
      (select coalesce(count(*), 0)::int from public.request_steps where escalated_at is not null and escalated_at >= v_from and escalated_at < v_to) as total_escalated
    from acted_steps a
  ),
  by_type as (
    select
      r.request_type,
      count(s.id)::int as decisions_count,
      round(coalesce(avg(greatest(0.0, extract(epoch from (s.acted_at - s.created_at)) / 3600.0)), 0.0)::numeric, 1)::float as avg_hours,
      round(coalesce(percentile_cont(0.5) within group (order by greatest(0.0, extract(epoch from (s.acted_at - s.created_at)) / 3600.0)), 0.0)::numeric, 1)::float as median_hours
    from public.request_steps s
    join public.requests r on r.id = s.request_id
    where s.acted_at is not null
      and s.status in ('approved', 'rejected')
      and s.acted_at >= v_from
      and s.acted_at < v_to
    group by r.request_type
    order by count(s.id) desc
  )
  select jsonb_build_object(
    'summary', (select to_jsonb(s) from overall_summary s),
    'approvers', coalesce((select jsonb_agg(to_jsonb(app) order by app.total_decisions desc, app.pending_count desc) from approver_agg app), '[]'::jsonb),
    'byRequestType', coalesce((select jsonb_agg(to_jsonb(bt)) from by_type bt), '[]'::jsonb),
    'period', jsonb_build_object(
      'from', p_from,
      'to', p_to
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_approval_speed_report(date, date) from public, anon;
grant execute on function public.get_approval_speed_report(date, date) to authenticated;

commit;
