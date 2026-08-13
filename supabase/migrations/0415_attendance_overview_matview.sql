-- =====================================================================
-- 0415: materialized view لحظي للوحة الحضور التنفيذية اليومية
-- =====================================================================
-- يبني على 0067 (دالة get_executive_attendance_overview) و0391 (لقطة سنابشوت
-- كل 3 دقائق). هنا ننشئ لقطة أكثر حداثةً (كل 60 ثانية) باسم مستقل لتجنّب
-- تعارض الأسماء، مع دالة قراءة سريعة get_executive_attendance_overview_fast
-- تقرأ مباشرة من الـ MV دون إعادة الحساب.
--
--   1) materialized view: mv_executive_attendance_overview (حالي اليوم).
--   2) فهارس: فهرس فريد على employee_id (شرط REFRESH CONCURRENTLY) + فهارس بحث.
--   3) دالة refresh_executive_attendance_overview() — REFRESH CONCURRENTLY.
--   4) جدولة pg_cron كل 60 ثانية: '* * * * *'.
--   5) دالة get_executive_attendance_overview_fast(p_date) تقرأ من الـ MV.
--   6) GRANT SELECT على الـ MV لـ authenticated.
--
-- كل الدوال SECURITY DEFINER مع search_path=public,pg_temp ونمط revoke/grant.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- (أ) materialized view: التصفية مسبقاً لليوم الحالي
--     نستخدم نفس منطق تصنيف `classified` CTE من 0067 (دون فرع weekend
--     لأن الـ MV تُحدَّث كل دقيقة وتقرأ فقط لحظة الطلب).
-- ---------------------------------------------------------------------
create materialized view if not exists public.mv_executive_attendance_overview as
with v_today as (
  select current_date as d
),
base as (
  select
    e.id as employee_id,
    e.full_name_ar,
    e.employee_code,
    e.department_id,
    e.photo_url,
    jt.name as job_title,
    dp.name as department,
    (select mgr.full_name_ar from public.manager_relations mr
       join public.employees mgr on mgr.id = mr.manager_employee_id
      where mr.employee_id = e.id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
      order by mr.effective_from desc limit 1) as manager_name,
    ad.status as att_status,
    ad.first_check_in,
    ad.last_check_out,
    ad.late_minutes,
    ad.early_leave_minutes,
    ad.updated_at as att_updated_at,
    exists(
      select 1 from public.leave_requests lr
        join public.requests rq on rq.id = lr.request_id
      where lr.employee_id = e.id
        and rq.status = 'approved'
        and (select d from v_today) between lr.start_date and lr.end_date
    ) as on_leave,
    (select wa.assignment_type from public.work_assignment_participants wp
       join public.work_assignments wa on wa.id = wp.assignment_id
      where wp.employee_id = e.id
        and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
        and (select d from v_today) between wa.start_at::date and wa.end_at::date
      order by wa.start_at desc limit 1) as assignment_type,
    lp.latitude  as last_latitude,
    lp.longitude as last_longitude,
    lp.accuracy  as last_accuracy,
    lp.recorded_at as last_location_at,
    lp.address_ar  as last_address_ar,
    lp.source      as loc_source,
    ar.id     as active_request_id,
    ar.status as active_request_status
  from public.employees e
  left join public.job_titles jt on jt.id = e.job_title_id
  left join public.departments dp on dp.id = e.department_id
  left join public.attendance_daily ad
    on ad.employee_id = e.id and ad.work_date = (select d from v_today)
  left join lateral (
    select l.latitude, l.longitude, l.accuracy, l.recorded_at, l.address_ar, l.source
    from public.employee_locations l
    where l.employee_id = e.id
    order by l.recorded_at desc limit 1
  ) lp on true
  left join lateral (
    select r.id, r.status
    from public.live_location_requests r
    where r.employee_id = e.id
      and r.status in ('pending','accepted','active')
      and (r.expires_at is null or r.expires_at > now())
    order by r.requested_at desc limit 1
  ) ar on true
  where e.status = 'active' and e.is_deleted = false
),
classified as (
  select *,
    case
      when on_leave then 'on_leave'
      when assignment_type is not null then 'assignment'
      when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
      when att_status = 'present' then 'present'
      when att_status = 'late' then 'late'
      when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
      when last_check_out is not null then 'checked_out'
      when att_status = 'absent' then 'absent'
      else 'not_yet'
    end as derived_status
  from base
)
select
  employee_id,
  full_name_ar,
  employee_code,
  department,
  job_title,
  manager_name,
  derived_status,
  att_status,
  first_check_in,
  last_check_out,
  late_minutes,
  early_leave_minutes,
  on_leave,
  assignment_type,
  last_latitude,
  last_longitude,
  last_accuracy,
  last_location_at,
  last_address_ar,
  active_request_id,
  active_request_status,
  greatest(coalesce(att_updated_at, last_location_at), coalesce(last_location_at, att_updated_at)) as status_updated_at
