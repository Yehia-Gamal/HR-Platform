# Migration Registry — أحلى شباب HR

> سجل شامل لجميع ملفات الترحيل في `supabase/migrations/`.
> آخر تحديث: 2026-07-27 — الوكيل 14 (Integration Lead).

## الإحصائيات

| العنصر | العدد |
|---|---|
| إجمالي الملفات | 163 |
| النطاق | 0001–0163 |
| التكرارات النشطة | ⚠️ 0159 (×2), 0161 (×2) |
| الفجوات | 0160, 0162 |
| ملفات V23 جديدة | 5 |
| مركونة في `_v23_parking/` | 8 |

---

## ⚠️ تعارضات نشطة

| الرقم | الملف أ | الملف ب | الحالة |
|---|---|---|---|
| **0159** | `0159_fix_is_official_holiday.sql` | `0159_v23_attendance_geofence_hardening.sql` | 🔴 يتطلب إعادة ترقيم |
| **0161** | `0161_v23_dispute_committee_alignment.sql` | `0161_v23_leaves_escalation_split.sql` | 🔴 يتطلب إعادة ترقيم |

### خطة الحل المقترحة

ترتيب إعادة الترقيم حسب قاعدة الدمج (contracts → migrations → RLS → state → UI):

1. `0159_fix_is_official_holiday.sql` → يبقى 0159 (إصلاح عاجل، لا تبعية V23)
2. `0159_v23_attendance_geofence_hardening.sql` → يُعاد ترقيمه إلى **0160**
3. `0160_v23_security_search_path_hardening.sql` → يبقى (لا يحتاج نقل، لكن يجب ملء الفجوة أولاً) → يُعاد إلى **0161**
4. `0161_v23_leaves_escalation_split.sql` → يُعاد ترقيمه إلى **0162**
5. `0161_v23_dispute_committee_alignment.sql` → يُعاد ترقيمه إلى **0163**
6. `0163_v23_device_biometric_recovery.sql` → يُعاد ترقيمه إلى **0164**

> **ملاحظة:** هذا الحل يتطلب تنسيقاً بين الوكلاء ومراجعة التبعيات قبل التنفيذ.

---

## السجل الكامل

### الأساس (0001–0011)

| # | الملف | الوكيل | الموجة | الوصف |
|---|---|---|---|---|
| 0001 | `0001_extensions_and_conventions.sql` | 2 | Foundation | إضافات PostgreSQL والاتفاقيات |
| 0002 | `0002_permissions_roles_functions.sql` | 3 | Foundation | أدوار وصلاحيات ودوال أساسية |
| 0003 | `0003_organization.sql` | 4 | Foundation | الهيكل التنظيمي |
| 0004 | `0004_employees.sql` | 4 | Foundation | جدول الموظفين |
| 0005 | `0005_attendance.sql` | 6 | Foundation | الحضور والانصراف |
| 0006 | `0006_requests_workflow.sql` | 7 | Foundation | الطلبات وسير العمل |
| 0007 | `0007_kpi_performance.sql` | 8 | Foundation | تقييم الأداء KPI |
| 0008 | `0008_communications_disputes.sql` | 9/10 | Foundation | التواصل والتظلمات |
| 0009 | `0009_documents_tasks_policies.sql` | 5 | Foundation | وثائق ومهام وسياسات |
| 0010 | `0010_recruitment_onboarding.sql` | 4 | Foundation | التوظيف والتهيئة |
| 0011 | `0011_audit_security_system.sql` | 3 | Foundation | التدقيق والأمان |

### التصلب والتحسين (0012–0038)

