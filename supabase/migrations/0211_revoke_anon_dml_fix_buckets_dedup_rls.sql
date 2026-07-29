-- تعزيز أمني — الجولة الثالثة
-- 1. سحب ALL من anon على جميع جداول وتسلسلات public
-- 2. سحب TRUNCATE/REFERENCES/TRIGGER من authenticated (TRUNCATE يتجاوز RLS!)
-- 3. ضبط الصلاحيات الافتراضية لمنع أي منح خطر مستقبلاً
-- 4. جعل bucket employee-avatars خاصاً + إصلاح سياساته
-- 5. حذف سياسات RLS مكررة/ميتة على public_holidays

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. REVOKE ALL من anon على جميع الجداول والتسلسلات
--    - لا يوجد أي RLS policy يستهدف anon (كلها authenticated)
--    - جميع الدوال المتاحة لـ anon هي SECURITY DEFINER
--    - Edge Functions تستخدم service_role داخلياً
--    ⇒ anon لا يحتاج أي صلاحية على الجداول
-- ═══════════════════════════════════════════════════════════════

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon;

-- ═══════════════════════════════════════════════════════════════
-- 2. سحب TRUNCATE / REFERENCES / TRIGGER من authenticated
--    TRUNCATE يتجاوز RLS بالكامل — أي مستخدم مسجّل يمكنه مسح جدول!
--    REFERENCES و TRIGGER لا يحتاجهما التطبيق.
-- ═══════════════════════════════════════════════════════════════

REVOKE TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA public FROM authenticated, anon;

-- ═══════════════════════════════════════════════════════════════
-- 3. صلاحيات افتراضية — حماية الجداول والتسلسلات الجديدة
-- ═══════════════════════════════════════════════════════════════

-- anon: لا شيء على الجداول والتسلسلات
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM anon;

-- authenticated: TRUNCATE / REFERENCES / TRIGGER ممنوعة
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 4. جعل bucket employee-avatars خاصاً + إصلاح السياسات
--    - حذف public_read (كانت تسمح لأي شخص بقراءة الصور)
--    - إضافة employee_avatars_select لـ authenticated فقط
--    - الإبقاء على سياسات _manage_ الحالية (full-access أو
--      people.employee.create أو المجلد الخاص بالمستخدم)
-- ═══════════════════════════════════════════════════════════════

UPDATE storage.buckets
   SET public = false
 WHERE id = 'employee-avatars'
   AND public = true;

DROP POLICY IF EXISTS employee_avatars_public_read ON storage.objects;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'employee_avatars_select'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY employee_avatars_select ON storage.objects
        FOR SELECT TO authenticated
        USING (bucket_id = 'employee-avatars')
    $pol$;
  END IF;
END
$$;

-- ═══════════════════════════════════════════════════════════════
-- 5. حذف سياسات RLS مكررة/ميتة على public_holidays
--    الصلاحية organization.public_holidays.manage غير مُصنَّفة —
--    holidays.manage هي الصلاحية الفعلية. نحذف السياسات الميتة.
--    public_holidays_select_authenticated مطابقة لـ public_holidays_select.
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS public_holidays_select_authenticated ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_insert_manage         ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_update_manage         ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_delete_manage         ON public.public_holidays;

COMMIT;
