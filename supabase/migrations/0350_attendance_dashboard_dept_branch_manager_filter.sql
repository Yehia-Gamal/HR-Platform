-- =====================================================================
-- 0350: فلاتر القسم/الفرع/المدير على لوحة الحضور (get_attendance_dashboard)
-- =====================================================================
-- السياق: كانت get_attendance_dashboard تقبل p_date فقط وترصد كل الموظفين
-- النشطين. نحتاج القدرة على تصغير اللوحة إلى قسم/فرع/مدير محدّد (تمشياً مع
-- rpc التفصيل 0294 الذي يقبل هذه الفلاتر أصلاً).
--
-- التغيير: توسيع الدالة بثلاثة بارامترات اختيارية (uuid default null) وتوسيع
-- نطاق كل CTE (daily / visible_events / approved_leaves /
-- location_requests_day) ليلتحق بـ visible_employees المفلترة. متوافق تماماً
-- عكسياً: النداءات الحالية بـ p_date فقط تعمل كما السابق (الفلاتر null = لا
-- تصغير). نُسقط الدالة القديمة(date) ونُنشئ المعادلة الموسّعة.
--
-- إشارة: لوحة الحركة الحية الحالية عاجزة عن تصغير نطاقها، وهذا تعزيز مهم
-- لمراقبي HR/المديرين. لا يكسر أي grant قائم لأن الدالة القديمة تُسقط صراحة.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) إسقاط الدالة القديمة (p_date فقط) حتى لا يحدث overload ضار
-- ---------------------------------------------------------------------
drop function if exists public.get_attendance_dashboard(date);

-- ---------------------------------------------------------------------
-- 2) إعادة إنشائها موسّعة بالفلاتر + توسيع نطاق CTEs إليها
-- ---------------------------------------------------------------------
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
    select e.id
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

grant execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) to authenticated;
