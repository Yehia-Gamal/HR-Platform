-- =======================================================================
-- 0514: Allow background cron & postgres superuser in tg_profiles_protect_sensitive
-- =======================================================================

CREATE OR REPLACE FUNCTION public.tg_profiles_protect_sensitive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_self_activation boolean;
begin
  -- السياقات الموثوقة: service_role أو كرون النظام (postgres/supabase_admin) أو ذوو الصلاحية الكاملة
  if auth.role() = 'service_role'
     or current_user in ('postgres', 'supabase_admin')
     or session_user in ('postgres', 'supabase_admin')
     or public.current_is_full_access()
     or public.has_permission('profiles.manage') then
    return new;
  end if;

  -- الحقول الأكثر حساسية محظورة على أي مستخدم غير مخوّل مهما كان.
  if new.primary_role_id is distinct from old.primary_role_id then
    raise exception 'غير مصرح بتغيير الدور الأساسي' using errcode = '42501';
  end if;
  if new.employee_id is distinct from old.employee_id then
    raise exception 'غير مصرح بتغيير معرّف الموظف' using errcode = '42501';
  end if;

  -- التفعيل الذاتي: الموظف يفعّل ملفه بنفسه بعد أول ضبط كلمة مرور
  v_self_activation :=
       new.id = auth.uid()
       and old.status in ('pending', 'invited', 'onboarding', 'draft')
       and new.status = 'active'
       and new.temporary_password = false;

  if new.status is distinct from old.status and not v_self_activation then
    raise exception 'غير مصرح لك بتغيير الحالة' using errcode = '42501';
  end if;
  if new.temporary_password is distinct from old.temporary_password and not v_self_activation then
    raise exception 'غير مصرح بتغيير كلمة المرور المؤقتة' using errcode = '42501';
  end if;

  return new;
end;
$function$;