| # | الملف | الوكيل | الموجة | الوصف |
|---|---|---|---|---|
| 0012 | `0012_core_p0_hardening.sql` | 3 | Hardening | تصلب P0 أساسي |
| 0013 | `0013_foundation_access_and_provisioning.sql` | 4 | Hardening | وصول وتزويد أساسي |
| 0014 | `0014_employee_access_canonicalization.sql` | 4 | Hardening | توحيد وصول الموظفين |
| 0015 | `0015_operational_workspaces.sql` | 5 | Hardening | مساحات عمل تشغيلية |
| 0016 | `0016_management_overviews_notifications.sql` | 5 | Hardening | لوحات إدارية وإشعارات |
| 0017 | `0017_live_location_mobile_flow.sql` | 11 | Hardening | الموقع المباشر — تدفق الموبايل |
| 0018 | `0018_employee_request_self_service.sql` | 7 | Hardening | خدمة ذاتية للطلبات |
| 0019 | `0019_kpi_forms_and_attendance_state.sql` | 8 | Hardening | نماذج KPI وحالة الحضور |
| 0020 | `0020_passkey_lifecycle_and_mobile_actions.sql` | 6 | Hardening | دورة Passkey وإجراءات الموبايل |
| 0021 | `0021_mobile_details_and_action_routing.sql` | 10 | Hardening | تفاصيل وتوجيه الموبايل |
| 0022 | `0022_mobile_daily_workspaces.sql` | 10 | Hardening | مساحات عمل يومية — موبايل |
| 0023 | `0023_passkey_devices_and_attendance_history.sql` | 6 | Hardening | أجهزة Passkey وسجل الحضور |
| 0024 | `0024_mobile_notifications_and_action_links.sql` | 11 | Hardening | إشعارات موبايل وروابط إجراءات |
| 0025 | `0025_admin_structure_access_onboarding.sql` | 5 | Hardening | بنية الإدارة والتهيئة |
| 0026 | `0026_leave_ledger_and_request_sla.sql` | 7 | Hardening | سجل الإجازات وSLA الطلبات |
| 0027 | `0027_decision_lifecycle_polls_and_execution.sql` | 9 | Hardening | دورة القرارات والتصويت |
| 0028 | `0028_rosters_attendance_periods_and_corrections.sql` | 6 | Hardening | جداول المناوبات والتصحيحات |
| 0029 | `0029_kpi_cycles_evidence_appeals_and_attendance_inputs.sql` | 8 | Hardening | دورات KPI والأدلة والطعون |
| 0030 | `0030_disputes_committee_quorum_decisions_and_appeals.sql` | 9 | Hardening | لجنة التظلمات والنصاب |
| 0031 | `0031_documents_assets_and_offboarding_lifecycle.sql` | 5 | Hardening | وثائق وأصول ومغادرة |
| 0032 | `0032_mobile_self_service_roster_and_period_hardening.sql` | 10 | Hardening | خدمة ذاتية موبايل — تصلب |
| 0033 | `0033_talent_learning_documents_reports_notifications.sql` | 5 | Hardening | مواهب وتعلم وتقارير |
| 0034 | `0034_private_storage_buckets_and_retention.sql` | 3 | Hardening | تخزين خاص واستبقاء |
| 0035 | `0035_enterprise_strategy_projects_service_governance.sql` | 5 | Hardening | استراتيجية ومشاريع وحوكمة |
| 0036 | `0036_workforce_compensation_payroll_engagement.sql` | 5 | Hardening | قوى عاملة ورواتب |
| 0037 | `0037_retention_privacy_and_release_hardening.sql` | 3 | Hardening | خصوصية واستبقاء وإصدار |
| 0038 | `0038_release_access_privacy_integration_governance.sql` | 3/14 | Hardening | حوكمة الوصول والتكامل |

### تسجيل الدخول والأمان (0039–0055)

| # | الملف | الوكيل | الموجة |
|---|---|---|---|
| 0039 | `0039_identifier_login_security.sql` | 3 | Security |
| 0040 | `0040_release_0_10_ui_and_identifier_login.sql` | 5 | Release 0.10 |
| 0041 | `0041_mobile_manager_and_executive_workspaces.sql` | 10 | Mobile |
| 0042 | `0042_mobile_executive_brief_and_people.sql` | 10 | Mobile |
| 0043 | `0043_grant_service_role_sla_processor.sql` | 3 | Security |
| 0044 | `0044_recruitment_interviews_offers_hire.sql` | 4 | HR |
| 0045 | `0045_grant_authenticated_table_privileges.sql` | 3 | Security |
| 0046 | `0046_attendance_mock_location_and_travel_guard.sql` | 6 | Attendance |
| 0047 | `0047_scheduling_leave_accrual_and_cron.sql` | 7 | Leaves |
| 0048 | `0048_pgcrypto_search_path_for_digest.sql` | 3 | Security |
| 0049 | `0049_schedule_edge_functions_via_pg_net.sql` | 11 | Notifications |
| 0050 | `0050_audit_remediation_p0_p1.sql` | 3 | Audit |
| 0051 | `0051_schedule_remaining_edge_functions.sql` | 11 | Notifications |
| 0052 | `0052_audit_remediation_p2_p3.sql` | 3 | Audit |
| 0053 | `0053_full_access_sees_all_workspaces.sql` | 5 | Access |
| 0054 | `0054_observability_and_alerting.sql` | 3 | Observability |
| 0055 | `0055_audit_remediation_p3_ledger.sql` | 3 | Audit |

