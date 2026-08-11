-- ══════════════════════════════════════════════════════════════════════
-- 0375: إضافة فحص صلاحية لدالة get_employee_360 (P0 — تسريب حالة الموظف)
--
-- المشكلة: 0364 أعادت تعريف get_employee_360 (SECURITY DEFINER) دون أي
--   فحص صلاحية داخلي — لا auth.uid() IS NULL ولا has_permission ولا
--   can_access_employee. أي موظف مسجّل يستطيع استدعاؤها عبر PostgREST
--   واستخراج حالة حساب أي موظف آخر (terminated/suspended/inactive/…)
--   مع employeeStatus و isActive — بيانات HR حساسة.
--
-- الإصلاح: إضافة الحارسَين المعياريَّين قبل أي قراءة:
--   1) auth.uid() IS NULL  → AUTH_REQUIRED
--   2) NOT (has_permission('people.employee.read') OR can_access_employee(p_employee_id))
--      → ERR_FORBIDDEN (42501)
--   هذا يتيح الوصول لـ: صاحب الملف نفسه + مديره المباشر + HR + full-access.
--   ويطابق الحماية التي كانت موجودة قبل 0364.
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.get_employee_360(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_employee public.employees;
  v_profile  public.profiles;
  v_account_status text;
BEGIN
  -- حارس المصادقة
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  -- حارس الصلاحية: صاحب الملف أو مديره أو HR أو full-access
  IF NOT (
    public.has_permission('people.employee.read')
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_employee
  FROM public.employees
  WHERE id = p_employee_id AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'employee not found' USING ERRCODE = 'P0002';
  END IF;

  v_account_status := CASE
    WHEN v_employee.status = 'terminated'      THEN 'terminated'
    WHEN v_employee.status = 'suspended'       THEN 'suspended'
    WHEN v_employee.is_active = false          THEN 'inactive'
    WHEN v_employee.status = 'invited'         THEN 'invited'
    WHEN v_employee.status = 'pending'         THEN 'pending'
    WHEN v_employee.status = 'probation_failed' THEN 'probation_failed'
    WHEN v_employee.status = 'notice_period'   THEN 'notice_period'
    ELSE 'active'
  END;

  BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_employee_id;
    IF FOUND AND v_profile.status IS NOT NULL THEN
      IF v_profile.status = 'active' AND v_employee.status IS DISTINCT FROM 'active' THEN
        NULL;
      ELSIF v_profile.status IS DISTINCT FROM 'active' AND v_employee.status = 'active' THEN
        v_account_status := v_profile.status;
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN jsonb_build_object(
    'accountStatus', v_account_status,
    'employeeStatus', v_employee.status,
    'isActive',       v_employee.is_active
  );
END;
$$;

COMMIT;
