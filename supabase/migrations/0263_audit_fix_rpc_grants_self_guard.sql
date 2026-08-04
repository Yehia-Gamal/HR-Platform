-- 0263: إغلاق فجوات التدقيق متعددة الطبقات
--
-- 1) منح EXECUTE للمصادقين على 4 دوال لوحة الإدارة (0256 أضاف الفحوص فقط ولم يمنح):
--    get_audit_security_data / get_integration_center_data / get_operations_center_data /
--    get_employee_photo_url -- كانت محظورة للجميع (revoke في 0227 بلا grant).
-- 2) حماية is_deleted + national_id_enc من تعديل الموظف الذاتي (tg_employees_protect_job_fields).
-- 3) جعل rpc_revoke_role متماثلا مع rpc_assign_role (حماية أدوار full-access).
-- 4) فرض tasks.write على admin_create_task / admin_transition_task مع تحقق صحة المدخلات.
-- 5) إضافة organization.entity.read إلى بوابة get_enterprise_management_catalog.
--
-- Idempotent: CREATE OR REPLACE فقط. لا يعدل أي migration منشورة.

BEGIN;

-- 1) منح الدوال الأربع (الفحوص موجودة في 0256/0261)
GRANT EXECUTE ON FUNCTION public.get_audit_security_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_integration_center_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_operations_center_data() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_employee_photo_url(uuid) TO authenticated;

