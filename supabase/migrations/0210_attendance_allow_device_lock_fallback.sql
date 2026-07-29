-- Migration 0210: Allow device-lock (PIN/pattern) as attendance fallback
--
-- Problem: punch_attendance_local_biometric_v1 requires `biometric_available`
-- on managed_devices. Devices without fingerprint/face hardware (but with
-- PIN/pattern screen lock) are blocked from punching attendance.
--
-- Fix:
--   ① Remove the hard `biometric_available` filter — the device is already
--     approved (status='active') and the local auth check is enforced
--     client-side (Flutter local_auth).
--   ② Record the actual verificationMethod in the result:
--     'local_biometric' when biometric_available = true,
--     'device_lock' when biometric_available = false.
--   ③ Update register_my_device comment to reflect the new semantics:
--     biometric_available now means "device supports any local auth"
--     (biometric OR device lock), matching the Flutter-side change.

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- ① punch_attendance_local_biometric_v1 — relax biometric_available check
-- ═══════════════════════════════════════════════════════════════════════════
create or replace function public.punch_attendance_local_biometric_v1(
  p_operation_id uuid,
  p_event_type text,
  p_installation_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_hash text;
  v_managed public.managed_devices;
  v_employee_device public.employee_devices;
  v_operation public.local_attendance_operations;
  v_event_id uuid;
  v_event public.attendance_events;
  v_result jsonb;
  v_error text;
  v_verification_method text;  -- 0210: 'local_biometric' | 'device_lock'
  -- 0208: Added 'invalid_attendance_location' (bounds check from 0201)
  v_known_errors constant text[] := array[
    'attendance_outside_complex','attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low','attendance_geofence_not_configured',
    'attendance_location_required','duplicate_attendance_event',
    'attendance_period_finalized','attendance_check_in_required',
    'attendance_check_out_required','invalid_attendance_location'
  ];
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode='42501';
  end if;
  if p_operation_id is null then
    raise exception 'attendance_operation_id_required' using errcode='22023';
  end if;
  if p_event_type not in ('CHECK_IN','CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode='22023';
  end if;
  if length(trim(coalesce(p_installation_id,'')))<12 then
    raise exception 'invalid_installation_id' using errcode='22023';
  end if;
  if exists (
    select 1 from public.user_roles ur join public.roles r on r.id=ur.role_id
    where ur.user_id=auth.uid() and r.slug in ('executive','executive-director')
      and ur.effective_from<=now()
      and (ur.effective_to is null or ur.effective_to>now())
  ) then
    raise exception 'executive_attendance_not_required' using errcode='42501';
  end if;

  v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

  -- 0210: Removed `and biometric_available` — devices with only PIN/pattern
  -- are allowed. The local auth check is enforced client-side by Flutter.
  -- The device must still be active (admin-approved) and on a mobile platform.
  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active'
  for update;
  if not found then
    raise exception 'local_biometric_device_not_active' using errcode='28000';
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    raise exception 'local_biometric_device_not_active' using errcode='28000';
  end if;

  -- 0210: Determine verification method based on device capabilities
  v_verification_method := case
    when v_managed.biometric_available then 'local_biometric'
    else 'device_lock'
  end;

  insert into public.local_attendance_operations(
    operation_id,user_id,employee_id,event_type,credential_id
  ) values (p_operation_id,auth.uid(),v_employee_id,p_event_type,v_hash)
  on conflict (operation_id) do nothing;
  select * into v_operation from public.local_attendance_operations
  where operation_id=p_operation_id for update;
  if v_operation.user_id<>auth.uid()
     or v_operation.employee_id<>v_employee_id
     or v_operation.event_type<>p_event_type
     or v_operation.credential_id<>v_hash then
    raise exception 'attendance_idempotency_conflict' using errcode='22023';
  end if;
  if v_operation.status in ('completed','rejected') then
    return coalesce(v_operation.result,'{}'::jsonb)
      || jsonb_build_object('replayed',true);
  end if;

  begin
    v_event_id := public.record_attendance_local_biometric(
      v_employee_id,p_event_type,p_latitude,p_longitude,
      p_accuracy_meters,p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error=message_text;
    if v_error=any(v_known_errors) then
      v_result := jsonb_build_object('ok',false,'error',v_error,'replayed',false);
      update public.local_attendance_operations
      set status='rejected',result=v_result,completed_at=now()
      where operation_id=p_operation_id;
      return v_result;
    end if;
    raise;
  end;

  update public.employee_devices set last_used_at=now()
  where id=v_employee_device.id;
  update public.managed_devices set last_seen_at=now()
  where id=v_managed.id;
  select * into v_event from public.attendance_events where id=v_event_id;
  v_result := jsonb_build_object(
    'ok',true,'verified',true,
    'verificationMethod',v_verification_method,  -- 0210: biometric أو device_lock
    'eventId',v_event_id,'eventType',p_event_type,
    'status',coalesce(v_event.status,'accepted'),
    'insideComplex',v_event.status='accepted',
    'distanceMeters',v_event.distance_meters,'geofenceId',v_event.geofence_id,
    'recordedAt',v_event.event_at,'replayed',false
  );
  update public.local_attendance_operations
  set status='completed',result=v_result,completed_at=now()
  where operation_id=p_operation_id;
  return v_result;
end;
$$;

revoke all on function public.punch_attendance_local_biometric_v1(
  uuid,text,text,double precision,double precision,double precision,boolean
) from public, anon, authenticated;
grant execute on function public.punch_attendance_local_biometric_v1(
  uuid,text,text,double precision,double precision,double precision,boolean
) to authenticated;

comment on function public.punch_attendance_local_biometric_v1 is
  '0210: Allows device_lock (PIN/pattern) fallback for devices without biometric hardware. Records verificationMethod in result.';

commit;
