-- =====================================================================
-- 0597: لوحات المدير التنفيذي على مصدر الحضور الموحّد (attendance_day_facts)
--
-- لوحة الموارد البشرية والكشوف تُبنى منذ 0587/0589 على حقائق يوم الحضور، أما
-- لوحات المدير التنفيذي فبقيت على اشتقاق قديم فاختلفت أرقامها عنها:
--   • get_v10_executive_daily_report (التقرير التنفيذي اليومي)
--   • get_executive_attendance_overview(_fast) (نبض اليوم + لوحة المتابعة)
--   • get_executive_attendance_today (شاشة الحضور التنفيذية في الموبايل)
-- الأسباب:
--   • المأموريات/القوافل/الفاندي من work_assignments — الجدول فارغ في الإنتاج؛
--     التكليفات فعلياً طلبات (requests) أو تعديلات يوم — فكانت دائماً 0
--     ويظهر من في مأمورية «غائباً».
--   • الإجازة المعتمدة فقط من leave_requests (لا طلبات الإجازة العامة ولا
--     تعديلات اليوم)، والإجازة قيد الاعتماد كانت تُعدّ غياباً.
--   • الاستبعاد بالدور لا بقرار الإعفاء: أبو عمار (معفى من البصمة) يظهر غائباً
--     كل يوم، والتأخير من الحالة المخزنة لا من سياسة الوردية.
--   • لقطة اليوم من عرض مادي يتجدد دورياً فتتأخر عن الواقع.
-- مثال 2026-10-01: «مطلوب حضورهم» 27 مقابل 28 في لوحة الموارد البشرية،
-- والإجازات 1 مقابل 2، والمأموريات 0 مقابل 1.
--
-- الآن: دالة داخلية attendance_day_board(date) تبني على attendance_day_facts
-- حالة كل موظف في اليوم (الإعفاء، الإجازة، العمل خارج المقر ونوعه، الحضور،
-- التأخير من سياسة الوردية، الغياب بعد موعد الحضور + السماح) وتُبنى عليها
-- الدوال الأربع بنفس مفاتيح JSON التي تقرؤها الواجهات.
-- موعد الحضور كما في 0595: الوردية المسندة ثم جدول المناوبات المنشور ثم الدوام
-- الأساسي (10:00 + 15 دقيقة سماح).
-- =====================================================================

begin;

