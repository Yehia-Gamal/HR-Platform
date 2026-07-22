-- 0095: Security hardening fixes from APK audit.
--
-- 1. Explicit table-level REVOKE on employee_devices for defense-in-depth
-- 2. Fix upsert_my_push_token revoke pattern (return type stays void to match existing)
-- 3. Add accuracy range validation to punch_attendance_local

-- 1. Explicit REVOKE on employee_devices (defense-in-depth consistency)
revoke all on table public.employee_devices from public, anon, authenticated;

-- 2. Fix upsert_my_push_token revoke pattern (keep return type void to match existing)
create or replace function public.upsert_my_push_token(
  p_fcm_token text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_token text := trim(p_fcm_token);
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if length(v_token) < 16 then
    raise exception 'token_too_short' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid_platform' using errcode = '22023';
  end if;

  insert into public.push_subscriptions(user_id, fcm_token, platform, is_active, last_seen_at)
  values (v_user_id, v_token, p_platform, true, now())
  on conflict (user_id, fcm_token) do update set
    is_active = true,
    platform = excluded.platform,
    last_seen_at = now();
end;
$$;

revoke all on function public.upsert_my_push_token(text, text) from public, anon, authenticated;
grant execute on function public.upsert_my_push_token(text, text) to authenticated;

-- 3. Add accuracy range validation to punch_attendance_local
create or replace function public.punch_attendance_local(
  p_event_type text,
  p_credential_id text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_is_mock boolean default false,
  p_device_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_employee record;
  v_credential record;
  v_device record;
  v_event_id uuid;
  v_event record;
  v_result jsonb;
  v_error text;
  v_known_errors constant text[] := array[
    'attendance_outside_complex',
    'attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low',
    'attendance_geofence_not_configured',
    'attendance_location_required',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required'
  ];
begin
  if v_user_id is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;
  if nullif(trim(p_credential_id), '') is null then
    raise exception 'credential_required' using errcode = '22023';
  end if;
  if p_latitude is null or p_longitude is null or p_accuracy_meters is null then
    raise exception 'attendance_location_required' using errcode = '22023';
  end if;
  if p_latitude < -90 or p_latitude > 90
     or p_longitude < -180 or p_longitude > 180 then
    raise exception 'invalid_latitude_or_longitude' using errcode = '22023';
  end if;
  if p_accuracy_meters < 0 or p_accuracy_meters > 10000 then
    raise exception 'invalid_accuracy' using errcode = '22023';
  end if;

  -- Lookup employee
  select id, status, user_id into v_employee
  from public.employees
  where user_id = v_user_id and status in ('active', 'onboarding');

  if v_employee.id is null then
    raise exception 'no_employee_linked' using errcode = 'P0002';
  end if;

  -- Verify credential is active and belongs to this employee
  select id, credential_id, status into v_credential
  from public.passkey_credentials
  where credential_id = p_credential_id
    and employee_id = v_employee.id
    and user_id = v_user_id
    and status = 'active'
    and trusted = true;

  if v_credential.id is null then
    raise exception 'credential_not_found' using errcode = '42501';
  end if;

  -- Verify device is active
  select id, status into v_device
  from public.employee_devices
  where employee_id = v_employee.id
    and user_id = v_user_id
    and credential_id = p_credential_id
    and status = 'active';

  if v_device.id is null then
    raise exception 'device_not_active' using errcode = '28000';
  end if;

  -- Update last_used_at
  update public.employee_devices
  set last_used_at = now()
  where id = v_device.id;

  update public.passkey_credentials
  set last_used = now()
  where id = v_credential.id;

  -- Record attendance event (reuses existing function with all geofence checks)
  begin
    v_event_id := public.record_attendance_event(
      v_employee.id,
      p_event_type,
      p_latitude,
      p_longitude,
      p_accuracy_meters,
      'passkey',
      null,
      v_credential.id,
      true,
      p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    if v_error = any(v_known_errors) then
      return jsonb_build_object(
        'ok', false,
        'error', v_error,
        'replayed', false
      );
    end if;
    raise;
  end;

  select * into v_event from public.attendance_events where id = v_event_id;
  v_result := jsonb_build_object(
    'ok', true,
    'verified', true,
    'eventId', v_event_id,
    'eventType', p_event_type,
    'status', coalesce(v_event.status, 'accepted'),
    'insideComplex', v_event.status = 'accepted',
    'distanceMeters', v_event.distance_meters,
    'geofenceId', v_event.geofence_id,
    'recordedAt', v_event.event_at,
    'replayed', false
  );

  return v_result;
end;
$$;

revoke all on function public.punch_attendance_local(
  text, text, double precision, double precision, double precision, boolean, text
) from public, anon, authenticated;
grant execute on function public.punch_attendance_local(
  text, text, double precision, double precision, double precision, boolean, text
) to authenticated;

notify pgrst, 'reload schema';
