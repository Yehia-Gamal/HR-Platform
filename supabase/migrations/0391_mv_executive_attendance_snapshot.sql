-- mig 0391: materialized view for executive attendance overview
-- تخزين نتيجة get_executive_attendance_overview لليوم الحالي مؤقتاً.
-- يُحدَّث كل 3 دقائق خلال ساعات العمل (6:00-22:00 بتوقيت القاهرة).
-- RPC تقرأ من الـ MV عند p_date = current_date، وتعود للاستعلام الحي للتواريخ الأخرى.

-- ════════════════════════════════════════════════════════
-- 1) الـ materialized view
-- ════════════════════════════════════════════════════════

create materialized view if not exists public.mv_executive_attendance_snapshot as
with v_today as (select current_date as d),
base as (
  select
    e.id, e.full_name_ar, e.employee_code, e.department_id, e.photo_url,
    jt.name as job_title, dp.name as department,
    (select mgr.full_name_ar from public.manager_relations mr
       join public.employees mgr on mgr.id = mr.manager_employee_id
      where mr.employee_id = e.id
        and mr.effective_from <= now()
        and (mr.effective_to is null or mr.effective_to > now())
      order by mr.effective_from desc limit 1) as manager_name,
    ad.status as att_status, ad.first_check_in, ad.last_check_out,
    ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
    exists(
      select 1 from public.leave_requests lr join public.requests rq on rq.id = lr.request_id
      where lr.employee_id = e.id and rq.status = 'approved'
        and (select d from v_today) between lr.start_date and lr.end_date
    ) as on_leave,
    (select wa.assignment_type from public.work_assignment_participants wp
       join public.work_assignments wa on wa.id = wp.assignment_id
      where wp.employee_id = e.id
        and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
        and (select d from v_today) between wa.start_at::date and wa.end_at::date
      order by wa.start_at desc limit 1) as assignment_type,
    lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
    ar.id as active_request_id, ar.status as active_request_status
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
      when extract(isodow from (select d from v_today)) = 5 then 'weekend'
      when on_leave then 'on_leave'
      when assignment_type is not null then 'assignment'
      when att_status = 'present' and coalesce(late_minutes, 0) > 0 then 'late'
      when att_status = 'present' then 'present'
      when att_status = 'late' then 'late'
      when last_check_out is not null and coalesce(early_leave_minutes, 0) > 0 then 'left_early'
      when last_check_out is not null then 'checked_out'
      when att_status = 'absent' then 'absent'
      else 'not_yet'
    end as derived_status,
    (select d from v_today) as snapshot_date
  from base
)
select * from classified;

-- فهارس للبحث السريع
create unique index if not exists mv_exec_att_snapshot_id
  on public.mv_executive_attendance_snapshot (id);

create index if not exists mv_exec_att_snapshot_status
  on public.mv_executive_attendance_snapshot (derived_status);

-- ════════════════════════════════════════════════════════
-- 2) دالة التحديث — يُستخدمها pg_cron
-- ════════════════════════════════════════════════════════

create or replace function public.refresh_executive_attendance_snapshot()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  refresh materialized view concurrently public.mv_executive_attendance_snapshot;
exception
  when others then
    -- تحديث بسيط (بدون CONCURRENTLY) كبديل عند الفشل
    refresh materialized view public.mv_executive_attendance_snapshot;
end;
$$;

revoke execute on function public.refresh_executive_attendance_snapshot() from public;
grant execute on function public.refresh_executive_attendance_snapshot() to service_role;

-- ════════════════════════════════════════════════════════
-- 3) pg_cron: تحديث كل 3 دقائق خلال ساعات العمل (6-22 بتوقيت UTC+3)
--    6:00 Cairo = 3:00 UTC / 22:00 Cairo = 19:00 UTC
-- ════════════════════════════════════════════════════════

select cron.schedule(
  'refresh-executive-attendance-snapshot',
  '*/3 3-19 * * *',
  $$select public.refresh_executive_attendance_snapshot();$$
);

-- ════════════════════════════════════════════════════════
-- 4) تحديث get_executive_attendance_overview لقراءة من الـ MV عند طلب اليوم الحالي
-- ════════════════════════════════════════════════════════

