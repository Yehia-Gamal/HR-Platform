-- 0294: إصلاح صور الموظفين عبر RPC موحّد + روابط authenticated
--
-- ملاحظة: migration 0293 أعاد bucket عامًا (public = true) كحل سريع، لكن
-- الاستراتيجية الكاملة تتطلب:
--   1) get_employee_photo_url يعيد رابطًا بصيغة authenticated/ موحّدة
--      (لا يعتمد على حالة public/private في المستقبل)
--   2) set_my_photo_url RPC جديد يسمح للموظف بتحديث صورته الذاتية بشكل مُدقق
--      بدلًا من UPDATE مباشر على employees (audit trail + validation)
--   3) Backfill: تحويل روابط public/ القديمة في photo_url إلى authenticated/
--
-- هذا migration مستقل (idempotent) وآمن للتشغيل المتكرر.

BEGIN;

-- ═══════════════════════════════════════════════════════════════
-- 1) get_employee_photo_url — يعيد رابطًا بصيغة authenticated/
--    الصيغة الموحّدة تضمن عمل العرض سواء كان bucket عامًا أو خاصًا.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_employee_photo_url(p_employee_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_url text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  IF NOT (
    public.has_permission('people.employee.read')
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT e.photo_url INTO v_url FROM public.employees e WHERE e.id = p_employee_id;
  IF v_url IS NULL THEN
    RETURN NULL;
  END IF;

  -- توحيد: استبدل /object/public/ بـ /object/authenticated/ في كل رابط.
  v_url := replace(v_url, '/storage/v1/object/public/employee-avatars/',
                          '/storage/v1/object/authenticated/employee-avatars/');
  RETURN v_url;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_employee_photo_url(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 2) set_my_photo_url — RPC جديد لتحديث الصورة الذاتية بشكل مُدقق
--    - يسمح فقط للموظف بتحديث صورته (auth.uid = employee.profile.id)
--    - يتحقق من صحة الـ URL (يجب أن يكون داخل employee-avatars)
--    - يمنع null/empty/vacuous updates
--    - يعمل عبر RLS employees_update policy (id = current_employee_id)
--    - يُرجع الرابط الجديد بصيغة authenticated/ موحّدة
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_my_photo_url(p_photo_url text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_emp_id uuid;
  v_url text;
  v_normalized text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  v_emp_id := public.current_employee_id();
  IF v_emp_id IS NULL THEN
    RAISE EXCEPTION 'ERR_NO_EMPLOYEE_PROFILE' USING ERRCODE = '42501';
  END IF;

  v_url := nullif(trim(p_photo_url), '');
  IF v_url IS NULL THEN
    RAISE EXCEPTION 'ERR_INVALID_URL' USING ERRCODE = '23502';
  END IF;

  -- يجب أن يكون الـ URL داخل bucket employee-avatars (authenticated أو public).
  IF NOT (
    v_url LIKE '%/storage/v1/object/authenticated/employee-avatars/%'
    OR v_url LIKE '%/storage/v1/object/public/employee-avatars/%'
  ) THEN
    RAISE EXCEPTION 'ERR_INVALID_URL' USING ERRCODE = '23514';
  END IF;

  -- توحيد على صيغة authenticated.
  v_normalized := replace(v_url, '/storage/v1/object/public/employee-avatars/',
                                '/storage/v1/object/authenticated/employee-avatars/');

  -- التحديث عبر UPDATE على employees — RLS تسمح بالتحديث الذاتي.
  UPDATE public.employees
     SET photo_url = v_normalized
   WHERE id = v_emp_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'ERR_UPDATE_FAILED' USING ERRCODE = '44000';
  END IF;

  RETURN v_normalized;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_my_photo_url(text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════
-- 3) Backfill: تحويل روابط public/ القديمة في photo_url إلى authenticated/
--    يُصلح كل السجلات الموجودة دفعة واحدة.
-- ═══════════════════════════════════════════════════════════════
UPDATE public.employees
   SET photo_url = replace(photo_url,
                           '/storage/v1/object/public/employee-avatars/',
                           '/storage/v1/object/authenticated/employee-avatars/')
 WHERE photo_url LIKE '%/storage/v1/object/public/employee-avatars/%';

COMMIT;
