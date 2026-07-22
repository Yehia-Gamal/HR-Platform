-- 0089: Atomically finalize a server-verified WebAuthn attendance punch.
-- The Edge Function verifies the signature; this RPC is the only place that
-- consumes the challenge, advances the authenticator counter, and records the
-- attendance event. Any unexpected failure rolls the entire operation back.

create table if not exists public.attendance_punch_attempts (
  operation_id uuid primary key,
  correlation_id uuid not null,
  challenge_id uuid not null references public.webauthn_challenges(id) on delete restrict,
  credential_id uuid not null references public.passkey_credentials(id) on delete restrict,
  employee_id uuid not null references public.employees(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  event_type text not null check (event_type in ('CHECK_IN', 'CHECK_OUT')),
  status text not null default 'processing' check (status in ('processing', 'completed', 'rejected')),
  attendance_event_id uuid references public.attendance_events(id) on delete restrict,
  rejection_code text,
  result jsonb,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  constraint attendance_punch_attempt_result_chk check (
    (status = 'processing' and attendance_event_id is null and rejection_code is null)
    or (status = 'completed' and attendance_event_id is not null and rejection_code is null)
    or (status = 'rejected' and attendance_event_id is null and rejection_code is not null)
  )
);

create unique index if not exists ux_attendance_punch_challenge
  on public.attendance_punch_attempts(challenge_id);
create index if not exists ix_attendance_punch_employee_created
  on public.attendance_punch_attempts(employee_id, created_at desc);
create index if not exists ix_attendance_punch_correlation
  on public.attendance_punch_attempts(correlation_id);

alter table public.attendance_punch_attempts enable row level security;
revoke all on table public.attendance_punch_attempts from public, anon, authenticated;
grant select, insert, update on table public.attendance_punch_attempts to service_role;

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
  if not exists (
    select 1 from public.employee_devices d
    where d.employee_id = p_employee_id
      and d.user_id = p_user_id
      and d.credential_id = v_credential.credential_id
      and d.status = 'active'
  ) then
    raise exception 'device_not_active' using errcode = '28000';
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

comment on function public.finalize_verified_attendance(
  uuid, uuid, uuid, uuid, uuid, uuid, text, double precision,
  double precision, double precision, bigint, text, boolean
) is 'Service-only atomic/idempotent finalization after Edge-verified WebAuthn assertion.';
