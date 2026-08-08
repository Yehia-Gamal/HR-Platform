-- =====================================================================
-- 0333: العمل يوم الجمعة + تفعيل تقديم بدل الراحة الأسبوعية
-- =====================================================================
-- السياق: إذا عمل موظف يوم الجمعة (مأمورية/قافلة/فاندي/بصمة حضور)، يجب أن
-- يظهر كيوم عمل — ليس كراحة أسبوعية. ويحق له طلب "بدل راحة أسبوعية"
-- (weekly_rest_comp) تعويضاً، ولا يُخصم من رصيده، بشرط موافقة المدير + HR.
--
-- 0279 وضع فحص الجمعة أولاً في CASE فقصَر كل الفروع الأخرى. هذا الترحيل
-- يعكس الترتيب: فحص الجمعة يصبح الأخير (fallback)، فيظهر عمال الجمعة
-- بحالتهم الفعلية (مأمورية/حاضر/متأخر)، ومن لم يعمل = 'weekend'.
--
-- كما يفعّل submit_my_request لقبول weekly_rest_comp (كان مرفوضاً في 0325).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) get_executive_attendance_overview: فحص الجمعة يصبح fallback
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
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id=mr.manager_employee_id
        where mr.employee_id=e.id and mr.effective_from<=now() and (mr.effective_to is null or mr.effective_to>now())
        order by mr.effective_from desc limit 1) as manager_name,
      ad.status as att_status, ad.first_check_in, ad.last_check_out,
      ad.late_minutes, ad.early_leave_minutes, ad.updated_at as att_updated_at,
      exists(
        select 1 from public.leave_requests lr join public.requests rq on rq.id=lr.request_id
        where lr.employee_id=e.id and rq.status='approved' and v_date between lr.start_date and lr.end_date
      ) as on_leave,
      (select wa.assignment_type from public.work_assignment_participants wp
         join public.work_assignments wa on wa.id=wp.assignment_id
        where wp.employee_id=e.id and wa.status in ('APPROVED','IN_PROGRESS','REPORT_PENDING','REPORT_SUBMITTED')
          and v_date between wa.start_at::date and wa.end_at::date
        order by wa.start_at desc limit 1) as assignment_type,
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
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
        when on_leave then 'on_leave'
        when assignment_type is not null then 'assignment'
        when att_status='present' and coalesce(late_minutes,0)>0 then 'late'
        when att_status='present' then 'present'
        when att_status='late' then 'late'
        when last_check_out is not null and coalesce(early_leave_minutes,0)>0 then 'left_early'
        when last_check_out is not null then 'checked_out'
        when att_status='absent' then 'absent'
        -- يوم الجمعة = راحة أسبوعية (fallback: فقط لمن لم يعمل)
        when extract(isodow from v_date) = 5 then 'weekend'
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
-- 2) get_attendance_today_overview: حذف القفزة المبكرة، حساب حقيقي يوم الجمعة
--    يوم الجمعة: expected = على مأمورية فقط، absent = expected - present
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
  v_is_friday boolean := (extract(isodow from p_date) = 5);
begin
  if not (public.current_is_full_access()
          or public.has_permission('attendance.record.read')
          or public.has_permission('people.employee.read')) then
    raise exception 'not authorized' using errcode = '42501';
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

  -- يوم الجمعة: المتوقع = من على مأمورية فقط (لا كل الموظفين)
  if v_is_friday then
    v_expected := v_on_assignment;
  else
    v_expected := greatest(0, v_total_active - v_on_leave - v_on_assignment);
  end if;

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
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now()
  );
end;
$fn$;

grant execute on function public.get_attendance_today_overview(date) to authenticated;

