-- 0085: Repair canonical device rows for existing passkeys. A device is active
-- only when the corresponding server-side credential is trusted and active.

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
  case when pc.trusted and pc.status = 'active' then 'active' else 'blocked' end,
  pc.created_at,
  case when pc.trusted and pc.status = 'active' then null else now() end,
  jsonb_build_object(
    'serverVerified', pc.trusted,
    'repairedByMigration', '0085',
    'passkeyCredentialId', pc.id,
    'credentialDeviceType', pc.credential_device_type,
    'credentialBackedUp', pc.credential_backed_up
  )
from public.passkey_credentials pc
where pc.user_id is not null
on conflict (employee_id, device_identifier_hash) do update set
  user_id = excluded.user_id,
  credential_id = excluded.credential_id,
  public_key = excluded.public_key,
  device_name = excluded.device_name,
  status = case
    when public.employee_devices.status = 'revoked' then 'revoked'
    else excluded.status
  end,
  revoked_at = case
    when public.employee_devices.status = 'revoked' then public.employee_devices.revoked_at
    else excluded.revoked_at
  end,
  metadata = public.employee_devices.metadata || excluded.metadata;

notify pgrst, 'reload schema';
