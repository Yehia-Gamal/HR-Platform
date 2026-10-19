-- 0701: إصلاح تمرير بيانات ومسميات وأسباب المأموريات المعلقة في كشف الحضور اليومي
-- حل مشكلة ظهور المأموريات كـ "طلب إجازة معلق" وبدون تفاصيل الغرض أو الوجهة

CREATE OR REPLACE FUNCTION public.get_attendance_day_roster(
  p_date date DEFAULT NULL::date,
  p_category text DEFAULT 'scheduled'::text,
  p_search text DEFAULT NULL::text,
  p_department_id uuid DEFAULT NULL::uuid,
  p_branch_id uuid DEFAULT NULL::uuid,
  p_manager_id uuid DEFAULT NULL::uuid,
  p_sort text DEFAULT 'name'::text,
  p_direction text DEFAULT 'asc'::text,
  p_limit integer DEFAULT 100,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_work_date date := coalesce(p_date, (now() at time zone 'Africa/Cairo')::date);
  v_today     date := (now() at time zone 'Africa/Cairo')::date;
  v_is_today  boolean := (v_work_date = v_today);
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
             e.is_attendance_exempt,
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
       and not (public.is_employee_isolated(e.id) and not public.can_view_isolated_employee(e.id))
       -- استبعاد غير المطالبين بالبصمة إطلاقاً (مثل الشيخ محمد وأبو عمار) ما لم يسجلوا بصمة حضور فعلية اليوم
       and not (
         (
           coalesce(e.is_attendance_exempt, false)
           or public.is_employee_attendance_exempt(e.id)
           or public.is_employee_executive(e.id)
         )
         and not exists (
           select 1 from public.attendance_daily ad
            where ad.employee_id = e.id
              and ad.work_date = v_work_date
              and ad.first_check_in is not null
         )
         and not exists (
           select 1 from public.attendance_events ae
            where ae.employee_id = e.id
              and (ae.event_at at time zone 'Africa/Cairo')::date = v_work_date
         )
       )
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
           lr.employee_id,
           lt.is_paid,
           lt.code as leave_code,
           coalesce(lt.name_ar, lt.name_en, lt.code) as leave_name,
           r.title as leave_title,
           coalesce(r.reason, r.payload->>'reason') as leave_reason,
           r.request_number as leave_request_number
      from public.leave_requests lr
      join public.requests r on r.id = lr.request_id and r.status = 'approved'
      join public.leave_types lt on lt.id = lr.leave_type_id
     where v_work_date between lr.start_date and lr.end_date
     order by lr.employee_id, lr.start_date desc
  ), approved_direct_requests as (
    select distinct on (r.employee_id)
           r.employee_id,
           r.request_type,
           coalesce(r.title, 'طلب ' || r.request_type) as request_title,
           coalesce(r.reason, r.payload->>'reason') as request_reason,
           r.request_number
      from public.requests r
     where r.status = 'approved'
       and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
     order by r.employee_id, r.created_at desc
  ), pending_requests as (
    select distinct on (r.employee_id)
           r.employee_id,
           r.id as request_id,
           r.request_number,
           r.request_type,
           coalesce(r.title, 'طلب ' || r.request_type) as request_title,
           coalesce(r.reason, r.payload->>'reason') as request_reason,
           case
             when r.request_type in ('leave', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave', 'weekly_rest_comp', 'compensation')
               then 'leave'
             when r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
               then 'mission'
             when r.request_type in ('late_permit', 'early_leave_permit', 'temporary_departure_permit')
               then 'permit'
             else r.request_type
           end as normalized_type
      from public.requests r
     where r.status in ('pending', 'submitted')
       and r.request_type in (
         'leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave', 'weekly_rest_comp',
         'mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy',
         'late_permit', 'early_leave_permit', 'temporary_departure_permit'
       )
       and v_work_date between coalesce(public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
                           and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'end_date'), public.try_cast_date(r.payload->>'permitDate'), public.try_cast_date(r.payload->>'startDate'), public.try_cast_date(r.payload->>'start_date'), public.try_cast_date(r.payload->>'date'), (r.created_at at time zone 'Africa/Cairo')::date)
     order by r.employee_id, r.created_at desc
  ), active_missions as (
    select distinct p.employee_id
       from public.work_assignment_participants p
       join public.work_assignments wa on wa.id = p.assignment_id
      where wa.status in ('APPROVED','IN_PROGRESS')
        and v_work_date between wa.start_at::date and wa.end_at::date
     union
     select r.employee_id
       from approved_direct_requests r
      where r.request_type in ('mission', 'external_mission', 'convoy', 'field_convoy', 'fundraising', 'fandy')
  ), excused_absent as (
    select dv.employee_id
      from (
        select ve.id as employee_id,
               d.status as daily_status,
               (al.employee_id is not null or adr.request_type in ('leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave')) as has_approved_leave,
               (am.employee_id is not null) as has_mission,
               (pr.employee_id is not null) as has_pending_request
          from visible_employees ve
          left join daily d on d.employee_id = ve.id
          left join approved_leaves al on al.employee_id = ve.id
          left join approved_direct_requests adr on adr.employee_id = ve.id
          left join active_missions am on am.employee_id = ve.id
          left join pending_requests pr on pr.employee_id = ve.id
      ) dv
      left join approved_leaves al on al.employee_id = dv.employee_id
      left join approved_direct_requests adr on adr.employee_id = dv.employee_id
      left join pending_requests pr on pr.employee_id = dv.employee_id
      left join events_day e on e.employee_id = dv.employee_id
     where dv.daily_status = 'absent' or dv.daily_status is null
     group by dv.employee_id
     having count(al.employee_id) filter (
              where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
            ) > 0
        or count(adr.employee_id) > 0
        or count(pr.employee_id) > 0
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
             when e.status = 'flagged' then 'أُشعر تلقائياً للمراجعة'
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
      coalesce(s.name, emp_shift.name) as shift_name,
      coalesce(s.start_time, emp_shift.start_time) as shift_start,
      coalesce(s.end_time, emp_shift.end_time) as shift_end,
      coalesce(
        (select bool_or(e.requires_review) from events_day e where e.employee_id = ve.id),
        false
      ) or (pr.employee_id is not null and (d.first_check_in is null or d.status in ('absent', 'pending'))) as requires_review,
      coalesce(
        rr.reason,
        case
          when pr.employee_id is not null and pr.normalized_type = 'leave' then
            'طلب إجازة قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null and pr.normalized_type = 'mission' then
            'طلب مأمورية قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null then
            'طلب ' || pr.request_title || ' قيد المراجعة (#' || pr.request_number || ')'
          else null
        end
      ) as review_reason,
      coalesce(al.employee_id is not null or adr.request_type in ('leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave'), false) as has_approved_leave,
      coalesce(
        al.leave_code,
        adr.request_type,
        case
          when pr.normalized_type = 'leave' then 'pending_leave'
          when pr.normalized_type = 'mission' then 'pending_mission'
          when pr.normalized_type is not null then 'pending_' || pr.normalized_type
          else null
        end
      ) as leave_code,
      coalesce(al.leave_name, adr.request_title, pr.request_title) as leave_name,
      coalesce(al.leave_title, adr.request_title, pr.request_title) as leave_title,
      coalesce(al.leave_reason, adr.request_reason, pr.request_reason) as leave_reason,
      coalesce(al.leave_request_number, adr.request_number, pr.request_number) as leave_request_number,
      coalesce(al.is_paid, true) as leave_is_paid,
      coalesce(am.employee_id is not null, false) as has_mission,
      coalesce(pr.employee_id is not null, false) as has_pending_request,
      pr.request_id    as pending_request_id,
      pr.request_number as pending_request_number,
      pr.request_title  as pending_request_title,
      pr.normalized_type as pending_request_type,
      lrd.llr_status   as location_request_status,
      lrd.requested_at as location_requested_at,
      lrd.responded_at as location_responded_at,
      coalesce(lrd.responded, false) as location_responded_today,
      -- تمييز الطاقم الطبي للعيادات لوضعهم في نهاية أي جدول (مع استثناء مديريهم مثل مصطفى أحمد ويوسف رسمي)
      (
        (
          ve.department_name in ('إدارة العيادات الطبية', 'العيادات الطبية')
          or coalesce(ve.job_title, '') in ('تمريض', 'دكتورة المعمل', 'موظف استقبال')
        )
        and ve.id not in (
          '4120ce3a-8999-453e-8d9d-acd8f3b5f04c', -- مصطفي أحمد كمال الدين
          'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'  -- يوسف رسمي شعبان
        )
        and coalesce(ve.job_title, '') not like '%مدير%'
        and coalesce(ve.job_title, '') not like '%أدارة%'
        and coalesce(ve.job_title, '') not like '%ادارة%'
        and coalesce(ve.job_title, '') not like '%مسؤول%'
      ) as is_clinic_medical_staff,
      case
        -- غير المطالبين بالبصمة لا يُعتبرون غائبين أبداً
        when (coalesce(ve.is_attendance_exempt, false) or public.is_employee_attendance_exempt(ve.id) or public.is_employee_executive(ve.id))
             and d.first_check_in is null
          then 'exempt'
        -- المأموريات والإجازات المعتمدة تعلو على نقص بصمة الانصراف
        when am.employee_id is not null then 'on_mission'
        when (al.employee_id is not null or adr.request_type in ('leave', 'compensation', 'annual_leave', 'casual_leave', 'sick_leave', 'unpaid_leave')) then 'on_leave'
        -- المأموريات والإجازات المعلّقة تنقل الموظف من الغياب إلى الإجازة/المأمورية
        when pr.employee_id is not null and pr.normalized_type = 'mission' and d.first_check_in is null then 'on_mission'
        when pr.employee_id is not null and pr.normalized_type = 'leave' and d.first_check_in is null then 'on_leave'
        -- Missing checkout applies only if day has passed without checkout, OR if shift end has elapsed on finalized records
        when d.id is not null and d.status in ('present','late')
             and d.first_check_in is not null and d.last_check_out is null
             and (not v_is_today or d.is_finalized)
          then 'missing_checkout'
        when d.id is not null and d.status in ('present','late') then d.status
        when d.id is not null then d.status
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        else 'absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.shifts s on s.id = d.shift_id
    left join lateral (
      select s2.name, s2.start_time, s2.end_time
        from public.shift_assignments sa2
        join public.shifts s2 on s2.id = sa2.shift_id
       where sa2.employee_id = ve.id
         and sa2.is_active = true
         and v_work_date >= sa2.effective_from
         and (sa2.effective_to is null or v_work_date <= sa2.effective_to)
       order by sa2.effective_from desc
       limit 1
    ) emp_shift on true
    left join review_reasons rr on rr.employee_id = ve.id
    left join approved_leaves al on al.employee_id = ve.id
    left join approved_direct_requests adr on adr.employee_id = ve.id
    left join active_missions am on am.employee_id = ve.id
    left join pending_requests pr on pr.employee_id = ve.id
    left join location_requests_day lrd on lrd.employee_id = ve.id
  ), categorized as (
    select b.*,
           case when b.is_clinic_medical_staff then 1 else 0 end as clinic_staff_order,
           case p_sort
             when 'check_in' then coalesce(to_char(b.first_check_in, 'YYYY-MM-DD HH24:MI:SS'), '9999-99-99 99:99:99')
             when 'late'     then lpad(coalesce(b.late_minutes::text, '0'), 12, '0')
             when 'status'   then coalesce(b.derived_status, '')
             else coalesce(b.full_name_ar, '')
           end as sort_key
      from base b
     where case p_category
        when 'scheduled'          then b.derived_status <> 'exempt'
        when 'present'            then b.derived_status in ('present','late','partial','missing_checkout')
        when 'late'               then b.derived_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.derived_status = 'absent' and not coalesce(b.has_pending_request, false)
        when 'unexcused_absent'   then b.derived_status = 'absent'
                                     and not coalesce(b.has_pending_request, false)
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then (b.derived_status = 'on_leave' or b.has_approved_leave = true or (b.has_pending_request = true and b.pending_request_type = 'leave'))
        when 'on_mission'         then (b.derived_status = 'on_mission' or b.has_mission = true or (b.has_pending_request = true and b.pending_request_type = 'mission'))
        when 'missing_checkout'   then (b.first_check_in is not null and b.last_check_out is null and (not v_is_today or b.is_finalized))
        when 'pending_review'     then (b.requires_review = true or b.has_pending_request = true)
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
            'firstCheckIn', c.first_check_in,
            'lastCheckOut', c.last_check_out,
            'lateMinutes', c.late_minutes,
            'shiftName', c.shift_name,
            'shiftStart', c.shift_start,
            'shiftEnd', c.shift_end,
            'requiresReview', c.requires_review,
            'reviewReason', c.review_reason,
            'hasApprovedLeave', c.has_approved_leave,
            'leaveCode', c.leave_code,
            'leaveName', c.leave_name,
            'leaveTitle', c.leave_title,
            'leaveReason', c.leave_reason,
            'leaveRequestNumber', c.leave_request_number,
            'leaveIsPaid', c.leave_is_paid,
            'hasMission', c.has_mission,
            'hasPendingRequest', c.has_pending_request,
            'pendingRequestId', c.pending_request_id,
            'pendingRequestNumber', c.pending_request_number,
            'pendingRequestTitle', c.pending_request_title,
            'pendingRequestType', c.pending_request_type,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at,
            'locationRespondedToday', c.location_responded_today,
            'isClinicMedicalStaff', c.is_clinic_medical_staff
          ) as item
          from categorized c
          order by c.clinic_staff_order asc,
            case when p_direction = 'asc'  then c.sort_key end asc nulls last,
            case when p_direction = 'desc' then c.sort_key end desc nulls last,
            c.employee_id asc
          limit v_limit offset v_offset
        ) sub
    ), '[]'::jsonb),
    'total', (select count(*) from categorized),
    'limit', v_limit,
    'offset', v_offset
  ) into v_result;

  return v_result;
end;
$function$;

revoke all on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) from public, anon;
grant execute on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) to authenticated, service_role;
comment on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) is
  '0701: تمرير مسميات وأسباب وأرقام المأموريات المعلقة بشكل دقيق في كشف الحضور.';
