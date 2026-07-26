# سجل الـ Migrations — MIGRATION_REGISTRY

> **تاريخ الجرد:** 2026-07-27 (محدّث) | **Agent 00A**

---

## ملخص

| المقياس | القيمة |
|---|---|
| إجمالي ملفات Migration | 163 (+ README) |
| النطاق | 0001 — 0160 |
| ⚠️ أرقام مكررة | 0160 (**3 ملفات**) |
| Bridge placeholders | 2 (0119, 0122) |
| آخر رقم مستخدم | **0160** |
| **أول رقم آمن للـ migration التالي** | **0161** |
| جداول أُنشئت | ~238 |

> ⚠️ **تحذير تكرار الأرقام:**
> - `0160` يظهر **3 مرات**: `v23_kpi_parallel_workflow.sql` و `v23_leaves_escalation_split.sql` و `v23_notification_catalog_completion.sql`
> - هذا خطر متكرر من المحادثات المتوازية — **يجب دائماً تشغيل:**
> ```bash
> ls supabase/migrations/ | sort | tail -3
> ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
> ```

---

## السجل الكامل

### التأسيس (0001–0011) — Schema

| الرقم | الاسم | النوع | الجداول | الوصف |
|---|---|---|---|---|
| 0001 | extensions_and_conventions | Config | 0 | إعدادات PostgreSQL وامتدادات |
| 0002 | permissions_roles_functions | Schema | 4 | permissions, roles, role_permissions, user_roles + RBAC functions |
| 0003 | organization | Schema | 15 | legal_entities, branches, departments, shifts... |
| 0004 | employees | Schema | 7 | employees, profiles, manager_relations... |
| 0005 | attendance | Schema | 9 | attendance_events, passkey_credentials, webauthn_challenges... |
| 0006 | requests_workflow | Schema | 10 | requests, leave_requests, missions, workflows... |
| 0007 | kpi_performance | Schema | 20 | kpi_cycles, evaluations, goals, competencies... |
| 0008 | communications_disputes | Schema | 17 | announcements, notifications, dispute_cases... |
| 0009 | documents_tasks_policies | Schema | 20 | documents, tasks, meetings, risks, hr_tickets... |
| 0010 | recruitment_onboarding | Schema | 20 | job_requisitions, candidates, onboarding... |
| 0011 | audit_security_system | Schema | 17 | audit_logs, security_events, settings, location... |

### التقوية P0 والوصول (0012–0025) — RPC/Fix

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0012 | core_p0_hardening | Fix | استبدال سياسات، وصول الموظفين |
| 0013 | foundation_access_and_provisioning | RPC | سياق الوصول، provision |
| 0014 | employee_access_canonicalization | Fix | توحيد سياسات الموظفين |
| 0015 | operational_workspaces | RPC | dashboard, inbox, workspace RPCs |
| 0016 | management_overviews_notifications | RPC | دوال النظرات العامة |
| 0017 | live_location_mobile_flow | RPC | تدفق الموقع المباشر |
| 0018 | employee_request_self_service | RPC | تقديم الطلبات |
| 0019 | kpi_forms_and_attendance_state | RPC | نماذج KPI، حالة الحضور |
| 0020 | passkey_lifecycle_and_mobile_actions | RPC | دورة حياة مفاتيح المرور |
| 0021 | mobile_details_and_action_routing | RPC | تفاصيل الموبايل |
| 0022 | mobile_daily_workspaces | RPC | التقارير اليومية |
| 0023 | passkey_devices_and_attendance_history | RPC | أجهزة المفاتيح |
| 0024 | mobile_notifications_and_action_links | RPC | إشعارات الموبايل |
| 0025 | admin_structure_access_onboarding | RPC | هيكل الإدارة |