### العمليات والحوكمة (0056–0080)

| # | الملف | الوكيل | الموجة |
|---|---|---|---|
| 0056 | `0056_employee_onboarding_simplification.sql` | 4 | Operations |
| 0057 | `0057_official_shifts_and_punch_reminders.sql` | 6 | Attendance |
| 0058 | `0058_official_kpi_governance.sql` | 8 | KPI |
| 0059 | `0059_dispute_committee_end_to_end.sql` | 9 | Disputes |
| 0060 | `0060_leave_types_and_entitlement.sql` | 7 | Leaves |
| 0061 | `0061_leave_submission_and_casual.sql` | 7 | Leaves |
| 0062 | `0062_request_escalation_on_behalf.sql` | 7 | Requests |
| 0063 | `0063_work_assignments.sql` | 7 | Assignments |
| 0064 | `0064_dispute_committee_fixes.sql` | 9 | Disputes |
| 0065 | `0065_assignments_attendance_link.sql` | 6/7 | Assignments |
| 0066 | `0066_assignments_kpi_link.sql` | 7/8 | Assignments |
| 0067 | `0067_live_location_executive_flow.sql` | 11 | Location |
| 0068 | `0068_location_request_ux_fixes.sql` | 11 | Location |
| 0069 | `0069_executive_attendance_today.sql` | 6 | Attendance |
| 0070 | `0070_cancel_location_request.sql` | 11 | Location |
| 0071 | `0071_auto_cancel_on_new_request.sql` | 11 | Location |
| 0072 | `0072_fix_request_live_location_audit_call.sql` | 11 | Location |
| 0073 | `0073_location_security_hardening.sql` | 3/11 | Security |
| 0074 | `0074_fix_log_audit_event_overload.sql` | 3 | Audit |
| 0075 | `0075_cleanup_attendance_rpc.sql` | 6 | Attendance |
| 0076 | `0076_fix_attendance_period_legal_entity_id.sql` | 6 | Attendance |
| 0077 | `0077_executive_manager_fixes.sql` | 10 | Mobile |
| 0078 | `0078_fix_record_attendance_overload.sql` | 6 | Attendance |
| 0079 | `0079_auto_provision_employees.sql` | 4 | HR |
| 0080 | `0080_reapply_fixes.sql` | 2 | Fix |

### الإصلاحات والأمان (0081–0110)

