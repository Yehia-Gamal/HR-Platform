-- فهارس FK المفقودة — تسريع استعلامات JOIN و DELETE على أعمدة المفاتيح الخارجية
-- تم إنشاؤها تلقائياً بواسطة فحص Supabase العميق
-- يستثنى: أعمدة التدقيق (created_by, updated_by, etc.)

BEGIN;

-- administrative_decisions
CREATE INDEX IF NOT EXISTS idx_administrative_decisions_implementation_owner_id ON public.administrative_decisions (implementation_owner_id);
CREATE INDEX IF NOT EXISTS idx_administrative_decisions_issued_by ON public.administrative_decisions (issued_by);

-- ai_use_cases
CREATE INDEX IF NOT EXISTS idx_ai_use_cases_owner_employee_id ON public.ai_use_cases (owner_employee_id);

-- app_error_events
CREATE INDEX IF NOT EXISTS idx_app_error_events_employee_id ON public.app_error_events (employee_id);

-- application_stage_history
CREATE INDEX IF NOT EXISTS idx_application_stage_history_from_stage ON public.application_stage_history (from_stage);
CREATE INDEX IF NOT EXISTS idx_application_stage_history_moved_by ON public.application_stage_history (moved_by);
CREATE INDEX IF NOT EXISTS idx_application_stage_history_to_stage ON public.application_stage_history (to_stage);

-- asset_assignments
CREATE INDEX IF NOT EXISTS idx_asset_assignments_handed_over_by ON public.asset_assignments (handed_over_by);
CREATE INDEX IF NOT EXISTS idx_asset_assignments_return_received_by ON public.asset_assignments (return_received_by);

-- attendance_corrections
CREATE INDEX IF NOT EXISTS idx_attendance_corrections_attendance_daily_id ON public.attendance_corrections (attendance_daily_id);
CREATE INDEX IF NOT EXISTS idx_attendance_corrections_employee_id ON public.attendance_corrections (employee_id);

-- attendance_daily
CREATE INDEX IF NOT EXISTS idx_attendance_daily_shift_id ON public.attendance_daily (shift_id);

-- attendance_events
CREATE INDEX IF NOT EXISTS idx_attendance_events_geofence_id ON public.attendance_events (geofence_id);
CREATE INDEX IF NOT EXISTS idx_attendance_events_passkey_credential_id ON public.attendance_events (passkey_credential_id);
CREATE INDEX IF NOT EXISTS idx_attendance_events_shift_assignment_id ON public.attendance_events (shift_assignment_id);

-- attendance_exceptions
CREATE INDEX IF NOT EXISTS idx_attendance_exceptions_attendance_daily_id ON public.attendance_exceptions (attendance_daily_id);
CREATE INDEX IF NOT EXISTS idx_attendance_exceptions_attendance_event_id ON public.attendance_exceptions (attendance_event_id);

-- attendance_identity_checks
CREATE INDEX IF NOT EXISTS idx_attendance_identity_checks_passkey_credential_id ON public.attendance_identity_checks (passkey_credential_id);

-- attendance_periods
CREATE INDEX IF NOT EXISTS idx_attendance_periods_unlocked_by ON public.attendance_periods (unlocked_by);

-- attendance_punch_attempts
CREATE INDEX IF NOT EXISTS idx_attendance_punch_attempts_attendance_event_id ON public.attendance_punch_attempts (attendance_event_id);
CREATE INDEX IF NOT EXISTS idx_attendance_punch_attempts_credential_id ON public.attendance_punch_attempts (credential_id);

-- attendance_risk_events
CREATE INDEX IF NOT EXISTS idx_attendance_risk_events_identity_check_id ON public.attendance_risk_events (identity_check_id);

-- audit_events
CREATE INDEX IF NOT EXISTS idx_audit_events_actor_employee_id ON public.audit_events (actor_employee_id);

-- audit_findings
CREATE INDEX IF NOT EXISTS idx_audit_findings_owner_employee_id ON public.audit_findings (owner_employee_id);

