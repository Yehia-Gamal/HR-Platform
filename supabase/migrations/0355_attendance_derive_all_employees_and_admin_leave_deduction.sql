-- ============================================================================
-- 0355: لوحة الحضور تَحصي كل الموظفين (لا صفوف attendance_daily فقط) +
--       المسار الإداري ينشئ طلباً معتمداً ويخصم الرصيد
-- ============================================================================
-- السياق (من فحص حي في DB محلي):
--   1) get_attendance_dashboard (0350) والرستر (0294) كانا يعتمدان على صفوف
--      attendance_daily فقط، وتُنشأ هذه الصفوف عند البصمة الفعلية أو عند اعتماد
--      طلب (on_leave / present). لذا:
--        • من لم يحضر إطلاقاً (no-show) لا صف له → لا يُعدّ غائباً إطلاقاً.
--        • من في مأمورية/قافلة/فاندي قد لا يكون له صف → لا يظهر.
--        • البصمة الواحدة (check-in بلا check-out) → status='present'/'late'
--          لأن v_first_check_in موجود → تُعدّ حاضراً لا incomplete.
--      الحل: اشتقاق حالة كل موظف نشط (مثل get_executive_attendance_today 0333)
--      من: attendance_daily ← approved leave ← active mission ← عطلة رسمية
--          ← الجمعة ← absent (افتراضياً).
--   2) set_employee_attendance_day_admin (0266) كان يكتب attendance_day_overrides
--      فقط — بلا attendance_daily وبلا leave_requests وبلا خصم رصيد. قرار
--      المنتج: عند ترميز إجازة/غياب/مأمورية/قافلة/فاندي إدارياً، يُنشأ طلب معتمد
--      فوراً (عبر _submit_request_for ثم اعتماد مباشر) فيشتغل كل التريغرات
--      القياسية: خصم الرصيد (consume) + وسم attendance_daily (on_leave/present)
--      + سجل تدقيق — بلا تكرار منطق.
--
-- التغييرات:
--   (1) get_attendance_dashboard: إعادة بناء بالاشتقاق الشامل لكل موظف.
--   (2) get_attendance_day_roster: نفس الاشتقاق + فئات on_leave/on_mission/
--       missing_checkout جديدة (توافقية مع الفئات التسع القائمة).
--   (3) set_employee_attendance_day_admin: بارامتر p_leave_type جديد + إنشاء
--       طلب معتمد وخصم الرصيد عند الترميز الإداري المباشر.
--   (4) دالة مساعدة _admin_approve_request_immediately للاعتماد الفوري مع
--       إنهاء الخطوات/نموذج سير العمل كمسار العارضة (0325).
-- ============================================================================

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- (1) get_attendance_dashboard — اشتقاق حالة كل موظف نشط (مفلتر)
-- ═══════════════════════════════════════════════════════════════════════════

drop function if exists public.get_attendance_dashboard(date);

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
      left join approved_leaves al on al.employee_id = dv.employee_id
      left join visible_events e on e.employee_id = dv.employee_id
     where dv.derived_status = 'absent'
     group by dv.employee_id
    having count(al.employee_id) filter (
             where al.is_paid or coalesce(al.leave_code, '') <> 'sick'
           ) > 0
      or count(e.id) > 0
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
      -- يوم الجمعة: المتوقع = من لديهم سجل حضور فقط؛ غير ذلك = كل النشطين المفلترين
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
    'locationRespondedToday', (select count(*) from location_requests_day where responded),
    'incomplete', (select count(*) from derived where derived_status in ('partial','pending','missing_checkout')),
    'pendingReview', (select count(*) from visible_events where requires_review = true),
    'isWeekend', (extract(isodow from (select work_date from params)) = 5),
    'lastUpdatedAt', now()
  );
$function$;

grant execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- (2) get_attendance_day_roster — نفس الاشتقاق + فئات جديدة
-- ═══════════════════════════════════════════════════════════════════════════

