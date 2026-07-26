# جرد مخطط قاعدة البيانات — DATABASE_SCHEMA_INVENTORY

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## ملخص

| المقياس | القيمة |
|---|---|
| إجمالي الجداول | ~238 |
| ملفات Migration | 162 |
| النطاقات | 17 |
| أحدث Migration | 0162 |

---

## 1. المصادقة والصلاحيات (mig 0002)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `permissions` | id, slug, name_ar, category, is_sensitive |
| `roles` | id, slug, name_ar, is_full_access, is_system |
| `role_permissions` | role_id → roles, permission_id → permissions |
| `user_roles` | user_id → auth.users, role_id → roles, assigned_by |

## 2. الهيكل التنظيمي (mig 0003)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `legal_entities` | id, name_ar, name_en, registration_number |
| `branches` | id, name_ar, legal_entity_id → legal_entities |
| `work_sites` | id, name_ar, branch_id → branches, latitude, longitude |
| `cost_centers` | id, code, name_ar, legal_entity_id |
| `job_titles` | id, name_ar, name_en |
| `job_grades` | id, name_ar, level, min_salary, max_salary |
| `departments` | id, name_ar, parent_id → departments (شجري), legal_entity_id |
| `teams` | id, name_ar, department_id → departments |
| `positions` | id, name_ar, department_id, job_title_id, job_grade_id |
| `employment_types` | id, name_ar, code |
| `geofences` | id, name_ar, work_site_id, latitude, longitude, radius_meters |
| `shifts` | id, name_ar, start_time, end_time, is_night_shift |
| `shift_patterns` | id, name_ar, pattern_days |
| `public_holidays` | id, name_ar, date, is_recurring |
| `working_calendars` | id, name_ar, legal_entity_id |

## 3. الموظفون (mig 0004)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `employees` | id, full_name_ar, full_name_en, employee_code, phone_e164, email, employment_status, department_id, position_id, job_title_id, manager_id, hire_date, is_active, is_deleted, photo_url |
| `profiles` | id (= auth.uid), employee_id → employees, avatar_url |
| `manager_relations` | id, employee_id → employees, manager_id → employees, relation_type |
| `employee_assignments` | id, employee_id, department_id, position_id, start_date, end_date |
| `employee_documents` | id, employee_id, document_type, file_path, status |
| `employee_skills` | id, employee_id, skill_name, proficiency_level |
| `employee_certifications` | id, employee_id, certification_name, issued_date, expiry_date |

## 4. الحضور (mig 0005, 0028, 0073, 0089, 0096)

| الجدول | Migration | الأعمدة الرئيسية |
|---|---|---|
| `shift_assignments` | 0005 | employee_id, shift_id, start_date, end_date |
| `passkey_credentials` | 0005 | id, employee_id, credential_id, public_key, sign_count |
| `webauthn_challenges` | 0005 | id, user_id, challenge, type, expires_at, used_at |
| `attendance_events` | 0005 | id, employee_id, event_type, timestamp, latitude, longitude, accuracy_meters, is_mock |
| `attendance_daily` | 0005 | id, employee_id, date, check_in, check_out, status |
| `attendance_identity_checks` | 0005 | id, attendance_event_id, check_type, result |
| `attendance_risk_events` | 0005 | id, employee_id, risk_type, details |
| `attendance_exceptions` | 0005 | id, employee_id, date, exception_type |
| `attendance_permits` | 0005 | id, employee_id, permit_type, date |
| `attendance_periods` | 0028 | id, employee_id, date, period_type, legal_entity_id |
| `work_rosters` | 0028 | id, employee_id, date, shift_id |
| `roster_days` | 0028 | id, roster_id, day_of_week |
| `attendance_corrections` | 0028 | id, employee_id, date, correction_type |
| `overtime_records` | 0028 | id, employee_id, date, hours |
| `employee_devices` | 0073 | id, employee_id, device_label, status, passkey_credential_id |
| `location_request_responses` | 0073 | id, request_id, employee_id, latitude, longitude, map_snapshot_path |
| `attendance_punch_attempts` | 0089 | id, employee_id, operation_id, event_type, status |
| `local_attendance_operations` | 0096 | id, employee_id, operation_type |

## 5. الطلبات وسير العمل (mig 0006)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `leave_types` | id, name_ar, code, default_balance, requires_approval |
| `workflow_definitions` | id, name_ar, entity_type |
| `workflow_steps` | id, workflow_id, step_order, approver_type |
| `requests` | id, employee_id, request_type, status, submitted_at |
| `leave_requests` | id, request_id → requests, leave_type_id, start_date, end_date |
| `missions` | id, request_id → requests, destination, purpose |
| `convoy_requests` | id, request_id → requests, vehicle_type |
| `request_steps` | id, request_id, step_number, assignee_id, status |
| `request_actions` | id, request_step_id, actor_id, action_type, comment |
| `workflow_instances` | id, workflow_definition_id, entity_id, status |