### الميزات المتقدمة (0026–0038) — Schema+RPC

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0026 | leave_ledger_and_request_sla | Schema+RPC | leave_balance_accounts, leave_ledger_entries |
| 0027 | decision_lifecycle_polls_and_execution | Schema+RPC | decision_versions, polls... |
| 0028 | rosters_attendance_periods_and_corrections | Schema+RPC | attendance_periods, rosters... |
| 0029 | kpi_cycles_evidence_appeals | Schema+RPC | kpi_evidence, appeals... |
| 0030 | disputes_committee_quorum_decisions | Schema+RPC | dispute_decisions, appeals... |
| 0031 | documents_assets_offboarding | Schema+RPC | offboarding_cases... |
| 0032 | mobile_self_service_roster_hardening | Fix | تقوية الخدمة الذاتية |
| 0033 | talent_learning_documents_reports | Schema | learning_courses, reports... |
| 0034 | private_storage_buckets_and_retention | Config | حاويات التخزين |
| 0035 | enterprise_strategy_projects_service | Schema | strategic_objectives, enterprise... |
| 0036 | workforce_compensation_payroll | Schema | salary_structures, payroll... |
| 0037 | retention_privacy_and_release_hardening | Schema | video_access_logs |
| 0038 | release_access_privacy_integration | Schema | app_release_policies, managed_devices... |

### الأمان وتسجيل الدخول (0039–0055)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0039 | identifier_login_security | Schema | login_auth_attempts |
| 0040 | release_0_10_ui_and_identifier_login | Fix | واجهة 0.10 |
| 0041 | mobile_manager_and_executive | RPC | مساحات الموبايل |
| 0042 | mobile_executive_brief_and_people | RPC | ملخص تنفيذي |
| 0043 | grant_service_role_sla_processor | Fix | صلاحيات service_role |
| 0044 | recruitment_interviews_offers_hire | RPC | توظيف |
| 0045 | grant_authenticated_table_privileges | Fix | صلاحيات الجداول |
| 0046 | attendance_mock_location_travel_guard | Fix | حماية الموقع |
| 0047 | scheduling_leave_accrual_cron | Fix | استحقاق الإجازات |
| 0048 | pgcrypto_search_path | Fix | مسار pgcrypto |
| 0049 | schedule_edge_functions_via_pg_net | Config | جدولة cron |
| 0050 | audit_remediation_p0_p1 | Fix | معالجة المراجعة |
| 0051 | schedule_remaining_edge_functions | Config | جدولة إضافية |
| 0052 | audit_remediation_p2_p3 | Fix | معالجة المراجعة |
| 0053 | full_access_sees_all_workspaces | Fix | وصول كامل |
| 0054 | observability_and_alerting | Schema | system_alerts |
| 0055 | audit_remediation_p3_ledger | Fix | سجل المراجعة |

### الحوكمة والميزات (0056–0066)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0056 | employee_onboarding_simplification | Fix | تبسيط provision |
| 0057 | official_shifts_and_punch_reminders | Fix | تذكيرات الحضور |
| 0058 | official_kpi_governance | Schema+RPC | kpi_policy_versions, goals... |
| 0059 | dispute_committee_end_to_end | Schema+RPC | dispute_parties, statements... |
| 0060 | leave_types_and_entitlement | Fix | أنواع الإجازات |
| 0061 | leave_submission_and_casual | Fix | تقديم الإجازات |
| 0062 | request_escalation_on_behalf | Fix | التصعيد بالإنابة |
| 0063 | work_assignments | Schema+RPC | work_assignments |
| 0064 | dispute_committee_fixes | Fix | إصلاحات الشكاوى |
| 0065 | assignments_attendance_link | Fix | ربط التكليفات بالحضور |
| 0066 | assignments_kpi_link | Schema | kpi_assignment_contributions |

