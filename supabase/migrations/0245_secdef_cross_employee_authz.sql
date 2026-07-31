-- ═══════════════════════════════════════════════════════════════════════
-- 0245: سد تسريب بيانات عبر دوال SECURITY DEFINER بلا حصر للمستدعي
--       (أُنشئت أصلاً كـ 0240؛ أُعيد ترقيمها إلى 0245 لتفادي تصادم مع جلسة موازية)
-- ═══════════════════════════════════════════════════════════════════════
-- دوال SECURITY DEFINER تتجاوز RLS وممنوح لها EXECUTE إلى authenticated
-- دون أي فحص صلاحية ولا مطابقة للمستدعي، فيقرأ أي موظف بلا صلاحيات بيانات
-- موظفين آخرين بتمرير UUID كيفي.
--
-- المعالجة:
--   • get_employee_departments (P1) — تستخدمها الواجهة (صفحة تفاصيل الموظف)
--     لعرض أقسام موظفٍ آخر، فلا يصلح REVOKE؛ نضيف حارس صلاحية بدل ذلك:
--     يُسمح إن كان المستهدف = الموظف الحالي، أو full-access، أو HR، أو
--     can_access_employee(target). خلاف ذلك FORBIDDEN (42501).
--   • بقية الدوال (P2) — غير مُستدعاة من web/mobile إطلاقاً (تم التحقق)،
--     ومستدعوها الداخليون يعملون كـ SECURITY DEFINER owner، فالحل الأنظف
--     هو REVOKE EXECUTE من authenticated (يبقى service_role والاستدعاء الداخلي).
-- ═══════════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────────
-- P1: get_employee_departments — تحويل إلى plpgsql مع حارس صلاحية
-- (نفس الإخراج تماماً كنسخة 0175، مع إضافة كتلة التحقق في البداية فقط)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_departments(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- الحارس: المستدعي إمّا صاحب السجل، أو كامل الوصول، أو HR، أو له وصول
  -- إداري للموظف المستهدف. غير ذلك يُرفض (تجنّب كشف بيانات موظف آخر).
  IF NOT (
    p_employee_id = public.current_employee_id()
    OR public.current_is_full_access()
    OR public.current_is_hr_only()
    OR public.can_access_employee(p_employee_id)
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: لا صلاحية لعرض أقسام هذا الموظف'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(
      jsonb_build_object(
        'id', ed.id,
        'departmentId', ed.department_id,
        'departmentName', d.name,
        'jobTitle', ed.job_title,
        'isPrimary', ed.is_primary,
        'assignedAt', ed.assigned_at,
        'allocationPercentage', ed.allocation_percentage,
        'startDate', ed.start_date,
        'endDate', ed.end_date,
        'functionalManagerId', ed.functional_manager_id,
        'functionalManagerName', fm.full_name_ar
      ) order by ed.is_primary desc, ed.assigned_at
    ), '[]'::jsonb)
    FROM public.employee_departments ed
    JOIN public.departments d ON d.id = ed.department_id
    LEFT JOIN public.employees fm ON fm.id = ed.functional_manager_id
    WHERE ed.employee_id = p_employee_id
      AND (ed.end_date IS NULL OR ed.end_date >= current_date)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_employee_departments(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_departments(uuid)
  TO authenticated, service_role;

-- ───────────────────────────────────────────────────────────────────────
-- P2: سحب EXECUTE من authenticated للدوال غير المُستدعاة من الواجهة
-- (المستدعون الداخليون SECURITY DEFINER لا يتأثرون؛ service_role يبقى)
-- ───────────────────────────────────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION public.effective_annual_entitlement(uuid, date)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.effective_annual_entitlement(uuid, date)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.leave_request_units(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.leave_request_units(uuid)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.resolve_request_approver(uuid, date)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_request_approver(uuid, date)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.is_management_descendant(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_management_descendant(uuid, uuid)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.employee_has_role(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.employee_has_role(uuid, text)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.first_active_employee_for_role(text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.first_active_employee_for_role(text)
  TO service_role;

REVOKE EXECUTE ON FUNCTION public.get_kpi_validation_errors(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_kpi_validation_errors(uuid)
  TO service_role;

-- ───────────────────────────────────────────────────────────────────────
-- إضافي: asset_inventory — سياسة SELECT كانت using(true) فتكشف purchase_cost
-- والموقع لأي موظف رغم وجود صلاحية assets.read. الكتابة محمية بـ assets.write.
-- الجدول غير مُستخدم في الواجهة، فتشديد القراءة آمن.
-- ───────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS asset_inventory_select ON public.asset_inventory;
CREATE POLICY asset_inventory_select ON public.asset_inventory
  FOR SELECT TO authenticated
  USING (
    public.current_is_full_access()
    OR public.has_permission('assets.read')
    OR public.has_permission('assets.inventory.manage')
    OR public.has_permission('assets.write')
  );

COMMIT;
