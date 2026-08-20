-- ============================================================================
-- 0444: استبعاد المدير التنفيذي من إشعارات الحضور الخاصة به وقوائم الموظفين
-- ============================================================================
-- المشكلة: المدير التنفيذي ليس موظفاً عادياً — لا يصح أن يتلقى إشعارات عن
--   حضور/انصراف نفسه (هو يتلقى عن الموظفين فقط)، ولا يجب أن يظهر في قوائم
--   الموظفين (الحضور، دليل الموقع، دليل الأشخاص).
--
-- الحل:
--   1) دالة مساعدة is_employee_executive لتحديد ما إذا كان الموظف هو المدير التنفيذي
--   2) tg_attendance_daily_notify_manager: لا يُرسل إشعار المدير التنفيذي
--      عندما يكون الموظف هو المدير التنفيذي نفسه
--   3) get_executive_attendance_today: استبعاد المدير التنفيذي من النتائج
--   4) get_location_directory: استبعاد المدير التنفيذي من دليل الموقع
--   5) get_mobile_executive_people: استبعاد المدير التنفيذي من دليل الأشخاص
--   6) get_executive_attendance_overview: استبعاد المدير التنفيذي من لوحة الحضور
--      (الـ materialized view + الاستعلام الحي)
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1) دالة مساعدة: هل هذا الموظف هو المدير التنفيذي؟
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.is_employee_executive(p_employee_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.roles r
    join public.user_roles ur on ur.role_id = r.id
      and (ur.effective_from is null or ur.effective_from <= now())
      and (ur.effective_to   is null or ur.effective_to   >  now())
    join public.profiles p on p.id = ur.user_id
    join public.employees e on e.id = p.employee_id
      and e.is_active = true and e.status = 'active'
    where r.slug = 'executive-director'
      and e.id = p_employee_id
  );
$$;

comment on function public.is_employee_executive(uuid) is
  '0444: هل يحمل الموظف دور المدير التنفيذي (executive-director)؟ تُستخدم لاستبعاده من إشعاراته الذاتية وقوائم الموظفين.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2) إصلاح tg_attendance_daily_notify_manager: لا يُشعر المدير التنفيذي
--    بحضور/انصراف نفسه (هو يتلقى عن كل الموظفين إلا نفسه)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.tg_attendance_daily_notify_manager()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_manager uuid;
  v_event text;
  v_time text;
  v_emp_ar text;
begin
  -- عند إدراج جديد أو تحديث لأوقات الدخول/الخروج
  if tg_op = 'INSERT' then
    if new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  else
    -- UPDATE: فقط عند تغيّر قيمة الدخول/الخروج
    if new.first_check_in is distinct from old.first_check_in and new.first_check_in is not null then
      v_event := 'attendance_check_in';
    elsif new.last_check_out is distinct from old.last_check_out and new.last_check_out is not null then
      v_event := 'attendance_check_out';
    else
      return new;
    end if;
  end if;

  select full_name_ar into v_emp_ar from public.employees where id = new.employee_id;

  v_time := to_char(
    case when v_event = 'attendance_check_in' then new.first_check_in else new.last_check_out end
      at time zone 'Africa/Cairo',
    'HH24:MI'
  );

  -- إشعار الموظف نفسه (تأكيد تسجيل الحضور/الانصراف)
  perform public.notify_employee(
    new.employee_id,
    case when v_event = 'attendance_check_in' then 'تم تسجيل حضورك'
         else 'تم تسجيل انصرافك' end,
    format(
      'تم تسجيل %s الساعة %s',
      case when v_event = 'attendance_check_in' then 'حضورك' else 'انصرافك' end,
      v_time
    ),
    'attendance', 'normal', 'attendance_daily', new.id,
    jsonb_build_object(
      'event', v_event,
      'self', true,
      'workDate', new.work_date,
      'time', v_time
    )
  );

  -- إشعار المدير المباشر (يبقى كما هو — أولوية منخفضة)
  select mr.manager_employee_id into v_manager
  from public.manager_relations mr
  where mr.employee_id = new.employee_id
    and mr.relation_type = 'primary'
    and mr.effective_from <= current_date
    and (mr.effective_to is null or mr.effective_to >= current_date)
  order by mr.created_at desc
  limit 1;

  if v_manager is not null then
    perform public.notify_employee(
      v_manager,
      case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
           else 'انصراف موظف — تسجيل خروج' end,
      format(
        '%s — %s (%s)',
        coalesce(v_emp_ar, 'موظف'),
        case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
        v_time
      ),
      'attendance', 'low', 'attendance_daily', new.id,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'managerId', v_manager,
        'time', v_time
      )
    );
  end if;

  -- 0444: إشعار المدير التنفيذي (كامل الشاشة) عند كل دخول/انصراف — لكن
  -- لا يُشعر المدير التنفيذي عن حضور/انصراف نفسه (هو ليس موظفاً عادياً)
  if not public.is_employee_executive(new.employee_id) then
    perform public.notify_executive_fullscreen(
      case when v_event = 'attendance_check_in' then 'دخول موظف — تسجيل حضور'
           else 'انصراف موظف — تسجيل خروج' end,
      format(
        '%s — %s (%s)',
        coalesce(v_emp_ar, 'موظف'),
        case when v_event = 'attendance_check_in' then 'دخل الساعة ' else 'انصرف الساعة ' end,
        v_time
      ),
      'attendance',
      'attendance_daily', new.id,
      null,
      jsonb_build_object(
        'event', v_event,
        'employeeId', new.employee_id,
        'workDate', new.work_date,
        'time', v_time
      ),
      false  -- لا nudge على كثافة أحداث الحضور؛ يعتمد على جدولة الـ dispatcher
    );
  end if;

  return new;