### الموقع المباشر والأجهزة (0067–0096)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0067 | live_location_executive_flow | RPC | تدفق الموقع التنفيذي |
| 0068 | location_request_ux_fixes | Fix | إصلاحات UX الموقع |
| 0069 | executive_attendance_today | RPC | حضور اليوم التنفيذي |
| 0070 | cancel_location_request | RPC | إلغاء طلب الموقع |
| 0071 | auto_cancel_on_new_request | Fix | إلغاء تلقائي |
| 0072 | fix_request_live_location_audit_call | Fix | إصلاح استدعاء التدقيق |
| 0073 | location_security_hardening | Schema | employee_devices, location_request_responses |
| 0074 | fix_log_audit_event_overload | Fix | إصلاح حمل التدقيق |
| 0075 | cleanup_attendance_rpc | Fix | تنظيف RPC |
| 0076 | fix_attendance_period_legal_entity_id | Fix | معرف الكيان القانوني |
| 0077 | executive_manager_fixes | Fix | إصلاحات المدير |
| 0078 | fix_record_attendance_overload | Fix | حمل تسجيل الحضور |
| 0079 | auto_provision_employees | Fix | تزويد تلقائي |
| 0080 | reapply_fixes | Fix | إعادة تطبيق |
| 0081 | fix_attendance_columns_and_employee_visibility | Fix | أعمدة + رؤية |
| 0082 | attendance_acceptance_leave_backfill | Fix | قبول + ملء إجازات |
| 0083 | location_history_and_verified_devices | Fix | تاريخ + أجهزة |
| 0084 | secure_employee_manager_change | RPC | تغيير مدير آمن |
| 0085 | repair_verified_employee_devices | Fix | إصلاح أجهزة |
| 0086 | location_only_completion_audit | Fix | تدقيق إكمال |
| 0087 | authorized_mobile_action_resolver | RPC | محلل إجراءات |
| 0088 | canonical_location_responses_and_map_snapshots | Schema | map_access_logs |
| 0089 | atomic_idempotent_attendance_finalize | Schema | attendance_punch_attempts |
| 0090 | secure_employee_archive_and_delete_guard | RPC | أرشفة + حماية حذف |
| 0091 | fix_employee_archive_permission | Fix | صلاحية الأرشفة |
| 0092 | fix_log_audit_event_type_mismatch | Fix | عدم تطابق نوع |
| 0093 | fix_device_not_active_root_cause | Fix | جهاز غير نشط |
| 0094 | punch_attendance_local_biometric | Schema | local_attendance_operations |
| 0095 | security_hardening_audit_fixes | Fix | تقوية + إصلاحات |
| 0096 | release_0_11_1_deep_audit_remediation | Fix | تدقيق 0.11.1 |

### إصدار V10 (0097–0118)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0097 | activate_employee_after_first_login | Fix | تفعيل بعد أول دخول |
| 0098 | signed_url_and_offline_support | Fix | روابط موقعة + offline |
| 0099 | fix_signed_url_rpc | Fix | إصلاح RPC |
| 0100 | enforce_report_storage_signed_url_fix | Fix | تخزين التقارير |
| 0101 | mobile_rpc_scoping_fixes | Fix | نطاق RPC |
| 0102 | fix_employee_home_rpc | Fix | صفحة الموظف |
| 0103 | reschedule_edge_jobs_from_runtime_settings | Config | إعادة جدولة |
| 0104 | v10_identity_workspace_local_biometric | RPC | هوية + بصمة |
| 0105 | fix_pgcrypto_function_search_paths | Fix | مسارات pgcrypto |
| 0106 | v10_runtime_contract_repairs | Fix | عقود التشغيل |
| 0107 | standardize_live_location_request_audit | Fix | توحيد تدقيق |
| 0108 | finish_runtime_lint_repairs | Fix | إصلاحات lint |
| 0109 | v10_kpi_workflow | RPC | سير عمل KPI |
| 0110 | v10_executive_kpi_report_access | Fix | وصول تقارير |
| 0111 | v10_dashboards_notifications_daily_report | RPC | لوحات + تقارير |
| 0112 | v10_request_acceptance_repairs | Fix | قبول الطلبات |
| 0113 | v10_request_attachment_catalog_access | Fix | وصول المرفقات |
| 0114 | unify_employee_avatar_storage | Fix | توحيد الصور |
| 0115 | fix_kpi_validation_array_initialization | Fix | تهيئة KPI |
| 0116 | restore_fcm_push_delivery | Fix | استعادة FCM |
| 0117 | fix_verification_status_and_fullname | Fix | التحقق + الاسم |
| 0118 | restore_release_governance_overview | Fix | نظرة الحوكمة |

### البنية والنشر (0119–0129)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0119 | bridge_placeholder | Placeholder | حجز رقم |
| 0120 | security_hardening_comprehensive | Fix | تقوية أمنية شاملة |
| 0121 | seed_org_structure_roles_departments | Seed | بذر الهيكل التنظيمي |
| 0122 | bridge_placeholder | Placeholder | حجز رقم |
| 0123 | mobile_org_chart_rpc | RPC | الهيكل التنظيمي |
| 0124 | remove_video_from_live_location | Fix | إزالة الفيديو |
| 0125 | employee_lifecycle_hardening | Fix | تقوية دورة الحياة |
| 0126 | fix_verification_status_and_fullname | Fix | حالة التحقق (2) |
| 0127 | monthly_attendance_statement | RPC | كشف الحضور الشهري |
| 0128 | repair_request_live_location_staging | Fix | إصلاح staging |
| 0129 | employee_edit_and_list_enrichment | RPC | إثراء بيانات الموظف |