-- ─── 1) حالة كل موظف في يوم (داخلية — لا تُستدعى من العميل) ──────────────
create or replace function public.attendance_day_board(p_date date)
returns table (
  employee_id uuid,
  is_exempt boolean,
  is_workday boolean,
  is_holiday boolean,
  leave_like boolean,
  approved_leave boolean,
  offsite boolean,
  offsite_type text,
  checked_in boolean,
  expected boolean,
  late_minutes integer,
  first_check_in timestamptz,
  last_check_out timestamptz,
  early_leave_minutes integer,
  att_status text,
  att_updated_at timestamptz,
  due_time time,
  missing_checkout boolean,
  board_status text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  with clock as (
    select (now() at time zone 'Africa/Cairo')::date as today,
           (now() at time zone 'Africa/Cairo')::time as now_time
  ),
  f as (
    select * from public.attendance_day_facts(p_date, p_date)
  ),
  enriched as (
    select f.*,
      ad.first_check_in as ad_first_in,
      ad.last_check_out as ad_last_out,
      coalesce(ad.early_leave_minutes, 0) as ad_early,
      ad.status as ad_status,
      ad.updated_at as ad_updated_at,
      o.day_type as override_type,
      sh.start_time as shift_start,
      sh.end_time as shift_end,
      sh.grace as shift_grace
    from f
    left join public.attendance_daily ad
      on ad.employee_id = f.employee_id and ad.work_date = f.work_date
    left join public.attendance_day_overrides o
      on o.employee_id = f.employee_id and o.work_date = f.work_date and o.is_active
    left join lateral (
      select s.start_time, s.end_time, coalesce(s.grace_in_minutes, 15) as grace
        from (
          select sa.shift_id, 1 as prio, sa.effective_from::timestamp as ord
            from public.shift_assignments sa
           where sa.employee_id = f.employee_id
             and sa.is_active
             and sa.effective_from <= p_date
             and (sa.effective_to is null or sa.effective_to >= p_date)
          union all
          select rd.shift_id, 2, wr.published_at::timestamp
            from public.roster_days rd
            join public.work_rosters wr on wr.id = rd.roster_id and wr.status = 'published'
           where rd.employee_id = f.employee_id
             and rd.work_date = p_date
             and rd.day_status = 'scheduled'
          union all
          select s0.id, 3, null::timestamp
            from public.shifts s0
           where s0.code = 'OFFICIAL' and s0.is_active
        ) c
        join public.shifts s on s.id = c.shift_id
       order by c.prio, c.ord desc nulls last
       limit 1
    ) sh on true
  ),
  typed as (
    select e.*,
      coalesce(e.shift_start, '10:00'::time) + make_interval(mins => coalesce(e.shift_grace, 15)) as due_at,
      (e.leave_like and (
         coalesce(e.override_type, '') = 'leave'
         or coalesce(e.ad_status, '') = 'on_leave'
         or exists (
           select 1 from public.leave_requests lr
             join public.requests r on r.id = lr.request_id
            where lr.employee_id = e.employee_id and r.status = 'approved'
              and p_date between lr.start_date and lr.end_date)
         or exists (
           select 1 from public.requests r
            where r.employee_id = e.employee_id and r.status = 'approved'
              and r.request_type in ('leave', 'casual_leave', 'annual_leave', 'sick_leave', 'unpaid_leave', 'compensation')
              and p_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                             and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                          public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date')))
      )) as approved_leave_flag,
      case when e.offsite then coalesce(
        case e.override_type
          when 'mission' then 'MISSION'
          when 'convoy' then 'CONVOY'
          when 'fundraising' then 'FUNDRAISING'
        end,
        (select case
                  when r.request_type in ('convoy', 'field_convoy')
                       or coalesce(r.payload->>'missionType', r.payload->>'type') = 'convoy' then 'CONVOY'
                  when r.request_type in ('fundraising', 'fandy', 'fundi')
                       or coalesce(r.payload->>'missionType', r.payload->>'type') in ('fundraising', 'fandy') then 'FUNDRAISING'
                  else 'MISSION'
                end
           from public.requests r
          where r.employee_id = e.employee_id
            and r.status not in ('rejected', 'cancelled')
            and (r.request_type in ('mission', 'external_mission', 'administrative_mission', 'convoy', 'field_convoy',
                                    'fundraising', 'fandy', 'fundi', 'remote_work')
                 or coalesce(r.payload->>'missionType', r.payload->>'type') in ('convoy', 'fundraising', 'fandy', 'mission'))
            and p_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'),
                                        public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'))
          order by r.created_at desc
          limit 1),
        'MISSION') end as offsite_kind,
      (exists (
         select 1 from public.public_holidays h
          where coalesce(h.is_active, true)
            and p_date between h.holiday_date and coalesce(h.end_date, h.holiday_date))
       or coalesce(e.override_type, '') = 'holiday') as holiday_flag
    from enriched e
  )
  select
    t.employee_id,
    t.is_exempt,
    t.is_workday,
    t.holiday_flag,
    t.leave_like,
    t.approved_leave_flag,
    t.offsite,
    t.offsite_kind,
    t.checked_in,
    (t.is_workday and not t.leave_like and not (t.offsite and not t.checked_in)) as expected,
    coalesce(t.late_minutes, 0),
    t.ad_first_in,
    t.ad_last_out,
    t.ad_early,
    t.ad_status,
    t.ad_updated_at,
    t.due_at,
    (t.checked_in and t.ad_last_out is null
      and (p_date < c.today or (p_date = c.today and c.now_time > coalesce(t.shift_end, '18:00'::time)))) as missing_checkout,
    case
      when t.is_exempt then 'exempt'
      when t.leave_like then 'on_leave'
      when t.offsite and not t.checked_in then 'assignment'
      when t.checked_in then case
        when coalesce(t.late_minutes, 0) > 0 then 'late'
        when t.ad_last_out is not null and t.ad_early > 0 then 'left_early'
        when t.ad_last_out is not null then 'checked_out'
        else 'present'
      end
      when not t.is_workday then 'weekend'
      when p_date > c.today then 'not_yet'
      when p_date < c.today or c.now_time >= t.due_at then 'absent'
      else 'not_yet'
    end
  from typed t
  cross join clock c;
$fn$;

revoke execute on function public.attendance_day_board(date) from public, anon, authenticated;
grant execute on function public.attendance_day_board(date) to service_role;

comment on function public.attendance_day_board(date) is
  '0597: حالة كل موظف في يوم من attendance_day_facts — مصدر لوحات المدير التنفيذي (داخلية).';

-- ─── 2) التقرير التنفيذي اليومي ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_v10_executive_daily_report(p_date date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_date     date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_result   jsonb;
begin
  if not (
    public.current_is_executive_secretary()
    or public.current_has_active_role(array['executive','executive-director'])
    or public.has_any_permission(array['reports.executive.read','reports.attendance.read','performance.kpi.report.read'])
  ) then raise exception 'EXECUTIVE_REPORT_FORBIDDEN' using errcode='42501'; end if;

  with b as (
    select * from public.attendance_day_board(v_date) where not is_exempt
  ), attendance_summary as (
    select count(*) total_active,
      count(*) filter (where expected) required_today,
      count(*) filter (where checked_in) present,
      count(*) filter (where checked_in and late_minutes > 0) late,
      count(*) filter (where board_status = 'absent') absent,
      count(*) filter (where board_status = 'not_yet') not_yet,
      count(*) filter (where last_check_out is not null) checked_out,
      count(*) filter (where missing_checkout) missing_checkout,
      count(*) filter (where approved_leave) approved_leave,
      count(*) filter (where offsite and offsite_type = 'MISSION') missions,
      count(*) filter (where offsite and offsite_type = 'CONVOY') convoys,
      count(*) filter (where offsite and offsite_type = 'FUNDRAISING') fundraising
    from b
  ), kpi_summary as (
    select
      count(*) filter(where e.current_stage='self') at_employee,
      count(*) filter(where e.current_stage in ('manager_review','manager_final')) at_manager,
      count(*) filter(where e.current_stage='hr_review') at_hr,
      count(*) filter(where e.current_stage in ('finalized','closed','archived')) ready,
      count(*) filter(where e.workflow_status='OVERDUE') overdue
    from public.kpi_evaluations e
    join public.kpi_cycles c on c.id=e.cycle_id
    where c.period_month = date_trunc('month', v_date)::date
  )
  select jsonb_build_object(
    'date', v_date,
    'employees', jsonb_build_object('active', a.total_active, 'requiredToday', a.required_today),
    'attendance', jsonb_build_object(
      'present', a.present, 'late', a.late, 'absent', a.absent,
      'notYet', a.not_yet, 'checkedOut', a.checked_out, 'missingCheckout', a.missing_checkout
    ),
    'workStatus', jsonb_build_object(
      'approvedLeave', a.approved_leave, 'missions', a.missions,
      'convoys', a.convoys, 'fundraising', a.fundraising
    ),
    'requests', jsonb_build_object(
      'pendingLeave', (select count(*) from public.requests where request_type='leave' and status='pending'),
      'pendingMission', (select count(*) from public.requests where request_type in ('mission','convoy') and status='pending')
    ),
    'kpi', jsonb_build_object(
      'atEmployee', k.at_employee, 'atManager', k.at_manager, 'atHr', k.at_hr,
      'ready', k.ready, 'overdue', k.overdue
    ),
    'cases', jsonb_build_object(
      'new', (select count(*) from public.dispute_cases where status in ('submitted','needs_more_information')),
      'open', (select count(*) from public.dispute_cases where status not in ('closed','rejected','cancelled_by_employee'))
    ),
    'followUp', jsonb_build_object(
      'decisions', (select count(*) from public.administrative_decisions where status in ('draft','in_review','approved')),
      'missingReports', (select count(*) from public.work_assignments where status='REPORT_PENDING'),
      'activeLocationRequests', (select count(*) from public.live_location_requests where status in ('pending','accepted','active') and (expires_at is null or expires_at>now())),
      'unansweredLocationRequests', (select count(*) from public.live_location_requests where status='pending' and (expires_at is null or expires_at>now()))
    ),
    'sources', jsonb_build_object(
      'employees', 'attendance_day_facts (المعفون من البصمة خارج العدّ)',
      'attendance', 'attendance_day_board ← attendance_day_facts + attendance_daily (0597)',
      'workStatus', 'requests + attendance_day_overrides + leave_requests (0597)',
      'requests', 'requests',
      'kpi', 'kpi_evaluations + kpi_cycles',
      'cases', 'dispute_cases',
      'followUp', 'administrative_decisions + work_assignments + live_location_requests'
    ),
    'generatedAt', now()
  ) into v_result from attendance_summary a cross join kpi_summary k;

  return v_result;
end $function$;

-- ─── 3) لوحة المتابعة ونبض اليوم ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_executive_attendance_overview(p_date date DEFAULT NULL::date)
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

  -- 0597: حيّ لكل التواريخ من المصدر الموحّد (كان اليوم من عرض مادي متأخر)
  with base as (
    select
      e.id, e.full_name_ar, e.employee_code, e.photo_url,
      jt.name as job_title, d.name as department,
      (select mgr.full_name_ar from public.manager_relations mr
         join public.employees mgr on mgr.id = mr.manager_employee_id
        where mr.employee_id = e.id and mr.effective_from <= now()
          and (mr.effective_to is null or mr.effective_to > now())
        order by mr.effective_from desc limit 1) as manager_name,
      b.board_status as derived_status, b.att_status, b.first_check_in, b.last_check_out,
      b.late_minutes, b.early_leave_minutes, b.att_updated_at, b.leave_like as on_leave,
      case when b.offsite then b.offsite_type end as assignment_type,
      b.is_exempt,
      lp.latitude, lp.longitude, lp.accuracy, lp.recorded_at, lp.address_ar, lp.source as loc_source,
      ar.id as active_request_id, ar.status as active_request_status
    from public.attendance_day_board(v_date) b
    join public.employees e on e.id = b.employee_id
    left join public.job_titles jt on jt.id = e.job_title_id
    left join public.departments d on d.id = e.department_id
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
    where not public.is_employee_executive(e.id)  -- 0444: استبعاد المدير التنفيذي
      and (public.current_is_full_access()
        or public.can_access_employee(e.id, 'attendance.record.read')
        or public.can_access_employee(e.id, 'people.employee.read'))
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
      -- المعفى من البصمة يظهر في القائمة («معفى») ولا يدخل أرقام الحضور
      'total',          count(*) filter (where not is_exempt),
      'present',        count(*) filter (where derived_status = 'present'),
      'late',           count(*) filter (where derived_status = 'late'),
      'notYet',         count(*) filter (where derived_status = 'not_yet'),
      'absent',         count(*) filter (where derived_status = 'absent'),
      'checkedOut',     count(*) filter (where derived_status = 'checked_out'),
      'leftEarly',      count(*) filter (where derived_status = 'left_early'),
      'onLeave',        count(*) filter (where derived_status = 'on_leave'),
      'onAssignment',   count(*) filter (where derived_status = 'assignment'),
      'onMission',      count(*) filter (where not is_exempt and assignment_type = 'MISSION'),
      'onConvoy',       count(*) filter (where not is_exempt and assignment_type = 'CONVOY'),
      'onFundraising',  count(*) filter (where not is_exempt and assignment_type = 'FUNDRAISING'),
      'weekend',        count(*) filter (where derived_status = 'weekend'),
      'exempt',         count(*) filter (where is_exempt),
      'activeLocationRequests', count(*) filter (where active_request_id is not null)
    )
  into v_rows, v_summary
  from base;

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
begin
  if not (
    public.current_is_full_access()
    or public.has_permission('reports.attendance.read')
    or public.has_permission('live_location.request')
  ) then
    raise exception 'attendance overview permission required' using errcode = '42501';
  end if;

  -- 0597: العرض المادي يتأخر عن الواقع ويختلف عن المصدر الموحّد — نفس الدالة الحية
  return public.get_executive_attendance_overview(p_date);
end;
$function$;

-- ─── 4) شاشة الحضور التنفيذية في الموبايل ───────────────────────────────
CREATE OR REPLACE FUNCTION public.get_executive_attendance_today(p_status text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_today date := (now() at time zone 'Africa/Cairo')::date;
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
    raise exception 'صلاحية تنفيذي أو حضور مطلوبة' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(x.item order by x.sort_order, x.item->>'name')
    from (
      select
        jsonb_build_object(
          'id',               e.id,
          'name',             e.full_name_ar,
          'employeeCode',     e.employee_code,
          'jobTitle',         jt.name,
          'department',       d.name,
          'departmentId',     d.id,
          'photoUrl',         e.photo_url,
          'attendanceStatus', s.app_status,
          'firstCheckIn',     b.first_check_in,
          'lastCheckOut',     b.last_check_out,
          'lateMinutes',      b.late_minutes,
          'isOnMission',      (b.board_status = 'assignment'),
          'lastLatitude',     last_loc.latitude,
          'lastLongitude',    last_loc.longitude,
          'lastRecordedAt',   last_loc.recorded_at
        ) as item,
        case
          when b.board_status = 'assignment' then 1
          when s.app_status = 'present'  then 2
          when s.app_status = 'late'     then 3
          when s.app_status = 'on_leave' then 5
          when s.app_status = 'holiday'  then 6
          when s.app_status = 'weekend'  then 7
          when s.app_status = 'absent'   then 8
          else 9
        end as sort_order
      from public.attendance_day_board(v_today) b
      -- مفردات حالة التطبيق: لا «لم يحضر بعد» فيها، فقبل موعد الحضور + السماح يبقى «غائب» كما كان
      cross join lateral (
        select case b.board_status
          when 'late' then 'late'
          when 'present' then 'present'
          when 'checked_out' then 'present'
          when 'left_early' then 'present'
          when 'on_leave' then 'on_leave'
          when 'assignment' then 'on_mission'
          when 'weekend' then case when b.is_holiday then 'holiday' else 'weekend' end
          else 'absent'
        end as app_status
      ) s
      join public.employees e on e.id = b.employee_id
      left join public.job_titles  jt on jt.id = e.job_title_id
      left join public.departments d  on d.id  = e.department_id
      left join lateral (
        select l.latitude, l.longitude, l.recorded_at
        from public.employee_locations l
        where l.employee_id = e.id
        order by l.recorded_at desc limit 1
      ) last_loc on true
      where not b.is_exempt  -- 0597: المعفى من البصمة ليس غائباً
        and (p_department_id is null or e.department_id = p_department_id)
        and (v_search is null
          or e.full_name_ar ilike '%' || v_search || '%'
          or e.employee_code ilike '%' || v_search || '%')
        and (v_status_match is null or s.app_status = v_status_match)
        and (
          v_is_executive
          or public.current_is_full_access()
          or public.can_access_employee(e.id, 'attendance.record.read')
          or public.can_access_employee(e.id, 'people.employee.read')
        )
    ) x
  ), '[]'::jsonb);
end;
$function$;

commit;
