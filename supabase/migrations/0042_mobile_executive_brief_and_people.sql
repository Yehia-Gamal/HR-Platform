-- Migration 0042: executive daily brief and privacy-minimised employee summary.

begin;

create or replace function public.get_mobile_executive_brief(
  p_period text default 'morning'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_yesterday date := ((now() at time zone 'Africa/Cairo')::date - 1);
  v_allowed boolean;
begin
  if p_period not in ('morning','evening') then
    raise exception 'invalid brief period' using errcode = '22023';
  end if;

  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'comms.decision.manage',
    'reports.executive.read',
    'live_location.request',
    'risks.read',
    'incidents.read'
  ]);
  if not v_allowed then
    raise exception 'executive brief access denied' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'period', p_period,
    'briefDate', v_today,
    'attendance', jsonb_build_object(
      'presentToday', (select count(*) from public.attendance_daily where work_date = v_today and status in ('present','late','partial')),
      'presentYesterday', (select count(*) from public.attendance_daily where work_date = v_yesterday and status in ('present','late','partial')),
      'lateToday', (select count(*) from public.attendance_daily where work_date = v_today and (status = 'late' or late_minutes > 0)),
      'lateYesterday', (select count(*) from public.attendance_daily where work_date = v_yesterday and (status = 'late' or late_minutes > 0)),
      'absentToday', (select count(*) from public.attendance_daily where work_date = v_today and status = 'absent'),
      'onLeaveToday', (select count(*) from public.attendance_daily where work_date = v_today and status = 'on_leave'),
      'weekAverageLate', coalesce((
        select round(avg(x.daily_count), 1)
        from (
          select work_date, count(*)::numeric daily_count
          from public.attendance_daily
          where work_date between v_today - 7 and v_today - 1
            and (status = 'late' or late_minutes > 0)
          group by work_date
        ) x
      ), 0)
    ),
    'decisions', jsonb_build_object(
      'urgentActions', (select count(*) from public.requests where status = 'pending' and decision_due_at < now() + interval '4 hours'),
      'pendingApprovals', (select count(*) from public.requests where status = 'pending'),
      'pendingFinalKpi', (select count(*) from public.kpi_evaluations where current_stage = 'executive'),
      'decisionsInReview', (select count(*) from public.administrative_decisions where status = 'in_review'),
      'publishedToday', (select count(*) from public.administrative_decisions where status = 'published' and published_at >= v_today::timestamptz),
      'reportsReadyToday', (select count(*) from public.report_runs where status = 'completed' and completed_at >= v_today::timestamptz)
    ),
    'risk', jsonb_build_object(
      'criticalRisks', (select count(*) from public.risks where status in ('open','mitigating') and severity = 'critical'),
      'highRisks', (select count(*) from public.risks where status in ('open','mitigating') and severity = 'high'),
      'activeIncidents', (select count(*) from public.incidents where status in ('open','investigating')),
      'criticalIncidents', (select count(*) from public.incidents where status in ('open','investigating') and severity = 'critical')
    ),
    'highlights', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', h.kind,
        'title', h.title,
        'value', h.value,
        'severity', h.severity,
        'detail', h.detail
      ) order by h.rank)
      from (
        select * from (
          select 'incident'::text kind, 'حوادث حرجة نشطة'::text title,
            (select count(*)::integer from public.incidents where status in ('open','investigating') and severity = 'critical') value,
            'critical'::text severity, 'تحتاج متابعة فورية من مركز المخاطر'::text detail, 1 rank
          union all
          select 'action', 'إجراءات بمهلة قصيرة',
            (select count(*)::integer from public.requests where status = 'pending' and decision_due_at < now() + interval '4 hours'),
            'critical', 'موعد القرار خلال أربع ساعات', 2
          union all
          select 'risk', 'مخاطر حرجة مفتوحة',
            (select count(*)::integer from public.risks where status in ('open','mitigating') and severity = 'critical'),
            'high', 'راجع المالك وخطة المعالجة الحالية', 3
          union all
          select 'kpi', 'تقييمات تنتظر الاعتماد النهائي',
            (select count(*)::integer from public.kpi_evaluations where current_stage = 'executive'),
            'high', 'اعتماد تنفيذي نهائي مطلوب', 4
          union all
          select 'report', 'تقارير جديدة جاهزة اليوم',
            (select count(*)::integer from public.report_runs where status = 'completed' and completed_at >= v_today::timestamptz),
            'normal', 'متاحة داخل صندوق التقارير التنفيذي', 5
          union all
          select 'attendance', 'حالات تأخير اليوم',
            (select count(*)::integer from public.attendance_daily where work_date = v_today and (status = 'late' or late_minutes > 0)),
            'normal', 'مقارنة الحضور متاحة في البطاقة اليومية', 6
        ) raw_highlights
        where raw_highlights.value > 0
        order by raw_highlights.rank
        limit 5
      ) h
    ), '[]'::jsonb),
    'generatedAt', now(),
    'sourceLabel', 'مصادر تشغيلية مباشرة من Supabase'
  );