end;
$$;

comment on function public.tg_attendance_daily_notify_manager() is
  '0444: يُشعر الموظف نفسه (تأكيد) والمدير المباشر (low) والمدير التنفيذي (كامل الشاشة) بدخول/انصراف أي موظف — إلا المدير التنفيذي نفسه فلا يُشعر عن حضور/انصراف نفسه.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3) get_executive_attendance_today: استبعاد المدير التنفيذي من قائمة
--    "الحاضرون الآن" في هاتف المدير التنفيذي
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.get_executive_attendance_today()
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $function$
declare
  v_today date := current_date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
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
    select jsonb_agg(jsonb_build_object(
      'id',               e.id,
      'name',             e.full_name_ar,
      'employeeCode',     e.employee_code,
      'jobTitle',         jt.name,
      'department',       d.name,
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
    ) order by
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
      end,
      e.full_name_ar
    )
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
      and (
        v_is_executive
        or public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
  ), '[]'::jsonb);
end;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4) get_location_directory: استبعاد المدير التنفيذي من دليل الموقع
-- ═══════════════════════════════════════════════════════════════════════════
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
        AND NOT public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 5) get_mobile_executive_people: استبعاد المدير التنفيذي من دليل الأشخاص
-- ═══════════════════════════════════════════════════════════════════════════
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
        and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
        and public.can_access_employee(e.id,'people.employee.read')
        and (v_search is null or e.full_name_ar ilike '%' || public.escape_ilike(v_search) || '%' or e.employee_code ilike '%' || public.escape_ilike(v_search) || '%')
      order by e.full_name_ar
      limit greatest(1, least(coalesce(p_limit, 60), 100))
    ) x
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6) get_executive_attendance_overview: استبعاد المدير التنفيذي من لوحة الحضور
--    (إعادة بناء الـ materialized view + تحديث دالة RPC)
-- ═══════════════════════════════════════════════════════════════════════════

-- 6a) حذف الـ MV القديم وإعادة بنائه مع استبعاد المدير التنفيذي
drop materialized view if exists public.mv_executive_attendance_snapshot;

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
    and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
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

-- 6b) تحديث دالة التحديث للـ MV
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
    refresh materialized view public.mv_executive_attendance_snapshot;
end;
$$;

-- 6c) تحديث RPC get_executive_attendance_overview (الاستعلام الحي للتواريخ الأخرى)
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
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
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

