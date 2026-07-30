-- Migration 0215: Fix 5 regressions in finalize_verified_attendance (0208)
--
-- 0208 rewrote finalize_verified_attendance to sync v_known_errors and add
-- device auto-provisioning, but accidentally dropped critical logic from 0089:
--
--   ① INSERT into attendance_punch_attempts omits credential_id + event_type
--      (both NOT NULL, no DEFAULT) → NOT NULL violation on every passkey punch.
--
--   ② WebAuthn challenge validation completely removed — the function blindly
--      marks the challenge used without checking type, ownership, expiry, or
--      whether it was already consumed. Security regression: a replayed or
--      expired challenge would be silently accepted.
--
--   ③ v_event.event_time does not exist — column is event_at. Causes
--      "record has no field event_time" crash when building the success JSON.
--      (Bug originated in 0192, carried into 0208.)
--
--   ④ Completion UPDATE omits attendance_event_id — violates the CHECK
--      constraint attendance_punch_attempt_result_chk which requires
--      attendance_event_id IS NOT NULL when status = 'completed'.
--
--   ⑤ Idempotency validation weakened — no FOR UPDATE lock, no field-mismatch
--      comparison. A concurrent request with same operation_id but different
--      parameters would silently proceed instead of raising
--      attendance_idempotency_conflict.
--
-- This migration restores all five from the original 0089 while keeping 0208's
-- improvements: device auto-provisioning, updated v_known_errors, and the
-- stricter service_role guard.

begin;

create or replace function public.finalize_verified_attendance(
  p_operation_id     uuid,
  p_correlation_id   uuid,
  p_challenge_id     uuid,
  p_credential_id    uuid,
  p_employee_id      uuid,
  p_user_id          uuid,
  p_event_type       text,
  p_latitude         double precision,
  p_longitude        double precision,
  p_accuracy_meters  double precision,
  p_new_sign_count   bigint,
  p_selfie_path      text default null,
  p_is_mock          boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempt    public.attendance_punch_attempts%rowtype;
  v_challenge  public.webauthn_challenges%rowtype;
  v_credential public.passkey_credentials%rowtype;
  v_device_exists boolean;
  v_event_id   uuid;
  v_event      public.attendance_events%rowtype;
  v_result     jsonb;
  v_error      text;
  -- 0208: v_known_errors synced with record_attendance_event (0201)
  v_known_errors text[] := array[
    'attendance_mock_location_rejected',
    'attendance_location_required',
    'attendance_location_accuracy_too_low',
    'attendance_outside_complex',
    'attendance_geofence_not_configured',
    'attendance_passkey_not_trusted',
    'duplicate_attendance_event',
    'attendance_period_finalized',
    'attendance_check_in_required',
    'attendance_check_out_required',
    'invalid_attendance_location'
  ];
begin
  -- ── Guard: caller must be service_role (0208 style) ──
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'rpc_service_role_only' using errcode = '42501';
  end if;

  -- ── Input validation (restored from 0089) ──
  if p_operation_id is null or p_correlation_id is null then
    raise exception 'attendance_operation_id_required' using errcode = '22023';
  end if;
  if p_event_type not in ('CHECK_IN', 'CHECK_OUT') then
    raise exception 'invalid_event_type' using errcode = '22023';
  end if;

  -- ── ① FIX: Idempotency INSERT — include credential_id + event_type (NOT NULL) ──
  insert into public.attendance_punch_attempts(
    operation_id, correlation_id, challenge_id, credential_id,
    employee_id, user_id, event_type
  ) values (
    p_operation_id, p_correlation_id, p_challenge_id, p_credential_id,
    p_employee_id, p_user_id, p_event_type
  )
  on conflict (operation_id) do nothing;

  -- ── ⑤ FIX: Proper idempotency — FOR UPDATE lock + field comparison ──
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

  -- ── ② FIX: Validate WebAuthn challenge (restored from 0089) ──
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

  -- ── Verify credential is active + trusted ──
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

  -- ── Check active device exists — auto-provision if needed (0208 feature) ──
  select exists (
    select 1 from public.employee_devices d
    where d.employee_id = p_employee_id
      and d.user_id = p_user_id
      and d.credential_id = v_credential.credential_id
      and d.status = 'active'
  ) into v_device_exists;

  if not v_device_exists then
    -- إذا لم يكن هناك جهاز نشط، ننشئ جهاز بحالة pending
    -- ونرفض تسجيل الحضور حتى يُعتمد الجهاز من المسؤول.
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, public_key,
      device_name, platform, status, registered_at, metadata
    ) values (
      p_employee_id, p_user_id,
      encode(digest(convert_to(v_credential.credential_id, 'UTF8'), 'sha256'), 'hex'),
      v_credential.credential_id, v_credential.public_key,
      coalesce(v_credential.device_label, 'هاتف الموظف'), 'android', 'pending', now(),
      jsonb_build_object('serverVerified', true, 'autoProvisioned', 'finalize_attendance', 'passkeyCredentialId', v_credential.id)
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      credential_id = excluded.credential_id,
      public_key = excluded.public_key,
      status = public.employee_devices.status,
      metadata = public.employee_devices.metadata || excluded.metadata;

    -- إعادة فحص: هل أصبح الجهاز نشطاً بعد الـ upsert؟
    select exists (
      select 1 from public.employee_devices d
      where d.employee_id = p_employee_id
        and d.user_id = p_user_id
        and d.credential_id = v_credential.credential_id
        and d.status = 'active'
    ) into v_device_exists;

    if not v_device_exists then
      v_result := jsonb_build_object(
        'ok', false,
        'error', 'device_pending_approval',
        'correlationId', p_correlation_id,
        'operationId', p_operation_id,
        'replayed', false
      );
      update public.attendance_punch_attempts
      set status = 'rejected', rejection_code = 'device_pending_approval',
          result = v_result, completed_at = now()
      where operation_id = p_operation_id;
      return v_result;
    end if;
  end if;

  -- ── Counter replay check ──
  if p_new_sign_count < 0
     or (v_credential.sign_count > 0 and p_new_sign_count <= v_credential.sign_count) then
    raise exception 'authenticator_counter_replay' using errcode = '28000';
  end if;

  -- ── Consume challenge ──
  update public.webauthn_challenges
  set used_at = now()
  where id = p_challenge_id;

  -- ── Update credential counters ──
  update public.passkey_credentials
  set sign_count = p_new_sign_count, last_used = now()
  where id = p_credential_id;

  update public.employee_devices
  set last_used_at = now()
  where employee_id = p_employee_id
    and user_id = p_user_id
    and credential_id = v_credential.credential_id
    and status = 'active';

  -- ── Record attendance event ──
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
    -- ③ FIX: event_at (not event_time — column does not exist)
    'recordedAt', v_event.event_at,
    'correlationId', p_correlation_id,
    'operationId', p_operation_id,
    'replayed', false,
    'credentialLabel', v_credential.device_label
  );

  -- ④ FIX: include attendance_event_id (required by CHECK constraint)
  update public.attendance_punch_attempts
  set status = 'completed', attendance_event_id = v_event_id,
      result = v_result, completed_at = now()
  where operation_id = p_operation_id;

  return v_result;
end;
$$;

comment on function public.finalize_verified_attendance is
  '0215: Fix 5 regressions from 0208 — restore NOT NULL INSERT cols, challenge validation, event_at, attendance_event_id, idempotency lock.';

commit;
