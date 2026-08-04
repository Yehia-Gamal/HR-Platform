# Migrations — أحلى شباب Management OS V8

تُطبَّق الملفات بالترتيب الرقمي. بعد تطبيق أي Migration لا تُعدّل في Production؛ تُنشأ Migration جديدة. الملفات الحالية هي مصدر البناء النظيف من قاعدة فارغة، وأي تعديل قبل أول نشر فعلي يجب أن يبقى موثقًا ومختبرًا.

> ⚠️ **جلسات متوازية**: يعمل أكثر من مهندس على هذا المستودع في الوقت نفسه. قبل إنشاء أي Migration أو اختبار **تحقق دائمًا من أعلى رقم على القرص** (`ls supabase/migrations/ | sort | tail -3`) ومن عدم وجود تكرار، ولا تعتمد على README أو Registry وحدهما. افحص التكرار بـ `ls supabase/migrations/ | cut -c1-4 | sort | uniq -d`. لا تعدّل ملفات migration مرقّمة يملكها شخص آخر إلا بالتنسيق معه.

| # | الملف | المجال |
|---:|---|---|
| 0001 | `extensions_and_conventions` | Extensions والدوال العامة والتوقيت |
| 0002 | `permissions_roles_functions` | كتالوج الصلاحيات والأدوار ودوال التخويل |
| 0003 | `organization` | الكيانات والفروع والإدارات والفرق والمناصب والورديات |
| 0004 | `employees` | الموظفون والحسابات والعلاقات والمستندات |
| 0005 | `attendance` | الحضور والهوية وPasskey والمخاطر |
| 0006 | `requests_workflow` | الطلبات ومحرك الموافقات والإجازات والمأموريات |
| 0007 | `kpi_performance` | KPI والأهداف والكفاءات وPIP |
| 0008 | `communications_disputes` | الإعلانات والقرارات والإشعارات والنزاعات |
| 0009 | `documents_tasks_policies` | المستندات والمهام والسياسات والمشروعات والمخاطر |
| 0010 | `recruitment_onboarding` | ATS والعروض والعقود والإلحاق الوظيفي |
| 0011 | `audit_security_system` | التدقيق والأمان والإعدادات والتكاملات والموقع الحي |
| 0012 | `core_p0_hardening` | RLS بالنطاق، الشجرة الإدارية، Workflow متعدد المراحل، Passkey hardening |
| 0013 | `foundation_access_and_provisioning` | Access Context وإنشاء الموظف والحساب Transactionally |
| 0014 | `employee_access_canonicalization` | توحيد صلاحيات الموظف ومنع الحذف المباشر |
| 0015 | `operational_workspaces` | Read models للحضور والطلبات وKPI والقناة الرسمية ومركز الإجراءات |
| 0016 | `management_overviews_notifications` | لوحات الإدارة والإشعارات وHealth summaries |
| 0017 | `live_location_mobile_flow` | طلب الموقع والتتبع والفيديو الخاص وسياسات التخزين |
| 0018 | `employee_request_self_service` | نماذج الطلبات الذاتية والتحقق الخادمي |
| 0019 | `kpi_forms_and_attendance_state` | نماذج KPI التفصيلية وحالة الحضور للموبايل |
| 0020 | `passkey_lifecycle_and_mobile_actions` | تسجيل Passkey ودورة حياته وعقود الإجراءات |
| 0021 | `mobile_details_and_action_routing` | تفاصيل الطلب/KPI/القرار وAction routing |
| 0022 | `mobile_daily_workspaces` | الملف والمهام والفريق والتقارير اليومية |
| 0023 | `passkey_devices_and_attendance_history` | إدارة أجهزة Passkey وسجل الحضور |
| 0024 | `mobile_notifications_and_action_links` | إشعارات الموبايل وروابط الإجراءات |
| 0025 | `admin_structure_access_onboarding` | إدارة الهيكل والمناصب وRole Builder والتوظيف وOnboarding عبر RPCs |
| 0026 | `leave_ledger_and_request_sla` | سجل أرصدة الإجازات وSLA للطلبات |
| 0027 | `decision_lifecycle_polls_and_execution` | دورة حياة القرارات والتصويت والتنفيذ |
| 0028 | `rosters_attendance_periods_and_corrections` | الروستر وفترات الحضور والتصحيحات |
| 0029 | `kpi_cycles_evidence_appeals_and_attendance_inputs` | دورات KPI والأدلة والتظلمات ومدخلات الحضور |
| 0030 | `disputes_committee_quorum_decisions_and_appeals` | النزاعات ونصاب اللجان والقرارات والتظلمات |
| 0031 | `documents_assets_and_offboarding_lifecycle` | المستندات والعهد ودورة Offboarding |
| 0032 | `mobile_self_service_roster_and_period_hardening` | خدمة ذاتية للموبايل وتقوية الروستر والفترات |
| 0033 | `talent_learning_documents_reports_notifications` | المواهب والتعلّم والمستندات والتقارير والإشعارات |
| 0034 | `private_storage_buckets_and_retention` | حاويات التخزين الخاصة وسياسات الاحتفاظ |
| 0035 | `enterprise_strategy_projects_service_governance` | الإستراتيجية والمشروعات وحوكمة الخدمة |
| 0036 | `workforce_compensation_payroll_engagement` | القوى العاملة والتعويضات والرواتب والمشاركة |
| 0037 | `retention_privacy_and_release_hardening` | الاحتفاظ والخصوصية وتقوية الإصدار |
| 0038 | `release_access_privacy_integration_governance` | حوكمة الوصول والخصوصية والتكامل للإصدار |
| 0039 | `identifier_login_security` | أمان الدخول بمعرّف متعدد (بريد/هاتف/كود) |
| 0040 | `release_0_10_ui_and_identifier_login` | نشر بيانات Build 0.10.0 وتحسين الواجهات والدخول بمعرّف |
| 0041 | `mobile_manager_and_executive_workspaces` | مساحات عمل المدير والمدير التنفيذي للموبايل |
| 0042 | `mobile_executive_brief_and_people` | الملخص التنفيذي اليومي وملخص الموظف مصغّر الخصوصية |
| 0043 | `grant_service_role_sla_processor` | إصلاح Runtime: منح service_role تنفيذ معالج SLA للطلبات (كان محجوبًا خطأً منذ 0026) |
| 0044 | `recruitment_interviews_offers_hire` | RPCs التوظيف: جدولة المقابلات وقراراتها، إنشاء العروض وتحولات حالتها، والتعيين من الطلب |
| 0045 | `grant_authenticated_table_privileges` | إصلاح Runtime: منح صلاحيات DML للدور `authenticated` وSELECT للدور `anon` على جداول public لتفعيل سياسات RLS (كانت معطّلة لغياب المنح)، مع سحب الكتابة المباشرة عن الجداول الخادمية (attendance_events/passkey_credentials/webauthn_challenges) وحجب الجداول السرية (login_auth_attempts/credential_vault/password_reset_requests) |
| 0046 | `attendance_mock_location_and_travel_guard` | أمان الحضور: عمود `is_mock_location`، وتوسيع `record_attendance_event` بمعامل `p_is_mock`، وكشف الموقع المزيف + حارس الانتقال المستحيل (>150كم/س خلال 6 ساعات) — يُعلّم البصمة `flagged` للمراجعة مع أسباب في `notes` |
| 0047 | `scheduling_leave_accrual_and_cron` | المشغّل الآلي: عمود `monthly_accrual_units` على `leave_types`، ودالة `run_monthly_leave_accrual` (service_role، idempotent عبر source_key، لا تتجاوز الحد السنوي)، وتفعيل `pg_cron` وجدولة المهام الأربع (SLA كل 10د، الاستحقاق أول الشهر، تنظيف الاحتفاظ يوميًا، طابور التقارير كل 15د) مع حارس آمن إن غابت الإضافة محليًا |
| 0048 | `pgcrypto_search_path_for_digest` | إصلاح جذر نشر Supabase المُدار: ضمان `pgcrypto` وإعادة تعريف `decision_content_hash` مع `search_path = public, extensions` ليُحلّ `digest` أينما ثُبّتت الإضافة (محلي/staging/production) — يمنع فشل `function digest(text, unknown) does not exist` عند `db push` |
| 0049 | `schedule_edge_functions_via_pg_net` | جدولة استدعاء دالتَي Edge عبر `pg_net`/`net.http_post` بترويسة `x-cron-secret` (notification-dispatcher + integration-outbox-worker) — لأن 0047 جدول دوال DB مباشرة فقط |
| 0050 | `audit_remediation_p0_p1` | إصلاحات التدقيق العميق P0/P1: انهيار نطاق جداول payroll/loan (قراءة/كتابة على مستوى المؤسسة)، وكتابة `kpi_scores` لغير الذات تتجاهل نطاق الموظف |
| 0051 | `schedule_remaining_edge_functions` | إكمال جدولة دوال Edge المتبقية عبر `pg_net` (scheduled-report-runner + retention-cleanup) مع `cron.unschedule` آمن قبل إعادة الجدولة |
| 0052 | `audit_remediation_p2_p3` | إصلاحات التدقيق P2/P3: سحب `PUBLIC EXECUTE` الافتراضي عن دوال DEFINER (0033/0035/0036) وإحكام صلاحيات جدولة التقارير (أُعيد ترقيمه من 0051) |
| 0053 | `full_access_sees_all_workspaces` | حسابات الوصول الكامل ترى كل مساحات العمل |
| 0054 | `observability_and_alerting` | طبقة المراقبة والتنبيهات (Observability & Alerting) — P1.7 |
| 0055 | `audit_remediation_p3_ledger` | إصلاحات التدقيق P3 — LEDGER-02 |
| 0056 | `employee_onboarding_simplification` | تبسيط رحلة إنشاء الموظف في لوحة الأدمن |
| 0057 | `official_shifts_and_punch_reminders` | توقيت العمل الرسمي + تذكيرات البصمة |
| 0058 | `official_kpi_governance` | سياسة KPI الشهرية الرسمية وسير عملها وحوكمة السكرتير التنفيذي |
| 0059 | `dispute_committee_end_to_end` | سير عمل لجنة المشكلات والنزاعات من البداية للنهاية |
| 0060 | `leave_types_and_entitlement` | أنواع الإجازات القانونية + الكوتا + قاعدة الـ30 يومًا + إعدادات التصعيد |
| 0061 | `leave_submission_and_casual` | ربط تقديم الإجازة بالدفتر + تنفيذ العارضة مباشرة + توجيه المدير |
| 0062 | `request_escalation_on_behalf` | تصعيد حقيقي للطلبات + قرار بالإنابة + صلاحيات السكرتير التنفيذي |
| 0063 | `work_assignments` | وحدة تكليفات العمل — المأمورية / القافلة / الفاندي |
| 0064 | `dispute_committee_fixes` | إصلاحات لجنة المشكلات والنزاعات (0059) |
| 0065 | `assignments_attendance_link` | ربط الإجازات وتكليفات العمل بالحضور + توسيع إعفاء KPI |
| 0066 | `assignments_kpi_link` | ربط التكليفات (قافلة/فاندي) بـ KPI مع منع الاحتساب المزدوج |
| 0067 | `live_location_executive_flow` | رحلة المدير التنفيذي لطلب الموقع الحي + فيديو التحقق |
| 0068 | `location_request_ux_fixes` | تحسينات UX لطلب الموقع الحي |
| 0069 | `executive_attendance_today` | لوحة حضور اليوم للمدير التنفيذي |
| 0070 | `cancel_location_request` | السماح للمُطلب بإلغاء طلب الموقع النشط |
| 0071 | `auto_cancel_on_new_request` | إلغاء تلقائي للطلب السابق عند إرسال طلب موقع جديد |
| 0072 | `fix_request_live_location_audit_call` | إصلاح استدعاء `log_audit_event` في `request_live_location` |
| 0073 | `location_security_hardening` | تقوية أمان الموقع الحي |
| 0074 | `fix_log_audit_event_overload` | إصلاح الحمولة الزائدة لدالة `log_audit_event` |
| 0075 | `cleanup_attendance_rpc` | إزالة التواقيع القديمة (numeric) لـ `record_attendance_event` |
| 0076 | `fix_attendance_period_legal_entity_id` | إصلاح خطأ `e.legal_entity_id` في `get_my_attendance_services` |
| 0077 | `executive_manager_fixes` | إصلاحات المدير التنفيذي |
| 0078 | `fix_record_attendance_overload` | إصلاح PGRST203: إعادة إنشاء كل تحميلات `record_attendance_event` |
| 0079 | `auto_provision_employees` | إنشاء الموظف تلقائيًا عند التسجيل |
| 0080 | `reapply_fixes` | إعادة تطبيق إصلاحات دوال الحضور |
| 0081 | `fix_attendance_columns_and_employee_visibility` | إصلاح أسماء أعمدة الحضور + رؤية الموظف |
| 0082 | `attendance_acceptance_leave_backfill` | جعل الحضور المحقق نهائيًا ومرئيًا فورًا |
| 0083 | `location_history_and_verified_devices` | حفظ طلبات الموقع المستقلة + تفعيل الأجهزة الموثقة ذريًا |
| 0084 | `secure_employee_manager_change` | تغيير المدير المباشر المرتبط بـ HR في معاملة واحدة |
| 0085 | `repair_verified_employee_devices` | إصلاح صفوف الأجهزة الأساسية لـ passkeys الموجودة |
| 0086 | `location_only_completion_audit` | إكمال طلبات وضع الفيديو صراحةً مع التدقيق |
| 0087 | `authorized_mobile_action_resolver` | محلل deep-link الدقيق مع قائمة أنواع صارمة |
| 0088 | `canonical_location_responses_and_map_snapshots` | توحيد استجابات الموقع + لقطات خرائط خاصة |
| 0089 | `atomic_idempotent_attendance_finalize` | إنهاء بصمة WebAuthn المحققة خادميًا بشكل ذري |
| 0090 | `secure_employee_archive_and_delete_guard` | الأرشفة تحفظ التاريخ؛ الحذف الدائم استثناء محروس |
| 0091 | `fix_employee_archive_permission` | استخدام الصلاحيات الأساسية لوصول HR للأرشفة |
| 0092 | `fix_log_audit_event_type_mismatch` | إصلاح استدعاءات `log_audit_event` في دوال الأرشفة |
| 0093 | `fix_device_not_active_root_cause` | إصلاح السبب الجذري لـ `device_not_active` |
| 0094 | `punch_attendance_local_biometric` | بصمة حضور خفيفة عبر التحقق البيومتري المحلي |
| 0095 | `security_hardening_audit_fixes` | إصلاحات تقوية أمنية من تدقيق APK |
| 0096 | `release_0_11_1_deep_audit_remediation` | سد ثغرات تدقيق الإصدار 0.11.1 P0/P1 |
| 0097 | `activate_employee_after_first_login` | تفعيل الموظف بعد أول تسجيل دخول/تغيير كلمة المرور |
| 0098 | `signed_url_and_offline_support` | Signed URL لملفات التقارير + دعم الكاش دون اتصال |
| 0099 | `fix_signed_url_rpc` | استبدال الموقّع غير الصالح بدالة Storage مدعومة بـ RLS |
| 0100 | `enforce_report_storage_signed_url_fix` | إصلاح إنتاجي لتخزين التقارير (Signed URL) |
| 0101 | `mobile_rpc_scoping_fixes` | إصلاح نطاق دوال الموبايل |
| 0102 | `fix_employee_home_rpc` | إصلاح `get_employee_home` (security definer + حارس NULL) |
| 0103 | `reschedule_edge_jobs_from_runtime_settings` | إعادة جدولة عمال Edge بعد ضبط عنوان التشغيل |
| 0104 | `v10_identity_workspace_local_biometric` | V10: تقوية الهوية ومساحات العمل والبصمة البيومترية المحلية |
| 0105 | `fix_pgcrypto_function_search_paths` | إصلاح `search_path` لدوال pgcrypto (SECURITY DEFINER) |
| 0106 | `v10_runtime_contract_repairs` | إصلاحات Runtime والعقود من مجموعة الاختبارات المحلية |
| 0107 | `standardize_live_location_request_audit` | توحيد تدقيق طلبات الموقع الحي |
| 0108 | `finish_runtime_lint_repairs` | إنهاء إصلاحات plpgsql_check للأعمدة والتحميلات |
| 0109 | `v10_kpi_workflow` | سير عمل KPI: موظف → مدير مباشر → HR → اعتماد المدير النهائي |
| 0110 | `v10_executive_kpi_report_access` | المدير التنفيذي يقرأ تقارير KPI ولا يعتمد الدرجات |
| 0111 | `v10_dashboards_notifications_daily_report` | مواءمة اللوحات ومركز الإجراءات والتقرير اليومي مع V10 |
| 0112 | `v10_request_acceptance_repairs` | إصلاحات قبول طلبات الإجازة والمأمورية |
| 0113 | `v10_request_attachment_catalog_access` | السماح للمراجعين بقراءة سجل المرفقات |
| 0114 | `unify_employee_avatar_storage` | توحيد صور الموظفين على حاوية employee-avatars العامة |
| 0115 | `fix_kpi_validation_array_initialization` | تثبيت مصفوفة أخطاء التحقق من KPI |
| 0116 | `restore_fcm_push_delivery` | استعادة خط FCM الإنتاجي للطلبات العاجلة |
| 0117 | `fix_verification_status_and_fullname` | إصلاح خطأين حرجين مؤكدين من تدقيق العقود عبر الطبقات |
| 0118 | `restore_release_governance_overview` | استعادة عقد حوكمة الإصدار بعد 0117 |
| 0119 | `bridge_placeholder` | جسر ترقيم (no-op) لسد فجوة التسلسل |
| 0120 | `security_hardening_comprehensive` | تقوية أمنية شاملة + استعادة حارس الانتقال |
| 0121 | `seed_org_structure_roles_departments` | بذر الهيكل التنظيمي والأدوار والإدارات الفعلية للجمعية |
| 0122 | `bridge_placeholder` | جسر ترقيم (no-op) لسد فجوة التسلسل |
| 0123 | `mobile_org_chart_rpc` | دالة الهيكل التنظيمي للموبايل `get_mobile_org_chart` |
| 0124 | `remove_video_from_live_location` | إزالة الفيديو من نظام الموقع الحي (V12) |
| 0125 | `employee_lifecycle_hardening` | تقوية دورة حياة الموظف وسد ثغرات الفحص |
| 0126 | `fix_verification_status_and_fullname` | إصلاح مشكلتين حرجتين من فحص تطابق العقود |
| 0127 | `monthly_attendance_statement` | كشف الحضور والانصراف الشهري لكل موظف (V12 §18) |
| 0128 | `repair_request_live_location_staging` | إصلاح `request_live_location` على staging وعقد V17 النهائي |
| 0129 | `employee_edit_and_list_enrichment` | تعديل بيانات الموظف + إثراء قائمة الموظفين |
| 0130 | `v17_kpi_flow_reorder` | عكس مسار KPI: إزالة manager_final من المسار النشط (V17 §10) |
| 0131 | `v17_dispute_admin_actions` | إجراءات إدارة النزاعات (V17) |
| 0132 | `v17_official_holidays` | الإجازات الرسمية ونطاق الاستثناءات (V17 §1.7) |
| 0133 | `v17_post_publishing` | نشر المنشورات الرسمية (V17 §18) |
| 0134 | `v17_request_types` | أنواع الطلبات (V17) |
| 0135 | `v17_word_count_checks` | قيود طول النص (Word Count Checks) (V17 §1.3) |
| 0136 | `fix_resolve_request_approver` | إصلاح دالة `resolve_request_approver` |
| 0137 | `v17_attendance_executive_exemption` | استكمال استثناء المدير التنفيذي من الحضور الإلزامي (V17 §7) |
| 0138 | `v17_permission_matrix_fixes` | إصلاح مصفوفة الصلاحيات بناءً على تدقيق Wave 3 (V17 §2.2.1) |
| 0139 | `v17_request_return_status` | إضافة حالة "مُعاد" (returned) لدورة عمل الطلبات (V17 §4.3) |
| 0140 | `v17_attendance_history_days` | إضافة معامل `p_days` إلى `get_my_attendance_history` (V17 §4.2) |
| 0141 | `v17_dispute_admin_action_catalog` | كشف حقول الإجراءات الإدارية في كتالوج النزاعات (V17 §14) |
| 0142 | `v17_announcement_images` | تخزين صور الإعلانات وتحديث الدوال لدعم الصور |
| 0143 | `fix_attendance_all_non_executive` | تصحيح سياسة البصمة لجميع المستخدمين ما عدا المدير التنفيذي |
| 0144 | `v17_access_context_photo_url` | إضافة photoUrl إلى `get_my_access_context` |
| 0145 | `v18_device_approval_workflow` | سير عمل اعتماد الأجهزة (V18 §5) |
| 0146 | `v17_kpi_stage_notify` | إشعارات انتقال مراحل تقييم الأداء (V17 §9.2.2) |
| 0147 | `v17_request_decision_notify` | إشعار الموظف عند اتخاذ قرار على طلبه (V17 §9.2.3) |
| 0148 | `v17_announcement_publish_notify` | إشعار جماعي عند نشر إعلان رسمي (V17 §9.2.5) |
| 0149 | `fix_org_chart_recursive_cte` | إصلاح `get_mobile_org_chart` (CTE عودي + أعمدة صحيحة) |
| 0150 | `fix_request_live_location_admin_access` | السماح لأدوار full-access بـ `request_live_location` |
| 0151 | `admin_sees_hr_workspace` | الأدمن الرئيسي يرى لوحة HR أيضًا |
| 0152 | `v18_committee_dispute_mobile_portal` | بوابة لجنة النزاعات للموبايل (V18) |
| 0153 | `fix_kpi_notify_fullname` | إصلاح `full_name` → `full_name_ar` في دوال إشعارات KPI |
| 0154 | `add_departments_slug_and_fix_seed_timing` | عمود slug للإدارات + إصلاح توقيت بذر الصلاحيات |
| 0155 | `fix_attendance_missing_check_null` | إصلاح NULL في missingCheckIn/missingCheckOut بكشف الحضور |
| 0156 | `multi_department_support` | دعم تعدد الإدارات لكل موظف (many-to-many + RLS + RPCs) |
| 0157 | `fix_seed_timing_permission_grants` | إصلاح توقيت بذر الصلاحيات (إنشاء + منح المفقودة) |
| 0158 | `grant_employee_devices_select` | منح SELECT على employee_devices إلى authenticated |
| 0159 | `fix_is_official_holiday` | إصلاح `is_official_holiday` عبر departments للحصول على legal_entity_id |
| 0160 | `employee_kpi_self_assess` | منح صلاحية التقييم الذاتي لدور الموظف |
| 0161 | `add_return_to_request_actions` | إضافة 'return' إلى قيد `request_actions.action` |
| 0162 | `add_is_capability_to_roles` | عمود is_capability في جدول الأدوار (قدرة إضافية) |
| 0163 | `add_kpi_notification_category` | إضافة 'kpi' إلى قيد `notifications.category` |
| 0164 | `v23_notification_catalog_completion` | استكمال كتالوج الإشعارات (V23 §8) |
| 0165 | `v23_executive_posts_reports` | أنواع منشورات موسعة + معلومات المؤلف + نظرة الحضور + تقارير HR |
| 0166 | `v23_kpi_parallel_workflow` | مسار KPI متوازٍ: مراجعة HR + المدير معًا (V23 §06) |
| 0167 | `v23_security_search_path_hardening` | تقوية `search_path` للدوال المساعدة (V23) |
| 0168 | `v23_dispute_committee_alignment` | مواءمة لجنة النزاعات مع V23 |
| 0169 | `v23_attendance_geofence_hardening` | تقوية السياج الجغرافي للحضور (V23 §4) |
| 0170 | `v23_roles_permissions_hardening` | تقوية الأدوار والصلاحيات + `current_is_hr_only` + `rpc_assign_role` |
| 0171 | `v23_device_biometric_recovery` | استعادة الجهاز البيومتري + الإلغاء الإداري (V23) |
| 0172 | `fix_role_notify_column_name` | إصلاح ثلاثة أخطاء في مشغلات الإشعارات (من 0160) |
| 0173 | `v23_leaves_escalation_split` | فصل مهلة التصعيد: تنفيذي 6 ساعات / البقية 12 ساعة |
| 0174 | `v23_scoped_permission_foundation` | أساس `has_scoped_permission` لترحيل RLS التدريجي (V23 §3) |
| 0175 | `v23_multi_assignment_p0` | توسيع employee_departments لدعم التعيينات المتعددة (V23 §6) |
| 0176 | `v23_rate_limiting_expansion` | توسيع تحديد المعدل (Rate Limiting) لـ 7 مجالات (V23 §1E) |
| 0177 | `v23_announcements_storage_notifications` | سد فجوات Task-10 (إعلانات/تخزين/إشعارات) |
| 0178 | `v23_attendance_statement_fields` | توسيع كشف الحضور الشهري (V23 §14) |
| 0179 | `fix_approver_id_and_request_action_return` | إصلاح ثلاث مشاكل كانت تمنع نجاح pgTAP |
| 0180 | `fix_notification_category_and_dispute_catalog_args` | إصلاح مشكلتين (فئة الإشعار + وسيطات كتالوج النزاعات) |
| 0181 | `fix_main_admin_attendance_policy` | إصلاح سياسة الحضور لأدوار الإدارة الرئيسية |
| 0182 | `seed_employment_types` | بذر أنواع التوظيف الأساسية |
| 0183 | `repair_v23_agent_functions` | إصلاح دوال V23 المطبقة بكود خاطئ (0171–0173) |
| 0184 | `v23_hr_reports_summary` | RPC `get_hr_reports_summary` |
| 0185 | `fix_official_feed_publish` | إصلاح نشر المنشور الرسمي |
| 0186 | `friday_only_weekly_rest` | الراحة الأسبوعية الجمعة فقط (السبت يوم عمل عادي) |
| 0187 | `activate_linked_employees` | تفعيل الموظفين ذوي الحسابات المربوطة |
| 0188 | `arabic_permission_names` | أسماء الصلاحيات بالعربية + إصلاح عرض أدوار full-access |
| 0189 | `fix_access_catalog_full_access_display` | إصلاح عرض الصلاحيات الكاملة في كتالوج الصلاحيات |
| 0190 | `fix_admin_permission_display` | إصلاح عرض الصلاحيات الكاملة |
| 0191 | `update_employee_text_fields` | `update_employee_admin`: دعم إدخال المسمى الوظيفي والدرجة كنص حر |
| 0192 | `fix_finalize_attendance_device_bypass` | إصلاح تجاوز اعتماد الجهاز في `finalize_verified_attendance` |
| 0193 | `create_auth_invite_log` | جدول `auth_invite_log` |
| 0194 | `placeholder` | جسر ترقيم (محفوظ تاريخيًا لسلامة التسلسل) |
| 0195 | `fix_announcement_post_type_insert` | إصلاح `publish_official_announcement` (post_type مفقود من INSERT) |
| 0196 | `fix_secretary_attendance_policy` | السكرتير التنفيذي يحتاج بصمة (إزالة استثناء main_admin) |
| 0197 | `backfill_kpi_evaluations_for_activated_employees` | تعبئة تقييمات KPI للموظفين المفعّلين حديثًا (0187) |
| 0198 | `dispute_member_recommendations_mobile` | السماح لأعضاء اللجنة بإبداء رأيهم من الموبايل |
| 0199 | `fix_attendance_today_overview` | إصلاح `get_attendance_today_overview` (أعمدة غير موجودة) |
| 0200 | `fix_ilike_injection_and_storage_policy` | إصلاح حقن ILIKE wildcard + تشديد سياسة التخزين |
| 0201 | `attendance_geofence_default` | سياج جغرافي افتراضي + fallback في دوال الحضور |
| 0202 | `fix_dispute_lifecycle_gaps` | سد ثغرات دورة حياة النزاعات |
| 0203 | `add_missing_fk_indexes` | فهارس FK المفقودة لتسريع JOIN/DELETE |
| 0204 | `fix_kpi_inbox_scope` | إصلاح `get_kpi_inbox`: المدير يرى فريقه فقط |
| 0205 | `fix_historical_attendance_records` | إصلاح سجلات الحضور التاريخية |
| 0206 | `kpi_admin_fullaccess_notifications` | إصلاح صفحة دورات KPI وإشعاراتها |
| 0207 | `revoke_anon_execute_functions` | سحب EXECUTE من anon على كل الدوال التطبيقية |
| 0208 | `fix_attendance_known_errors_and_device_status` | إصلاح أخطاء الحضور + رؤية حالة الجهاز |
| 0209 | `security_hardening_revoke_public_execute` | تعزيز أمني (الجولة الثانية) |
| 0210 | `attendance_allow_device_lock_fallback` | السماح بقفل الجهاز (PIN/pattern) كبديل للبصمة |
| 0211 | `revoke_anon_dml_fix_buckets_dedup_rls` | تعزيز أمني (الجولة الثالثة) |
| 0212 | `fix_attendance_state_biometric_check` | مزامنة `get_my_attendance_state` مع 0210 |
| 0213 | `centralize_data_access_rpcs` | مركزة CRUD المباشر في RPCs خادمية |
| 0214 | `fix_kpi_admin_fullaccess_authz` | إصلاح صلاحيات full-access للوظائف الإدارية لدورات KPI |
| 0215 | `fix_finalize_verified_attendance_regressions` | إصلاح 5 انتكاسات في `finalize_verified_attendance` (0208) |
| 0216 | `rls_financial_tables` | تشديد RLS على الجداول المالية/التعويضات |
| 0217 | `rls_dispute_tables` | تشديد RLS على جداول النزاعات والشكاوى |
| 0218 | `trigram_indexes_arabic_search` | فهارس Trigram للبحث العربي + فهارس أداء |
| 0219 | `placeholder_sequence_fix` | جسر ترقيم (سد فجوة) |
| 0220 | `materialized_views_dashboard` | عروض مادية (Materialized Views) للوحة المعلومات |
| 0221 | `credential_vault_encryption` | تشفير خزنة الاعتمادات عبر دوال SECURITY DEFINER |
| 0222 | `session_limits_rate_cleanup` | مهام صيانة مجدولة لسجل Rate Limit ومراقبة الخصوصية |
| 0223 | `rls_remaining_unprotected` | تفعيل FORCE RLS على جميع الجداول + حذف سياسات DML الميتة |
| 0224 | `batch_operations_rpcs` | عمليات دفعية: قرار جماعي على الطلبات + إشعارات جماعية |
| 0225 | `admin_panel_rpcs` | RPCs لوحة الأدمن بدل الاستعلامات المباشرة |
| 0226 | `fix_attendance_device_mismatch` | إصلاح تعارض جهاز البصمة |
| 0227 | `critical_rpc_authz_hardening` | تقوية تفويض الدوال الحرجة (P0 + P1) |
| 0228 | `security_appmetadata_mv_dispute_authz` | حماية بيانات auth + العروض المادية + صلاحيات النزاعات |
| 0229 | `fix_device_replacement_keep_old_active` | إبقاء الجهاز القديم فعّالاً حتى اعتماد الجديد (V24) |
| 0230 | `restore_server_only_privileges_and_finance_rls` | استعادة صلاحيات الخادم + سد فجوة قراءة التعويضات |
| 0231 | `bridge_placeholder` | جسر ترقيم (no-op) لسد فجوة |
| 0232 | `bridge_placeholder` | جسر ترقيم (no-op) لسد فجوة |
| 0233 | `critical_cron_consolidation` | جدولة موحدة idempotent للمهام الحرجة + فحص صحي + تنبيهات |
| 0234 | `revoke_remaining_internal_rpcs` | سد الثغرات الأمنية المتبقية (الجولة الخامسة) |
| 0235 | `validate_storage_paths_and_urls` | التحقق خادميًا من مسارات التخزين والروابط |
| 0236 | `finalize_attendance_selfie_path_scope` | تثبيت نطاق مسار selfie الحضور |
| 0237 | `fix_work_assignments_rls_recursion` | إصلاح التكرار اللانهائي (42P17) في سياسات التكليفات |
| 0238 | `batch_size_limits_dos_hardening` | حدود حجم الدفعات في دوال SECURITY DEFINER الحساسة |
| 0239 | `fix_finalize_selfie_nul_check` | إصلاح فحص NUL في مسار selfie عند الإنهاء |
| 0240 | `admin_reinstate_device` | إعادة تفعيل جهاز بواسطة المسؤول |
| 0241 | `device_reinstate_and_reregister_fix` | إصلاح إعادة التفعيل/إعادة التسجيل للأجهزة |
| 0242 | `repair_runtime_rpcs_and_cron_health` | إصلاح RPCs التشغيلية + فحص صحة cron |
| 0243 | `validate_announcement_and_kpi_evidence_urls` | التحقق من روابط الإعلانات وأدلة KPI |
| 0244 | `production_observability_cron_health` | مراقبة إنتاجية لصحة مهام cron |
| 0245 | `secdef_cross_employee_authz` | سد تسريب بيانات عبر دوال SECURITY DEFINER بلا حصر للمستدعي |
| 0246 | `fix_auth_admin_execute_handle_new_user` | إصلاح منح EXECUTE لدالة auth admin handle_new_user |
| 0247 | `harden_cron_http_header_json` | تقوية بناء ترويسة x-cron-secret لمهام HTTP |
| 0248 | `admin_reinstate_device` | استعادة دالة إعادة تفعيل الجهاز الإدارية |
| 0249 | `harden_url_path_validators` | تطبيع المسافات ورفض الهروب المختلط (مسار/رابط) |
| 0250 | `harden_external_link_validator` | مواءمة التحقق من الروابط الخارجية مع 0249 |
| 0251 | `fix_monthly_attendance_as_of_date` | جعل كشف الحضور الشهري تقريرًا "حتى الآن" |
| 0252 | `attendance_day_detail_explainability` | إثراء كل يوم في الكشف بحقول "details" توضيحية |
| 0253 | `leave_workflow_and_device_reinstate` | سير عمل إجازة بخطوتين (مدير → HR) + تجاوز المدير بعد 12 ساعة + إعادة تفعيل الأجهزة |
| 0254 | `restrict_employee_departments_read` | تشديد سياسة قراءة employee_departments (RLS) |
| 0255 | `payroll_formula_templates_schema` | مخطط قوالب صيغ الرواتب (بدون eval خادمي) |
| 0256 | `admin_panel_rpc_capability_guards` | حراسة قدرات RPC لوحة الأدمن (P0) |
| 0257 | `attendance_rate_exclude_open_shift` | استبعاد الوردية المفتوحة من نسبة الحضور/الالتزام |
| 0258 | `payroll_dsl_security_foundation` | أساس آمن لقوالب صيغ الرواتب |
| 0259 | `payroll_dsl_interpreter` | مفسّر صيغ الرواتب (JSON خالص) |
| 0260 | `rls_gap_closure` | إغلاق ثغرات RLS المتبقية في الجداول العامة |
| 0261 | `fix_ops_center_guard` | إصلاح حارس `get_operations_center_data` (P0، نتيجة 0256) |
| 0262 | `fix_payroll_dsl_fail_open` | إصلاح Fail-Open في `payroll_validate_dsl_spec` (0259) |
| 0263 | `audit_fix_rpc_grants_self_guard` | منح EXECUTE للمصادقين على دوال لوحة الإدارة، حماية `is_deleted`/`national_id_enc` من التعديل الذاتي، تماثل `rpc_revoke_role`، وفرض `tasks.write` |
| 0264 | `cron_http_from_system_settings` | قراءة مهام cron HTTP من `system_settings` بدل custom GUC (غير مسموح على Supabase المُدارة) |
| 0265 | `restore_live_location_video_verification` | استعادة عقد الموقع الحي + التحقق بالفيديو (storage bucket + رفع الملفات + تدقيق الإكمال) |
| 0266 | `monthly_attendance_full_month_rates_and_day_overrides` | نسب الحضور والساعات الشهرية الكاملة + تعديلات يومية إدارية مع حماية يوم الجمعة |

## القواعد الثابتة

- كل قرار حساس يُنفذ خادميًا عبر RPC أو Edge Function، وليس من العميل مباشرة.
- RLS مفعّل على الجداول العامة، والنطاقات تُطبق في الخادم لا كفلتر واجهة.
- كل RPC حساس يستخدم `SECURITY DEFINER` مع `search_path` ثابت، وفحص صلاحية داخلي، و`revoke from public` ثم Grant محدد.
- لا تُخزن كلمات مرور أو أسرار داخل الجداول القابلة للقراءة من التطبيق.
- Timestamps تُخزن UTC ويُستخدم `Africa/Cairo` للحسابات التشغيلية.
- الجداول التاريخية لا تُحذف ماديًا؛ تستخدم الحالة/الأرشفة والإجراءات التعويضية.
- الإدارات والمناصب وطلبات التوظيف ورحلات Onboarding ومهامها لا تملك سياسات كتابة مباشرة بعد 0025.

## التشغيل والتحقق

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

يجب تشغيل Reset والاختبارات مرتين على Local، ثم مرة على Staging، وحفظ Evidence قبل اعتبار قاعدة البيانات جاهزة للإنتاج.