-- ═══════════════════════════════════════════════════════════════════════════
-- 7) get_mobile_employee_directory: استبعاد المدير التنفيذي من دليل الموظفين
--    (يستخدمه جميع الموظفين في التطبيق)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.get_mobile_employee_directory(
  p_search text default null,
  p_limit  integer default 40
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text := nullif(trim(coalesce(p_search, '')), '');
  v_today date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',           e.id,
      'name',         e.full_name_ar,
      'employeeCode', e.employee_code,
      'photoUrl',     e.photo_url,
      'jobTitle',     jt.name,
      'department',   d.name,
      'statusToday',  case
        when ad.status in ('present','late','partial') then 'present'
        when ad.status = 'on_leave' then 'on_leave'
        when ad.status is not null and ad.status <> 'absent' then ad.status
        when exists (
          select 1 from public.missions m join public.requests r on r.id = m.request_id
          where m.employee_id = e.id and r.status = 'approved'
            and v_today between (m.start_at at time zone 'Africa/Cairo')::date and (m.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.convoy_requests c join public.requests r on r.id = c.request_id
          where c.employee_id = e.id and r.status = 'approved'
            and v_today between (c.departure_at at time zone 'Africa/Cairo')::date and (coalesce(c.return_at,c.departure_at) at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.work_assignment_participants wp join public.work_assignments wa on wa.id = wp.assignment_id
          where wp.employee_id = e.id and wa.status = 'APPROVED' and coalesce(wa.counts_as_work_day,true)
            and v_today between (wa.start_at at time zone 'Africa/Cairo')::date and (wa.end_at at time zone 'Africa/Cairo')::date
        ) then 'on_leave'
        when exists (
          select 1 from public.leave_requests lr join public.requests r on r.id = lr.request_id
          where lr.employee_id = e.id and r.status = 'approved'
            and v_today between lr.start_date and lr.end_date
        ) then 'on_leave'
        else 'absent'
      end
    ) order by e.full_name_ar)
    from public.employees e
    left join public.job_titles  jt on jt.id = e.job_title_id
    left join public.departments d  on d.id  = e.department_id
    left join public.attendance_daily ad on ad.employee_id = e.id and ad.work_date = v_today
    where e.is_active  = true
      and e.is_deleted = false
      and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and (
        v_search is null
        or e.full_name_ar  ilike '%' || v_search || '%'
        or e.employee_code ilike '%' || v_search || '%'
        or jt.name         ilike '%' || v_search || '%'
        or d.name          ilike '%' || v_search || '%'
      )
    limit greatest(1, least(coalesce(p_limit, 40), 100))
  ), '[]'::jsonb);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 8) get_attendance_dashboard: استبعاد المدير التنفيذي من لوحة تحكم الحضور
--    (تستخدم في واجهة الويب للإدارة)
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.get_attendance_dashboard(
  p_date          date default null,
  p_department_id uuid default null,
  p_branch_id     uuid default null,
  p_manager_id    uuid default null
)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (
         p_manager_id is null or exists (
           select 1
             from public.manager_relations mr
            where mr.employee_id = e.id
              and mr.manager_employee_id = p_manager_id
              and mr.effective_from <= now()
              and (mr.effective_to is null or mr.effective_to > now())
         )
       )
  ), daily as (
    select d.*
      from public.attendance_daily d
      join params p on p.work_date = d.work_date
      join visible_employees ve on ve.id = d.employee_id
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), approved_leaves as (
    select lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
      join params p on p.work_date between lr.start_date and lr.end_date
      join visible_employees ve on ve.id = lr.employee_id
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
      join params prm on prm.work_date between wa.start_at::date and wa.end_at::date
     where wa.status in ('APPROVED','IN_PROGRESS')
  ), derived as (
    select
      ve.id as employee_id,
      d.id as daily_id,
      d.status as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      d.is_finalized,
      (al.employee_id is not null) as has_approved_leave,
      (am.employee_id is not null) as has_mission,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when am.employee_id is not null then 'on_mission'
        when public.is_official_holiday((select work_date from params), ve.id) then 'holiday'
        when extract(isodow from (select work_date from params)) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
  ), excused_absent as (
    select dv.employee_id
      from derived dv
      join visible_events e on e.employee_id = dv.employee_id
     where dv.derived_status = 'absent'
     group by dv.employee_id
    having count(e.id) > 0
  ), location_requests_day as (
    select llr.employee_id, llr.status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
      join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
         or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
      join visible_employees ve on ve.id = llr.employee_id
  )
  select jsonb_build_object(
    'scheduled',
      case when extract(isodow from (select work_date from params)) = 5
           then (select count(distinct employee_id) from daily)
           else (select count(*) from visible_employees)
      end,
    'present', (select count(*) from derived where derived_status in ('present','late','partial')),
    'late', (select count(*) from derived where derived_status = 'late' or late_minutes > 0),
    'absent', (select count(*) from derived where derived_status = 'absent'),
    'unexcusedAbsent', (select count(*) from derived where derived_status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'onLeave', (select count(*) from derived where derived_status = 'on_leave'),
    'onMission', (select count(*) from derived where derived_status = 'on_mission'),
    'missingCheckout', (select count(*) from derived where derived_status = 'missing_checkout'),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRequestsResponded', (select count(*) from location_requests_day where responded),
    'date', (select work_date from params)
  );
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9) تحديث الـ materialized view فوراً (حتى لا تظل خالية حتى cron القادم)
-- ═══════════════════════════════════════════════════════════════════════════
select public.refresh_executive_attendance_snapshot();

