-- =====================================================================
-- 0589: لوحتا الحضور اليومي من المصدر الموحّد (attendance_day_facts)
--
-- قبلها اختلفت الشاشتان مع الحقيقة ومع بعضهما لليوم نفسه (متوقع 26 مقابل 31
-- مقابل 29 فعلياً): المأموريات من الطلبات تظهر «لم يحضر»، ومن لم يسجل انصرافاً
-- يختفي من «حاضر»، والإجازات والمأموريات في مقام نسبة الحضور.
-- =====================================================================

begin;

CREATE OR REPLACE FUNCTION public.get_attendance_today_overview(p_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager'])
    or public.has_permission('attendance.record.read')
    or public.has_permission('people.employee.read')
    -- 0589: current_user داخل SECURITY DEFINER = المالك (postgres) دائماً فكان هذا الشرط يتجاوز الفحص لكل المستخدمين
    or auth.role() = 'service_role'
    or auth.role() is null
  ) then
    raise exception 'غير مصرح لك' using errcode = '42501';
  end if;

  -- 0589: من حقائق يوم الحضور (attendance_day_facts) — كانت المأموريات/القوافل من
  -- طلبات requests لا تُحسب (work_assignments فقط) فيظهر أصحابها «لم يحضر»، والإجازة
  -- المقدَّمة لا تُستبعد، وتاريخ البصمة بتوقيت UTC.
  select
    count(*),
    count(*) filter (where f.is_workday and f.leave_like),
    count(*) filter (where f.offsite and not f.checked_in),
    count(*) filter (where f.checked_in),
    count(*) filter (where f.late_minutes > 0),
    count(*) filter (where f.is_workday and not f.leave_like and not (f.offsite and not f.checked_in))
  into v_total_active, v_on_leave, v_on_assignment, v_present, v_late, v_expected
  from public.attendance_day_facts(p_date, p_date) f
  where not f.is_exempt;

  v_not_checked_in := greatest(0, coalesce(v_expected, 0) - coalesce(v_present, 0));
  v_absent := v_not_checked_in;

  return jsonb_build_object(
    'date', p_date,
    'totalActive', coalesce(v_total_active, 0),
    'expected', coalesce(v_expected, 0),
    'expectedToday', coalesce(v_expected, 0),
    'present', coalesce(v_present, 0),
    'late', coalesce(v_late, 0),
    'onLeave', coalesce(v_on_leave, 0),
    'onAssignment', coalesce(v_on_assignment, 0),
    'notCheckedIn', coalesce(v_not_checked_in, 0),
    'absent', coalesce(v_absent, 0),
    'isFriday', v_is_friday,
    'isWeekend', v_is_friday,
    'lastUpdatedAt', now(),
    'generatedAt', now()
  );
end;
$function$;

create or replace function public.get_attendance_dashboard(
  p_date date default null,
  p_department_id uuid default null,
  p_branch_id uuid default null,
  p_manager_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  -- 0589: من حقائق يوم الحضور. كانت «حاضر» تُسقط من لم يسجل انصرافاً (لا حاضر
  -- ولا غائب)، والمقام يشمل الإجازات والمأموريات، والمأموريات من work_assignments
  -- فقط. كانت الدالة SECURITY INVOKER تعتمد RLS للنطاق؛ الآن النطاق صريح بنفس فحص
  -- الصلاحية المعتمد (can_access_employee) لأن مصدر الحقائق SECURITY DEFINER.
  with params as (
    select coalesce(p_date, (now() at time zone 'Africa/Cairo')::date) as work_date
  ), visible_employees as (
    select e.id
      from public.employees e
     where e.is_active = true
       and coalesce(e.is_deleted, false) = false
       and not public.is_employee_attendance_exempt(e.id)
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
       and (public.current_is_full_access() or public.can_access_employee(e.id, 'attendance.record.read'))
  ), f as (
    select f.*
      from params p
      cross join lateral public.attendance_day_facts(p.work_date, p.work_date) f
      join visible_employees ve on ve.id = f.employee_id
     where not f.is_exempt
  ), visible_events as (
    select e.*
      from public.attendance_events e
      join params p on (e.event_at at time zone 'Africa/Cairo')::date = p.work_date
      join visible_employees ve on ve.id = e.employee_id
  ), pending_excuse as (
    select distinct r.employee_id
      from public.requests r
      join params p on p.work_date between public.try_cast_date(r.payload->>'startDate')
                                       and coalesce(public.try_cast_date(r.payload->>'endDate'), public.try_cast_date(r.payload->>'startDate'))
      join visible_employees ve on ve.id = r.employee_id
     where r.status = 'pending'
       and r.request_type in ('leave', 'mission', 'convoy', 'fundraising')
  )
  select jsonb_build_object(
    'date', (select work_date from params),
    'scheduled', (select count(*) from f),
    'totalEmployees', (select count(*) from f),
    'expected', (select count(*) from f where is_workday and not leave_like and not (offsite and not checked_in)),
    'present', (select count(*) from f where checked_in),
    'presentCount', (select count(*) from f where checked_in),
    'late', (select count(*) from f where late_minutes > 0),
    'lateCount', (select count(*) from f where late_minutes > 0),
    'earlyLeave', (select count(*) from public.attendance_daily d join params p on p.work_date = d.work_date
                    join visible_employees ve on ve.id = d.employee_id where coalesce(d.early_leave_minutes, 0) > 0),
    'onLeave', (select count(*) from f where is_workday and not checked_in and (leave_like or offsite)),
    'excusedCount', (select count(*) from f where is_workday and not checked_in and (leave_like or offsite)),
    'pendingCount', (select count(*) from pending_excuse),
    'absent', (select count(*) from f where is_workday and not leave_like and not offsite and not checked_in),
    'unexcusedAbsent', (select count(*) from f where is_workday and not leave_like and not offsite and not checked_in),
    'isWeekend', ((select extract(isodow from work_date) from params) = 5),
    'firstCheckIn', (select min(e.event_at) filter (where e.event_type = 'CHECK_IN') from visible_events e),
    'lastCheckOut', (select max(e.event_at) filter (where e.event_type = 'CHECK_OUT') from visible_events e)
  );
$fn$;
revoke execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) from public, anon;
grant execute on function public.get_attendance_dashboard(date, uuid, uuid, uuid) to authenticated, service_role;

