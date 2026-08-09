-- Migration 0341: Fix get_employee_360 recentTasks column reference
-- ================================================================================
-- المشكلة: الدالة get_employee_360 المنشورة في قاعدة البيانات كانت قد بُنيت من
-- نسخة قديمة تستخدم public.tasks.assigned_to (عمود غير موجود)، بينما العمود
-- الحقيقي هو assignee_employee_id (كما في 0324/0305). أي استدعاء للدالة ينفجر
-- بـ 42703 في قسم recentTasks، ويكسر صفحة ملف الموظف واختبار 0052.
--
-- الإصلاح: إعادة تعريف الدالة من نسخة 0339 المحدّثة مع الإبقاء على قرار
-- accountStatus (يعكس حالة الموظف الفعلية لا حالة الملف الشخصي).
--
-- ملاحظة التكامل مع 0340: 0340 تنظّف البيانات (تحويل كل profile/employee
-- المعلّق إلى active) ولا تعيد تعريف الدالة نهائياً، بينما هذه الدالة (0341)
-- تعيد تعريف get_employee_360 بحيث يعكس accountStatus حالة الموظف الفعلية
-- (terminated/suspended/inactive/active). الترتيب في reset النظيف هو
-- 0339 → 0340 → 0341، والنتيجة النهائية: بيانات كلها active + منطق سليم في
-- الدالة. أي تشغيل يدوي لـ 0340 بعد 0341 يجب أن يعقبه إعادة تطبيق 0341.

