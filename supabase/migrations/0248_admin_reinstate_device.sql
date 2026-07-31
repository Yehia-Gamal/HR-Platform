-- 0248: استعادة دالة إعادة تفعيل الجهاز الإدارية (admin_reinstate_device).
-- ═══════════════════════════════════════════════════════════════════════
-- الخلفية: الدالة مصمّمة ومُغطّاة باختبار 0086 (دورة الحياة الكاملة) لكن
-- migration إنشائها فُقدت مراراً أثناء إعادة ضبط الفرع في جلسات متوازية.
-- هذه النسخة تعيدها وفق العقد الذي يفرضه الاختبار.
--
-- العقد (0086):
--   • SECURITY DEFINER + search_path ثابت.
--   • full-access حصراً (غير ذلك 42501).
--   • الجهاز يجب أن يكون في حالة قابلة لإعادة التفعيل (revoked/auto_revoked/
--     blocked)؛ أي حالة أخرى → 22023 (state-machine).
--   • جهاز غير موجود → P0002.
--   • عند النجاح: status='pending'، مسح revoked_at و revocation_source،
--     وضع رايات metadata (reinstated / reinstatedBy / reinstateReason)،
--     وتسجيل حدث أمني device.reinstated. تُكمَّل الدورة عبر approve_device.
-- ═══════════════════════════════════════════════════════════════════════

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
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'reinstated', true,
        'reinstatedAt', now(),
        'reinstatedBy', auth.uid(),
        'reinstateReason', p_reason,
        'previousStatus', v_device.status
      )
  where id = p_device_id;

  -- إعادة تنشيط بيانات اعتماد البصمة المرتبطة (بلا ثقة حتى تُعتمد من جديد).
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

comment on function public.admin_reinstate_device(uuid, text) is
  'يعيد جهازاً مُلغى (revoked/auto_revoked/blocked) إلى pending للمراجعة؛ للـ full-access حصراً. يمسح آثار الإلغاء، يسجّل device.reinstated، ثم يُكمَّل عبر approve_device.';

revoke all on function public.admin_reinstate_device(uuid, text)
  from public, anon, authenticated;
grant execute on function public.admin_reinstate_device(uuid, text)
  to authenticated;

commit;
