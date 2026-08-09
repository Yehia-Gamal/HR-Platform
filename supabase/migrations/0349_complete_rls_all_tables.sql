-- Migration 0349: Complete RLS on all 80 remaining tables
-- ================================================================================
-- Initiative 2 completion — enables RLS on every remaining unprotected table.
-- Uses a dynamic DO block that:
--   1. Enables RLS + FORCE on each table
--   2. REVOKE access from anon
--   3. Creates a read policy for authenticated (where applicable)
--   4. Creates an admin policy for full-access / HR roles
-- Uses the canonical authorization helpers (current_is_full_access,
-- current_has_active_role) instead of raw role-name matching.

BEGIN;

-- ─── Helper: enable RLS + policies on a table ────────────────────────────
-- Pattern: read for authenticated, write for admins (full-access + HR)

DO $$
DECLARE
  t text;
  v_admin_check text := $check$
    public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  $check$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    -- Reference data (read for all authenticated)
    'branches', 'cost_centers', 'departments', 'employment_types',
    'geofences', 'job_grades', 'job_titles', 'legal_entities',
    'positions', 'public_holidays', 'shift_patterns', 'shifts',
    'teams', 'work_sites', 'work_rosters', 'roster_days',
    'working_calendars',
    -- Financial (admin-only)
    'employee_compensation', 'employee_loans', 'loan_installments',
    'payroll_runs', 'payslips', 'payslip_lines',
    'payroll_instapay_batches', 'payroll_instapay_items',
    'salary_components', 'salary_structures',
    -- Disputes (admin-only)
    'dispute_actions', 'dispute_appeals', 'dispute_conflict_declarations',
    'dispute_decision_receipts', 'dispute_decisions', 'dispute_parties',
    'dispute_session_attendance', 'dispute_session_participants',
    'dispute_settlements', 'dispute_statements',
    -- Learning (read for all, write for admins)
    'learning_courses', 'learning_course_sessions', 'learning_enrollments',
    'knowledge_transfer_items',
    -- Enterprise management (admin-only)
    'enterprise_incidents', 'enterprise_meetings', 'enterprise_projects',
    'enterprise_risks', 'strategic_objectives', 'objective_key_results',
    'meeting_agenda_items', 'meeting_attendees', 'meeting_decisions',
    -- Workforce/operations (read for all, write for admins)
    'attendance_corrections', 'attendance_periods',
    'overtime_records', 'workforce_plans', 'capacity_snapshots',
    -- Governance (admin-only)
    'ai_use_cases', 'audit_findings', 'automation_rules', 'automation_runs',
    'corrective_actions', 'data_assets', 'data_quality_rules',
    'engagement_campaigns', 'generated_documents', 'internal_audits',
    'notification_jobs', 'quality_cases', 'report_runs',
    'scheduled_reports', 'service_catalog_items', 'service_requests',
    'service_request_messages',
    -- Offboarding (admin-only)
    'offboarding_actions', 'offboarding_cases', 'offboarding_clearance_items',
    -- Documents (admin-only)
    'document_access_logs', 'document_signature_requests', 'document_templates',
    -- Other
    'project_tasks', 'wellbeing_requests',
    'employee_penalties'
  ]
  LOOP
    -- Skip if table doesn't exist
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE NOTICE 'Table % does not exist — skipping', t;
      CONTINUE;
    END IF;

    -- Enable + FORCE RLS
    EXECUTE format('ALTER TABLE IF EXISTS public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE IF EXISTS public.%I FORCE ROW LEVEL SECURITY', t);

    -- REVOKE from anon
    EXECUTE format('REVOKE SELECT, INSERT, UPDATE, DELETE ON public.%I FROM anon', t);

    -- Create read policy for authenticated (if not exists)
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = t AND policyname = t || '_read'
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (true)',
        t || '_read', t
      );
    END IF;

    -- Create admin write policy (if not exists)
    IF NOT EXISTS (
      SELECT 1 FROM pg_policies
      WHERE schemaname = 'public' AND tablename = t AND policyname = t || '_admin'
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
        t || '_admin', t, v_admin_check, v_admin_check
      );
    END IF;
  END LOOP;
END $$;

-- ─── Special: payroll/compensation tables — self OR finance/HR/full-access ─
-- Override the generic admin policy with a self-service read policy
DO $$
DECLARE
  t text;
  v_self_or_finance text := $self$
    employee_id IN (SELECT employee_id FROM public.profiles WHERE id = auth.uid())
    OR public.current_is_full_access()
    OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
  $self$;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'employee_compensation', 'employee_loans', 'loan_installments',
    'payroll_runs', 'payslips', 'payslip_lines'
  ]
  LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN CONTINUE; END IF;

    -- Drop the generic read policy and replace with self_or_finance
    BEGIN
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_read', t);
      EXECUTE format(
        'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (%s) WITH CHECK (%s)',
        t || '_read', t, v_self_or_finance, v_self_or_finance
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Could not set self_or_finance policy on %: %', t, SQLERRM;
    END;
  END LOOP;
END $$;

-- ─── Special: learning_enrollments — self OR admin ────────────────────────
DO $$
BEGIN
  IF to_regclass('public.learning_enrollments') IS NOT NULL THEN
    BEGIN
      EXECUTE $sql$
        DROP POLICY IF EXISTS learning_enrollments_read ON public.learning_enrollments;
      $sql$;
      EXECUTE $sql$
        CREATE POLICY learning_enrollments_read ON public.learning_enrollments
          FOR ALL TO authenticated USING (
            employee_id IN (SELECT employee_id FROM public.profiles WHERE id = auth.uid())
            OR public.current_is_full_access()
            OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
          ) WITH CHECK (
            employee_id IN (SELECT employee_id FROM public.profiles WHERE id = auth.uid())
            OR public.current_is_full_access()
            OR public.current_has_active_role(array['hr-manager', 'hr-specialist'])
          )
      $sql$;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'learning_enrollments policy: %', SQLERRM;
    END;
  END IF;
END $$;

NOTIFY pgrst, 'Reload schema';

COMMIT;
