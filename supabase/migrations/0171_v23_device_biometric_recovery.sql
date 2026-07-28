-- Migration 0169: V23 Agent-03 — Device biometric recovery & admin revocation
-- يضيف: auto_revoked إلى CHECK، عمود revocation_source، تنظيف جلسات،
-- إلغاء إداري، طلب استبدال ذاتي، عرض حالة الجهاز، عرض جميع الأجهزة.
-- Rollback: DROP the new functions, re-CREATE the old CHECK without auto_revoked,
--   DROP the revocation_source column.

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Expand CHECK to include 'auto_revoked' + add revocation_source column
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.employee_devices
  drop constraint if exists employee_devices_status_check;

alter table public.employee_devices
  add constraint employee_devices_status_check
  check (status in ('pending','active','blocked','revoked','replaced','auto_revoked'));

alter table public.employee_devices
  add column if not exists revocation_source text;

comment on column public.employee_devices.revocation_source is
  'مصدر الإلغاء: admin | employee | replacement | system';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Internal helper: cleanup user sessions & push subscriptions
--    SECURITY DEFINER — never callable externally.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public._cleanup_user_sessions_and_push(
  p_user_id uuid,
  p_reason text default 'device_revoked'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- حذف الجلسات النشطة
  delete from auth.sessions where user_id = p_user_id;
  -- حذف refresh tokens
  delete from auth.refresh_tokens where user_id = p_user_id::text;
  -- تعطيل اشتراكات الدفع
  update public.push_subscriptions
  set is_active = false, updated_at = now()
  where user_id = p_user_id and is_active = true;
end;
$$;

-- لا يُستدعى من أي دور — داخلي فقط
revoke all on function public._cleanup_user_sessions_and_push(uuid, text)
  from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3. Updated trigger: auto-replace sets revocation_source
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_fn_employee_devices_auto_replace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- فقط عند إدراج جهاز بحالة active — لا يُستبدل عند pending/blocked
  if NEW.status = 'active' then
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        revocation_source = 'replacement',
        metadata = metadata || jsonb_build_object('replacedByDeviceInsert', true)
    where employee_id = NEW.employee_id
      and id <> NEW.id
      and status = 'active';
  end if;
  return NEW;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4. Updated approve_device — revocation_source on replaced + session cleanup
-- ═══════════════════════════════════════════════════════════════════════════════

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
  v_old_user_id uuid;
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
    -- حفظ user_id القديم للجهاز النشط السابق (لتنظيف الجلسات عند تغيير المستخدم)
    select user_id into v_old_user_id
    from public.employee_devices
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active'
    limit 1;

    -- تعطيل أي جهاز active آخر لنفس الموظف
    update public.employee_devices
    set status = 'replaced',
        revoked_at = now(),
        revocation_source = 'replacement',
        metadata = metadata || jsonb_build_object('replacedByApproval', p_device_id)
    where employee_id = v_device.employee_id
      and id <> p_device_id
      and status = 'active';

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null,
        revocation_source = null
    where id = p_device_id;

    -- تنظيف الجلسات إن تغيّر المستخدم
    if v_old_user_id is not null and v_old_user_id <> v_device.user_id then
      perform public._cleanup_user_sessions_and_push(v_old_user_id, 'device_replaced');
    end if;
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5. admin_revoke_device — إلغاء إداري لجهاز نشط
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_revoke_device(
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

  if v_device.status not in ('active', 'pending') then
    raise exception 'device is not in a revocable state (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- إلغاء الجهاز
  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'admin'
  where id = p_device_id;

  -- إلغاء بيانات اعتماد البصمة المرتبطة
  update public.passkey_credentials
  set status = 'revoked', trusted = false, updated_at = now()
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'active';

  -- تنظيف الجلسات واشتراكات الدفع
  perform public._cleanup_user_sessions_and_push(v_device.user_id, 'admin_revoke');

  perform public.log_security_event(
    'device.admin_revoked',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'deviceName', v_device.device_name,
      'platform', v_device.platform
    )
  );

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'revoked',
    'sessionsCleared', true
  );
end;
$$;

