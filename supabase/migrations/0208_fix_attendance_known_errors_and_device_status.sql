-- Migration 0208: Fix attendance error handling + device status visibility
--
-- ① finalize_verified_attendance — v_known_errors array contains WRONG error
--   codes that don't match record_attendance_event (updated in 0201). ALL
--   attendance errors in the passkey/WebAuthn path escape the catch block and
--   return generic 500 instead of meaningful error codes.
--
-- ② get_my_attendance_state — missing localDeviceStatus field. Flutter reads
--   json['localDeviceStatus'] but the RPC never returns it → employees with
--   pending devices see "no active device" with no explanation.
--
-- ③ punch_attendance_local_biometric_v1 — v_known_errors missing
--   'invalid_attendance_location' added in 0201.

begin;

-- ═══════════════════════════════════════════════════════════════════════════
-- ① Fix finalize_verified_attendance — correct v_known_errors
-- ═══════════════════════════════════════════════════════════════════════════
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
  -- 0208: Fixed — must match ACTUAL error codes from record_attendance_event (0201)
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
    'attendance_check_out_required'
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
  '0208: v_known_errors synced with record_attendance_event (0201). V18-compliant device approval.';


-- ═══════════════════════════════════════════════════════════════════════════
-- ② Fix get_my_attendance_state — add localDeviceStatus
-- ═══════════════════════════════════════════════════════════════════════════
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
  v_local_device_status text;  -- 0208: new — 'active' | 'pending' | null
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

  select count(*) into v_local_devices
  from public.managed_devices md
  where md.user_id=auth.uid() and md.employee_id=v_me
    and md.platform in ('android','ios') and md.status='active'
    and md.biometric_available
    and exists (
      select 1 from public.employee_devices ed
      where ed.employee_id=v_me and ed.user_id=auth.uid() and ed.status='active'
        and ed.device_identifier_hash=encode(
          digest(convert_to(md.installation_id,'UTF8'),'sha256'),'hex'
        )
    );

  -- 0208: Determine device status for the mobile UI
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
      perform 1 from public.managed_devices md
      where md.user_id = auth.uid() and md.employee_id = v_me
        and md.platform in ('android','ios') and md.biometric_available
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
    'localDeviceStatus',v_local_device_status,   -- 0208: new field
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


-- ═══════════════════════════════════════════════════════════════════════════
-- ③ Fix punch_attendance_local_biometric_v1 — add missing error code
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
  select * into v_managed from public.managed_devices
  where installation_id=p_installation_id and user_id=auth.uid()
    and employee_id=v_employee_id and platform in ('android','ios')
    and status='active' and biometric_available
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
    'ok',true,'verified',true,'verificationMethod','local_biometric',
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

commit;
