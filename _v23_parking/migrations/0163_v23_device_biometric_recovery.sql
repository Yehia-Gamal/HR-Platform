-- 0163: V23 Agent-03 — Device biometric recovery & admin revocation.
-- يضيف: auto_revoked للحالات، revocation_source، إلغاء إداري، طلب استبدال (هاتف مفقود)،
-- تنظيف الجلسات والـ FCM عند الإلغاء، عرض كل الأجهزة للمسؤول.

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1) توسيع CHECK constraint لإضافة auto_revoked
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.employee_devices
  drop constraint if exists employee_devices_status_check;

alter table public.employee_devices
  add constraint employee_devices_status_check
  check (status in ('pending','active','blocked','revoked','replaced','auto_revoked'));

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2) عمود مصدر الإلغاء
-- ═══════════════════════════════════════════════════════════════════════════════

alter table public.employee_devices
  add column if not exists revocation_source text;

comment on column public.employee_devices.revocation_source
  is 'مصدر الإلغاء: admin | employee | replacement | system';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 3) دالة مساعدة داخلية: تنظيف جلسات المستخدم و push subscriptions
--    تُستدعى عند إلغاء/استبدال جهاز لمنع الوصول من الجهاز القديم.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public._cleanup_user_sessions_and_push(
  p_user_id uuid,
  p_reason  text default 'device_revoked'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- حذف جلسات المستخدم (يفرض تسجيل دخول جديد)
  delete from auth.sessions where user_id = p_user_id;
  delete from auth.refresh_tokens where user_id = p_user_id;

  -- تعطيل اشتراكات Push (FCM) للمستخدم
  update public.push_subscriptions
  set is_active = false,
      updated_at = now()
  where user_id = p_user_id
    and is_active = true;

  -- تسجيل حدث أمني
  perform public.log_security_event(
    'device.sessions_cleaned',
    'high', 'allowed',
    p_user_id::text,
    jsonb_build_object('reason', p_reason)
  );
end;
$$;

-- دالة داخلية — لا يستدعيها المستخدم مباشرة
revoke all on function public._cleanup_user_sessions_and_push(uuid, text)
  from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 4) تحديث trigger الاستبدال التلقائي ← يسجّل revocation_source
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.trg_fn_employee_devices_auto_replace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.employee_devices
  set status = 'replaced',
      revoked_at = now(),
      revocation_source = 'replacement',
      metadata = metadata || jsonb_build_object('replacedByDeviceInsert', true)
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and status = 'active';
  return NEW;
end;
$$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 5) تحديث approve_device — تنظيف الجلسات عند الاستبدال + revocation_source
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
    -- حفظ user_id للجهاز القديم لتنظيف جلساته
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

    -- تنظيف جلسات المستخدم القديم إذا كان مختلفاً
    if v_old_user_id is not null and v_old_user_id <> v_device.user_id then
      perform public._cleanup_user_sessions_and_push(v_old_user_id, 'device_replaced');
    end if;

    update public.employee_devices
    set status = 'active',
        approved_by = auth.uid(),
        approved_at = now(),
        rejection_reason = null,
        revoked_at = null,
        revocation_source = null
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 6) إلغاء جهاز بواسطة المسؤول
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_revoke_device(
  p_device_id uuid,
  p_reason    text default null
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

  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'admin',
      rejection_reason = coalesce(nullif(trim(p_reason), ''), 'إلغاء إداري'),
      metadata = metadata || jsonb_build_object('revokedBy', auth.uid())
  where id = p_device_id;

  -- إلغاء credential المرتبط
  if v_device.credential_id is not null then
    update public.passkey_credentials
    set status = 'revoked', trusted = false, updated_at = now()
    where credential_id = v_device.credential_id
      and employee_id = v_device.employee_id
      and status = 'active';
  end if;

  -- تنظيف جلسات المستخدم
  if v_device.user_id is not null then
    perform public._cleanup_user_sessions_and_push(v_device.user_id, 'admin_revoke');
  end if;

  perform public.log_security_event(
    'device.admin_revoked', 'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'reason', p_reason,
      'revokedBy', auth.uid()
    )
  );

  return jsonb_build_object('ok', true, 'status', 'revoked');
