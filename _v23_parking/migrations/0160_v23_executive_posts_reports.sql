-- Migration 0160: V23 Task-10 — Extended post types, author info, attendance overview, HR reports
-- 1. Add post_type column on announcements
-- 2. Replace publish_official_announcement (7 args, includes p_post_type)
-- 3. Replace get_official_feed_admin (adds authorName, authorPhotoUrl, postType)
-- 4. New RPC get_attendance_today_overview
-- 5. New RPC get_hr_reports_summary

begin;

-- ─────────────────────────────────────────────────────────
-- 1. post_type column
-- ─────────────────────────────────────────────────────────
alter table public.announcements
  add column if not exists post_type text not null default 'announcement'
  check (post_type in ('announcement','alert','poll','meeting','holiday_notice','kpi_notice','attendance_notice'));

-- ─────────────────────────────────────────────────────────
-- 2. publish_official_announcement — 7 args
-- ─────────────────────────────────────────────────────────
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
    coalesce(p_post_type, 'announcement'),
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

-- ─────────────────────────────────────────────────────────
-- 3. get_official_feed_admin — with authorName, authorPhotoUrl, postType
-- ─────────────────────────────────────────────────────────
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
      'postType', coalesce(a.post_type, 'announcement'),
      'requiresAcknowledgement', a.requires_acknowledgement,
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'authorName', e_a.full_name,
      'authorPhotoUrl', e_a.photo_url,
      'acknowledgedCount', (select count(*) from public.announcement_acknowledgements x where x.announcement_id = a.id),
      'targetCount', null,
      'myAcknowledged', exists(select 1 from public.announcement_acknowledgements x where x.announcement_id=a.id and x.employee_id=public.current_employee_id()),
      'createdAt', a.created_at
    ) as item, coalesce(a.published_at, a.created_at) as sort_at
    from public.announcements a
    left join public.employees e_a on e_a.user_id = a.created_by
    union all
    select jsonb_build_object(
      'id', d.id, 'kind', 'decision', 'title', d.title, 'body', coalesce(d.body,''),
      'category', d.category, 'priority', coalesce(d.metadata->>'priority','high'), 'status', d.status,
      'postType', 'decision',
      'requiresAcknowledgement', d.requires_read_receipt,
      'publishedAt', d.published_at, 'expiresAt', d.expiry_date,
      'imageUrl', d.attachment_url,
      'authorName', coalesce(e_d2.full_name, e_d1.full_name),
      'authorPhotoUrl', coalesce(e_d2.photo_url, e_d1.photo_url),
      'acknowledgedCount', (select count(*) from public.decision_reads x where x.decision_id = d.id and x.acknowledged = true),
      'targetCount', (select count(*) from public.decision_recipients x where x.decision_id = d.id),
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'createdAt', d.created_at
    ) as item, coalesce(d.published_at, d.created_at) as sort_at
    from public.administrative_decisions d
    left join public.employees e_d1 on e_d1.user_id = d.created_by
    left join public.employees e_d2 on e_d2.id = d.issued_by
    ) unioned
    order by sort_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) feed;
