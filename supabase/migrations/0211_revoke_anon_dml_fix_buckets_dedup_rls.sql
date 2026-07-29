-- تعزيز أمني — الجولة الثالثة
-- 1. سحب INSERT/UPDATE/DELETE من anon على جميع جداول public
-- 2. ضبط الصلاحيات الافتراضية لمنع DML المستقبلي على anon
-- 3. جعل bucket employee-avatars خاصاً
-- 4. حذف سياسات RLS مكررة/ميتة على public_holidays
-- 5. إضافة سياسات storage لـ employee-avatars (authenticated فقط)

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1. REVOKE INSERT / UPDATE / DELETE من anon على جميع الجداول
--    SECURITY DEFINER functions تعمل بصلاحية المالك فلا تتأثر.
--    SELECT يبقى (RLS يحجب الصفوف فعلياً).
-- ═══════════════════════════════════════════════════════════════

REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM anon;

-- ═══════════════════════════════════════════════════════════════
-- 2. صلاحيات افتراضية: الجداول الجديدة لا تُمنح DML لـ anon
-- ═══════════════════════════════════════════════════════════════

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE INSERT, UPDATE, DELETE ON TABLES FROM anon;

-- ═══════════════════════════════════════════════════════════════
-- 3. جعل bucket employee-avatars خاصاً
--    (تم تطبيقه على البعيد مباشرة — هنا للمزامنة مع المحلي)
-- ═══════════════════════════════════════════════════════════════

UPDATE storage.buckets
   SET public = false
 WHERE id = 'employee-avatars'
   AND public = true;

-- ═══════════════════════════════════════════════════════════════
-- 4. حذف سياسات RLS مكررة/ميتة على public_holidays
--    الصلاحية organization.public_holidays.manage غير مُصنَّفة —
--    holidays.manage هي الصلاحية الفعلية. نحذف السياسات الميتة.
--    public_holidays_select_authenticated مطابقة لـ public_holidays_select.
-- ═══════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS public_holidays_select_authenticated ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_insert_manage         ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_update_manage         ON public.public_holidays;
DROP POLICY IF EXISTS public_holidays_delete_manage         ON public.public_holidays;

-- ═══════════════════════════════════════════════════════════════
-- 5. سياسات storage لـ employee-avatars
--    authenticated يستطيع القراءة؛ full-access يستطيع الإدارة.
--    (IF NOT EXISTS عبر DO block لأن CREATE POLICY لا يدعمها)
-- ═══════════════════════════════════════════════════════════════

DO $$
BEGIN
  -- SELECT policy
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

  -- INSERT policy (full-access only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'employee_avatars_insert'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY employee_avatars_insert ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (
          bucket_id = 'employee-avatars'
          AND (SELECT public.current_is_full_access())
        )
    $pol$;
  END IF;

  -- UPDATE policy (full-access only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'employee_avatars_update'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY employee_avatars_update ON storage.objects
        FOR UPDATE TO authenticated
        USING (
          bucket_id = 'employee-avatars'
          AND (SELECT public.current_is_full_access())
        )
    $pol$;
  END IF;

  -- DELETE policy (full-access only)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'employee_avatars_delete'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY employee_avatars_delete ON storage.objects
        FOR DELETE TO authenticated
        USING (
          bucket_id = 'employee-avatars'
          AND (SELECT public.current_is_full_access())
        )
    $pol$;
  END IF;
END
$$;

COMMIT;
