-- ═══════════════════════════════════════════════════════════════════════════════
-- 0356: Auto-accept device registration (no manual web approval required)
-- ═══════════════════════════════════════════════════════════════════════════════
-- كان تسجيل الجهاز من تطبيق الموظف يُنشئ employee_devices بحالة 'pending'
-- ويتطلب موافقة يدوية من صفحة الأجهزة على الويب. هذا التعديل يجعل كل جهاز
-- يُسجَّل (local_biometric) مقبولاً تلقائياً بحالة 'active' مع approved_at.
--
-- (1) إعادة إنشاء register_my_device (أحدث نسخة من 0241) مع القبول التلقائي.
-- (2) تفعيل الأجهزة المحلية المعلّقة سابقاً كتغذية راجعة للسلوك الجديد.
-- ═══════════════════════════════════════════════════════════════════════════════

begin;

-- (2) backfill: تفعيل الأجهزة المحلية المعلّقة سابقاً
update public.employee_devices
set status = 'active',
    approved_at = coalesce(approved_at, now())
where status = 'pending'
  and metadata ->> 'kind' = 'local_biometric';

-- (1) القبول التلقائي عند التسجيل
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
      platform, status, approved_at, last_used_at, metadata
    ) values (
      v_employee_id, auth.uid(), v_identifier_hash, null,
      coalesce(nullif(trim(p_device_name), ''), nullif(trim(p_device_model), '')),
      p_platform, 'active', now(), now(), jsonb_build_object(
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
          then 'active'
        else public.employee_devices.status
      end,
      approved_at = now(),
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
      'biometricAvailable', p_biometric_available,
      'autoAccepted', true
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
