-- Migration 0041: complete manager and executive mobile workspaces.
-- The mobile client receives server-scoped aggregates only; sensitive tables
-- remain protected by their existing RLS policies and controlled RPCs.

begin;

create or replace function public.get_mobile_manager_operations(
  p_from date default ((now() at time zone 'Africa/Cairo')::date),
  p_to date default (((now() at time zone 'Africa/Cairo')::date) + 14)
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager_id uuid := public.current_employee_id();
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  if v_manager_id is null then
    raise exception 'employee profile is not linked' using errcode = '42501';
  end if;

  if p_from is null or p_to is null or p_to < p_from or p_to > p_from + 45 then
    raise exception 'invalid operations date range' using errcode = '22023';
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
      select 1
      from public.manager_relations mr
      where mr.manager_employee_id = v_manager_id
        and mr.relation_type = 'primary'
        and mr.effective_from <= v_today
        and (mr.effective_to is null or mr.effective_to >= v_today)
    )
  ) then
    raise exception 'manager workspace is not allowed' using errcode = '42501';
  end if;

  with team_scope as (
    select e.id, e.employee_code, e.full_name_ar
    from public.manager_relations mr
    join public.employees e on e.id = mr.employee_id
    where mr.manager_employee_id = v_manager_id
      and mr.relation_type = 'primary'
      and mr.effective_from <= v_today
      and (mr.effective_to is null or mr.effective_to >= v_today)
      and e.is_active = true
      and e.is_deleted = false
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'metrics', jsonb_build_object(
      'scheduledToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status = 'scheduled'
      ),
      'awayToday', (
        select count(*)
        from public.roster_days rd
        join team_scope ts on ts.id = rd.employee_id
        where rd.work_date = v_today and rd.day_status in ('leave','mission','rest','holiday')
      ),
      'overdueTasks', (
        select count(*)
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress') and t.due_date < v_today
      ),
      'expiringDocuments', (
        select count(*)
        from public.documents d
        join team_scope ts on ts.id = d.owner_employee_id
        where d.status <> 'archived' and d.expiry_date between v_today and v_today + 60
      ),
      'missingReports', (
        select count(*)
        from team_scope ts
        where not exists (
          select 1 from public.daily_reports dr
          where dr.employee_id = ts.id and dr.report_date = v_today
        )
      )
    ),
    'calendar', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rd.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'workDate', rd.work_date,
        'dayStatus', rd.day_status,
        'shiftName', s.name,
        'startsAt', coalesce(rd.start_override, s.start_time),
        'endsAt', coalesce(rd.end_override, s.end_time),
        'notes', rd.notes
      ) order by rd.work_date, ts.full_name_ar)
      from public.roster_days rd
      join team_scope ts on ts.id = rd.employee_id
      left join public.shifts s on s.id = rd.shift_id
      where rd.work_date between p_from and p_to and rd.day_status <> 'cancelled'
    ), '[]'::jsonb),
    'documentAlerts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id,
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code,
        'title', d.title,
        'documentType', d.doc_type,
        'expiryDate', d.expiry_date,
        'status', case when d.expiry_date < v_today then 'expired' else d.status end
      ) order by d.expiry_date, ts.full_name_ar)
      from public.documents d
      join team_scope ts on ts.id = d.owner_employee_id
      where d.status <> 'archived' and d.expiry_date <= v_today + 60
    ), '[]'::jsonb),
    'tasks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'employeeId', x.employee_id,
        'employeeName', x.employee_name,
        'title', x.title,
        'priority', x.priority,
        'status', x.status,
        'dueDate', x.due_date,
        'isOverdue', x.due_date is not null and x.due_date < v_today
      ) order by x.is_overdue desc, x.due_date nulls last, x.created_at desc)
      from (
        select t.*, ts.id employee_id, ts.full_name_ar employee_name,
          (t.due_date is not null and t.due_date < v_today) is_overdue
        from public.tasks t
        join team_scope ts on ts.id = t.assignee_employee_id
        where t.status in ('pending','in_progress')
        order by is_overdue desc, t.due_date nulls last, t.created_at desc
        limit 40
      ) x
    ), '[]'::jsonb),
    'missingReports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'employeeId', ts.id,
        'employeeName', ts.full_name_ar,
        'employeeCode', ts.employee_code
      ) order by ts.full_name_ar)
      from team_scope ts
      where not exists (
        select 1 from public.daily_reports dr
        where dr.employee_id = ts.id and dr.report_date = v_today
      )
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.get_mobile_manager_operations(date,date) from public;
grant execute on function public.get_mobile_manager_operations(date,date) to authenticated;

