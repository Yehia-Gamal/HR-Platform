-- 0229: V24 — Keep old device active until new one is approved.
--
-- Problem:
--   request_device_replacement immediately revoked ALL active devices,
--   locking the employee out until admin approves the replacement
--   (no biometric device → can't punch attendance).
--
-- Fix:
--   Don't revoke the old device. The V18 device-approval workflow already
--   handles replacement when approve_device() runs — it sets the old active
--   device's status to 'replaced' (lines 127–134 of 0171). All we need is
--   a notification to admins so they know to expect a pending device.
--
-- Changes:
--   1. request_device_replacement — no longer revokes active devices.
--      Logs the request, notifies admins, and returns ok so the employee
--      can install on a new phone and register while the old one still works.

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. request_device_replacement — keep old device active
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
begin
  if v_employee_id is null or v_user_id is null then
    raise exception 'authenticated employee required' using errcode = '42501';
  end if;

  -- V24: Do NOT revoke active devices. The old device stays usable until
  -- admin approves the new one. approve_device() (0171) will handle
  -- replacement when it sets the new device to 'active'.

  -- Log the request for audit and admin notification
  perform public.log_security_event(
    'device.replacement_requested',
    'high', 'allowed',
    null,
    jsonb_build_object(
      'employeeId', v_employee_id,
      'reason', p_reason
    )
  );

  return jsonb_build_object(
    'ok', true,
    'message', 'جهازك الحالي سيبقى نشطاً حتى اعتماد الجهاز الجديد من قبل المسؤول.'
  );
end;
$$;

revoke all on function public.request_device_replacement(text) from public, anon, authenticated;
grant execute on function public.request_device_replacement(text) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. notify_admin_on_replacement_request — trigger on employee_devices insert
--    to alert admins of pending replacement.
-- ═══════════════════════════════════════════════════════════════════════════════

create or replace function public.tg_device_replacement_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if NEW.status = 'pending' and exists (
    select 1 from public.employee_devices
    where employee_id = NEW.employee_id
      and id <> NEW.id
      and status = 'active'
  ) then
    perform public.log_security_event(
      'device.replacement_pending_approval',
      'medium', 'allowed',
      NEW.device_identifier_hash,
      jsonb_build_object(
        'deviceId', NEW.id,
        'employeeId', NEW.employee_id,
        'deviceName', NEW.device_name,
        'hasExistingActiveDevice', true
      )
    );
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_device_replacement_notify on public.employee_devices;
create trigger trg_device_replacement_notify
  after insert on public.employee_devices
  for each row
  when (NEW.status = 'pending')
  execute function public.tg_device_replacement_notify();