commit;

-- ═══════════════════════════════════════════════════════════════════════════
-- 10) request_live_location: منع طلب موقع المدير التنفيذي
--     المدير التنفيذي لا يجب أن يكون هدفاً لطلبات المواقع — هو فقط من يطلبها
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.request_live_location(
  p_employee_id uuid,
  p_mode text default 'snapshot',
  p_reason text default ''
)
returns public.live_location_requests
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_req public.live_location_requests;
  v_duration integer;
  v_target_user uuid;
  v_deep_link text;
begin
  if v_me is null then raise exception 'requester has no employee profile' using errcode='42501'; end if;
  if not (public.current_is_full_access() or public.current_has_active_role(array['executive', 'executive-director'])) then
    raise exception 'only executive director may request employee location' using errcode='42501';
  end if;
  if p_employee_id = v_me then raise exception 'cannot request own location' using errcode='22023'; end if;

  -- 0444: المدير التنفيذي لا يُطلب موقعه — هو فقط من يطلب مواقع الآخرين
  if public.is_employee_executive(p_employee_id) then
    raise exception 'cannot request location of executive director' using errcode='22023';
  end if;

  if coalesce(p_mode, '') <> 'snapshot' then
    raise exception 'LOCATION_MODE_DISABLED: V17 allows snapshot location requests only'
      using errcode='22023';
  end if;

  if not exists (
    select 1 from public.employees where id = p_employee_id
      and status = 'active' and is_active and not is_deleted and user_id is not null
  ) then
    raise exception 'employee is not active or has no linked user account' using errcode='P0002';
  end if;

  if exists (
    select 1 from public.live_location_requests
    where requested_by = v_me and employee_id = p_employee_id
      and requested_at > now() - interval '30 seconds'
  ) then
    raise exception 'cooldown_active: please wait 30 seconds between requests' using errcode='22023';
  end if;

  v_duration := 1;

  insert into public.live_location_requests(
    employee_id, requested_by, reason, status, purpose,
    requested_at, expires_at, duration_minutes, metadata, created_by)
  values(
    p_employee_id, v_me, coalesce(nullif(trim(p_reason),''), null),
    'pending', 'verification',
    now(), now() + interval '5 minutes', v_duration,
    jsonb_build_object(
      'mode', 'snapshot', 'videoSeconds', 0,
      'needsPoint', true, 'needsVideo', false,
      'isTracking', false, 'videoRemoved', true, 'policyVersion', 'V17'),
    auth.uid())
  returning * into v_req;

  update public.live_location_requests
    set metadata = metadata || jsonb_build_object('requestId', v_req.id)
    where id = v_req.id returning * into v_req;

  v_deep_link := 'https://ahla-shabab-management-os.vercel.app/action/live_location_request/' || v_req.id::text;

  select user_id into v_target_user from public.employees where id = p_employee_id;
  if v_target_user is not null then
    insert into public.notifications(
      recipient_user_id, recipient_employee_id, title, body, category, priority,
      action_url, entity_type, entity_id, metadata, created_by)
    values(
      v_target_user, p_employee_id, 'طلب تحديد موقع فوري',
      'السكرتير التنفيذي أو المدير التنفيذي يطلب موقعك الآن. يرجى الاستجابة.',
      'system', 'urgent',
      v_deep_link,
      'live_location_request', v_req.id, jsonb_build_object(
        'fullScreen', true, 'kind', 'live_location_request', 'requestId', v_req.id,
        'entityId', v_req.id, 'channel', 'urgent_location_v6',
        'deepLink', v_deep_link),
      auth.uid());
  end if;

  perform public.log_audit_event(
    'live_location.requested', 'security', 'info',
    'live_location_requests', v_req.id, 'تم طلب الموقع اللحظي', null,
    jsonb_build_object('mode', 'snapshot', 'employeeId', p_employee_id, 'requestId', v_req.id));
  return v_req;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11) get_employees_enriched: استبعاد المدير التنفيذي من قائمة الموظفين
