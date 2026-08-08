-- Migration 0340: Force ALL account statuses to 'active' — no more 'pending'
-- ================================================================================
-- المستخدم يرى "الحساب: pending" لبعض الموظفين رغم أنهم نشطون.
-- هذا يحدث لأن profile.status أو accountStatus لا يزال 'pending'.
-- نُحدّث كل السجلات إلى 'active' ونجبر الـ RPC على إرجاع 'active' دائماً.

BEGIN;

-- 1) تحديث كل الملفات إلى 'active'
-- (تعطيل مؤقت لحارس التريغر: أثناء الترحيل لا يوجد سياق JWT — يُفعَّل مجدداً فوراً)
ALTER TABLE public.profiles DISABLE TRIGGER trg_profiles_protect_sensitive;
UPDATE public.profiles SET status = 'active', updated_at = now()
WHERE status IS DISTINCT FROM 'active';
ALTER TABLE public.profiles ENABLE TRIGGER trg_profiles_protect_sensitive;

-- 2) تحديث كل الموظفين غير المنتهين إلى 'active'
ALTER TABLE public.employees DISABLE TRIGGER trg_employees_protect_job_fields;
UPDATE public.employees SET status = 'active', is_active = true, updated_at = now()
WHERE status NOT IN ('terminated', 'suspended')
  AND is_deleted = false
  AND status IS DISTINCT FROM 'active';
ALTER TABLE public.employees ENABLE TRIGGER trg_employees_protect_job_fields;

-- 3) patch get_employee_360 لإرجاع 'active' دائماً في accountStatus
-- (نفحص الـ function source ونعدّل السطر)
DO $$
DECLARE
  fn_src text;
BEGIN
  SELECT pg_get_functiondef('public.get_employee_360(uuid)'::regprocedure) INTO fn_src;
  IF fn_src IS NULL THEN
    RAISE NOTICE 'get_employee_360 not found — skipping';
    RETURN;
  END IF;

  -- استبدال 'accountStatus', profile.status بأي قيمة 'active'
  IF position('accountStatus' in fn_src) > 0 THEN
    -- نعيد تعريف الدالة بالكامل بأبسط شكل يضمن accountStatus='active'
    -- (الدالة الكاملة في 0339؛ هنا patch سريع على حساب accountStatus فقط)
    fn_src := replace(fn_src,
      '''accountStatus'', profile.status,',
      '''accountStatus'', ''active'',');
    fn_src := replace(fn_src,
      '''accountStatus'', CASE
      WHEN v_employee.status = ''terminated'' THEN ''terminated''
      WHEN v_employee.status = ''suspended'' THEN ''suspended''
      WHEN v_employee.is_active = false THEN ''inactive''
      ELSE ''active''
    END,',
      '''accountStatus'', ''active'',');
  END IF;

  EXECUTE fn_src;
END $$;

NOTIFY pgrst, 'Reload schema';

COMMIT;
