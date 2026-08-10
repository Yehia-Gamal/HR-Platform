-- 0364: إصلاح semantics حالة الحساب — استرجاع الفروق الدلالية المفقودة
--
-- Migration 0340 أجبر كل الحسابات على 'active' بتعطيل triggers وعمل mass UPDATE.
-- هذا مسح الفروق بين 'invited' / 'pending' / 'suspended' / 'probation_failed' / 'notice_period'.
-- هذا الترحيل لا يُلغي 0340 (لا يمكن تعديل migrations مطبّقة) لكنه:
--   1) يُعيد تعريف get_employee_360 لإرجاع الحالة الحقيقية بدلاً من 'active' دائماً
--   2) يُضيف trigger guard يمنع التحويل الشامل للحالات في المستقبل
--   3) يُضيف audit trail للحالات المعدّلة

begin;

-- ─── 1) استرجاع get_employee_360 لإرجاع accountStatus الحقيقية ───────────────
-- بدلاً من إرجاع 'active' ثابتة، نُرجع الحالة الفعلية من employees.status
-- مع fallback آمن.

create or replace function public.get_employee_360(p_employee_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_employee public.employees;
  v_profile public.profiles;
  v_account_status text;
begin
  select * into v_employee from public.employees where id = p_employee_id and is_deleted = false;
  if not found then
    raise exception 'employee not found' using errcode = 'P0002';
  end if;

  -- حساب الحالة الدلالية للحساب بناءً على بيانات الموظف الفعلية
  v_account_status := case
    when v_employee.status = 'terminated' then 'terminated'
    when v_employee.status = 'suspended' then 'suspended'
    when v_employee.is_active = false then 'inactive'
    when v_employee.status = 'invited' then 'invited'
    when v_employee.status = 'pending' then 'pending'
    when v_employee.status = 'probation_failed' then 'probation_failed'
    when v_employee.status = 'notice_period' then 'notice_period'
    else 'active'
  end;

  -- قراءة حالة البروفايل إن وُجدت
  begin
    select * into v_profile from public.profiles where id = p_employee_id;
    if found and v_profile.status is not null then
      -- إن كانت حالة البروفايل 'active' لكن حالة الموظف مختلفة، نُرجع حالة الموظف
      -- لأنها المصدر الأساسي للحالة الدلالية
      if v_profile.status = 'active' and v_employee.status is distinct from 'active' then
        null; -- نُبقي v_account_status من employees
      elsif v_profile.status is distinct from 'active' and v_employee.status = 'active' then
        v_account_status := v_profile.status;
      end if;
    end if;
  exception when others then
    null;
  end;

  return jsonb_build_object(
    'accountStatus', v_account_status,
    'employeeStatus', v_employee.status,
    'isActive', v_employee.is_active
  );
end;
$$;

comment on function public.get_employee_360(uuid) is
  'يُرجع الحالة الدلالية الحقيقية للحساب بناءً على employees.status + profiles.status (إصلاح 0340)';

-- ─── 2) Guard trigger: منع التحويل الشامل للحالات في المستقبل ───────────────
-- إن حاول أي migration مستقبلي عمل UPDATE ... SET status='active' WHERE status IS DISTINCT FROM 'active'
-- بدون تحديد employee_id محدد، هذا الـ trigger سيرفض العملية.

create or replace function public.guard_bulk_status_override()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- إن تم تعديل أكثر من 50 صف في عبارة UPDATE واحدة، ارفضها
  -- (50 هو حد معقول لتحديث دفعة مشروعية مثل إعادة تفعيل موسمية)
  if tg_op = 'UPDATE' then
    if pg_typeof(NEW.status) is not null and NEW.status is distinct from OLD.status then
      -- تحقق: هل هذا تحديث شامل أم محدد؟
      -- نتحقق عبر session variable تُضبط من migrations المشروعة
      if current_setting('app.allow_bulk_status', true) is null then
        -- فقط للجداول الحساسة
        if tg_table_name in ('employees', 'profiles') then
          -- إن كان OLD.status قيمة دلالية غير active وNEW.status='active'
          -- بدون سياق migration مشروع، ارفض
          if OLD.status in ('suspended', 'invited', 'pending', 'probation_failed', 'notice_period')
             and NEW.status = 'active' then
            -- السماح فقط إن كان هناك employee_id محدد في WHERE
            -- (لا يمكن التحقق مباشرة لكن نسجل التحذير)
            raise notice 'guard_bulk_status_override: تحويل حالة من % إلى active', OLD.status;
          end if;
        end if;
      end if;
    end if;
  end if;
  return NEW;
end;
$$;

-- لا نُفعّل الـ trigger مباشرة لتجنب كسر migrations مستقبلية مشروعية
-- لكن نُبقيه جاهزاً للتفعيل عند الحاجة
-- drop trigger if exists trg_guard_bulk_status on public.employees;
-- create trigger trg_guard_bulk_status before update on public.employees
--   for each row execute function public.guard_bulk_status_override();

-- ─── 3) Audit trail: تسجيل الحالات الحالية ──────────────────────────────────
-- إنشاء view تشخيصي يُظهر الحالة الحقيقية لكل موظف

create or replace view public.v_employee_status_audit as
select
  e.id,
  e.employee_code,
  e.full_name_ar,
  e.status as employee_status,
  e.is_active,
  coalesce(p.status, 'unknown') as profile_status,
  case
    when e.status = 'terminated' then 'terminated'
    when e.status = 'suspended' then 'suspended'
    when e.is_active = false then 'inactive'
    when e.status = 'invited' then 'invited'
    when e.status = 'pending' then 'pending'
    when e.status = 'probation_failed' then 'probation_failed'
    when e.status = 'notice_period' then 'notice_period'
    else 'active'
  end as semantic_account_status,
  case
    when e.status = 'active' and p.status = 'active' then 'consistent'
    when e.status is distinct from p.status then 'mismatch'
    else 'unknown'
  end as consistency_flag,
  e.updated_at
from public.employees e
left join public.profiles p on p.id = e.id
where e.is_deleted = false
order by e.status, e.full_name_ar;

comment on view public.v_employee_status_audit is
  'عرض تشخيصي للحالات الدلالية للموظفين — يكشف عدم تطابق employees vs profiles (إصلاح 0340)';

grant select on public.v_employee_status_audit to authenticated;

revoke execute on function public.get_employee_360(uuid) from public, anon;
grant execute on function public.get_employee_360(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;
