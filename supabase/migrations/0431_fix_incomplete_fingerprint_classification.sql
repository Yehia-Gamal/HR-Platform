-- 0431: تصنيف "بصمة بلا انصراف" — من بصم حضوراً يُعدّ حاضراً لليوم
--
-- الجذر: قائمة "بصمات غير مكتملة" كانت تضم من حضر وبصم انصرافه ناقص
-- (missing_checkout) رغم أن الآلية الليلية finalize_missing_checkouts تسجّله
-- "بصمة انصراف ناقصة" مع بقائه حاضراً لليوم (حضر ولم يُتمم الانصراف فقط).
--
-- التغيير على get_attendance_dashboard و get_attendance_day_roster:
--   1) فئة present تشمل missing_checkout → حضر لليوم.
--   2) فئة incomplete تقتصر على partial + pending (بصمات غير مكتملة فعلاً).
-- فئة missing_checkout القائمة ("بصمة بلا انصراف") تبقى كشرح/تنبيه مستقل.

CREATE OR REPLACE FUNCTION public.get_attendance_dashboard(p_date date DEFAULT NULL::date, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id, e.department_id, e.branch_id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
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
    -- موظف غائب لكن له event في هذا اليوم (بصمة جزئية) = مبرر
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
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'lastUpdatedAt', now()
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(p_date date DEFAULT NULL::date, p_category text DEFAULT 'scheduled'::text, p_search text DEFAULT NULL::text, p_department_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_manager_id uuid DEFAULT NULL::uuid, p_sort text DEFAULT 'name'::text, p_direction text DEFAULT 'asc'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_search    text := nullif(trim(coalesce(p_search, '')), '');
  v_limit     int  := greatest(1, least(coalesce(p_limit, 100), 500));
  v_offset    int  := greatest(0, coalesce(p_offset, 0));
  v_result    jsonb;
begin
  if p_category not in (
    'scheduled','present','late','absent','unexcused_absent',
    'incomplete','pending_review','location_requests','location_responded',
    'on_leave','on_mission','missing_checkout'
  ) then
    raise exception 'invalid attendance roster category: %', p_category
      using errcode = '22023';
  end if;
  if p_limit is not null and p_limit <= 0 then
    raise exception 'invalid roster limit: %', p_limit using errcode = '22023';
  end if;
  if p_offset is not null and p_offset < 0 then
    raise exception 'invalid roster offset: %', p_offset using errcode = '22023';
  end if;
  if p_sort not in ('name','check_in','late','status') then
    raise exception 'invalid roster sort: %', p_sort using errcode = '22023';
  end if;
  if p_direction not in ('asc','desc') then
    raise exception 'invalid roster direction: %', p_direction using errcode = '22023';
  end if;

  with visible_employees as (
      select e.id, e.employee_code, e.full_name_ar, e.photo_url,
             e.department_id, e.branch_id,
             d.name as department_name,
             b.name as branch_name,
             jt.name as job_title,
             mr.manager_employee_id,
             me.full_name_ar as manager_name
      from public.employees e
      left join public.departments d on d.id = e.department_id
      left join public.branches b on b.id = e.branch_id
      left join public.job_titles jt on jt.id = e.job_title_id
      left join lateral (
        select mr.manager_employee_id
          from public.manager_relations mr
         where mr.employee_id = e.id
           and mr.relation_type = 'primary'
           and mr.effective_to is null
         order by mr.effective_from desc
         limit 1
      ) mr on true
      left join public.employees me on me.id = mr.manager_employee_id
     where e.is_active = true and coalesce(e.is_deleted, false) = false
       and (p_department_id is null or e.department_id = p_department_id)
       and (p_branch_id is null or e.branch_id = p_branch_id)
       and (p_manager_id is null or mr.manager_employee_id = p_manager_id)
       and (v_search is null
         or lower(e.full_name_ar) like '%' || v_search || '%'
         or lower(e.employee_code) like '%' || v_search || '%')
  ), daily as (
    select d.* from public.attendance_daily d where d.work_date = v_work_date
  ), events_day as (
    select e.* from public.attendance_events e
     where (e.event_at at time zone 'Africa/Cairo')::date = v_work_date
  ), approved_leaves as (
    select distinct on (lr.employee_id)
           lr.employee_id, lt.is_paid, lt.code as leave_code
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
     order by lr.employee_id, lr.start_date desc
  ), active_missions as (
    select distinct p.employee_id
      from public.work_assignment_participants p
      join public.work_assignments wa on wa.id = p.assignment_id
     where wa.status in ('APPROVED','IN_PROGRESS')
       and v_work_date between wa.start_at::date and wa.end_at::date
  ), excused_absent as (
    select dv.employee_id
      from (
        select ve.id as employee_id,
               d.status as daily_status,
               (al.employee_id is not null) as has_approved_leave,
               (am.employee_id is not null) as has_mission
          from visible_employees ve
          left join daily d on d.employee_id = ve.id
          left join approved_leaves al on al.employee_id = ve.id
          left join active_missions am on am.employee_id = ve.id
      ) dv
      left join approved_leaves al on al.employee_id = dv.employee_id
      left join events_day e on e.employee_id = dv.employee_id
     where dv.daily_status = 'absent'
     group by dv.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
      or count(e.id) > 0
  ), location_requests_day as (
    select distinct on (llr.employee_id)
           llr.employee_id, llr.status as llr_status, llr.requested_at, llr.responded_at,
           (llr.responded_at is not null or llr.status in ('accepted','active','completed')) as responded
      from public.live_location_requests llr
     where (llr.requested_at at time zone 'Africa/Cairo')::date = v_work_date
        or (llr.responded_at is not null and (llr.responded_at at time zone 'Africa/Cairo')::date = v_work_date)
     order by llr.employee_id, llr.requested_at desc
  ), review_reasons as (
    select distinct on (e.employee_id) e.employee_id,
           case
             when e.verification_status = 'failed' then 'فشل التحقق من الهوية'
             when e.latitude is null or e.longitude is null then 'لا يوجد موقع مؤكد'
             when e.accuracy_meters is not null and e.accuracy_meters > 100 then 'دقة GPS منخفضة'
             when e.distance_meters is not null and e.distance_meters > 0 then 'خارج النطاق المعتمد'
             when e.status = 'flagged' then 'أُشعِر تلقائيًا للمراجعة'
             else 'يحتاج مراجعة بشرية'
           end as reason
      from events_day e
     where e.requires_review = true
     order by e.employee_id, e.created_at desc
  ), base as (
    select
      ve.id            as employee_id,
      ve.employee_code,
      ve.full_name_ar,
      ve.photo_url,
      ve.department_id,
      ve.department_name,
      ve.branch_id,
      ve.branch_name,
      ve.job_title,
      ve.manager_employee_id,
      ve.manager_name,
      d.id             as daily_id,
      d.status         as daily_status,
      d.first_check_in,
      d.last_check_out,
      coalesce(d.late_minutes, 0) as late_minutes,
      coalesce(d.is_finalized, false) as is_finalized,
      s.name           as shift_name,
      s.start_time     as shift_start,
      s.end_time       as shift_end,
      coalesce((select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id), false) as requires_review,
      rr.reason        as review_reason,
      (al.employee_id is not null) as has_approved_leave,
      al.leave_code,
      al.is_paid       as leave_is_paid,
      (am.employee_id is not null) as has_mission,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today,
      case
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and not d.is_finalized
          then 'missing_checkout'
        when am.employee_id is not null then 'on_mission'
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.shifts s on s.id = d.shift_id
    left join review_reasons rr on rr.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  ), categorized as (
    select b.*,
           case p_sort
             when 'check_in' then coalesce(to_char(b.first_check_in, 'YYYY-MM-DD HH24:MI:SS'), '9999-99-99 99:99:99')
             when 'late'     then lpad(coalesce(b.late_minutes::text, '0'), 12, '0')
             when 'status'   then coalesce(b.derived_status, '')
             else coalesce(b.full_name_ar, '')
           end as sort_key
      from base b
     where case p_category
        when 'scheduled'          then true
        when 'present'            then b.derived_status in ('present','late','partial','missing_checkout')
        when 'late'               then b.derived_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.derived_status = 'absent'
        when 'unexcused_absent'   then b.derived_status = 'absent'
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then b.derived_status = 'on_leave'
        when 'on_mission'         then b.derived_status = 'on_mission'
        when 'missing_checkout'   then b.derived_status = 'missing_checkout'
        when 'pending_review'     then b.requires_review = true
        when 'location_requests'  then b.location_requested_at is not null
                                    or b.location_responded_at is not null
        when 'location_responded' then b.location_responded_today = true
        else false
      end
  )
  select jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(item)
        from (
          select jsonb_build_object(
            'employeeId', c.employee_id,
            'employeeCode', c.employee_code,
            'employeeName', c.full_name_ar,
            'photoUrl', c.photo_url,
            'departmentId', c.department_id,
            'departmentName', c.department_name,
            'branchId', c.branch_id,
            'branchName', c.branch_name,
            'jobTitle', c.job_title,
            'managerId', c.manager_employee_id,
            'managerName', c.manager_name,
            'status', c.derived_status,
            'lateMinutes', c.late_minutes,
            'firstCheckIn', c.first_check_in,
            'lastCheckOut', c.last_check_out,
            'shiftName', c.shift_name,
            'shiftStartAt', c.shift_start,
            'shiftEndAt', c.shift_end,
            'requiresReview', c.requires_review,
            'reviewReason', c.review_reason,
            'hasApprovedLeave', c.has_approved_leave,
            'leaveCode', c.leave_code,
            'leaveIsPaid', c.leave_is_paid,
            'hasMission', c.has_mission,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at
          ) as item
          from categorized c
          order by
            case when p_direction = 'desc' then c.sort_key end desc,
            case when p_direction = 'asc'  then c.sort_key end asc,
            c.full_name_ar asc
          limit v_limit offset v_offset
        ) t
    ), '[]'::jsonb),
    'total', (select count(*) from categorized),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result;

  return v_result;
end;
$function$;