## 6. الإجازات المتقدمة (mig 0026)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `leave_balance_accounts` | id, employee_id, leave_type_id, balance, year |
| `leave_ledger_entries` | id, account_id, entry_type, amount, reference_id |

## 7. تقييم الأداء KPI (mig 0007, 0029, 0058, 0066)

| الجدول | Migration | الأعمدة الرئيسية |
|---|---|---|
| `kpi_cycles` | 0007 | id, name_ar, start_date, end_date, status |
| `kpi_templates` | 0007 | id, name_ar, criteria_config |
| `kpi_criteria` | 0007 | id, template_id, name_ar, weight, code |
| `kpi_evaluations` | 0007 | id, cycle_id, employee_id, evaluator_id, stage, status |
| `kpi_scores` | 0007 | id, evaluation_id, criterion_id, score, evaluator_type |
| `monthly_evaluations` | 0007 | id, employee_id, month, year |
| `goal_objectives` | 0007 | id, employee_id, title, target_date |
| `goal_key_results` | 0007 | id, objective_id, title, target_value |
| `goal_checkins` | 0007 | id, key_result_id, value, date |
| `feedback_rounds` | 0007 | id, employee_id, type, status |
| `feedback_raters` | 0007 | id, round_id, rater_id |
| `competencies` | 0007 | id, name_ar, category |
| `competency_levels` | 0007 | id, competency_id, level, description |
| `role_competency_profiles` | 0007 | id, position_id, competency_id, required_level |
| `employee_competency_assessments` | 0007 | id, employee_id, competency_id, assessed_level |
| `calibration_sessions` | 0007 | id, cycle_id, status |
| `review_cycle_templates` | 0007 | id, name_ar, type |
| `review_cycle_instances` | 0007 | id, template_id, kpi_cycle_id, status |
| `improvement_plans` | 0007 | id, employee_id, status |
| `one_on_ones` | 0007 | id, employee_id, manager_id, date |
| `kpi_evidence` | 0029 | id, evaluation_id, file_path |
| `kpi_stage_history` | 0029 | id, evaluation_id, from_stage, to_stage |
| `kpi_appeals` | 0029 | id, evaluation_id, reason |
| `kpi_policy_versions` | 0058 | id, version, criteria_weights, active |
| `kpi_goals` | 0058 | id, evaluation_id, title, weight |
| `kpi_review_sessions` | 0058 | id, evaluation_id, reviewer_id, notes |
| `kpi_compliance_records` | 0058 | id, evaluation_id, metric_code, value |
| `kpi_attendance_snapshots` | 0058 | id, evaluation_id, attendance_data |
| `kpi_notification_receipts` | 0058 | id, evaluation_id, notification_type |
| `kpi_assignment_contributions` | 0066 | id, evaluation_id, assignment_id |

## 8. الاتصالات والشكاوى (mig 0008, 0027, 0030, 0059)

| الجدول | Migration | الأعمدة الرئيسية |
|---|---|---|
| `administrative_decisions` | 0008 | id, title, body, status, created_by |
| `decision_recipients` | 0008 | id, decision_id, employee_id |
| `decision_reads` | 0008 | id, decision_id, employee_id, read_at |
| `announcements` | 0008 | id, title, body, published_at, created_by |
| `announcement_acknowledgements` | 0008 | id, announcement_id, employee_id |
| `surveys` | 0008 | id, title, status |
| `survey_questions` | 0008 | id, survey_id, question_text |
| `survey_responses` | 0008 | id, question_id, respondent_id |
| `suggestions` | 0008 | id, employee_id, content, status |
| `recognitions` | 0008 | id, from_id, to_id, message |
| `notifications` | 0008 | id, user_id, title, body, read, priority |
| `push_subscriptions` | 0008 | id, user_id, fcm_token, platform, is_active |
| `notification_delivery_log` | 0008 | id, notification_id, channel, status |
| `dispute_cases` | 0008 | id, complainant_id, title, description, status |
| `dispute_sessions` | 0008 | id, case_id, scheduled_at, status |
| `dispute_evidence` | 0008 | id, case_id, file_path |
| `committee_members` | 0008 | id, employee_id, role, is_active |
| `decision_versions` | 0027 | id, decision_id, version, body |
| `decision_actions` | 0027 | id, decision_id, action_type, actor_id |
| `decision_execution_items` | 0027 | id, decision_id, description, status |
| `decision_polls` | 0027 | id, decision_id, question, status |
| `decision_poll_options` | 0027 | id, poll_id, option_text |
| `decision_poll_eligibility` | 0027 | id, poll_id, employee_id |
| `decision_poll_votes` | 0027 | id, poll_id, option_id, voter_id |
| `dispute_conflict_declarations` | 0030 | id, case_id, member_id, declared |
| `dispute_session_attendance` | 0030 | id, session_id, member_id, attended |
| `dispute_decisions` | 0030 | id, case_id, decision_type, body |
| `dispute_appeals` | 0030 | id, case_id, appellant_id, reason |
| `dispute_actions` | 0030 | id, case_id, action_type, actor_id |
| `dispute_parties` | 0059 | id, case_id, employee_id, role |
| `dispute_statements` | 0059 | id, case_id, author_id, content |
| `dispute_session_participants` | 0059 | id, session_id, employee_id |
| `dispute_settlements` | 0059 | id, case_id, terms, status |
| `dispute_decision_receipts` | 0059 | id, decision_id, recipient_id, acknowledged |