-- audit_logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor_employee_id ON public.audit_logs (actor_employee_id);

-- automation_runs
CREATE INDEX IF NOT EXISTS idx_automation_runs_rule_id ON public.automation_runs (rule_id);

-- break_glass_requests
CREATE INDEX IF NOT EXISTS idx_break_glass_requests_requested_role_id ON public.break_glass_requests (requested_role_id);
CREATE INDEX IF NOT EXISTS idx_break_glass_requests_user_role_id ON public.break_glass_requests (user_role_id);

-- calibration_sessions
CREATE INDEX IF NOT EXISTS idx_calibration_sessions_facilitator_id ON public.calibration_sessions (facilitator_id);

-- corrective_actions
CREATE INDEX IF NOT EXISTS idx_corrective_actions_owner_employee_id ON public.corrective_actions (owner_employee_id);
CREATE INDEX IF NOT EXISTS idx_corrective_actions_quality_case_id ON public.corrective_actions (quality_case_id);

-- data_assets
CREATE INDEX IF NOT EXISTS idx_data_assets_owner_employee_id ON public.data_assets (owner_employee_id);
CREATE INDEX IF NOT EXISTS idx_data_assets_steward_employee_id ON public.data_assets (steward_employee_id);

-- decision_actions
CREATE INDEX IF NOT EXISTS idx_decision_actions_actor_employee_id ON public.decision_actions (actor_employee_id);
CREATE INDEX IF NOT EXISTS idx_decision_actions_decision_id ON public.decision_actions (decision_id);

-- decision_execution_items
CREATE INDEX IF NOT EXISTS idx_decision_execution_items_decision_id ON public.decision_execution_items (decision_id);
CREATE INDEX IF NOT EXISTS idx_decision_execution_items_owner_employee_id ON public.decision_execution_items (owner_employee_id);

-- decision_polls
CREATE INDEX IF NOT EXISTS idx_decision_polls_decision_id ON public.decision_polls (decision_id);

-- decision_register
CREATE INDEX IF NOT EXISTS idx_decision_register_decided_by ON public.decision_register (decided_by);

-- departments
CREATE INDEX IF NOT EXISTS idx_departments_cost_center_id ON public.departments (cost_center_id);

-- dispute_actions
CREATE INDEX IF NOT EXISTS idx_dispute_actions_actor_employee_id ON public.dispute_actions (actor_employee_id);
CREATE INDEX IF NOT EXISTS idx_dispute_actions_assigned_to ON public.dispute_actions (assigned_to);

-- dispute_appeals
CREATE INDEX IF NOT EXISTS idx_dispute_appeals_case_id ON public.dispute_appeals (case_id);

-- dispute_cases
CREATE INDEX IF NOT EXISTS idx_dispute_cases_accepted_by ON public.dispute_cases (accepted_by);
CREATE INDEX IF NOT EXISTS idx_dispute_cases_executed_by ON public.dispute_cases (executed_by);
CREATE INDEX IF NOT EXISTS idx_dispute_cases_executive_decision_by ON public.dispute_cases (executive_decision_by);
CREATE INDEX IF NOT EXISTS idx_dispute_cases_proposed_by ON public.dispute_cases (proposed_by);
CREATE INDEX IF NOT EXISTS idx_dispute_cases_respondent_employee_id ON public.dispute_cases (respondent_employee_id);

-- dispute_decisions
CREATE INDEX IF NOT EXISTS idx_dispute_decisions_implementation_owner_id ON public.dispute_decisions (implementation_owner_id);
CREATE INDEX IF NOT EXISTS idx_dispute_decisions_session_id ON public.dispute_decisions (session_id);
CREATE INDEX IF NOT EXISTS idx_dispute_decisions_supersedes_decision_id ON public.dispute_decisions (supersedes_decision_id);

-- dispute_sessions
CREATE INDEX IF NOT EXISTS idx_dispute_sessions_chaired_by ON public.dispute_sessions (chaired_by);

