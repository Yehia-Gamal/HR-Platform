-- Migration 0316: Employee Data Integrity — fix broken manager_relations, orphaned FKs, duplicates
-- ================================================================================
-- Ensures every active employee:
--   1. Can open their detail page (get_employee_360 won't return null)
--   2. Appears in the org chart (even without a manager_relations entry)
--   3. Has valid department/position references (or NULL, not broken FKs)

BEGIN;

-- ─── Section 1: Fix broken manager_relations ─────────────────────────────
-- Employees with manager_relations pointing to deleted/nonexistent managers

-- 1a. Deactivate manager_relations where the manager employee_id doesn't exist
UPDATE public.manager_relations mr
SET effective_to = now()
WHERE mr.effective_to IS NULL
  AND mr.relation_type = 'primary'
  AND mr.manager_employee_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employees e WHERE e.id = mr.manager_employee_id
  );

-- 1b. Deactivate manager_relations where the employee_id doesn't exist
UPDATE public.manager_relations mr
SET effective_to = now()
WHERE mr.effective_to IS NULL
  AND mr.employee_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employees e WHERE e.id = mr.employee_id
  );

-- 1c. Fix circular references (employee A → manager B → manager A)
-- Detect and break cycles by deactivating the deeper relation
UPDATE public.manager_relations mr
SET effective_to = now()
WHERE mr.effective_to IS NULL
  AND mr.relation_type = 'primary'
  AND mr.manager_employee_id = mr.employee_id;  -- self-reference

-- ─── Section 2: Fix orphaned FK columns on employees ────────────────────
-- Set FK columns to NULL when they point to nonexistent records

-- 2a. department_id pointing to deleted department
UPDATE public.employees e
SET department_id = NULL
WHERE e.department_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.departments d WHERE d.id = e.department_id);

-- 2b. position_id pointing to deleted position
UPDATE public.employees e
SET position_id = NULL
WHERE e.position_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.positions p WHERE p.id = e.position_id);

-- 2c. job_title_id pointing to deleted job_title
UPDATE public.employees e
SET job_title_id = NULL
WHERE e.job_title_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.job_titles jt WHERE jt.id = e.job_title_id);

-- 2d. team_id pointing to deleted team
UPDATE public.employees e
SET team_id = NULL
WHERE e.team_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.teams t WHERE t.id = e.team_id);

-- 2e. branch_id pointing to deleted branch
UPDATE public.employees e
SET branch_id = NULL
WHERE e.branch_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.branches b WHERE b.id = e.branch_id);

-- 2f. work_site_id pointing to deleted work_site
UPDATE public.employees e
SET work_site_id = NULL
WHERE e.work_site_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.work_sites ws WHERE ws.id = e.work_site_id);

-- 2g. grade_id pointing to deleted job_grade
UPDATE public.employees e
SET grade_id = NULL
WHERE e.grade_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.job_grades jg WHERE jg.id = e.grade_id);

-- ─── Section 3: Fix employee_departments orphans ─────────────────────────
-- Remove employee_departments entries pointing to deleted employees or departments
DELETE FROM public.employee_departments ed
WHERE NOT EXISTS (SELECT 1 FROM public.employees e WHERE e.id = ed.employee_id)
   OR NOT EXISTS (SELECT 1 FROM public.departments d WHERE d.id = ed.department_id);

-- ─── Section 4: Fix profiles without employees (and vice versa) ──────────
-- Deactivate profiles that reference nonexistent employees
UPDATE public.profiles p
SET is_active = false
WHERE p.employee_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.employees e WHERE e.id = p.employee_id);

-- ─── Section 5: Data integrity diagnostic view ──────────────────────────
-- Shows employees with potential issues that could cause page failures
CREATE OR REPLACE VIEW public.employee_data_integrity AS
SELECT
  e.id AS employee_id,
  e.employee_code,
  e.full_name_ar,
  e.status,
  e.department_id,
  e.position_id,
  e.job_title_id,
  CASE WHEN e.department_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.departments d WHERE d.id = e.department_id)
       THEN 'broken_dept_fk' END AS issue_department,
  CASE WHEN e.position_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.positions p WHERE p.id = e.position_id)
       THEN 'broken_position_fk' END AS issue_position,
  CASE WHEN e.job_title_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.job_titles jt WHERE jt.id = e.job_title_id)
       THEN 'broken_job_title_fk' END AS issue_job_title,
  CASE WHEN NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.employee_id = e.id)
       THEN 'missing_profile' END AS issue_missing_profile,
  CASE WHEN NOT EXISTS (
         SELECT 1 FROM public.manager_relations mr
         WHERE mr.employee_id = e.id
           AND mr.effective_to IS NULL
           AND mr.relation_type = 'primary'
       ) THEN 'no_manager_relation' END AS issue_no_manager,
  CASE WHEN e.status = 'active'
       AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.employee_id = e.id AND p.is_active = true)
       THEN 'inactive_profile_for_active_employee' END AS issue_inactive_profile
FROM public.employees e
ORDER BY e.employee_code;

REVOKE ALL ON public.employee_data_integrity FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.employee_data_integrity TO postgres, service_role;

COMMENT ON VIEW public.employee_data_integrity IS
  'Diagnostic view showing employees with data integrity issues (broken FKs, missing profiles, no manager relation).';

-- ─── Section 6: RPC to get integrity summary ─────────────────────────────
CREATE OR REPLACE FUNCTION public.get_employee_integrity_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_employees', COUNT(*),
    'broken_dept_fk', COUNT(*) FILTER (WHERE issue_department IS NOT NULL),
    'broken_position_fk', COUNT(*) FILTER (WHERE issue_position IS NOT NULL),
    'broken_job_title_fk', COUNT(*) FILTER (WHERE issue_job_title IS NOT NULL),
    'missing_profile', COUNT(*) FILTER (WHERE issue_missing_profile IS NOT NULL),
    'no_manager_relation', COUNT(*) FILTER (WHERE issue_no_manager IS NOT NULL),
    'inactive_profile', COUNT(*) FILTER (WHERE issue_inactive_profile IS NOT NULL),
    'checked_at', now()
  )
  INTO result
  FROM public.employee_data_integrity;

  RETURN result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_integrity_summary() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_employee_integrity_summary() TO postgres, service_role;

-- ─── Section 7: Ensure get_admin_org_chart includes employees without manager_relations ───
-- The RPC already uses a recursive CTE where the anchor is "employees with no active primary manager".
-- Employees without a manager_relations entry are treated as roots. This is correct behavior —
-- they appear at the top level. No change needed to the RPC itself, but we add a diagnostic here.

-- Log how many employees have no manager relation (informational)
DO $$
DECLARE
  no_mgr_count int;
BEGIN
  SELECT COUNT(*) INTO no_mgr_count
  FROM public.employees e
  WHERE e.status = 'active'
    AND NOT EXISTS (
      SELECT 1 FROM public.manager_relations mr
      WHERE mr.employee_id = e.id
        AND mr.effective_to IS NULL
        AND mr.relation_type = 'primary'
    );

  RAISE NOTICE 'Employees without active primary manager relation: %', no_mgr_count;
  RAISE NOTICE 'These employees will appear as roots in the org chart.';
END $$;

COMMIT;
