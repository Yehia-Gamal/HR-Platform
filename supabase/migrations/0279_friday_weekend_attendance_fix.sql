-- =====================================================================
-- 0279: إصلاح غياب يوم الجمعة — دوال الحضور اليومي يجب أن تحترم يوم الراحة
-- =====================================================================
-- المشكلة: يوم الجمعة (isodow=5) هو يوم الراحة الأسبوعية الوحيد (0186)، لكن
-- دوال الحضور اليومي لا تتحقق منه:
--   * get_executive_attendance_overview: تصنف الموظفين كـ 'not_yet' أو 'absent'
--     بدلاً من 'weekend' يوم الجمعة، فيظهر الجميع كغائبين على لوحة التحكم.
--   * get_attendance_today_overview: تحسب expected = total - leave - assignment
--     بدون استثناء يوم الجمعة، فيظهر عدد غائبين على البطاقة الرئيسية.
--   * get_attendance_dashboard: تعتمد على attendance_daily وتحسب absent حتى يوم
--     الجمعة إذا وُجدت سجلات قديمة.
--   * get_executive_attendance_today (موبايل): coalesce(ad.status, 'absent') تجعل
--     كل من ليس له سجلات يظهر كغائب يوم الجمعة.
--
-- الحل: إضافة فحص isodow=5 في كل دالة:
--   * إذا كان اليوم جمعة → تصنيف الموظف كـ 'weekend'، expected=0، absent=0.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) get_executive_attendance_overview: إضافة 'weekend' كحالة يوم الجمعة
-- ---------------------------------------------------------------------

create or replace function public.get_executive_attendance_overview(p_date date default null)
returns jsonb
language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare
  v_date date := coalesce(p_date, current_date);
  v_rows jsonb;
  v_summary jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode='42501';
  end if;

  with base as (
    select
      e.id, e.full_name_ar, e.employee_code, e.department_id, e.photo_url,
      jt.name as job_title, d.name as department,
      -- المدير المباشر
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id=mr.manager_employee_id
        where mr.employee_id=e.id and mr.effective_from<=now() and (mr.effective_to is null or mr.effective_to>now())
        order by mr.effective_from desc limit 1) as manager_name,
      ad.status as att_status, ad.first_check_in, ad.last_check_out,
      ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
      -- إجازة معتمدة تشمل اليوم
      exists(
        select 1 from public.leave_requests lr join public.requests rq on rq.id=lr.request_id
        where lr.employee_id=e.id and rq.status='approved' and v_date between lr.start_date and lr.end_date
      ) as on_leave,
      -- تكليف عمل معتمد/جارٍ يشمل اليوم (مأمورية/قافلة/فاندي)
      (select wa.assignment_type from public.work_assignment_participants wp
         join public.work_assignments wa on wa.id=wp.assignment_id
        where wp.employee_id=e.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between wa.start_at::date and wa.end_at::date
        order by wa.start_at desc limit 1) as assignment_type,
      -- آخر موقع مسجّل
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
      -- طلب موقع نشط
      ar.id as active_request_id, ar.status as active_request_status
    from public.employees e
    left join public.job_titles jt on jt.id=e.job_title_id
    left join public.departments d on d.id=e.department_id
    left join public.attendance_daily ad on ad.employee_id=e.id and ad.work_date=v_date
    left join lateral (
      select l.latitude,l.longitude,l.accuracy,l.recorded_at,l.address_ar,l.source
      from public.employee_locations l where l.employee_id=e.id order by l.recorded_at desc limit 1
    ) lp on true
    left join lateral (
      select r.id,r.status from public.live_location_requests r
      where r.employee_id=e.id and r.status in ('pending','accepted','active')
        and (r.expires_at is null or r.expires_at>now())
      order by r.requested_at desc limit 1
    ) ar on true
    where e.status='active'
      and public.can_access_employee(e.id,'live_location.request')
  ),
  classified as (
    select *,
      case
        -- يوم الجمعة = راحة أسبوعية لكل الموظفين
        when extract(isodow from v_date) = 5 then 'weekend'
        when on_leave then 'on_leave'
        when assignment_type is not null then 'assignment'
        when att_status='present' and coalesce(late_minutes,0)>0 then 'late'
        when att_status='present' then 'present'
        when att_status='late' then 'late'
        when last_check_out is not null and coalesce(early_leave_minutes,0)>0 then 'left_early'
        when last_check_out is not null then 'checked_out'
        when att_status='absent' then 'absent'
        else 'not_yet'
      end as derived_status
    from base
  )
  select
    jsonb_agg(jsonb_build_object(
      'id',id,'name',full_name_ar,'employeeCode',employee_code,'avatarUrl',photo_url,
      'jobTitle',job_title,'department',department,'managerName',manager_name,
      'status',derived_status,'attStatus',att_status,
      'firstCheckIn',first_check_in,'lastCheckOut',last_check_out,
      'lateMinutes',late_minutes,'earlyLeaveMinutes',early_leave_minutes,
      'onLeave',on_leave,'assignmentType',assignment_type,
      'lastLatitude',latitude,'lastLongitude',longitude,'lastAccuracy',accuracy,
      'lastLocationAt',recorded_at,'lastAddressAr',address_ar,'locationSource',loc_source,
      'statusUpdatedAt',greatest(coalesce(att_updated_at,recorded_at),coalesce(recorded_at,att_updated_at)),
      'activeRequestId',active_request_id,'activeRequestStatus',active_request_status
    ) order by full_name_ar),
    jsonb_build_object(
      'total',count(*),
      'present',count(*) filter (where derived_status='present'),
      'late',count(*) filter (where derived_status='late'),
      'notYet',count(*) filter (where derived_status='not_yet'),
      'absent',count(*) filter (where derived_status='absent'),
      'checkedOut',count(*) filter (where derived_status='checked_out'),
      'leftEarly',count(*) filter (where derived_status='left_early'),
      'onLeave',count(*) filter (where derived_status='on_leave'),
      'onAssignment',count(*) filter (where derived_status='assignment'),
      'onMission',count(*) filter (where assignment_type='MISSION'),
      'onConvoy',count(*) filter (where assignment_type='CONVOY'),
      'onFundraising',count(*) filter (where assignment_type='FUNDRAISING'),
      'weekend',count(*) filter (where derived_status='weekend'),
      'activeLocationRequests',count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from classified;

  return jsonb_build_object(
    'date', v_date,
    'summary', coalesce(v_summary, jsonb_build_object('total',0)),
    'employees', coalesce(v_rows,'[]'::jsonb),
    'generatedAt', now()
  );
end;
$$;

revoke execute on function public.get_executive_attendance_overview(date) from public;
grant execute on function public.get_executive_attendance_overview(date) to authenticated;

-- ---------------------------------------------------------------------
-- 2) get_attendance_today_overview: يوم الجمعة → expected=0, absent=0
-- ---------------------------------------------------------------------

