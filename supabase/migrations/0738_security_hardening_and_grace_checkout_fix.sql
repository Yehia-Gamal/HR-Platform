-- ============================================================================
-- Staged Migration (Pending Owner Approval): Security Hardening & Grace Checkout Fix
-- Suggested version after 0737: 0738_security_hardening_and_grace_checkout_fix.sql
--
-- Fixes confirmed defects:
-- 1. Revokes accidental `authenticated` EXECUTE grants on internal SECURITY DEFINER
--    helpers that take arbitrary employee_id or perform global cron jobs without
--    per-caller ownership validation:
--      - public.record_attendance_local_biometric(...)
--      - public._submit_request_for(...)
--      - public.auto_waive_penalty_if_completed_eight_hours(...)
--      - public.generate_punch_reminders(...)
-- 2. Fixes public.admin_auto_grace_checkout(uuid, text) (from 0736):
--      - Uses valid status 'cancelled' + cancelled_reason instead of invalid 'waived'
--        (which failed instant_attendance_penalties_status_check with SQLSTATE 23514).
--      - Checks whether any other doubled/suspended penalties exist before lifting
--        employee suspension instead of unconditionally resetting all dates.
--      - Revokes PUBLIC/anon EXECUTE on both overloads of admin_auto_grace_checkout.
-- ============================================================================

begin;

-- ─── 1) Lock internal SECURITY DEFINER helpers to service_role only ───────────
revoke all on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) from public, anon, authenticated;
grant execute on function public.record_attendance_local_biometric(uuid, text, double precision, double precision, double precision, boolean) to service_role;

revoke all on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public._submit_request_for(uuid, text, uuid, uuid, text, text, jsonb) to service_role;

revoke all on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) from public, anon, authenticated;
grant execute on function public.auto_waive_penalty_if_completed_eight_hours(uuid, date) to service_role;

revoke all on function public.generate_punch_reminders(integer) from public, anon, authenticated;
grant execute on function public.generate_punch_reminders(integer) to service_role;

-- ─── 2) Fix admin_auto_grace_checkout status='cancelled' & scoped unsuspension ─
create or replace function public.admin_auto_grace_checkout(
  p_attendance_daily_id uuid,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_rec record;
  v_shift public.shifts%rowtype;
  v_checkout_time timestamptz;
  v_tz text := 'Africa/Cairo';
  v_work_minutes integer;
  v_cancelled_count integer := 0;
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

  v_checkout_time := (
    v_rec.work_date
    + case when coalesce(v_shift.crosses_midnight, false) then 1 else 0 end
    + coalesce(v_shift.end_time, '18:00'::time)
  ) at time zone v_tz;

  v_work_minutes := floor(extract(epoch from (v_checkout_time - v_rec.first_check_in)) / 60)::integer;

  update public.attendance_daily
     set last_check_out = v_checkout_time,
         status = 'present',
         work_minutes = greatest(coalesce(v_work_minutes, 480), 0),
         is_finalized = true,
         updated_at = now()
   where id = p_attendance_daily_id;

  update public.attendance_exceptions
     set status = 'resolved',
         description = coalesce(description, '') || ' [اعتماد تلقائي ذكي لنهاية الوردية الرسمية' || case when p_note is not null then ': ' || p_note else '' end || ']',
         reviewed_at = now(),
         reviewed_by = public.current_employee_id()
   where attendance_daily_id = p_attendance_daily_id
     and kind in ('missing_check_out', 'incomplete')
     and status in ('open', 'approved');

  -- Use valid status 'cancelled' per instant_attendance_penalties_status_check
  with cancelled as (
    update public.instant_attendance_penalties
       set status = 'cancelled',
           cancelled_reason = 'أُلغيت لاعتماد انصراف نهاية الوردية الرسمية إدارياً' || case when p_note is not null and btrim(p_note) <> '' then ': ' || btrim(p_note) else '' end,
           cancelled_at = now(),
           cancelled_by = public.current_employee_id(),
           notes = coalesce(notes || ' | ', '') || 'أُلغيت لاعتماد انصراف نهاية الوردية الرسمية إدارياً',
           updated_at = now()
     where employee_id = v_rec.employee_id
       and work_date = v_rec.work_date
       and status in ('pending_payment', 'doubled', 'suspended')
    returning id
  )
  select count(*) into v_cancelled_count from cancelled;

  -- Only reactivate employee if no other unpaid doubled/suspended penalties remain
  if not exists (
    select 1 from public.instant_attendance_penalties
     where employee_id = v_rec.employee_id
       and status in ('doubled', 'suspended')
  ) then
    update public.employees
       set is_active = true,
           status = 'active',
           updated_at = now()
     where id = v_rec.employee_id
       and (status = 'suspended' or not is_active);

    update public.profiles
       set status = 'active',
           updated_at = now()
     where employee_id = v_rec.employee_id
       and status = 'suspended';
  end if;

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
      'workMinutes', v_work_minutes,
      'cancelledPenalties', v_cancelled_count
    )
  );

  return jsonb_build_object(
    'success', true,
    'checkoutTime', v_checkout_time,
    'workMinutes', v_work_minutes,
    'cancelledPenalties', v_cancelled_count,
    'message', 'تم اعتماد انصراف الموظف بنهاية ورديته الرسمية وإلغاء الغرامة بنجاح.'
  );
end;
$function$;

revoke all on function public.admin_auto_grace_checkout(uuid, text) from public, anon;
grant execute on function public.admin_auto_grace_checkout(uuid, text) to authenticated, service_role;

revoke all on function public.admin_auto_grace_checkout(uuid, date, text) from public, anon;
grant execute on function public.admin_auto_grace_checkout(uuid, date, text) to authenticated, service_role;

commit;
