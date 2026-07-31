-- 0240: Restore the missing administrative device-reinstate RPC.
-- Recovered from the complete device lifecycle change in repository commit
-- 01cdd4b.  Migration 0241 reapplies it before adding re-registration repair.

begin;

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
    'device.reinstated', 'medium', 'allowed', v_device.device_identifier_hash,
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

comment on function public.admin_reinstate_device(uuid, text) is
  'Returns a revoked, auto-revoked, or blocked employee device to pending review; full-access administrators only.';

commit;