create or replace function public.get_attendance_today_overview(p_date date default current_date)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $fn$
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

  -- يوم الجمعة (isodow=5) = راحة أسبوعية: لا غياب ولا متوقع
  if extract(isodow from p_date) = 5 then
    return jsonb_build_object(
      'date', p_date,
      'totalActive', 0,
      'expected', 0,
      'present', 0,
      'late', 0,
      'notCheckedIn', 0,
      'onLeave', 0,
      'onAssignment', 0,
      'absent', 0,
      'isWeekend', true,
      'lastUpdatedAt', now()
    );
  end if;

  -- إجمالي الموظفين النشطين (بدون التنفيذيين)
  select count(*) into v_total_active
  from public.employees e
  where e.status = 'active'
    and not exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = e.user_id
        and r.slug in ('executive','executive-director')
        and ur.effective_from <= now()
        and (ur.effective_to is null or ur.effective_to > now())
    );

  -- الموظفون في إجازة معتمدة
  select count(distinct lr.employee_id) into v_on_leave
  from public.leave_requests lr
  join public.requests req on req.id = lr.request_id
  where req.status = 'approved'
    and p_date between lr.start_date and lr.end_date;

  -- الموظفون في تكليفات نشطة
  select count(distinct wa.responsible_employee_id) into v_on_assignment
  from public.work_assignments wa
  where wa.status in ('APPROVED','IN_PROGRESS')
    and p_date between wa.start_at::date and wa.end_at::date;

  v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);

  -- الحاضرون (سجّلوا حضور اليوم)
  select count(distinct employee_id) into v_present
  from public.attendance_events
  where event_at::date = p_date and event_type = 'CHECK_IN';

  -- المتأخرون
  select count(distinct ae.employee_id) into v_late
  from public.attendance_events ae
  where ae.event_at::date = p_date
    and ae.event_type = 'CHECK_IN'
    and ae.late_minutes > 0;

  v_not_checked_in := greatest(0, v_expected - v_present);
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
    'isWeekend', false,
    'lastUpdatedAt', now()
  );
