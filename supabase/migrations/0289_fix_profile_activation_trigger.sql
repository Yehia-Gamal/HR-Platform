-- Migration 0288: إصلاح trigger حماية profiles ليسمح بمسارات التفعيل المشروعة.

-- المشكلة: tg_profiles_protect_sensitive كان يمنع تحديث status/temporary_password
-- في أي سياق غير full-access — بما فيها:
--   1) service_role (Edge Functions مثل admin-set-password): ليس لها auth.uid()
--      فعائدها current_is_full_access()=false دائماً — كانت خطوة التفعيل
--      admin_activate_employee_after_password_set تفشل بصمت ويبقى الموظف pending.
--   2) الموظف نفسه عند أول ضبط كلمة مرور (activate_employee_after_first_login)
--      من الويب/الموبايل — موظف عادي غير full-access.
-- النتيجة: حسابات تظهر «نشط» (employees.status=active) بينما profiles.status
-- يبقى pending وtemporary_password=true، فيفشل فهم حالتها في لوحة الإدارة.
--
-- الإصلاح:
--   - service_role تمر مباشرة (مسار الخادم الموثوق — Edge Functions).
--   - غير المخوّل يُسمح له فقط بـ«التفعيل الذاتي»: على ملفه هو نفسه، تغيير
--     status من حالة ما قبل التفعيل إلى 'active' ومسح temporary_password.
--     يبقى تغيير role_id/employee_id/غير ذلك محظوراً على الجميع غير المخوّلين.

create or replace function public.tg_profiles_protect_sensitive()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_self_activation boolean;
begin
  -- السياقات الموثوقة تمر مباشرة. لا نستخدم current_user هنا لأنه داخل دالة
  -- security definer يعود باسم المالك (postgres) دائماً — بل نستخدم auth.role()
  -- المستخرجة من JWT الطلب (نمط مطبّق في 0026/0033).
  if auth.role() = 'service_role'
     or public.current_is_full_access()
     or public.has_permission('profiles.manage') then
    return new;
  end if;

  -- الحقول الأكثر حساسية محظورة على أي مستخدم غير مخوّل مهما كان.
  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'not authorized to change primary_role_id' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'not authorized to change employee_id' using errcode = '42501';
  end if;

  -- التفعيل الذاتي: الموظف يفعّل ملفه بنفسه بعد أول ضبط كلمة مرور
  -- (activate_employee_after_first_login من الويب/الموبايل) — المسار الوحيد
  -- المسموح لغير المخوّل لتغيير status/temporary_password.
  v_self_activation :=
       new.id = auth.uid()
       and old.status in ('pending', 'invited', 'onboarding', 'draft')
       and new.status = 'active'
       and new.temporary_password = false;

  if new.status is distinct from old.status and not v_self_activation then
    raise exception 'not authorized to change status' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password and not v_self_activation then
    raise exception 'not authorized to change temporary_password' using errcode = '42501';
  end if;

  return new;
end;
$$;

comment on function public.tg_profiles_protect_sensitive() is
  'يمنع غير المصرّح لهم من تعديل الأعمدة الحساسة في profiles (role_id, status, employee_id, temporary_password)، مع السماح بـ: service_role، وذوي full-access/profiles.manage، والتفعيل الذاتي للموظف على ملفه (pending→active + مسح العلم المؤقت).';
