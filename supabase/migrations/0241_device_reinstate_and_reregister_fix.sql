-- 0241: Device administration repair: reinstate revoked devices and permit
--        a revoked/blocked device to be submitted again for approval.
--
-- This is the complete successor of the narrower 0240 draft.  It was recovered
-- from repository commit 01cdd4b after an external concurrent rename removed
-- the untracked working copy.

begin;

-- 1. Return a revoked device to pending so it must pass approval again.
create or replace function public.admin_reinstate_device(
  p_device_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_device public.employee_devices;
begin
  if not public.current_is_full_access() then
    raise exception 'insufficient permissions' using errcode = '42501';
  end if;

  select * into v_device
  from public.employee_devices
  where id = p_device_id
  for update;

  if v_device is null then
    raise exception 'device not found' using errcode = 'P0002';
  end if;

  if v_device.status not in ('revoked', 'auto_revoked', 'blocked') then
    raise exception 'device is not in a reinstatable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  update public.employee_devices
  set status = 'pending',
      revoked_at = null,
      revocation_source = null,
      approved_by = null,
      approved_at = null,
      rejection_reason = null,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'reinstated', true,
        'reinstatedAt', now(),
        'reinstatedBy', auth.uid(),
        'reinstateReason', p_reason,
        'previousStatus', v_device.status
      )
  where id = p_device_id;

  update public.passkey_credentials
  set status = 'active', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked';

  perform public.log_security_event(
    'device.reinstated',
    'medium', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'previousStatus', v_device.status,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'pending',
    'previousStatus', v_device.status
  );
end;
$$;

revoke all on function public.admin_reinstate_device(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_reinstate_device(uuid, text)
  to authenticated;

-- 2. Re-registering a revoked/blocked/replaced device submits it as pending.
create or replace function public.register_my_device(
  p_installation_id text,
  p_platform text,
  p_device_name text,
  p_device_model text,
  p_os_version text,
  p_app_version text,
  p_app_build integer,
  p_environment text default 'production',
  p_push_enabled boolean default false,
  p_biometric_available boolean default false,
  p_metadata jsonb default '{}'::jsonb
)
returns public.managed_devices
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_row public.managed_devices;
  v_existing_user uuid;
  v_employee_id uuid := public.current_employee_id();
  v_identifier_hash text;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_installation_id, ''))) < 12 then
    raise exception 'invalid installation id' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'invalid platform' using errcode = '22023';
  end if;
  if p_environment not in ('development', 'staging', 'production') then
    raise exception 'invalid environment' using errcode = '22023';
  end if;

  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  select user_id into v_existing_user
  from public.managed_devices
  where installation_id = p_installation_id;

  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'installation belongs to another account' using errcode = '42501';
  end if;

  insert into public.managed_devices(
    installation_id, user_id, employee_id, platform, device_name, device_model,
    os_version, app_version, app_build, environment, push_enabled,
    biometric_available, last_seen_at, metadata
  ) values (
    p_installation_id, auth.uid(), v_employee_id, p_platform,
    nullif(trim(p_device_name), ''), nullif(trim(p_device_model), ''),
    nullif(trim(p_os_version), ''), coalesce(nullif(trim(p_app_version), ''), '0.0.0'),
    greatest(coalesce(p_app_build, 0), 0), p_environment,
    coalesce(p_push_enabled, false), coalesce(p_biometric_available, false),
    now(), coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id = excluded.user_id,
    employee_id = excluded.employee_id,
    platform = excluded.platform,
    device_name = excluded.device_name,
    device_model = excluded.device_model,
    os_version = excluded.os_version,
    app_version = excluded.app_version,
    app_build = excluded.app_build,
    environment = excluded.environment,
    push_enabled = excluded.push_enabled,
    biometric_available = excluded.biometric_available,
    last_seen_at = now(),
    metadata = excluded.metadata,
    status = case
      when public.managed_devices.status = 'retired' then 'active'
      else public.managed_devices.status
    end
  returning * into v_row;

  if v_employee_id is not null and p_platform in ('android', 'ios') then
    insert into public.employee_devices(
      employee_id, user_id, device_identifier_hash, credential_id, device_name,
      platform, status, last_used_at, metadata
    ) values (
      v_employee_id, auth.uid(), v_identifier_hash, null,
      coalesce(nullif(trim(p_device_name), ''), nullif(trim(p_device_model), '')),
      p_platform, 'pending', now(), jsonb_build_object(
        'kind', 'local_biometric',
        'managedDeviceId', v_row.id,
        'biometricAvailable', coalesce(p_biometric_available, false)
      )
    )
    on conflict (employee_id, device_identifier_hash) do update set
      user_id = excluded.user_id,
      device_name = excluded.device_name,
      platform = excluded.platform,
      last_used_at = now(),
      status = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then 'pending'
        else public.employee_devices.status
      end,
      revoked_at = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revoked_at
      end,
      revocation_source = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.revocation_source
      end,
      rejection_reason = case
        when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
          then null
        else public.employee_devices.rejection_reason
      end,
      metadata = coalesce(public.employee_devices.metadata, '{}'::jsonb)
        || excluded.metadata
        || case
          when public.employee_devices.status in ('revoked', 'auto_revoked', 'blocked', 'replaced')
            then jsonb_build_object(
              'reregistered', true,
              'reregisteredAt', now(),
              'previousStatus', public.employee_devices.status
            )
          else '{}'::jsonb
        end;
  end if;

  perform public.log_security_event(
    'device.registered', 'low', 'allowed', v_identifier_hash,
    jsonb_build_object(
      'platform', p_platform,
      'appVersion', p_app_version,
      'appBuild', p_app_build,
      'biometricAvailable', p_biometric_available
    )
  );

  return v_row;
end;
$$;

revoke all on function public.register_my_device(
  text, text, text, text, text, text, integer, text, boolean, boolean, jsonb
) from public, anon;
grant execute on function public.register_my_device(
  text, text, text, text, text, text, integer, text, boolean, boolean, jsonb
) to authenticated;

notify pgrst, 'reload schema';

commit;
