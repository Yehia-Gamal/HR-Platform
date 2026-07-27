-- Migration 0160: V23 — Extended post types, author info in feed, attendance overview, HR reports summary
-- Task 10: Executive Mobile + Posts/Decisions + Reports + Org Chart
--
-- 1. Add post_type column on announcements
-- 2. Update publish_official_announcement to accept p_post_type (7-arg)
-- 3. Update get_official_feed_admin with author info + post_type
-- 4. New RPC get_attendance_today_overview — attendance breakdown for HR/admin dashboards
-- 5. New RPC get_hr_reports_summary — consolidated report data for HR reports page
-- 6. New permission posts.publish for extended post types

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. post_type column on announcements
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.announcements
  add column if not exists post_type text not null default 'announcement'
    check(post_type in ('announcement','alert','poll','meeting','holiday_notice','kpi_notice','attendance_notice'));

comment on column public.announcements.post_type is
  'V23 Task-10: نوع المنشور الموسع — إعلان/تنبيه/تصويت/اجتماع/عطلة/KPI/حضور';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Update publish_official_announcement — 7 params (adds p_post_type)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop the old 6-arg signature to avoid overload ambiguity
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
  -- Validate post_type
  if p_post_type not in ('announcement','alert','poll','meeting','holiday_notice','kpi_notice','attendance_notice') then
    raise exception 'invalid post_type: %', p_post_type using errcode = '22023';
  end if;
  insert into public.announcements(title, body, category, priority, status, target_type,
    requires_acknowledgement, banner_url, post_type, published_at, created_by)
  values (trim(p_title), trim(p_body), p_category, p_priority, 'published', 'all',
    coalesce(p_requires_acknowledgement,false), nullif(trim(coalesce(p_banner_url,'')), ''),
    coalesce(p_post_type,'announcement'), now(), auth.uid()) returning * into v_row;
  perform public.log_audit_event(
    'announcement.published','workflow','info','announcements',v_row.id,
    'نشر إعلان رسمي',null,jsonb_build_object('title',v_row.title,'priority',v_row.priority,
      'postType',v_row.post_type,'hasBanner', v_row.banner_url is not null)
  );
  return v_row;
end;
$$;
revoke execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) from public;
grant execute on function public.publish_official_announcement(text,text,text,text,boolean,text,text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Update get_official_feed_admin — author info + post_type
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
      'postType', coalesce(a.post_type, 'announcement'),
      'requiresAcknowledgement', a.requires_acknowledgement,
      'publishedAt', a.published_at, 'expiresAt', a.expires_at,
      'imageUrl', a.banner_url,
      'authorName', e_a.full_name_ar,
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
      'authorName', coalesce(e_d.full_name_ar, e_d2.full_name_ar),
      'authorPhotoUrl', coalesce(e_d.photo_url, e_d2.photo_url),
      'acknowledgedCount', (select count(*) from public.decision_reads x where x.decision_id = d.id and x.acknowledged = true),
      'targetCount', (select count(*) from public.decision_recipients x where x.decision_id = d.id),
      'myAcknowledged', exists(select 1 from public.decision_reads x where x.decision_id=d.id and x.employee_id=public.current_employee_id() and x.acknowledged=true),
      'createdAt', d.created_at
    ) as item, coalesce(d.published_at, d.created_at) as sort_at
    from public.administrative_decisions d
    left join public.employees e_d on e_d.user_id = d.created_by
    left join public.employees e_d2 on e_d2.id = d.issued_by
    ) unioned
    order by sort_at desc
    limit greatest(1, least(coalesce(p_limit,100),500))
  ) feed;
