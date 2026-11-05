-- ============================================================================
-- Migration 0729: Overload Admin Auto Grace Checkout, Penalty Annulment & Workflow SLA Alignment
-- ============================================================================

begin;

-- 1. Align default workflow_steps SLAs with business hours standard (24-48h instead of 2h)
update public.workflow_steps
   set sla_hours = 24,
       escalate_after_hours = 48
 where sla_hours < 24
    or escalate_after_hours < 24;

-- 2. Enhanced admin_auto_grace_checkout with automatic penalty waiving & suspension lift
CREATE OR REPLACE FUNCTION public.admin_auto_grace_checkout(
  p_attendance_daily_id uuid,
  p_note text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_rec record;
  v_shift public.shifts%rowtype;
  v_checkout_time timestamptz;
  v_tz text := 'Africa/Cairo';
  v_work_minutes integer;
  v_emp_name text;
begin
  if auth.uid() is not null
     and not (
       public.current_is_full_access()
       or public.current_has_active_role(array['admin', 'super-admin', 'hr-manager', 'executive', 'operations-manager-1'])
     ) then
    raise exception 'FORBIDDEN' using errcode = '42501';
  end if;

  select ad.*, e.full_name_ar into v_rec
    from public.attendance_daily ad
    join public.employees e on e.id = ad.employee_id
   where ad.id = p_attendance_daily_id
     for update;

  if not found then
    raise exception 'سجل الحضور غير موجود' using errcode = 'P0002';
  end if;

  if v_rec.first_check_in is null then
    raise exception 'لا يمكن اعتماد انصراف لموظف لم يسجل حضوراً أصلاً' using errcode = '22023';
  end if;

  -- العثور على وردية اليوم للموظف
  if v_rec.shift_id is not null then
    select * into v_shift from public.shifts where id = v_rec.shift_id;
  end if;

  if v_shift.id is null then
    select s.* into v_shift
      from public.shift_assignments sa
      join public.shifts s on s.id = sa.shift_id
     where sa.employee_id = v_rec.employee_id
       and sa.is_active = true
       and sa.effective_from <= v_rec.work_date
       and (sa.effective_to is null or sa.effective_to >= v_rec.work_date)
     order by sa.effective_from desc
     limit 1;
  end if;

  if v_shift.id is null then
    select * into v_shift from public.shifts where code = 'OFFICIAL' and is_active limit 1;
  end if;

  -- تحديد موعد الانصراف في نهاية الوردية الرسمية
  v_checkout_time := (
    v_rec.work_date
    + case when coalesce(v_shift.crosses_midnight, false) then 1 else 0 end
    + coalesce(v_shift.end_time, '18:00'::time)
  ) at time zone v_tz;

  v_work_minutes := floor(extract(epoch from (v_checkout_time - v_rec.first_check_in)) / 60)::integer;

  -- تحديث سجل الحضور
  update public.attendance_daily
     set last_check_out = v_checkout_time,
         status = 'present',
         work_minutes = greatest(coalesce(v_work_minutes, 480), 0),
         is_finalized = true,
         updated_at = now()
   where id = p_attendance_daily_id;

  -- حل أي استثناء معلق خاص بعدم الانصراف لهذا اليوم
  update public.attendance_exceptions
     set status = 'resolved',
         resolution_notes = 'اعتماد تلقائي ذكي لنهاية الوردية الرسمية' || case when p_note is not null then ': ' || p_note else '' end,
         resolved_at = now()
   where attendance_daily_id = p_attendance_daily_id
     and kind in ('missing_check_out', 'incomplete')
     and status in ('open', 'approved');

  -- إسقاط أي غرامة فورية خاصة بعدم الانصراف أو الحضور لهذا التاريخ
  update public.instant_attendance_penalties
     set status = 'waived',
         notes = coalesce(notes, '') || ' — أُلغيت لاعتماد انصراف نهاية الوردية الرسمية إدارياً',
         updated_at = now()
   where employee_id = v_rec.employee_id
     and penalty_date = v_rec.work_date
     and status in ('unpaid', 'pending', 'escalated');

  -- رفع الإيقاف عن الموظف فوراً إذا كان حسابه معلقاً
  perform public.evaluate_and_lift_suspension(v_rec.employee_id);

  perform public.log_audit_event(
    'attendance.auto_grace_checkout', 'attendance', 'medium',
    'attendance_daily', p_attendance_daily_id,
    'اعتماد انصراف نهاية الوردية الرسمية للموظف ' || coalesce(v_rec.full_name_ar, ''),
    p_note,
    jsonb_build_object(
      'employeeId', v_rec.employee_id,
      'workDate', v_rec.work_date,
      'checkIn', v_rec.first_check_in,
      'checkOut', v_checkout_time,
      'workMinutes', v_work_minutes
    )
  );

  return jsonb_build_object(
    'success', true,
    'checkoutTime', v_checkout_time,
    'workMinutes', v_work_minutes,
    'message', 'تم اعتماد انصراف الموظف بنهاية ورديته الرسمية وإلغاء الغرامة بنجاح.'
  );
end;
$function$;

-- 3. Overloaded version accepting (employee_id, work_date, note)
CREATE OR REPLACE FUNCTION public.admin_auto_grace_checkout(
  p_employee_id uuid,
  p_work_date date,
  p_note text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_daily_id uuid;
begin
  select id into v_daily_id
    from public.attendance_daily
   where employee_id = p_employee_id
     and work_date = p_work_date;

  if v_daily_id is null then
    raise exception 'لا يوجد سجل حضور للموظف في هذا التاريخ' using errcode = 'P0002';
  end if;

  return public.admin_auto_grace_checkout(v_daily_id, p_note);
end;
$function$;

grant execute on function public.admin_auto_grace_checkout(uuid, text) to authenticated, service_role;
grant execute on function public.admin_auto_grace_checkout(uuid, date, text) to authenticated, service_role;

commit;