-- ---------------------------------------------------------------------
-- 3) get_attendance_dashboard: حذف قفزة الجمعة، دع الاستعلامات الحقيقية تعمل
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
  ), visible_employees as (
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
    'scheduled',
      -- يوم الجمعة: المتوقع = من لديهم سجل حضور فقط؛ غير ذلك = كل النشطين
      case when extract(isodow from (select work_date from params)) = 5
           then (select count(distinct employee_id) from daily)
           else (select count(*) from visible_employees)
      end,
    'present', (select count(*) from daily where status in ('present','late','partial')),
    'late', (select count(*) from daily where status = 'late' or late_minutes > 0),
    'absent', (select count(*) from daily where status = 'absent'),
    'unexcusedAbsent', (select count(*) from daily where status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from daily where status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'lastUpdatedAt', now()
  );
$function$;

grant execute on function public.get_attendance_dashboard(date) to authenticated;

-- ---------------------------------------------------------------------
-- 4) get_executive_attendance_today (موبايل): فحص mission قبل 'weekend' يوم الجمعة
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
        case
          when mission.id is not null then 'on_mission'
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
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'present' then 2
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'late'    then 3
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'partial' then 4
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'on_leave' then 5
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'holiday' then 6
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
               when extract(isodow from v_today) = 5 then 'weekend'
               else 'absent' end) = 'weekend' then 7
        when coalesce(ad.status,
          case when mission.id is not null then 'on_mission'
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
create or replace function public.submit_my_request(
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns requests
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_me uuid := public.current_employee_id();
  v_manager uuid;
  v_row public.requests;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_day_mark boolean := coalesce((v_payload->>'dayMark')::boolean, false);
  v_start_date date;
  v_end_date date;
  v_permit_date date;
  v_minutes integer;
  v_leave_type text;
  v_leave_type_id uuid;
  v_affects boolean;
  v_days numeric;
  v_substitute uuid;
  v_correction_date date;
  v_correction_type text;
  v_corrected_time text;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  -- V17 §8 + 0333: 7 أنواع رسمية بالضبط
  if p_request_type not in ('leave','mission','convoy','fundraising','late_permit','early_permit','attendance_correction') then
    raise exception 'invalid request type' using errcode = '22023';
  end if;

  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  -- قواعد تحديد اليوم (dayMark): يوم ماضٍ من نفس الشهر أو اليوم الحالي فقط.
  -- تُطبَّق على الإجازات والتوجيهات التشغيلية (مأمورية/قافلة/فاندي).
  if v_day_mark and p_request_type in ('leave','mission','convoy','fundraising') then
    v_start_date := nullif(v_payload->>'startDate', '')::date;
    v_end_date := nullif(v_payload->>'endDate', '')::date;
    if v_start_date is null or v_end_date is null then
      raise exception 'day mark requires a date' using errcode = '22023';
    end if;
    if v_end_date <> v_start_date then
      raise exception 'day marks are single-day only' using errcode = '22023';
    end if;
    if v_start_date < v_month_start then
      raise exception 'day marks are allowed within the current month only' using errcode = '22023';
    end if;
    if v_start_date > v_today then
      raise exception 'future days cannot be marked' using errcode = '22023';
    end if;
  end if;

  begin
    case p_request_type
      -- ─── إجازة ──────────────────────────────────────────────────────────────
      when 'leave' then
        v_leave_type := v_payload->>'leaveType';
        -- توافق خلفي: emergency → casual
        if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
        if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
          raise exception 'unsupported leave type' using errcode = '22023';
        end if;
        if v_start_date is null or v_end_date is null then
          raise exception 'leave start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'leave end date cannot precede start date' using errcode = '22023';
        end if;
        -- أثر رجعي: مسموح فقط عبر dayMark (نفس الشهر) — وإلا منع كالمعتاد
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive leave requests are not allowed' using errcode = '22023';
        end if;
        select id, affects_balance into v_leave_type_id, v_affects
        from public.leave_types where code = v_leave_type and is_active = true;
        if v_leave_type_id is null then
          raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
        end if;
        v_days := (v_end_date - v_start_date) + 1;
        v_payload := v_payload || jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', v_start_date,
          'endDate', v_end_date,
          'days', v_days,
          'immediate', (v_leave_type = 'casual'));

      -- ─── مأمورية / قافلة / فاندي ───────────────────────────────────────────
      when 'mission', 'convoy', 'fundraising' then
        v_start_date := nullif(v_payload->>'startDate', '')::date;
        v_end_date := nullif(v_payload->>'endDate', '')::date;
        if v_start_date is null or v_end_date is null then
          raise exception 'assignment start and end dates are required' using errcode = '22023';
        end if;
        if v_end_date < v_start_date then
          raise exception 'assignment end date cannot precede start date' using errcode = '22023';
        end if;
        -- أثر رجعي: مسموح فقط عبر dayMark — وإلا منع كالمعتاد
        if not v_day_mark and v_start_date < v_today then
          raise exception 'retroactive assignments are not allowed' using errcode = '22023';
        end if;
        if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
          raise exception 'assignment location is required' using errcode = '22023';
        end if;
        -- وقت مخطط اختياري بصيغة HH:MM — يرفض "9:00"
        if nullif(trim(coalesce(v_payload->>'startTime','')),'') is not null
           and v_payload->>'startTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'startTime must be in HH:MM format' using errcode = '22023';
        end if;
        if nullif(trim(coalesce(v_payload->>'endTime','')),'') is not null
           and v_payload->>'endTime' !~ '^\d{2}:\d{2}$' then
          raise exception 'endTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'startDate', v_start_date,
          'endDate', v_end_date,
          'location', trim(v_payload->>'location'),
          'days', (v_end_date - v_start_date) + 1,
          'startTime', nullif(trim(coalesce(v_payload->>'startTime','')),''),
          'endTime', nullif(trim(coalesce(v_payload->>'endTime','')),''));

      -- ─── إذن تأخير (V17 §8) ────────────────────────────────────────────────
      when 'late_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'late_arrival',
          'minutes', v_minutes);

      -- ─── إذن انصراف مبكر (V17 §8) ──────────────────────────────────────────
      when 'early_permit' then
        v_permit_date := nullif(v_payload->>'permitDate', '')::date;
        v_minutes := nullif(v_payload->>'minutes', '')::integer;
        if v_permit_date is null then
          raise exception 'permit date is required' using errcode = '22023';
        end if;
        if v_permit_date < v_today then
          raise exception 'retroactive permits are not allowed' using errcode = '22023';
        end if;
        if v_minutes is null or v_minutes < 1 or v_minutes > 240 then
          raise exception 'permit minutes must be between 1 and 240' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'permitDate', v_permit_date,
          'permitKind', 'early_departure',
          'minutes', v_minutes);

      -- ─── تصحيح حضور (V17 §8) ─────────────────────────────────────────────
      when 'attendance_correction' then
        v_correction_date := nullif(v_payload->>'correctionDate', '')::date;
        v_correction_type := v_payload->>'correctionType';
        v_corrected_time := v_payload->>'correctedTime';
        if v_correction_date is null then
          raise exception 'correction date is required' using errcode = '22023';
        end if;
        if v_correction_type not in ('check_in','check_out','both') then
          raise exception 'correctionType must be check_in, check_out, or both' using errcode = '22023';
        end if;
        if v_corrected_time is null or v_corrected_time !~ '^\d{2}:\d{2}$' then
          raise exception 'correctedTime must be in HH:MM format' using errcode = '22023';
        end if;
        v_payload := v_payload || jsonb_build_object(
          'correctionDate', v_correction_date,
          'correctionType', v_correction_type,
          'correctedTime', v_corrected_time);

      else
        null;
    end case;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception 'invalid request dates or numeric values' using errcode = '22023';
  end;

  -- المدير المسؤول من الهيكل الإداري (مع منع الموافقة الذاتية + توجيه التشغيل)
  v_manager := public.resolve_request_approver(v_me, v_today);

  v_row := public._submit_request_for(
    v_me,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- إنشاء صف تفصيل الإجازة (يُفعّل حجز الرصيد عبر تريغر 0026)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, v_me, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    -- العارضة/الطارئة: تُنفَّذ مباشرة دون موافقة المدير المباشر
    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', v_me));
    end if;
  end if;

  return v_row;
end $function$;
comment on function public.submit_my_request(text, text, text, jsonb) is
  'V17 §8 + 0333: تقديم طلب ذاتي — 7 أنواع، مع تحديد يوم (dayMark) بأثر رجعي بنفس الشهر وتنفيذ فوري للعارضة.';
revoke execute on function public.submit_my_request(text,text,text,jsonb) from public;
grant execute on function public.submit_my_request(text,text,text,jsonb) to authenticated;
create or replace function public.submit_employee_day_mark(
  p_employee_id uuid,
  p_request_type text,
  p_title text,
  p_reason text,
  p_payload jsonb default '{}'::jsonb
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_month_start date := date_trunc('month', v_today)::date;
  v_start_date date;
  v_end_date date;
  v_manager uuid;
  v_leave_type text;
  v_leave_type_id uuid;
  v_days numeric := 1;
  v_substitute uuid;
  v_row public.requests;
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;
  if p_employee_id is null then
    raise exception 'employee is required' using errcode = '22023';
  end if;

  -- الصلاحية: نفس صلاحية التعديل الإداري لليوم (0266)
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  -- منع التعديل على شهر مغلق
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month_start
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  -- النوع: إجازة أو توجيه تشغيلي فقط
  if p_request_type not in ('leave','mission','convoy','fundraising') then
    raise exception 'day mark supports leave, mission, convoy, fundraising only' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_title,''))) < 3
     or length(trim(coalesce(p_reason,''))) < 3 then
    raise exception 'title and reason are required (min 3 chars)' using errcode = '22023';
  end if;

  v_start_date := nullif(v_payload->>'startDate', '')::date;
  v_end_date := nullif(v_payload->>'endDate', '')::date;
  if v_start_date is null or v_end_date is null then
    raise exception 'day mark requires a date' using errcode = '22023';
  end if;
  if v_end_date <> v_start_date then
    raise exception 'day marks are single-day only' using errcode = '22023';
  end if;
  if v_start_date < v_month_start then
    raise exception 'day marks are allowed within the current month only' using errcode = '22023';
  end if;
  if v_start_date > v_today then
    raise exception 'future days cannot be marked' using errcode = '22023';
  end if;

  v_manager := public.resolve_request_approver(p_employee_id, v_today);

  if p_request_type = 'leave' then
    v_leave_type := v_payload->>'leaveType';
    if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
    if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
      raise exception 'unsupported leave type' using errcode = '22023';
    end if;
    select id into v_leave_type_id
    from public.leave_types where code = v_leave_type and is_active = true;
    if v_leave_type_id is null then
      raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
    end if;
    v_substitute := nullif(v_payload->>'substituteEmployeeId', '')::uuid;
    v_payload := v_payload || jsonb_build_object(
      'leaveType', v_leave_type,
      'startDate', v_start_date,
      'endDate', v_end_date,
      'days', v_days,
      'immediate', (v_leave_type = 'casual'),
      'dayMark', true);
  else
    if length(trim(coalesce(v_payload->>'location', ''))) < 2 then
      raise exception 'assignment location is required' using errcode = '22023';
    end if;
    v_payload := v_payload || jsonb_build_object(
      'startDate', v_start_date,
      'endDate', v_end_date,
      'location', trim(v_payload->>'location'),
      'days', v_days,
      'dayMark', true);
  end if;

  v_row := public._submit_request_for(
    p_employee_id,
    p_request_type,
    null,
    v_manager,
    trim(p_title),
    trim(p_reason),
    v_payload);

  -- صف تفصيل الإجازة + تنفيذ فوري للعارضة (نفس مسار submit_my_request)
  if p_request_type = 'leave' then
    insert into public.leave_requests(
      request_id, employee_id, leave_type_id, start_date, end_date,
      days_count, duration_unit, handover_notes, contact_during_leave,
      attachment_url, substitute_employee_id, created_by)
    values(
      v_row.id, p_employee_id, v_leave_type_id, v_start_date, v_end_date,
      v_days, 'day',
      nullif(v_payload->>'handoverNotes',''),
      nullif(v_payload->>'contactDuringLeave',''),
      nullif(v_payload->>'attachmentUrl',''),
      v_substitute, auth.uid());

    if v_leave_type = 'casual' then
      update public.requests
        set status = 'approved',
            workflow_status = 'completed',
            decided_at = now(),
            decided_by = v_me,
            updated_at = now()
        where id = v_row.id
        returning * into v_row;

      update public.request_steps
        set status = 'skipped', acted_at = now(), acted_by = v_me,
            comment = 'تنفيذ مباشر للإجازة العارضة دون موافقة', updated_at = now()
        where request_id = v_row.id and status in ('active','pending');

      update public.workflow_instances
        set status = 'completed', completed_at = now(), updated_at = now()
        where request_id = v_row.id and status = 'running';

      insert into public.request_actions(
        request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
      values(
        v_row.id, v_me, 'system', 'pending', 'approved',
        'تنفيذ مباشر للإجازة العارضة (لا تستوجب موافقة المدير المباشر)',
        jsonb_build_object('immediate', true, 'leaveType', 'casual'), auth.uid());

      perform public.log_audit_event(
        'leave.casual.immediate', 'workflow', 'info', 'requests', v_row.id,
        'تنفيذ فوري لإجازة عارضة',
        format('من %s إلى %s', v_start_date, v_end_date),
        jsonb_build_object('days', v_days, 'employeeId', p_employee_id));
    end if;
  end if;

  return v_row;
end;
$$;
comment on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) is
  '0325: إداري يُنشئ طلب تحديد يوم (مأمورية/قافلة/فاندي/إجازة) نيابةً عن موظف — بموافقة المدير المباشر.';
revoke execute on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.submit_employee_day_mark(uuid, text, text, text, jsonb) to authenticated;
