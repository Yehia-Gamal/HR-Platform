-- 0291: إخفاء الأجهزة المنتهية من العرض الافتراضي + حذف نهائي إداري
-- ═══════════════════════════════════════════════════════════════════════
-- المشكلة:
--   get_all_devices_admin تعيد كل الأجهزة بما فيها الملغاة والمستبدلة
--   فتتراكم عشرات الأجهزة غير المفيدة في الواجهة بدون طريقة لإخفائها أو حذفها.
--
-- التغييرات:
--   1. get_all_devices_admin: باراميتر جديد p_include_terminated (default false)
--      — عند false: يعرض فقط pending/active/blocked
--      — عند true: يعرض كل الحالات (السلوك القديم)
--   2. admin_delete_device: RPC جديد يحذف نهائياً جهاز في حالة منتهية فقط
--      (revoked/replaced/auto_revoked) مع تسجيل حدث أمني
-- ═══════════════════════════════════════════════════════════════════════

begin;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. تحديث get_all_devices_admin — إخفاء المنتهية افتراضياً
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.get_all_devices_admin(
  p_status_filter text default null,
  p_include_terminated boolean default false
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
  where (p_status_filter is null or d.status = p_status_filter)
    and (
      p_include_terminated = true
      or d.status in ('pending', 'active', 'blocked')
    );
$$;

revoke all on function public.get_all_devices_admin(text, boolean) from public, anon, authenticated;
grant execute on function public.get_all_devices_admin(text, boolean) to authenticated;

-- إزالة التوقيع القديم (text) حتى لا يبقى overload غامض يكسر أي استدعاء بوسيط واحد
-- (الوظيفة الجديدة بباراميترات افتراضية تحل محله بالكامل).
drop function if exists public.get_all_devices_admin(text);

comment on function public.get_all_devices_admin(text, boolean) is
  'يعرض الأجهزة للإدارة. p_include_terminated=false (افتراضي) يخفي revoked/replaced/auto_revoked.';

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. admin_delete_device — حذف نهائي لجهاز منتهي فقط
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.admin_delete_device(
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

  -- لا يُسمح بحذف جهاز نشط أو معلق أو محظور (قابل لإعادة التفعيل)
  if v_device.status not in ('revoked', 'replaced', 'auto_revoked') then
    raise exception 'only terminated devices (revoked/replaced/auto_revoked) can be deleted (current: %)', v_device.status
      using errcode = '22023';
  end if;

  -- تسجيل حدث أمني قبل الحذف
  perform public.log_security_event(
    'device.admin_deleted',
    'high', 'allowed',
    v_device.device_identifier_hash,
    jsonb_build_object(
      'deviceId', p_device_id,
      'employeeId', v_device.employee_id,
      'deviceName', v_device.device_name,
      'platform', v_device.platform,
      'previousStatus', v_device.status,
      'reason', p_reason
    )
  );

  -- حذف بيانات اعتماد البصمة المرتبطة إن كانت منتهية ولا تربطها أجهزة أخرى
  delete from public.passkey_credentials
  where employee_id = v_device.employee_id
    and credential_id = v_device.credential_id
    and status = 'revoked'
    and not exists (
      select 1 from public.employee_devices ed
      where ed.credential_id = v_device.credential_id
        and ed.employee_id = v_device.employee_id
        and ed.id <> p_device_id
        and ed.status in ('pending', 'active', 'blocked')
    );

  -- حذف الجهاز نهائياً
  delete from public.employee_devices
  where id = p_device_id;

  return jsonb_build_object(
    'ok', true,
    'deviceId', p_device_id,
    'status', 'deleted'
  );
end;
$$;

revoke all on function public.admin_delete_device(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_delete_device(uuid, text) to authenticated;

comment on function public.admin_delete_device(uuid, text) is
  'حذف نهائي لجهاز في حالة منتهية فقط (revoked/replaced/auto_revoked). للـ full-access حصراً.';

notify pgrst, 'reload schema';

commit;