-- dispute_settlements
CREATE INDEX IF NOT EXISTS idx_dispute_settlements_apology_from ON public.dispute_settlements (apology_from);
CREATE INDEX IF NOT EXISTS idx_dispute_settlements_apology_to ON public.dispute_settlements (apology_to);
CREATE INDEX IF NOT EXISTS idx_dispute_settlements_case_id ON public.dispute_settlements (case_id);
CREATE INDEX IF NOT EXISTS idx_dispute_settlements_confirmed_by ON public.dispute_settlements (confirmed_by);

-- dispute_statements
CREATE INDEX IF NOT EXISTS idx_dispute_statements_party_id ON public.dispute_statements (party_id);

-- document_access_logs
CREATE INDEX IF NOT EXISTS idx_document_access_logs_actor_employee_id ON public.document_access_logs (actor_employee_id);
CREATE INDEX IF NOT EXISTS idx_document_access_logs_employee_document_id ON public.document_access_logs (employee_document_id);

-- document_signature_requests
CREATE INDEX IF NOT EXISTS idx_document_signature_requests_signer_employee_id ON public.document_signature_requests (signer_employee_id);

-- employee_assignments
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_branch_id ON public.employee_assignments (from_branch_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_department_id ON public.employee_assignments (from_department_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_grade_id ON public.employee_assignments (from_grade_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_job_title_id ON public.employee_assignments (from_job_title_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_position_id ON public.employee_assignments (from_position_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_from_team_id ON public.employee_assignments (from_team_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_branch_id ON public.employee_assignments (to_branch_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_department_id ON public.employee_assignments (to_department_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_grade_id ON public.employee_assignments (to_grade_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_job_title_id ON public.employee_assignments (to_job_title_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_position_id ON public.employee_assignments (to_position_id);
CREATE INDEX IF NOT EXISTS idx_employee_assignments_to_team_id ON public.employee_assignments (to_team_id);

-- employee_compensation
CREATE INDEX IF NOT EXISTS idx_employee_compensation_structure_id ON public.employee_compensation (structure_id);

-- employee_competency_assessments
CREATE INDEX IF NOT EXISTS idx_employee_competency_assessments_assessor_id ON public.employee_competency_assessments (assessor_id);

-- employee_loans
CREATE INDEX IF NOT EXISTS idx_employee_loans_employee_id ON public.employee_loans (employee_id);

-- employees
CREATE INDEX IF NOT EXISTS idx_employees_employment_type_id ON public.employees (employment_type_id);
CREATE INDEX IF NOT EXISTS idx_employees_grade_id ON public.employees (grade_id);
CREATE INDEX IF NOT EXISTS idx_employees_job_title_id ON public.employees (job_title_id);
CREATE INDEX IF NOT EXISTS idx_employees_position_id ON public.employees (position_id);
CREATE INDEX IF NOT EXISTS idx_employees_work_site_id ON public.employees (work_site_id);

-- enterprise_incidents
CREATE INDEX IF NOT EXISTS idx_enterprise_incidents_assigned_to_employee_id ON public.enterprise_incidents (assigned_to_employee_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_incidents_reported_by_employee_id ON public.enterprise_incidents (reported_by_employee_id);

-- enterprise_meetings
CREATE INDEX IF NOT EXISTS idx_enterprise_meetings_organizer_employee_id ON public.enterprise_meetings (organizer_employee_id);

-- enterprise_projects
CREATE INDEX IF NOT EXISTS idx_enterprise_projects_department_id ON public.enterprise_projects (department_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_projects_manager_employee_id ON public.enterprise_projects (manager_employee_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_projects_objective_id ON public.enterprise_projects (objective_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_projects_sponsor_employee_id ON public.enterprise_projects (sponsor_employee_id);

-- enterprise_risks
CREATE INDEX IF NOT EXISTS idx_enterprise_risks_owner_employee_id ON public.enterprise_risks (owner_employee_id);
CREATE INDEX IF NOT EXISTS idx_enterprise_risks_project_id ON public.enterprise_risks (project_id);

-- generated_documents
CREATE INDEX IF NOT EXISTS idx_generated_documents_employee_id ON public.generated_documents (employee_id);
CREATE INDEX IF NOT EXISTS idx_generated_documents_template_id ON public.generated_documents (template_id);

-- improvement_plans
CREATE INDEX IF NOT EXISTS idx_improvement_plans_hr_owner_id ON public.improvement_plans (hr_owner_id);
CREATE INDEX IF NOT EXISTS idx_improvement_plans_manager_id ON public.improvement_plans (manager_id);

-- incidents
CREATE INDEX IF NOT EXISTS idx_incidents_reported_by ON public.incidents (reported_by);

-- integration_outbox
CREATE INDEX IF NOT EXISTS idx_integration_outbox_integration_id ON public.integration_outbox (integration_id);

-- integrations
CREATE INDEX IF NOT EXISTS idx_integrations_vault_key_name ON public.integrations (vault_key_name);

-- internal_audits
CREATE INDEX IF NOT EXISTS idx_internal_audits_lead_auditor_employee_id ON public.internal_audits (lead_auditor_employee_id);

-- job_requisitions
CREATE INDEX IF NOT EXISTS idx_job_requisitions_requested_by ON public.job_requisitions (requested_by);

-- knowledge_articles
CREATE INDEX IF NOT EXISTS idx_knowledge_articles_author_employee_id ON public.knowledge_articles (author_employee_id);

-- knowledge_transfer_items
CREATE INDEX IF NOT EXISTS idx_knowledge_transfer_items_destination_employee_id ON public.knowledge_transfer_items (destination_employee_id);
CREATE INDEX IF NOT EXISTS idx_knowledge_transfer_items_offboarding_case_id ON public.knowledge_transfer_items (offboarding_case_id);

-- kpi_cycles
CREATE INDEX IF NOT EXISTS idx_kpi_cycles_opened_by ON public.kpi_cycles (opened_by);
CREATE INDEX IF NOT EXISTS idx_kpi_cycles_overridden_by ON public.kpi_cycles (overridden_by);
CREATE INDEX IF NOT EXISTS idx_kpi_cycles_policy_version_id ON public.kpi_cycles (policy_version_id);
CREATE INDEX IF NOT EXISTS idx_kpi_cycles_template_id ON public.kpi_cycles (template_id);

-- kpi_evaluations
CREATE INDEX IF NOT EXISTS idx_kpi_evaluations_hr_approved_by ON public.kpi_evaluations (hr_approved_by);
CREATE INDEX IF NOT EXISTS idx_kpi_evaluations_manager_approved_by ON public.kpi_evaluations (manager_approved_by);

-- kpi_goals
CREATE INDEX IF NOT EXISTS idx_kpi_goals_manager_approved_by ON public.kpi_goals (manager_approved_by);

-- kpi_notification_receipts
CREATE INDEX IF NOT EXISTS idx_kpi_notification_receipts_notification_id ON public.kpi_notification_receipts (notification_id);

-- kpi_review_sessions
CREATE INDEX IF NOT EXISTS idx_kpi_review_sessions_employee_id ON public.kpi_review_sessions (employee_id);
CREATE INDEX IF NOT EXISTS idx_kpi_review_sessions_manager_employee_id ON public.kpi_review_sessions (manager_employee_id);

-- kpi_stage_history
CREATE INDEX IF NOT EXISTS idx_kpi_stage_history_actor_employee_id ON public.kpi_stage_history (actor_employee_id);

-- leave_ledger_entries
CREATE INDEX IF NOT EXISTS idx_leave_ledger_entries_account_id ON public.leave_ledger_entries (account_id);
CREATE INDEX IF NOT EXISTS idx_leave_ledger_entries_leave_type_id ON public.leave_ledger_entries (leave_type_id);

-- leave_requests
CREATE INDEX IF NOT EXISTS idx_leave_requests_substitute_employee_id ON public.leave_requests (substitute_employee_id);

-- live_location_map_access_logs
CREATE INDEX IF NOT EXISTS idx_live_location_map_access_logs_request_id ON public.live_location_map_access_logs (request_id);
CREATE INDEX IF NOT EXISTS idx_live_location_map_access_logs_response_id ON public.live_location_map_access_logs (response_id);

-- live_location_video_access_logs
CREATE INDEX IF NOT EXISTS idx_live_location_video_access_logs_actor_employee_id ON public.live_location_video_access_logs (actor_employee_id);

-- loan_installments
CREATE INDEX IF NOT EXISTS idx_loan_installments_payslip_id ON public.loan_installments (payslip_id);

-- local_attendance_operations
CREATE INDEX IF NOT EXISTS idx_local_attendance_operations_employee_id ON public.local_attendance_operations (employee_id);

-- location_request_responses
CREATE INDEX IF NOT EXISTS idx_location_request_responses_device_id ON public.location_request_responses (device_id);

-- meeting_agenda_items
CREATE INDEX IF NOT EXISTS idx_meeting_agenda_items_meeting_id ON public.meeting_agenda_items (meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_agenda_items_presenter_employee_id ON public.meeting_agenda_items (presenter_employee_id);

-- meeting_decisions
CREATE INDEX IF NOT EXISTS idx_meeting_decisions_agenda_item_id ON public.meeting_decisions (agenda_item_id);
CREATE INDEX IF NOT EXISTS idx_meeting_decisions_meeting_id ON public.meeting_decisions (meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_decisions_owner_employee_id ON public.meeting_decisions (owner_employee_id);

-- notification_delivery_log
CREATE INDEX IF NOT EXISTS idx_notification_delivery_log_subscription_id ON public.notification_delivery_log (subscription_id);

-- notification_jobs
CREATE INDEX IF NOT EXISTS idx_notification_jobs_notification_id ON public.notification_jobs (notification_id);

-- objective_key_results
CREATE INDEX IF NOT EXISTS idx_objective_key_results_objective_id ON public.objective_key_results (objective_id);

-- offboarding_actions
CREATE INDEX IF NOT EXISTS idx_offboarding_actions_actor_employee_id ON public.offboarding_actions (actor_employee_id);
CREATE INDEX IF NOT EXISTS idx_offboarding_actions_offboarding_case_id ON public.offboarding_actions (offboarding_case_id);

-- offboarding_cases
CREATE INDEX IF NOT EXISTS idx_offboarding_cases_employee_id ON public.offboarding_cases (employee_id);
CREATE INDEX IF NOT EXISTS idx_offboarding_cases_handover_employee_id ON public.offboarding_cases (handover_employee_id);

-- offboarding_clearance_items
CREATE INDEX IF NOT EXISTS idx_offboarding_clearance_items_assignee_employee_id ON public.offboarding_clearance_items (assignee_employee_id);
CREATE INDEX IF NOT EXISTS idx_offboarding_clearance_items_completed_by ON public.offboarding_clearance_items (completed_by);

-- payslip_lines
CREATE INDEX IF NOT EXISTS idx_payslip_lines_payslip_id ON public.payslip_lines (payslip_id);

-- positions
CREATE INDEX IF NOT EXISTS idx_positions_cost_center_id ON public.positions (cost_center_id);
CREATE INDEX IF NOT EXISTS idx_positions_job_grade_id ON public.positions (job_grade_id);

-- privacy_requests
CREATE INDEX IF NOT EXISTS idx_privacy_requests_requester_employee_id ON public.privacy_requests (requester_employee_id);

-- profiles
CREATE INDEX IF NOT EXISTS idx_profiles_branch_id ON public.profiles (branch_id);
CREATE INDEX IF NOT EXISTS idx_profiles_department_id ON public.profiles (department_id);
CREATE INDEX IF NOT EXISTS idx_profiles_team_id ON public.profiles (team_id);

-- project_tasks
CREATE INDEX IF NOT EXISTS idx_project_tasks_assignee_employee_id ON public.project_tasks (assignee_employee_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_parent_id ON public.project_tasks (parent_id);
CREATE INDEX IF NOT EXISTS idx_project_tasks_project_id ON public.project_tasks (project_id);

-- quality_cases
CREATE INDEX IF NOT EXISTS idx_quality_cases_owner_employee_id ON public.quality_cases (owner_employee_id);

-- report_runs
CREATE INDEX IF NOT EXISTS idx_report_runs_scheduled_report_id ON public.report_runs (scheduled_report_id);

-- request_steps
CREATE INDEX IF NOT EXISTS idx_request_steps_acted_by ON public.request_steps (acted_by);
CREATE INDEX IF NOT EXISTS idx_request_steps_workflow_step_id ON public.request_steps (workflow_step_id);

-- requests
CREATE INDEX IF NOT EXISTS idx_requests_decided_by ON public.requests (decided_by);
CREATE INDEX IF NOT EXISTS idx_requests_workflow_definition_id ON public.requests (workflow_definition_id);

-- roster_days
CREATE INDEX IF NOT EXISTS idx_roster_days_geofence_id ON public.roster_days (geofence_id);
CREATE INDEX IF NOT EXISTS idx_roster_days_shift_id ON public.roster_days (shift_id);
CREATE INDEX IF NOT EXISTS idx_roster_days_work_site_id ON public.roster_days (work_site_id);

-- security_events
CREATE INDEX IF NOT EXISTS idx_security_events_employee_id ON public.security_events (employee_id);

-- service_catalog_items
CREATE INDEX IF NOT EXISTS idx_service_catalog_items_workflow_definition_id ON public.service_catalog_items (workflow_definition_id);

-- service_request_messages
CREATE INDEX IF NOT EXISTS idx_service_request_messages_request_id ON public.service_request_messages (request_id);

-- service_requests
CREATE INDEX IF NOT EXISTS idx_service_requests_assigned_to_employee_id ON public.service_requests (assigned_to_employee_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_catalog_item_id ON public.service_requests (catalog_item_id);
CREATE INDEX IF NOT EXISTS idx_service_requests_requester_employee_id ON public.service_requests (requester_employee_id);

-- shift_assignments
CREATE INDEX IF NOT EXISTS idx_shift_assignments_geofence_id ON public.shift_assignments (geofence_id);
CREATE INDEX IF NOT EXISTS idx_shift_assignments_work_site_id ON public.shift_assignments (work_site_id);

-- strategic_objectives
CREATE INDEX IF NOT EXISTS idx_strategic_objectives_department_id ON public.strategic_objectives (department_id);
CREATE INDEX IF NOT EXISTS idx_strategic_objectives_owner_employee_id ON public.strategic_objectives (owner_employee_id);
CREATE INDEX IF NOT EXISTS idx_strategic_objectives_parent_id ON public.strategic_objectives (parent_id);

-- tasks
CREATE INDEX IF NOT EXISTS idx_tasks_created_by_employee_id ON public.tasks (created_by_employee_id);

-- wellbeing_requests
CREATE INDEX IF NOT EXISTS idx_wellbeing_requests_employee_id ON public.wellbeing_requests (employee_id);

-- work_assignments
CREATE INDEX IF NOT EXISTS idx_work_assignments_decided_by ON public.work_assignments (decided_by);

-- work_rosters
CREATE INDEX IF NOT EXISTS idx_work_rosters_branch_id ON public.work_rosters (branch_id);
CREATE INDEX IF NOT EXISTS idx_work_rosters_department_id ON public.work_rosters (department_id);
CREATE INDEX IF NOT EXISTS idx_work_rosters_published_by ON public.work_rosters (published_by);
CREATE INDEX IF NOT EXISTS idx_work_rosters_team_id ON public.work_rosters (team_id);

-- workflow_steps
CREATE INDEX IF NOT EXISTS idx_workflow_steps_approver_employee_id ON public.workflow_steps (approver_employee_id);

-- working_calendars
CREATE INDEX IF NOT EXISTS idx_working_calendars_default_shift_id ON public.working_calendars (default_shift_id);
CREATE INDEX IF NOT EXISTS idx_working_calendars_shift_pattern_id ON public.working_calendars (shift_pattern_id);

COMMIT;