$$;
grant execute on function public.get_official_feed_admin(integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. get_attendance_today_overview — attendance breakdown for dashboards
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_attendance_today_overview(p_date date default current_date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_total_active int;
  v_expected int;
  v_present int;
  v_late int;
  v_not_checked_in int;
  v_on_leave int;
  v_on_assignment int;
  v_absent int;
begin
  -- صلاحية: HR أو أدمن أو full-access
  if not (public.current_is_full_access()
          or public.has_any_permission(array['attendance.record.read','people.employee.read'])) then
    raise exception 'غير مصرح بعرض نظرة الحضور' using errcode = '42501';
  end if;

  -- إجمالي النشطين (يستثنى المؤرشف والمحذوف)
  select count(*) into v_total_active
  from public.employees e
  where e.is_active and not e.is_deleted;

  -- المتوقع حضورهم (نشط - إجازة - تكليف - عطلة رسمية)
  select count(*) into v_on_leave
  from public.leave_requests lr
  join public.employees e on e.id = lr.employee_id and e.is_active and not e.is_deleted
  where lr.status = 'approved'
    and p_date between lr.start_date and lr.end_date;

  select count(*) into v_on_assignment
  from public.work_assignments wa
  join public.work_assignment_members wam on wam.assignment_id = wa.id
  join public.employees e on e.id = wam.employee_id and e.is_active and not e.is_deleted
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date
    and not exists (
      select 1 from public.leave_requests lr2
      where lr2.employee_id = e.id and lr2.status = 'approved'
        and p_date between lr2.start_date and lr2.end_date
    );

  v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);

  -- حاضرون (check-in موجود)
  select count(distinct ae.employee_id) into v_present
  from public.attendance_events ae
  join public.employees e on e.id = ae.employee_id and e.is_active and not e.is_deleted
  where ae.event_type = 'check_in'
    and ae.recorded_at::date = p_date;

  -- متأخرون (check-in بعد وقت الدوام المحدد في الشفت)
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  join public.employees e on e.id = ae.employee_id and e.is_active and not e.is_deleted
  left join public.roster_assignments ra on ra.employee_id = ae.employee_id
    and p_date between ra.start_date and coalesce(ra.end_date, p_date)
  left join public.shifts s on s.id = ra.shift_id
  where ae.event_type = 'check_in'
    and ae.recorded_at::date = p_date
    and s.start_time is not null
    and ae.recorded_at::time > (s.start_time + interval '10 minutes');

  -- لم يسجلوا حضور
  v_not_checked_in := greatest(0, v_expected - v_present);
  -- غائبون = المتوقع - حاضر - لم يسجل (سلبي = 0)
  v_absent := greatest(0, v_not_checked_in);

  v_result := jsonb_build_object(
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
  return v_result;
end;
$$;
revoke execute on function public.get_attendance_today_overview(date) from public;
grant execute on function public.get_attendance_today_overview(date) to authenticated;

comment on function public.get_attendance_today_overview(date) is
  'V23 Task-10: ملخص حضور اليوم — للوحة HR والإدارة';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. get_hr_reports_summary — consolidated report data
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_hr_reports_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
  v_attendance jsonb;
  v_leaves jsonb;
  v_assignments jsonb;
  v_kpi jsonb;
  v_disputes jsonb;
  v_location jsonb;
begin
  if not (public.current_is_full_access()
          or public.has_any_permission(array['reports.people.read','attendance.record.read'])) then
    raise exception 'غير مصرح بعرض التقارير' using errcode = '42501';
  end if;

  -- تقرير الحضور
  select jsonb_build_object(
    'totalEvents', count(*),
    'checkIns', count(*) filter (where ae.event_type = 'check_in' and ae.recorded_at::date = current_date),
    'checkOuts', count(*) filter (where ae.event_type = 'check_out' and ae.recorded_at::date = current_date),
    'pendingReview', count(*) filter (where ae.status = 'pending_review'),
    'thisMonth', count(*) filter (where ae.recorded_at >= date_trunc('month', current_date))
  ) into v_attendance
  from public.attendance_events ae;

  -- تقرير الإجازات
  select jsonb_build_object(
    'totalRequests', count(*),
    'approved', count(*) filter (where lr.status = 'approved'),
    'pending', count(*) filter (where lr.status = 'pending'),
    'rejected', count(*) filter (where lr.status = 'rejected'),
    'activeNow', count(*) filter (where lr.status = 'approved' and current_date between lr.start_date and lr.end_date)
  ) into v_leaves
  from public.leave_requests lr;

  -- تقرير التكليفات
  select jsonb_build_object(
    'total', count(*),
    'active', count(*) filter (where wa.status in ('APPROVED','IN_PROGRESS')),
    'completed', count(*) filter (where wa.status = 'COMPLETED'),
    'pending', count(*) filter (where wa.status in ('DRAFT','SUBMITTED','PENDING_APPROVAL'))
  ) into v_assignments
  from public.work_assignments wa;

  -- تقرير KPI
  select jsonb_build_object(
    'activeCycles', count(distinct kc.id) filter (where kc.status = 'active'),
    'totalEvaluations', count(ke.id),
    'pendingEvaluations', count(ke.id) filter (where ke.status in ('pending','self_review','manager_review')),
    'completedEvaluations', count(ke.id) filter (where ke.status = 'completed')
  ) into v_kpi
  from public.kpi_cycles kc
  left join public.kpi_evaluations ke on ke.cycle_id = kc.id;

  -- تقرير القضايا
  select jsonb_build_object(
    'total', count(*),
    'open', count(*) filter (where dc.status in ('filed','under_investigation','hearing_scheduled')),
    'resolved', count(*) filter (where dc.status in ('resolved','closed')),
    'escalated', count(*) filter (where dc.is_escalated)
  ) into v_disputes
  from public.dispute_cases dc;

  -- تقرير الموقع
  select jsonb_build_object(
    'totalRequests', count(*),
    'pending', count(*) filter (where lr.status = 'pending'),
    'responded', count(*) filter (where lr.status in ('responded','expired'))
  ) into v_location
  from public.location_requests lr;

  v_result := jsonb_build_object(
    'attendance', coalesce(v_attendance, '{}'::jsonb),
    'leaves', coalesce(v_leaves, '{}'::jsonb),
    'assignments', coalesce(v_assignments, '{}'::jsonb),
    'kpi', coalesce(v_kpi, '{}'::jsonb),
    'disputes', coalesce(v_disputes, '{}'::jsonb),
    'location', coalesce(v_location, '{}'::jsonb),
    'generatedAt', now()
  );
  return v_result;
end;
$$;
revoke execute on function public.get_hr_reports_summary() from public;
grant execute on function public.get_hr_reports_summary() to authenticated;

comment on function public.get_hr_reports_summary() is
  'V23 Task-10: ملخص تقارير HR الشاملة — حضور، إجازات، تكليفات، KPI، قضايا، موقع';

commit;