| # | الملف | الوكيل | الموجة |
|---|---|---|---|
| 0081 | `0081_fix_attendance_columns_and_employee_visibility.sql` | 6 | Fix |
| 0082 | `0082_attendance_acceptance_leave_backfill.sql` | 6/7 | Fix |
| 0083 | `0083_location_history_and_verified_devices.sql` | 11 | Location |
| 0084 | `0084_secure_employee_manager_change.sql` | 4 | Security |
| 0085 | `0085_repair_verified_employee_devices.sql` | 6 | Fix |
| 0086 | `0086_location_only_completion_audit.sql` | 11 | Location |
| 0087 | `0087_authorized_mobile_action_resolver.sql` | 10 | Mobile |
| 0088 | `0088_canonical_location_responses_and_map_snapshots.sql` | 11 | Location |
| 0089 | `0089_atomic_idempotent_attendance_finalize.sql` | 6 | Attendance |
| 0090 | `0090_secure_employee_archive_and_delete_guard.sql` | 4 | Security |
| 0091 | `0091_fix_employee_archive_permission.sql` | 4 | Fix |
| 0092 | `0092_fix_log_audit_event_type_mismatch.sql` | 3 | Fix |
| 0093 | `0093_fix_device_not_active_root_cause.sql` | 6 | Fix |
| 0094 | `0094_punch_attendance_local_biometric.sql` | 6 | Attendance |
| 0095 | `0095_security_hardening_audit_fixes.sql` | 3 | Security |
| 0096 | `0096_release_0_11_1_deep_audit_remediation.sql` | 3 | Release 0.11.1 |
| 0097 | `0097_activate_employee_after_first_login.sql` | 4 | HR |
| 0098 | `0098_signed_url_and_offline_support.sql` | 11 | Storage |
| 0099 | `0099_fix_signed_url_rpc.sql` | 11 | Fix |
| 0100 | `0100_enforce_report_storage_signed_url_fix.sql` | 12 | Fix |
| 0101 | `0101_mobile_rpc_scoping_fixes.sql` | 10 | Mobile |
| 0102 | `0102_fix_employee_home_rpc.sql` | 10 | Fix |
| 0103 | `0103_reschedule_edge_jobs_from_runtime_settings.sql` | 11 | Notifications |
| 0104 | `0104_v10_identity_workspace_local_biometric.sql` | 6 | v10 |
| 0105 | `0105_fix_pgcrypto_function_search_paths.sql` | 3 | Fix |
| 0106 | `0106_v10_runtime_contract_repairs.sql` | 14 | v10 |
| 0107 | `0107_standardize_live_location_request_audit.sql` | 11 | Location |
| 0108 | `0108_finish_runtime_lint_repairs.sql` | 14 | Fix |
| 0109 | `0109_v10_kpi_workflow.sql` | 8 | v10 |
| 0110 | `0110_v10_executive_kpi_report_access.sql` | 8 | v10 |

### الإصدارات والنشر (0111–0158)

| # | الملف | الوكيل | الموجة |
|---|---|---|---|
| 0111 | `0111_v10_dashboards_notifications_daily_report.sql` | 5/11 | v10 |
| 0112 | `0112_v10_request_acceptance_repairs.sql` | 7 | v10 |
| 0113 | `0113_v10_request_attachment_catalog_access.sql` | 7 | v10 |
| 0114 | `0114_unify_employee_avatar_storage.sql` | 4 | Storage |
| 0115 | `0115_fix_kpi_validation_array_initialization.sql` | 8 | Fix |
| 0116 | `0116_restore_fcm_push_delivery.sql` | 11 | Notifications |
| 0117 | `0117_fix_verification_status_and_fullname.sql` | 6 | Fix |
| 0118 | `0118_restore_release_governance_overview.sql` | 5 | Fix |
| 0119 | `0119_bridge_placeholder.sql` | 14 | Bridge |
| 0120 | `0120_security_hardening_comprehensive.sql` | 3 | Security |
| 0121 | `0121_seed_org_structure_roles_departments.sql` | 4 | Seed |
| 0122 | `0122_bridge_placeholder.sql` | 14 | Bridge |
| 0123 | `0123_mobile_org_chart_rpc.sql` | 10 | Mobile |
| 0124 | `0124_remove_video_from_live_location.sql` | 11 | Location |
| 0125 | `0125_employee_lifecycle_hardening.sql` | 4 | HR |
| 0126 | `0126_fix_verification_status_and_fullname.sql` | 6 | Fix |
| 0127 | `0127_monthly_attendance_statement.sql` | 12 | Reports |
| 0128 | `0128_repair_request_live_location_staging.sql` | 11 | Fix |
| 0129 | `0129_employee_edit_and_list_enrichment.sql` | 4 | HR |
| 0130 | `0130_v17_kpi_flow_reorder.sql` | 8 | v17 |
| 0131 | `0131_v17_dispute_admin_actions.sql` | 9 | v17 |
| 0132 | `0132_v17_official_holidays.sql` | 7 | v17 |
| 0133 | `0133_v17_post_publishing.sql` | 10 | v17 |
| 0134 | `0134_v17_request_types.sql` | 7 | v17 |
| 0135 | `0135_v17_word_count_checks.sql` | 9 | v17 |
| 0136 | `0136_fix_resolve_request_approver.sql` | 7 | Fix |
| 0137 | `0137_v17_attendance_executive_exemption.sql` | 6 | v17 |
| 0138 | `0138_v17_permission_matrix_fixes.sql` | 3 | v17 |
| 0139 | `0139_v17_request_return_status.sql` | 7 | v17 |
| 0140 | `0140_v17_attendance_history_days.sql` | 6 | v17 |
| 0141 | `0141_v17_dispute_admin_action_catalog.sql` | 9 | v17 |
| 0142 | `0142_v17_announcement_images.sql` | 10 | v17 |
| 0143 | `0143_fix_attendance_all_non_executive.sql` | 6 | Fix |
| 0144 | `0144_v17_access_context_photo_url.sql` | 5 | v17 |
| 0145 | `0145_v18_device_approval_workflow.sql` | 6 | v18 |
| 0146 | `0146_v17_kpi_stage_notify.sql` | 8/11 | v17 |
| 0147 | `0147_v17_request_decision_notify.sql` | 7/11 | v17 |
| 0148 | `0148_v17_announcement_publish_notify.sql` | 10/11 | v17 |
| 0149 | `0149_fix_org_chart_recursive_cte.sql` | 10 | Fix |
| 0150 | `0150_fix_request_live_location_admin_access.sql` | 11 | Fix |
| 0151 | `0151_admin_sees_hr_workspace.sql` | 5 | Fix |
| 0152 | `0152_v18_committee_dispute_mobile_portal.sql` | 9/10 | v18 |
| 0153 | `0153_fix_kpi_notify_fullname.sql` | 8/11 | Fix |
| 0154 | `0154_add_departments_slug_and_fix_seed_timing.sql` | 4 | Fix |
| 0155 | `0155_fix_attendance_missing_check_null.sql` | 6 | Fix |
| 0156 | `0156_multi_department_support.sql` | 4 | v17 |
| 0157 | `0157_fix_seed_timing_permission_grants.sql` | 4 | Fix |
| 0158 | `0158_grant_employee_devices_select.sql` | 6 | Fix |

