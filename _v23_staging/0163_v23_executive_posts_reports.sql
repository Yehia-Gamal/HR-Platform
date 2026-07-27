-- 0163_v23_executive_posts_reports.sql
-- V23 §10: Enhanced posts system (extended post types + author info) & attendance overview RPC
-- Depends on: 0008 (announcements), 0142 (images/feed RPC), 0111 (executive daily report)

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Extended post types on announcements
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.announcements
  add column if not exists post_type text not null default 'announcement'
    check(post_type in (
      'announcement','alert','poll','meeting',
      'holiday_notice','kpi_notice','attendance_notice'
    ));

comment on column public.announcements.post_type is
  'V23 §10: نوع المنشور — إعلان/تنبيه/تصويت/اجتماع/عطلة/إشعار KPI/إشعار حضور';

create index if not exists ix_announcements_post_type
  on public.announcements(post_type);

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Update publish_official_announcement to accept post_type
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop old signature first to avoid ambiguity
drop function if exists public.publish_official_announcement(text,text,text,text,boolean,text);

create or replace function public.publish_official_announcement(
  p_title text,
  p_body text,
  p_category text default 'general',
  p_priority text default 'normal',
  p_requires_acknowledgement boolean default false,
  p_banner_url text default null,
  p_post_type text default 'announcement'
)
returns public.announcements
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.announcements;
begin
  if not (public.current_is_full_access() or public.has_permission('comms.announcement.manage')
          or public.has_permission('posts.publish')) then
    raise exception 'not authorized to publish announcements' using errcode = '42501';
  end if;
  if length(trim(p_title)) < 3 or length(trim(p_body)) < 10 then
    raise exception 'title or body is too short' using errcode = '22023';
  end if;
  insert into public.announcements(title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, post_type, published_at, created_by)
  values (trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement,false), nullif(trim(coalesce(p_banner_url,'')), ''),
    coalesce(p_post_type,'announcement'),
    now(), auth.uid()) returning * into v_row;
  perform public.log_audit_event(
    'announcement.published','workflow','info','announcements',v_row.id,
    'نشر إعلان رسمي',null,jsonb_build_object('title',v_row.title,'priority',v_row.priority,'postType',v_row.post_type,'hasBanner', v_row.banner_url is not null)
  );
  return v_row;
end;
$$;
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Update get_official_feed_admin — add post_type + author name/photo
-- ═══════════════════════════════════════════════════════════════════════════════

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
      'postType', a.post_type,
      'requiresAcknowledgement', a.requires_acknowledgement,
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'authorName', coalesce(emp_a.full_name_ar, ''),
      'authorPhotoUrl', emp_a.photo_url,
      'acknowledgedCount', (select count(*) from public.announcement_acknowledgements x where x.announcement_id = a.id),
      'targetCount', null,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'createdAt', a.created_at
    ) as item, coalesce(a.published_at, a.created_at) as sort_at
    from public.announcements a
    left join public.employees emp_a on emp_a.user_id = a.created_by
    union all
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'postType', 'decision',
      'requiresAcknowledgement', d.requires_read_receipt,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'authorName', coalesce(emp_d.full_name_ar, coalesce(iss.full_name_ar, '')),
      'authorPhotoUrl', coalesce(emp_d.photo_url, iss.photo_url),
      'acknowledgedCount', (select count(*) from public.decision_reads x where x.decision_id = d.id and x.acknowledged = true),
      'targetCount', (select count(*) from public.decision_recipients x where x.decision_id = d.id),
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'createdAt', d.created_at
    ) as item, coalesce(d.published_at, d.created_at) as sort_at
    from public.administrative_decisions d
    left join public.employees emp_d on emp_d.user_id = d.created_by
    left join public.employees iss on iss.id = d.issued_by
    ) unioned
    order by sort_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) feed;
$$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Attendance today overview — accessible to HR & admin (not executive-only)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_attendance_today_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_date date := (now() at time zone 'Africa/Cairo')::date;
  v_result jsonb;
