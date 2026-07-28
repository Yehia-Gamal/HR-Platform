-- Migration 0192: إصلاح تجاوز اعتماد الجهاز في finalize_verified_attendance
-- المشكلة: الـ RPC يُنشئ جهازاً بحالة active متجاوزاً V18 device approval workflow
-- الذي يتطلب أن تبدأ الأجهزة بحالة pending.
-- الحل: تغيير status من 'active' إلى 'pending' + رفض التسجيل بدون جهاز نشط.

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
  v_credential   public.passkey_credentials%rowtype;
  v_device_exists boolean;
  v_event_id     uuid;
  v_event        public.attendance_events%rowtype;
  v_result       jsonb;
  v_error        text;
  v_known_errors text[] := array[
    'attendance_already_checked_in',
    'attendance_already_checked_out',
    'attendance_no_check_in',
    'attendance_offsite_rejected',
    'attendance_outside_schedule',
    'attendance_duplicate_within_window',
    'mock_location_rejected'
  ];
begin
  -- ── Guard: caller must be service_role ──
  if current_setting('request.jwt.claim.role', true) is distinct from 'service_role' then
    raise exception 'rpc_service_role_only' using errcode = '42501';
  end if;

  -- ── Idempotency: check + insert attempt row ──
  insert into public.attendance_punch_attempts(
    operation_id, correlation_id, challenge_id, employee_id, user_id, status
  ) values (
    p_operation_id, p_correlation_id, p_challenge_id, p_employee_id, p_user_id, 'processing'
  )
  on conflict (operation_id) do nothing;

  if not found then
    select result into v_result
    from public.attendance_punch_attempts
    where operation_id = p_operation_id;
    if v_result is not null then return v_result; end if;
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

  -- ── Check active device exists ──
  select exists (
    select 1 from public.employee_devices d
    where d.employee_id = p_employee_id
      and d.user_id = p_user_id
      and d.credential_id = v_credential.credential_id
      and d.status = 'active'
  ) into v_device_exists;

  -- إذا لم يكن هناك جهاز نشط، ننشئ جهاز بحالة pending (لا active)
  -- ونرفض تسجيل الحضور حتى يُعتمد الجهاز من المسؤول.
  if not v_device_exists then
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
      -- الحفاظ على الحالة الحالية بدلاً من فرض active
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
    'timestamp', v_event.event_time,
    'correlationId', p_correlation_id,
    'operationId', p_operation_id,
    'replayed', false,
    'credentialLabel', v_credential.device_label
  );

  update public.attendance_punch_attempts
  set status = 'completed', result = v_result, completed_at = now()
  where operation_id = p_operation_id;

  return v_result;
end;
$$;

comment on function public.finalize_verified_attendance is
  'V18-compliant: auto-provisions devices as pending (not active); rejects attendance without an approved device.';

commit;