-- ─── ثغرات current_user داخل SECURITY DEFINER ─────────────────────────
-- (موظف عادي غيّر حالة حسابه بنفسه — رفع إيقافه — وقرأ طلبات إجازات الجميع)
CREATE OR REPLACE FUNCTION public.get_leave_requests_admin(p_year integer DEFAULT NULL::integer, p_status text DEFAULT NULL::text, p_leave_type text DEFAULT NULL::text, p_employee_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_year  integer;
  v_total bigint;
  v_rows  jsonb;
begin
  if not (
    public.current_is_full_access()
    or public.current_has_active_role(array['admin','super-admin','executive','executive-director','general-manager','hr-manager','operations-manager-1'])
    or public.has_permission('requests.leave.balance.read')
    or public.has_permission('requests.request.read')
    or public.has_permission('requests.request.approve')
    or public.has_permission('requests.leave.policy.manage')
    -- 0589: current_user داخل SECURITY DEFINER = المالك (postgres) دائماً فكان هذا الشرط يتجاوز الفحص لكل المستخدمين
    or auth.role() = 'service_role'
    or auth.role() is null
  ) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;

  v_year := coalesce(p_year, extract(year from now() at time zone 'Africa/Cairo')::integer);

  -- العد الكلي قبل الـ pagination
  select count(*)
    into v_total
    from public.leave_requests lr
    join public.requests r on r.id = lr.request_id
    join public.employees e on e.id = lr.employee_id
     and coalesce(e.is_deleted, false) = false
    join public.leave_types lt on lt.id = lr.leave_type_id
   where extract(year from lr.start_date)::integer = v_year
     and (p_status      is null or r.status = p_status)
     and (p_leave_type  is null or lt.code  = p_leave_type)
     and (p_employee_id is null or e.id     = p_employee_id)
     -- 0589: دور employee يملك requests.request.read (لطلباته) فكانت تُعاد إجازات الجميع
     and (public.current_is_full_access() or public.can_access_employee(e.id, 'requests.request.read'));

  -- جلب الصفحة المطلوبة
  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
        'requestId',     r.id,
        'requestNumber', r.request_number,
        'status',        r.status,
        'createdAt',     r.created_at,
        'employeeId',    e.id,
        'employeeCode',  e.employee_code,
        'employeeName',  coalesce(e.full_name_ar, e.full_name_en),
        'leaveTypeId',   lt.id,
        'leaveTypeCode', lt.code,
        'leaveTypeName', lt.name_ar,
        'isPaid',        lt.is_paid,
        'startDate',     lr.start_date,
        'endDate',       lr.end_date,
        'daysCount',     lr.days_count,
        'hoursCount',    lr.hours_count,
        'durationUnit',  coalesce(lr.duration_unit, 'day'),
        'isHalfDay',     coalesce(lr.is_half_day, false),
        'reason',        r.reason,
        'handoverNotes', lr.handover_notes,
        'attachmentUrl', lr.attachment_url
      ) as row_data,
      r.created_at
        from public.leave_requests lr
        join public.requests r on r.id = lr.request_id
        join public.employees e on e.id = lr.employee_id
         and coalesce(e.is_deleted, false) = false
        join public.leave_types lt on lt.id = lr.leave_type_id
       where extract(year from lr.start_date)::integer = v_year
         and (p_status      is null or r.status = p_status)
         and (p_leave_type  is null or lt.code  = p_leave_type)
         and (p_employee_id is null or e.id     = p_employee_id)
     -- 0589: دور employee يملك requests.request.read (لطلباته) فكانت تُعاد إجازات الجميع
     and (public.current_is_full_access() or public.can_access_employee(e.id, 'requests.request.read'))
       order by r.created_at desc
       limit p_limit offset p_offset
    ) sub;

  return jsonb_build_object('total', v_total, 'rows', v_rows);
