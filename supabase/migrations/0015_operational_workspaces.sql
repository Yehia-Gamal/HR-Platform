-- Migration 0015: Operational workspaces and canonical application RPCs
-- Adds stable, UI-facing read models for Attendance, Requests, KPI, Official Feed,
-- and Universal Action Center. Also removes the obsolete mandatory HR approval
-- stage from KPI while retaining HR-derived objective inputs.

begin;

-- ---------------------------------------------------------------------------
-- KPI canonical workflow: self -> manager -> secretary -> executive -> finalized
-- Existing rows waiting at HR are moved to secretary review.
-- ---------------------------------------------------------------------------
update public.kpi_evaluations set stage = 'secretary' where stage = 'hr';
update public.kpi_evaluations set current_stage = 'secretary' where current_stage = 'hr';
update public.kpi_scores set reviewer_stage = 'secretary' where reviewer_stage = 'hr';

alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_stage_check;
alter table public.kpi_evaluations drop constraint if exists kpi_evaluations_current_stage_check;
alter table public.kpi_scores drop constraint if exists kpi_scores_reviewer_stage_check;

alter table public.kpi_evaluations add constraint kpi_evaluations_stage_check
  check (stage in ('self','manager','secretary','executive','finalized'));
alter table public.kpi_evaluations add constraint kpi_evaluations_current_stage_check
  check (current_stage in ('self','manager','secretary','executive','finalized'));
alter table public.kpi_scores add constraint kpi_scores_reviewer_stage_check
  check (reviewer_stage in ('self','manager','secretary','executive','finalized'));

create or replace function public.advance_kpi_stage(
  p_evaluation_id uuid,
  p_action text,
  p_scores jsonb default null,
  p_note text default null
)
returns public.kpi_evaluations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.kpi_evaluations;
  v_cycle public.kpi_cycles;
  v_expected text;
  v_next text;
  v_perm text;
  v_row jsonb;
  v_final_score numeric(6,2);
begin
  case p_action
    when 'self' then v_expected := 'self'; v_next := 'manager'; v_perm := 'performance.kpi.self_assess';
    when 'manager' then v_expected := 'manager'; v_next := 'secretary'; v_perm := 'performance.kpi.manager_assess';
    when 'secretary' then v_expected := 'secretary'; v_next := 'executive'; v_perm := 'performance.kpi.secretary_review';
    when 'executive' then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.executive_review';
    when 'finalize' then v_expected := 'executive'; v_next := 'finalized'; v_perm := 'performance.kpi.finalize';
    else raise exception 'invalid KPI action: %', p_action using errcode = '22023';
  end case;

  select * into v_eval from public.kpi_evaluations where id = p_evaluation_id for update;
  if not found then raise exception 'KPI evaluation not found' using errcode = 'P0002'; end if;
  select * into v_cycle from public.kpi_cycles where id = v_eval.cycle_id;
  if v_eval.locked or v_cycle.status = 'locked' then raise exception 'KPI evaluation is locked' using errcode = '55000'; end if;
  if v_eval.current_stage is distinct from v_expected then
    raise exception 'stage_out_of_order: expected %, found %', v_expected, v_eval.current_stage using errcode = '55000';
  end if;
  if not (public.current_is_full_access() or public.has_permission(v_perm)) then
    raise exception 'insufficient privilege: % required', v_perm using errcode = '42501';
  end if;
  if p_action = 'self' and not public.current_is_full_access() and v_eval.employee_id is distinct from public.current_employee_id() then
    raise exception 'self assessment is restricted to the evaluated employee' using errcode = '42501';
  end if;
  if p_action = 'manager' and not public.current_is_full_access()
     and not public.can_access_employee(v_eval.employee_id, 'performance.kpi.manager_assess') then
    raise exception 'employee is outside manager scope' using errcode = '42501';
  end if;

  if p_scores is not null then
    for v_row in select * from jsonb_array_elements(p_scores)
    loop
      insert into public.kpi_scores(evaluation_id, criterion_id, score, reviewer_stage, note, created_by)
      values (p_evaluation_id, (v_row->>'criterion_id')::uuid, (v_row->>'score')::numeric, v_expected,
              coalesce(v_row->>'note', p_note), auth.uid())
      on conflict (evaluation_id, criterion_id, reviewer_stage)
      do update set score = excluded.score, note = excluded.note, updated_at = now();
    end loop;
  end if;

  if v_next = 'finalized' then
    select round(
      coalesce(sum(s.score * c.weight / nullif(c.max_score, 0)) / nullif(sum(c.weight), 0) * 100, v_eval.final_score), 2
    ) into v_final_score
    from public.kpi_scores s
    join public.kpi_criteria c on c.id = s.criterion_id
    where s.evaluation_id = p_evaluation_id
      and s.reviewer_stage in ('executive','manager');
  end if;

  update public.kpi_evaluations
  set stage = v_next,
      current_stage = v_next,
      locked = (v_next = 'finalized'),
      final_score = case when v_next = 'finalized' then coalesce(v_final_score, final_score) else final_score end,
      final_rating = case
        when v_next <> 'finalized' then final_rating
        when coalesce(v_final_score, final_score) >= 90 then 'ممتاز'
        when coalesce(v_final_score, final_score) >= 80 then 'جيد جدًا'
        when coalesce(v_final_score, final_score) >= 70 then 'جيد'
        when coalesce(v_final_score, final_score) >= 60 then 'مقبول'
        else 'يحتاج تحسين'
      end,
      updated_at = now()
  where id = p_evaluation_id
  returning * into v_eval;

  perform public.log_audit_event(
    'kpi.stage_advanced', 'workflow', 'info', 'kpi_evaluations', p_evaluation_id,
    'انتقال مرحلة تقييم الأداء', null,
    jsonb_build_object('action', p_action, 'from', v_expected, 'to', v_next, 'note', p_note)
  );
  return v_eval;