end;
$$;

revoke all on function public.admin_revoke_device(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_revoke_device(uuid, text)
  to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 7) طلب استبدال جهاز (هاتف مفقود) — يستدعيها الموظف
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
  v_user_id     uuid := auth.uid();
  v_active_count int;
begin
  if v_user_id is null or v_employee_id is null then
    raise exception 'authenticated employee is required' using errcode = '42501';
  end if;

  -- إلغاء كل الأجهزة النشطة للموظف
  update public.employee_devices
  set status = 'revoked',
      revoked_at = now(),
      revocation_source = 'employee',
      metadata = metadata || jsonb_build_object(
        'replacementReason', coalesce(nullif(trim(p_reason), ''), 'فقدان الهاتف'),
        'replacementRequestedAt', now()
      )
  where employee_id = v_employee_id
    and status = 'active'
  returning 1 into v_active_count;

  if v_active_count is null then
    raise exception 'no active device found to replace' using errcode = 'P0002';
  end if;

  -- إلغاء credentials المرتبطة
  update public.passkey_credentials
  set status = 'revoked', trusted = false, updated_at = now()
  where employee_id = v_employee_id
    and user_id = v_user_id
    and status = 'active';

  -- تنظيف الجلسات (يفرض تسجيل دخول جديد على الجهاز الجديد)
  perform public._cleanup_user_sessions_and_push(v_user_id, 'device_replacement');

  perform public.log_security_event(
    'device.replacement_requested', 'high', 'allowed',
    v_employee_id::text,
    jsonb_build_object(
      'employeeId', v_employee_id,
      'reason', p_reason
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', 'تم إلغاء الجهاز القديم. يمكنك تسجيل جهاز جديد.'
  );
end;
$$;

revoke all on function public.request_device_replacement(text)
  from public, anon, authenticated;
grant execute on function public.request_device_replacement(text)
  to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 8) حالة الجهاز الحالي للموظف (يستدعيها التطبيق)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_my_device_status()
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select jsonb_build_object(
      'hasActiveDevice', true,
      'deviceId', d.id,
      'deviceName', d.device_name,
      'status', d.status,
      'approvedAt', d.approved_at,
      'lastUsedAt', d.last_used_at,
      'canRegisterNew', false
    )
    from public.employee_devices d
    where d.employee_id = public.current_employee_id()
      and d.user_id = auth.uid()
      and d.status = 'active'
    limit 1),
    jsonb_build_object(
      'hasActiveDevice', false,
      'canRegisterNew', not exists (
        select 1 from public.employee_devices
        where employee_id = public.current_employee_id()
          and status = 'pending'
      )
    )
  );
$$;

revoke all on function public.get_my_device_status()
  from public, anon, authenticated;
grant execute on function public.get_my_device_status()
  to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 9) تحديث get_pending_devices_admin — إضافة revocationSource
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 10) تحديث get_my_passkeys — إضافة revocationSource + canResubmit
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
    'canResubmit', (d.status = 'blocked' or d.status = 'revoked')
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

-- ═══════════════════════════════════════════════════════════════════════════════
-- 11) عرض كل الأجهزة للمسؤول (مع فلترة اختيارية بالحالة)
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_all_devices_admin(
  p_status text default null
)
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
    'approvedAt', d.approved_at,
    'approvedBy', d.approved_by,
    'lastUsedAt', d.last_used_at,
    'revokedAt', d.revoked_at,
    'rejectionReason', d.rejection_reason,
    'revocationSource', d.revocation_source,
    'metadata', d.metadata
  ) order by d.registered_at desc), '[]'::jsonb)
  from public.employee_devices d
  join public.employees e on e.id = d.employee_id
  where public.current_is_full_access()
    and (p_status is null or d.status = p_status);
$$;

revoke all on function public.get_all_devices_admin(text)
  from public, anon, authenticated;
grant execute on function public.get_all_devices_admin(text)
  to authenticated;

commit;