end;
$function$;

CREATE OR REPLACE FUNCTION public.tg_profiles_protect_sensitive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_self_activation boolean;
begin
  -- السياقات الموثوقة: service_role أو كرون النظام (postgres/supabase_admin) أو ذوو الصلاحية الكاملة
  if auth.role() = 'service_role'
     -- 0589: current_user داخل SECURITY DEFINER = المالك (postgres) دائماً فكان هذا الشرط يتجاوز الفحص لكل المستخدمين
     -- بلا JWT إطلاقاً (كرون/migrations/اتصال مباشر) = سياق داخلي؛ anon وauthenticated ليسا كذلك
     or auth.role() is null
     or public.current_is_full_access()
     or public.has_permission('profiles.manage') then
    return new;
  end if;

  -- الحقول الأكثر حساسية محظورة على أي مستخدم غير مخوّل مهما كان.
  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'غير مصرح بتغيير الدور الأساسي' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'غير مصرح بتغيير معرّف الموظف' using errcode = '42501';
  end if;

  -- التفعيل الذاتي: الموظف يفعّل ملفه بنفسه بعد أول ضبط كلمة مرور
  v_self_activation :=
       new.id = auth.uid()
       and old.status in ('pending', 'invited', 'onboarding', 'draft')
       and new.status = 'active'
       and new.temporary_password = false;

  if new.status is distinct from old.status and not v_self_activation then
    raise exception 'غير مصرح لك بتغيير الحالة' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password and not v_self_activation then
    raise exception 'غير مصرح بتغيير كلمة المرور المؤقتة' using errcode = '42501';
  end if;

  return new;
end;
$function$;

-- ─── مطابقة التأخير المخزَّن مع القاعدة الحالية (الورديات المرنة 0588) ────
-- الكشف والتقارير تحسب بالقاعدة الحالية فوراً؛ المخزَّن (لوحة الشرف، KPI، قوائم
-- الإدارة) كان بقاعدة 10:00 القديمة → 156 يوماً مختلفاً. دون تشغيل أي تريجر.
set local session_replication_role = replica;

with calc as (
  select ad.id,
         public.attendance_policy_late_minutes(
           ad.employee_id, ad.work_date,
           case
             when o.id is not null and o.clear_check_in then null
             when o.id is not null and o.check_in_override is not null
               then ((ad.work_date + o.check_in_override)::timestamp at time zone 'Africa/Cairo')
             else ad.first_check_in
           end,
           ad.shift_id) as late
  from public.attendance_daily ad
  left join public.attendance_day_overrides o
    on o.employee_id = ad.employee_id and o.work_date = ad.work_date and o.is_active
  where ad.first_check_in is not null or o.check_in_override is not null
)
update public.attendance_daily ad
   set late_minutes = c.late,
       status = case
         when ad.status = 'present' and c.late > 0 then 'late'
         when ad.status = 'late' and c.late = 0 then 'present'
         else ad.status end
  from calc c
 where c.id = ad.id
   and (ad.late_minutes is distinct from c.late
        or (ad.status = 'present' and c.late > 0)
        or (ad.status = 'late' and c.late = 0));

with first_in as (
  select ae.id, ae.employee_id, ae.event_at,
         (ae.event_at at time zone 'Africa/Cairo')::date as work_date,
         row_number() over (partition by ae.employee_id, (ae.event_at at time zone 'Africa/Cairo')::date order by ae.event_at) as rn
  from public.attendance_events ae
  where ae.event_type = 'CHECK_IN' and ae.status in ('accepted', 'adjusted')
), calc as (
  select id, case when rn = 1 then public.attendance_policy_late_minutes(employee_id, work_date, event_at, null) else 0 end as late
  from first_in
)
update public.attendance_events ae set late_minutes = c.late
  from calc c where c.id = ae.id and ae.late_minutes is distinct from c.late;

set local session_replication_role = origin;

commit;