create or replace function public.get_mobile_executive_command_center()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_allowed boolean;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'comms.decision.manage',
    'reports.executive.read',
    'reports.schedule.manage',
    'live_location.request',
    'risks.read',
    'incidents.read'
  ]);
  if not v_allowed then
    raise exception 'executive command center access denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id,
        'name', coalesce(s.name_ar, r.report_type),
        'reportType', r.report_type,
        'scheduleKind', s.schedule_kind,
        'status', r.status,
        'periodStart', r.period_start,
        'periodEnd', r.period_end,
        'storagePath', r.result_storage_path,
        'summary', r.result_summary,
        'attempts', r.attempts,
        'createdAt', r.created_at,
        'completedAt', r.completed_at,
        'errorDetail', r.error_detail
      ) order by r.created_at desc)
      from (
        select * from public.report_runs order by created_at desc limit 60
      ) r
      left join public.scheduled_reports s on s.id = r.scheduled_report_id
    ), '[]'::jsonb),
    'reportSchedules', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name_ar,
        'reportType', s.report_type,
        'scheduleKind', s.schedule_kind,
        'active', s.active,
        'nextRunAt', s.next_run_at,
        'lastRunAt', s.last_run_at
      ) order by s.active desc, s.next_run_at nulls last)
      from public.scheduled_reports s
    ), '[]'::jsonb),
    'executionItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'decisionId', x.decision_id,
        'decisionTitle', x.decision_title,
        'title', x.title,
        'ownerName', x.owner_name,
        'dueAt', x.due_at,
        'status', x.status,
        'progressPercent', x.progress_percent,
        'blocker', x.blocker,
        'updatedAt', x.updated_at
      ) order by x.is_overdue desc, x.due_at nulls last, x.updated_at desc nulls last)
      from (
        select i.*, d.title decision_title, e.full_name_ar owner_name,
          (i.due_at is not null and i.due_at < now() and i.status not in ('completed','cancelled')) is_overdue
        from public.decision_execution_items i
        join public.administrative_decisions d on d.id = i.decision_id
        left join public.employees e on e.id = i.owner_employee_id
        where i.status <> 'cancelled'
        order by is_overdue desc, i.due_at nulls last
        limit 80
      ) x
    ), '[]'::jsonb),
    'polls', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id,
        'decisionId', p.decision_id,
        'decisionTitle', d.title,
        'question', p.question,
        'pollType', p.poll_type,
        'status', p.status,
        'isAnonymous', p.is_anonymous,
        'opensAt', p.opens_at,
        'closesAt', p.closes_at,
        'quorumPercent', p.quorum_percent,
        'approvalThresholdPercent', p.approval_threshold_percent,
        'eligibleCount', (select count(*) from public.decision_poll_eligibility pe where pe.poll_id = p.id),
        'voteCount', (select count(*) from public.decision_poll_votes pv where pv.poll_id = p.id),
        'canVote', exists(select 1 from public.decision_poll_eligibility pe where pe.poll_id = p.id and pe.employee_id = v_employee_id),
        'myOptionIds', coalesce((select to_jsonb(pv.option_ids) from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id), '[]'::jsonb),
        'myRating', (select pv.rating from public.decision_poll_votes pv where pv.poll_id = p.id and pv.employee_id = v_employee_id),
        'options', coalesce((
          select jsonb_agg(jsonb_build_object('id', o.id, 'label', o.label) order by o.sort_order, o.label)
          from public.decision_poll_options o where o.poll_id = p.id
        ), '[]'::jsonb)
      ) order by p.status = 'open' desc, p.closes_at)
      from public.decision_polls p
      left join public.administrative_decisions d on d.id = p.decision_id
      where p.status in ('open','closed','certified')
        and (
          public.current_is_full_access()
          or public.has_permission('comms.decision.manage')
          or exists (
            select 1 from public.decision_poll_eligibility pe
            where pe.poll_id = p.id and pe.employee_id = v_employee_id
          )
        )
    ), '[]'::jsonb),
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'likelihood', x.likelihood,
        'impact', x.impact,
        'severity', x.severity,
        'status', x.status,
        'ownerName', x.owner_name,
        'updatedAt', x.updated_at,
        'createdAt', x.created_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select r.*, e.full_name_ar owner_name
        from public.risks r
        left join public.employees e on e.id = r.owner_employee_id
        where r.status in ('open','mitigating','accepted')
        order by r.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'incidents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'description', x.description,
        'severity', x.severity,
        'status', x.status,
        'reporterName', x.reporter_name,
        'createdAt', x.created_at,
        'updatedAt', x.updated_at
      ) order by case x.severity when 'critical' then 1 when 'high' then 2 when 'medium' then 3 else 4 end, x.created_at desc)
      from (
        select i.*, e.full_name_ar reporter_name
        from public.incidents i
        left join public.employees e on e.id = i.reported_by
        where i.status in ('open','investigating')
        order by i.created_at desc
        limit 60
      ) x
    ), '[]'::jsonb),
    'meetings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id,
        'title', x.title,
        'scheduledAt', x.scheduled_at,
        'locationOrLink', x.location_or_link,
        'organizerName', x.organizer_name,
        'status', x.status
      ) order by x.scheduled_at)
      from (
        select m.*, e.full_name_ar organizer_name
        from public.meetings m
        left join public.employees e on e.id = m.organizer_employee_id
        where m.status = 'scheduled' and m.scheduled_at >= now() - interval '2 hours'
        order by m.scheduled_at
        limit 40
      ) x
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  );
end;
$$;

revoke all on function public.get_mobile_executive_command_center() from public;
grant execute on function public.get_mobile_executive_command_center() to authenticated;

commit;
