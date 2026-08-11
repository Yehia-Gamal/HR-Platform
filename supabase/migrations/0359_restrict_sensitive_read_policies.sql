-- Migration 0359: تقييد سياسات القراءة الواسعة على الجداول الحساسة
-- ================================================================================
-- Migration 0349 (complete_rls_all_tables) أنشأ سياسة قراءة {t}_read USING(true)
-- لكل جدول لم تكن لديه سياسة *_read سابقة — فتوسّعت قراءة الجداول الحساسة لأي
-- authenticated user (رواتب، مخالفات، تدقيق، نزاعات، مغادرة، مستندات،...).
--
-- RLS يدمج السياسات المتساهلة بـ OR، لذا الحل الصحيح: حذف السياسة الواسعة
-- واستبدالها بسياسة {t}_restricted_read تعتمد على current_is_full_access /
-- current_has_active_role / has_permission.
--
-- ملاحظة: الجداول المرجعية للقراءة (branches, departments, shifts, ...) تبقى
-- using(true) — مقبولة بقاعدة المشروع للجداول المرجعية.

BEGIN;

-- قائمة الجداول الحساسة التي حصلت على {t}_read USING(true) من 0349
DO $$
DECLARE
  t text;
  v_admin text := $x$
    public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  $x$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- مالية
    'salary_components', 'salary_structures',
    'payroll_instapay_batches', 'payroll_instapay_items',
    'employee_penalties',
    -- حوكمة/تدقيق
    'audit_findings', 'internal_audits', 'ai_use_cases',
    'automation_rules', 'automation_runs', 'corrective_actions',
    'data_assets', 'data_quality_rules', 'notification_jobs',
    'quality_cases', 'service_catalog_items', 'service_request_messages',
    -- نزاعات
    'dispute_conflict_declarations', 'dispute_session_attendance',
    -- مؤسسة
    'enterprise_incidents', 'enterprise_meetings', 'enterprise_projects',
    'enterprise_risks', 'strategic_objectives', 'objective_key_results',
    'meeting_agenda_items', 'meeting_attendees', 'meeting_decisions',
    -- مغادرة/مستندات
    'offboarding_clearance_items', 'document_signature_requests',
    -- أخرى
    'project_tasks'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE NOTICE 'Table % does not exist — skipping', t;
      CONTINUE;
    END IF;

    -- إزالة السياسة الواسعة إن وُجدت (سواء من 0349 أو قبلها)
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);

    -- إنشاء سياسة قراءة مقيدة
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (%s)',
      t || '_restricted_read', t, v_admin
    );
  END LOOP;
END $$;

-- salary_components / salary_structures: صلاحية payroll.structure.manage
-- (استعادة نية 0216 التي حصرتها في full_access / has_permission)
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['salary_components', 'salary_structures']
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_restricted_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_payroll_read', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (%s)',
      t || '_payroll_read', t,
      'public.current_is_full_access() OR public.has_permission(''payroll.structure.manage'')'
    );
  END LOOP;
END $$;

-- wellbeing_requests: يرى الموظف طلباته فقط، أو مَن لديه صلاحية الإدارة
DO $$
BEGIN
  IF to_regclass('public.wellbeing_requests') IS NOT NULL THEN
    DROP POLICY IF EXISTS wellbeing_requests_read ON public.wellbeing_requests;
    DROP POLICY IF EXISTS wellbeing_requests_restricted_read ON public.wellbeing_requests;
    CREATE POLICY wellbeing_requests_self_read ON public.wellbeing_requests
      FOR SELECT TO authenticated
      USING (
        employee_id = public.current_employee_id()
        OR public.current_is_full_access()
        OR public.has_permission('wellbeing.request.manage')
      );
  END IF;
END $$;

-- employee_penalties: full_access أو صلاحيات المسير/القراءة
DO $$
BEGIN
  IF to_regclass('public.employee_penalties') IS NOT NULL THEN
    DROP POLICY IF EXISTS employee_penalties_read ON public.employee_penalties;
    DROP POLICY IF EXISTS employee_penalties_restricted_read ON public.employee_penalties;
    CREATE POLICY employee_penalties_payroll_read ON public.employee_penalties
      FOR SELECT TO authenticated
      USING (
        public.current_is_full_access()
        OR public.has_any_permission(array['payroll.run.manage', 'payroll.run.approve', 'people.employee.read'])
      );
  END IF;
END $$;

NOTIFY pgrst, 'Reload schema';

COMMIT;