end;
$fn$;

grant execute on function public.get_attendance_today_overview(date) to authenticated;

-- ---------------------------------------------------------------------
-- 3) get_attendance_dashboard: يوم الجمعة → كل العدّادات صفر ما عدا scheduled
-- ---------------------------------------------------------------------

create or replace function public.get_attendance_dashboard(p_date date default null)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  )
  select case
    -- يوم الجمعة = راحة أسبوعية
    when extract(isodow from (select work_date from params)) = 5 then
      jsonb_build_object(
        'scheduled', 0,
        'present', 0,
        'late', 0,
        'absent', 0,
        'unexcusedAbsent', 0,
        'locationRequestsToday', 0,
        'locationRespondedToday', 0,
        'incomplete', 0,
        'pendingReview', 0,
        'isWeekend', true,
        'lastUpdatedAt', now()
      )
    else
      (with visible_employees as (
        select id from public.employees where is_active = true and coalesce(is_deleted, false) = false
      ), daily as (
        select d.* from public.attendance_daily d join params p on p.work_date = d.work_date
      ), visible_events as (
        select e.* from public.attendance_events e
          join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      ), approved_leaves as (
        select lr.employee_id, lt.is_paid, lt.code as leave_code
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
          join public.leave_types lt on lt.id = lr.leave_type_id
          join params p on p.work_date between lr.start_date and lr.end_date
      ), excused_absent as (
        select d.employee_id
          from daily d
          left join approved_leaves al on al.employee_id = d.employee_id
          left join visible_events e on e.employee_id = d.employee_id
         where d.status = 'absent'
         group by d.employee_id
        having count(al.employee_id) filter (
                 where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
               ) > 0
          or count(e.id) > 0
      ), location_requests_day as (
        select employee_id, status, requested_at, responded_at,
               (responded_at is not null or status in ('accepted','active','completed')) as responded
          from public.live_location_requests llr
          join params p on (llr.requested_at at time zone 'Africa/Cairo')::date = p.work_date
             or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = p.work_date)
      )
      select jsonb_build_object(
        'scheduled', (select count(*) from visible_employees),
        'present', (select count(*) from daily where status in ('present','late','partial')),
        'late', (select count(*) from daily where status = 'late' or late_minutes > 0),
        'absent', (select count(*) from daily where status = 'absent'),
        'unexcusedAbsent', (select count(*) from daily where status = 'absent' and employee_id not in (select employee_id from excused_absent)),
        'locationRequestsToday', (select count(*) from location_requests_day),
        'locationRespondedToday', (select count(*) from location_requests_day where responded),
        'incomplete', (select count(*) from daily where status in ('partial','pending')),
        'pendingReview', (select count(*) from visible_events where requires_review = true),
        'isWeekend', false,
        'lastUpdatedAt', now()
      ))
  end;
$function$;

grant execute on function public.get_attendance_dashboard(date) to authenticated;

-- ---------------------------------------------------------------------
-- 4) get_executive_attendance_today (موبايل): يوم الجمعة → status='weekend'
--    المشكلة: coalesce(ad.status, 'absent') تجعل كل من ليس له سجلات يظهر كغائب
--    يوم الجمعة. الحل: coalesce(ad.status, case when isodow=5 then 'weekend' else 'absent' end)
-- ---------------------------------------------------------------------

create or replace function public.get_executive_attendance_today()
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_today date := current_date;
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_has_attendance_access boolean;
begin
  select exists(
    select 1 from public.employees
    where id = v_me and manager_id is null and status = 'active'
  ) into v_is_executive;

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
      'attendanceStatus', coalesce(ad.status,
        case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end),
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
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'present' then 2
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'late'    then 3
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'partial' then 4
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status, case when extract(isodow from v_today) = 5 then 'weekend' else 'absent' end) = 'absent'  then 8
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
      select l.latitude, l.longitude, l.recorded_at
      from public.employee_locations l
      where l.employee_id = e.id
      order by l.recorded_at desc limit 1
    ) last_loc on true
    where e.status = 'active'
      and e.is_deleted = false
      and (
        public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read')
      )
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.get_executive_attendance_today() from public;
grant execute on function public.get_executive_attendance_today() to authenticated;
