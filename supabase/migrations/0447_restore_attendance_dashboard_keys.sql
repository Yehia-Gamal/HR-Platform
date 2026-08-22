-- =====================================================================
-- 0447: استعادة دلالات لوحة الحضور من 0431 (كانت قد تراجعت في 0444)
-- ---------------------------------------------------------------------
-- إعادة كتابة get_attendance_dashboard في 0444 كانت انطلاقاً من نسخة
-- أقدم فتراجعت عن عقد 0431 دون قصد (استبعاد التنفيذي لا علاقة له بها):
--   1) مفتاحا 'incomplete' و'pendingReview' و'isWeekend'
--      و'locationRespondedToday' حُذفا من الإخراج.
--   2) عدّاد present فقد missing_checkout — ومن بصم حضوراً بلا انصراف
--      يبقى حاضراً لليوم (عقد 0431).
--   3) أولوية on_mission انعكست: صاحب صف حضور ومن تكليف معتمد كان يظهر
--      بحالة الصف بدل on_mission.
-- هذا الملف يعيد دلالات 0431 كما هي، ويحافظ على استبعاد المدير التنفيذي
-- من 0444، ويُبقي مفاتيح 0444 الجديدة (locationRequestsResponded/date)
-- للتوافق مع الواجهة.
-- =====================================================================

begin;

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
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
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
    'present', (select count(*) from derived where derived_status in ('present','late','partial','missing_checkout')),
    'late', (select count(*) from derived where derived_status = 'late' or late_minutes > 0),
    'absent', (select count(*) from derived where derived_status = 'absent'),
    'unexcusedAbsent', (select count(*) from derived where derived_status = 'absent' and employee_id not in (select employee_id from excused_absent)),
    'onLeave', (select count(*) from derived where derived_status = 'on_leave'),
    'onMission', (select count(*) from derived where derived_status = 'on_mission'),
    'missingCheckout', (select count(*) from derived where derived_status = 'missing_checkout'),
    'locationRequestsToday', (select count(*) from location_requests_day),
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    -- مفاتيح 0444 تبقى للتوافق مع الواجهة الأحدث:
    'locationRequestsResponded', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'date', (select work_date from params),
    'lastUpdatedAt', now()
  );
$function$;

-- ─── 2) get_executive_attendance_overview: إعادة ترتيب فحص الجمعة كـ fallback ─
-- 0444 أعاد كتابة الفرع الحي بفحص weekend أولاً فيرجع كل يوم جمعة 'weekend'
-- حتى من هو في إجازة أو تكليف — نفس الانتكاسة التي أصلحها 0402 (عقد 0333).
-- الترتيب الصحيح: الحالات الفعلية أولاً ثم weekend ثم not_yet.
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
$$;

commit;

notify pgrst, 'reload schema';