end;
$$;

revoke all on function public.get_mobile_executive_brief(text) from public;
grant execute on function public.get_mobile_executive_brief(text) to authenticated;

create or replace function public.get_mobile_executive_people(
  p_search text default null,
  p_limit integer default 60
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_allowed boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'executive people access denied' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x.id,
      'employeeCode', x.employee_code,
      'name', x.full_name_ar,
      'photoUrl', x.photo_url,
      'jobTitle', x.job_title,
      'department', x.department,
      'team', x.team,
      'attendanceStatus', x.attendance_status,
      'pendingRequests', x.pending_requests,
      'openTasks', x.open_tasks,
      'latestKpiScore', x.latest_kpi_score
    ) order by x.full_name_ar)
    from (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
        jt.name job_title, d.name department, tm.name team,
        ad.status attendance_status,
        (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending') pending_requests,
        (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')) open_tasks,
        (select ke.final_score from public.kpi_evaluations ke join public.kpi_cycles kc on kc.id = ke.cycle_id where ke.employee_id = e.id order by kc.period_month desc, ke.created_at desc limit 1) latest_kpi_score
      from public.employees e
      left join public.job_titles jt on jt.id = e.job_title_id
      left join public.departments d on d.id = e.department_id
      left join public.teams tm on tm.id = e.team_id
      left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
      where e.is_active = true and e.is_deleted = false
        and (v_search is null or e.full_name_ar ilike '%' || v_search || '%' or e.employee_code ilike '%' || v_search || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_mobile_executive_people(text,integer) from public;
grant execute on function public.get_mobile_executive_people(text,integer) to authenticated;

create or replace function public.get_mobile_executive_employee_summary(
  p_employee_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_allowed boolean;
  v_result jsonb;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review',
    'reports.executive.read',
    'live_location.request',
    'people.employee.read'
  ]);
  if not v_allowed then
    raise exception 'executive employee summary access denied' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'id', e.id,
    'employeeCode', e.employee_code,
    'name', e.full_name_ar,
    'photoUrl', e.photo_url,
    'status', e.status,
    'jobTitle', jt.name,
    'position', p.name,
    'department', d.name,
    'team', tm.name,
    'branch', b.name,
    'workSite', ws.name,
    'managerName', manager.full_name_ar,
    'hireDate', e.hire_date,
    'pendingRequests', (select count(*) from public.requests r where r.employee_id = e.id and r.status = 'pending'),
    'openTasks', (select count(*) from public.tasks t where t.assignee_employee_id = e.id and t.status in ('pending','in_progress')),
    'expiringDocuments', (select count(*) from public.documents doc where doc.owner_employee_id = e.id and doc.status <> 'archived' and doc.expiry_date <= current_date + 60),
    'latestKpi', (
      select jsonb_build_object('score', ke.final_score, 'rating', ke.final_rating, 'stage', ke.current_stage, 'periodMonth', kc.period_month)
      from public.kpi_evaluations ke
      join public.kpi_cycles kc on kc.id = ke.cycle_id
      where ke.employee_id = e.id
      order by kc.period_month desc, ke.created_at desc
      limit 1
    ),
    'recentAttendance', coalesce((
      select jsonb_agg(jsonb_build_object(
        'workDate', a.work_date,
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'workMinutes', a.work_minutes,
        'firstCheckIn', a.first_check_in,
        'lastCheckOut', a.last_check_out
      ) order by a.work_date desc)
      from (
        select * from public.attendance_daily
        where employee_id = e.id
        order by work_date desc
        limit 14
      ) a
    ), '[]'::jsonb),
    'lastUpdatedAt', now()
  ) into v_result
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.positions p on p.id = e.position_id
  left join public.departments d on d.id = e.department_id
  left join public.teams tm on tm.id = e.team_id
  left join public.branches b on b.id = e.branch_id
  left join public.work_sites ws on ws.id = e.work_site_id
  left join lateral (
    select me.full_name_ar
    from public.manager_relations mr
    join public.employees me on me.id = mr.manager_employee_id
    where mr.employee_id = e.id and mr.relation_type = 'primary'
      and mr.effective_from <= current_date
      and (mr.effective_to is null or mr.effective_to >= current_date)
    order by mr.effective_from desc
    limit 1
  ) manager on true
  where e.id = p_employee_id and e.is_active = true and e.is_deleted = false;

  if v_result is null then
    raise exception 'employee summary not found' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

revoke all on function public.get_mobile_executive_employee_summary(uuid) from public;
grant execute on function public.get_mobile_executive_employee_summary(uuid) to authenticated;

commit;
