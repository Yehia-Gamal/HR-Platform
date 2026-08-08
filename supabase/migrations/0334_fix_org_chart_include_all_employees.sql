-- Migration 0334: Fix org chart — include ALL non-terminated employees
-- ================================================================================
-- المشكلة: get_admin_org_chart كان يفلتر بـ is_active=true AND status IN ('active','onboarding','probation_failed')
-- هذا يستبعد الموظفين الموقوفين (suspended)، المدعوين (invited)، وفترة الإخطار (notice_period)
-- فلا يظهر طارق وربيع وحاتم وغيرهم في الهيكل التنظيمي.
--
-- الإصلاح: تضمين كل الموظفين غير المحذوفين وغير المنتهين.
-- terminated و draft فقط يُستبعدون (منتهي ومسودة غير مكتملة).

BEGIN;

CREATE OR REPLACE FUNCTION public.get_admin_org_chart()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  WITH RECURSIVE
  -- جميع الموظفين غير المحذوفين وغير المنتهين (بما فيهم الموقوفون والمدعوون وفترة الإخطار)
  emp_base AS (
    SELECT
      e.id,
      e.full_name_ar,
      e.full_name_en,
      e.photo_url,
      coalesce(jt.name, jt.name_en, '') AS job_title,
      coalesce(d.name, '') AS department_name,
      e.employee_code,
      e.department_id,
      e.status,
      e.is_active,
      e.is_deleted
    FROM public.employees e
    LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
    LEFT JOIN public.departments d ON d.id = e.department_id
    WHERE e.is_deleted = false
      AND e.status NOT IN ('terminated', 'draft')
  ),
  -- العلاقات النشطة فقط (مدير رئيسي نشط)
  active_primary_managers AS (
    SELECT
      mr.employee_id,
      mr.manager_employee_id
    FROM public.manager_relations mr
    WHERE mr.relation_type = 'primary'
      AND mr.effective_to IS NULL
      AND mr.employee_id IN (SELECT id FROM emp_base)
      AND mr.manager_employee_id IN (SELECT id FROM emp_base)
  ),
  -- الشجرة الهرمية المتكررة بدءًا من الجذور (موظفون بلا مدير رئيسي)
  org_tree AS (
    -- الجذور: موظفون ليس لديهم مدير رئيسي نشط
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      NULL::uuid AS manager_employee_id,
      0 AS depth,
      ARRAY[eb.id]::uuid[] AS path
    FROM emp_base eb
    LEFT JOIN active_primary_managers apm ON apm.employee_id = eb.id
    WHERE apm.employee_id IS NULL

    UNION ALL

    -- الأبناء: موظفون مديرهم موجود بالفعل في الشجرة
    SELECT
      eb.id,
      eb.full_name_ar,
      eb.full_name_en,
      eb.photo_url,
      eb.job_title,
      eb.department_name,
      eb.employee_code,
      eb.department_id,
      eb.status,
      eb.is_active,
      apm.manager_employee_id,
      ot.depth + 1,
      ot.path || eb.id
    FROM emp_base eb
    JOIN active_primary_managers apm ON apm.employee_id = eb.id
    JOIN org_tree ot ON ot.id = apm.manager_employee_id
    WHERE NOT eb.id = ANY(ot.path)
  ),
  -- عدّ المرؤوسين المباشرين لكل موظف
  direct_counts AS (
    SELECT
      manager_employee_id AS emp_id,
      COUNT(*) AS direct_reports_count
    FROM active_primary_managers
    GROUP BY manager_employee_id
  )
  SELECT jsonb_build_object(
    'employees', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id,
        'fullNameAr', t.full_name_ar,
        'fullNameEn', t.full_name_en,
        'photoUrl', t.photo_url,
        'jobTitle', t.job_title,
        'departmentName', t.department_name,
        'employeeCode', t.employee_code,
        'departmentId', t.department_id,
        'status', t.status,
        'isActive', t.is_active,
        'managerEmployeeId', t.manager_employee_id,
        'directReportsCount', coalesce(dc.direct_reports_count, 0),
        'depth', t.depth,
        'path', t.path
      ) ORDER BY t.path, t.full_name_ar)
      FROM org_tree t
      LEFT JOIN direct_counts dc ON dc.emp_id = t.id
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_org_chart() TO authenticated;

COMMENT ON FUNCTION public.get_admin_org_chart() IS
  'شجرة هرمية للموظفين (مدير → مرؤوسون مباشرون بشكل متكرر) عبر manager_relations النشطة. يشمل جميع الموظفين غير المحذوفين وغير المنتهين.';

-- إعادة تحميل PostgREST schema cache
NOTIFY pgrst, 'Reload schema';

COMMIT;
