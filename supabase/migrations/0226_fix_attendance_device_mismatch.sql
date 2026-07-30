-- Migration 0226: Fix biometric attendance device mismatch
--
-- Root cause: Two bugs combine to show a generic error when punching attendance:
--
-- Bug ①: get_my_attendance_state() is PARAMETERLESS — checks ALL device pairs
--   for the user. If ANY pair (managed_device + employee_device) is active,
--   it reports canPunch=true. But the current device's pair may be inactive
--   (replaced/revoked/pending). The punch button lights up, user taps,
--   and the punch function rejects with local_biometric_device_not_active.
--
-- Bug ②: punch_attendance_local_biometric_v1 RAISEs an exception for
--   device-not-active (errcode 28000). Flutter receives this as a
--   PostgrestException, which maps to a generic message:
--   "تعذر إتمام العملية. أعد المحاولة بعد لحظات."
--   instead of a clear device-specific message.
--
-- Fixes:
--   ① get_my_attendance_state(p_installation_id) — optional parameter.
--     When provided, checks THIS device specifically and sets canPunch
--     based on the current device's status, not all devices.
--   ② punch_attendance_local_biometric_v1 — converts device-not-active
--     from RAISE EXCEPTION to structured JSON {ok:false, error:'...'},
--     so Flutter's result-check path handles it with a clear message.

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- ① get_my_attendance_state — add optional p_installation_id parameter
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop the old parameterless version (signature change requires drop+create)
drop function if exists public.get_my_attendance_state();

create or replace function public.get_my_attendance_state(
  p_installation_id text default null
)
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
  v_current_device_active boolean := false;  -- 0226: THIS device specifically
  v_current_device_status text;              -- 0226: status of THIS device
  v_passkeys integer := 0;
  v_last public.attendance_events;
  v_today date := (now() at time zone 'Africa/Cairo')::date;
  v_today_status text;
  v_suggested text := 'CHECK_IN';
  v_hash text;
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

  -- Count ALL active device pairs (backward compat)
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

  -- 0226: When installation_id is provided, check THIS device specifically
  if p_installation_id is not null and length(trim(p_installation_id)) >= 12 then
    v_hash := encode(digest(convert_to(p_installation_id,'UTF8'),'sha256'),'hex');

    -- Check managed_device for this installation_id
    if exists (
      select 1 from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
        and md.platform in ('android','ios')
        and md.status = 'active'
    ) then
      -- Managed device is active — check employee_device
      select ed.status into v_current_device_status
      from public.employee_devices ed
      where ed.employee_id = v_me
        and ed.user_id = auth.uid()
        and ed.device_identifier_hash = v_hash
      order by ed.created_at desc
      limit 1;

      if v_current_device_status = 'active' then
        v_current_device_active := true;
      end if;
      -- v_current_device_status keeps whatever status was found (pending/replaced/revoked/blocked/active/null)
    else
      -- Managed device not active — check if it exists at all
      select md.status into v_current_device_status
      from public.managed_devices md
      where md.installation_id = p_installation_id
        and md.user_id = auth.uid()
        and md.employee_id = v_me
      limit 1;

      if v_current_device_status is null then
        v_current_device_status := 'not_registered';
      end if;
    end if;
  end if;

  -- Determine general device status for the mobile UI (backward compat)
  if v_local_devices > 0 then
    v_local_device_status := 'active';
  else
    perform 1 from public.employee_devices ed
    where ed.employee_id = v_me and ed.user_id = auth.uid() and ed.status = 'pending'
    limit 1;
    if found then
      v_local_device_status := 'pending';
    else
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
    -- 0226: Current device info (only set when p_installation_id provided)
    'currentDeviceStatus',v_current_device_status,
    'currentDeviceActive',v_current_device_active,
    'activePasskeys',v_passkeys,
    'hasActivePasskey',v_passkeys>0,
    -- 0226: canPunch uses current device check when installation_id is provided
    'canPunch',v_active and not v_is_executive and (
      case when p_installation_id is not null and length(trim(p_installation_id)) >= 12
           then v_current_device_active
           else v_local_devices > 0
      end
    ),
    'suggestedAction',v_suggested,
    'lastEventType',v_last.event_type,
    'lastEventAt',v_last.event_at,
    'lastEventStatus',v_last.status,
    'todayStatus',v_today_status,
    'lastUpdatedAt',now()
  );
end;
$$;

revoke all on function public.get_my_attendance_state(text) from public, anon;
grant execute on function public.get_my_attendance_state(text) to authenticated;

comment on function public.get_my_attendance_state is
  '0226: Accepts optional p_installation_id to check THIS device specifically. Fixes device mismatch where canPunch was true for the wrong device.';


-- ═══════════════════════════════════════════════════════════════════════════
-- ② punch_attendance_local_biometric_v1 — structured JSON for device errors
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
  v_verification_method text;
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

  -- 0226: Return structured JSON instead of RAISE for device-not-active.
  -- This lets Flutter's result-check path show a clear device-specific message.
  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'managed_device_not_active',
      'replayed', false
    );
  end if;
  select * into v_employee_device from public.employee_devices
  where employee_id=v_employee_id and user_id=auth.uid()
    and device_identifier_hash=v_hash and status='active'
  for update;
  if not found then
    return jsonb_build_object(
      'ok', false,
      'error', 'local_biometric_device_not_active',
      'detail', 'employee_device_not_active',
      'replayed', false
    );
  end if;

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
    'verificationMethod',v_verification_method,
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
  '0226: Device-not-active returns structured JSON instead of RAISE. Fixes generic error message on inactive device.';

commit;
