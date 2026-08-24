-- ============================================================================
-- 0463: توحيد «اليوم» على توقيت القاهرة في دوال الحضور التنفيذية والتصحيح
-- ============================================================================
-- نفس فئة علة 0458/0460: current_date للخادم = UTC، وبين 00:00 و03:00
-- بتوقيت القاهرة يختلف عن تاريخ القاهرة فيظهر للتنفيذي «أمس» بوصفه اليوم،
-- ويُرفض تصحيح حضور يوم القاهرة الحالي بوصفه «مستقبلي». الإصلاح: استبدال
-- current_date بـ (now() at time zone 'Africa/Cairo')::date في:
--   1) get_executive_attendance_today
--   2) get_executive_attendance_overview (الافتراضي + شرط المسار السريع)
--   3) get_executive_attendance_overview_fast (كلاهما)
--   4) request_attendance_correction (رفض التواريخ المستقبلية)
-- بقية دوال current_date الـ22 سليمة: مقارنات effective_from أو دلالات
-- تواريخ ذاتية الاتساق لا تتقاطع مع حدود يوم القاهرة.
-- ============================================================================

begin;
CREATE OR REPLACE FUNCTION public.get_executive_attendance_today(p_status text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_status_match text := nullif(trim(coalesce(p_status, '')), '');
begin
  select public.current_has_active_role(array['executive-director', 'executive']) into v_is_executive;

  select public.current_is_full_access()
    or public.has_any_permission(array[
      'attendance.record.read',
      'attendance.history.manage',
      'attendance.roster.manage'
    ])
    or public.has_any_permission(array[
      'people.employee.read'
    ])
  into v_has_attendance_access;

  if not (v_is_executive or v_has_attendance_access) then
    raise exception 'executive or attendance access required' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(item order by item->>'name')
    from (
      select jsonb_build_object(
        'id',               e.id,
        'name',             e.full_name_ar,
        'employeeCode',     e.employee_code,
        'jobTitle',         jt.name,
        'department',       d.name,
        'departmentId',     d.id,
        'photoUrl',         e.photo_url,
        'attendanceStatus', coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end),
        'firstCheckIn',     ad.first_check_in,
        'lastCheckOut',     ad.last_check_out,
        'lateMinutes',      coalesce(ad.late_minutes, 0),
        'isOnMission',      (mission.id is not null),
        'lastLatitude',     last_loc.latitude,
        'lastLongitude',    last_loc.longitude,
        'lastRecordedAt',   last_loc.recorded_at
      ) as item,
      -- عمود خفي للترتيب (لا يظهر في JSON النهائي)
      case
        when mission.id is not null                     then 1
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'present' then 2
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'late'    then 3
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'partial' then 4
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status,
          case when alv.employee_id is not null then 'on_leave'
               when mission.id is not null then 'on_mission'
               when public.is_official_holiday(v_today, e.id) then 'holiday'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'absent'  then 8
        else 9
      end as sort_order
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d   on d.id  = e.department_id
    left join public.attendance_daily ad
           on ad.employee_id = e.id and ad.work_date = v_today
    left join lateral (
      select wa.id
      from public.work_assignment_participants wap
      join public.work_assignments wa on wa.id = wap.assignment_id
      where wap.employee_id = e.id
        and wa.status in ('APPROVED', 'IN_PROGRESS')
        and wa.counts_as_work_day = true
        and wa.start_at::date <= v_today
        and wa.end_at::date   >= v_today
      limit 1
    ) mission on true
    left join lateral (
      select lr.employee_id
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      where lr.employee_id = e.id
        and v_today between lr.start_date and lr.end_date
      limit 1
    ) alv on true
    left join lateral (
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      -- فلتر القسم
      and (p_department_id is null or e.department_id = p_department_id)
      -- فلتر البحث
      and (v_search is null
        or e.full_name_ar ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%')
      -- فلتر الحالة (يطبّق بعد الـ LATERAL JOINs)
      and (v_status_match is null or
        coalesce(ad.status,
          case
            when alv.employee_id is not null then 'on_leave'
            when mission.id is not null      then 'on_mission'
            when public.is_official_holiday(v_today, e.id) then 'holiday'
            when extract(isodow from v_today) = 5 then 'weekend'
            else 'absent'
          end) = v_status_match)
      and (
        v_is_executive
        or public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
    order by sort_order, e.full_name_ar
    ) items
  ), '[]'::jsonb);
end;
$function$;
CREATE OR REPLACE FUNCTION public.get_executive_attendance_overview(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date   date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
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
  if v_date = (now() at time zone 'Africa/Cairo')::date then
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
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and (public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read'))
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
        when extract(isodow from v_date) = 5 then 'weekend'  -- 0447: fallback أخير (0333/0402)
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
$function$;
CREATE OR REPLACE FUNCTION public.get_executive_attendance_overview_fast(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date    date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
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
  if v_date <> (now() at time zone 'Africa/Cairo')::date then
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
$function$;
CREATE OR REPLACE FUNCTION public.request_attendance_correction(p_work_date date, p_type text, p_reason text, p_check_in timestamp with time zone DEFAULT NULL::timestamp with time zone, p_check_out timestamp with time zone DEFAULT NULL::timestamp with time zone, p_status text DEFAULT NULL::text, p_attachment_path text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_emp uuid:=public.current_employee_id(); v_id uuid; v_daily uuid;
begin
 if v_emp is null then raise exception 'NO_EMPLOYEE'; end if;
 if p_work_date>(now() at time zone 'Africa/Cairo')::date or length(trim(p_reason))<5 then raise exception 'INVALID_CORRECTION'; end if;
 select id into v_daily from public.attendance_daily where employee_id=v_emp and work_date=p_work_date;
 insert into public.attendance_corrections(employee_id,attendance_daily_id,work_date,correction_type,requested_check_in,requested_check_out,requested_status,reason,attachment_path,created_by)
 values(v_emp,v_daily,p_work_date,p_type,p_check_in,p_check_out,p_status,trim(p_reason),p_attachment_path,auth.uid()) returning id into v_id;
 perform public.notify_employees_with_permission(
   'attendance.correction.review',
   'طلب تصحيح حضور جديد',
   format('طلب تصحيح حضور بتاريخ %s (%s)', p_work_date, coalesce(p_type, '')),
   'attendance', 'normal', 'attendance_corrections', v_id,
   '{}'::jsonb, v_emp);
 return v_id;
end $function$;
commit;

notify pgrst, 'reload schema';