### V23 — الموجة الجديدة (0159+)

| # | الملف | الوكيل | الحالة | ملاحظات |
|---|---|---|---|---|
| 0159 | `0159_fix_is_official_holiday.sql` | 7 | ⚠️ تكرار | إصلاح دالة is_official_holiday |
| 0159 | `0159_v23_attendance_geofence_hardening.sql` | 6 | ⚠️ تكرار | تصلب سياج جغرافي |
| 0160 | `0160_v23_security_search_path_hardening.sql` | 3 | ✅ | تصلب search_path |
| 0161 | `0161_v23_dispute_committee_alignment.sql` | 9 | ⚠️ تكرار | محاذاة لجنة التظلمات |
| 0161 | `0161_v23_leaves_escalation_split.sql` | 7 | ⚠️ تكرار | فصل مهلة تصعيد الإجازات |
| 0163 | `0163_v23_device_biometric_recovery.sql` | 6 | ✅ | استرداد البيومترية |

### ملفات مركونة (`_v23_parking/`)

> هذه الملفات تم نقلها مؤقتاً من `supabase/migrations/` لحل تعارضات الترقيم.

| الملف | الوكيل الأصلي | ملاحظات |
|---|---|---|
| `0159_v23_roles_permissions_hardening.sql` | 3 | أدوار وصلاحيات V23 |
| `0160_v23_kpi_parallel_workflow.sql` | 8 | سير عمل KPI المتوازي |
| `0160_v23_notification_catalog_completion.sql` | 11 | كاتالوج الإشعارات |
| `0161_v23_dispute_committee_alignment.sql` | 9 | نسخة من المحاذاة |
| `0161_v23_leaves_escalation_split.sql` | 7 | نسخة من فصل التصعيد |
| `migrations/0160–0163` | متعدد | نسخ معاد ترقيمها تجريبياً |
| `tests/0060–0066` | متعدد | اختبارات V23 مركونة |

---

## التحقق من السلامة

```bash
# عدد الملفات
ls supabase/migrations/*.sql | wc -l

# التكرارات
ls supabase/migrations/ | grep -v README | cut -c1-4 | sort | uniq -d

# الفجوات (يجب أن تكون فارغة بعد الحل)
seq -w 1 163 | while read n; do
  ls supabase/migrations/0${n}_* 2>/dev/null | head -1 || echo "GAP: 0${n}"
done | grep GAP
```