--     (تستخدم في لوحة ويب الإدارة)
-- ═══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_employees_enriched(
  p_search text default null,
  p_status text default null,
  p_limit integer default 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_is_org_admin boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  v_is_org_admin := public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read');

  RETURN coalesce((
    SELECT jsonb_agg(row_data ORDER BY row_data->>'fullNameAr')
    FROM (
      SELECT jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', d.name,
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at
      ) AS row_data
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      LEFT JOIN public.teams t ON t.id = e.team_id
      LEFT JOIN public.branches b ON b.id = e.branch_id
      LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
      WHERE e.is_deleted = false
        AND NOT public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
        AND (p_status IS NULL OR e.status = p_status)
        AND (v_search IS NULL
          OR lower(e.full_name_ar) LIKE '%' || v_search || '%'
          OR lower(coalesce(e.full_name_en, '')) LIKE '%' || v_search || '%'
          OR lower(e.employee_code) LIKE '%' || v_search || '%'
          OR e.phone_e164 LIKE '%' || v_search || '%')
        AND (
          v_is_org_admin
          OR public.can_access_employee(e.id, 'people.employee.read')
        )
      ORDER BY e.created_at DESC
      LIMIT greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12) get_executive_attendance_today: إضافة فلاتر (حالة/قسم/بحث)
--     ليتمكن المدير التنفيذي من تصفية قائمة "الحاضرون الآن"
-- ═══════════════════════════════════════════════════════════════════════════
drop function if exists public.get_executive_attendance_today();
create or replace function public.get_executive_attendance_today(
  p_status        text    default null,  -- present, late, absent, on_leave, on_mission, weekend, holiday
  p_department_id uuid    default null,
  p_search        text    default null
)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $function$
declare
  v_today date := current_date;
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
revoke all on function public.get_executive_attendance_today(text, uuid, text) from public, anon;
grant  execute on function public.get_executive_attendance_today(text, uuid, text) to authenticated;

-- ============================================================================
-- ملخص التعديلات:
--   1)  is_employee_executive(employee_id) — دالة مساعدة للتحقق من دور executive-director
--   2)  tg_attendance_daily_notify_manager — لا يُشعر التنفيذي عن حضور نفسه
--   3)  get_executive_attendance_today — استبعاد التنفيذي + فلاتر (حالة/قسم/بحث)
--   4)  get_location_directory — استبعاد التنفيذي من دليل الموقع
--   5)  get_mobile_executive_people — استبعاد التنفيذي من دليل الأشخاص
--   6)  get_executive_attendance_overview — استبعاد التنفيذي من لوحة الحضور (MV + حي)
--   7)  get_mobile_employee_directory — استبعاد التنفيذي من دليل الموظفين
--   8)  get_attendance_dashboard — استبعاد التنفيذي من لوحة تحكم الحضور (الويب)
--   9)  request_live_location — منع طلب موقع المدير التنفيذي (هو فقط من يطلب)
--   10) get_employees_enriched — استبعاد التنفيذي من قائمة موظفين الويب
-- ============================================================================