## 9. المستندات والمهام (mig 0009, 0031, 0033)

| الجدول | Migration | الأعمدة الرئيسية |
|---|---|---|
| `documents` | 0009 | id, title, content, status, created_by |
| `attachments` | 0009 | id, entity_type, entity_id, file_path |
| `tasks` | 0009 | id, title, assigned_to, status, due_date |
| `task_templates` | 0009 | id, title, steps |
| `policies` | 0009 | id, title, content, version, status |
| `policy_acknowledgements` | 0009 | id, policy_id, employee_id |
| `daily_reports` | 0009 | id, employee_id, date, content |
| `asset_inventory` | 0009 | id, name, category, status |
| `asset_assignments` | 0009 | id, asset_id, employee_id, assigned_at |
| `projects` | 0009 | id, name, status |
| `project_members` | 0009 | id, project_id, employee_id |
| `meetings` | 0009 | id, title, scheduled_at, location |
| `meeting_minutes` | 0009 | id, meeting_id, content |
| `decision_register` | 0009 | id, title, status, decision_date |
| `risks` | 0009 | id, title, probability, impact, status |
| `incidents` | 0009 | id, title, severity, reported_by |
| `knowledge_articles` | 0009 | id, title, content, category |
| `hr_tickets` | 0009 | id, employee_id, subject, status |
| `ticket_messages` | 0009 | id, ticket_id, sender_id, message |
| `document_access_logs` | 0031 | id, document_id, user_id, accessed_at |
| `offboarding_cases` | 0031 | id, employee_id, reason, status |
| `offboarding_clearance_items` | 0031 | id, case_id, item_type, status |
| `knowledge_transfer_items` | 0031 | id, case_id, description |
| `offboarding_actions` | 0031 | id, case_id, action_type |
| `learning_courses` | 0033 | id, title, category |
| `learning_course_sessions` | 0033 | id, course_id, scheduled_at |
| `learning_enrollments` | 0033 | id, session_id, employee_id |
| `document_templates` | 0033 | id, name, template_body |
| `generated_documents` | 0033 | id, template_id, employee_id, output_path |
| `document_signature_requests` | 0033 | id, document_id, signer_id, status |
| `scheduled_reports` | 0033 | id, name, schedule_cron, query |
| `report_runs` | 0033 | id, report_id, status, output_path |
| `notification_jobs` | 0033 | id, notification_id, status, attempts |

## 10. التوظيف والتهيئة (mig 0010)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `job_requisitions` | id, title, department_id, status, positions_count |
| `job_requisition_approvals` | id, requisition_id, approver_id, status |
| `job_postings` | id, requisition_id, platform, status |
| `candidates` | id, full_name, email, phone, source |
| `candidate_documents` | id, candidate_id, document_type, file_path |
| `applications` | id, candidate_id, requisition_id, status |
| `pipeline_stages` | id, name, order |
| `application_stage_history` | id, application_id, stage_id, moved_at |
| `application_current_state` | application_id, stage_id, status |
| `interviews` | id, application_id, scheduled_at, status |
| `interview_panel` | id, interview_id, panelist_id |
| `interview_scorecards` | id, interview_id, panelist_id, overall_score |
| `scorecard_criteria_scores` | id, scorecard_id, criterion, score |
| `job_offers` | id, application_id, salary, status |
| `offer_approvals` | id, offer_id, approver_id, status |
| `employment_contracts` | id, offer_id, start_date, contract_type |
| `contract_signatures` | id, contract_id, signer_id, signed_at |
| `onboarding_journeys` | id, employee_id, status |
| `onboarding_tasks` | id, journey_id, title, status |
| `provisioning_requests` | id, journey_id, resource_type, status |