### V17 (0130–0158)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0130 | v17_kpi_flow_reorder | Fix | إعادة ترتيب KPI |
| 0131 | v17_dispute_admin_actions | RPC | إجراءات إدارية |
| 0132 | v17_official_holidays | Schema+RPC | عطل رسمية |
| 0133 | v17_post_publishing | RPC | نشر المنشورات |
| 0134 | v17_request_types | Fix | أنواع الطلبات |
| 0135 | v17_word_count_checks | Fix | فحص عدد الكلمات |
| 0136 | fix_resolve_request_approver | Fix | حل المعتمد |
| 0137 | v17_attendance_executive_exemption | Fix | إعفاء التنفيذي |
| 0138 | v17_permission_matrix_fixes | Fix | مصفوفة الصلاحيات |
| 0139 | v17_request_return_status | Fix | حالة الإرجاع |
| 0140 | v17_attendance_history_days | Fix | أيام الحضور |
| 0141 | v17_dispute_admin_action_catalog | RPC | كتالوج الإجراءات |
| 0142 | v17_announcement_images | Fix | صور الإعلانات |
| 0143 | fix_attendance_all_non_executive | Fix | حضور غير التنفيذي |
| 0144 | v17_access_context_photo_url | Fix | رابط الصورة |
| 0145 | v18_device_approval_workflow | RPC | تدفق اعتماد الأجهزة |
| 0146 | v17_kpi_stage_notify | RPC | إشعارات KPI |
| 0147 | v17_request_decision_notify | RPC | إشعارات القرارات |
| 0148 | v17_announcement_publish_notify | RPC | إشعارات الإعلانات |
| 0149 | fix_org_chart_recursive_cte | Fix | CTE الهيكل التنظيمي |
| 0150 | fix_request_live_location_admin_access | Fix | وصول admin للموقع |
| 0151 | admin_sees_hr_workspace | Fix | admin يرى HR |
| 0152 | v18_committee_dispute_mobile_portal | RPC | بوابة اللجنة |
| 0153 | fix_kpi_notify_fullname | Fix | اسم KPI |
| 0154 | add_departments_slug_and_fix_seed_timing | Fix | slug الأقسام |
| 0155 | fix_attendance_missing_check_null | Fix | فحص null |
| 0156 | multi_department_support | Schema | employee_departments |
| 0157 | fix_seed_timing_permission_grants | Fix | توقيت البذر |
| 0158 | grant_employee_devices_select | Fix | صلاحية قراءة الأجهزة |

### V23 (0159–0160)

| الرقم | الاسم | النوع | الوصف |
|---|---|---|---|
| 0159 | v23_roles_permissions_hardening | Fix | تقوية أدوار وصلاحيات |
| 0160 | v23_kpi_parallel_workflow | RPC | ⚠️ **مكرر** — سير KPI متوازي |
| 0160 | v23_leaves_escalation_split | RPC | ⚠️ **مكرر** — تصعيد الإجازات |
| 0160 | v23_notification_catalog_completion | RPC | ⚠️ **مكرر** — كتالوج الإشعارات |

---

## اختبارات pgTAP (65 ملف)