BEGIN;

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
BEGIN
  IF p_employee_id IS NULL THEN
    RAISE EXCEPTION 'employee_not_found';
  END IF;

  IF NOT public.can_access_employee(p_employee_id, 'people.employee.read') THEN
    RAISE EXCEPTION 'employee scope denied' USING ERRCODE = '42501';
  END IF;

  SELECT
    e.id, e.employee_code, e.full_name_ar, e.full_name_en, e.phone_e164,
    e.photo_url, e.status, e.is_active, e.hire_date, e.contract_end,
    e.probation_end, e.job_title_id, e.position_id, e.grade_id,
    e.department_id, e.team_id, e.branch_id, e.work_site_id,
    e.employment_type_id, e.national_id_enc, e.updated_at, e.created_at
  INTO v_employee
  FROM public.employees e
  WHERE e.id = p_employee_id AND e.is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'employee_not_found';
  END IF;

  -- resolve manager via manager_relations
  SELECT mr.manager_employee_id INTO v_manager_id
  FROM public.manager_relations mr
  WHERE mr.employee_id = p_employee_id
    AND mr.relation_type = 'primary'
    AND mr.effective_to IS NULL
  ORDER BY mr.effective_from DESC
  LIMIT 1;

  SELECT jsonb_build_object(
    'id', v_employee.id,
    'employeeCode', v_employee.employee_code,
    'fullNameAr', v_employee.full_name_ar,
    'fullNameEn', v_employee.full_name_en,
    'email', au.email,
    'phoneE164', v_employee.phone_e164,
    'photoUrl', v_employee.photo_url,
    'status', v_employee.status,
    'isActive', v_employee.is_active,
    'hireDate', v_employee.hire_date,
    'contractEnd', v_employee.contract_end,
    'probationEnd', v_employee.probation_end,
    'jobTitle', jt.name,
    'position', pos.name,
    'grade', grade.name,
    'department', dept.name,
    'team', team.name,
    'branch', branch.name,
    'workSite', site.name,
    'managerName', manager_rel.full_name_ar,
    'managerId', v_manager_id,
    -- accountStatus يعكس حالة الموظف الفعلية (active/suspended/terminated/inactive)
    'accountStatus', CASE
      WHEN v_employee.status = 'terminated' THEN 'terminated'
      WHEN v_employee.status = 'suspended' THEN 'suspended'
      WHEN v_employee.is_active = false THEN 'inactive'
      ELSE 'active'
    END,
    'departmentId', v_employee.department_id,
    'teamId', v_employee.team_id,
    'branchId', v_employee.branch_id,
    'workSiteId', v_employee.work_site_id,
    'jobTitleId', v_employee.job_title_id,
    'positionId', v_employee.position_id,
    'gradeId', v_employee.grade_id,
    'employmentTypeId', v_employee.employment_type_id,
    'roles', coalesce((
      SELECT jsonb_agg(jsonb_build_object('slug', r.slug, 'name', r.name_ar) ORDER BY r.name_ar)
      FROM public.user_roles ur
      JOIN public.roles r ON r.id = ur.role_id
      WHERE ur.user_id = (
        SELECT p.id FROM public.profiles p WHERE p.employee_id = v_employee.id
        UNION ALL
        SELECT au.id FROM auth.users au
        JOIN public.profiles p ON p.id = au.id
        WHERE p.employee_id = v_employee.id
        LIMIT 1
      )
      AND (ur.effective_to IS NULL OR ur.effective_to > now())
    ), '[]'::jsonb),
    'directReports', (
      SELECT count(*) FROM public.manager_relations mr
      WHERE mr.manager_employee_id = v_employee.id
        AND mr.relation_type = 'primary'
        AND mr.effective_from <= (now() at time zone 'Africa/Cairo')::date
        AND (mr.effective_to IS NULL OR mr.effective_to >= (now() at time zone 'Africa/Cairo')::date)
    ),
    'attendance30', jsonb_build_object(
      'present', (SELECT count(*) FROM public.attendance_daily a WHERE a.employee_id = v_employee.id AND a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 AND a.status IN ('present','late')),
      'lateDays', (SELECT count(*) FROM public.attendance_daily a WHERE a.employee_id = v_employee.id AND a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 AND a.late_minutes > 0),
      'absent', (SELECT count(*) FROM public.attendance_daily a WHERE a.employee_id = v_employee.id AND a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29 AND a.status = 'absent'),
      'workMinutes', (SELECT coalesce(sum(a.work_minutes),0) FROM public.attendance_daily a WHERE a.employee_id = v_employee.id AND a.work_date >= (now() at time zone 'Africa/Cairo')::date - 29)
    ),
    'requestCounts', jsonb_build_object(
      'pending', (SELECT count(*) FROM public.requests r WHERE r.employee_id = v_employee.id AND r.status = 'pending'),
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
    'documents', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', doc.id, 'type', doc.doc_type, 'title', doc.title,
        'expiryDate', doc.expiry_date,
        'status', CASE WHEN doc.expiry_date IS NOT NULL AND doc.expiry_date < (now() at time zone 'Africa/Cairo')::date THEN 'expired' ELSE doc.status END
      ) ORDER BY doc.created_at DESC)
      FROM public.documents doc
      WHERE doc.owner_employee_id = v_employee.id AND doc.status <> 'archived'
    ), '[]'::jsonb),
    'assets', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', aa.id, 'assetName', ai.name_ar, 'assetType', ai.asset_type,
        'serial', ai.serial, 'handedOverAt', aa.handed_over_at, 'returnedAt', aa.returned_at
      ) ORDER BY aa.handed_over_at DESC NULLS LAST)
      FROM public.asset_assignments aa
      JOIN public.asset_inventory ai ON ai.id = aa.asset_id
      WHERE aa.employee_id = v_employee.id
    ), '[]'::jsonb),
    'recentRequests', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', r.id, 'requestNumber', r.request_number, 'requestType', r.request_type,
        'title', r.title, 'status', r.status, 'createdAt', r.created_at
      ) ORDER BY r.created_at DESC)
      FROM (SELECT * FROM public.requests WHERE employee_id = v_employee.id ORDER BY created_at DESC LIMIT 10) r
    ), '[]'::jsonb),
    'recentTasks', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', t.id, 'title', t.title, 'status', t.status,
        'priority', t.priority, 'dueDate', t.due_date
      ) ORDER BY t.created_at DESC)
      FROM (SELECT * FROM public.tasks WHERE assignee_employee_id = v_employee.id ORDER BY created_at DESC LIMIT 10) t
    ), '[]'::jsonb),
    'departments', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'id', ed.id, 'departmentId', ed.department_id,
        'departmentName', d.name, 'jobTitle', ed.job_title,
        'isPrimary', ed.is_primary, 'assignedAt', ed.assigned_at
      ) ORDER BY ed.is_primary DESC, ed.assigned_at DESC)
      FROM public.employee_departments ed
      JOIN public.departments d ON d.id = ed.department_id
      WHERE ed.employee_id = v_employee.id
        AND (ed.start_date IS NULL OR ed.start_date <= (now() at time zone 'Africa/Cairo')::date)
        AND (ed.end_date IS NULL OR ed.end_date >= (now() at time zone 'Africa/Cairo')::date)
    ), '[]'::jsonb),
    'lastUpdatedAt', coalesce(v_employee.updated_at, v_employee.created_at, now())
  )
  INTO v_result
  FROM public.employees e
  LEFT JOIN public.job_titles jt ON jt.id = v_employee.job_title_id
  LEFT JOIN public.positions pos ON pos.id = v_employee.position_id
  LEFT JOIN public.job_grades grade ON grade.id = v_employee.grade_id
  LEFT JOIN public.departments dept ON dept.id = v_employee.department_id
  LEFT JOIN public.teams team ON team.id = v_employee.team_id
  LEFT JOIN public.branches branch ON branch.id = v_employee.branch_id
  LEFT JOIN public.work_sites site ON site.id = v_employee.work_site_id
  LEFT JOIN public.employees manager_rel ON manager_rel.id = v_manager_id
  LEFT JOIN public.profiles profile ON profile.employee_id = e.id
  LEFT JOIN auth.users au ON au.id = profile.id
  WHERE e.id = p_employee_id;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_employee_360(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_employee_360(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_employee_360(uuid) IS
  'ملف موظف كامل 360°. recentTasks يستخدم assignee_employee_id. accountStatus يعكس حالة الموظف الفعلية.';

NOTIFY pgrst, 'Reload schema';

COMMIT;
