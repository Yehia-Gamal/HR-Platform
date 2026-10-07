-- 0614: إعفاء المسؤول العام (يحيى جمال السبع) من الغرامات نهائياً
-- =====================================================================
-- السبب: كان trigger tg_admin_immunity_employees_fn يفرض 
--   is_penalty_exempt := false دائماً على حساب المسؤول العام
-- الإصلاح: تعديل الـ trigger ليضع is_penalty_exempt := true
--   وإلغاء أي غرامات معلقة
-- =====================================================================

begin;

-- 1. تحديث trigger الحصانة الإدارية
create or replace function public.tg_admin_immunity_employees_fn()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if NEW.id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
     or NEW.phone_e164 in ('+201154869616', '01154869616')
     or NEW.employee_code in ('+201154869616', '01154869616')
     or NEW.user_id = '6f347a78-bb30-4ae5-8b07-2ecfc623f960'
     or NEW.full_name_ar ilike '%يحيى%جمال%' then
    -- الحساب نشط دائماً ولا يُوقف عن العمل نهائياً
    NEW.status := 'active';
    NEW.is_active := true;
    -- معفى دائماً من الغرامات: المسؤول العام للنظام
    NEW.is_penalty_exempt := true;
  end if;
  return NEW;
end;
$function$;

-- 2. إلغاء أي غرامات معلقة ليحيى
update instant_attendance_penalties
set status = 'cancelled',
    cancelled_reason = 'إعفاء دائم واستثناء قطعي - المسؤول العام للنظام (يحيى جمال السبع)',
    notes = coalesce(notes, '') || ' | إلغاء: المسؤول العام معفى دائماً من الغرامات',
    updated_at = now()
where employee_id = 'b452c987-ae08-4e12-8433-272cc66c85f9'
  and status in ('pending_payment', 'pending_escalation', 'escalated', 'doubled');

-- 3. تأكيد الإعفاء في سجل الموظف
update employees
set is_penalty_exempt = true,
    updated_at = now()
where id = 'b452c987-ae08-4e12-8433-272cc66c85f9';

commit;