| الرقم | الملف | الوصف |
|---|---|---|
| 0001 | core_security_structure | أمان + هيكل |
| 0002 | foundation_contracts | عقود أساسية |
| 0003 | operational_workspaces | مساحات تشغيلية |
| 0004 | management_overviews | نظرات إدارية |
| 0005 | live_location_flow | تدفق الموقع |
| 0006 | request_self_service | خدمة ذاتية |
| 0007 | kpi_attendance_mobile | KPI + حضور |
| 0008 | mobile_details_routing | تفاصيل + توجيه |
| 0009 | mobile_daily_workspaces | مساحات يومية |
| 0010 | passkey_revoke_attendance_history | إلغاء + تاريخ |
| 0011 | mobile_notifications_contract | إشعارات |
| 0012 | passkey_mobile_action_security | أمان إجراءات |
| 0013 | admin_operations | عمليات إدارية |
| 0014 | leave_ledger_contract | دفتر الإجازات |
| 0015 | decision_lifecycle_contract | دورة القرارات |
| 0016 | attendance_operations_contract | عمليات الحضور |
| 0017 | kpi_advanced_contract | KPI متقدم |
| 0018 | dispute_committee_contract | لجنة الشكاوى |
| 0019 | lifecycle_contract | دورة الحياة |
| 0020 | enterprise_talent_learning_contract | مواهب + تعلم |
| 0021 | enterprise_management_modules | وحدات مؤسسية |
| 0022 | workforce_payroll_engagement_contract | رواتب + مشاركة |
| 0023 | retention_privacy_contract | استبقاء + خصوصية |
| 0024 | release_access_privacy_integration_governance | وصول + حوكمة |
| 0025 | identifier_login_security | أمان تسجيل الدخول |
| 0026 | release_0_10_contract | عقد 0.10 |
| 0027 | persona_rls_runtime | RLS + runtime |
| 0028 | recruitment_interviews_offers_hire | توظيف |
| 0029 | break_glass_runtime | وصول طوارئ |
| 0030 | leave_accrual_scheduling | استحقاق + جدولة |
| 0031 | audit_remediation_runtime | معالجة تدقيق |
| 0032 | audit_remediation_p2 | تدقيق P2 |
| 0033 | observability_alerting | مراقبة + تنبيهات |
| 0034 | audit_remediation_p3_ledger | تدقيق P3 |
| 0035 | official_kpi_governance | حوكمة KPI |
| 0036 | official_kpi_runtime | KPI runtime |
| 0037 | dispute_committee_runtime | لجنة شكاوى |
| 0038 | leave_workflow_contract | سير الإجازات |
| 0039 | work_assignments_contract | مهام العمل |
| 0040 | live_location_executive_runtime | موقع تنفيذي |
| 0041 | v4_location_notification_device_contract | موقع + إشعار + جهاز |
| 0042 | atomic_attendance_contract | حضور ذري |
| 0043 | employee_archive_delete_contract | أرشفة + حذف |
| 0044 | release_0_11_1_deep_audit_contract | تدقيق 0.11.1 |
| 0045 | v10_six_role_acceptance | قبول 6 أدوار |
| 0046 | employee_avatar_storage_contract | تخزين صور |
| 0047 | kpi_validation_array_initialization | تهيئة KPI |
| 0048 | fcm_push_delivery_runtime | تسليم FCM |
| 0049 | release_governance_overview_regression | انحدار الحوكمة |
| 0050 | monthly_attendance_statement | كشف شهري |
| 0051 | provision_employee_record | تزويد موظف |
| 0052 | employee_edit_enrichment | تعديل + إثراء |
| 0053 | v17_kpi_flow | سير KPI V17 |
| 0054 | v17_dispute_admin_actions | إجراءات شكاوى |
| 0055 | v17_official_holidays | عطل رسمية |
| 0056 | v17_operations_request_routing | توجيه عمليات |
| 0057 | v17_post_publishing | نشر إعلانات |
| 0058 | v17_word_count_checks | فحص كلمات |
| 0059 | v17_permission_matrix_fixes | مصفوفة صلاحيات |
| 0060 | v17_request_return_and_attendance_days | إرجاع + أيام حضور |
| 0061 | v18_device_approval_workflow | اعتماد أجهزة |
| 0062 | security_negative_tests | ⚠️ مكرر |
| 0062 | v23_rbac_negative_scenarios | ⚠️ مكرر |
| 0065 | v23_kpi_parallel_workflow | سير KPI V23 |

---

## إحصائيات

| الفئة | العدد | النسبة |
|---|---|---|
| Schema (جداول جديدة) | ~40 | 25% |
| RPC (دوال جديدة) | ~30 | 18% |
| Fix/Patch (إصلاحات) | ~80 | 49% |
| Seed/Config | ~8 | 5% |
| Bridge placeholders | 2 | 1% |
| V17 features | ~18 | 11% |
| V23 features | ~4 | 2% |

---

## قواعد للوكلاء

1. **فحص التكرار قبل الإنشاء:**
   ```bash
   ls supabase/migrations/ | sort | tail -3
   ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
   ```
2. **آخر رقم مستخدم:** 0160 (مكرر × 3 — الرقم التالي المتاح هو **0161**)
3. **تسجيل كل migration جديد هنا قبل الإنشاء**
4. **لا تعدّل migration منشورة — أنشئ migration جديدة**