create or replace function public.get_executive_attendance_overview(p_date date default null)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_date   date := coalesce(p_date, current_date);
  v_rows   jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode = '42501';
  end if;

  -- ─── قراءة من الـ materialized view عند طلب اليوم الحالي ───
  if v_date = current_date then
    select
      jsonb_agg(jsonb_build_object(
        'id', id, 'name', full_name_ar, 'employeeCode', employee_code, 'avatarUrl', photo_url,
        'jobTitle', job_title, 'department', department, 'managerName', manager_name,
        'status', derived_status, 'attStatus', att_status,
        'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
        'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
        'onLeave', on_leave, 'assignmentType', assignment_type,
        'lastLatitude', latitude, 'lastLongitude', longitude, 'lastAccuracy', accuracy,
        'lastLocationAt', recorded_at, 'lastAddressAr', address_ar, 'locationSource', loc_source,
        'statusUpdatedAt', greatest(coalesce(att_updated_at, recorded_at), coalesce(recorded_at, att_updated_at)),
        'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
      ) order by full_name_ar),
      jsonb_build_object(
        'total',          count(*),
        'present',        count(*) filter (where derived_status = 'present'),
        'late',           count(*) filter (where derived_status = 'late'),
        'notYet',         count(*) filter (where derived_status = 'not_yet'),
        'absent',         count(*) filter (where derived_status = 'absent'),
        'checkedOut',     count(*) filter (where derived_status = 'checked_out'),
        'leftEarly',      count(*) filter (where derived_status = 'left_early'),
        'onLeave',        count(*) filter (where derived_status = 'on_leave'),
        'onAssignment',   count(*) filter (where derived_status = 'assignment'),
        'onMission',      count(*) filter (where assignment_type = 'MISSION'),
        'onConvoy',       count(*) filter (where assignment_type = 'CONVOY'),
        'onFundraising',  count(*) filter (where assignment_type = 'FUNDRAISING'),
        'weekend',        count(*) filter (where derived_status = 'weekend'),
        'activeLocationRequests', count(*) filter (where active_request_id is not null)
      )
    into v_rows, v_summary
    from public.mv_executive_attendance_snapshot;

    return jsonb_build_object(
      'date', v_date,
      'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
      'employees', coalesce(v_rows, '[]'::jsonb),
      'generatedAt', now(),
      'source', 'cache'
    );
  end if;

  -- ─── استعلام حي للتواريخ الأخرى ───
  with base as (
    select
      e.id, e.full_name_ar, e.employee_code, e.department_id, e.photo_url,
      jt.name as job_title, d.name as department,
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id = mr.manager_employee_id
        where mr.employee_id = e.id and mr.effective_from <= now()
          and (mr.effective_to is null or mr.effective_to > now())
        order by mr.effective_from desc limit 1) as manager_name,
      ad.status as att_status, ad.first_check_in, ad.last_check_out,
      ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
      exists(
        select 1 from public.leave_requests lr join public.requests rq on rq.id = lr.request_id
        where lr.employee_id = e.id and rq.status = 'approved' and v_date between lr.start_date and lr.end_date
      ) as on_leave,
      (select wa.assignment_type from public.work_assignment_participants wp
         join public.work_assignments wa on wa.id = wp.assignment_id
        where wp.employee_id = e.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between wa.start_at::date and wa.end_at::date
        order by wa.start_at desc limit 1) as assignment_type,
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
      ar.id as active_request_id, ar.status as active_request_status
    from public.employees e
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_date
    left join lateral (
      select l.latitude, l.longitude, l.accuracy, l.recorded_at, l.address_ar, l.source
      from public.employee_locations l where l.employee_id = e.id order by l.recorded_at desc limit 1
    ) lp on true
    left join lateral (
      select r.id, r.status from public.live_location_requests r
      where r.employee_id = e.id and r.status in ('pending','accepted','active')
        and (r.expires_at is null or r.expires_at > now())
      order by r.requested_at desc limit 1
    ) ar on true
    where e.status = 'active' and e.is_deleted = false
      and (public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read'))
  ),
  classified as (
    select *,
      case
        when extract(isodow from v_date) = 5 then 'weekend'
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
    jsonb_agg(jsonb_build_object(
      'id', id, 'name', full_name_ar, 'employeeCode', employee_code, 'avatarUrl', photo_url,
      'jobTitle', job_title, 'department', department, 'managerName', manager_name,
      'status', derived_status, 'attStatus', att_status,
      'firstCheckIn', first_check_in, 'lastCheckOut', last_check_out,
      'lateMinutes', late_minutes, 'earlyLeaveMinutes', early_leave_minutes,
      'onLeave', on_leave, 'assignmentType', assignment_type,
      'lastLatitude', latitude, 'lastLongitude', longitude, 'lastAccuracy', accuracy,
      'lastLocationAt', recorded_at, 'lastAddressAr', address_ar, 'locationSource', loc_source,
      'statusUpdatedAt', greatest(coalesce(att_updated_at, recorded_at), coalesce(recorded_at, att_updated_at)),
      'activeRequestId', active_request_id, 'activeRequestStatus', active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',         count(*),
      'present',       count(*) filter (where derived_status = 'present'),
      'late',          count(*) filter (where derived_status = 'late'),
      'notYet',        count(*) filter (where derived_status = 'not_yet'),
      'absent',        count(*) filter (where derived_status = 'absent'),
      'checkedOut',    count(*) filter (where derived_status = 'checked_out'),
      'leftEarly',     count(*) filter (where derived_status = 'left_early'),
      'onLeave',       count(*) filter (where derived_status = 'on_leave'),
      'onAssignment',  count(*) filter (where derived_status = 'assignment'),
      'onMission',     count(*) filter (where assignment_type = 'MISSION'),
      'onConvoy',      count(*) filter (where assignment_type = 'CONVOY'),
      'onFundraising', count(*) filter (where assignment_type = 'FUNDRAISING'),
      'weekend',       count(*) filter (where derived_status = 'weekend'),
      'activeLocationRequests', count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from classified;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total', 0)),
    'employees', coalesce(v_rows, '[]'::jsonb),
    'generatedAt', now(),
    'source', 'live'
  );
end;
$$;

revoke execute on function public.get_executive_attendance_overview(date) from public;
grant execute on function public.get_executive_attendance_overview(date) to authenticated;
