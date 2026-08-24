-- ============================================================================
-- 0468: هاتف واحد نشط لكل موظف — إصلاح ثغرة تعدد الأجهزة النشطة
-- ============================================================================
-- المشكلة (رصد إنتاجي): 20 موظفاً لديهم أكثر من جهاز بحالة active.
-- السبب: trg_employee_devices_auto_replace كان يعمل على INSERT فقط، بينما
-- تتفعّل الأجهزة أيضاً عبر UPDATE (موافقة pending→active، مسارات ترميم،
-- reinstatements) — فتراكمت أجهزة نشطة متعددة لنفس الموظف.
--
-- هذا الملف:
--   1) ترميم البيانات: لكل موظف يُبقى الجهاز النشط الأحدث استخداماً
--      (last_used_at ثم registered_at) ويُوضع الباقي replaced.
--   2) إعادة بناء الزناد ليعمل على INSERT OR UPDATE عندما تصبح الحالة
--      active — مع WHEN لمنع العودية — فلا يتعدى الجهاز النشط واحداً
--      لكل موظف من أي مسار مستقبلاً.
-- ============================================================================

begin;

-- ─── 1) ترميم: جهاز نشط واحد لكل موظف (الأحدث استخداماً) ───
with ranked as (
  select id,
         row_number() over (
           partition by employee_id
           order by coalesce(last_used_at, registered_at) desc, id desc
         ) as rn
  from public.employee_devices
  where status = 'active'
)
update public.employee_devices d
set status = 'replaced',
    revoked_at = now(),
    metadata = coalesce(d.metadata, '{}'::jsonb)
             || jsonb_build_object('autoReplacedMultiActive', true, 'replacedByMigration', '0468')
from ranked r
where d.id = r.id
  and r.rn > 1;

-- ─── 2) الزناد الشامل: INSERT أو UPDATE عند الوصول إلى active ───
create or replace function public.trg_fn_employee_devices_auto_replace()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- إبعاد كل جهاز آخر نشط لنفس الموظف — الجهاز الحالي هو الوحيد النشط.
  update public.employee_devices
  set status = 'replaced',
      revoked_at = now(),
      metadata = coalesce(metadata, '{}'::jsonb)
               || jsonb_build_object('replacedByDevice', NEW.id)
  where employee_id = NEW.employee_id
    and id <> NEW.id
    and status = 'active';
  return NEW;
end;
$$;

drop trigger if exists trg_employee_devices_auto_replace on public.employee_devices;
create trigger trg_employee_devices_auto_replace
  after insert or update of status on public.employee_devices
  for each row
  when (new.status = 'active')
execute function public.trg_fn_employee_devices_auto_replace();

commit;

-- ملاحظة: WHEN (new.status = 'active') يمنع العودية — تحديثاتنا للصفوف
-- الأخرى تضبطها على 'replaced' فلا يعاد إطلاق الزناد عليها.