from classified;

-- فهرس: فريد على employee_id (شرط لازم لـ REFRESH ... CONCURRENTLY)
create unique index if not exists ux_mv_exec_att_overview_emp
  on public.mv_executive_attendance_overview (employee_id);

create index if not exists ix_mv_exec_att_overview_status
  on public.mv_executive_attendance_overview (derived_status);

create index if not exists ix_mv_exec_att_overview_dept
  on public.mv_executive_attendance_overview (department);

-- ---------------------------------------------------------------------
-- (ب) دالة التحديث — يُستخدمها pg_cron
--     REFRESH CONCURRENTLY لا يحجب القراءات. عند الفشل (مثلاً عدم وجود
--     الفهرس الفريد بعد ترقية قديمة) نسقط لتحديث بسيط.
-- ---------------------------------------------------------------------
create or replace function public.refresh_executive_attendance_overview()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  refresh materialized view concurrently public.mv_executive_attendance_overview;
exception
  when others then
    refresh materialized view public.mv_executive_attendance_overview;
end;
$$;

revoke execute on function public.refresh_executive_attendance_overview() from public;
grant execute on function public.refresh_executive_attendance_overview() to service_role;

-- تعبئة أولية لضمان توفر بيانات مباشرة بعد التركيب
do $$
begin
  perform public.refresh_executive_attendance_overview();
exception when others then
  null;
end $$;

-- ---------------------------------------------------------------------
-- (ج) pg_cron: تحديث كل 60 ثانية طوال اليوم
--     اسم الوظيفة مستقل عن وظيفة 0391 (refresh-executive-attendance-snapshot).
-- ---------------------------------------------------------------------
do $$
begin
  -- إلغاء أي جدولة سابقة بنفس الاسم لتجنّب التكرار عند إعادة التركيب
  perform cron.unschedule('refresh-executive-attendance-overview');
exception when others then
  null;
end$$;

select cron.schedule(
  'refresh-executive-attendance-overview',
  '* * * * *',
  $$select public.refresh_executive_attendance_overview();$$
);

-- ---------------------------------------------------------------------
-- (د) get_executive_attendance_overview_fast: قراءة سريعة من الـ MV
--     تعيد نفس شكل خرج get_executive_attendance_overview (jsonb) لكن بمصدر
--     'cache'. تتجاهل p_date حال كونه اليوم الحالي؛ وللتواريخ الأخرى تسقط
--     للاستعلام الحي عبر تفويض الدالة الأصلية.
-- ---------------------------------------------------------------------
create or replace function public.get_executive_attendance_overview_fast(p_date date default null)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_date    date := coalesce(p_date, current_date);
  v_rows    jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode = '42501';
  end if;

  -- الـ MV تخص اليوم الحالي فقط؛ للتواريخ الأخرى فوّض على الدالة الحية الأصلية.
  if v_date <> current_date then
    return public.get_executive_attendance_overview(v_date);
  end if;

  select
    jsonb_agg(jsonb_build_object(
      'id', employee_id, 'name', full_name_ar, 'employeeCode', employee_code,
      'jobTitle', job_title, 'department', department, 'managerName', manager_name,
      'status', derived_status, 'attStatus', att_status,
      'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave, 'assignmentType', assignment_type,
      'lastLatitude', last_latitude, 'lastLongitude', last_longitude,
      'lastAccuracy', last_accuracy,
      'lastLocationAt', last_location_at, 'lastAddressAr', last_address_ar,
      'statusUpdatedAt', status_updated_at,
      'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',                count(*),
      'present',              count(*) filter (where derived_status = 'present'),
      'late',                 count(*) filter (where derived_status = 'late'),
      'notYet',               count(*) filter (where derived_status = 'not_yet'),
      'absent',               count(*) filter (where derived_status = 'absent'),
      'checkedOut',           count(*) filter (where derived_status = 'checked_out'),
      'leftEarly',            count(*) filter (where derived_status = 'left_early'),
      'onLeave',              count(*) filter (where derived_status = 'on_leave'),
      'onAssignment',         count(*) filter (where derived_status = 'assignment'),
      'onMission',            count(*) filter (where assignment_type = 'MISSION'),
      'onConvoy',             count(*) filter (where assignment_type = 'CONVOY'),
      'onFundraising',        count(*) filter (where assignment_type = 'FUNDRAISING'),
      'activeLocationRequests', count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from public.mv_executive_attendance_overview;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
    'employees', coalesce(v_rows, '[]'::jsonb),
    'generatedAt', now(),
    'source', 'cache'
  );
end;
$$;

revoke execute on function public.get_executive_attendance_overview_fast(date) from public;
grant execute on function public.get_executive_attendance_overview_fast(date) to authenticated;

-- ---------------------------------------------------------------------
-- (هـ) صلاحيات القراءة على الـ MV
-- ---------------------------------------------------------------------
grant select on public.mv_executive_attendance_overview to authenticated;

commit;
