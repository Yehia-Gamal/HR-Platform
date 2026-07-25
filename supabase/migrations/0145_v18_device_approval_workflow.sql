-- 0145: V18 §5 — Device approval workflow.
-- موظف يسجل جهاز ← pending ← HR/Operations يوافق ← active.
-- لا يُسمح بأكثر من جهاز active لنفس الموظف.
-- أعمدة جديدة: approved_by, approved_at, rejection_reason.
-- RPCs: approve_device, get_pending_devices_admin.

begin;

-- ─────────────────────────────────────────────────────────────
-- 1) أعمدة الموافقة
-- ─────────────────────────────────────────────────────────────
alter table public.employee_devices
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists rejection_reason text;

comment on column public.employee_devices.approved_by is 'المستخدم الذي وافق/رفض الجهاز';
comment on column public.employee_devices.approved_at is 'وقت الموافقة أو الرفض';
comment on column public.employee_devices.rejection_reason is 'سبب الرفض (إن وُجد)';

-- backfill: الأجهزة الحالية بحالة active تُعتبر موافقاً عليها ضمنياً
update public.employee_devices
set approved_at = registered_at
where status = 'active' and approved_at is null;

-- ─────────────────────────────────────────────────────────────
-- 2) Trigger: تعطيل الجهاز النشط القديم عند تسجيل جديد
-- ─────────────────────────────────────────────────────────────
create or replace function public.trg_fn_employee_devices_auto_replace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- عند إدراج جهاز جديد، أي جهاز active سابق لنفس الموظف يُستبدل
  update public.employee_devices
  set status = 'replaced',
      revoked_at = now(),
      metadata = metadata || jsonb_build_object('replacedByDeviceInsert', true)
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and status = 'active';
  return NEW;
end;
$$;

drop trigger if exists trg_employee_devices_auto_replace on public.employee_devices;
create trigger trg_employee_devices_auto_replace
  after insert on public.employee_devices
  for each row
  execute function public.trg_fn_employee_devices_auto_replace();

-- ─────────────────────────────────────────────────────────────
-- 3) RPC: approve_device — موافقة أو رفض جهاز
-- ─────────────────────────────────────────────────────────────
create or replace function public.approve_device(
  p_device_id uuid,
  p_approved boolean,
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
  where id = p_device_id;

  if v_device is null then
    raise exception 'device not found' using errcode = 'P0002';
  end if;

  if v_device.status not in ('pending', 'blocked') then
    raise exception 'device is not in a reviewable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  if p_approved then
    -- قبل التفعيل: تعطيل أي جهاز active آخر لنفس الموظف
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        metadata = metadata || jsonb_build_object('replacedByApproval', p_device_id)
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active';

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null
    where id = p_device_id;
  else
    update public.employee_devices
    set status = 'blocked',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = coalesce(p_reason, 'رفض إداري')
    where id = p_device_id;
  end if;

  perform public.log_security_event(
    case when p_approved then 'device.approved' else 'device.rejected' end,
    'medium', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'approved', p_approved,
      'reason', p_reason
    )
  );

  return jsonb_build_object('ok', true, 'status', case when p_approved then 'active' else 'blocked' end);
end;
$$;

revoke all on function public.approve_device(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.approve_device(uuid, boolean, text) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4) RPC: get_pending_devices_admin — قائمة الأجهزة المعلقة
-- ─────────────────────────────────────────────────────────────
create or replace function public.get_pending_devices_admin()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', d.id,
    'employeeId', d.employee_id,
    'employeeName', e.full_name,
    'employeeCode', e.employee_code,
    'employeePhotoUrl', p.photo_url,
    'deviceName', d.device_name,
    'platform', d.platform,
    'status', d.status,
    'registeredAt', d.registered_at,
    'lastUsedAt', d.last_used_at,
    'rejectionReason', d.rejection_reason,
    'metadata', d.metadata
  ) order by d.registered_at desc), '[]'::jsonb)
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  left join public.profiles p on p.id = e.user_id
  where d.status in ('pending', 'blocked')
    and public.current_is_full_access();
$$;

