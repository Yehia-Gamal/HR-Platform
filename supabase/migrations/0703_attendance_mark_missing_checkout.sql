-- 0703: إضافة إمكانية تحديد الموظف وتسجيل "انصراف بدون بصمة" (مشي بدون بصمة)
-- 1. دالة mark_attendance_missing_checkout لتسجيل انصراف الموظف بدون بصمة
-- 2. دالة unmark_attendance_missing_checkout للتراجع وإعادة الموظف للحالة النشطة
-- 3. تحديث get_attendance_day_roster لعكس الحالة فوراً حتى في اليوم الحالي (v_is_today)

begin;

-- ─── 1) دالة تسجيل انصراف بدون بصمة ─────────────────────────────────────────────
create or replace function public.mark_attendance_missing_checkout(
  p_employee_ids uuid[],
  p_work_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_work_date date := coalesce(p_work_date, (now() at time zone 'Africa/Cairo')::date);
  v_emp_id uuid;
  v_count integer := 0;
  v_daily_id uuid;
  v_first_in timestamptz;
  v_now timestamptz := now();
begin
  if p_employee_ids is null or array_length(p_employee_ids, 1) = 0 then
    raise exception 'NO_EMPLOYEES_SPECIFIED' using errcode = '22023';
  end if;

  if not (
    public.current_is_full_access()
    or exists (
      select 1 from unnest(p_employee_ids) as e_id
      where public.can_access_employee(e_id, 'attendance.record.manual_create')
         or public.can_access_employee(e_id, 'attendance.correction.review')
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  foreach v_emp_id in array p_employee_ids loop
    -- جلب أو التأكد من وجود سجل attendance_daily لليوم
    select id, first_check_in into v_daily_id, v_first_in
      from public.attendance_daily
     where employee_id = v_emp_id and work_date = v_work_date;

    -- إذا لم يكن هناك first_check_in في attendance_daily، نبحث في أحداث اليوم
    if v_first_in is null then
      select min(event_at) into v_first_in
        from public.attendance_events
       where employee_id = v_emp_id
         and (event_at at time zone 'Africa/Cairo')::date = v_work_date
         and event_type = 'CHECK_IN'
         and status in ('accepted', 'adjusted');
    end if;

    -- إذا لم يكن قد بصم حضوراً بعد، نعتمد وقت بداية افتراضي حتى يُسجل كمغادر بلا انصراف
    if v_first_in is null then
      v_first_in := (v_work_date::text || ' 09:00:00')::timestamp at time zone 'Africa/Cairo';
    end if;

    -- تحديث أو إدراج سجل attendance_daily
    insert into public.attendance_daily (
      employee_id, work_date, first_check_in, last_check_out,
      status, is_finalized, updated_at, created_by
    ) values (
      v_emp_id, v_work_date, v_first_in, null,
      'missing_checkout', true, v_now, auth.uid()
    )
    on conflict on constraint attendance_daily_uq do update set
      status = 'missing_checkout',
      last_check_out = null,
      is_finalized = true,
      updated_at = v_now
    returning id into v_daily_id;

    -- تسجيل تعديل إداري في attendance_day_overrides ليُثبت في التقارير وكشف الشهر
    insert into public.attendance_day_overrides (
      employee_id, work_date, day_type, clear_check_out,
      reason, is_active, created_by, updated_by, updated_at
    ) values (
      v_emp_id, v_work_date, 'work', true,
      'انصرف من مقر العمل بدون بصمة', true, auth.uid(), auth.uid(), v_now
    )
    on conflict (employee_id, work_date) do update set
      clear_check_out = true,
      reason = 'انصرف من مقر العمل بدون بصمة',
      is_active = true,
      updated_by = auth.uid(),
      updated_at = v_now;

    -- تسجيل استثناء إداري
    insert into public.attendance_exceptions(
      employee_id, attendance_daily_id, work_date, kind, description
    )
    select
      v_emp_id,
      v_daily_id,
      v_work_date,
      'missing_check_out',
      'انصراف من العمل بدون بصمة — تم التحديد والتأكيد إدارياً'
    where not exists (
      select 1
      from public.attendance_exceptions ae
      where ae.attendance_daily_id = v_daily_id
        and ae.kind = 'missing_check_out'
        and ae.status in ('open', 'approved', 'resolved')
    );

    v_count := v_count + 1;
  end loop;

  perform public.log_audit_event(
    'attendance.marked_missing_checkout', 'workflow', 'warning',
    'attendance_daily', null,
    'تسجيل موظفين: انصراف بدون بصمة',
    format('تم تسجيل %s موظف كمغادرين بدون بصمة انصراف لتاريخ %s', v_count, v_work_date),
    jsonb_build_object(
      'employeeIds', p_employee_ids,
      'workDate', v_work_date,
      'count', v_count
    )
  );

  return jsonb_build_object(
    'ok', true,
    'count', v_count,
    'workDate', v_work_date
  );
end;
$$;

revoke all on function public.mark_attendance_missing_checkout(uuid[], date) from public, anon;
grant execute on function public.mark_attendance_missing_checkout(uuid[], date) to authenticated, service_role;
comment on function public.mark_attendance_missing_checkout(uuid[], date) is
  '0703: تحديد الموظف كمغادر من مقر العمل بدون بصمة انصراف وتثبيتها فورياً في الكشف.';


-- ─── 2) دالة التراجع عن تسجيل انصراف بدون بصمة ──────────────────────────────────
create or replace function public.unmark_attendance_missing_checkout(
  p_employee_ids uuid[],
  p_work_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_work_date date := coalesce(p_work_date, (now() at time zone 'Africa/Cairo')::date);
  v_emp_id uuid;
  v_count integer := 0;
  v_now timestamptz := now();
begin
  if p_employee_ids is null or array_length(p_employee_ids, 1) = 0 then
    raise exception 'NO_EMPLOYEES_SPECIFIED' using errcode = '22023';
  end if;

  if not (
    public.current_is_full_access()
    or exists (
      select 1 from unnest(p_employee_ids) as e_id
      where public.can_access_employee(e_id, 'attendance.record.manual_create')
         or public.can_access_employee(e_id, 'attendance.correction.review')
    )
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  foreach v_emp_id in array p_employee_ids loop
    -- إعادة ضبط attendance_daily
    update public.attendance_daily
       set is_finalized = false,
           status = case when late_minutes > 0 then 'late' else 'present' end,
           updated_at = v_now
     where employee_id = v_emp_id
       and work_date = v_work_date
       and status = 'missing_checkout';

    -- إلغاء override الخاص بالمغادرة بدون بصمة إن وُجد
    delete from public.attendance_day_overrides
     where employee_id = v_emp_id
       and work_date = v_work_date
       and reason = 'انصرف من مقر العمل بدون بصمة';

    -- إلغاء الاستثناء إن وُجد
    delete from public.attendance_exceptions
     where employee_id = v_emp_id
       and work_date = v_work_date
       and kind = 'missing_check_out';

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'count', v_count,
    'workDate', v_work_date
  );
end;
$$;

revoke all on function public.unmark_attendance_missing_checkout(uuid[], date) from public, anon;
grant execute on function public.unmark_attendance_missing_checkout(uuid[], date) to authenticated, service_role;
comment on function public.unmark_attendance_missing_checkout(uuid[], date) is
  '0703: التراجع عن تسجيل انصراف بدون بصمة وإعادة الموظف للحالة النشطة.';


-- ─── 3) تحديث get_attendance_day_roster لعكس الحالة فوراً ──────────────────────
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
          when pr.employee_id is not null and pr.normalized_type = 'permit' then
            'تصريح عمل قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
          when pr.employee_id is not null then
            'طلب قيد المراجعة (#' || pr.request_number || '): ' || pr.request_title
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
      (
        (
          ve.department_name in ('إدارة العيادات الطبية', 'العيادات الطبية')
          or coalesce(ve.job_title, '') in ('تمريض', 'دكتورة المعمل', 'موظف استقبال')
        )
        and ve.id not in (
          '4120ce3a-8999-453e-8d9d-acd8f3b5f04c',
          'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6'
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
        -- بصمة بلا انصراف (يشمل من تم تعيينه إدارياً كمغادر بدون بصمة أو من انتهت ورديته)
        when d.id is not null and d.first_check_in is not null and d.last_check_out is null
             and (
               d.status = 'missing_checkout'
               or d.is_finalized
               or not v_is_today
               or coalesce(ado.clear_check_out, false) = true
             )
          then 'missing_checkout'
        when d.id is not null and d.status in ('present','late') then d.status
        when d.id is not null then d.status
        when public.is_official_holiday(v_work_date, ve.id) then 'holiday'
        when extract(isodow from v_work_date) = 5 then 'weekend'
        -- إذا لم يحضر ولديه طلب معلق آخر (تصريح أو عذر)
        when pr.employee_id is not null then 'absent'
        -- غياب قطعي بدون إذن
        else 'unexcused_absent'
      end as derived_status
    from visible_employees ve
    left join daily d on d.employee_id = ve.id
    left join public.attendance_day_overrides ado on ado.employee_id = ve.id and ado.work_date = v_work_date and ado.is_active = true
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
        -- إجمالي الغياب: يشمل كل من لم يسجل حضوراً اليوم وليس في مأمورية ميدانية (سواء كان في إجازة، طلب معلق، أو بدون إذن)
        when 'absent'             then (
                                       b.first_check_in is null
                                       and b.derived_status <> 'exempt'
                                       and b.derived_status <> 'on_mission'
                                       and not coalesce(b.has_mission, false)
                                     )
        -- غياب بدون إذن: حصراً من لم يسجل حضوراً وليس لديه أي إجازة معتمدة أو مأمورية أو أي طلب معلق أو عذر
        when 'unexcused_absent'   then (
                                       b.derived_status = 'unexcused_absent'
                                       or (
                                         b.first_check_in is null
                                         and b.derived_status in ('absent', 'unexcused_absent')
                                         and not coalesce(b.has_pending_request, false)
                                         and not coalesce(b.has_approved_leave, false)
                                         and not coalesce(b.has_mission, false)
                                       )
                                     )
        when 'incomplete'         then b.derived_status in ('partial','pending')
        when 'on_leave'           then (b.derived_status = 'on_leave' or b.has_approved_leave = true or (b.has_pending_request = true and b.pending_request_type = 'leave'))
        when 'on_mission'         then (b.derived_status = 'on_mission' or b.has_mission = true or (b.has_pending_request = true and b.pending_request_type = 'mission'))
        when 'missing_checkout'   then (
                                       b.derived_status = 'missing_checkout'
                                       or (b.first_check_in is not null and b.last_check_out is null and (not v_is_today or b.is_finalized or b.daily_status = 'missing_checkout'))
                                     )
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
            'managerEmployeeId', c.manager_employee_id,
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
            'isClinicMedicalStaff', c.is_clinic_medical_staff,
            'locationRequestStatus', c.location_request_status,
            'locationRequestedAt', c.location_requested_at,
            'locationRespondedAt', c.location_responded_at,
            'locationRespondedToday', c.location_responded_today
          ) as item
          from categorized c
          order by
            c.clinic_staff_order asc,
            case when p_direction = 'asc'  then c.sort_key end asc,
            case when p_direction = 'desc' then c.sort_key end desc,
            c.full_name_ar asc
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
  '0703: دعم الانصراف بدون بصمة الفوري وانتقال الموظف المباشر لتبويب بصمة بلا انصراف.';

commit;
