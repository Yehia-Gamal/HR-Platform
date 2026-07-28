-- 0199: إصلاح get_attendance_today_overview — أعمدة غير موجودة
-- الأخطاء المصلحة:
--   1. employees.is_executive → ليس عموداً — نستخدم استعلام أدوار
--   2. attendance_events.event_date → event_at::date
--   3. attendance_events.is_late → late_minutes > 0
--   4. event_type = 'check_in' → 'CHECK_IN' (أحرف كبيرة)
--   5. leave_requests.status → الحالة في جدول requests عبر request_id
--   6. work_assignments.status = 'active' → أحرف كبيرة + start_at/end_at

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
    'lastUpdatedAt', now()
  );
end;
$fn$;

-- الصلاحيات (لم تتغير)
grant execute on function public.get_attendance_today_overview(date) to authenticated;