end;
$$;
revoke execute on function public.advance_kpi_stage(uuid,text,jsonb,text) from public;
grant execute on function public.advance_kpi_stage(uuid,text,jsonb,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Attendance dashboard (security invoker: RLS determines visible employees).
-- ---------------------------------------------------------------------------
create or replace function public.get_attendance_dashboard(p_date date default null)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select id from public.employees where is_active = true and coalesce(is_deleted, false) = false
  ), daily as (
    select d.* from public.attendance_daily d join params p on p.work_date = d.work_date
  )
  select jsonb_build_object(
    'scheduled', (select count(*) from visible_employees),
    'present', (select count(*) from daily where status in ('present','late','partial')),
    'late', (select count(*) from daily where status = 'late' or late_minutes > 0),
    'absent', (select count(*) from daily where status = 'absent'),
    'incomplete', (select count(*) from daily where status in ('partial','pending')),
    'pendingReview', (select count(*) from public.attendance_events e join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date where e.requires_review = true),
    'lastUpdatedAt', now()
  );
$$;
grant execute on function public.get_attendance_dashboard(date) to authenticated;

-- ---------------------------------------------------------------------------
-- Requests inbox read model.
-- ---------------------------------------------------------------------------
create or replace function public.get_request_inbox(p_limit integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(item order by item->>'createdAt' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', r.id,
      'requestNumber', r.request_number,
      'requestType', r.request_type,
      'employeeId', r.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'title', r.title,
      'reason', r.reason,
      'status', r.status,
      'workflowStatus', r.workflow_status,
      'currentStepOrder', r.current_step_order,
      'activeStepName', active_step.name_ar,
      'decisionDueAt', r.decision_due_at,
      'createdAt', r.created_at
    ) as item
    from public.requests r
    join public.employees e on e.id = r.employee_id
    left join lateral (
      select rs.name_ar from public.request_steps rs
      where rs.request_id = r.id and rs.status in ('active','escalated')
      order by rs.step_order limit 1
    ) active_step on true
    order by r.created_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) q;
$$;
grant execute on function public.get_request_inbox(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- KPI inbox read model.
-- ---------------------------------------------------------------------------
create or replace function public.get_kpi_inbox(p_limit integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(item order by item->>'updatedAt' desc nulls last), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', k.id,
      'employeeId', k.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'cycleId', k.cycle_id,
      'periodMonth', c.period_month,
      'currentStage', k.current_stage,
      'finalScore', k.final_score,
      'finalRating', k.final_rating,
      'locked', k.locked,
      'updatedAt', coalesce(k.updated_at,k.created_at)
    ) as item
    from public.kpi_evaluations k
    join public.employees e on e.id = k.employee_id
    join public.kpi_cycles c on c.id = k.cycle_id
    order by coalesce(k.updated_at,k.created_at) desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) q;
