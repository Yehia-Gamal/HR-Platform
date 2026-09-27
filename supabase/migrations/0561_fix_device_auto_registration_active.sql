-- ============================================================================
-- 0561: إصلاح حلقة تكرار البصمة والتفعيل التلقائي لجهاز الموظف
-- ============================================================================
-- 1) ضمان تنشيط الجهاز في managed_devices و employee_devices بحالة 'active'
--    تلقائياً عند استدعاء register_my_device، حتى إن كان الجهاز سابقاً 'pending'
--    أو مسجلاً من قبل.
-- 2) إتاحة نقل تثبيت الجهاز إلى المستخدم الحالي المسجّل في حال تم تسجيل الدخول
--    بحساب جديد على نفس الهاتف (بدلاً من إلقاء استثناء يمنع تسجيل الدخول نهائياً).
-- 3) تحديث الأجهزة السابقة المعلّقة pending إلى active لإنهاء أي حلقة تكرار معلقة.
-- ============================================================================

begin;

-- (1) تنشيط أي أجهزة معلّقة سابقاً
update public.managed_devices
set status = 'active'
where status = 'pending';

update public.employee_devices
set status = 'active',
    approved_at = coalesce(approved_at, now())
where status = 'pending';

-- (2) دالة تسجيل الجهاز المحدثة مع القبول والتنشيط التلقائي
create or replace function public.register_my_device(
  p_installation_id text,
  p_platform text,
  p_device_name text,
  p_device_model text,
  p_os_version text,
  p_app_version text,
  p_app_build integer,
  p_environment text default 'production'::text,
  p_push_enabled boolean default false,
  p_biometric_available boolean default false,
  p_metadata jsonb default '{}'::jsonb
)
returns public.managed_devices
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_row public.managed_devices;
  v_employee_id uuid := public.current_employee_id();
  v_identifier_hash text;
begin
  if auth.uid() is null then
    raise exception 'يلزم تسجيل الدخول أولاً' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_installation_id, ''))) < 12 then
    raise exception 'معرّف جهاز غير صالح' using errcode = '22023';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'نظام تشغيل غير مدعوم' using errcode = '22023';
  end if;
  if p_environment not in ('development', 'staging', 'production') then
    raise exception 'بيئة غير صالحة' using errcode = '22023';
  end if;

  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  -- إدراج أو تحديث managed_devices وتفعيله كـ active دائماً
  insert into public.managed_devices(
    installation_id, user_id, employee_id, platform, device_name, device_model,
    os_version, app_version, app_build, environment, push_enabled,
    biometric_available, last_seen_at, metadata, status
  ) values (
    p_installation_id, auth.uid(), v_employee_id, p_platform,
    nullif(trim(p_device_name), ''), nullif(trim(p_device_model), ''),
    nullif(trim(p_os_version), ''), coalesce(nullif(trim(p_app_version), ''), '0.0.0'),
    greatest(coalesce(p_app_build, 0), 0), p_environment,
    coalesce(p_push_enabled, false), coalesce(p_biometric_available, false),
    now(), coalesce(p_metadata, '{}'::jsonb), 'active'
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
    status = 'active',
    revoked_at = null,
    revoked_by = null,
    revoke_reason = null
  returning * into v_row;

  -- إدراج أو تحديث employee_devices وتفعيله كـ active فوراً
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
      status = 'active',
      approved_at = coalesce(public.employee_devices.approved_at, now()),
      revoked_at = null,
      revocation_source = null,
      rejection_reason = null,
      metadata = coalesce(public.employee_devices.metadata, '{}'::jsonb)
        || excluded.metadata
        || jsonb_build_object(
          'reregistered', true,
          'reregisteredAt', now()
        );
  end if;

  return v_row;
end;
$function$;

commit;
