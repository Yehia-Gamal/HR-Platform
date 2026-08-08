-- Migration 0335: Fix employee list — org_chart.read users see all non-deleted employees
-- ================================================================================
-- المشكلة: get_employees_enriched يفلتر بـ can_access_employee(e.id, 'people.employee.read')
-- الذي قد يكون نطاقه 'department' أو 'direct_reports'، فيستبعد موظفين خارج نطاق المستخدم.
-- هذا يسبب عدم ظهور موظفين مثل طارق وربيع وحاتم في قائمة الموظفين.
--
-- الإصلاح: إذا كان المستخدم لديه صلاحية organization.org_chart.read أو هو full-access،
-- يرى جميع الموظفين غير المحذوفين دون فلترة النطاق.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_employees_enriched(
  p_search text default null,
  p_status text default null,
  p_limit integer default 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_search text := nullif(trim(lower(coalesce(p_search, ''))), '');
  v_is_org_admin boolean := false;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- إذا كان المستخدم لديه صلاحية الهيكل التنظيمي أو full-access، يرى الكل
  v_is_org_admin := public.current_is_full_access()
    OR public.has_permission('organization.org_chart.read');

  RETURN coalesce((
    SELECT jsonb_agg(row_data ORDER BY row_data->>'fullNameAr')
    FROM (
      SELECT jsonb_build_object(
        'id', e.id,
        'employeeCode', e.employee_code,
        'fullNameAr', e.full_name_ar,
        'fullNameEn', e.full_name_en,
        'phoneE164', e.phone_e164,
        'status', e.status,
        'isActive', e.is_active,
        'photoUrl', e.photo_url,
        'departmentId', e.department_id,
        'department', d.name,
        'teamId', e.team_id,
        'team', t.name,
        'branchId', e.branch_id,
        'branch', b.name,
        'jobTitle', jt.name,
        'createdAt', e.created_at
      ) AS row_data
      FROM public.employees e
      LEFT JOIN public.departments d ON d.id = e.department_id
      LEFT JOIN public.teams t ON t.id = e.team_id
      LEFT JOIN public.branches b ON b.id = e.branch_id
      LEFT JOIN public.job_titles jt ON jt.id = e.job_title_id
      WHERE e.is_deleted = false
        AND (p_status IS NULL OR e.status = p_status)
        AND (v_search IS NULL
          OR lower(e.full_name_ar) LIKE '%' || v_search || '%'
          OR lower(coalesce(e.full_name_en, '')) LIKE '%' || v_search || '%'
          OR lower(e.employee_code) LIKE '%' || v_search || '%'
          OR e.phone_e164 LIKE '%' || v_search || '%')
        AND (
          v_is_org_admin
          OR public.can_access_employee(e.id, 'people.employee.read')
        )
      ORDER BY e.created_at DESC
      LIMIT greatest(1, least(coalesce(p_limit, 200), 500))
    ) sub
  ), '[]'::jsonb);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employees_enriched(text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_employees_enriched(text, text, integer) TO authenticated;

COMMENT ON FUNCTION public.get_employees_enriched(text, text, integer) IS
  'قائمة موظفين مُثراة. المستخدمون بصلاحية org_chart.read أو full-access يرون جميع الموظفين غير المحذوفين.';

NOTIFY pgrst, 'Reload schema';

COMMIT;