$$;
grant execute on function public.get_kpi_inbox(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Official feed and publishing.
-- ---------------------------------------------------------------------------
create or replace function public.get_official_feed_admin(p_limit integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(item order by sort_at desc), '[]'::jsonb)
  from (
    select item, sort_at
    from (
    select jsonb_build_object(
      'id', a.id, 'kind', 'announcement', 'title', a.title, 'body', a.body,
      'category', a.category, 'priority', a.priority, 'status', a.status,
      'requiresAcknowledgement', a.requires_acknowledgement,
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'acknowledgedCount', (select count(*) from public.announcement_acknowledgements x where x.announcement_id = a.id),
      'targetCount', null,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'createdAt', a.created_at
    ) as item, coalesce(a.published_at, a.created_at) as sort_at from public.announcements a
    union all
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'requiresAcknowledgement', d.requires_read_receipt,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'acknowledgedCount', (select count(*) from public.decision_reads x where x.decision_id = d.id and x.acknowledged = true),
      'targetCount', (select count(*) from public.decision_recipients x where x.decision_id = d.id),
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'createdAt', d.created_at
    ) as item, coalesce(d.published_at, d.created_at) as sort_at from public.administrative_decisions d
    ) unioned
    order by sort_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) feed;
$$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

create or replace function public.publish_official_announcement(
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_requires_acknowledgement boolean default false
)
returns public.announcements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.announcements;
begin
  if not (public.current_is_full_access() or public.has_permission('comms.announcement.manage')) then
    raise exception 'not authorized to publish announcements' using errcode = '42501';
  end if;
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'title or body is too short' using errcode = '22023';
  end if;
  insert into public.announcements(title, body, category, priority, status, target_type,
    requires_acknowledgement, published_at, created_by)
  values (trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement,false), now(), auth.uid()) returning * into v_row;
  perform public.log_audit_event(
    'announcement.published','workflow','info','announcements',v_row.id,
    'نشر إعلان رسمي',null,jsonb_build_object('title',v_row.title,'priority',v_row.priority)
  );
  return v_row;
end;
$$;
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- Universal action center.
-- ---------------------------------------------------------------------------
create or replace function public.get_universal_action_center(p_limit integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  with actions as (
    select
      'request-'||r.id::text as id, 'request'::text as kind,
      coalesce(r.title, 'طلب رقم '||r.request_number::text) as title,
      e.full_name_ar || coalesce(' · '||e.employee_code,'') as subtitle,
      case when r.decision_due_at is not null and r.decision_due_at < now() + interval '4 hours' then 'urgent' else 'high' end as priority,
      r.workflow_status as status, r.decision_due_at as due_at,
      '/hr/requests'::text as action_url, coalesce(r.updated_at,r.created_at) as source_updated_at
    from public.requests r join public.employees e on e.id = r.employee_id
    where r.status = 'pending'
    union all
    select
      'kpi-'||k.id::text, 'kpi', 'تقييم '||e.full_name_ar||' يحتاج مراجعة',
      e.employee_code, case when k.current_stage = 'executive' then 'urgent' else 'high' end,
      k.current_stage, null::timestamptz, '/hr/performance', coalesce(k.updated_at,k.created_at)
    from public.kpi_evaluations k join public.employees e on e.id = k.employee_id
    where k.current_stage <> 'finalized'
    union all
    select
      'decision-'||d.id::text, 'decision', d.title,
      'نسبة الإقرار '||coalesce((select count(*) from public.decision_reads dr where dr.decision_id=d.id and dr.acknowledged)::text,'0')||' من '||
      coalesce((select count(*) from public.decision_recipients rr where rr.decision_id=d.id)::text,'0'),
      'normal', d.status, null::timestamptz, '/admin/official-feed', coalesce(d.updated_at,d.created_at)
    from public.administrative_decisions d
    where d.status='published' and d.requires_read_receipt=true
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'kind',kind,'title',title,'subtitle',subtitle,'priority',priority,'status',status,
    'dueAt',due_at,'actionUrl',action_url,'sourceUpdatedAt',source_updated_at
  ) order by case priority when 'urgent' then 1 when 'high' then 2 else 3 end, due_at nulls last), '[]'::jsonb)
  from (select * from actions limit greatest(1,least(coalesce(p_limit,100),500))) limited;
