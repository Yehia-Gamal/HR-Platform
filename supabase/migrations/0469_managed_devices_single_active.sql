-- ============================================================================
-- 0469: هاتف واحد نشط لكل موظف — تعميم الإصلاح على managed_devices
-- ============================================================================
-- 0468 غطّى employee_devices (جدول الموافقات). لكن تسجيل الأجهزة يُخزَّن في
-- managed_devices — وفحص البصمة (punch_attendance_local_biometric_v1) يشترط
-- جهازاً نشطاً فيها، فتعدد النشط يسمح بالبصمة من أكثر من هاتف.
--
--   1) ترميم: لكل موظف يُبقى الجهاز النشط الأحدث ظهوراً (last_seen_at)
--      ويُسحب الباقي (revoked + سبب واضح).
--   2) زناد INSERT OR UPDATE OF status WHEN active — يسحب باقي أجهزة
--      الموظف من أي مسار تفعيل (تسجيل جديد، عودة retired، ترقية).
-- ============================================================================

begin;

-- ─── 1) ترميم البيانات ───
with ranked as (
  select id,
         row_number() over (
           partition by employee_id
           order by coalesce(last_seen_at, first_seen_at, created_at) desc, id desc
         ) as rn
  from public.managed_devices
  where status = 'active'
)
update public.managed_devices d
set status = 'revoked',
    revoked_at = now(),
    revoke_reason = 'single_device_policy_0469',
    metadata = coalesce(d.metadata, '{}'::jsonb) || jsonb_build_object('autoRevokedMultiActive', true)
from ranked r
where d.id = r.id
  and r.rn > 1;

-- ─── 2) الزناد الشامل ───
create or replace function public.trg_fn_managed_devices_single_active()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.managed_devices
  set status = 'revoked',
      revoked_at = now(),
      revoke_reason = 'superseded_by_device_' || NEW.id::text
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and status = 'active';
  return NEW;
end;
$$;

drop trigger if exists trg_managed_devices_single_active on public.managed_devices;
create trigger trg_managed_devices_single_active
  after insert or update of status on public.managed_devices
  for each row
  when (new.status = 'active')
execute function public.trg_fn_managed_devices_single_active();

commit;