-- 2) حماية is_deleted و national_id_enc من التعديل الذاتي
CREATE OR REPLACE FUNCTION tg_employees_protect_job_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  -- SECURITY DEFINER يجعل current_user = المالك (postgres) دائمًا، لذا لا يمكن
  -- التمييز عبر current_user. نستبدل بالتحقق من غياب JWT claims (وصول صيانة مباشر)
  -- أو service_role (Edge Functions) — الحالة الصحيحة للتجاوز.
  IF current_setting('request.jwt.claims', true) IS NULL
     OR current_setting('request.jwt.claim.role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;

  IF (
    NEW.employee_code    IS DISTINCT FROM OLD.employee_code OR
    NEW.status           IS DISTINCT FROM OLD.status OR
    NEW.is_active        IS DISTINCT FROM OLD.is_active OR
    NEW.is_deleted       IS DISTINCT FROM OLD.is_deleted OR
    NEW.national_id_enc  IS DISTINCT FROM OLD.national_id_enc OR
    NEW.department_id    IS DISTINCT FROM OLD.department_id OR
    NEW.team_id          IS DISTINCT FROM OLD.team_id OR
    NEW.branch_id        IS DISTINCT FROM OLD.branch_id OR
    NEW.work_site_id     IS DISTINCT FROM OLD.work_site_id OR
    NEW.job_title_id     IS DISTINCT FROM OLD.job_title_id OR
    NEW.position_id      IS DISTINCT FROM OLD.position_id OR
    NEW.grade_id         IS DISTINCT FROM OLD.grade_id OR
    NEW.employment_type_id IS DISTINCT FROM OLD.employment_type_id OR
    NEW.hire_date        IS DISTINCT FROM OLD.hire_date OR
    NEW.contract_end     IS DISTINCT FROM OLD.contract_end OR
    NEW.user_id          IS DISTINCT FROM OLD.user_id
  ) THEN
    IF NOT (
      public.current_is_full_access()
      OR public.has_permission('people.employee.update_sensitive')
    ) THEN
      RAISE EXCEPTION 'ERR_FORBIDDEN: تعديل الحقول الحساسة يتطلب صلاحية people.employee.update_sensitive'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  RETURN NEW;
END
$$;

-- 3) rpc_revoke_role -- حماية أدوار full-access (تماثل مع rpc_assign_role)
CREATE OR REPLACE FUNCTION public.rpc_revoke_role(p_user_id uuid, p_role_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_role public.roles;
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('access.role.remove')) THEN
    RAISE EXCEPTION 'not authorized to revoke roles' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_role FROM public.roles WHERE id = p_role_id;
  IF v_role.id IS NULL THEN
    RAISE EXCEPTION 'role not found' USING ERRCODE = '22023';
  END IF;

  IF v_role.is_full_access AND NOT public.current_is_super_admin() THEN
    RAISE EXCEPTION 'only super-admin may revoke a full-access role' USING ERRCODE = '42501';
  END IF;

  IF p_user_id = auth.uid() AND v_role.is_full_access THEN
    RAISE EXCEPTION 'cannot revoke your own full access' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_roles WHERE user_id = p_user_id AND role_id = p_role_id;

  PERFORM public.log_audit_event(
    'access.role.revoked',
    'access',
    'notice',
    'user_roles',
    p_role_id,
    'تم سحب دور «' || coalesce(v_role.name_ar, v_role.slug) || '»',
    'Role "' || v_role.slug || '" revoked',
    jsonb_build_object(
      'role_slug', v_role.slug,
      'role_id', p_role_id,
      'target_user_id', p_user_id
    )
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_revoke_role(uuid, uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.rpc_revoke_role(uuid, uuid) TO authenticated;

-- 4) مهام لوحة العمليات -- فرض tasks.write + تحقق صحة المدخلات
CREATE OR REPLACE FUNCTION public.admin_create_task(
  p_title       text,
  p_description text DEFAULT NULL,
  p_assignee_id uuid DEFAULT NULL,
  p_priority    text DEFAULT 'medium',
  p_due_date    date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY INVOKER
AS $$
DECLARE
  v_id     uuid;
  v_emp_id uuid;
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('tasks.write')) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: إنشاء المهام يتطلب صلاحية tasks.write' USING ERRCODE = '42501';
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

REVOKE ALL ON FUNCTION public.admin_create_task(text, text, uuid, text, date) FROM anon;

CREATE OR REPLACE FUNCTION public.admin_transition_task(
  p_id     uuid,
  p_status text
)
RETURNS void
LANGUAGE plpgsql SECURITY INVOKER
AS $$
BEGIN
  IF NOT (public.current_is_full_access() OR public.has_permission('tasks.write')) THEN
    RAISE EXCEPTION 'ERR_FORBIDDEN: تغيير حالة المهام يتطلب صلاحية tasks.write' USING ERRCODE = '42501';
  END IF;

  IF p_status IS NULL OR p_status NOT IN ('pending', 'in_progress', 'done', 'cancelled') THEN
    RAISE EXCEPTION 'INVALID_TASK_STATUS' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tasks
  SET status = p_status, updated_at = now()
  WHERE id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_transition_task(uuid, text) FROM anon;

-- 5) بوابة get_enterprise_management_catalog -- إضافة organization.entity.read
CREATE OR REPLACE FUNCTION public.get_enterprise_management_catalog()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
BEGIN
  IF NOT (
    public.current_is_full_access()
    OR public.has_any_permission(array[
      'organization.entity.read',
      'strategy.objective.manage','projects.project.manage','risk.risk.manage',
      'service.request.manage','meetings.meeting.manage','quality.capa.manage',
      'audit.internal.manage','automation.rule.manage','governance.data.manage',
      'governance.ai.manage'
    ])
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'objectives', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',code,'title',title,'level',level,'status',status,'progress',progress,'periodEnd',period_end) ORDER BY created_at DESC) FROM public.strategic_objectives),'[]'::jsonb),
    'projects', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name,'status',status,'priority',priority,'progress',progress,'targetEndDate',target_end_date,'openTasks',(SELECT count(*) FROM public.project_tasks t WHERE t.project_id=p.id AND t.status NOT IN ('done','cancelled'))) ORDER BY created_at DESC) FROM public.enterprise_projects p),'[]'::jsonb),
    'risks', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'number',risk_number,'title',title,'category',category,'probability',probability,'impact',impact,'score',probability*impact,'status',status,'reviewDate',review_date) ORDER BY probability*impact DESC) FROM public.enterprise_risks),'[]'::jsonb),
    'incidents', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'number',incident_number,'title',title,'severity',severity,'status',status,'occurredAt',occurred_at) ORDER BY created_at DESC) FROM public.enterprise_incidents),'[]'::jsonb),
    'serviceRequests', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',r.id,'number',r.request_number,'serviceName',c.name_ar,'requesterName',e.full_name_ar,'title',r.title,'priority',r.priority,'status',r.status,'dueAt',r.due_at) ORDER BY r.created_at DESC) FROM public.service_requests r JOIN public.service_catalog_items c ON c.id=r.catalog_item_id JOIN public.employees e ON e.id=r.requester_employee_id),'[]'::jsonb),
    'meetings', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'title',title,'meetingType',meeting_type,'startsAt',starts_at,'status',status,'minutesStatus',minutes_status,'decisions',(SELECT count(*) FROM public.meeting_decisions d WHERE d.meeting_id=m.id)) ORDER BY starts_at DESC NULLS LAST) FROM public.enterprise_meetings m),'[]'::jsonb),
    'qualityCases', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'number',case_number,'title',title,'severity',severity,'status',status,'dueAt',due_at) ORDER BY created_at DESC) FROM public.quality_cases),'[]'::jsonb),
    'audits', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',audit_code,'title',title,'status',status,'plannedStart',planned_start,'findings',(SELECT count(*) FROM public.audit_findings f WHERE f.audit_id=a.id)) ORDER BY planned_start DESC NULLS LAST) FROM public.internal_audits a),'[]'::jsonb),
    'automations', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'eventType',event_type,'version',version,'active',active,'requiresApproval',requires_approval) ORDER BY created_at DESC) FROM public.automation_rules),'[]'::jsonb),
    'dataAssets', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'sourceSystem',source_system,'classification',classification,'active',active) ORDER BY name_ar) FROM public.data_assets),'[]'::jsonb),
    'aiUseCases', COALESCE((SELECT jsonb_agg(jsonb_build_object('id',id,'code',code,'name',name_ar,'purpose',purpose,'provider',model_provider,'modelName',model_name,'riskLevel',risk_level,'humanReviewRequired',human_review_required,'active',active) ORDER BY name_ar) FROM public.ai_use_cases),'[]'::jsonb),
    'lastUpdatedAt', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_enterprise_management_catalog() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.get_enterprise_management_catalog() TO authenticated;

COMMIT;
