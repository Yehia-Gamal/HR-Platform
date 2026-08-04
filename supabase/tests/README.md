# Database tests

حزمة اختبارات pgTAP/SQL. ملفات متسلسلة الأرقام (فجوات 0063/0064/0091/0092 محجوزة أو مدمجة في ملفات أخرى). العدد الحالي: 99 ملفًا حتى `0103`.

| # | الملف | المجال |
|---:|---|---|
| 0001 | `core_security_structure` | الأمان البنيوي ومنع الكتابة المباشرة |
| 0002 | `foundation_contracts` | عقود Foundation وإنشاء الموظف |
| 0003 | `operational_workspaces` | Workspaces التشغيلية |
| 0004 | `management_overviews` | لوحات الإدارة |
| 0005 | `live_location_flow` | الموقع والتتبع والفيديو |
| 0006 | `request_self_service` | الطلبات الذاتية والتحقق الخادمي |
| 0007 | `kpi_attendance_mobile` | KPI والحضور للموبايل |
| 0008 | `mobile_details_routing` | تفاصيل الإجراءات والـDeep Links |
| 0009 | `mobile_daily_workspaces` | الملف والمهام والفريق والتقارير اليومية |
| 0010 | `passkey_revoke_attendance_history` | إلغاء Passkeys وسجل الحضور |
| 0011 | `mobile_notifications_contract` | الإشعارات وروابط الإجراءات |
| 0012 | `passkey_mobile_action_security` | أمان Passkey ومسارات الموبايل |
| 0013 | `admin_operations` | إدارة الهيكل والأدوار والتوظيف وOnboarding ومنع الكتابة المباشرة |
| 0014 | `leave_ledger_contract` | سجل أرصدة الإجازات |
| 0015 | `decision_lifecycle_contract` | دورة حياة القرارات |
| 0016 | `attendance_operations_contract` | عمليات الحضور |
| 0017 | `kpi_advanced_contract` | KPI المتقدم |
| 0018 | `dispute_committee_contract` | النزاعات واللجان |
| 0019 | `lifecycle_contract` | دورة الحياة الوظيفية |
| 0020 | `enterprise_talent_learning_contract` | المواهب والتعلّم المؤسسي |
| 0021 | `enterprise_management_modules` | وحدات الإدارة المؤسسية |
| 0022 | `workforce_payroll_engagement_contract` | القوى العاملة والرواتب والمشاركة |
| 0023 | `retention_privacy_contract` | الاحتفاظ والخصوصية |
| 0024 | `release_access_privacy_integration_governance` | حوكمة الإصدار والوصول والخصوصية والتكامل |
| 0025 | `identifier_login_security` | أمان الدخول بمعرّف متعدد (بريد/هاتف/كود) |
| 0026 | `release_0_10_contract` | عقد إصدار Build 0.10.0 |
| 0027 | `persona_rls_runtime` | Persona RLS Runtime Matrix: سياقات JWT فعلية لتسعة Personas ضد RLS وRPCs (23 فحصًا) |
| 0028 | `recruitment_interviews_offers_hire` | عقود RPCs التوظيف: التواقيع الدقيقة وSECURITY DEFINER والمنح (Migration 0044) |
| 0029 | `break_glass_runtime` | Break-glass Runtime Lifecycle: طلب → Four-eyes → دور مؤقت → انتهاء آلي (9 فحوصات) |
| 0030 | `leave_accrual_scheduling` | الاستحقاق الشهري للإجازات (Migration 0047): idempotency وحدود الخدمة |
| 0031 | `audit_remediation_runtime` | إثبات Runtime لإصلاحات التدقيق والأمان والصلاحيات |
| 0032 | `audit_remediation_p2` | عقود إصلاحات التدقيق P2/P3 (Migration 0052) |
| 0033 | `observability_alerting` | المراقبة والتنبيهات وقواعد تسجيل الأحداث (0054) |
| 0034 | `audit_remediation_p3_ledger` | دفتر التدقيق LEDGER-02 (0055) |
| 0035 | `official_kpi_governance` | حوكمة KPI الرسمية ومراحلها وصلاحياتها (0058) |
| 0036 | `official_kpi_runtime` | سيناريوهات Runtime لمسار KPI الرسمي |
| 0037 | `dispute_committee_runtime` | سيناريوهات Runtime للجنة حل المشكلات (0059) |
| 0038 | `leave_workflow_contract` | نظام الإجازات الجديد (0060/0061/0062): الكوتا القانونية (15/6/24) وقاعدة الـ30 يومًا والتصعيد (24 فحصًا) |
| 0039 | `work_assignments_contract` | تكليفات العمل (0063/0065/0066): المأمورية/القافلة/الفاندي + إثبات عدم الخصم من رصيد الإجازات (18 فحصًا) |
| 0040 | `live_location_executive_runtime` | رحلة المدير التنفيذي للموقع الحي + فيديو (0067): أوضاع ودورة استجابة وتدقيق وعزل RLS (36 فحصًا) |
| 0041 | `v4_location_notification_device_contract` | عقد إشعار الموقع والجهاز الموثوق |
| 0042 | `atomic_attendance_contract` | عقد الإنهاء الذري للحضور |
| 0043 | `employee_archive_delete_contract` | عقد الأرشفة والحذف المحمي للموظف |
| 0044 | `release_0_11_1_deep_audit_contract` | عقد إصلاحات تدقيق الإصدار 0.11.1 |
| 0045 | `v10_six_role_acceptance` | قبول الأدوار الستة (V10): موظف/مدير/Operations/تنفيذي/HR/سكرتير |
| 0046 | `employee_avatar_storage_contract` | تخزين صور الموظفين وحدود RLS والصلاحيات |
| 0047 | `kpi_validation_array_initialization` | تثبيت مصفوفة أخطاء التحقق من KPI (115) |
| 0048 | `fcm_push_delivery_runtime` | إثبات خط FCM للطلبات العاجلة (0116) |
| 0049 | `release_governance_overview_regression` | انحدار حوكمة الإصدار بعد 0117 |
| 0050 | `monthly_attendance_statement` | عقد كشف الحضور والانصراف الشهري (V12 §18، 0127) |
| 0051 | `provision_employee_record` | إنشاء سجل الموظف transactional عبر `provision_employee_record` |
| 0052 | `employee_edit_enrichment` | تعديل بيانات الموظف + إثراء القائمة (V17، 0129) |
| 0053 | `v17_kpi_flow` | عكس مسار KPI: إزالة manager_final (0130) |
| 0054 | `v17_dispute_admin_actions` | إجراءات إدارة النزاعات (V17 §14، 0131) |
| 0055 | `v17_official_holidays` | الإجازات الرسمية ونطاق الاستثناءات (V17 §1.7، 0132) |
| 0056 | `v17_operations_request_routing` | توجيه طلبات التشغيل للمدير التنفيذي (V17 §1.2) |
| 0057 | `v17_post_publishing` | نشر المنشورات الرسمية (V17 §18، 0133) |
| 0058 | `v17_word_count_checks` | قيود طول النص (V17 §1.3، 0135) |
| 0059 | `v17_permission_matrix_fixes` | مصفوفة الصلاحيات (V17 §2.2.1، 0138) |
| 0060 | `v17_request_return_and_attendance_days` | إجراء "إعادة" (return) وتصفية p_days (V17 §4.2+§4.3) |
| 0061 | `v18_device_approval_workflow` | سير عمل اعتماد الأجهزة (V18 §5، 0145) |
| 0062 | `security_negative_tests` | اختبارات أمان سلبية — رفض العمليات غير المصرح بها |
| 0065 | `v23_kpi_parallel_workflow` | KPI المتوازي: HR + مدير معًا (V23 §06) |
| 0066 | `v23_dispute_committee_alignment` | مواءمة لجنة النزاعات مع V23 (0164) |
| 0067 | `v23_device_biometric_recovery` | استعادة الجهاز البيومتري + الإلغاء الإداري (V23 Agent-03) |
| 0068 | `v23_security_search_path_audit` | تدقيق أمني: search_path hardening + قائمة using(true) المسموحة |
| 0069 | `v23_notification_catalog` | كتالوج الإشعارات: المشغلات + إشعارات اعتماد الجهاز (V23 §8) |
| 0070 | `v23_rbac_negative_scenarios` | RBAC سلبية: تقييد HR وحماية full-access وتدقيقها |
| 0071 | `v23_attendance_geofence_hardening` | السياج الجغرافي للحضور (V23 §4) |
| 0072 | `v23_leaves_escalation_split` | فصل مهلة التصعيد (0171) |
| 0073 | `v23_scoped_permission_foundation` | أساس الصلاحيات المحددة النطاق (0172) |
| 0074 | `v23_multi_assignment_p0` | التعيينات المتعددة P0 (0173) |
| 0075 | `v23_rate_limiting_expansion` | توسيع تحديد المعدل لـ 7 مجالات (0174) |
| 0076 | `v23_attendance_statement_fields` | حقول كشف الحضور الشهري الجديدة (0176) |
| 0077 | `v23_multi_department_behavioral` | سلوك تعدد الإدارات (0156 + 0173): تعيين/إزالة/تزامن/حراس |
| 0078 | `v23_rls_abac_reporting_lines` | ABAC خطوط الإبلاغ عبر `can_access_employee` (V23 §3.4) |
| 0079 | `v23_no_individual_permissions` | لا صلاحية فردية للمستخدم (V23 §3.2) |
| 0080 | `v23_casual_leave_auto_approval` | العارضة = تنفيذ مباشر بشروط (V23 §7.3) |
| 0081 | `v23_executive_no_kpi_evaluation` | Executive لا يُقيَّم في KPI (V23 §8.4) |
| 0082 | `v23_missing_checkout_no_phantom` | Missing Checkout لا يُنشئ وقتًا وهميًا (V23 §6.5) |
| 0083 | `v23_dispute_simplified_submission` | حذف الأولوية والمكان والأدلة من تقديم النزاعات (V23 §9.3) |
| 0084 | `rls_financial_tables` | RLS على الجداول المالية: حماية التعويضات والرواتب |
| 0085 | `attendance_device_mismatch_fix` | إصلاح تعارض جهاز البصمة (0226) |
| 0086 | `device_reinstate_lifecycle` | دورة حياة الأجهزة (Reinstate Pipeline) + خط أنابيب الأمان |
| 0087 | `validate_storage_paths_and_urls` | التحقق خادميًا من مسارات التخزين والروابط (0235) |
| 0088 | `finalize_attendance_selfie_path_scope` | نطاق selfie_path حسب الموظف (0236 + 0239) |
| 0089 | `batch_size_limits_dos_hardening` | حدود حجم الدفعات في الدوال الحساسة (0238) |
| 0090 | `admin_panel_rpc_authz` | تفويض RPCs لوحة الأدمن (0256) |
| 0093 | `harden_url_path_validators` | انحدارات المسارات: مسافات بادئة وهروب مختلط وتجاوز (0249) |
| 0094 | `harden_external_link_validator` | انحدارات الروابط الخارجية (0250) |
| 0095 | `monthly_attendance_as_of_date` | كشف الحضور الشهري "حتى الآن" دون عدّ المستقبل غيابًا (0251) |
| 0096 | `employee_departments_rls_select` | سياسة قراءة employee_departments (0254): self/full-access/HR/مدير مباشر |
| 0097 | `attendance_day_detail_explainability` | إثراء كل يوم في الكشف بحقول "details" توضيحية (0252) |
| 0098 | `leave_workflow_two_step` | سير عمل الإجازة بخطوتين (مدير → HR) + تجاوز المدير بعد 12 ساعة (0253) |
| 0099 | `payroll_dsl_validation` | أساس DSL صيغ الرواتب (0255 + 0258) |
| 0100 | `payroll_dsl_interpreter` | مفسّر DSL صيغ الرواتب الخالص (0259) |
| 0101 | `rls_gap_closure` | إغلاق ثغرات RLS المتبقية (0260) |
| 0102 | `ops_center_guard` | حارس `get_operations_center_data` (0261) |
| 0103 | `payroll_dsl_fail_closed` | انحدار المنطق الثلاثي في بوابة DSL (0262) |
| 0104 | `audit_fix_rpc_grants_self_guard` | أذونات لوحة الإدارة وحماية الحقول الوظيفية وتماثل revoke/assign (0263) |

تشغيلها يتطلب Supabase محليًا:

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

الاختبارات البنيوية لا تستبدل اختبارات Personas الفعلية. قبل Production يجب إثبات السيناريوهات التالية على Local وStaging:

- الموظف لا يقرأ موظفًا آخر.
- المدير المباشر يرى مرؤوسيه فقط.
- مدير الإدارة يرى نطاقه وفق ABAC.
- HR لا يصل إلى أسرار Main Admin.
- المدير التنفيذي لا ينفذ بصمة شخصية.
- لا توجد موافقة ذاتية.
- الموافقة الأولى تفتح الخطوة التالية ولا تنهي المسار.
- تحدي WebAuthn لا يُستهلك مرتين.
- الفيديو والموقع لا يُقبلان دون طلب نشط وموافقة.
- الكتابة على الإدارات والمناصب والأدوار والتوظيف وOnboarding تتم عبر RPCs المصرح بها فقط.