revoke all on function public.get_pending_devices_admin() from public, anon, authenticated;
grant execute on function public.get_pending_devices_admin() to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 5) تعديل activate_verified_passkey_device → pending بدلاً من active
-- ─────────────────────────────────────────────────────────────
create or replace function public.activate_verified_passkey_device(
  p_employee_id uuid,
  p_user_id uuid,
  p_credential_id text,
  p_public_key text,
  p_sign_count bigint,
  p_transports text[],
  p_device_label text,
  p_webauthn_user_id text,
  p_credential_device_type text,
  p_credential_backed_up boolean
)
returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp
as $$
declare
  v_credential public.passkey_credentials;
  v_device public.employee_devices;
  v_hash text;
begin
  if p_employee_id is null or p_user_id is null or nullif(trim(p_credential_id), '') is null then
    raise exception 'verified credential identity is required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.employees
    where id = p_employee_id and user_id = p_user_id
  ) then
    raise exception 'employee/user link mismatch' using errcode = '42501';
  end if;

  -- passkey_credentials تبقى active (هي credential فنية، ليست سياسة موافقة)
  insert into public.passkey_credentials(
    employee_id, user_id, credential_id, public_key, sign_count,
    transports, device_label, status, trusted, webauthn_user_id,
    credential_device_type, credential_backed_up, created_by
  ) values (
    p_employee_id, p_user_id, p_credential_id, p_public_key, p_sign_count,
    p_transports, left(coalesce(p_device_label, 'هاتف الموظف'), 120),
    'active', true, nullif(p_webauthn_user_id, ''),
    p_credential_device_type, p_credential_backed_up, p_user_id
  ) returning * into v_credential;

  v_hash := encode(digest(convert_to(p_credential_id, 'UTF8'), 'sha256'), 'hex');
  -- V18 §5: الجهاز يُسجَّل بحالة pending وينتظر موافقة المسؤول
  insert into public.employee_devices(
    employee_id, user_id, device_identifier_hash, credential_id, public_key,
    device_name, platform, status, registered_at, metadata
  ) values (
    p_employee_id, p_user_id, v_hash, p_credential_id, p_public_key,
    left(coalesce(p_device_label, 'هاتف الموظف'), 120), 'android', 'pending', now(),
    jsonb_build_object(
      'serverVerified', true,
      'credentialDeviceType', p_credential_device_type,
      'credentialBackedUp', p_credential_backed_up,
      'passkeyCredentialId', v_credential.id
    )
  )
  on conflict (employee_id, device_identifier_hash) do update set
    user_id = excluded.user_id,
    credential_id = excluded.credential_id,
    public_key = excluded.public_key,
    device_name = excluded.device_name,
    status = 'pending',
    revoked_at = null,
    registered_at = now(),
    approved_by = null,
    approved_at = null,
    rejection_reason = null,
    metadata = excluded.metadata
  returning * into v_device;

  return jsonb_build_object(
    'id', v_credential.id,
    'credential_id', v_credential.credential_id,
    'device_label', v_credential.device_label,
    'status', 'pending',
    'created_at', v_credential.created_at,
    'device_id', v_device.id,
    'verified', true,
    'requiresApproval', true
  );
end;
$$;

revoke execute on function public.activate_verified_passkey_device(
  uuid, uuid, text, text, bigint, text[], text, text, text, boolean
) from public, anon, authenticated;
grant execute on function public.activate_verified_passkey_device(
  uuid, uuid, text, text, bigint, text[], text, text, text, boolean
) to service_role;