revoke all on function public.admin_revoke_device(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_revoke_device(uuid, text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6. request_device_replacement — طلب استبدال ذاتي (فقدان هاتف)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.request_device_replacement(
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid := public.current_employee_id();
  v_user_id uuid := auth.uid();
  v_revoked_count int;
begin
  if v_employee_id is null or v_user_id is null then
    raise exception 'authenticated employee required' using errcode = '42501';
  end if;

  -- إلغاء جميع الأجهزة النشطة
  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'employee'
  where employee_id = v_employee_id
    and status = 'active';

  get diagnostics v_revoked_count = row_count;

  if v_revoked_count = 0 then
    raise exception 'no active device to replace' using errcode = 'P0002';
  end if;

  -- إلغاء بيانات الاعتماد
  update public.passkey_credentials
  set status = 'revoked', trusted = false, updated_at = now()
  where employee_id = v_employee_id
    and user_id = v_user_id
    and status = 'active';

  -- تنظيف الجلسات
  perform public._cleanup_user_sessions_and_push(v_user_id, 'device_replacement');

  perform public.log_security_event(
    'device.replacement_requested',
    'high', 'allowed',
    null,
    jsonb_build_object(
      'employeeId', v_employee_id,
      'reason', p_reason,
      'revokedDevices', v_revoked_count
    )
  );

  return jsonb_build_object(
    'ok', true,
    'revokedDevices', v_revoked_count,
    'canRegisterNew', true
  );
end;
$$;

revoke all on function public.request_device_replacement(text) from public, anon, authenticated;
grant execute on function public.request_device_replacement(text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7. get_my_device_status — حالة جهاز الموظف الحالي
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_my_device_status()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'hasActiveDevice', exists(
      select 1 from public.employee_devices
      where employee_id = public.current_employee_id()
        and user_id = auth.uid()
        and status = 'active'
    ),
    'canRegisterNew', not exists(
      select 1 from public.employee_devices
      where employee_id = public.current_employee_id()
        and user_id = auth.uid()
        and status = 'pending'
    )
  );
$$;

revoke all on function public.get_my_device_status() from public, anon, authenticated;
grant execute on function public.get_my_device_status() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8. get_all_devices_admin — عرض جميع الأجهزة (للمسؤول)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_all_devices_admin(
  p_status_filter text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not public.current_is_full_access() then '[]'::jsonb
    else coalesce(jsonb_agg(jsonb_build_object(
      'id', d.id,
      'employeeId', d.employee_id,
      'employeeName', e.full_name_ar,
      'employeeCode', e.employee_code,
      'employeePhotoUrl', e.photo_url,
      'deviceName', d.device_name,
      'platform', d.platform,
      'status', d.status,
      'registeredAt', d.registered_at,
      'lastUsedAt', d.last_used_at,
      'revokedAt', d.revoked_at,
      'revocationSource', d.revocation_source,
      'approvedBy', d.approved_by,
      'rejectionReason', d.rejection_reason,
      'metadata', d.metadata
    ) order by d.registered_at desc), '[]'::jsonb)
  end
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where (p_status_filter is null or d.status = p_status_filter);
$$;

revoke all on function public.get_all_devices_admin(text) from public, anon, authenticated;
grant execute on function public.get_all_devices_admin(text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9. Updated get_pending_devices_admin — adds revocationSource
-- ═══════════════════════════════════════════════════════════════════════════════

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
    'employeeName', e.full_name_ar,
    'employeeCode', e.employee_code,
    'employeePhotoUrl', e.photo_url,
    'deviceName', d.device_name,
    'platform', d.platform,
    'status', d.status,
    'registeredAt', d.registered_at,
    'lastUsedAt', d.last_used_at,
    'rejectionReason', d.rejection_reason,
    'revocationSource', d.revocation_source,
    'metadata', d.metadata
  ) order by d.registered_at desc), '[]'::jsonb)
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where d.status in ('pending', 'blocked')
    and public.current_is_full_access();
$$;

revoke all on function public.get_pending_devices_admin() from public, anon, authenticated;
grant execute on function public.get_pending_devices_admin() to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10. Updated get_my_passkeys — adds revocationSource, canResubmit
-- ═══════════════════════════════════════════════════════════════════════════════

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
    'rejectionReason', d.rejection_reason,
    'revocationSource', d.revocation_source,
    'canResubmit', coalesce(d.status in ('blocked', 'revoked'), false)
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. Fix trg_fn_role_assignment_notify — references roles.name but column is name_ar
--     (originally defined in 0160, broken since roles table uses name_ar/name_en not name)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal',
        'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal',
        'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. Fix trg_fn_role_assignment_notify — roles.name → roles.name_ar
--     Original in 0160 references non-existent column `name`;
--     the actual column (defined in 0002) is `name_ar`.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal',
        'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal',
        'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11. Fix trg_fn_role_assignment_notify — references roles.name but column is name_ar
--     (original in 0160, broken since roles table has name_ar/name_en, not name)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_fn_role_assignment_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee_id uuid;
  v_role_name text;
  v_user_id uuid;
begin
  if TG_OP = 'INSERT' then
    v_user_id := NEW.user_id;
    select name_ar into v_role_name from public.roles where id = NEW.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم منحك دوراً جديداً',
        'تم منحك دور «' || coalesce(v_role_name, 'غير معروف') || '» في النظام.',
        'system', 'normal',
        'role', NEW.role_id,
        jsonb_build_object('kind', 'role_granted', 'roleName', v_role_name, 'roleId', NEW.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;

  elsif TG_OP = 'DELETE' then
    v_user_id := OLD.user_id;
    select name_ar into v_role_name from public.roles where id = OLD.role_id;

    select p.employee_id into v_employee_id
    from public.profiles p where p.id = v_user_id and p.status = 'active';

    if v_employee_id is not null then
      insert into public.notifications(
        recipient_user_id, recipient_employee_id, title, body,
        category, priority, entity_type, entity_id, metadata, created_by
      ) values (
        v_user_id, v_employee_id,
        'تم سحب دور منك',
        'تم سحب دور «' || coalesce(v_role_name, 'غير معروف') || '» من حسابك.',
        'system', 'normal',
        'role', OLD.role_id,
        jsonb_build_object('kind', 'role_revoked', 'roleName', v_role_name, 'roleId', OLD.role_id),
        coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000')
      );
    end if;
  end if;

  return coalesce(NEW, OLD);
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- Reload PostgREST schema cache
-- ═══════════════════════════════════════════════════════════════════════════════

notify pgrst, 'reload schema';

commit;