$$;
grant execute on function public.get_universal_action_center(integer) to authenticated;


create or replace function public.acknowledge_announcement(p_announcement_id uuid)
returns public.announcement_acknowledgements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_me uuid := public.current_employee_id(); v_row public.announcement_acknowledgements;
begin
  if v_me is null then raise exception 'no employee linked to current user' using errcode='42501'; end if;
  if not exists(select 1 from public.announcements a where a.id=p_announcement_id and a.status='published') then
    raise exception 'announcement not available' using errcode='P0002';
  end if;
  insert into public.announcement_acknowledgements(announcement_id,employee_id,created_by)
  values(p_announcement_id,v_me,auth.uid())
  on conflict(announcement_id,employee_id) do update set acknowledged_at=excluded.acknowledged_at,updated_at=now()
  returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.acknowledge_announcement(uuid) from public;
grant execute on function public.acknowledge_announcement(uuid) to authenticated;

create or replace function public.get_employee_home()
returns jsonb
language sql stable security invoker set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'pendingRequests',(select count(*) from public.requests where employee_id=public.current_employee_id() and status='pending'),
    'activeTasks',(select count(*) from public.tasks where assignee_employee_id=public.current_employee_id() and status not in ('done','cancelled')),
    'kpiStage',(select current_stage from public.kpi_evaluations where employee_id=public.current_employee_id() order by created_at desc limit 1),
    'unreadNotifications',(select count(*) from public.notifications where recipient_user_id=auth.uid() and is_read=false),
    'unreadOfficial',(select count(*) from public.decision_recipients dr join public.administrative_decisions d on d.id=dr.decision_id left join public.decision_reads rr on rr.decision_id=d.id and rr.employee_id=dr.employee_id where dr.employee_id=public.current_employee_id() and d.status='published' and coalesce(rr.acknowledged,false)=false),
    'lastUpdatedAt',now()
  );
$$;
grant execute on function public.get_employee_home() to authenticated;

create or replace function public.get_manager_dashboard()
returns jsonb
language sql stable security invoker set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'teamMembers',(select count(*) from public.employees e where e.id<>public.current_employee_id() and public.can_access_employee(e.id,'people.employee.read')),
    'pendingRequests',(select count(*) from public.requests r where r.status='pending' and public.can_access_employee(r.employee_id,'requests.request.approve')),
    'pendingKpi',(select count(*) from public.kpi_evaluations k where k.current_stage='manager' and public.can_access_employee(k.employee_id,'performance.kpi.manager_assess')),
    'lateToday',(select count(*) from public.attendance_daily d where d.work_date=(now() at time zone 'Africa/Cairo')::date and (d.status='late' or d.late_minutes>0) and public.can_access_employee(d.employee_id,'attendance.record.read')),
    'lastUpdatedAt',now()
  );
$$;
grant execute on function public.get_manager_dashboard() to authenticated;

create or replace function public.get_executive_dashboard()
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare v_allowed boolean;
begin
  v_allowed := public.current_is_full_access() or public.has_any_permission(array[
    'performance.kpi.executive_review','comms.decision.manage','reports.executive.read','live_location.request'
  ]);
  if not v_allowed then raise exception 'executive dashboard access denied' using errcode='42501'; end if;
  return jsonb_build_object(
    'urgentActions',(select count(*) from public.requests where status='pending' and decision_due_at<now()+interval '4 hours'),
    'pendingApprovals',(select count(*) from public.requests where status='pending'),
    'pendingFinalKpi',(select count(*) from public.kpi_evaluations where current_stage='executive'),
    'publishedDecisions',(select count(*) from public.administrative_decisions where status='published'),
    'openCases',(select count(*) from public.dispute_cases where status not in ('resolved','closed','dismissed')),
    'activeLocationRequests',(select count(*) from public.live_location_requests where status in ('pending','accepted','active')),
    'lastUpdatedAt',now()
  );
end;
$$;
revoke execute on function public.get_executive_dashboard() from public;
grant execute on function public.get_executive_dashboard() to authenticated;

commit;