begin
  -- يتطلب صلاحية قراءة الحضور أو وصول كامل
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array['attendance.record.read','reports.attendance.read','reports.executive.read'])
    or public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive','executive-director'])
  ) then
    raise exception 'ATTENDANCE_OVERVIEW_FORBIDDEN' using errcode='42501';
  end if;

  with active_people as (
    select e.id, e.user_id
    from public.employees e
    where e.is_active and not coalesce(e.is_deleted,false) and e.status='active'
      -- استثناء التنفيذيين
      and not exists(
        select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
        where ur.user_id=e.user_id and r.slug in ('executive','executive-director')
          and (ur.effective_from is null or ur.effective_from<=now())
          and (ur.effective_to is null or ur.effective_to>now())
      )
  ), facts as (
    select p.id,
      d.status as att_status, d.first_check_in, d.last_check_out, d.late_minutes,
      not exists(select 1 from public.roster_days rd where rd.employee_id=p.id and rd.work_date=v_date and rd.day_status in ('rest','holiday','cancelled')) as scheduled,
      exists(select 1 from public.leave_requests lr join public.requests rq on rq.id=lr.request_id where lr.employee_id=p.id and rq.status='approved' and v_date between lr.start_date and lr.end_date) as on_leave,
      exists(select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id=wp.assignment_id where wp.employee_id=p.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED') and v_date between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date) as on_assignment
    from active_people p
    left join public.attendance_daily d on d.employee_id=p.id and d.work_date=v_date
  )
  select jsonb_build_object(
    'date', v_date,
    'totalActive', count(*),
    'expected', count(*) filter(where scheduled and not on_leave and not on_assignment),
    'present', count(*) filter(where first_check_in is not null or att_status in ('present','late','partial')),
    'late', count(*) filter(where att_status='late' or coalesce(late_minutes,0)>0),
    'notCheckedIn', count(*) filter(where scheduled and not on_leave and not on_assignment and first_check_in is null and coalesce(att_status,'') not in ('absent')),
    'onLeave', count(*) filter(where on_leave),
    'onAssignment', count(*) filter(where on_assignment),
    'absent', count(*) filter(where att_status='absent'),
    'lastUpdatedAt', now()
  ) into v_result from facts;

  return v_result;
end;
$$;

revoke execute on function public.get_attendance_today_overview() from public, anon;
grant execute on function public.get_attendance_today_overview() to authenticated;

comment on function public.get_attendance_today_overview() is
  'V23 §10: ملخص حضور اليوم — الموظفون المتوقعون مع حالاتهم (حاضر/متأخر/لم يسجل/إجازة/تكليف/غياب)، التنفيذيون مستثنون.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. HR reports summary — aggregate metrics for the reports page
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_hr_reports_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_result jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'reports.people.read','reports.attendance.read','reports.executive.read',
      'attendance.record.read','performance.kpi.read'
    ])
    or public.current_is_executive_secretary()
  ) then
    raise exception 'REPORTS_SUMMARY_FORBIDDEN' using errcode='42501';
  end if;

  select jsonb_build_object(
    'attendance', jsonb_build_object(
      'presentToday', (select count(*) from public.attendance_daily where work_date=v_today and status in ('present','late','partial')),
      'absentToday', (select count(*) from public.attendance_daily where work_date=v_today and status='absent'),
      'lateToday', (select count(*) from public.attendance_daily where work_date=v_today and (status='late' or late_minutes>0)),
      'pendingReview', (select count(*) from public.attendance_daily where work_date=v_today and status='pending_review')
    ),
    'leaves', jsonb_build_object(
      'activeNow', (select count(*) from public.leave_requests lr join public.requests rq on rq.id=lr.request_id where rq.status='approved' and v_today between lr.start_date and lr.end_date),
      'pendingApproval', (select count(*) from public.leave_requests lr join public.requests rq on rq.id=lr.request_id where rq.status='pending'),
      'thisMonth', (select count(*) from public.leave_requests lr join public.requests rq on rq.id=lr.request_id where rq.status='approved' and lr.start_date >= v_month_start and lr.start_date <= v_today)
    ),
    'assignments', jsonb_build_object(
      'activeNow', (select count(*) from public.work_assignments where status in ('APPROVED','IN_PROGRESS') and v_today between (start_at at time zone 'Africa/Cairo')::date and (end_at at time zone 'Africa/Cairo')::date),
      'pendingReport', (select count(*) from public.work_assignments where status='REPORT_PENDING'),
      'thisMonth', (select count(*) from public.work_assignments where status not in ('DRAFT','CANCELLED') and (start_at at time zone 'Africa/Cairo')::date >= v_month_start)
    ),
    'kpi', jsonb_build_object(
      'currentCycle', (select count(*) from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=date_trunc('month',v_today)::date),
      'pendingSelf', (select count(*) from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=date_trunc('month',v_today)::date and e.current_stage='self'),
      'pendingManager', (select count(*) from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=date_trunc('month',v_today)::date and e.current_stage in ('manager_review','manager_final')),
      'pendingHr', (select count(*) from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=date_trunc('month',v_today)::date and e.current_stage='hr_review'),
      'overdue', (select count(*) from public.kpi_evaluations e join public.kpi_cycles c on c.id=e.cycle_id where c.period_month=date_trunc('month',v_today)::date and e.workflow_status='OVERDUE')
    ),
    'disputes', jsonb_build_object(
      'open', (select count(*) from public.dispute_cases where status not in ('closed','rejected','cancelled_by_employee')),
      'newThisMonth', (select count(*) from public.dispute_cases where created_at >= v_month_start),
      'closedThisMonth', (select count(*) from public.dispute_cases where status='closed' and updated_at >= v_month_start)
    ),
    'location', jsonb_build_object(
      'activeRequests', (select count(*) from public.live_location_requests where status in ('pending','accepted','active') and (expires_at is null or expires_at>now())),
      'unanswered', (select count(*) from public.live_location_requests where status='pending' and (expires_at is null or expires_at>now()))
    ),
    'generatedAt', now()
  ) into v_result;

  return v_result;
end;
$$;

revoke execute on function public.get_hr_reports_summary() from public, anon;
grant execute on function public.get_hr_reports_summary() to authenticated;

comment on function public.get_hr_reports_summary() is
  'V23 §10: ملخص التقارير الشامل — حضور، إجازات، تكليفات، KPI، قضايا، موقع.';

commit;