create or replace function public.get_attendance_day_roster(
  p_date date default null,
  p_category text default 'scheduled',
  p_search text default null,
  p_department_id uuid default null,
  p_branch_id uuid default null,
  p_manager_id uuid default null,
  p_sort text default 'name',
  p_direction text default 'asc',
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $function$
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
        when d.id is not null then d.status
        when al.employee_id is not null then 'on_leave'
        when am.employee_id is not null then 'on_mission'
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
        when 'present'            then b.derived_status in ('present','late','partial')
        when 'late'               then b.derived_status = 'late' or b.late_minutes > 0
        when 'absent'             then b.derived_status = 'absent'
        when 'unexcused_absent'   then b.derived_status = 'absent'
                                     and b.employee_id not in (select employee_id from excused_absent)
        when 'incomplete'         then b.derived_status in ('partial','pending','missing_checkout')
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
grant execute on function public.get_attendance_day_roster(date, text, text, uuid, uuid, uuid, text, text, integer, integer) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- (3) المسار الإداري: ينشئ طلباً معتمداً ويخصم الرصيد
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- (3a) اعتماد فوري لطلب مع إنهاء الخطوات/نموذج سير العمل (كمسار العارضة 0325)
--      حتى تشتغل تريغرات الخصم والوسم بشكل قياسي دون تكرار منطق.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public._admin_approve_request_immediately(
  p_request_id uuid
)
returns public.requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.requests;
  v_me uuid := public.current_employee_id();
begin
  if p_request_id is null then
    raise exception 'REQUEST_REQUIRED' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.has_any_permission(array[
      'requests.approve',
      'attendance.correction.review',
      'attendance.record.manual_create'
    ])
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select * into v_row from public.requests where id = p_request_id;
  if not found then
    raise exception 'REQUEST_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_row.status <> 'pending' then
    raise exception 'REQUEST_NOT_PENDING' using errcode = '22023';
  end if;

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
        comment = 'اعتماد إداري مباشر من تصحيح يوم الحضور', updated_at = now()
    where request_id = v_row.id and status in ('active','pending');

  update public.workflow_instances
    set status = 'completed', completed_at = now(), updated_at = now()
    where request_id = v_row.id and status = 'running';

  insert into public.request_actions(
    request_id, actor_employee_id, action, from_status, to_status, comment, metadata, created_by)
  values(
    v_row.id, v_me, 'system', 'pending', 'approved',
    'اعتماد إداري مباشر من تصحيح يوم الحضور',
    jsonb_build_object('source', 'attendance_day_editor'), auth.uid());

  perform public.log_audit_event(
    'attendance.day.request.approved', 'workflow', 'warning', 'requests', v_row.id,
    'اعتماد إداري مباشر لطلب يوم حضور',
    v_row.title,
    jsonb_build_object('requestType', v_row.request_type, 'employeeId', v_row.employee_id));

  return v_row;
end;
$$;

revoke execute on function public._admin_approve_request_immediately(uuid) from public, anon;
grant execute on function public._admin_approve_request_immediately(uuid) to service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- (3b) إعادة تعريف set_employee_attendance_day_admin:
--      • p_leave_type جديد (annual/casual/sick/unpaid) للترميز الإداري المباشر.
--      • عند day_type في (leave, absent, mission, convoy, fundraising):
--        يُنشأ طلب (leave_requests أو payload تشغيلي) عبر _submit_request_for
--        ثم يُعتمد مباشرة → reserve على submit، consume + on_leave عند الاعتماد
--        (إجازة) أو present + استثناء (تشغيلي).
--      • عند day_type = work/holiday/rest: سلوك 0266 القديم (override فقط).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.set_employee_attendance_day_admin(
  p_employee_id uuid,
  p_work_date date,
  p_day_type text,
  p_check_in time default null,
  p_check_out time default null,
  p_clear_check_in boolean default false,
  p_clear_check_out boolean default false,
  p_reason text default null,
  p_notes text default null,
  p_leave_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_previous jsonb;
  v_month date := date_trunc('month', p_work_date)::date;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_manager uuid;
  v_req public.requests;
  v_leave_type_id uuid;
  v_affects boolean;
  v_leave_type text;
  v_payload jsonb;
begin
  if p_employee_id is null or p_work_date is null then
    raise exception 'EMPLOYEE_AND_DATE_REQUIRED' using errcode = '22023';
  end if;
  if p_day_type not in ('work','leave','mission','convoy','fundraising','holiday','rest','absent') then
    raise exception 'INVALID_DAY_TYPE' using errcode = '22023';
  end if;
  if length(btrim(coalesce(p_reason, ''))) < 5 then
    raise exception 'REASON_REQUIRED' using errcode = '22023';
  end if;
  if p_clear_check_in and p_check_in is not null then
    raise exception 'CHECK_IN_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if p_clear_check_out and p_check_out is not null then
    raise exception 'CHECK_OUT_CLEAR_CONFLICT' using errcode = '22023';
  end if;
  if not (
    public.current_is_full_access()
    or public.can_access_employee(p_employee_id, 'attendance.correction.review')
    or public.can_access_employee(p_employee_id, 'attendance.record.manual_create')
  ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;
  if exists (
    select 1
    from public.attendance_periods ap
    join public.employees e on e.id = p_employee_id
    left join public.branches b on b.id = e.branch_id
    where ap.period_month = v_month
      and ap.status = 'closed'
      and (ap.branch_id is null or ap.branch_id = e.branch_id)
      and (ap.legal_entity_id is null or ap.legal_entity_id = b.legal_entity_id)
  ) then
    raise exception 'ATTENDANCE_PERIOD_CLOSED' using errcode = '55000';
  end if;

  select to_jsonb(o) into v_previous
  from public.attendance_day_overrides o
  where o.employee_id = p_employee_id and o.work_date = p_work_date;

  insert into public.attendance_day_overrides(
    employee_id, work_date, day_type,
    check_in_override, check_out_override,
    clear_check_in, clear_check_out,
    reason, notes, is_active, created_by, updated_by
  ) values (
    p_employee_id, p_work_date, p_day_type,
    p_check_in, p_check_out,
    coalesce(p_clear_check_in, false), coalesce(p_clear_check_out, false),
    btrim(p_reason), nullif(btrim(coalesce(p_notes, '')), ''), true, auth.uid(), auth.uid()
  )
  on conflict(employee_id, work_date) do update set
    day_type = excluded.day_type,
    check_in_override = excluded.check_in_override,
    check_out_override = excluded.check_out_override,
    clear_check_in = excluded.clear_check_in,
    clear_check_out = excluded.clear_check_out,
    reason = excluded.reason,
    notes = excluded.notes,
    is_active = true,
    updated_by = auth.uid(),
    updated_at = now()
  returning id into v_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- ترميز إداري مباشر → ينشئ طلباً معتمداً (خصم الرصيد للِإجازة/الغياب).
  -- نمنع إنشاء طلب مكرر ليومٍ به طلب معتمد مسبقاً يغطي نفس اليوم.
  -- ─────────────────────────────────────────────────────────────────────────
  if p_day_type in ('leave','absent','mission','convoy','fundraising') then
    if p_day_type in ('leave','absent') then
      -- نوع الإجازة: p_leave_type أو افتراضي حسب الترميز
      v_leave_type := coalesce(nullif(trim(coalesce(p_leave_type, '')), ''), case when p_day_type = 'absent' then 'unpaid' else 'annual' end);
      if v_leave_type = 'emergency' then v_leave_type := 'casual'; end if;
      if v_leave_type not in ('annual','casual','sick','unpaid','weekly_rest_comp') then
        raise exception 'unsupported leave type: %', v_leave_type using errcode = '22023';
      end if;
      select id, affects_balance into v_leave_type_id, v_affects
      from public.leave_types where code = v_leave_type and is_active = true;
      if v_leave_type_id is null then
        raise exception 'leave type is inactive or unknown: %', v_leave_type using errcode = '22023';
      end if;

      if not exists (
        select 1
          from public.leave_requests lr
          join public.requests r on r.id = lr.request_id and r.status = 'approved'
         where lr.employee_id = p_employee_id
           and p_work_date between lr.start_date and lr.end_date
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'leaveType', v_leave_type,
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true);

        v_req := public._submit_request_for(
          p_employee_id,
          'leave',
          null,
          v_manager,
          'تحديد يوم إداري — ' || (case when p_day_type = 'absent' then 'غياب' else 'إجازة' end),
          btrim(p_reason),
          v_payload);

        insert into public.leave_requests(
          request_id, employee_id, leave_type_id, start_date, end_date,
          days_count, duration_unit, created_by)
        values(
          v_req.id, p_employee_id, v_leave_type_id, p_work_date, p_work_date,
          1, 'day', auth.uid());

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    else
      -- مأمورية/قافلة/فاندي: طلب تشغيلي معتمد → تريجر الإعفاء يكتب present + استثناء
      if not exists (
        select 1
          from public.requests r
         where r.employee_id = p_employee_id
           and r.request_type = p_day_type
           and r.status = 'approved'
           and p_work_date between (r.payload->>'startDate')::date
                               and coalesce((r.payload->>'endDate')::date, (r.payload->>'startDate')::date)
      ) then
        v_manager := public.resolve_request_approver(p_employee_id, p_work_date);
        v_payload := jsonb_build_object(
          'startDate', p_work_date,
          'endDate', p_work_date,
          'days', 1,
          'dayMark', true,
          'location', coalesce(nullif(trim(coalesce(p_notes, '')), ''), 'تحديد إداري'));

        v_req := public._submit_request_for(
          p_employee_id,
          p_day_type,
          null,
          v_manager,
          'تحديد يوم إداري — ' || public.request_type_label(p_day_type),
          btrim(p_reason),
          v_payload);

        v_req := public._admin_approve_request_immediately(v_req.id);
      end if;
    end if;
  end if;

  perform public.log_audit_event(
    'attendance.day.override.saved', 'workflow', 'warning',
    'attendance_day_overrides', v_id,
    'تعديل إداري ليوم حضور', p_reason,
    jsonb_build_object(
      'employeeId', p_employee_id,
      'workDate', p_work_date,
      'previous', v_previous,
      'dayType', p_day_type,
      'leaveType', v_leave_type,
      'requestId', case when v_req.id is null then null else v_req.id end,
      'checkIn', p_check_in,
      'checkOut', p_check_out,
      'clearCheckIn', coalesce(p_clear_check_in, false),
      'clearCheckOut', coalesce(p_clear_check_out, false)
    )
  );

  return jsonb_build_object('ok', true, 'id', v_id, 'employeeId', p_employee_id, 'workDate', p_work_date);
end
$$;

revoke all on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text)
  from public, anon;
grant execute on function public.set_employee_attendance_day_admin(uuid,date,text,time,time,boolean,boolean,text,text,text)
  to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