$$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 4. get_attendance_today_overview
-- ─────────────────────────────────────────────────────────
create or replace function public.get_attendance_today_overview(p_date date default current_date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_on_leave int;
  v_on_assignment int;
  v_not_checked_in int;
  v_absent int;
begin
  if not (public.current_is_full_access()
          or public.has_permission('attendance.record.read')
          or public.has_permission('people.employee.read')) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- إجمالي الموظفين النشطين غير التنفيذيين
  select count(*) into v_total_active
  from public.employees
  where status = 'active' and is_executive is not true;

  -- في إجازة معتمدة اليوم
  select count(distinct employee_id) into v_on_leave
  from public.leave_requests
  where status = 'approved' and p_date between start_date and end_date;

  -- في تكليف خارجي اليوم
  select count(distinct employee_id) into v_on_assignment
  from public.work_assignments
  where status = 'active' and p_date between start_date and end_date;

  -- المتوقع حضورهم = نشطون - إجازات - تكليفات
  v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);

  -- الحاضرون (سجّلوا دخول اليوم)
  select count(distinct employee_id) into v_present
  from public.attendance_events
  where event_date = p_date and event_type = 'check_in';

  -- المتأخرون (سجّلوا دخول بعد الموعد)
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_date = p_date and ae.event_type = 'check_in'
    and ae.is_late is true;

  -- لم يسجّلوا بعد
  v_not_checked_in := greatest(0, v_expected - v_present);

  -- غائبون (لم يسجّلوا ولا إجازة ولا تكليف) — نفس لم يسجّل إلا في نهاية اليوم
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', v_total_active,
    'expected', v_expected,
    'present', v_present,
    'late', v_late,
    'notCheckedIn', v_not_checked_in,
    'onLeave', v_on_leave,
    'onAssignment', v_on_assignment,
    'absent', v_absent,
    'lastUpdatedAt', now()
  );
end;
$$;
grant execute on function public.get_attendance_today_overview(date) to authenticated;

-- ─────────────────────────────────────────────────────────
-- 5. get_hr_reports_summary
-- ─────────────────────────────────────────────────────────
create or replace function public.get_hr_reports_summary()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_att jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
begin
  if not (public.current_is_full_access()
          or public.has_permission('reports.people.read')
          or public.has_permission('attendance.record.read')) then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  -- الحضور
  select jsonb_build_object(
    'totalEvents', count(*),
    'checkIns', count(*) filter (where event_type = 'check_in' and event_date = current_date),
    'checkOuts', count(*) filter (where event_type = 'check_out' and event_date = current_date),
    'pendingReview', count(*) filter (where needs_review = true),
    'thisMonth', count(*) filter (where event_date >= date_trunc('month', current_date))
  ) into v_att from public.attendance_events;

  -- الإجازات
  select jsonb_build_object(
    'totalRequests', count(*),
    'approved', count(*) filter (where status = 'approved'),
    'pending', count(*) filter (where status = 'pending'),
    'rejected', count(*) filter (where status = 'rejected'),
    'activeNow', count(*) filter (where status = 'approved' and current_date between start_date and end_date)
  ) into v_leaves from public.leave_requests;

  -- التكليفات
  select jsonb_build_object(
    'total', count(*),
    'active', count(*) filter (where status = 'active'),
    'completed', count(*) filter (where status = 'completed'),
    'pending', count(*) filter (where status = 'pending')
  ) into v_assignments from public.work_assignments;

  -- الأداء
  select jsonb_build_object(
    'activeCycles', (select count(*) from public.kpi_cycles where status = 'active'),
    'totalEvaluations', count(*),
    'pendingEvaluations', count(*) filter (where status in ('pending','in_progress','draft')),
    'completedEvaluations', count(*) filter (where status in ('completed','approved'))
  ) into v_kpi from public.kpi_evaluations;

  -- النزاعات
  select jsonb_build_object(
    'total', count(*),
    'open', count(*) filter (where status in ('open','submitted','under_review')),
    'resolved', count(*) filter (where status in ('resolved','closed')),
    'escalated', count(*) filter (where status = 'escalated')
  ) into v_disputes from public.disputes;

  -- الموقع
  select jsonb_build_object(
    'totalRequests', count(*),
    'pending', count(*) filter (where status = 'pending'),
    'responded', count(*) filter (where status in ('responded','completed'))
  ) into v_location from public.location_requests;

  return jsonb_build_object(
    'attendance', v_att,
    'leaves', v_leaves,
    'assignments', v_assignments,
    'kpi', v_kpi,
    'disputes', v_disputes,
    'location', v_location,
    'generatedAt', now()
  );
end;
$$;
grant execute on function public.get_hr_reports_summary() to authenticated;

commit;
