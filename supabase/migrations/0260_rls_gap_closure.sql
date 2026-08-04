-- 0260: Conservatively close remaining public-table RLS gaps.
--
-- Existing policies are preserved. Tables without a policy receive either:
--   * authenticated read-only access for non-sensitive reference catalogs; or
--   * full-access-only access for operational/sensitive data.
-- This migration intentionally does not add permissive policies to financial
-- tables already hardened by migrations 0216 and 0230.

begin;
do $rls$
declare
  v_table text;
  v_reference_tables constant text[] := array[
    'branches', 'cost_centers', 'departments', 'employment_types',
    'job_grades', 'job_titles', 'legal_entities', 'positions', 'teams',
    'work_sites', 'working_calendars', 'public_holidays',
    'learning_courses', 'learning_course_sessions',
    'service_catalog_items', 'document_templates'
  ];
  v_operational_tables constant text[] := array[
    'ai_use_cases', 'audit_findings', 'automation_rules', 'automation_runs',
    'capacity_snapshots', 'corrective_actions', 'data_assets',
    'data_quality_rules', 'dispute_actions', 'dispute_appeals',
    'dispute_conflict_declarations', 'dispute_decision_receipts',
    'dispute_decisions', 'dispute_parties', 'dispute_session_attendance',
    'dispute_session_participants', 'dispute_settlements',
    'dispute_statements', 'document_access_logs',
    'document_signature_requests', 'engagement_campaigns',
    'enterprise_incidents', 'enterprise_meetings', 'enterprise_projects',
    'enterprise_risks', 'generated_documents', 'geofences',
    'internal_audits', 'knowledge_transfer_items', 'learning_enrollments',
    'meeting_agenda_items', 'meeting_attendees', 'meeting_decisions',
    'notification_jobs', 'objective_key_results', 'offboarding_actions',
    'offboarding_cases', 'offboarding_clearance_items', 'overtime_records',
    'project_tasks', 'quality_cases', 'report_runs', 'roster_days',
    'scheduled_reports', 'service_request_messages', 'service_requests',
    'shift_patterns', 'shifts', 'strategic_objectives', 'wellbeing_requests',
    'work_rosters', 'workforce_plans', 'attendance_corrections',
    'attendance_periods'
  ];
  v_financial_tables constant text[] := array[
    'employee_compensation', 'employee_loans', 'loan_installments',
    'payroll_runs', 'payslips', 'payslip_lines', 'salary_components',
    'salary_structures'
  ];
begin
  foreach v_table in array v_reference_tables || v_operational_tables || v_financial_tables loop
    if to_regclass(format('public.%I', v_table)) is null then
      continue;
    end if;
    execute format('alter table public.%I enable row level security', v_table);
    execute format('alter table public.%I force row level security', v_table);
    execute format('revoke all on table public.%I from public, anon', v_table);
  end loop;

  foreach v_table in array v_reference_tables loop
    if to_regclass(format('public.%I', v_table)) is null then
      continue;
    end if;
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = v_table
    ) then
      execute format(
        'create policy %I on public.%I for select to authenticated using (true)',
        v_table || '_authenticated_read', v_table
      );
      execute format(
        'create policy %I on public.%I for all to authenticated '
        'using (public.current_is_full_access()) '
        'with check (public.current_is_full_access())',
        v_table || '_full_access_manage', v_table
      );
    end if;
  end loop;

  foreach v_table in array v_operational_tables loop
    if to_regclass(format('public.%I', v_table)) is null then
      continue;
    end if;
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = v_table
    ) then
      execute format(
        'create policy %I on public.%I for all to authenticated '
        'using (public.current_is_full_access()) '
        'with check (public.current_is_full_access())',
        v_table || '_rls_gap_full_access', v_table
      );
    end if;
  end loop;
end
$rls$;
commit;
