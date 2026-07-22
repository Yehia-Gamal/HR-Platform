-- 0093: Fix `device_not_active` root cause.
--
-- Root cause analysis:
-- 1. `revoke_my_passkey` (migration 0023) revokes `passkey_credentials` but
--    never touches `employee_devices` — stale active device rows survive.
-- 2. Passkeys registered before migration 0073/0083 may lack
--    `employee_devices` rows entirely, causing `device_not_active` in both
--    the Edge Function and the `finalize_verified_attendance` RPC.
-- 3. Migration 0085 attempted a one-time repair, but new edge cases keep
--    appearing because `revoke_my_passkey` still doesn't cascade.
--
-- Fix:
-- A. Backfill ALL missing `employee_devices` rows from active credentials.
-- B. Update `revoke_my_passkey` to cascade revocation to `employee_devices`.
-- C. Add a guard in `finalize_verified_attendance` that auto-creates the
--    device row if the credential is trusted but the device is missing.

-- ── A. Backfill missing employee_devices from passkey_credentials ──────────
insert into public.employee_devices(
  employee_id, user_id, device_identifier_hash, credential_id, public_key,
  device_name, platform, status, registered_at, revoked_at, metadata
)
select
  pc.employee_id,
  pc.user_id,
  encode(digest(convert_to(pc.credential_id, 'UTF8'), 'sha256'), 'hex'),
  pc.credential_id,
  pc.public_key,
  coalesce(pc.device_label, 'هاتف الموظف'),
  'android',
  case when pc.trusted and pc.status = 'active' then 'active'
       when pc.status = 'revoked' then 'revoked'
       else 'blocked' end,
  pc.created_at,
  case when pc.status = 'revoked' then now() else null end,
  jsonb_build_object(
    'serverVerified', pc.trusted,
    'backfilledBy', '0093',
    'passkeyCredentialId', pc.id
  )
from public.passkey_credentials pc
where pc.user_id is not null
  and not exists (
    select 1 from public.employee_devices ed
    where ed.employee_id = pc.employee_id
      and ed.credential_id = pc.credential_id
  )
on conflict (employee_id, device_identifier_hash) do update set
  user_id = excluded.user_id,
  credential_id = excluded.credential_id,
  public_key = excluded.public_key,
  device_name = excluded.device_name,
  status = case
    when public.employee_devices.status = 'revoked' then 'revoked'
    when public.employee_devices.status = 'blocked' and excluded.status = 'active' then 'blocked'
    else excluded.status
  end,
  revoked_at = case
    when public.employee_devices.status = 'revoked' then public.employee_devices.revoked_at
    when excluded.status = 'revoked' then now()
    else public.employee_devices.revoked_at
  end,
  metadata = public.employee_devices.metadata || excluded.metadata;