## 11. المراجعة والأمان والنظام (mig 0011, 0039, 0054)

| الجدول | Migration | الأعمدة الرئيسية |
|---|---|---|
| `audit_logs` | 0011 | id, user_id, action, entity_type, entity_id, details |
| `audit_events` | 0011 | id, event_type, actor_id, target, metadata |
| `security_events` | 0011 | id, event_type, user_id, ip_address, details |
| `login_identifier_attempts` | 0011 | id, identifier_hash, ip_hash, success |
| `credential_vault` | 0011 | id, owner_id, key_name, encrypted_value |
| `password_reset_requests` | 0011 | id, user_id, token_hash, expires_at |
| `settings` | 0011 | id, key, value, category |
| `system_settings` | 0011 | id, key, value, data_type |
| `system_backups` | 0011 | id, backup_type, status, file_path |
| `app_error_events` | 0011 | id, error_type, message, stack_trace |
| `feature_flags` | 0011 | id, flag_name, is_enabled, description |
| `integrations` | 0011 | id, name, webhook_url, is_enabled, status |
| `integration_logs` | 0011 | id, integration_id, event_type, payload |
| `live_location_requests` | 0011 | id, requester_id, target_id, status, mode |
| `live_location_videos_meta` | 0011 | id, request_id, video_path, duration |
| `employee_locations` | 0011 | id, employee_id, latitude, longitude, recorded_at |
| `location_requests` | 0011 | id, requester_id, target_id, status |
| `login_auth_attempts` | 0039 | id, identifier_hash, ip_hash, success, created_at |
| `system_alerts` | 0054 | id, alert_type, severity, message, resolved |

## 12. المؤسسية والاستراتيجية (mig 0035)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `strategic_objectives` | id, title, description, status |
| `objective_key_results` | id, objective_id, title, target |
| `enterprise_projects` | id, name, department_id, status |
| `project_tasks` | id, project_id, title, assignee_id |
| `enterprise_risks` | id, title, probability, impact |
| `enterprise_incidents` | id, title, severity, status |
| `service_catalog_items` | id, name, category |
| `service_requests` | id, catalog_item_id, requester_id, status |
| `service_request_messages` | id, request_id, sender_id, message |
| `enterprise_meetings` | id, title, scheduled_at |
| `meeting_attendees` | id, meeting_id, employee_id |
| `meeting_agenda_items` | id, meeting_id, title |
| `meeting_decisions` | id, meeting_id, decision_text |
| `quality_cases` | id, title, status |
| `corrective_actions` | id, case_id, description |
| `internal_audits` | id, title, scope, status |
| `audit_findings` | id, audit_id, finding, severity |
| `automation_rules` | id, name, trigger, action |
| `automation_runs` | id, rule_id, status, result |
| `data_assets` | id, name, type, owner_id |
| `data_quality_rules` | id, asset_id, rule_type |
| `ai_use_cases` | id, title, department_id, status |

## 13. الرواتب والتعويضات (mig 0036)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `workforce_plans` | id, department_id, year, headcount_target |
| `capacity_snapshots` | id, department_id, date, current_count |
| `salary_structures` | id, name, currency |
| `salary_components` | id, structure_id, name, type |
| `employee_compensation` | id, employee_id, component_id, amount |
| `payroll_runs` | id, period, status |
| `payslips` | id, run_id, employee_id |
| `payslip_lines` | id, payslip_id, component_id, amount |
| `employee_loans` | id, employee_id, amount, status |
| `loan_installments` | id, loan_id, amount, due_date |
| `engagement_campaigns` | id, title, status |
| `wellbeing_requests` | id, employee_id, type, status |

## 14. الحوكمة والخصوصية (mig 0037, 0038)

| الجدول | Migration |
|---|---|
| `live_location_video_access_logs` | 0037 |
| `app_release_policies` | 0038 |
| `managed_devices` | 0038 |
| `access_review_campaigns` | 0038 |
| `access_review_items` | 0038 |
| `break_glass_requests` | 0038 |
| `privacy_requests` | 0038 |
| `integration_outbox` | 0038 |

## 15. التكليفات (mig 0063)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `work_assignments` | id, employee_id, type (mission/convoy/fandi), start_date, end_date, status |
| `work_assignment_participants` | id, assignment_id, employee_id |

## 16. إدارات متعددة (mig 0156)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `employee_departments` | id, employee_id, department_id, is_primary, allocation_pct |

## 17. خريطة الموقع (mig 0088)

| الجدول | الأعمدة الرئيسية |
|---|---|
| `live_location_map_access_logs` | id, response_id, accessor_id, accessed_at |