-- ─────────────────────────────────────────────────────────────
-- 6) تعديل register_my_device → pending بدلاً من active (للأجهزة الجديدة)
-- ─────────────────────────────────────────────────────────────
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
    raise exception 'authentication required' using errcode='42501';
  end if;
  if length(trim(coalesce(p_installation_id,''))) < 12 then
    raise exception 'invalid installation id' using errcode='22023';
  end if;
  if p_platform not in ('android','ios','web') then
    raise exception 'invalid platform' using errcode='22023';
  end if;
  if p_environment not in ('development','staging','production') then
    raise exception 'invalid environment' using errcode='22023';
  end if;
  v_identifier_hash := encode(
    digest(convert_to(p_installation_id, 'UTF8'), 'sha256'), 'hex'
  );

  select user_id into v_existing_user
  from public.managed_devices
  where installation_id=p_installation_id;
  if v_existing_user is not null and v_existing_user <> auth.uid() then
    raise exception 'installation belongs to another account' using errcode='42501';
  end if;

  insert into public.managed_devices(
    installation_id,user_id,employee_id,platform,device_name,device_model,os_version,
    app_version,app_build,environment,push_enabled,biometric_available,last_seen_at,metadata
  ) values (
    p_installation_id,auth.uid(),v_employee_id,p_platform,nullif(trim(p_device_name),''),
    nullif(trim(p_device_model),''),nullif(trim(p_os_version),''),
    coalesce(nullif(trim(p_app_version),''),'0.0.0'),greatest(coalesce(p_app_build,0),0),
    p_environment,coalesce(p_push_enabled,false),coalesce(p_biometric_available,false),
    now(),coalesce(p_metadata,'{}'::jsonb)
  )
  on conflict (installation_id) do update set
    user_id=excluded.user_id,employee_id=excluded.employee_id,platform=excluded.platform,
    device_name=excluded.device_name,device_model=excluded.device_model,
    os_version=excluded.os_version,app_version=excluded.app_version,
    app_build=excluded.app_build,environment=excluded.environment,
    push_enabled=excluded.push_enabled,biometric_available=excluded.biometric_available,
    last_seen_at=now(),metadata=excluded.metadata,
    status=case when public.managed_devices.status='retired'
      then 'active' else public.managed_devices.status end
  returning * into v_row;

  -- V18 §5: الأجهزة الجديدة تُسجَّل بحالة pending وتحتاج موافقة
  if v_employee_id is not null and p_platform in ('android','ios') then
    insert into public.employee_devices(
      employee_id,user_id,device_identifier_hash,credential_id,device_name,
      platform,status,last_used_at,metadata
    ) values (
      v_employee_id,auth.uid(),v_identifier_hash,null,
      coalesce(nullif(trim(p_device_name),''),nullif(trim(p_device_model),'')),
      p_platform,'pending',now(),jsonb_build_object(
        'kind','local_biometric','managedDeviceId',v_row.id,
        'biometricAvailable',coalesce(p_biometric_available,false)
      )
    )
    on conflict (employee_id,device_identifier_hash) do update set
      user_id=excluded.user_id,device_name=excluded.device_name,
      platform=excluded.platform,last_used_at=now(),
      status=case
        when public.employee_devices.status in ('blocked','revoked','replaced')
          then public.employee_devices.status
        else public.employee_devices.status  -- لا تغيّر الحالة عند التحديث
      end,
      metadata=public.employee_devices.metadata || excluded.metadata;
  end if;

  perform public.log_security_event(
    'device.registered','low','allowed',v_identifier_hash,
    jsonb_build_object('platform',p_platform,'appVersion',p_app_version,
      'appBuild',p_app_build,'biometricAvailable',p_biometric_available)
  );
  return v_row;
end;
$$;

revoke all on function public.register_my_device(
  text,text,text,text,text,text,integer,text,boolean,boolean,jsonb
) from public, anon;
grant execute on function public.register_my_device(
  text,text,text,text,text,text,integer,text,boolean,boolean,jsonb
) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 7) تحديث get_my_passkeys لعرض بيانات الموافقة
-- ─────────────────────────────────────────────────────────────
create or replace function public.get_my_passkeys()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', p.id,
    'credentialId', p.credential_id,
    'deviceId', d.id,
    'deviceLabel', coalesce(d.device_name, p.device_label, 'هاتف الموظف'),
    'status', case
      when p.status = 'revoked' then 'revoked'
      else coalesce(d.status, 'pending')
    end,
    'trusted', p.status = 'active' and p.trusted and d.status = 'active',
    'deviceType', p.credential_device_type,
    'backedUp', p.credential_backed_up,
    'lastUsedAt', greatest(p.last_used, d.last_used_at),
    'createdAt', p.created_at,
    'approvedAt', d.approved_at,
    'rejectionReason', d.rejection_reason
  ) order by p.created_at desc), '[]'::jsonb)
  from public.passkey_credentials p
  left join lateral (
    select ed.*
    from public.employee_devices ed
    where ed.employee_id = p.employee_id
      and ed.user_id = p.user_id
      and ed.credential_id = p.credential_id
    order by
      case ed.status
        when 'active' then 1 when 'pending' then 2 when 'blocked' then 3
        when 'replaced' then 4 else 5
      end,
      ed.registered_at desc
    limit 1
  ) d on true
  where p.user_id = auth.uid()
    and p.employee_id = public.current_employee_id();
$$;

revoke all on function public.get_my_passkeys() from public, anon, authenticated;
grant execute on function public.get_my_passkeys() to authenticated;

commit;
