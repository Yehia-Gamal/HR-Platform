-- Migration 0212: Sync get_my_attendance_state with 0210 biometric relaxation
--
-- Problem: Migration 0210 removed the `biometric_available` filter from
-- punch_attendance_local_biometric_v1, allowing devices with only PIN/pattern
-- screen lock. But get_my_attendance_state() still checks biometric_available
-- when counting active local devices, causing the UI to show "غير مفعلة"
-- even though the punch function would accept the device.
--
-- Fix:
--   ① Remove `biometric_available` filter from v_local_devices count.
--   ② Remove `biometric_available` filter from pending-device status check.
--   ③ Both now match the relaxed policy in 0210: device-lock (PIN/pattern)
--      is accepted as a valid local auth method.

begin;

create or replace function public.get_my_attendance_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_me uuid := public.current_employee_id();
  v_is_executive boolean;
  v_active boolean;
  v_local_devices integer := 0;
  v_local_device_status text;  -- 'active' | 'pending' | null
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
begin
  if v_me is null then
    raise exception 'no employee linked to current user' using errcode = '42501';
  end if;

  select e.is_active and not coalesce(e.is_deleted, false), exists(
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.slug in ('executive','executive-director')
      and ur.effective_from <= now()
      and (ur.effective_to is null or ur.effective_to > now())
  ) into v_active, v_is_executive
  from public.employees e where e.id = v_me;

  -- 0212: Removed `and md.biometric_available` — devices with only
  -- PIN/pattern screen lock are now accepted, matching 0210.
  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id=auth.uid() and md.employee_id=v_me
    and md.platform in ('android','ios') and md.status='active'
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

  -- Determine device status for the mobile UI
  if v_local_devices > 0 then
    v_local_device_status := 'active';
  else
    -- Check if any device is pending approval (employee_devices or managed_devices)
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
      -- 0212: Removed `and md.biometric_available` — matching 0210.
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'pending'
      limit 1;
      if found then
        v_local_device_status := 'pending';
      end if;
    end if;
  end if;

  select count(*) into v_passkeys
  from public.passkey_credentials p
  where p.employee_id=v_me and p.user_id=auth.uid()
    and p.status='active' and p.trusted;

  select * into v_last from public.attendance_events
  where employee_id=v_me
    and (event_at at time zone 'Africa/Cairo')::date=v_today
  order by event_at desc limit 1;
  select status into v_today_status from public.attendance_daily
  where employee_id=v_me and work_date=v_today;
  if v_last.id is not null and v_last.event_type='CHECK_IN' then
    v_suggested := 'CHECK_OUT';
  end if;

  return jsonb_build_object(
    'employeeId',v_me,
    'attendanceRequired',v_active and not v_is_executive,
    'selfPunchEnabled',v_active and not v_is_executive,
    'activeLocalDevices',v_local_devices,
    'hasActiveLocalDevice',v_local_devices>0,
    'localDeviceStatus',v_local_device_status,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    'canPunch',v_active and not v_is_executive and v_local_devices>0,
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state() from public, anon;
grant execute on function public.get_my_attendance_state() to authenticated;

comment on function public.get_my_attendance_state is
  '0212: Removed biometric_available filter — synced with 0210 device-lock fallback.';

commit;