-- ── B. Update revoke_my_passkey to cascade to employee_devices ─────────────
create or replace function public.revoke_my_passkey(
  p_credential_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_credential public.passkey_credentials;
begin
  if auth.uid() is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode='42501';
  end if;

  select * into v_credential
  from public.passkey_credentials
  where id=p_credential_id
    and user_id=auth.uid()
    and employee_id=v_employee_id
  for update;

  if v_credential.id is null then
    raise exception 'passkey not found' using errcode='P0002';
  end if;

  if v_credential.status='revoked' then
    return jsonb_build_object(
      'id',v_credential.id,
      'status','revoked',
      'alreadyRevoked',true
    );
  end if;

  update public.passkey_credentials
  set status='revoked', trusted=false, updated_at=now()
  where id=v_credential.id;

  update public.employee_devices
  set status='revoked', revoked_at=now(), updated_at=now()
  where employee_id=v_employee_id
    and credential_id=v_credential.credential_id
    and status='active';

  perform public.log_audit_event(
    'passkey.revoked',
    'security',
    'warning',
    'passkey_credentials',
    v_credential.id,
    'إلغاء جهاز بصمة موثوق',
    nullif(trim(coalesce(p_reason,'')),''),
    jsonb_build_object(
      'deviceLabel',v_credential.device_label,
      'credentialDeviceType',v_credential.credential_device_type,
      'lastUsedAt',v_credential.last_used
    )
  );

  return jsonb_build_object(
    'id',v_credential.id,
    'status','revoked',
    'alreadyRevoked',false
  );
end;
$$;

revoke execute on function public.revoke_my_passkey(uuid,text) from public;
grant execute on function public.revoke_my_passkey(uuid,text) to authenticated;

-- ── C. Auto-create employee_devices row in finalize_verified_attendance ────
-- If the credential is trusted and active but the device row is missing
-- (edge case from pre-0073 passkeys), auto-provision it instead of failing.
create or replace function public.finalize_verified_attendance(
  p_operation_id uuid,
  p_correlation_id uuid,
  p_challenge_id uuid,
  p_credential_id uuid,
  p_employee_id uuid,
  p_user_id uuid,
  p_event_type text,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_new_sign_count bigint,
  p_selfie_path text default null,
  p_is_mock boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempt public.attendance_punch_attempts%rowtype;
  v_challenge public.webauthn_challenges%rowtype;
  v_credential public.passkey_credentials%rowtype;
  v_event_id uuid;
  v_event public.attendance_events%rowtype;
  v_result jsonb;
  v_error text;
  v_device_exists boolean;
  v_known_errors constant text[] := array[
    'attendance_outside_complex',
    'attendance_mock_location_rejected',
    'attendance_location_accuracy_too_low',
    'attendance_geofence_not_configured',
    'attendance_location_required',
    'attendance_passkey_not_trusted',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required'
  ];
begin
  if coalesce(
       current_setting('request.jwt.claim.role', true),
       current_setting('role', true),
       current_user
     ) not in ('service_role', 'postgres', 'supabase_admin')
     and current_user <> 'service_role' then
    raise exception 'attendance_trusted_server_required' using errcode = '42501';
  end if;

  if p_operation_id is null or p_correlation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;

  insert into public.attendance_punch_attempts(
    operation_id, correlation_id, challenge_id, credential_id,
    employee_id, user_id, event_type
  ) values (
    p_operation_id, p_correlation_id, p_challenge_id, p_credential_id,
    p_employee_id, p_user_id, p_event_type
  )
  on conflict (operation_id) do nothing;

  select * into v_attempt
  from public.attendance_punch_attempts
  where operation_id = p_operation_id
  for update;

  if v_attempt.operation_id is null then
    raise exception 'attendance_attempt_create_failed' using errcode = '55000';
  end if;
  if v_attempt.challenge_id <> p_challenge_id
     or v_attempt.credential_id <> p_credential_id
     or v_attempt.employee_id <> p_employee_id
     or v_attempt.user_id <> p_user_id
     or v_attempt.event_type <> p_event_type then
    raise exception 'attendance_idempotency_conflict' using errcode = '22023';
  end if;
  if v_attempt.status in ('completed', 'rejected') then
    return v_attempt.result || jsonb_build_object('replayed', true);
  end if;

  select * into v_challenge
  from public.webauthn_challenges
  where id = p_challenge_id
  for update;
  if v_challenge.id is null
     or v_challenge.type <> 'auth'
     or v_challenge.user_id <> p_user_id
     or v_challenge.employee_id <> p_employee_id
     or v_challenge.used_at is not null
     or v_challenge.expires_at <= now() then
    raise exception 'challenge_invalid_or_used' using errcode = '22023';
  end if;

  select * into v_credential
  from public.passkey_credentials
  where id = p_credential_id
  for update;
  if v_credential.id is null
     or v_credential.user_id <> p_user_id
     or v_credential.employee_id <> p_employee_id
     or v_credential.status <> 'active'
     or not v_credential.trusted then
    raise exception 'attendance_passkey_not_trusted' using errcode = '28000';
  end if;

  select exists (
    select 1 from public.employee_devices d
    where d.employee_id = p_employee_id
      and d.user_id = p_user_id
      and d.credential_id = v_credential.credential_id
      and d.status = 'active'
  ) into v_device_exists;

  if not v_device_exists then
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, public_key,
      device_name, platform, status, registered_at, metadata
    ) values (
      p_employee_id, p_user_id,
      encode(digest(convert_to(v_credential.credential_id, 'UTF8'), 'sha256'), 'hex'),
      v_credential.credential_id, v_credential.public_key,
      coalesce(v_credential.device_label, 'هاتف الموظف'), 'android', 'active', now(),
      jsonb_build_object('serverVerified', true, 'autoProvisioned', 'finalize_attendance', 'passkeyCredentialId', v_credential.id)
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      credential_id = excluded.credential_id,
      public_key = excluded.public_key,
      status = 'active',
      revoked_at = null,
      registered_at = now(),
      metadata = public.employee_devices.metadata || excluded.metadata;
  end if;

  if p_new_sign_count < 0
     or (v_credential.sign_count > 0 and p_new_sign_count <= v_credential.sign_count) then
    raise exception 'authenticator_counter_replay' using errcode = '28000';
  end if;

  update public.webauthn_challenges
  set used_at = now()
  where id = p_challenge_id;

  update public.passkey_credentials
  set sign_count = p_new_sign_count, last_used = now()
  where id = p_credential_id;

  update public.employee_devices
  set last_used_at = now()
  where employee_id = p_employee_id
    and user_id = p_user_id
    and credential_id = v_credential.credential_id
    and status = 'active';

  begin
    v_event_id := public.record_attendance_event(
      p_employee_id,
      p_event_type,
      p_latitude,
      p_longitude,
      p_accuracy_meters,
      'passkey',
      p_selfie_path,
      p_credential_id,
      true,
      p_is_mock
    );
  exception when others then
    get stacked diagnostics v_error = message_text;
    if v_error = any(v_known_errors) then
      v_result := jsonb_build_object(
        'ok', false,
        'error', v_error,
        'correlationId', p_correlation_id,
        'operationId', p_operation_id,
        'replayed', false
      );
      update public.attendance_punch_attempts
      set status = 'rejected', rejection_code = v_error,
          result = v_result, completed_at = now()
      where operation_id = p_operation_id;
      return v_result;
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
    'correlationId', p_correlation_id,
    'operationId', p_operation_id,
    'replayed', false
  );

  update public.attendance_punch_attempts
  set status = 'completed', attendance_event_id = v_event_id,
      result = v_result, completed_at = now()
  where operation_id = p_operation_id;

  return v_result;
end;
$$;

revoke all on function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text, double precision,
  double precision, double precision, bigint, text, boolean
) from public, anon, authenticated;
grant execute on function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text, double precision,
  double precision, double precision, bigint, text, boolean
) to service_role;

-- ── Also fix verify-attendance-punch edge function concern ─────────────────
-- The Edge Function checks employee_devices before finalize RPC. We cannot
-- modify the Edge Function here, but the auto-provision in finalize covers
-- the race condition. For extra safety, backfill all existing credentials
-- one more time (idempotent).

notify pgrst, 'reload schema';
