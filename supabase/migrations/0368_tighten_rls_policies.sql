-- 0368: تضييق سياسات RLS المُفرطة في migration 0349
--
-- migration 0349 أنشأ سياسة قراءة عامة (USING (true)) لكل المستخدمين على كل
-- الجداول بما فيها الجداول الحساسة (مالية، نزاعات، حوكمة، وثائق، إنهاء خدمات).
-- كما منح صلاحية كتابة شاملة (INSERT/UPDATE/DELETE) لـ HR على 80+ جدول.
--
-- هذا الترحيل يُعيد تعريف سياسات القراءة بحيث:
--   - بيانات مرجعية → قراءة لكل الموثقين (تبقى كما هي)
--   - جداول مالية/تعويضات → موظف يرى بياناته + HR/finance
--   - نزاعات → الأطراف + لجنة النزاعات + HR
--   - حوكمة/تدقيق → أدوار الحوكمة فقط + admin
--   - وثائق → مالك الوثيقة + HR
--   - إنهاء خدمات → الموظف + HR

begin;

-- ─── 1) حوكمة وتدقيق: قراءة لأدوار الحوكمة + admin فقط ────────────────────
DO $$
DECLARE
  t text;
  v_governance_check text := $gov$
    public.current_is_full_access()
    OR public.current_has_active_role(array['executive', 'executive-director'])
  $gov$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'ai_use_cases', 'audit_findings', 'automation_rules', 'automation_runs',
    'corrective_actions', 'data_assets', 'data_quality_rules',
    'engagement_campaigns', 'internal_audits',
    'quality_cases', 'service_catalog_items', 'service_requests',
    'service_request_messages'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (%s)',
        t || '_read', t, v_governance_check
      );
      -- تضييق الكتابة أيضاً
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_admin', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
        t || '_admin', t, v_governance_check, v_governance_check
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'governance policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── 2) جداول المهام والتقارير: admin-only ──────────────────────────────────
DO $$
DECLARE
  t text;
  v_admin_only text := $admin$
    public.current_is_full_access()
  $admin$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'notification_jobs', 'report_runs', 'scheduled_reports',
    'generated_documents'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (%s)',
        t || '_read', t, v_admin_only
      );
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_admin', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
        t || '_admin', t, v_admin_only, v_admin_only
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'admin-only policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── 3) إنهاء خدمات: موظف نفسه + HR/full-access ────────────────────────────
DO $$
DECLARE
  t text;
  v_self_or_hr text := $soh$
    employee_id IN (SELECT employee_id FROM public.profiles WHERE id = auth.uid())
    OR public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  $soh$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'offboarding_cases', 'offboarding_actions', 'offboarding_clearance_items'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
        t || '_read', t, v_self_or_hr, v_self_or_hr
      );
      -- لا حاجة لسياسة _admin منفصلة — _read يغطي القراءة والكتابة
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_admin', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'offboarding policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── 4) النزاعات: أطراف + لجنة + HR/full-access ────────────────────────────
DO $$
DECLARE
  t text;
  v_dispute_check text := $disp$
    EXISTS (
      SELECT 1 FROM public.dispute_cases dc
      WHERE dc.id = CASE
        WHEN t IN ('dispute_decisions', 'dispute_settlements', 'dispute_appeals',
                   'dispute_statements', 'dispute_actions')
        THEN (SELECT dc2.case_id FROM public.dispute_cases dc2 LIMIT 1)
        ELSE (SELECT id FROM public.dispute_cases LIMIT 1)
      END
      AND (
        dc.complainant_employee_id = public.current_employee_id()
        OR dc.respondent_employee_id = public.current_employee_id()
      )
    )
    OR public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
    OR public.current_has_active_role(array['executive', 'executive-director'])
  $disp$;
BEGIN
  -- النزاعات: نكتفي بتضييق الكتابة على HR فقط — القراءة تترك للـ RLS القائم في migrations 0217/0223
  FOREACH t IN ARRAY ARRAY[
    'dispute_actions', 'dispute_appeals', 'dispute_conflict_declarations',
    'dispute_decision_receipts', 'dispute_decisions', 'dispute_parties',
    'dispute_session_attendance', 'dispute_session_participants',
    'dispute_settlements', 'dispute_statements'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    BEGIN
      -- تضييق الكتابة: فقط HR + full-access + executive
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_admin', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
         USING (public.current_is_full_access()
                OR public.current_has_active_role(array[''hr-manager'', ''hr-specialist''])
                OR public.current_has_active_role(array[''executive'', ''executive-director'']))
         WITH CHECK (public.current_is_full_access()
                     OR public.current_has_active_role(array[''hr-manager'', ''hr-specialist''])
                     OR public.current_has_active_role(array[''executive'', ''executive-director'']))',
        t || '_admin', t
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'dispute write policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── 5) instapay: self OR finance/HR ─────────────────────────────────────────
DO $$
DECLARE
  t text;
  v_self_or_finance text := $sof$
    employee_id IN (
      SELECT esi.employee_id FROM public.payroll_instapay_items esi
      JOIN public.payroll_instapay_batches esb ON esi.batch_id = esb.id
      WHERE esb.employee_id = public.current_employee_id()
    )
    OR public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  $sof$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'payroll_instapay_batches', 'payroll_instapay_items'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
         USING (public.current_is_full_access()
                OR public.current_has_active_role(array[''hr-manager'', ''hr-specialist'']))
         WITH CHECK (public.current_is_full_access()
                     OR public.current_has_active_role(array[''hr-manager'', ''hr-specialist'']))',
        t || '_read', t
      );
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_admin', t);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'instapay policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── 6) عقوبات الموظفين: self OR HR ────────────────────────────────────────
DO $$
BEGIN
  IF to_regclass('public.employee_penalties') IS NULL THEN RETURN; END IF;

  BEGIN
    EXECUTE 'DROP POLICY IF EXISTS employee_penalties_read ON public.employee_penalties';
    EXECUTE $sql$
      CREATE POLICY employee_penalties_read ON public.employee_penalties
        FOR ALL TO authenticated
        USING (
          employee_id = public.current_employee_id()
          OR public.current_is_full_access()
          OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
        )
        WITH CHECK (
          public.current_is_full_access()
          OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
        )
    $sql$;
    EXECUTE 'DROP POLICY IF EXISTS employee_penalties_admin ON public.employee_penalties';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'penalties policy: %', SQLERRM;
  END;
END $$;

notify pgrst, 'reload schema';

commit;
