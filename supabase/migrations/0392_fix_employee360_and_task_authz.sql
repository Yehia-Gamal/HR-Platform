-- ══════════════════════════════════════════════════════════════════════
-- 0392: إصلاح get_employee_360 + توسيع صلاحية admin_create_task
--
-- مشكلة 1 — get_employee_360 مكسورة (P0):
--   0364 ثم 0375 استبدلا الدالة الكاملة بـ stub يعيد 3 حقول فقط
--   (accountStatus, employeeStatus, isActive). employee360Schema في الويب
--   يتوقع 20+ حقلاً → Zod parse يفشل → "بيانات الموظف غير مكتملة".
--   الإصلاح: إعادة تعريف الدالة بجسمها الكامل (من 0341) مع إضافة
--   حارسَي المصادقة والصلاحية من 0375.
--
-- مشكلة 2 — admin_create_task 403 لمستخدمي العمليات (P1):
--   route guard للصفحة يسمح لـ operations.mission.manage/convoy.manage,
--   لكن الدالة تتطلب is_full_access OR tasks.write فقط. المستخدمون
--   الذين لديهم صلاحية operations.mission.manage يرون الصفحة لكن يتلقون
--   403 عند إنشاء المهمة.
--   الإصلاح: إضافة operations.mission.manage إلى شرط الصلاحية.
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1) استعادة get_employee_360 الكاملة ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_employee_360(p_employee_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_employee record;
  v_manager_id uuid;
  v_result jsonb;
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

  IF p_employee_id IS NULL THEN
    RAISE EXCEPTION 'employee_not_found';
  END IF;

  SELECT
    e.id, e.employee_code, e.full_name_ar, e.full_name_en, e.phone_e164,
    e.photo_url, e.status, e.is_active, e.hire_date, e.contract_end,
    e.probation_end, e.job_title_id, e.position_id, e.grade_id,
    e.department_id, e.team_id, e.branch_id, e.work_site_id,
    e.employment_type_id, e.updated_at, e.created_at
  INTO v_employee
  FROM public.employees e
  WHERE e.id = p_employee_id AND e.is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'employee_not_found';
  END IF;

  -- حساب حالة الحساب الدلالية
  v_account_status := CASE
    WHEN v_employee.status = 'terminated'       THEN 'terminated'
    WHEN v_employee.status = 'suspended'        THEN 'suspended'
    WHEN v_employee.is_active = false           THEN 'inactive'
    WHEN v_employee.status = 'invited'          THEN 'invited'
    WHEN v_employee.status = 'pending'          THEN 'pending'
    WHEN v_employee.status = 'probation_failed' THEN 'probation_failed'
    WHEN v_employee.status = 'notice_period'    THEN 'notice_period'
    ELSE 'active'
  END;

  -- resolve manager via manager_relations
  SELECT mr.manager_employee_id INTO v_manager_id
  FROM public.manager_relations mr
  WHERE mr.employee_id = p_employee_id
    AND mr.relation_type = 'primary'
    AND mr.effective_to IS NULL
  ORDER BY mr.effective_from DESC
  LIMIT 1;

  SELECT jsonb_build_object(
    'id',               v_employee.id,
    'employeeCode',     v_employee.employee_code,
    'fullNameAr',       v_employee.full_name_ar,
    'fullNameEn',       v_employee.full_name_en,
    'email',            au.email,
    'phoneE164',        v_employee.phone_e164,
    'photoUrl',         v_employee.photo_url,
    'status',           v_employee.status,
    'isActive',         v_employee.is_active,
    'hireDate',         v_employee.hire_date,
    'contractEnd',      v_employee.contract_end,
    'probationEnd',     v_employee.probation_end,
    'jobTitle',         jt.name,
    'position',         pos.name,
    'grade',            grade.name,
    'department',       dept.name,
    'team',             team.name,
    'branch',           branch.name,
    'workSite',         site.name,
    'managerName',      manager_rel.full_name_ar,
    'managerId',        v_manager_id,
    'accountStatus',    v_account_status,
    'departmentId',     v_employee.department_id,
    'teamId',           v_employee.team_id,
    'branchId',         v_employee.branch_id,
    'workSiteId',       v_employee.work_site_id,
    'jobTitleId',       v_employee.job_title_id,
    'positionId',       v_employee.position_id,
    'gradeId',          v_employee.grade_id,
    'employmentTypeId', v_employee.employment_type_id,
    'roles', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) ORDER BY r.name_ar)
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (
        SELECT p.id FROM public.profiles p WHERE p.employee_id = v_employee.id LIMIT 1
      )
        AND (ur.effective_to IS NULL OR ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      SELECT count(*) FROM public.manager_relations mr
      WHERE mr.manager_employee_id = v_employee.id
        AND mr.relation_type = 'primary'
        AND mr.effective_from <= (now() AT TIME ZONE 'Africa/Cairo')::date
        AND (mr.effective_to IS NULL OR mr.effective_to >= (now() AT TIME ZONE 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present',     (SELECT count(*) FROM public.attendance_daily a
                      WHERE a.employee_id = v_employee.id
                        AND a.work_date >= (now() AT TIME ZONE 'Africa/Cairo')::date - 29
                        AND a.status IN ('present','late')),
      'lateDays',    (SELECT count(*) FROM public.attendance_daily a
                      WHERE a.employee_id = v_employee.id
                        AND a.work_date >= (now() AT TIME ZONE 'Africa/Cairo')::date - 29
                        AND a.late_minutes > 0),
      'absent',      (SELECT count(*) FROM public.attendance_daily a
                      WHERE a.employee_id = v_employee.id
                        AND a.work_date >= (now() AT TIME ZONE 'Africa/Cairo')::date - 29
                        AND a.status = 'absent'),
      'workMinutes', (SELECT COALESCE(sum(a.work_minutes),0) FROM public.attendance_daily a
                      WHERE a.employee_id = v_employee.id
                        AND a.work_date >= (now() AT TIME ZONE 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending',  (SELECT count(*) FROM public.requests r WHERE r.employee_id = v_employee.id AND r.status = 'pending'),
      'approved', (SELECT count(*) FROM public.requests r WHERE r.employee_id = v_employee.id AND r.status = 'approved'),
      'rejected', (SELECT count(*) FROM public.requests r WHERE r.employee_id = v_employee.id AND r.status = 'rejected')
    ),
    'latestKpi', (
      SELECT jsonb_build_object(
        'id', ke.id, 'periodMonth', kc.period_month,
        'currentStage', ke.current_stage,
        'finalScore', ke.final_score, 'finalRating', ke.final_rating
      )
      FROM public.kpi_evaluations ke
      JOIN public.kpi_cycles kc ON kc.id = ke.cycle_id
      WHERE ke.employee_id = v_employee.id
      ORDER BY kc.period_month DESC, ke.created_at DESC
      LIMIT 1
    ),
    'documents', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', CASE
          WHEN doc.expiry_date IS NOT NULL
           AND doc.expiry_date < (now() AT TIME ZONE 'Africa/Cairo')::date
          THEN 'expired' ELSE doc.status END
      ) ORDER BY doc.created_at DESC)
      FROM public.documents doc
      WHERE doc.owner_employee_id = v_employee.id AND doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) ORDER BY aa.handed_over_at DESC NULLS LAST)
      FROM public.asset_assignments aa
      JOIN public.asset_inventory ai ON ai.id = aa.asset_id
      WHERE aa.employee_id = v_employee.id
    ), '[]'::jsonb),
    'recentRequests', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) ORDER BY r.created_at DESC)
      FROM (SELECT * FROM public.requests WHERE employee_id = v_employee.id
            ORDER BY created_at DESC LIMIT 10) r
    ), '[]'::jsonb),
    'recentTasks', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) ORDER BY t.created_at DESC)
      FROM (SELECT * FROM public.tasks WHERE assignee_employee_id = v_employee.id
            ORDER BY created_at DESC LIMIT 10) t
    ), '[]'::jsonb),
    'departments', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id,
        'departmentName', d.name, 'jobTitle', ed.job_title,
        'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) ORDER BY ed.is_primary DESC, ed.assigned_at DESC)
      FROM public.employee_departments ed
      JOIN public.departments d ON d.id = ed.department_id
      WHERE ed.employee_id = v_employee.id
        AND (ed.start_date IS NULL OR ed.start_date <= (now() AT TIME ZONE 'Africa/Cairo')::date)
        AND (ed.end_date IS NULL OR ed.end_date >= (now() AT TIME ZONE 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', COALESCE(v_employee.updated_at, v_employee.created_at, now())
  )
  INTO v_result
  FROM public.employees e
  LEFT JOIN public.job_titles jt    ON jt.id    = v_employee.job_title_id
  LEFT JOIN public.positions pos    ON pos.id   = v_employee.position_id
  LEFT JOIN public.job_grades grade ON grade.id = v_employee.grade_id
  LEFT JOIN public.departments dept ON dept.id  = v_employee.department_id
  LEFT JOIN public.teams team       ON team.id  = v_employee.team_id
  LEFT JOIN public.branches branch  ON branch.id = v_employee.branch_id
  LEFT JOIN public.work_sites site  ON site.id  = v_employee.work_site_id
  LEFT JOIN public.employees manager_rel ON manager_rel.id = v_manager_id
  LEFT JOIN public.profiles profile ON profile.employee_id = e.id
  LEFT JOIN auth.users au            ON au.id = profile.id
  WHERE e.id = p_employee_id;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_360(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_employee_360(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_employee_360(uuid) IS
  '0392: ملف موظف كامل 360° — يحمل حارسَي المصادقة والصلاحية من 0375 مع الجسم الكامل من 0341.';

-- ─── 2) توسيع صلاحية admin_create_task ───────────────────────────────────────
-- route /admin/operations مفتوح لـ operations.mission.manage/convoy.manage
-- لكن الدالة كانت تتطلب is_full_access OR tasks.write فقط → 403 لمديري العمليات.

CREATE OR REPLACE FUNCTION public.admin_create_task(
  p_title       text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_priority    text DEFAULT 'medium',
  p_due_date    date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = 'public', 'pg_temp'
AS $$
DECLARE
  v_id     uuid;
  v_emp_id uuid;
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_permission('tasks.write')
    OR public.has_permission('operations.mission.manage')
  ) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: إنشاء المهام يتطلب صلاحية tasks.write أو operations.mission.manage'
      USING ERRCODE = '42501';
  END IF;

  IF NULLIF(btrim(COALESCE(p_title, '')), '') IS NULL THEN
    RAISE EXCEPTION 'TITLE_REQUIRED' USING ERRCODE = '22023';
  END IF;

  IF p_priority IS NOT NULL AND p_priority NOT IN ('low', 'medium', 'high', 'urgent') THEN
    RAISE EXCEPTION 'INVALID_PRIORITY' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_emp_id
  FROM public.employees
  WHERE user_id = auth.uid() AND is_active
  LIMIT 1;

  INSERT INTO public.tasks (
    title, description, assignee_employee_id,
    priority, due_date, created_by_employee_id, created_by
  ) VALUES (
    btrim(p_title), p_description, p_assignee_id,
    p_priority, p_due_date, v_emp_id, auth.uid()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_task(text, text, uuid, text, date) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.admin_create_task(text, text, uuid, text, date) TO authenticated;

COMMENT ON FUNCTION public.admin_create_task(text,text,uuid,text,date) IS
  '0392: يسمح لـ full_access + tasks.write + operations.mission.manage بإنشاء المهام.';

NOTIFY pgrst, 'reload schema';

COMMIT;
