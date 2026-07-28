-- Migration 0200: إصلاح ILIKE wildcard injection + تشديد storage policy
-- المشكلة (1): 3 دوال بحث تستخدم ILIKE بدون هروب أحرف % و _ من مدخلات المستخدم
--   → المستخدم يرسل '%' كبحث فيحصل على كل النتائج (تجاوز LIMIT الفعلي)
-- المشكلة (2): سياسة رفع announcements تسمح لأي مستخدم مسجّل بالرفع
-- الحل: دالة مساعدة escape_ilike + تحديث الدوال الثلاث + تشديد السياسة

begin;

-- ═══════════════════════════════════════════════════════════════════════
-- 1. دالة مساعدة لهروب أحرف ILIKE الخاصة
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.escape_ilike(p_input text)
returns text
language sql immutable parallel safe
as $$
  -- يهرب الأحرف الخاصة في ILIKE: % → \%  _ → \_  \ → \\
  select replace(replace(replace(p_input, '\', '\\'), '%', '\%'), '_', '\_');
$$;

comment on function public.escape_ilike(text) is
  'هروب أحرف ILIKE الخاصة (% _ \) لمنع wildcard injection في البحث.';

-- ═══════════════════════════════════════════════════════════════════════
-- 2. إصلاح get_location_directory (آخر نسخة: 0081)
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_location_directory(
  p_search text    default null,
  p_limit  integer default 100
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text;
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('live_location.request')) THEN
    RAISE EXCEPTION 'live location request permission required' USING errcode = '42501';
  END IF;

  v_search := nullif(trim(coalesce(p_search, '')), '');

  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'id',                  q.id,
      'name',                q.full_name_ar,
      'employeeCode',        q.employee_code,
      'jobTitle',            q.job_title,
      'department',          q.department,
      'lastLatitude',        q.latitude,
      'lastLongitude',       q.longitude,
      'lastAccuracy',        q.accuracy,
      'lastRecordedAt',      q.recorded_at,
      'activeRequestId',     q.active_request_id,
      'activeRequestStatus', q.active_request_status
    ) ORDER BY q.full_name_ar)
    FROM (
      SELECT
        e.id, e.full_name_ar, e.employee_code,
        jt.name  job_title,
        d.name   department,
        last_point.latitude, last_point.longitude,
        last_point.accuracy, last_point.recorded_at,
        active_req.id     active_request_id,
        active_req.status active_request_status
      FROM public.employees e
      LEFT JOIN public.job_titles  jt  ON jt.id = e.job_title_id
      LEFT JOIN public.departments d   ON d.id  = e.department_id
      LEFT JOIN LATERAL (
        SELECT l.latitude, l.longitude, l.accuracy, l.recorded_at
        FROM public.employee_locations l
        WHERE l.employee_id = e.id
        ORDER BY l.recorded_at DESC LIMIT 1
      ) last_point ON TRUE
      LEFT JOIN LATERAL (
        SELECT r.id, r.status
        FROM public.live_location_requests r
        WHERE r.employee_id = e.id
          AND r.status IN ('pending','accepted','active')
          AND (r.expires_at IS NULL OR r.expires_at > now())
        ORDER BY r.requested_at DESC LIMIT 1
      ) active_req ON TRUE
      WHERE e.status IN ('active', 'invited', 'onboarding')
        AND e.is_deleted = false
        AND e.id IS DISTINCT FROM public.current_employee_id()
        AND e.user_id IS NOT NULL
        AND (
          public.current_is_full_access()
          OR public.can_access_employee(e.id, 'live_location.request')
        )
        AND (
          v_search IS NULL
          OR e.full_name_ar  ILIKE '%' || public.escape_ilike(v_search) || '%'
          OR e.employee_code ILIKE '%' || public.escape_ilike(v_search) || '%'
        )
      ORDER BY e.full_name_ar
      LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 100), 300))
    ) q
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_location_directory(text, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_location_directory(text, integer) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. إصلاح get_mobile_executive_people (آخر نسخة: 0042)
-- ═══════════════════════════════════════════════════════════════════════
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
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_mobile_executive_people(text,integer) from public;
grant execute on function public.get_mobile_executive_people(text,integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. إصلاح get_dispute_participant_directory (آخر نسخة: 0059)
-- ═══════════════════════════════════════════════════════════════════════
create or replace function public.get_dispute_participant_directory(p_search text default null, p_limit integer default 100)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id,'name',q.full_name_ar,'employeeCode',q.employee_code,'department',q.department
 ) order by q.full_name_ar),'[]'::jsonb)
 from (
  select e.id,e.full_name_ar,e.employee_code,d.name department
  from public.employees e left join public.departments d on d.id=e.department_id
  where e.status='active' and e.is_active and not e.is_deleted
   and e.id is distinct from public.current_employee_id()
   and (coalesce(trim(p_search),'')='' or e.full_name_ar ilike '%'||public.escape_ilike(trim(p_search))||'%' or e.employee_code ilike '%'||public.escape_ilike(trim(p_search))||'%')
  order by e.full_name_ar limit greatest(1,least(coalesce(p_limit,100),200))
 ) q
$$;

revoke execute on function public.get_dispute_participant_directory(text,integer) from public;
grant execute on function public.get_dispute_participant_directory(text,integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 5. تشديد سياسة رفع الملفات لـ announcements bucket
--    السياسة القديمة: أي مستخدم مسجّل يستطيع الرفع
--    الجديدة: فقط من يملك صلاحية نشر الإعلانات أو full-access
-- ═══════════════════════════════════════════════════════════════════════

drop policy if exists "auth_upload_announcements" on storage.objects;

create policy "auth_upload_announcements"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'announcements'
    and (
      public.current_is_full_access()
      or public.has_permission('comms.announcement.manage')
      or public.has_permission('posts.publish')
    )
  );

commit;
