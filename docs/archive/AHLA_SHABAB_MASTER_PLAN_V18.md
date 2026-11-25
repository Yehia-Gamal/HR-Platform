# الخطة التنفيذية الشاملة V18 — نظام إدارة أحلى شباب

**التاريخ:** 2026-07-25
**الحالة:** سارية المفعول — تلغي V17 وجميع الإصدارات السابقة
**المرجع:** Supabase `ujzzvqsodyhnnnpkoaml` | Vercel `https://ahla-shabab-management-os.vercel.app`
**الفرع:** `codex/v17-master-plan` (يُدمج في `main` عند الاعتماد)

---

## 1. قاعدة منع الاجتهاد وصلاحية الوكيل

### 1.1 قاعدة منع الاجتهاد

> **لا يفترض الوكيل وجود جدول أو دالة أو عمود أو صلاحية أو دور غير مؤكد الوجود.**

| القاعدة | التطبيق |
|---|---|
| **ابدأ بـ discovery** | قبل أي تعديل، نفّذ `grep` / `\dt` / `\df` للتأكد من وجود الكيان المستهدف |
| **لا بيانات عشوائية** | لا `INSERT` بقيم مختلقة. كل بذرة تستند لبيانات حقيقية موثقة |
| **لا "تم" بدون اختبار** | كل تغيير يُتبع بـ `tsc --noEmit` + `vitest run` + `flutter analyze` + `supabase test db` حسب النطاق |
| **لا افتراض أسماء** | إن لم تجد الجدول بالاسم المتوقع، ابحث عن البديل قبل الإنشاء |
| **تحقق من التكرار** | قبل ترقيم أي migration جديدة: `ls supabase/migrations/ \| sort \| tail -3` ثم `cut -c1-4 \| sort \| uniq -d` |

### 1.2 صلاحية الوكيل

الوكيل يملك صلاحية **كاملة** داخل المستودع بالشروط التالية:

1. **git branch** — كل عمل جديد يبدأ من فرع مخصص، لا يُدفع مباشرة إلى `main`
2. **backup** — قبل أي تعديل جوهري على ملف موجود، يُقرأ الملف أولاً ويُوثق التغيير
3. **migrations جديدة فقط** — لا تعديل على migration منشورة (pushed to staging/prod). أنشئ migration تالية
4. **اختبار قبل الالتزام** — لا `git commit` بدون تمرير الفحوصات المطلوبة

---

## 2. القواعد الثابتة

### 2.1 أمان المستودع

| القاعدة | التفصيل |
|---|---|
| **لا أسرار في الملفات** | لا مفاتيح API، لا كلمات مرور، لا tokens في أي ملف مُتتبَّع. استخدم `inline shell env vars` أو Supabase Secrets |
| **لا PII** | لا تطبع أسماء موظفين حقيقية أو `user_id` فعلي في scripts أو logs أو تعليقات |
| **لا تعديل migration منشورة** | الـ migrations المنشورة على staging (حتى `0141`) لا تُعدَّل. أنشئ migration لاحقة |
| **تحقق من تكرار الأرقام** | هناك محادثات متوازية — خطر التكرار حقيقي. قبل كل migration جديدة: |

```bash
ls supabase/migrations/ | sort | tail -3          # آخر رقم فعلي
ls supabase/migrations/ | cut -c1-4 | sort | uniq -d   # كشف التكرارات
```

### 2.2 قواعد الكود

| المنصة | التقنيات | القواعد |
|---|---|---|
| **Web** | React 19 + Vite + Tailwind + TanStack Query + react-router-dom + Zod + react-hook-form | لا `console.log` في الإنتاج |
| **Mobile** | Flutter 3 + Riverpod + Dart | `debugPrint` محمي بـ `kDebugMode` فقط. الإعدادات عبر `--dart-define` |
| **Shared** | `packages/shared-contracts/` — Zod schemas مشتركة بين الويب و Edge Functions | 18 عقد (access, disputes, kpi, holidays, requests, ...) |
| **اللغة** | عربي RTL في كل الواجهات. النصوص بالعربية. التعليقات بالعربية مقبولة | |
| **الأسلوب** | طابق أسلوب الكود المحيط: كثافة التعليقات، التسمية، الأنماط | |

### 2.3 قواعد الأمان (RLS والصلاحيات)

| القاعدة | التفصيل |
|---|---|
| **`USING(true)` مقيّد** | مسموح **فقط** على جداول القراءة المرجعية: `roles`, `permissions`, `kpi_criteria`, `departments`, `job_titles`, `branches` |
| **`current_is_full_access()`** | تحمي كل العمليات الحساسة (حذف/أرشفة موظف، تعديل أدوار نظامية، break-glass) |
| **`provision_employee_record`** | يتجاوز `rpc_assign_role` — الأدوار ذات الصلاحيات الكاملة لا تُمنح عند الإنشاء |
| **الحضور** | فحص mock location + geofence + impossible travel يُطبَّق في **كلا** المسارين (WebAuthn + Local Biometric) |
| **SECURITY DEFINER** | كل دالة `SECURITY DEFINER` تحمل `SET search_path = public, pg_temp` |

### 2.4 قواعد الاختبار

| الطبقة | الأداة | الحالة الفعلية |
|---|---|---|
| **Web** | `vitest run` (apps/admin_web) | 32 اختبار / 8 ملفات |
| **Contracts** | `vitest run` (packages/shared-contracts) | 54 اختبار / 18 ملف |
| **Flutter** | `flutter test` | 29 اختبار |
| **pgTAP** | `supabase test db` | **60 ملف / 810 assertion** |

**قاعدة ملزمة:** كل migration جديدة يُرافقها ملف pgTAP اختبار أو توسيع ملف موجود. لا يُدمج كود بدون `npm run check:all`.

### 2.5 قواعد النشر

| المكوّن | الأمر | الملاحظات |
|---|---|---|
| **Web** | `npx vercel --prod` | يتطلب `VERCEL_TOKEN`. مشروع: `prj_ZLbewe64wIFujXhWruZQNdLgmGep` |
| **Migrations** | `npx supabase db push` | يدفع كل migrations الجديدة بالترتيب |
| **Edge Functions** | `npx supabase functions deploy` | ينشر جميع الـ 13 دالة (بما فيها `_shared`) |
| **Flutter** | `flutter build apk --release` | Keystore في `android/keystore.properties` (gitignored). كلمة المرور: مخزنة محلياً |
| **فحص شامل** | `npm run check:all` | typecheck + test + build + dart-source + secrets |

---

## 3. خريطة واقع النظام — الجرد المفصّل

### 3.1 الـ Migrations (141 migration: 0001–0141)

#### المجموعة التأسيسية (0001–0011): البنية الأساسية

| # | الملف | الوصف | أهم الجداول/الكيانات |
|---|---|---|---|
| 0001 | `extensions_and_conventions` | الامتدادات والاصطلاحات العامة | pgcrypto, uuid-ossp, pgtap |
| 0002 | `permissions_roles_functions` | الصلاحيات والأدوار ودوال التفويض | `permissions`, `roles`, `role_permissions`, `user_roles` |
| 0003 | `organization` | الهيكل التنظيمي | `legal_entities`, `branches`, `work_sites`, `cost_centers`, `job_titles`, `job_grades`, `departments`, `teams`, `positions`, `employment_types`, `geofences`, `shifts`, `shift_patterns`, `public_holidays`, `working_calendars` |
| 0004 | `employees` | الموظفون والملفات الشخصية | `employees`, `profiles`, `manager_relations`, `employee_assignments`, `employee_documents`, `employee_skills`, `employee_certifications` |
| 0005 | `attendance` | الحضور والورديات والهوية | `shift_assignments`, `passkey_credentials`, `webauthn_challenges`, `attendance_events`, `attendance_daily`, `attendance_identity_checks`, `attendance_risk_events`, `attendance_exceptions`, `attendance_permits` |
| 0006 | `requests_workflow` | الطلبات ومحرك الموافقات | `leave_types`, `workflow_definitions`, `workflow_steps`, `requests`, `leave_requests`, `missions`, `convoy_requests`, `request_steps`, `request_actions`, `workflow_instances` |
| 0007 | `kpi_performance` | مؤشرات الأداء والأهداف | `kpi_cycles`, `kpi_templates`, `kpi_criteria`, `kpi_evaluations`, `kpi_scores`, `monthly_evaluations`, `goal_objectives`, `goal_key_results`, `goal_checkins`, `feedback_rounds`, `feedback_raters`, `competencies`, `competency_levels`, `role_competency_profiles`, `employee_competency_assessments`, `calibration_sessions`, `review_cycle_templates`, `review_cycle_instances`, `improvement_plans`, `one_on_ones` |
| 0008 | `communications_disputes` | القرارات والتواصل والنزاعات | `administrative_decisions`, `decision_recipients`, `decision_reads`, `announcements`, `announcement_acknowledgements`, `surveys`, `survey_questions`, `survey_responses`, `suggestions`, `recognitions`, `notifications`, `push_subscriptions`, `notification_delivery_log`, `dispute_cases`, `dispute_sessions`, `dispute_evidence`, `committee_members` |
| 0009 | `documents_tasks_policies` | المستندات والمهام والسياسات | `documents`, `attachments`, `tasks`, `task_templates`, `policies`, `policy_acknowledgements`, `daily_reports`, `asset_inventory`, `asset_assignments`, `projects`, `project_members`, `meetings`, `meeting_minutes`, `decision_register`, `risks`, `incidents`, `knowledge_articles`, `hr_tickets`, `ticket_messages` |
| 0010 | `recruitment_onboarding` | التوظيف والإلحاق | `job_requisitions`, `job_requisition_approvals`, `job_postings`, `candidates`, `candidate_documents`, `applications`, `pipeline_stages`, `application_stage_history`, `application_current_state`, `interviews`, `interview_panel`, `interview_scorecards`, `scorecard_criteria_scores`, `job_offers`, `offer_approvals`, `employment_contracts`, `contract_signatures`, `onboarding_journeys`, `onboarding_tasks`, `provisioning_requests` |
| 0011 | `audit_security_system` | التدقيق والأمان والنظام | `audit_logs`, `audit_events`, `security_events`, `login_identifier_attempts`, `credential_vault`, `password_reset_requests`, `settings`, `system_settings`, `system_backups`, `app_error_events`, `feature_flags`, `integrations`, `integration_logs`, `live_location_requests`, `live_location_videos_meta`, `employee_locations`, `location_requests` |

#### مجموعة التقوية والعقود (0012–0025): تصليب الأساس

| # | الملف | الوصف |
|---|---|---|
| 0012 | `core_p0_hardening` | تقوية أمنية P0 للبنية الأساسية |
| 0013 | `foundation_access_and_provisioning` | سياق الوصول التأسيسي + إنشاء الموظفين بمعاملة واحدة |
| 0014 | `employee_access_canonicalization` | توحيد namespace صلاحيات الموظفين + منع الحذف الفيزيائي |
| 0015 | `operational_workspaces` | مساحات العمل التشغيلية وعقود RPC |
| 0016 | `management_overviews_notifications` | نماذج قراءة الإدارة والإشعارات |
| 0017 | `live_location_mobile_flow` | تدفق الموقع المباشر المدقَّق |
| 0018 | `employee_request_self_service` | الخدمة الذاتية لطلبات الموظف |
| 0019 | `kpi_forms_and_attendance_state` | نماذج KPI للموبايل + حالة الحضور |
| 0020 | `passkey_lifecycle_and_mobile_actions` | دورة حياة Passkey + توجيه الإجراءات |
| 0021 | `mobile_details_and_action_routing` | نماذج التفاصيل + توجيه الإجراءات |
| 0022 | `mobile_daily_workspaces` | مساحات العمل اليومية (ملف شخصي، مهام، فريق، إشعارات) |
| 0023 | `passkey_devices_and_attendance_history` | الخدمة الذاتية للأجهزة + سجل الحضور |
| 0024 | `mobile_notifications_and_action_links` | توسيع الإشعارات لروابط الموبايل العميقة |
| 0025 | `admin_structure_access_onboarding` | هيكل الإدارة والوصول والإلحاق |

#### مجموعة الوحدات المتقدمة (0026–0039): الأنظمة الفرعية

| # | الملف | الوصف | جداول جديدة |
|---|---|---|---|
| 0026 | `leave_ledger_and_request_sla` | دفتر الإجازات + SLA الطلبات | `leave_balance_accounts`, `leave_ledger_entries` |
| 0027 | `decision_lifecycle_polls_and_execution` | دورة حياة القرارات والتصويت | `decision_versions`, `decision_actions`, `decision_execution_items`, `decision_polls`, `decision_poll_options`, `decision_poll_eligibility`, `decision_poll_votes` |
| 0028 | `rosters_attendance_periods_and_corrections` | الجداول والفترات والتصحيحات | `attendance_periods`, `work_rosters`, `roster_days`, `attendance_corrections`, `overtime_records` |
| 0029 | `kpi_cycles_evidence_appeals` | إدارة دورات KPI والأدلة | `kpi_evidence`, `kpi_stage_history`, `kpi_appeals` |
| 0030 | `disputes_committee_quorum_decisions` | لجنة المنازعات والنصاب | `dispute_conflict_declarations`, `dispute_session_attendance`, `dispute_decisions`, `dispute_appeals`, `dispute_actions` |
| 0031 | `documents_assets_and_offboarding` | المستندات والعهد وإنهاء الخدمة | `document_access_logs`, `offboarding_cases`, `offboarding_clearance_items`, `knowledge_transfer_items`, `offboarding_actions` |
| 0032 | `mobile_self_service_roster_hardening` | تقوية الخدمة الذاتية والجداول | (تعديلات RPC فقط) |
| 0033 | `talent_learning_documents_reports` | التعلم والمستندات والتقارير | `learning_courses`, `learning_course_sessions`, `learning_enrollments`, `document_templates`, `generated_documents`, `document_signature_requests`, `scheduled_reports`, `report_runs`, `notification_jobs` |
| 0034 | `private_storage_buckets_and_retention` | تخزين خاص وسياسات وصول | (storage policies) |
| 0035 | `enterprise_strategy_projects_governance` | الاستراتيجية والمشاريع والحوكمة | `strategic_objectives`, `objective_key_results`, `enterprise_projects`, `project_tasks`, `enterprise_risks`, `enterprise_incidents`, `service_catalog_items`, `service_requests`, `service_request_messages`, `enterprise_meetings`, `meeting_attendees`, `meeting_agenda_items`, `meeting_decisions`, `quality_cases`, `corrective_actions`, `internal_audits`, `audit_findings`, `automation_rules`, `automation_runs`, `data_assets`, `data_quality_rules`, `ai_use_cases` |
| 0036 | `workforce_compensation_payroll` | القوى العاملة والرواتب | `workforce_plans`, `capacity_snapshots`, `salary_structures`, `salary_components`, `employee_compensation`, `payroll_runs`, `payslips`, `payslip_lines`, `employee_loans`, `loan_installments`, `engagement_campaigns`, `wellbeing_requests` |
| 0037 | `retention_privacy_release_hardening` | الاحتفاظ والخصوصية | `live_location_video_access_logs` |
| 0038 | `release_access_privacy_integration` | الإصدارات والأجهزة والخصوصية | `app_release_policies`, `managed_devices`, `access_review_campaigns`, `access_review_items`, `break_glass_requests`, `privacy_requests`, `integration_outbox` |
| 0039 | `identifier_login_security` | أمان تسجيل الدخول بالمعرّف | `login_auth_attempts` |

#### مجموعة الإصدار 0.10 (0040–0055): التثبيت والنشر

| # | الملف | الوصف |
|---|---|---|
| 0040 | `release_0_10_ui_and_identifier_login` | بيانات إصدار 0.10 المرحلي |
| 0041 | `mobile_manager_and_executive_workspaces` | مساحات عمل المدير والتنفيذي |
| 0042 | `mobile_executive_brief_and_people` | الموجز التنفيذي اليومي |
| 0043 | `grant_service_role_sla_processor` | منح service_role صلاحية معالج SLA |
| 0044 | `recruitment_interviews_offers_hire` | تكامل التوظيف (مقابلات، عروض) |
| 0045 | `grant_authenticated_table_privileges` | منح صلاحيات الجداول للمصادقين |
| 0046 | `attendance_mock_location_and_travel_guard` | حماية من المواقع الوهمية + impossible travel |
| 0047 | `scheduling_leave_accrual_and_cron` | جدولة الاستحقاق + cron jobs |
| 0048 | `pgcrypto_search_path_for_digest` | إصلاح مسار pgcrypto |
| 0049 | `schedule_edge_functions_via_pg_net` | جدولة Edge Functions عبر pg_net |
| 0050 | `audit_remediation_p0_p1` | معالجة التدقيق P0/P1 |
| 0051 | `schedule_remaining_edge_functions` | جدولة بقية Edge Functions |
| 0052 | `audit_remediation_p2_p3` | معالجة التدقيق P2/P3 |
| 0053 | `full_access_sees_all_workspaces` | full-access يرى كل المساحات |
| 0054 | `observability_and_alerting` | المراقبة والتنبيهات — `system_alerts` |
| 0055 | `audit_remediation_p3_ledger` | معالجة تدقيق P3 (دفتر) |

#### مجموعة الأنظمة الرسمية (0056–0066): KPI والإجازات والتكليفات

| # | الملف | الوصف | جداول جديدة |
|---|---|---|---|
| 0056 | `employee_onboarding_simplification` | تبسيط الإلحاق + أدوار `direct-manager` و`operations-officer` | (أدوار فقط) |
| 0057 | `official_shifts_and_punch_reminders` | الورديات الرسمية وتذكيرات التسجيل | (RPCs) |
| 0058 | `official_kpi_governance` | حوكمة KPI الشهرية الرسمية | `kpi_policy_versions`, `kpi_goals`, `kpi_review_sessions`, `kpi_compliance_records`, `kpi_attendance_snapshots`, `kpi_notification_receipts` |
| 0059 | `dispute_committee_end_to_end` | لجنة حل المشكلات من البداية للنهاية + أدوار `operations-manager-1/2` و`committee-secretary` | `dispute_parties`, `dispute_statements`, `dispute_session_participants`, `dispute_settlements`, `dispute_decision_receipts` |
| 0060 | `leave_types_and_entitlement` | أنواع الإجازات والاستحقاقات | (تعديلات) |
| 0061 | `leave_submission_and_casual` | تقديم الإجازات والعارضة | (RPCs) |
| 0062 | `request_escalation_on_behalf` | تصعيد الطلبات نيابةً عن | (RPCs) |
| 0063 | `work_assignments` | التكليفات | `work_assignments`, `work_assignment_participants` |
| 0064 | `dispute_committee_fixes` | إصلاحات لجنة المنازعات | (تعديلات) |
| 0065 | `assignments_attendance_link` | ربط التكليفات بالحضور | (تعديلات) |
| 0066 | `assignments_kpi_link` | ربط التكليفات بالأداء | `kpi_assignment_contributions` |

#### مجموعة الموقع المباشر (0067–0088): التتبع التنفيذي

| # | الملف | الوصف | جداول جديدة |
|---|---|---|---|
| 0067 | `live_location_executive_flow` | تدفق الموقع المباشر التنفيذي | (RPCs) |
| 0068 | `location_request_ux_fixes` | إصلاحات UX طلبات الموقع | |
| 0069 | `executive_attendance_today` | لوحة حضور اليوم التنفيذية | |
| 0070 | `cancel_location_request` | إلغاء طلب الموقع | |
| 0071 | `auto_cancel_on_new_request` | إلغاء تلقائي عند طلب جديد | |
| 0072 | `fix_request_live_location_audit_call` | إصلاح استدعاء التدقيق | |
| 0073 | `location_security_hardening` | تقوية أمان الموقع | `employee_devices`, `location_request_responses` |
| 0074–0078 | (إصلاحات متعددة) | إصلاح audit/attendance/overloads | |
| 0079 | `auto_provision_employees` | إنشاء تلقائي للموظفين عند التسجيل | |
| 0080–0087 | (إصلاحات وتقوية) | إصلاحات الحضور + الأجهزة + الأرشفة + الحذف | |
| 0088 | `canonical_location_responses_and_map_snapshots` | استجابات الموقع + لقطات الخريطة | `live_location_map_access_logs` |

#### مجموعة الحضور الذري والأمان (0089–0100)

| # | الملف | الوصف | جداول جديدة |
|---|---|---|---|
| 0089 | `atomic_idempotent_attendance_finalize` | إنهاء الحضور الذري | `attendance_punch_attempts` |
| 0090 | `secure_employee_archive_and_delete_guard` | أرشفة آمنة + حماية الحذف | |
| 0091–0093 | (إصلاحات) | إصلاح أرشفة/audit/أجهزة | |
| 0094 | `punch_attendance_local_biometric` | تسجيل الحضور بالبصمة المحلية | |
| 0095 | `security_hardening_audit_fixes` | تقوية أمنية من تدقيق APK | |
| 0096 | `release_0_11_1_deep_audit_remediation` | معالجة التدقيق العميق 0.11.1 | |
| 0097 | `activate_employee_after_first_login` | تفعيل الموظف بعد أول تسجيل دخول | |
| 0098–0100 | (إصلاحات Signed URL) | روابط موقّعة للتقارير + دعم offline | |

#### مجموعة V10 (0101–0118): إعادة هيكلة شاملة

| # | الملف | الوصف |
|---|---|---|
| 0101 | `mobile_rpc_scoping_fixes` | إصلاح نطاق RPCs الموبايل |
| 0102 | `fix_employee_home_rpc` | إصلاح الصفحة الرئيسية للموظف |
| 0103 | `reschedule_edge_jobs` | إعادة جدولة Edge Jobs |
| 0104 | `v10_identity_workspace_local_biometric` | V10: الهوية + مساحات العمل + البصمة المحلية |
| 0105 | `fix_pgcrypto_function_search_paths` | إصلاح مسارات pgcrypto |
| 0106 | `v10_runtime_contract_repairs` | إصلاحات عقود V10 |
| 0107 | `standardize_live_location_request_audit` | توحيد تدقيق طلبات الموقع |
| 0108 | `finish_runtime_lint_repairs` | إنهاء إصلاحات plpgsql_check |
| 0109 | `v10_kpi_workflow` | سير عمل KPI الجديد (ذاتي → مدير → HR → مدير نهائي) |
| 0110 | `v10_executive_kpi_report_access` | وصول التنفيذي لتقارير KPI (قراءة فقط) |
| 0111 | `v10_dashboards_notifications_daily_report` | لوحات + إشعارات + التقرير اليومي |
| 0112 | `v10_request_acceptance_repairs` | إصلاحات قبول الطلبات |
| 0113 | `v10_request_attachment_catalog_access` | وصول المراجعين للمرفقات |
| 0114 | `unify_employee_avatar_storage` | توحيد تخزين صور الموظفين |
| 0115 | `fix_kpi_validation_array_initialization` | إصلاح تهيئة مصفوفة KPI |
| 0116 | `restore_fcm_push_delivery` | استعادة خط أنابيب FCM |
| 0117 | `fix_verification_status_and_fullname` | إصلاح حالة التحقق والاسم الكامل |
| 0118 | `restore_release_governance_overview` | استعادة عقد حوكمة الإصدار |

#### مجموعة البنية التنظيمية (0119–0129)

| # | الملف | الوصف |
|---|---|---|
| 0119 | `bridge_placeholder` | جسر ترقيم (no-op) |
| 0120 | `security_hardening_comprehensive` | تقوية أمنية شاملة (REVOKE 8 دوال + impossible travel + rate limit) |
| 0121 | `seed_org_structure_roles_departments` | بذر الهيكل التنظيمي: 22 إدارة + 20 مسمى + أدوار executive/executive-secretary/hr-manager |
| 0122 | `bridge_placeholder` | جسر ترقيم (no-op) |
| 0123 | `mobile_org_chart_rpc` | RPC الهيكل التنظيمي للموبايل |
| 0124 | `remove_video_from_live_location` | إزالة الفيديو من الموقع المباشر نهائياً |
| 0125 | `employee_lifecycle_hardening` | تقوية دورة حياة الموظف |
| 0126 | `fix_verification_status_and_fullname` | إصلاح التحقق والاسم (wave 2) |
| 0127 | `monthly_attendance_statement` | كشف الحضور الشهري |
| 0128 | `repair_request_live_location_staging` | إصلاح طلب الموقع على staging |
| 0129 | `employee_edit_and_list_enrichment` | إثراء تعديل وقائمة الموظفين |

#### مجموعة V17 (0130–0141): القرارات الإدارية الثمانية

| # | الملف | الوصف | القرار الإداري |
|---|---|---|---|
| 0130 | `v17_kpi_flow_reorder` | عكس تدفق KPI: ذاتي → HR → مدير → اعتماد | §10 |
| 0131 | `v17_dispute_admin_actions` | الإجراءات الإدارية للمنازعات: لجنة → سكرتير → تنفيذي → HR | §14 (القرار 4) |
| 0132 | `v17_official_holidays` | العطل الرسمية: نطاق مرن + استثناءات | §1.7 (القرار 7) |
| 0133 | `v17_post_publishing` | نشر المنشورات: 3 مصادر فقط (أدمن/HR/تنفيذي) | §18 (القرار 5) |
| 0134 | `v17_request_types` | محاذاة أنواع الطلبات + توجيه Operations للتنفيذي | §8 + §1.2 (القرار 2) |
| 0135 | `v17_word_count_checks` | قيود طول النص: 3–300 كلمة مع عداد | §1.3 (القرار 3) |
| 0136 | `fix_resolve_request_approver` | إصلاح جدول role_assignments → user_roles | (إصلاح تقني) |
| 0137 | `v17_attendance_executive_exemption` | استثناء المدير التنفيذي من الحضور + التذكيرات | §7 (القرار 1 جزئياً) |
| 0138 | `v17_permission_matrix_fixes` | إصلاح مصفوفة الصلاحيات (4 مشاكل) | §2.2.1 |
| 0139 | `v17_request_return_status` | حالة "مُعاد" (returned) للطلبات | §4.3 |
| 0140 | `v17_attendance_history_days` | معامل p_days لتصفية سجل الحضور | §4.2 |
| 0141 | `v17_dispute_admin_action_catalog` | عرض حقول الإجراءات الإدارية في الكتالوج + صندوق التنفيذي | §14 |

---

### 3.2 الـ Edge Functions (13 دالة)

| # | الدالة | الوصف | الاستدعاء |
|---|---|---|---|
| 1 | `_shared/` | مكتبة مشتركة: CORS, phone normalization, timing-safe comparison, secrets | مُستورد من كل الدوال |
| 2 | `admin-create-employee` | إنشاء موظف جديد: Supabase Auth signup + ربط employee record + إرسال رابط التفعيل | Web: صفحة إنشاء موظف |
| 3 | `admin-resend-invite` | إعادة إرسال رابط التفعيل لموظف لم يُفعّل حسابه بعد | Web: تفاصيل الموظف |
| 4 | `identifier-sign-in` | تسجيل دخول بمعرّف (بريد / هاتف / كود موظف) → تحويل لبريد → `signInWithPassword`. حماية: rate limit بالـ IP + pepper hash | Mobile + Web |
| 5 | `integration-outbox-worker` | معالج صندوق التكامل الصادر: يستهلك `integration_outbox` ويرسل webhooks | Cron (pg_net) |
| 6 | `live-location-map-url` | إنشاء رابط موقّع (120 ثانية) لعرض لقطة الخريطة | Web: بطاقة نتيجة الموقع |
| 7 | `live-location-video-url` | **معطّل نهائياً (V17 §9)** — يُرجع `410 Gone`. مُبقى كـ stub لمنع كسر النشر | -- |
| 8 | `notification-dispatcher` | مُرسل الإشعارات: يستهلك `notification_jobs` → FCM v1 (Android + APNs). يدعم الإشعارات العاجلة (شاشة كاملة + صوت) | Cron (pg_net) |
| 9 | `passkey-register` | تسجيل Passkey جديد: يتحقق من WebAuthn registration response ويحفظ المفتاح العام | Mobile: إعداد الجهاز |
| 10 | `retention-cleanup` | تنظيف البيانات المنتهية الصلاحية: حذف ملفات الفيديو/المواقع القديمة من Storage | Cron (pg_net) |
| 11 | `scheduled-report-runner` | منفّذ التقارير المجدولة: يُنشئ تقارير PDF/Excel ويحفظها في Storage | Cron (pg_net) |
| 12 | `verify-attendance-punch` | تحقق من WebAuthn assertion + تسجيل الحضور عبر RPC خادم فقط | Mobile: تسجيل الحضور (مسار WebAuthn) |
| 13 | `webauthn-challenge` | إنشاء تحديات WebAuthn (تسجيل + مصادقة) عبر `@simplewebauthn/server` | Mobile: قبل التسجيل/التحقق |

---

### 3.3 صفحات Flutter (40 صفحة + 2 مصادقة = 42 ملف) عبر 5 مساحات عمل

#### مساحة عمل الموظف (Employee Workspace) — الدور: `employee`

| الصفحة | الملف | الوصف |
|---|---|---|
| الرئيسية | `employee_home_page.dart` | لوحة الموظف: حالة الحضور + إجراءات اليوم + KPI |
| الحضور | `mobile_attendance_page.dart` | تسجيل الحضور (WebAuthn أو بصمة محلية) |
| خدمات الحضور | `mobile_attendance_services_page.dart` | خدمات الحضور المتقدمة |
| سجل الحضور | `attendance_history_page.dart` | سجل الحضور الشخصي |
| كشف شهري | `monthly_attendance_statement_page.dart` | الكشف الشهري المفصّل |
| الطلبات | `mobile_requests_page.dart` | قائمة طلباتي (إجازة، إذن، مهمة) |
| تفاصيل طلب | `mobile_request_detail_page.dart` | تفاصيل طلب مع الحالة والتعليقات |
| الأداء | `mobile_kpi_page.dart` | تقييمي الشهري + التقييم الذاتي |
| تفاصيل تقييم | `kpi_evaluation_detail_page.dart` | تفاصيل تقييم KPI واحد |
| الملف الشخصي | `mobile_profile_page.dart` | بيانات الموظف الشخصية |
| الفريق | `mobile_team_page.dart` | أعضاء فريقي |
| المهام | `mobile_tasks_page.dart` | مهامي اليومية |
| التقارير اليومية | `mobile_daily_reports_page.dart` | تقاريري اليومية |
| المنازعات | `mobile_disputes_page.dart` | قضاياي في لجنة المنازعات |
| الخدمة الذاتية | `mobile_self_service_page.dart` | بوابة الخدمة الذاتية |
| المنشورات | `mobile_official_feed_page.dart` | المنشورات الرسمية |
| تفاصيل منشور | `mobile_feed_detail_page.dart` | تفاصيل منشور رسمي |
| الإشعارات | `mobile_notifications_page.dart` | مركز الإشعارات |
| صندوق الإجراءات | `mobile_action_inbox_page.dart` | الإجراءات المطلوبة مني |
| الأجهزة | `passkey_devices_page.dart` | إدارة أجهزة Passkey |
| الهيكل التنظيمي | `org_chart_page.dart` | عرض الهيكل التنظيمي |

#### مساحة عمل المدير (Manager Workspace) — الدور: `direct-manager`

| الصفحة | الملف | الوصف |
|---|---|---|
| الرئيسية | `manager_home_page.dart` | لوحة المدير: حالة الفريق + طلبات معلقة + KPI |
| العمليات | `manager_operations_page.dart` | عمليات إدارة الفريق |

#### مساحة عمل التنفيذي (Executive Workspace) — الدور: `executive`

| الصفحة | الملف | الوصف |
|---|---|---|
| الرئيسية | `executive_home_page.dart` | لوحة المدير التنفيذي الشاملة |
| الموجز | `executive_brief_page.dart` | الموجز التنفيذي اليومي |
| القرارات | `executive_decisions_page.dart` | القرارات الإدارية المعلقة |
| الأشخاص | `executive_people_page.dart` | نظرة عامة على القوى العاملة |
| ملخص موظف | `executive_employee_summary_page.dart` | ملخص موظف مُختصر (privacy-minimised) |
| الحضور | `executive_attendance_tab.dart` | تبويب حضور اليوم |
| الموقع المباشر | `executive_location_page.dart` | طلب + متابعة الموقع المباشر |
| جلسة التتبع | `live_tracking_session_page.dart` | جلسة تتبع مباشر نشطة |
| المنازعات | `executive_disputes_page.dart` | قضايا المنازعات (قرار تنفيذي) |
| التقارير | `executive_reports_page.dart` | التقارير التنفيذية |
| الحوكمة | `executive_governance_page.dart` | حوكمة الإصدارات والسياسات |
| الطوارئ | `executive_emergency_page.dart` | مركز الطوارئ |
| مركز المخاطر | `executive_risk_center_page.dart` | مركز إدارة المخاطر |

#### مساحة عمل التشغيل (Operations Workspace) — الأدوار: `operations-manager-1/2`, `operations-officer`

| الصفحة | الملف | الوصف |
|---|---|---|
| (مشتركة) | تستخدم صفحات المدير + لجنة المنازعات | عمليات التشغيل |

#### مساحة عمل اللجنة (Committee Workspace) — الدور: `committee-secretary`

| الصفحة | الملف | الوصف |
|---|---|---|
| (مشتركة) | تستخدم `mobile_disputes_page.dart` | بوابة لجنة حل المشكلات |

#### صفحات مشتركة / نظامية

| الصفحة | الملف | الوصف |
|---|---|---|
| تسجيل الدخول | `login_page.dart` | تسجيل دخول بمعرّف (بريد/هاتف/كود) |
| تعيين كلمة المرور | `set_password_page.dart` | تعيين/إعادة تعيين كلمة المرور |
| رابط عميق | `mobile_action_deep_link_page.dart` | معالج الروابط العميقة |
| رابط طلب موقع | `mobile_location_request_deep_link_page.dart` | رابط عميق لطلب موقع وارد |
| طلبات الموقع | `location_requests_page.dart` | قائمة طلبات الموقع الواردة |
| تراكب الموقع | `location_incoming_overlay.dart` | تراكب شاشة كاملة لطلب موقع عاجل |
| موجّه الإجراءات | `mobile_action_router.dart` | توجيه الإجراءات حسب النوع |
| عناصر مشتركة | `mobile_widgets.dart` | عناصر واجهة مشتركة |

#### ملفات البنية التحتية للموبايل

| المجلد | الملفات الرئيسية | الوصف |
|---|---|---|
| `core/` | `app_theme.dart`, `theme_mode_controller.dart`, `connectivity_service.dart` | السمة + الاتصال |
| `features/auth/` | `auth_providers.dart` | مزودو المصادقة (Riverpod) |
| `features/mobile_data/` | `mobile_models.dart`, `mobile_providers.dart`, `location_service.dart`, `push_service.dart` | النماذج + المزودون + GPS + FCM |
| `features/workspaces/` | `app_gate.dart`, `workspace_scaffold.dart`, + 5 workspaces | البوابة + الهيكل + 5 مساحات عمل |

---

### 3.4 ملفات الويب (70 ملف في 13 feature directory)

#### التوزيع حسب المجلد

| المجلد | عدد الملفات | الصفحات/المكونات الرئيسية |
|---|---|---|
| **management/** | 27 | `AccessPage`, `AuditSecurityPage`, `DocumentStudioPage`, `EnterpriseManagementPage`, `ExecutiveMonitoringPage`, `IntegrationsJobsPage`, `LearningPage`, `LiveLocationPage`, `LiveLocationMap`, `LiveLocationResultCard`, `OnboardingPage`, `OperationsCenterPage`, `OrganizationPage`, `PeopleFinancePage`, `RecruitmentPage`, `ReleaseGovernancePage`, `ReportSchedulerPage`, `ReportsPage`, `ServiceDeskPage`, `SystemPage` + 7 hooks |
| **auth/** | 9 | `AuthProvider`, `LoginPage`, `MobileRedirectPage`, `PasswordSetupPage` (+ test), `WebReleaseStatusPage`, `accessService`, `mockContexts`, `useWebReleasePolicy` |
| **advanced/** | 5 | `AttendanceOperationsPage`, `DisputesPage`, `KpiCyclesPage`, `LifecycleOperationsPage`, `useAdvancedOperations` |
| **employees/** | 5 | `CreateEmployeePage`, `EmployeeDetailPage`, `EmployeesPage`, `useEmployees`, `useOrganizationLookups` |
| **attendance/** | 4 | `AttendancePage`, `MonthlyStatementSection`, `useAttendanceDashboard`, `useMonthlyStatement` |
| **performance/** | 4 | `KpiEvaluationEditor`, `PerformancePage`, `usePerformance`, `workflowStatus` |
| **workspaces/** | 4 | `DashboardPage`, `WorkspaceShell`, `access` (+ test) |
| **actions/** | 2 | `ActionCenterPage`, `useActionCenter` |
| **communications/** | 2 | `OfficialFeedPage`, `useOfficialFeed` |
| **holidays/** | 2 | `OfficialHolidaysPage`, `useHolidays` |
| **mock/** | 2 | `domainMocks`, `loadDomainMocks` |
| **notifications/** | 2 | `NotificationsPage`, `useNotifications` |
| **requests/** | 2 | `RequestsPage`, `useRequests` |

#### مساحات العمل الويب (3 مساحات + لجنة)

| المساحة | المسار | الصلاحية | الصفحات |
|---|---|---|---|
| **HR** | `/hr/*` | عبر `WorkspaceGuard` | Dashboard, Employees, Attendance, Requests, Performance, Recruitment, Onboarding, Reports, Holidays, Official Feed, Notifications |
| **Main Admin** | `/admin/*` | عبر `WorkspaceGuard` | Dashboard, Actions, Live Location, Monitoring, Official Feed, Organization, KPI Cycles, Disputes, Access, Settings, Reports Scheduler, Enterprise, Operations, Audit Security, Integrations, Notifications |
| **Committee** | `/committee/*` | عبر `WorkspaceGuard` | Disputes, Notifications |
| **Auth** | `/login`, `/auth/*` | عام | Login, PasswordSetup, MobileRedirect, WebReleaseStatus |

---

### 3.5 اختبارات pgTAP (60 ملف / 810 assertion)

| # | الملف | عدد الـ assertions | النطاق |
|---|---|---|---|
| 0001 | `core_security_structure` | 14 | البنية الأمنية الأساسية |
| 0002 | `foundation_contracts` | 10 | عقود التأسيس |
| 0003 | `operational_workspaces` | 13 | مساحات العمل التشغيلية |
| 0004 | `management_overviews` | 8 | نماذج الإدارة |
| 0005 | `live_location_flow` | 8 | تدفق الموقع المباشر |
| 0006 | `request_self_service` | 5 | الخدمة الذاتية للطلبات |
| 0007 | `kpi_attendance_mobile` | 6 | KPI والحضور والموبايل |
| 0008 | `mobile_details_routing` | 7 | تفاصيل وتوجيه الموبايل |
| 0009 | `mobile_daily_workspaces` | 17 | مساحات العمل اليومية |
| 0010 | `passkey_revoke_attendance_history` | 8 | إلغاء Passkey + سجل الحضور |
| 0011 | `mobile_notifications_contract` | 3 | عقد الإشعارات |
| 0012 | `passkey_mobile_action_security` | 12 | أمان Passkey والإجراءات |
| 0013 | `admin_operations` | 22 | عمليات الإدارة |
| 0014 | `leave_ledger_contract` | 12 | عقد دفتر الإجازات |
| 0015 | `decision_lifecycle_contract` | 13 | عقد دورة حياة القرارات |
| 0016 | `attendance_operations_contract` | 11 | عقد عمليات الحضور |
| 0017 | `kpi_advanced_contract` | 10 | عقد KPI المتقدم |
| 0018 | `dispute_committee_contract` | 14 | عقد لجنة المنازعات |
| 0019 | `lifecycle_contract` | 12 | عقد دورة الحياة |
| 0020 | `enterprise_talent_learning_contract` | 13 | عقد المواهب والتعلم |
| 0021 | `enterprise_management_modules` | 15 | وحدات إدارة المؤسسة |
| 0022 | `workforce_payroll_engagement_contract` | 12 | عقد الرواتب والتفاعل |
| 0023 | `retention_privacy_contract` | 10 | عقد الاحتفاظ والخصوصية |
| 0024 | `release_access_privacy_integration_governance` | 24 | حوكمة الإصدار والوصول |
| 0025 | `identifier_login_security` | 7 | أمان تسجيل الدخول |
| 0026 | `release_0_10_contract` | 4 | عقد الإصدار 0.10 |
| 0027 | `persona_rls_runtime` | 23 | RLS حسب الشخصية |
| 0028 | `recruitment_interviews_offers_hire` | 11 | التوظيف والمقابلات |
| 0029 | `break_glass_runtime` | 9 | وصول الطوارئ |
| 0030 | `leave_accrual_scheduling` | 9 | جدولة استحقاق الإجازات |
| 0031 | `audit_remediation_runtime` | 9 | معالجة التدقيق |
| 0032 | `audit_remediation_p2` | 6 | معالجة التدقيق P2 |
| 0033 | `observability_alerting` | 11 | المراقبة والتنبيهات |
| 0034 | `audit_remediation_p3_ledger` | 3 | معالجة التدقيق P3 |
| 0035 | `official_kpi_governance` | 31 | حوكمة KPI الرسمية |
| 0036 | `official_kpi_runtime` | 16 | تشغيل KPI الرسمي |
| 0037 | `dispute_committee_runtime` | 16 | تشغيل لجنة المنازعات |
| 0038 | `leave_workflow_contract` | 24 | عقد سير عمل الإجازات |
| 0039 | `work_assignments_contract` | 18 | عقد التكليفات |
| 0040 | `live_location_executive_runtime` | 22 | تشغيل الموقع التنفيذي |
| 0041 | `v4_location_notification_device_contract` | 16 | عقد الموقع والإشعارات والأجهزة |
| 0042 | `atomic_attendance_contract` | 17 | عقد الحضور الذري |
| 0043 | `employee_archive_delete_contract` | 11 | عقد الأرشفة والحذف |
| 0044 | `release_0_11_1_deep_audit_contract` | 17 | عقد تدقيق 0.11.1 |
| 0045 | `v10_six_role_acceptance` | 47 | قبول الأدوار الستة (V10) |
| 0046 | `employee_avatar_storage_contract` | 12 | عقد تخزين الصور |
| 0047 | `kpi_validation_array_initialization` | 3 | تهيئة مصفوفة KPI |
| 0048 | `fcm_push_delivery_runtime` | 14 | تشغيل إرسال FCM |
| 0049 | `release_governance_overview_regression` | 4 | انحدار حوكمة الإصدار |
| 0050 | `monthly_attendance_statement` | 12 | الكشف الشهري |
| 0051 | `provision_employee_record` | 13 | إنشاء سجل الموظف |
| 0052 | `employee_edit_enrichment` | 12 | إثراء تعديل الموظف |
| 0053 | `v17_kpi_flow` | 18 | تدفق KPI (V17) |
| 0054 | `v17_dispute_admin_actions` | 22 | الإجراءات الإدارية (V17) |
| 0055 | `v17_official_holidays` | 20 | العطل الرسمية (V17) |
| 0056 | `v17_operations_request_routing` | 16 | توجيه طلبات التشغيل (V17) |
| 0057 | `v17_post_publishing` | 16 | نشر المنشورات (V17) |
| 0058 | `v17_word_count_checks` | 18 | قيود طول النص (V17) |
| 0059 | `v17_permission_matrix_fixes` | 10 | إصلاح مصفوفة الصلاحيات (V17) |
| 0060 | `v17_request_return_and_attendance_days` | 14 | حالة المُعاد + أيام الحضور (V17) |

---

### 3.6 الأدوار (10 أدوار فعلية في قاعدة البيانات)

| # | الـ slug | الاسم العربي | المصدر | `is_full_access` | الوصف |
|---|---|---|---|---|---|
| 1 | `admin` | مدير النظام (Main Admin) | mig 0002 | **نعم** | أعلى صلاحية — يرى كل شيء |
| 2 | `employee` | موظف | mig 0002 | لا | الدور الافتراضي لكل موظف |
| 3 | `direct-manager` | مدير مباشر | mig 0056 | لا | يدير فريقه المباشر |
| 4 | `operations-officer` | ضابط عمليات | mig 0056 | لا | عمليات التشغيل |
| 5 | `operations-manager-1` | مدير التشغيل 1 | mig 0059 | لا | إدارة التشغيل الأولى + لجنة المنازعات |
| 6 | `operations-manager-2` | مدير التشغيل 2 | mig 0059 | لا | إدارة التشغيل الثانية + لجنة المنازعات |
| 7 | `committee-secretary` | مقرر لجنة حل المشكلات | mig 0059 | لا | إدارة الجلسات والمحاضر |
| 8 | `executive` | المدير التنفيذي | mig 0121 | لا | أعلى صلاحية تشغيلية بعد admin |
| 9 | `executive-secretary` | السكرتير التنفيذي | mig 0121 | لا | إدارة الدورات والمتابعة |
| 10 | `hr-manager` | مدير الموارد البشرية | mig 0121 | لا | شؤون الموظفين والحضور والتقييم |

**ملاحظة:** الأدوار الستة المُشار إليها في الوثائق التشغيلية هي التجميع الوظيفي:
1. **Employee** = `employee`
2. **Manager** = `direct-manager`
3. **Operations** = `operations-officer` + `operations-manager-1` + `operations-manager-2`
4. **Executive Director** = `executive`
5. **HR** = `hr-manager` (+ `executive-secretary` للدعم)
6. **Main Admin** = `admin` (+ `committee-secretary` للجنة)

---

### 3.7 مسارا الحضور

| المسار | الآلية | الملفات الرئيسية | سياسة الأمان |
|---|---|---|---|
| **WebAuthn** | Edge Function `verify-attendance-punch` → `@simplewebauthn/server` → RPC خادم | mig 0005, 0020, 0023, 0089; Edge: `webauthn-challenge`, `verify-attendance-punch`, `passkey-register` | challenge/response مشفر + device attestation + `attendance_punch_attempts` idempotent |
| **Local Biometric** | RPC `punch_attendance_local_biometric_v1` مباشرة من Flutter | mig 0094, 0095, 0104, 0137 | بصمة محلية + فحص `employee_devices.is_active` |

**فجوة مكتشفة (V17 §8 — القرار 8):**

| الفحص | WebAuthn | Local Biometric | الحالة |
|---|---|---|---|
| Mock location detection | mig 0046 | mig 0095 (جزئي) | **غير موحّد** |
| Geofence validation | mig 0046, 0089 | mig 0094 (مختلف) | **غير موحّد** |
| Impossible travel | mig 0046 | **غير موجود** | **فجوة** |
| Executive exemption | mig 0137 | mig 0137 | موحّد |

---

## 4. القرارات الإدارية الملزمة (8 قرارات)

### القرار 1: استثناء المدير التنفيذي من KPI والحضور الإلزامي

**الحالة:** مُنفَّذ جزئياً

| البند | التنفيذ | المرجع |
|---|---|---|
| استثناء من الحضور | mig 0137: سدّ ثغرتين في `punch_attendance_local` و`generate_punch_reminders` | V17 §7 |
| استثناء من تذكيرات الحضور | mig 0137: فلترة التنفيذي من `generate_punch_reminders` | V17 §7 |
| استثناء من KPI | mig 0110: التنفيذي يتلقى تقارير KPI التجميعية **لكن لا يُقيَّم** | V17 §10 |

**القاعدة:** المدير التنفيذي (slug = `executive`) لا يظهر في:
- قوائم تسجيل الحضور
- تذكيرات التسجيل (4 تذكيرات يومية)
- دورات التقييم الشهرية كمُقيَّم
- يظهر **فقط** كمعتمد نهائي أو متلقٍ للتقارير

---

### القرار 2: طلبات Operations تُرفع للمدير التنفيذي

**الحالة:** مُنفَّذ

| البند | التنفيذ | المرجع |
|---|---|---|
| توجيه الطلبات | mig 0134: `resolve_request_approver` يوجّه طلبات `operations-manager-1/2` و`operations-officer` للتنفيذي | V17 §1.2 |
| إصلاح المسار | mig 0136: إصلاح مرجع `role_assignments` → `user_roles` | إصلاح تقني |

**القاعدة:** أي طلب (إجازة، إذن، مهمة) مقدّم من موظف بدور Operations يُوجَّه تلقائياً للمدير التنفيذي كمعتمد، وليس لمديره المباشر.

---

### القرار 3: وصف المشكلة 3–300 كلمة مع عداد

**الحالة:** مُنفَّذ

| البند | التنفيذ | المرجع |
|---|---|---|
| قيود قاعدة البيانات | mig 0135: قيود `CHECK` على حقول النص (NOT VALID — لا تمس البيانات القديمة) | V17 §1.3 |
| النطاقات | نص قصير: 3–300 كلمة. نص طويل: 3–2000 كلمة | |
| عقد مشترك | `shared-contracts/src/validation.ts`: دوال Zod للعدّ والتحقق | |

**القاعدة:** كل حقل وصف مشكلة أو بيان أو تعليق في النظام يخضع لقيد الطول. واجهة المستخدم تعرض عداد كلمات حي.

---

### القرار 4: مسار الجزاء — 8 حالات

**الحالة:** مُنفَّذ

**المسار الكامل:**

```
لجنة حل المشكلات (اقتراح إجراء)
    → مقرر اللجنة (committee-secretary): يوثّق ويرفع
    → المدير التنفيذي (executive): قرار تنفيذي (موافقة/رفض/تعديل)
    → HR (hr-manager): تنفيذ القرار + توثيق في ملف الموظف
```

| الحالة | المعنى | المرجع |
|---|---|---|
| `proposed` | الإجراء مقترح من اللجنة | mig 0131 |
| `secretary_review` | مراجعة المقرر | mig 0131 |
| `executive_pending` | في انتظار قرار التنفيذي | mig 0131 |
| `executive_approved` | وافق التنفيذي | mig 0131 |
| `executive_rejected` | رفض التنفيذي | mig 0131 |
| `executive_modified` | عدّل التنفيذي الإجراء | mig 0131 |
| `hr_executing` | HR ينفّذ القرار | mig 0131 |
| `completed` | تم التنفيذ والتوثيق | mig 0131 |

**المراجع:** mig 0131, 0138 (إصلاح صلاحيات), 0141 (عرض في الكتالوج), test 0054

---

### القرار 5: المنشورات — 3 مصادر فقط

**الحالة:** مُنفَّذ

| المصدر | الصلاحية | المرجع |
|---|---|---|
| **Main Admin** (`admin`) | `comms.announcement.manage` (موجودة مسبقاً) | mig 0133 |
| **HR** (`hr-manager`) | `posts.publish` (جديدة) | mig 0133 |
| **المدير التنفيذي** (`executive`) | `posts.publish` (جديدة) | mig 0133 |

**القاعدة:** لا يحق لأي دور آخر نشر منشورات رسمية. عمود `publisher_channel` على `announcements` يُسجّل مصدر النشر. سياسات RLS محدّثة لقبول `posts.publish` بجانب `comms.announcement.manage`.

---

### القرار 6: مواعيد الحضور 10:00–18:00 مع 4 تذكيرات

**الحالة:** مُنفَّذ

| البند | التنفيذ | المرجع |
|---|---|---|
| الوردية الرسمية | mig 0057: `official_shifts` بداية 10:00، نهاية 18:00 | |
| التذكيرات | mig 0057: `generate_punch_reminders` — 4 تذكيرات يومية | |
| التذكير 1 | 09:45 — "تذكير: موعد تسجيل الحضور خلال 15 دقيقة" | |
| التذكير 2 | 10:15 — "تنبيه: لم تسجّل حضورك بعد" | |
| التذكير 3 | 17:45 — "تذكير: موعد تسجيل الانصراف خلال 15 دقيقة" | |
| التذكير 4 | 18:15 — "تنبيه: لم تسجّل انصرافك بعد" | |

**القاعدة:** التذكيرات تُرسل عبر FCM (`notification-dispatcher`). المدير التنفيذي مُستثنى (القرار 1).

---

### القرار 7: الإجازات الرسمية — وحدة HR بنطاق مرن

**الحالة:** مُنفَّذ

| البند | التنفيذ | المرجع |
|---|---|---|
| جدول العطل | mig 0132: توسيع `public_holidays` (mig 0003) بأعمدة النطاق | V17 §1.7 |
| نطاق التطبيق | `scope_type`: الكل / جهة قانونية / إدارة محددة | mig 0132 |
| الاستثناءات | جدول استثناءات لموظفين أو إدارات لا تشملهم العطلة | mig 0132 |
| صفحة الويب | `OfficialHolidaysPage` + `useHolidays` في `/hr/holidays` | features/holidays/ |
| الصلاحية | `holidays.manage` — مقصورة على HR وAdmin | mig 0132 |
| العقد المشترك | `shared-contracts/src/holidays.ts` | test 0055 (20 assertion) |

---

### القرار 8: (جديد) توحيد سياسة الأمان — Mock Locations و Geofence

**الحالة:** فجوة مفتوحة — يتطلب تنفيذاً في V18

**المشكلة المكتشفة:**

مسارا الحضور (WebAuthn و Local Biometric) يطبّقان سياسات أمان **غير متطابقة**:

| الفحص | WebAuthn (0046, 0089) | Local Biometric (0094, 0095) | المطلوب في V18 |
|---|---|---|---|
| **Mock location** | `is_mock_location` → رفض فوري + `attendance_risk_events` | فحص جزئي في 0095 | توحيد: نفس المنطق |
| **Geofence** | فحص `geofences` + مسافة + `ST_DWithin` | فحص مبسّط في 0094 | توحيد: نفس دالة المسافة |
| **Impossible travel** | `attendance_risk_events` + فحص سرعة بين آخر موقع | **غير موجود** | إضافة فحص impossible travel |
| **Device verification** | `passkey_credentials` + `employee_devices` | `employee_devices.is_active` | متّسق |
| **Audit trail** | `attendance_punch_attempts` + `audit_events` | `audit_events` فقط | توحيد: تسجيل في `attendance_punch_attempts` أيضاً |

**خطة التنفيذ المطلوبة:**

1. استخراج منطق الأمان المشترك إلى دالة PostgreSQL واحدة: `validate_attendance_security_checks()`
2. استدعاؤها من **كلا** المسارين قبل تسجيل الحضور
3. تشمل: mock location + geofence + impossible travel + device active
4. migration جديدة + توسيع اختبار 0042 (`atomic_attendance_contract`)

---

**نهاية القسم الأول من الخطة التنفيذية V18**

*الأقسام التالية (5–12) تغطي: تحليل الفجوات، أولويات V18، خطة التنفيذ المرحلية، مصفوفة الصلاحيات الكاملة، خطة الاختبار، خطة النشر، معايير القبول، والجدول الزمني.*

---

Now I have a thorough understanding of the codebase. Let me write the comprehensive P0 plan.

---

## 5. P0 -- تسجيل الجهاز والبصمة

### 5.1 المشكلة

النظام الحالي يسمح بتسجيل جهاز جديد عبر `PasskeyDevicesPage` و`MobileAttendancePage` دون رقابة ادارية. الموظف يستطيع تسجيل اي جهاز يملكه والبدء بالبصمة فورا. لا يوجد مفهوم "الموافقة" من المسؤول قبل تفعيل الجهاز، ولا آلية لمنع تسجيل اجهزة متعددة بالتوازي. الحالات الحالية في `employee_devices` هي `active` و`revoked` فقط -- لا توجد حالة `pending_approval` او `blocked`.

هذا يعني:
- موظف يستطيع تسجيل جهاز صديقه وبصمة الحضور نيابة عنه.
- لا يوجد سجل اداري لمن وافق على تسجيل الجهاز.
- تغيير الجهاز (شراء هاتف جديد) لا يعطل الجهاز القديم تلقائيا.

### 5.2 الصفحة المطلوبة: حسابي -- الاجهزة

**المسار:** `MobileAttendancePage` ← زر "اجهزتي" ← `PasskeyDevicesPage` (موجودة حاليا في `apps/mobile_flutter/lib/features/mobile_pages/passkey_devices_page.dart`).

**التعديل المطلوب:** اعادة تسمية الصفحة الى "اجهزة البصمة" وربطها ايضا من `MobileSelfServicePage` تحت قسم "حسابي" بعنوان "اجهزتي الموثوقة". الصفحة تعرض:

| العنصر | الوصف |
|---|---|
| قائمة الاجهزة | كل جهاز مسجل مع حالته ووقت التسجيل وآخر استخدام |
| شريط الحالة | لون مميز لكل حالة (اخضر=نشط، برتقالي=معلق، احمر=محظور، رمادي=ملغي) |
| زر التسجيل | `FloatingActionButton` يبدا عملية تسجيل جهاز جديد |
| زر الالغاء | لكل جهاز نشط -- يطلب سبب الالغاء ثم يعدل الحالة الى `revoked` |

### 5.3 حالات الجهاز

```
لا جهاز ← [تسجيل] ← pending_approval ← [موافقة Admin] ← active
                                        ← [رفض Admin]   ← blocked
active   ← [تسجيل جهاز جديد]          ← القديم: revoked_auto + الجديد: pending_approval
active   ← [الغاء يدوي]               ← revoked
active   ← [حظر اداري]                ← blocked
blocked  ← [رفع الحظر]                ← pending_approval (يحتاج موافقة جديدة)
```

**جدول الحالات في `employee_devices.status`:**

| الحالة | المعنى | يستطيع البصمة؟ |
|---|---|---|
| `pending_approval` | الموظف سجل الجهاز وينتظر موافقة المسؤول | لا |
| `active` | الجهاز موافق عليه ومفعل | نعم |
| `revoked` | الموظف الغى الجهاز يدويا | لا |
| `revoked_auto` | النظام الغاه تلقائيا عند تسجيل جهاز جديد | لا |
| `blocked` | المسؤول حظر الجهاز | لا |

### 5.4 رحلة التسجيل: WebAuthn -- موافقة Admin

```
[الموظف: يضغط "تسجيل هذا الجهاز"]
    ↓
[التطبيق: يقرا GPS + يتحقق من عدم وجود mock location]
    ↓
[التطبيق: يستدعي WebAuthn / Local Biometric]
    ↓
[Edge Function passkey-register أو RPC: يسجل credential + يُنشئ صف employee_devices بحالة pending_approval]
    ↓
[إشعار push لـ HR / Operations: "الموظف X سجل جهازا جديدا ينتظر الموافقة"]
    ↓
[لوحة الويب: صفحة "اجهزة الموظفين" تعرض الطلبات المعلقة]
    ↓
[HR/Operations: يوافق ← active | يرفض ← blocked مع سبب]
    ↓
[إشعار push للموظف: "تم تفعيل/رفض جهازك"]
```

### 5.5 القواعد

1. **جهاز واحد نشط فقط:** لا يُسمح بوجود اكثر من جهاز واحد بحالة `active` لنفس الموظف. عند تسجيل جهاز جديد، يُعدّل الجهاز النشط القديم الى `revoked_auto` تلقائيا قبل ادراج الجديد بحالة `pending_approval`.
2. **تغيير الجهاز = تعطيل القديم:** عبر constraint او trigger في PostgreSQL: `BEFORE INSERT ON employee_devices` يتحقق ويعطل اي جهاز `active` سابق.
3. **الموافقة مطلوبة:** لا يمكن تغيير حالة الجهاز الى `active` الا عبر RPC محمي بـ `current_is_full_access()` او صلاحية `approve_device`.
4. **الحظر الاداري لا يُلغى ذاتيا:** الجهاز المحظور يحتاج رفع الحظر يدويا، ثم موافقة جديدة.
5. **Auto-provision في `verify-attendance-punch`:** السلوك الحالي (سطر 148-176 في `supabase/functions/verify-attendance-punch/index.ts`) الذي ينشئ صف `employee_devices` تلقائيا يجب تعديله ليُنشئ الصف بحالة `pending_approval` بدلا من `active`.

### 5.6 التغييرات التقنية

| الطبقة | الملف/المكون | التغيير |
|---|---|---|
| Migration | جديد: `0142_device_approval_workflow.sql` | اضافة `pending_approval`, `revoked_auto`, `blocked` لـ check constraint على `employee_devices.status`؛ عمود `approved_by uuid`، `approved_at timestamptz`، `rejection_reason text`؛ trigger لتعطيل الجهاز القديم؛ RPC `approve_device(p_device_id, p_approved)` محمي بـ `current_is_full_access()` |
| Edge Function | `passkey-register/index.ts` | تعديل الادراج ليكون `status: 'pending_approval'` |
| Edge Function | `verify-attendance-punch/index.ts` | سطر 148-176: تعديل auto-provision ليكون `pending_approval` بدلا من `active` |
| Mobile | `passkey_devices_page.dart` | عرض الحالات الجديدة بالوان مناسبة؛ رسالة "جهازك ينتظر الموافقة" |
| Mobile | `mobile_attendance_page.dart` | اذا كان الجهاز `pending_approval`: عرض رسالة "جهازك مسجل وينتظر موافقة المسؤول" بدلا من زر البصمة |
| Web | صفحة جديدة: `DeviceApprovalPage.tsx` | قائمة الاجهزة المعلقة مع ازرار موافقة/رفض |

### 5.7 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | موظف بدون جهاز يسجل جهازا جديدا | يظهر الجهاز بحالة `pending_approval`، ولا يستطيع البصمة |
| 2 | HR يوافق على الجهاز | الحالة تتغير الى `active`، الموظف يستطيع البصمة، ويصله اشعار push |
| 3 | موظف لديه جهاز `active` يسجل جهازا جديدا | الجهاز القديم يتحول الى `revoked_auto`، الجديد `pending_approval` |
| 4 | HR يحظر جهازا نشطا | الحالة تتغير الى `blocked`، البصمة ترفض مع رسالة "جهازك محظور" |
| 5 | الموظف يحاول البصمة بجهاز `pending_approval` | الخادم يرفض مع خطا `device_not_active`، التطبيق يعرض "جهازك ينتظر الموافقة" |

---

## 6. P0 -- الحضور والانصراف

### 6.1 المساران الحاليان

النظام يملك مسارين للحضور، كلاهما موجود ويعمل:

**المسار الاول -- WebAuthn (`verify-attendance-punch`):**
- الملف: `supabase/functions/verify-attendance-punch/index.ts` (249 سطر)
- الآلية: التطبيق يقرا GPS ← يطلب WebAuthn challenge من `webauthn-challenge` ← يحقق بصمة الجهاز ← يُرسل assertion + احداثيات الى `verify-attendance-punch` ← الخادم يتحقق من assertion ← يستدعي `finalize_verified_attendance`
- **تعامله مع mock location:** يقرا `isMock` من الطلب (سطر 88) ويمرره كـ `p_is_mock` لـ `finalize_verified_attendance` (سطر 234). **المشكلة:** الدالة الخادمية تُعلّم البصمة `flagged` فقط ولا ترفضها.

**المسار الثاني -- Local Biometric (`punch_attendance_local_biometric`):**
- الملف: `supabase/migrations/0094_punch_attendance_local_biometric.sql`
- الآلية: التطبيق يقرا GPS ← يتحقق من بصمة الجهاز محليا ← يستدعي RPC `punch_attendance_local_biometric` بالاحداثيات
- **تعامله مع mock location:** يرفض البصمة فورا مع خطا `attendance_mock_location_rejected` (سطر 40).

### 6.2 التناقض الامني -- يجب اصلاحه

| السلوك | WebAuthn | Local Biometric |
|---|---|---|
| Mock location | يُعلّم `flagged` فقط ← **خطا: يجب ان يرفض** | يرفض فورا ← صحيح |
| فحص السياج (geofence) | يتحقق عبر `finalize_verified_attendance` | يتحقق عبر `punch_attendance_local_biometric` |
| فحص دقة GPS | لا يتحقق خادميا (العميل فقط) | يتحقق خادميا |

**الاصلاح المطلوب:** تعديل `finalize_verified_attendance` ليرفض البصمة عند `p_is_mock = true` بدلا من تعليمها فقط. يجب ان يرجع `{ ok: false, error: 'attendance_mock_location_rejected' }` تماما كما يفعل المسار المحلي.

### 6.3 الصفحة

الصفحة موجودة: `apps/mobile_flutter/lib/features/mobile_pages/mobile_attendance_page.dart` (688 سطر).

**تصميمها الحالي:**
- زر واحد يتحول بين "تسجيل الحضور" و"تسجيل الانصراف" حسب `suggestedAction` من `attendanceStateProvider`
- بطاقة حالة اليوم تعرض: الحالة، بصمة الجهاز (مفعلة/غير مفعلة)، آخر عملية، وقت آخر عملية
- ازرار فرعية: سجل الحضور، اجهزتي، كشف الشهر
- بانر GPS تحذيري (`GpsPreflightBanner`)
- معالجة كاملة لحالات GPS (مغلق / صلاحية مرفوضة / مرفوضة نهائيا) مع اعادة محاولة تلقائية عند العودة من الاعدادات

**لا تحتاج تغييرا جوهريا في الواجهة** -- التصميم مكتمل. التغيير المطلوب تقني فقط.

### 6.4 رحلة البصمة (المسار الموحد)

```
[الموظف: يضغط زر الحضور/الانصراف]
    ↓
[dialog تاكيد: "سيقرا التطبيق موقعك ويطلب بصمة الجهاز"]
    ↓
[فحص GPS: هل الخدمة مفعلة؟ هل الصلاحية ممنوحة؟]
    ↓ فشل → dialog مع زر فتح الاعدادات + اعادة محاولة تلقائية
[قراءة الموقع: Position مع دقة ≤ 100 متر]
    ↓ فشل → رسالة "الموقع غير دقيق بما يكفي"
[فحص mock location: Position.isMocked]
    ↓ true → رفض فوري: "موقع وهمي — لا يمكن تسجيل الحضور"
[فحص السياج: هل الموقع داخل نطاق المقر؟]
    ↓ خارج → يُسجل مع علامة "خارج المجمع" (لا يُرفض)
[بصمة الجهاز: WebAuthn assertion أو Local Biometric]
    ↓ فشل → "تم الغاء التحقق بالبصمة"
[ارسال للخادم: verify-attendance-punch أو punch_attendance_local_biometric]
    ↓
[الخادم: تحقق من الجهاز + credential + السياج + mock + الازدواجية]
    ↓ رفض → رسالة خطا محددة بالعربية
[نجاح ← تحديث حالة اليوم ← snackbar "تم تسجيل الحضور"]
```

### 6.5 القواعد

| # | القاعدة | التطبيق |
|---|---|---|
| 1 | بصمة واحدة حضور + واحدة انصراف في اليوم | `suggestedAction` يتحول بعد كل بصمة ناجحة؛ الخادم يرفض التكرار |
| 2 | لا تكرار خلال 5 دقائق | الخادم يتحقق من `last_event_at` ويرفض اذا الفارق < 5 دقائق |
| 3 | تاخر بعد 10:00 صباحا | الخادم يحسب `late_minutes` ويعلّم الحالة `late` |
| 4 | انصراف مبكر قبل 18:00 | الخادم يحسب `early_leave_minutes` ويعلّم في الملاحظات |
| 5 | mock location = رفض فوري | **كلا المسارين** يرفضان (بعد الاصلاح) |
| 6 | دقة GPS > 100 متر | رفض خادمي مع رسالة "الموقع غير دقيق" |
| 7 | الجهاز ليس `active` | رفض خادمي مع رسالة مناسبة حسب الحالة |

### 6.6 الاصلاح التقني المطلوب

| الطبقة | الملف | التغيير |
|---|---|---|
| Migration | جديد: `0143_unify_mock_location_rejection.sql` | تعديل `finalize_verified_attendance` ليرفض عند `p_is_mock = true` بدلا من تعليم `flagged` فقط، تماما كما يفعل `punch_attendance_local_biometric` |
| Edge Function | `verify-attendance-punch/index.ts` | لا تغيير -- يمرر `isMock` بالفعل؛ الاصلاح في الدالة الخادمية |
| Mobile | `mobile_attendance_page.dart` | اضافة فحص `position.isMocked` قبل ارسال الطلب في مسار WebAuthn (حاليا موجود في المسار المحلي فقط) |

### 6.7 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | موظف يبصم حضور من داخل المجمع بدون mock | نجاح، الحالة `present` |
| 2 | موظف يبصم حضور بعد 10:00 | نجاح، الحالة `late`، `late_minutes` محسوبة |
| 3 | موظف يبصم حضور بـ mock location عبر WebAuthn | رفض فوري بخطا `attendance_mock_location_rejected` |
| 4 | موظف يبصم حضور بـ mock location عبر Local Biometric | رفض فوري بخطا `attendance_mock_location_rejected` |
| 5 | موظف يبصم مرتين خلال 3 دقائق | الثانية تُرفض |
| 6 | موظف يبصم انصراف قبل 18:00 | نجاح مع علامة `early_departure` |
| 7 | موظف يبصم من خارج السياج | نجاح مع علامة `خارج المجمع` وحالة `flagged` للمراجعة |
| 8 | موظف بجهاز `pending_approval` يحاول البصمة | رفض مع رسالة "جهازك ينتظر الموافقة" |

---

## 7. P0 -- مركز الطلبات

### 7.1 الوضع الحالي

مركز الطلبات موجود ويعمل بالكامل:
- **صفحة الطلبات:** `apps/mobile_flutter/lib/features/mobile_pages/mobile_requests_page.dart` (824 سطر)
- **صفحة التفاصيل:** `apps/mobile_flutter/lib/features/mobile_pages/mobile_request_detail_page.dart` (599 سطر)
- **عنوان الصفحة:** يتحول بين "طلباتي" (للموظف) و"طلبات الفريق" (للمدير/المسؤول) حسب `allowDecision`
- **تبويبان:** "الاجازات والطلبات" + "تكليفات العمل"

### 7.2 الانواع الستة المدعومة

كل نوع موجود في dropdown انشاء طلب جديد (سطر 267-289 من `mobile_requests_page.dart`):

#### 7.2.1 اجازة (`leave`)

| البند | التفصيل |
|---|---|
| الحقول | نوع الاجازة (اعتيادية/مرضية/عارضة/بدون راتب)، تاريخ البداية، تاريخ النهاية، البديل (اختياري من دليل الموظفين)، مرفقات (حتى 5 صور)، العنوان، السبب |
| مسار الموافقة | موظف ← المدير المباشر (`manager_id`) ← Operations ← المدير التنفيذي |
| التاثير | خصم من رصيد الاجازات (`myLeaveBalancesProvider`)؛ الاجازة العارضة `casual` تنفذ فوريا مع اشعار للمدير |
| Validation | عنوان ≥ 3 احرف، سبب ≥ 3 و ≤ 300 حرف، تاريخ النهاية ≥ البداية |

#### 7.2.2 مامورية (`mission`)

| البند | التفصيل |
|---|---|
| الحقول | تاريخ البداية، تاريخ النهاية، المكان/جهة التكليف (الزامي ≥ 2 حرف)، مرفقات، العنوان، السبب |
| مسار الموافقة | موظف ← المدير المباشر ← Operations ← المدير التنفيذي |
| التاثير | لا تُخصم من رصيد الاجازات ولا تُحتسب غيابا. تظهر في تبويب "تكليفات العمل" |

#### 7.2.3 قافلة/فاندي (`convoy`)

| البند | التفصيل |
|---|---|
| الحقول | تاريخ البداية، تاريخ النهاية، المكان/جهة التكليف، مرفقات، العنوان، السبب |
| مسار الموافقة | موظف ← المدير المباشر ← Operations ← المدير التنفيذي |
| التاثير | مثل المامورية: لا تُخصم من الرصيد ولا تُحتسب غيابا |

#### 7.2.4 اذن تاخر (`late_permit`)

| البند | التفصيل |
|---|---|
| الحقول | تاريخ الاذن، نوع الاذن (تاخير وصول)، عدد الدقائق (1-240)، العنوان، السبب |
| مسار الموافقة | موظف ← المدير المباشر ← Operations |
| التاثير | يمنع احتساب التاخر لذلك اليوم ضمن حدود الدقائق المعتمدة |

#### 7.2.5 اذن انصراف مبكر (`early_permit`)

| البند | التفصيل |
|---|---|
| الحقول | تاريخ الاذن، نوع الاذن (انصراف مبكر)، عدد الدقائق (1-240)، العنوان، السبب |
| مسار الموافقة | موظف ← المدير المباشر ← Operations |
| التاثير | يمنع احتساب الانصراف المبكر لذلك اليوم ضمن حدود الدقائق المعتمدة |

#### 7.2.6 تصحيح حضور (`attendance_correction`)

| البند | التفصيل |
|---|---|
| الحقول | العنوان، السبب (يُفصّل فيه: التاريخ، البصمة الناقصة، السبب) |
| مسار الموافقة | موظف ← المدير المباشر ← HR (يتحقق ويُعدّل السجل) ← Operations |
| التاثير | HR يضيف/يعدل حدث حضور يدويا بناء على الطلب المعتمد |

### 7.3 مسار الموافقة العام

```
[الموظف: ينشئ الطلب]
    ↓
[النظام: ينشئ خطوات الاعتماد حسب النوع]
    ↓
[إشعار push للمدير المباشر: "طلب جديد من الموظف X"]
    ↓
[المدير: يفتح الطلب ← يعتمد / يرفض / يُرجع للتعديل]
    ↓ اعتمد
[Operations: يراجع ← يعتمد / يرفض]
    ↓ اعتمد
[المدير التنفيذي: يعتمد نهائيا (للاجازات والماموريات)]
    ↓
[إشعار push للموظف: "تم اعتماد/رفض طلبك"]
```

**ملاحظات:**
- يستطيع الموظف سحب الطلب قبل اي قرار عبر زر "سحب الطلب قبل القرار" (سطر 200-210 من `mobile_request_detail_page.dart`)
- الرفض والارجاع يتطلبان سببا الزاميا ≥ 3 احرف
- الاعتماد يقبل ملاحظة اختيارية
- صفحة التفاصيل تعرض: مسار الاعتماد بالكامل مع ترقيم الخطوات، البديل والتعارضات، المرفقات، بيانات الطلب المهيكلة

### 7.4 الفجوات المطلوب سدها

| الفجوة | التفصيل |
|---|---|
| ربط `manager_id` | مسار الموافقة يعتمد على `manager_id` الذي سيُنفذ في بند 8 |
| التصعيد التلقائي | اذا لم يتخذ المدير قرارا خلال 48 ساعة، يصعد تلقائيا لـ Operations |
| تنبيه التعارض | عند انشاء اجازة، يُظهر تعارضات مع اجازات زملاء في نفس الفترة (موجود جزئيا: `request.conflicts`) |
| اشعار كل خطوة | push notification لكل تقدم في مسار الاعتماد |

### 7.5 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | موظف ينشئ طلب اجازة اعتيادية 3 ايام | الطلب يظهر بحالة `pending`، الرصيد يُحجز (reserved)، المدير يتلقى اشعارا |
| 2 | المدير يعتمد طلب اجازة | الخطوة تتقدم لـ Operations، الموظف يتلقى اشعارا بالتقدم |
| 3 | المدير يرفض طلب اجازة مع سبب | الطلب يتحول لـ `rejected`، الرصيد المحجوز يُفك، الموظف يتلقى اشعارا |
| 4 | المدير يُرجع الطلب للموظف للتعديل | الطلب يعود للموظف مع سبب الارجاع |
| 5 | الموظف يسحب الطلب قبل اي قرار | الطلب يتحول لـ `cancelled`، الرصيد المحجوز يُفك |
| 6 | موظف ينشئ اذن تاخر 90 دقيقة | الطلب يظهر بحقل "90 دقيقة" في بيانات الطلب |
| 7 | موظف ينشئ طلب مامورية بدون مكان | Validation يمنع الارسال: "حدد مكان او جهة التكليف" |
| 8 | موظف ينشئ اجازة عارضة (casual) | الطلب ينفذ فوريا مع اشعار للمدير (بدون انتظار موافقة) |
| 9 | بعد 48 ساعة بدون قرار من المدير | الطلب يصعد تلقائيا لـ Operations مع اشعار |
| 10 | المدير التنفيذي يعتمد نهائيا | الطلب يتحول لـ `approved`، الرصيد يُستهلك، السجل يُحدّث |

---

## 8. P0 -- ربط الموظف بالمدير

### 8.1 الوضع الحالي

عمود `manager_id` موجود في جدول `employees` منذ migration `0003_organization.sql` ويُستخدم في:
- تصفية الطلبات حسب الفريق (`0041_mobile_manager_and_executive_workspaces.sql`)
- تحديد نطاق KPI (`0058_official_kpi_governance.sql`)
- صفحة الهيكل التنظيمي (`0123_mobile_org_chart_rpc.sql`)
- تغيير المدير الآمن (`0084_secure_employee_manager_change.sql`)
- التصعيد والانابة (`0062_request_escalation_on_behalf.sql`)

**الفجوة:** لا توجد واجهة ويب مخصصة لتعيين/تغيير `manager_id`. العملية تتم حاليا عبر:
1. تعديل يدوي في لوحة Supabase
2. او عبر RPC `secure_change_employee_manager` (migration 0084)

### 8.2 ما يجب بناؤه

**صفحة ويب: "ربط المديرين"** ضمن `apps/admin_web/src/features/employees/`:

| العنصر | الوصف |
|---|---|
| قائمة الموظفين | تعرض كل موظف مع مديره الحالي (او "غير معين") |
| فلتر | بحث بالاسم + تصفية حسب القسم + تصفية "بدون مدير" |
| تعيين المدير | dropdown يعرض الموظفين المؤهلين (بدور Manager او اعلى) |
| تغيير المدير | يستدعي `secure_change_employee_manager` مع تسجيل السبب |
| تاريخ التغييرات | سجل لكل تغيير مدير مع التاريخ والسبب ومن نفذ التغيير |

### 8.3 القواعد

| # | القاعدة | التطبيق |
|---|---|---|
| 1 | HR فقط يعين المدير | RPC محمي بـ `current_is_full_access()` او صلاحية `assign_manager` |
| 2 | لا يكون الموظف مديرا لنفسه | check constraint: `manager_id != id` |
| 3 | لا حلقات دائرية | فحص في RPC: الموظف A لا يكون مديرا لـ B الذي هو مدير A |
| 4 | التغيير يسري فورا | تحديث `manager_id` يؤثر على الطلبات الجديدة وتقييمات KPI المفتوحة |
| 5 | المدير التنفيذي بدون مدير | `manager_id = NULL` مقبول للمدير التنفيذي فقط |

### 8.4 التاثير على الانظمة الاخرى

| النظام | التاثير |
|---|---|
| الطلبات (بند 7) | الطلبات الجديدة توجه للمدير المعين؛ الطلبات القديمة تبقى على مسارها |
| KPI (بند 9) | مرحلة "مراجعة المدير" توجه للمدير المعين وقت فتح الدورة |
| الهيكل التنظيمي | صفحة `org_chart_page.dart` تعكس العلاقة فورا |
| الاشعارات | اشعارات الفريق توجه للمدير الحالي |

### 8.5 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | HR يعين مديرا لموظف بدون مدير | `manager_id` يتحدث، الموظف يظهر في فريق المدير |
| 2 | HR يغير مدير موظف | المدير القديم لا يرى الموظف في فريقه، المدير الجديد يراه |
| 3 | محاولة تعيين موظف مديرا لنفسه | رفض مع خطا |
| 4 | محاولة انشاء حلقة دائرية (A→B→A) | رفض مع خطا |
| 5 | موظف عادي يحاول تغيير `manager_id` | رفض -- الصلاحية محصورة بـ HR/Main Admin |

---

## 9. P0 -- KPI الشهري

### 9.1 النظام الحالي

نظام KPI موجود ومبني بالكامل في:
- **قاعدة البيانات:** migration `0058_official_kpi_governance.sql` + تعديلات في 0077، 0101، 0106، 0108، 0130
- **صفحة الويب:** `apps/admin_web/src/features/performance/PerformancePage.tsx` + `KpiEvaluationEditor.tsx`
- **صفحة الموبايل:** `apps/mobile_flutter/lib/features/mobile_pages/kpi_evaluation_detail_page.dart` + `mobile_kpi_page.dart`
- **العقود المشتركة:** `packages/shared-contracts/` تحتوي على schemas لـ `KpiEvaluationForm` و `KpiEvaluationSummary`

### 9.2 من يُقيَّم؟

**كل موظف نشط عدا المدير التنفيذي.** المدير التنفيذي مستثنى من KPI والحضور الشخصي (migration `0137_v17_attendance_executive_exemption.sql`).

### 9.3 المسار الكامل بالتفصيل

```
الدورة الشهرية: يبدا يوم 1 من كل شهر ← يُغلق يوم 5 من الشهر التالي
```

#### المرحلة 1: التقييم الذاتي (`self`)

| البند | التفصيل |
|---|---|
| من يفعلها | الموظف نفسه |
| ماذا يفعل | 1) يحدث انجاز الاهداف (القيمة المحققة + مصدر الاثبات + الحالة) عبر dialog "تحديث الانجاز والادلة" (سطر 200-206 من `kpi_evaluation_detail_page.dart`)؛ 2) يعطي نفسه درجة على كل معيار عبر slider (سطر 393-441)؛ 3) يكتب ملاحظة عامة؛ 4) يضغط "حفظ وارسال" |
| الخرج | التقييم ينتقل لمرحلة `hr_review` |
| Workflow status | `OPEN_FOR_SELF_EVALUATION` → `EMPLOYEE_INPUT_IN_PROGRESS` → `SUBMITTED_TO_HR` |

#### المرحلة 2: مراجعة HR (`hr_review`)

| البند | التفصيل |
|---|---|
| من يفعلها | موظف الموارد البشرية |
| ماذا يفعل | 1) يراجع درجات الموظف الذاتية؛ 2) يُدخل بيانات الحضور (تُحسب تلقائيا: تاخير، انصراف مبكر، غياب، بصمة ناقصة، نقص ساعات ← درجة /20)؛ 3) يسجل الالتزام بالصلاة (العدد المطلوب/الفعلي/الاعذار/الملغي اداريا)؛ 4) يسجل حضور حلقة الشيخ وليد يوسف (نفس الحقول)؛ 5) يكتب ملاحظة؛ 6) يُرسل للمدير او يعيد للموظف |
| الخرج | التقييم ينتقل لمرحلة `manager_review`، او يعود لـ `self` مع سبب |
| ازرار HR | "تسجيل الالتزام بالصلاة" + "تسجيل حضور حلقة الشيخ وليد يوسف" (سطر 256-269) |
| Workflow status | `HR_DATA_PENDING` → `HR_EVALUATION_IN_PROGRESS` → `SUBMITTED_TO_DIRECT_MANAGER` |

#### المرحلة 3: مراجعة المدير المباشر (`manager_review`)

| البند | التفصيل |
|---|---|
| من يفعلها | المدير المباشر (`manager_id`) |
| ماذا يفعل | 1) يراجع كل الدرجات السابقة (ذاتي + HR)؛ 2) يعدل الدرجات على المعايير القابلة للتعديل عبر slider؛ 3) يسجل جلسة التقييم مع الموظف (حضوريا/عن بُعد، ملخص المناقشة، نقاط القوة، نقاط التحسين، اهداف الشهر القادم) -- سطر 216-222 "تسجيل جلسة الموظف والمدير"؛ 4) يكتب ملاحظة؛ 5) يضغط "اعتماد النتيجة وادراجها في التقرير" |
| الخرج | التقييم ينتقل لـ `finalized` (مدرج في التقرير الشهري) |
| خيار الارجاع | المدير يستطيع اعادة التقييم لمرحلة `hr_review` مع سبب (سطر 488-522) |
| Workflow status | `MANAGER_EVALUATION_IN_PROGRESS` → `SESSION_SCHEDULED` → `SESSION_COMPLETED` → `MANAGER_APPROVED` → `INCLUDED_IN_MONTHLY_REPORT` |

#### المرحلة 4: الاعتماد النهائي (السكرتير التنفيذي)

| البند | التفصيل |
|---|---|
| من يفعلها | السكرتير التنفيذي (Main Admin) |
| ماذا يفعل | يدير دورة KPI من لوحة الويب: فتح الدورة، متابعة التقدم، اغلاق الدورة، ارشفة النتائج |
| الصفحة | `apps/admin_web/src/features/advanced/KpiCyclesPage.tsx` |
| Workflow status | `FINAL_REVIEW` → `SENT_TO_EXECUTIVE_DIRECTOR` → `APPROVED` → `CLOSED` → `ARCHIVED` |

### 9.4 هيكل الدرجات

| المكون | الوزن | المصدر |
|---|---|---|
| الاهداف الشخصية | 40 درجة | الموظف يُدخل الانجاز، المدير يراجع |
| الحضور والانضباط | 20 درجة | محسوب تلقائيا من سجل الحضور |
| الصلاة | 10 درجات | HR يُدخل يدويا |
| حلقة الشيخ | 10 درجات | HR يُدخل يدويا |
| معايير اخرى (جودة العمل، روح الفريق، المبادرة...) | 20 درجة | الموظف + المدير |
| **الاجمالي** | **100 درجة** | |

### 9.5 اصلاحات الواجهة المطلوبة

| الملف | المشكلة | الاصلاح |
|---|---|---|
| `KpiEvaluationEditor.tsx` | النموذج طويل جدا (810 سطر) بدون تقسيم | تقسيم الى tabs او accordion: الاهداف / المعايير / الحضور / الالتزام / الجلسة |
| `PerformancePage.tsx` | لا يعرض مؤشرات المراحل المتاخرة | اضافة بطاقة تحذير للتقييمات المتاخرة عن الموعد (workflow_status = `OVERDUE`) |
| `kpi_evaluation_detail_page.dart` | لا يعرض تقدم الموظف في المراحل بشكل مرئي | اضافة stepper افقي يُظهر المراحل (ذاتي ← HR ← مدير ← معتمد) |

### 9.6 الاشعارات

| الحدث | المستلم | المحتوى |
|---|---|---|
| فتح الدورة | كل الموظفين | "تم فتح دورة KPI لشهر يوليو -- ابدا تقييمك الذاتي" |
| الموظف ارسل التقييم الذاتي | HR | "الموظف X ارسل تقييمه الذاتي لشهر يوليو" |
| HR ارسل لللمدير | المدير المباشر | "تقييم الموظف X جاهز لمراجعتك" |
| المدير اعتمد | الموظف | "تم اعتماد تقييمك لشهر يوليو -- النتيجة: 85%" |
| ارجاع لمرحلة سابقة | المرحلة السابقة | "تم ارجاع تقييم X -- السبب: ..." |
| تاخر عن الموعد | صاحب المرحلة | "تقييم X متاخر 3 ايام -- يرجى المتابعة" |

### 9.7 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | موظف يفتح تقييمه في مرحلة `self` ويعدل درجة ويحفظ ويُرسل | التقييم ينتقل لـ `hr_review`، HR يتلقى اشعارا |
| 2 | HR يُدخل بيانات الصلاة والحلقة ويُرسل للمدير | التقييم ينتقل لـ `manager_review` |
| 3 | المدير يسجل جلسة ويعتمد النتيجة | التقييم ينتقل لـ `finalized`، الموظف يتلقى اشعارا بالنتيجة |
| 4 | المدير يعيد التقييم لـ HR مع سبب | التقييم يعود لـ `hr_review`، HR يتلقى اشعارا مع السبب |
| 5 | HR يعيد التقييم للموظف مع سبب | التقييم يعود لـ `self`، الموظف يتلقى اشعارا مع السبب |
| 6 | تقييم يتاخر 5 ايام عن الموعد | اشعار تذكيري يُرسل لصاحب المرحلة |
| 7 | المدير التنفيذي ليس لديه تقييم KPI | صفحة KPI لا تعرض اي تقييم للتنفيذي |
| 8 | الموظف يحاول تعديل درجة في مرحلة ليست مرحلته | الـ slider معطل والصفحة تعرض "للعرض فقط" |

---

## 10. P0 -- طلب الموقع المباشر

### 10.1 السياسة

**موقع فقط بدون فيديو.** تم تعطيل الفيديو نهائيا في V17 (تعليق في `location_incoming_overlay.dart` سطر 5: `// V17 §9: video_verification_page removed — video permanently disabled`). Edge Function `live-location-video-url` موجودة لكنها مُعطلة ولن تُفعَّل.

### 10.2 المُرسل

**المدير التنفيذي فقط.** صفحة طلب الموقع تظهر حصريا في مساحة عمل التنفيذي (`executive_location_page.dart`). لا يستطيع اي دور آخر ارسال طلب موقع.

### 10.3 الرحلة الكاملة

```
[التنفيذي: يفتح "المتابعة الميدانية" ← تبويب "طلب الموقع"]
    ↓
[يبحث عن الموظف بالاسم او الكود في `_LocationDirectoryTab`]
    ↓
[يضغط "طلب موقع فوري" ← RPC `requestLocation(employeeId, reason)`]
    ↓
[النظام: ينشئ سجل في `location_requests` بحالة `pending`]
[النظام: يُلغي اي طلب نشط سابق لنفس الموظف تلقائيا (migration 0071)]
[النظام: يُرسل push notification عاجل للموظف عبر `notification-dispatcher`]
    ↓
[الموظف: يتلقى اشعار push عاجل + اهتزاز متكرر]
[التطبيق: يعرض `LocationIncomingOverlay` فوق كل شيء (fullscreen, canPop: false)]
    ↓
[الشاشة المنبثقة تعرض:]
  - شريط طوارئ احمر: "طلب موقع عاجل من الادارة"
  - ايقونة نابضة (pulse animation)
  - اسم الطالب: "${requesterName} يطلب التحقق من موقعك الآن"
  - نوع الطلب: "لقطة موقع فورية" / "تتبع X دقائق"
  - زر "ارسل موقعي الآن" (احمر كبير)
  - زر "رفض الطلب" (شفاف صغير)
    ↓
[الموظف يضغط "ارسل موقعي الآن"]
    ↓
[التطبيق: يستدعي respondLocation(requestId, true) ← يقبل الطلب]
[التطبيق: يقرا GPS ← يعرض مراحل التقدم:]
  - "جاري قبول الطلب..."
  - "جاري تحديد الموقع..."
  - "جاري تحويل الاحداثيات لعنوان..."
  - "جاري ارسال الموقع..."
[التطبيق: يُرسل submitLocationPoint مع الاحداثيات + عنوان Google Maps]
    ↓
[النظام: يحفظ الموقع في `employee_locations` + يُحدّث `location_requests`]
    ↓
[التطبيق: يُوقف المنبه العاجل + يُغلق الشاشة المنبثقة]
    ↓
[التنفيذي: يرى الموقع المُحدّث في بطاقة الموظف:]
  - "آخر موقع: 25 يوليو - 2:30 م"
  - "دقة 15 متر"
  - زر "افتح الخريطة" → Google Maps
```

### 10.4 الصفحات الموجودة

| الصفحة | الملف | الوظيفة |
|---|---|---|
| `ExecutiveLocationPage` | `executive_location_page.dart` (378 سطر) | تبويبان: "حضور اليوم" + "طلب الموقع". تبويب الموقع يعرض دليل الموظفين مع بحث وزر "طلب موقع فوري" لكل موظف |
| `ExecutiveAttendanceTab` | `executive_attendance_tab.dart` (298 سطر) | حالة حضور كل موظف اليوم: شريط ملخص (حضر/متاخر/غائب/مامورية/اجازة) + بطاقة لكل موظف |
| `LocationIncomingOverlay` | `location_incoming_overlay.dart` (564 سطر) | الشاشة المنبثقة العاجلة: خلفية سوداء، ايقونة نابضة، اهتزاز، ازرار قبول/رفض |
| `LocationIncomingListener` | في نفس الملف (سطر 526-563) | مستمع يراقب `pendingIncomingLocationRequestProvider` ويعرض الشاشة المنبثقة عند ورود طلب |
| `LocationRequestsPage` | `location_requests_page.dart` | صفحة سجل طلبات الموقع |
| `LiveTrackingSessionPage` | `live_tracking_session_page.dart` | صفحة التتبع المباشر (track_5/10/15/30) |

### 10.5 انواع الطلب

```dart
'snapshot'       → 'لقطة موقع فورية'     // موقع واحد فوري
'video_5s'       → 'موقع فقط'            // كان فيديو، الآن موقع فقط
'location_video' → 'موقع فقط'            // كان فيديو، الآن موقع فقط
'track_5'        → 'تتبع 5 دقائق'        // ارسال موقع كل 30 ثانية لمدة 5 دقائق
'track_10'       → 'تتبع 10 دقائق'
'track_15'       → 'تتبع 15 دقيقة'
'track_30'       → 'تتبع 30 دقيقة'
```

### 10.6 `live-location-video-url` -- مُعطلة

Edge Function `live-location-video-url` موجودة في `supabase/functions/live-location-video-url/` لكنها **مُعطلة ولن تُستدعى**. اي طلب بنوع `video_5s` او `location_video` يُعامل كـ `snapshot` (موقع فقط). لا حاجة لحذف الدالة -- يكفي عدم استدعائها.

### 10.7 معالجة مشاكل GPS

الشاشة المنبثقة (`LocationIncomingOverlay`) تعالج 3 انواع مشاكل GPS:

| المشكلة | الزر المعروض | السلوك |
|---|---|---|
| GPS مغلق (`GpsDisabledException`) | "فتح اعدادات الموقع" ← `Geolocator.openLocationSettings()` | عند العودة: فحص تلقائي + اعادة الارسال |
| صلاحية مرفوضة نهائيا (`deniedForever`) | "فتح اعدادات التطبيق" ← `Geolocator.openAppSettings()` | عند العودة: فحص تلقائي + اعادة الارسال |
| صلاحية مرفوضة (قابلة للطلب) | "منح صلاحية الموقع" ← `Geolocator.requestPermission()` | اذا مُنحت: ارسال فوري |

### 10.8 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | التنفيذي يطلب موقع موظف | الموظف يتلقى اشعارا عاجلا + شاشة منبثقة |
| 2 | الموظف يضغط "ارسل موقعي" | الموقع يُرسل، التنفيذي يرى الاحداثيات + زر "افتح الخريطة" |
| 3 | الموظف يرفض الطلب | الطلب يتحول لـ `rejected`، التنفيذي يرى الرفض |
| 4 | التنفيذي يطلب موقعا ثانيا لنفس الموظف قبل الرد | الطلب الاول يُلغى تلقائيا، الثاني يُرسل |
| 5 | الموظف يقبل لكن GPS مغلق | تظهر رسالة خطا + زر "فتح اعدادات الموقع"، عند التفعيل يعاد الارسال تلقائيا |
| 6 | التنفيذي يضغط "طلب موقع فوري" ثم يضغط مرة اخرى خلال 30 ثانية | الزر معطل مع عداد "انتظر X ثانية" (cooldown 30 ثانية) |

---

## 11. P0 -- التقرير التنفيذي اليومي

### 11.1 المحتوى

التقرير التنفيذي اليومي يُعرض عبر `ExecutiveBriefPage` ويحتوي على:

| القسم | المحتوى |
|---|---|
| بانر الفترة | صباحي (قبل 15:00) / مسائي (بعد 15:00) مع تاريخ اليوم |
| العنوان الرئيسي | عدد الاجراءات العاجلة او "لا توجد اجراءات حرجة" |
| الحضور مقارنة بامس | حضور اليوم vs امس (سهم اخضر/احمر)، تاخير اليوم vs امس |
| مؤشرات سريعة | غياب اليوم، اجازات اليوم، اعتمادات معلقة، تقارير جاهزة |
| تقرير التشغيل الكامل | 12 مؤشر (انظر 11.2) |
| ما يحتاج انتباهك | اهم 5 تنبيهات مرتبة حسب الاثر والمهلة |
| المصدر والوقت | مصدر البيانات + وقت التوليد |

### 11.2 تقرير التشغيل اليومي -- 12 مؤشرا

يُعرض في `ExecutiveBriefPage` ضمن `MetricGrid` (سطر 227-242):

| # | المؤشر | المصدر | الايقونة |
|---|---|---|---|
| 1 | الموظفون النشطون | `dailyReport.employees.active` | groups |
| 2 | المطلوب حضورهم | `dailyReport.employees.requiredToday` | badge |
| 3 | لم يسجلوا بعد | `dailyReport.attendance.notYet` | hourglass_top |
| 4 | لم يسجلوا الانصراف | `dailyReport.attendance.missingCheckout` | logout |
| 5 | ماموريات | `dailyReport.workStatus.missions` | work_history |
| 6 | قوافل | `dailyReport.workStatus.convoys` | directions_bus |
| 7 | فاندي | `dailyReport.workStatus.fundraising` | volunteer_activism |
| 8 | KPI عند الموظف | `dailyReport.kpi.atEmployee` | person |
| 9 | KPI عند المدير | `dailyReport.kpi.atManager` | supervisor_account |
| 10 | KPI عند HR | `dailyReport.kpi.atHr` | fact_check |
| 11 | تقارير KPI جاهزة | `dailyReport.kpi.ready` | analytics |
| 12 | طلبات موقع بلا رد | `dailyReport.followUp.unansweredLocationRequests` | location_searching |

### 11.3 الصفحات التنفيذية -- 14 صفحة

كل الصفحات التالية موجودة ومبنية في `apps/mobile_flutter/lib/features/mobile_pages/`:

#### 11.3.1 `executive_home_page.dart` -- الصفحة الرئيسية

| ماذا تعرض |
|---|
| بانر "الملخص التنفيذي" مع تدرج لوني وشعار الجمعية |
| 3 روابط سريعة: "ملخص اليوم" (ExecutiveBriefPage) + "الموظفون" (ExecutivePeoplePage) + "اصدار قرارات" (ExecutiveDecisionsPage) |
| 6 مؤشرات: عاجل الآن، اعتمادات، تقارير KPI، قرارات منشورة، قضايا مفتوحة، طلبات موقع |
| بوصلة القرار: ترتيب مقترح (اجراءات عاجلة ← اعتمادات ← تقارير KPI) |
| بطاقة "مساحة تنفيذية مستقلة": لا بصمة شخصية، لا ارسال موقع |

#### 11.3.2 `executive_brief_page.dart` -- الملخص التنفيذي اليومي

| ماذا تعرض |
|---|
| تبديل صباحي/مسائي (`SegmentedButton`) |
| حضور اليوم vs امس (بطاقتا مقارنة) |
| 4 مؤشرات سريعة (غياب، اجازات، اعتمادات، تقارير) |
| 12 مؤشر تشغيلي كامل |
| اهم 5 تنبيهات (severity: critical/high/normal + kind: incident/risk/kpi/report/attendance) |
| مصدر البيانات ووقت التوليد |

#### 11.3.3 `executive_attendance_tab.dart` -- تبويب حضور اليوم

| ماذا تعرض |
|---|
| شريط ملخص: الاجمالي / حضر / متاخر / غائب / مامورية / اجازة / جزئي |
| بطاقة لكل موظف: الاسم، المسمى الوظيفي، القسم، وقت الدخول، دقائق التاخر، آخر موقع |
| لون الحالة: اخضر (حاضر)، برتقالي (متاخر)، احمر (غائب)، بنفسجي (مامورية)، ازرق (اجازة) |

#### 11.3.4 `executive_people_page.dart` -- الموظفون

| ماذا تعرض |
|---|
| دليل الموظفين مع بحث وتصفية |
| بطاقة لكل موظف: الاسم، الكود، القسم، المسمى، الحالة |
| الضغط يفتح `ExecutiveEmployeeSummaryPage` |

#### 11.3.5 `executive_employee_summary_page.dart` -- ملخص الموظف

| ماذا تعرض |
|---|
| بيانات الموظف الاساسية |
| ملخص الحضور (حاضر/متاخر/غائب) |
| آخر تقييم KPI ونتيجته |
| آخر موقع مسجل |
| القرارات والجزاءات السابقة |

#### 11.3.6 `executive_location_page.dart` -- المتابعة الميدانية

| ماذا تعرض |
|---|
| تبويبان: "حضور اليوم" (ExecutiveAttendanceTab) + "طلب الموقع" (دليل الموظفين مع زر "طلب موقع فوري") |
| بطاقة كل موظف في تبويب الموقع: الاسم، الكود، آخر موقع، الدقة، حالة الطلب النشط، زر "افتح الخريطة" |

#### 11.3.7 `executive_decisions_page.dart` -- اصدار قرارات

| ماذا تعرض |
|---|
| انشاء قرار اداري جديد (عنوان، نص، النوع، الموظفين المعنيين) |
| قائمة القرارات السابقة مع حالاتها |
| القرارات المنشورة تُرسل كاشعارات للموظفين المعنيين |

#### 11.3.8 `executive_disputes_page.dart` -- لجنة التحقيقات

| ماذا تعرض |
|---|
| القضايا المفتوحة والمغلقة |
| تفاصيل كل قضية: المشتكي، المشتكى عليه، الوقائع، القرار |
| ازرار اتخاذ القرار (جزاء، انذار، براءة) |

#### 11.3.9 `executive_governance_page.dart` -- الحوكمة

| ماذا تعرض |
|---|
| سياسات الجمعية النشطة |
| مؤشرات الامتثال |
| اللوائح والاجراءات |

#### 11.3.10 `executive_reports_page.dart` -- التقارير التنفيذية

| ماذا تعرض |
|---|
| التقارير الدورية المولدة تلقائيا |
| تقارير KPI الشهرية المجمعة |
| تقارير الحضور الاسبوعية |

#### 11.3.11 `executive_risk_center_page.dart` -- مركز المخاطر

| ماذا تعرض |
|---|
| المخاطر التشغيلية النشطة |
| الحوادث والتنبيهات |
| مستوى الخطورة (critical/high/medium/low) |
| اجراءات التخفيف المقترحة |

#### 11.3.12 `executive_emergency_page.dart` -- وضع الاستجابة السريعة

| ماذا تعرض |
|---|
| بانر طوارئ احمر |
| اجراءات عاجلة + اعتمادات معلقة + طلبات موقع بلا رد (من `executiveDashboardProvider` + `mobileExecutiveCommandCenterProvider`) |
| روابط مباشرة لـ: مركز المخاطر، صندوق الاجراءات، المتابعة الميدانية |
| مصمم للاستخدام السريع في الطوارئ بدون تصفح |

#### 11.3.13 صفحات مشتركة تظهر للتنفيذي

| الصفحة | الوظيفة |
|---|---|
| `mobile_action_inbox_page.dart` | صندوق الاجراءات -- كل ما يحتاج قرارا |
| `mobile_daily_reports_page.dart` | التقارير اليومية المفصلة |

### 11.4 اختبارات القبول

| # | الاختبار | المتوقع |
|---|---|---|
| 1 | التنفيذي يفتح الملخص الصباحي | يعرض بيانات اليوم مع مقارنة بامس، الفترة = "صباحي" |
| 2 | التنفيذي يبدل للملخص المسائي | البيانات تتحدث مع اعداد نهاية اليوم |
| 3 | يوجد 3 موظفين متاخرين | تظهر بطاقة تنبيه بخطورة عالية في "ما يحتاج انتباهك" |
| 4 | لا توجد اجراءات عاجلة | العنوان = "لا توجد اجراءات حرجة بمهلة قصيرة الآن" |
| 5 | التنفيذي يفتح "حضور اليوم" | يعرض شريط ملخص + بطاقة لكل موظف بحالته ولون مميز |
| 6 | التنفيذي يفتح "وضع الاستجابة السريعة" | يعرض المؤشرات العاجلة + روابط مباشرة بدون تصفح |
| 7 | التنفيذي يضغط على تنبيه نوع "risk" | ينتقل لصفحة مركز المخاطر |
| 8 | التنفيذي يسحب الصفحة لاسفل (pull-to-refresh) | البيانات تتحدث مع وقت توليد جديد |

---

Now I have a comprehensive understanding of the codebase. Let me compile the P1 section.

---

## P1 — الأنظمة الأساسية (V18)

> الأقسام 12–17 تُغطي الوظائف التشغيلية اليومية التي يعتمد عليها كل مستخدم.
> كل قسم يبدأ بتوصيف الوضع الحالي الفعلي (ملفات + migrations)، ثم المواصفة المطلوبة، ثم خطة الاختبار.

---

### 12. ملف الموظف الكامل (Employee 360)

#### 12.1 الوضع الحالي

| العنصر | الملف / Migration | الحالة |
|---|---|---|
| مخطط Zod | `packages/shared-contracts/src/employee.ts` — `employee360Schema` | مكتمل: 37 حقلاً + 4 مصفوفات فرعية |
| صفحة الويب | `apps/admin_web/src/features/employees/EmployeeDetailPage.tsx` (518 سطر) | مكتمل: 6 أقسام (بطاقة رأسية + 4 MetricCards + بيانات وظيفية + مستندات وعهد + طلبات + مهام + كشف شهري) |
| RPC الجلب | `get_employee_360` (mig 0129) | مكتمل |
| RPC التعديل | `update_employee_admin` (mig 0129) — JSONB patch + audit trail + سبب التعديل | مكتمل |
| نموذج التعديل | `EditEmployeeDialog` داخل EmployeeDetailPage — حقول شخصية (الاسم/الهاتف) + حقول حساسة (إدارة/فريق/فرع/موقع/مسمى/منصب/درجة/نوع توظيف/تاريخ تعيين/عقد/اختبار/حالة) | مكتمل |
| تغيير المدير | `ChangeManagerDialog` + RPC `change_employee_manager_admin` (mig 0084) | مكتمل |
| أرشفة الموظف | `ArchiveEmployeeDialog` + RPC `archive_employee_secure` | مكتمل |
| إعادة إرسال الدعوة | `useResendInvite` → Edge Function `admin-resend-invite` | مكتمل |
| Lookups تسلسلية | `useOrganizationLookups.ts` — إدارات/فرق/فروع/مواقع/مسميات/مناصب/درجات/أنواع توظيف مع تبعية أب-ابن | مكتمل |
| قائمة الموظفين | `EmployeesPage.tsx` + `useEmployees.ts` → RPC `get_employees_enriched` (بحث + فلتر حالة + حد 500) | مكتمل |
| إنشاء موظف | `CreateEmployeePage.tsx` → Edge Function `admin-create-employee` | مكتمل |
| اختبارات pgTAP | `0052_employee_edit_enrichment.sql` + `0051_provision_employee_record.sql` + `0043_employee_archive_delete_contract.sql` | مكتمل |

#### 12.2 الحقول المعتمدة

**البيانات الشخصية** (صلاحية `people.employee.update_basic`):

| الحقل | النوع | إلزامي | ملاحظة |
|---|---|---|---|
| `fullNameAr` | text | نعم | 3–160 حرف |
| `fullNameEn` | text | لا | 160 حرف |
| `phoneE164` | text | لا | صيغة `+201XXXXXXXXX` |
| `photoUrl` | text | لا | URL صورة |

**البيانات الوظيفية** (صلاحية `people.employee.update_sensitive`):

| الحقل | النوع | إلزامي | Lookup |
|---|---|---|---|
| `departmentId` | uuid FK | لا | `departments` |
| `teamId` | uuid FK | لا | `teams` (يتبع الإدارة) |
| `branchId` | uuid FK | لا | `branches` |
| `workSiteId` | uuid FK | لا | `work_sites` (يتبع الفرع) |
| `jobTitleId` | uuid FK | لا | `job_titles` |
| `positionId` | uuid FK | لا | `positions` (يتبع الإدارة) |
| `gradeId` | uuid FK | لا | `grades` |
| `employmentTypeId` | uuid FK | لا | `employment_types` |
| `hireDate` | date | لا | — |
| `contractEnd` | date | لا | — |
| `probationEnd` | date | لا | — |
| `status` | enum | نعم | 9 حالات: draft, invited, onboarding, active, suspended, notice_period, terminated, archived, probation_failed |

**بيانات مجمّعة (للقراءة فقط):**

| القسم | المصدر |
|---|---|
| حضور 30 يومًا (present/lateDays/absent/workMinutes) | `attendance_daily` |
| عدادات الطلبات (pending/approved/rejected) | `requests` |
| أحدث تقييم KPI (score/rating/stage) | `kpi_evaluations` |
| المستندات (5 أحدث) + العهد القائمة | `employee_documents` + `employee_assets` |
| أحدث الطلبات + المهام | `requests` + `tasks` |
| العلاقة الإدارية (مدير + مرؤوسون + أدوار) | `employees.manager_id` + `user_roles` |

#### 12.3 مصفوفة صلاحيات التعديل

| العملية | Main Admin | HR Manager | HR Specialist | Operations | Manager | Executive | Employee |
|---|---|---|---|---|---|---|---|
| عرض ملف 360 | الكل | الكل | الكل | إدارته | مرؤوسوه | الكل | نفسه |
| تعديل بيانات شخصية | نعم | نعم | نعم | لا | لا | لا | لا |
| تعديل بيانات وظيفية | نعم | نعم | لا | لا | لا | لا | لا |
| تغيير المدير المباشر | نعم | نعم | لا | لا | لا | لا | لا |
| أرشفة الموظف | نعم | نعم | لا | لا | لا | لا | لا |
| إعادة إرسال دعوة التفعيل | نعم | نعم | نعم | لا | لا | لا | لا |
| عرض كشف الحضور الشهري | نعم | نعم | نعم | إدارته | مرؤوسوه | الكل | نفسه |

#### 12.4 تبويبات EmployeeDetailPage (8 أقسام)

الصفحة الحالية تعرض المحتوى في أقسام متتالية (وليس tabs). المطلوب في V18:

| # | التبويب | المحتوى الحالي | المطلوب V18 |
|---|---|---|---|
| 1 | **نظرة عامة** | بطاقة رأسية + MetricCards + علاقة إدارية | موجود — لا تغيير |
| 2 | **البيانات الوظيفية** | position/grade/branch/workSite/hireDate/contractEnd | موجود — إضافة حقول: employmentType، email الحساب، تاريخ آخر ترقية |
| 3 | **الحضور** | كشف شهري مدمج (`MonthlyStatementSection`) | موجود — لا تغيير |
| 4 | **الطلبات** | أحدث 5 طلبات | موجود — إضافة فلتر نوع/حالة + ترقيم صفحات |
| 5 | **الأداء (KPI)** | أحدث تقييم فقط (MetricCard) | توسيع: عرض آخر 6 تقييمات + رسم بياني خطي للدرجة |
| 6 | **المستندات والعهد** | أحدث 5 مستندات + عهد قائمة | موجود — لا تغيير |
| 7 | **المهام** | أحدث المهام | موجود — لا تغيير |
| 8 | **الجهاز والأمان** | غير موجود | **جديد**: أجهزة موثوقة + Passkeys + جلسات نشطة + سجل تسجيل الدخول |

#### 12.5 الاختبارات

| الملف | النطاق | العدد |
|---|---|---|
| `supabase/tests/0052_employee_edit_enrichment.sql` | update_employee_admin + get_employee_360 + get_employees_enriched | موجود |
| `supabase/tests/0051_provision_employee_record.sql` | إنشاء موظف + ربط حساب + صلاحيات | موجود |
| `supabase/tests/0043_employee_archive_delete_contract.sql` | أرشفة + حذف + سحب جلسات | موجود |
| **جديد**: Web component test | `EmployeeDetailPage.test.tsx` — عرض mock 360 + tabs switching + edit dialog | مطلوب |

---

### 13. لجنة حل المشكلات والخلافات

#### 13.1 الوضع الحالي

| العنصر | الملف / Migration | الحالة |
|---|---|---|
| جدول `dispute_cases` | mig 0008 + 0030 + 0059 + 0064 + 0131 + 0141 | مكتمل — 20 حالة + 13 عمود إجراء إداري |
| جداول مساندة | `dispute_parties` + `committee_meetings` + `committee_decisions` + `committee_members` + `dispute_evidence` + `dispute_appeals` | مكتمل |
| صفحة الموظف (موبايل) | `mobile_disputes_page.dart` (831 سطر) | مكتمل: قائمة قضاياي + قرارات + اعتراضات + نموذج تقديم كامل |
| صفحة التنفيذي (موبايل) | `executive_disputes_page.dart` (720 سطر) | مكتمل: صندوق وارد إداري (تتطلب قرارك / بانتظار التنفيذ / تم التنفيذ) + نموذج قرار |
| RPC العمليات | `get_dispute_operations_catalog` (mig 0141) | مكتمل |
| RPC الموظف | `get_my_dispute_portal` (mig 0059) | مكتمل |
| RPC التقديم | `submit_dispute` + `cancel_dispute` + `appeal_dispute_decision` | مكتمل |
| RPC الإجراء الإداري | `propose_admin_action` + `decide_admin_action` + `execute_admin_action` (mig 0131) | مكتمل |
| صلاحيات | `disputes.admin_action.propose` / `.decide` / `.execute` + `disputes.case.manage` + `disputes.portal.access` | مكتمل (0138 أصلحت `.decide` للمدير التنفيذي) |
| اختبار pgTAP | `0054_v17_dispute_admin_actions.sql` + `0037_dispute_committee_runtime.sql` + `0018_dispute_committee_contract.sql` | مكتمل |

#### 13.2 نموذج تقديم الشكوى (المبسّط)

النموذج الحالي في `_NewDisputeForm` يطلب:

| الحقل | النوع | إلزامي | القيد |
|---|---|---|---|
| عنوان واضح | text | نعم | 3 أحرف على الأقل |
| التفاصيل | textarea | نعم | 3–300 حرف (مع عداد أحرف) |
| نوع الشكوى | select | نعم | 12 نوعًا: `employee_conflict`, `inappropriate_conduct`, `verbal_abuse`, `management_chain`, `direct_manager`, `department_conflict`, `misunderstanding`, `work_environment`, `donor_beneficiary`, `administrative_violation`, `agreement_breach`, `other` |
| الأولوية | select | نعم | `normal` / `urgent` |
| الأطراف المعنية | اختيار من دليل الموظفين | نعم | طرف واحد على الأقل |
| الشهود | اختيار من الدليل | لا | — |
| مكان الواقعة | text | لا | — |
| ما تطلبه من اللجنة | textarea | لا | — |
| مرفقات/أدلة | صور (ImagePicker) | لا | حد 5 مرفقات، 15 MB لكل مرفق |
| إقرار بصحة المعلومات | checkbox | نعم | — |
| إقرار بسرية الإجراءات | checkbox | نعم | — |

**ملاحظة V18:** الحد الحالي 300 **حرف** (وليس كلمة). القيد يُفرض في mig 0135 (`v17_word_count_checks`) على مستوى الـ DB أيضًا. المطلوب: توحيد القيد ليكون 3–300 **كلمة** (وليس حرف) في كل من: Flutter validator + DB check constraint + مخطط Zod.

#### 13.3 مسار الحالات الكامل (10 مراحل)

```
مسودة (draft)
  ↓ تقديم الموظف
مقدمة (submitted)
  ↓ مقرر اللجنة يقبل
مقبولة — قيد المراجعة (accepted / under_review)
  ↓ طلب معلومات إضافية (اختياري)
معلومات إضافية (needs_more_information)
  ↓ الموظف يستكمل
قيد المراجعة (under_review)
  ↓ جلسة لجنة
جلسة لجنة (session_scheduled → session_completed → committee_deliberation)
  ↓ دراسة اللجنة
اقتراح إجراء (action_proposed)
  ↓ المدير التنفيذي يقرر (approved / modified / rejected / deferred)
معتمد أو مرفوض (pending_execution أو returned_to_committee)
  ↓ HR ينفذ
تم التنفيذ (executed → closed)
```

**الحالات الكاملة في DB:** `draft`, `submitted`, `needs_more_information`, `accepted`, `rejected`, `under_review`, `waiting_for_respondent`, `waiting_for_witness`, `session_scheduled`, `session_completed`, `committee_deliberation`, `settlement_pending`, `escalated_to_executive`, `returned_to_committee`, `decision_issued`, `action_proposed`, `pending_execution`, `executed`, `closed`, `reopened`, `cancelled_by_employee`.

#### 13.4 شاشة المدير التنفيذي

`ExecutiveDisputesPage` تعرض 3 أقسام:

1. **تتطلب قرارك** (`awaitingDecision`) — بطاقات مع الإجراء المقترح + اسم المقترح + درجة الخطورة → نموذج قرار سفلي (4 خيارات: اعتماد / تعديل واعتماد / رفض / تأجيل + سبب إلزامي).
2. **بانتظار التنفيذ** (`pendingExecution`) — متابعة ما اعتمده.
3. **تم التنفيذ** (`recentlyExecuted`) — أرشيف 30 يومًا.

شرائح عدادات أعلى الصفحة: عدد كل فئة.

#### 13.5 دور HR في التنفيذ

عند حالة `pending_execution`، يستخدم HR الـ RPC `execute_admin_action` مع:
- `p_case_id` — معرف القضية
- `p_execution_notes` — ملاحظات التنفيذ
يتحقق من صلاحية `disputes.admin_action.execute` (ممنوحة لـ `hr-manager` + `hr-specialist`).

#### 13.6 صلاحيات اللجنة

| العملية | Main Admin | Executive | Secretary | Committee Chair | HR Manager | HR Specialist | Employee |
|---|---|---|---|---|---|---|---|
| تقديم شكوى | — | — | — | — | — | — | نعم (portal) |
| إلغاء قبل القبول | — | — | — | — | — | — | نعم (مالك الشكوى) |
| قراءة كل القضايا | نعم | نعم | نعم | نعم | نعم | لا | قضاياه فقط |
| قبول/رفض شكوى | نعم | — | نعم | نعم | — | — | — |
| اقتراح إجراء إداري | — | — | نعم | نعم | — | — | — |
| اتخاذ قرار تنفيذي | — | نعم | — | — | — | — | — |
| تنفيذ الإجراء | نعم | — | — | — | نعم | نعم | — |
| تقديم اعتراض | — | — | — | — | — | — | نعم (على قرار صادر) |

#### 13.7 الاختبارات

| الملف | العدد | النطاق |
|---|---|---|
| `supabase/tests/0054_v17_dispute_admin_actions.sql` | موجود | propose + decide + execute + permission matrix |
| `supabase/tests/0037_dispute_committee_runtime.sql` | موجود | lifecycle كامل: submit → accept → session → decision |
| `supabase/tests/0018_dispute_committee_contract.sql` | موجود | schema + RLS + quorum |
| `supabase/tests/0058_v17_word_count_checks.sql` | موجود | تحقق طول الوصف |

---

### 14. كشف الحضور الشهري

#### 14.1 الوضع الحالي

| العنصر | الملف | الحالة |
|---|---|---|
| Migration | `0127_monthly_attendance_statement.sql` | مكتمل — RPC `_build_attendance_statement` (server-side بتوقيت Cairo) |
| RPC عام | `get_employee_monthly_statement(p_employee_id, p_year, p_month)` | مكتمل — يتطلب صلاحية |
| RPC شخصي | `get_my_monthly_statement(p_year, p_month)` | مكتمل — الموظف لنفسه |
| ويب | `apps/admin_web/src/features/attendance/MonthlyStatementSection.tsx` (91 سطر) | مكتمل — مدمج داخل EmployeeDetailPage |
| ويب Hook | `useMonthlyStatement.ts` → `useEmployeeMonthlyStatement(employeeId, year, month)` | مكتمل |
| موبايل | `monthly_attendance_statement_page.dart` (218 سطر) | مكتمل — صفحة مستقلة للموظف |
| مخطط Zod | `AttendanceStatement` في shared-contracts | مكتمل |
| اختبار pgTAP | `supabase/tests/0050_monthly_attendance_statement.sql` | مكتمل |

#### 14.2 محتوى الكشف

**الملخص (summary):**

| الحقل | الوصف |
|---|---|
| `scheduledDays` | أيام العمل المجدولة |
| `presentDays` | أيام الحضور الفعلي |
| `absentDays` | أيام الغياب |
| `leaveDays` | أيام الإجازات المعتمدة |
| `missionDays` | أيام المأموريات |
| `convoyFundiDays` | أيام القوافل/الفاندي |
| `totalWorkHours` | إجمالي ساعات العمل |
| `averageWorkHours` | متوسط ساعات العمل اليومي |
| `totalLateMinutes` | إجمالي دقائق التأخير |
| `totalEarlyLeaveMinutes` | إجمالي دقائق الخروج المبكر |
| `missingCheckInCount` | مرات نسيان ختم الحضور |
| `missingCheckOutCount` | مرات نسيان ختم الانصراف |
| `correctionCount` | عدد التصحيحات |

**الجدول اليومي (days):**

| العمود | الوصف |
|---|---|
| `date` | التاريخ (YYYY-MM-DD) |
| `dayNameAr` | اسم اليوم بالعربية |
| `checkIn` | وقت الحضور (HH:MM) |
| `checkOut` | وقت الانصراف (HH:MM) |
| `shiftName` | اسم الوردية |
| `workHours` | ساعات العمل الفعلية |
| `lateMinutes` | دقائق التأخير |
| `status` | حالة اليوم (حاضر / غائب دون إذن / يحتاج مراجعة / إجازة / ...) |
| `missingCheckOut` | نسيان ختم انصراف (boolean) |
| `correctionNote` | ملاحظة تصحيح |

#### 14.3 تصدير PDF

| البند | التفصيل |
|---|---|
| الحالة الحالية | **غير موجود** — لا يوجد زر تصدير في الويب ولا الموبايل |
| المطلوب V18 | زر "تصدير PDF" في الويب (`MonthlyStatementSection`) يولّد PDF عربي RTL يحتوي: رأس المستند (شعار + اسم الموظف + كود + إدارة + شهر/سنة) + جدول يومي + ملخصات + توقيع إلكتروني (اسم المُصدِر + تاريخ التصدير) |
| التقنية المقترحة | `@react-pdf/renderer` (client-side) أو Edge Function تُرجع PDF binary |
| الموبايل | زر مشاركة في `MonthlyAttendanceStatementPage` يطلب الـ PDF من Edge Function ويفتحه بـ `share_plus` |

#### 14.4 الاختبارات

| الملف | النطاق |
|---|---|
| `supabase/tests/0050_monthly_attendance_statement.sql` | موجود — بناء الكشف + صلاحيات + حالات حافة (شهر بدون بيانات / موظف غير موجود) |
| **جديد**: Web component test | `MonthlyStatementSection.test.tsx` — عرض جدول + تبديل شهر/سنة + mock data |
| **جديد**: PDF export test | integration test — تنزيل PDF + التحقق من حجم الملف > 0 |

---

### 15. تسجيل الدخول واستعادة كلمة المرور

#### 15.1 الوضع الحالي

| العنصر | الملف | الحالة |
|---|---|---|
| Edge Function | `supabase/functions/identifier-sign-in/index.ts` (200 سطر) | مكتمل |
| صفحة تسجيل الدخول | `apps/admin_web/src/features/auth/LoginPage.tsx` | مكتمل |
| صفحة إعداد كلمة المرور | `apps/admin_web/src/features/auth/PasswordSetupPage.tsx` | مكتمل |
| اختبار PasswordSetup | `apps/admin_web/src/features/auth/PasswordSetupPage.test.tsx` | مكتمل |
| AuthProvider | `apps/admin_web/src/features/auth/AuthProvider.tsx` | مكتمل — `detectSessionInUrl: true`, `autoRefreshToken: true` |
| Rate limiting | جدول `login_auth_attempts` + حد IP (10/دقيقة) + حد identifier (6/5 دقائق) | مكتمل |
| Timing-safe | deadline ثابت 480±80 مللي ثانية (ESI-01) + عدم الثقة بـ forwarded IP إلا مع `TRUSTED_PROXY=1` (ESI-02) | مكتمل |
| اختبار pgTAP | `supabase/tests/0025_identifier_login_security.sql` | مكتمل |
| Mobile auth | Dart Supabase client مع `identifier-sign-in` | مكتمل |

#### 15.2 آلية `identifier-sign-in`

```
المستخدم يُدخل (بريد أو هاتف أو كود موظف) + كلمة المرور
  ↓
normalizeIdentifier():
  - يحتوي @ → email
  - 7–15 رقم → phone E.164 (01... → +20...)
  - غير ذلك → employee_code (UPPER)
  ↓
فحص Rate limit (IP + identifier hash)
  ↓
تحليل نوع المعرف:
  - email: يُستخدم مباشرة
  - phone: employees.phone_e164 → profiles.id → auth.users.email
  - employee_code: employees.employee_code → profiles.id → auth.users.email
  ↓
signInWithPassword(resolvedEmail, password)
  ↓
تسجيل المحاولة (نجاح/فشل) في login_auth_attempts
  ↓
انتظار حتى الـ deadline الثابت (لمنع timing attack)
  ↓
إرجاع: access_token + refresh_token + expires_in + expires_at
```

**لا تسجيل ذاتي** — لا يوجد مسار sign-up. الموظف يُنشأ فقط عبر `admin-create-employee` الذي يدعو `provision_employee_record`.

#### 15.3 استعادة كلمة المرور

```
المستخدم يطلب استعادة → resetPasswordForEmail(email)
  ↓
Supabase يُرسل رابط → https://ahla-shabab-management-os.vercel.app/auth/setup-password
  ↓
PasswordSetupPage يقرأ الـ token من URL (detectSessionInUrl: true)
  ↓
المستخدم يُدخل كلمة مرور جديدة (8 أحرف، حرف كبير، رقم، رمز)
  ↓
updateUser({ password }) → تسجيل دخول تلقائي
```

#### 15.4 إصلاح Redirect (Site URL = Vercel)

| البند | التفصيل |
|---|---|
| المشكلة | رابط التفعيل كان يوجّه إلى `localhost:3000` |
| الحل (مُطبّق) | ضبط Site URL في Supabase Dashboard = `https://ahla-shabab-management-os.vercel.app` + secret `APP_INVITE_REDIRECT_URL` في Edge Function `admin-create-employee` يُقيّد الـ redirect لـ Vercel |
| الحالة | **تم الإصلاح** — موثق في memory `auth-invite-redirect-localhost-bug.md` |

#### 15.5 الاختبارات

| الملف | النطاق |
|---|---|
| `supabase/tests/0025_identifier_login_security.sql` | rate limiting + identifier normalization + attempt logging |
| `apps/admin_web/src/features/auth/PasswordSetupPage.test.tsx` | عرض النموذج + validation + mock updateUser |
| **جديد**: Integration test | E2E: identifier-sign-in مع أنواع المعرفات الثلاثة (email/phone/code) |

---

### 16. نظام الإشعارات

#### 16.1 الوضع الحالي

| العنصر | الملف | الحالة |
|---|---|---|
| جدول `notifications` | mig 0008 — `recipient_user_id`, `title`, `body`, `category`, `priority`, `action_url`, `is_read`, `metadata` | مكتمل |
| جدول `notification_jobs` | mig 0033 — طابور التوصيل: `status` (queued/processing/sent/failed), `channel`, `idempotency_key`, `available_at`, `attempts` (حد 5) | مكتمل |
| جدول `notification_delivery_log` | mig 0008 — سجل التسليم لكل محاولة | مكتمل |
| Trigger إنشاء الوظائف | `trg_notifications_queue_jobs` → `queue_notification_jobs()` (mig 0033): يُنشئ job لـ `in_app` دائمًا + `push` إذا وُجد `push_subscriptions` | مكتمل |
| منع التكرار (dedup) | `idempotency_key` (UNIQUE) = `notification_id::text || ':' || channel` — إدراج مكرر يُتجاهل بصمت | مكتمل |
| Edge Function | `supabase/functions/notification-dispatcher/index.ts` (230 سطر) | مكتمل |
| مسار FCM v1 | `mintFcmAccessToken` (JWT-bearer RS256) + `buildFcmMessage` (data-only, Android HIGH/NORMAL, APNs time-sensitive) | مكتمل |
| تجربة عاجلة | `urgent` + `metadata.fullScreen` → Android HIGH priority + APNs critical sound + full-screen intent flag | مكتمل |
| مسار احتياطي | `PUSH_PROVIDER_URL` + `PUSH_PROVIDER_TOKEN` (مزوّد خارجي) إذا لم يُضبط FCM | مكتمل |
| إبطال رموز غير صالحة | FCM 404/410 → `push_subscriptions.is_active = false` | مكتمل |
| pg_cron | `schedule_edge_functions` (mig 0049/0051) يستدعي `notification-dispatcher` كل 2 دقيقة | مكتمل |
| صفحة الويب | `NotificationsPage.tsx` — قائمة + تعليم الكل كمقروء + فتح actionUrl | مكتمل |
| صفحة الموبايل | `mobile_notifications_page.dart` | مكتمل |
| اختبار pgTAP | `0048_fcm_push_delivery_runtime.sql` + `0041_v4_location_notification_device_contract.sql` + `0011_mobile_notifications_contract.sql` | مكتمل |

#### 16.2 قاعدة: إشعار واحد لكل حدث

الـ `idempotency_key` يضمن عدم إرسال نفس الإشعار أكثر من مرة لنفس القناة. عند إنشاء إشعار:
1. Trigger `queue_notification_jobs` يُدرج وظيفة `in_app` بمفتاح فريد.
2. إذا وجد اشتراك push نشط، يُدرج وظيفة `push` بمفتاح فريد.
3. `ON CONFLICT (idempotency_key) DO NOTHING` — لا تكرار.

#### 16.3 أنواع الأحداث (~37 نوع)

| الفئة | أنواع الأحداث |
|---|---|
| **حضور** (attendance) | تسجيل حضور ناجح، تسجيل انصراف، تأخير، غياب دون إذن، نسيان ختم، تصحيح حضور، إعفاء تنفيذي |
| **طلبات** (request) | طلب جديد، موافقة، رفض، إرجاع للتعديل، تصعيد، إلغاء، اقتراب موعد استحقاق |
| **إجازات** (leave) | طلب إجازة، موافقة إجازة، رصيد منخفض، إجازة طارئة |
| **KPI** (performance) | بداية دورة، تقييم ذاتي مطلوب، مراجعة مدير مطلوبة، مراجعة HR، اعتماد نهائي، نتيجة التقييم، تذكير catch-up |
| **مشكلات/خلافات** (dispute) | شكوى مقدمة، قبول شكوى، جلسة مجدولة، قرار صادر، اقتراح إجراء، قرار تنفيذي، تم التنفيذ، اعتراض |
| **منشورات** (announcement) | منشور رسمي جديد، قرار إداري، يتطلب إقرارًا |
| **موقع** (location) | طلب موقع وارد، مهلة انتهت، موقع مُستلَم |
| **نظام** (system) | تنبيه أمني، جهاز جديد، تغيير كلمة مرور، دعوة تفعيل، تحديث بيانات موظف |

#### 16.4 القنوات

| القناة | الآلية | الحالة |
|---|---|---|
| **In-App** | إدراج في `notifications` + عرض في NotificationsPage / mobile_notifications_page | مكتمل |
| **Push FCM** | `notification-dispatcher` → FCM v1 HTTP API (data-only message) | مكتمل |
| **صوت** | Android: `urgent.caf` + full-screen intent للعاجل. APNs: `critical: 0` + `interruption-level: time-sensitive` | مكتمل |

#### 16.5 الاختبارات

| الملف | النطاق |
|---|---|
| `supabase/tests/0048_fcm_push_delivery_runtime.sql` | job queuing + dedup + retry backoff + token invalidation |
| `supabase/tests/0041_v4_location_notification_device_contract.sql` | push subscriptions + device registration |
| `supabase/tests/0011_mobile_notifications_contract.sql` | notification schema + RLS + mark read |

---

### 17. المنشورات الرسمية

#### 17.1 الوضع الحالي

| العنصر | الملف / Migration | الحالة |
|---|---|---|
| جدول `announcements` | mig 0008 — `title`, `body`, `category` (6 أنواع: general/event/urgent/policy/celebration/maintenance), `priority`, `status`, `requires_acknowledgement` | مكتمل |
| جدول `administrative_decisions` | mig 0008 — `decision_number`, `title`, `body`, `category`, `status` (draft/published/archived/revoked), `effective_date`, `requires_acknowledgement` | مكتمل |
| جدول `announcement_acknowledgements` | mig 0008 — تتبع إقرار الموظفين | مكتمل |
| RPC القناة | `get_official_feed` (mig 0133) | مكتمل |
| RPC النشر | `publish_announcement` + `create_decision_draft` + `transition_decision` | مكتمل |
| صفحة الويب | `OfficialFeedPage.tsx` (105 سطر) | مكتمل: MetricCards (عدد المنشورات/القرارات/تحتاج إقرارًا/عاجل) + فلاتر (بحث/نوع/أولوية) + نموذج إنشاء (خبر أو قرار) + دورة حياة القرار (مسودة←مراجعة←اعتماد←نشر←أرشفة) + شريط تقدم الإقرار |
| صفحة الموبايل | `mobile_official_feed_page.dart` | مكتمل |
| اختبار pgTAP | `supabase/tests/0057_v17_post_publishing.sql` | مكتمل |

#### 17.2 المصادر الثلاث

| المصدر | المسؤول | النوع | الآلية |
|---|---|---|---|
| **الإدارة التنفيذية** | المدير التنفيذي + السكرتير التنفيذي | قرارات إدارية (`decision`) | دورة: مسودة ← مراجعة ← اعتماد ← نشر |
| **الموارد البشرية** | HR Manager + HR Specialist | أخبار وسياسات (`announcement`) | نشر مباشر بصلاحية |
| **Main Admin** | مدير النظام | كل الأنواع | صلاحية كاملة |

#### 17.3 المحتوى

**الخبر/الإعلان:**

| الحقل | النوع | إلزامي |
|---|---|---|
| العنوان | text | نعم (3 أحرف) |
| المحتوى | textarea | نعم (10 أحرف) |
| التصنيف | select | نعم — general / hr / policy / organizational / financial |
| الأولوية | select | نعم — normal / high / urgent |
| يتطلب إقرارًا | checkbox | لا |

**القرار الإداري:**

| الحقل | النوع | إلزامي |
|---|---|---|
| العنوان | text | نعم |
| المحتوى | textarea | نعم |
| التصنيف | select | نعم |
| النتيجة المتوقعة | text | لا |
| مؤشر قياس النجاح | text | لا |
| يتطلب إقرارًا | checkbox | لا |

#### 17.4 مصفوفة الصلاحيات

| العملية | Main Admin | Executive | Secretary | HR Manager | HR Specialist | Manager | Employee |
|---|---|---|---|---|---|---|---|
| قراءة المنشورات | نعم | نعم | نعم | نعم | نعم | نعم | نعم |
| إنشاء خبر/إعلان | نعم | — | — | نعم | نعم (`comms.announcement.manage`) | — | — |
| إنشاء مسودة قرار | نعم | نعم | نعم | — | — | — | — |
| إرسال للمراجعة | نعم | — | نعم (`comms.decision.manage`) | — | — | — | — |
| اعتماد القرار | نعم | نعم (`comms.decision.manage`) | — | — | — | — | — |
| نشر القرار | نعم | نعم | نعم | — | — | — | — |
| أرشفة القرار | نعم | — | نعم | — | — | — | — |
| تثبيت منشور | نعم | نعم | نعم | نعم | — | — | — |
| حذف منشور | نعم | — | — | نعم (منشوراته فقط) | — | — | — |
| تعديل منشور | نعم | — | نعم (مسودة فقط) | نعم (قبل النشر) | — | — | — |
| إقرار بالاطلاع | — | نعم | نعم | نعم | نعم | نعم | نعم |

#### 17.5 الاختبارات

| الملف | النطاق |
|---|---|
| `supabase/tests/0057_v17_post_publishing.sql` | publish + transition lifecycle + RLS + acknowledgement tracking |
| `supabase/tests/0015_decision_lifecycle_contract.sql` | دورة حياة القرار الإداري الكاملة |
| **جديد**: Web component test | `OfficialFeedPage.test.tsx` — عرض القناة + إنشاء خبر + فلترة + دورة قرار |

---

### ملخص P1 — حالة كل قسم

| # | القسم | DB | Backend | Web | Mobile | Tests | الفجوات المتبقية |
|---|---|---|---|---|---|---|---|
| 12 | ملف الموظف | مكتمل (0129) | مكتمل (RPCs) | مكتمل (518 سطر) | — (لا يوجد 360 بالموبايل) | 3 pgTAP | تبويب الجهاز/الأمان + Web component test |
| 13 | لجنة المشكلات | مكتمل (0131+0141) | مكتمل (6 RPCs) | — (لا صفحة ويب) | مكتمل (1551 سطر) | 4 pgTAP | صفحة ويب لإدارة القضايا + توحيد قيد 300 كلمة |
| 14 | كشف الحضور | مكتمل (0127) | مكتمل (2 RPCs) | مكتمل (91 سطر) | مكتمل (218 سطر) | 1 pgTAP | تصدير PDF + Web component test |
| 15 | تسجيل الدخول | مكتمل | مكتمل (200 سطر EF) | مكتمل | مكتمل | 1 pgTAP + 1 Web | لا فجوات جوهرية |
| 16 | الإشعارات | مكتمل (3 جداول) | مكتمل (230 سطر EF + pg_cron) | مكتمل | مكتمل | 3 pgTAP | لا فجوات جوهرية — فقط مراقبة التسليم |
| 17 | المنشورات | مكتمل (0008+0133) | مكتمل (4 RPCs) | مكتمل (105 سطر) | مكتمل | 2 pgTAP | Web component test |

---

Now I have all the context needed. Let me produce the four sections.

---

## 18. استراتيجية Offline — طابور البصمة بدون اتصال

### 18.1 السياق والمشكلة

الموظفون الميدانيون يعملون في مواقع ذات تغطية شبكة ضعيفة. حاليًا إذا انقطع الإنترنت أثناء بصمة الحضور تضيع البصمة بالكامل — لا تخزين محلي ولا إعادة محاولة. خدمة `ConnectivityService` القائمة (في `lib/core/network/connectivity_service.dart`) تكشف الانقطاع وتعرض شريط تنبيه، لكنها لا تحفظ أي عملية فاشلة.

### 18.2 المكتبة المختارة: Hive

```yaml
# pubspec.yaml — إضافات جديدة
dependencies:
  hive: ^4.0.0
  hive_flutter: ^2.0.0

dev_dependencies:
  hive_generator: ^3.0.0
  build_runner: ^2.4.0
```

**لماذا Hive وليس sqflite/drift:**
- لا يحتاج مخطط علائقي — الطابور مسطح (قائمة بصمات).
- أداء كتابة أسرع بـ 3x على الأجهزة الضعيفة.
- لا يعتمد على مكتبات أصلية ثقيلة (pure Dart).
- التشفير المدمج (AES-256) يحمي البيانات الحساسة.

### 18.3 نموذج البيانات المحلية

```dart
// lib/core/offline/offline_punch_model.dart
import 'package:hive/hive.dart';

part 'offline_punch_model.g.dart';

@HiveType(typeId: 1)
class OfflinePunch extends HiveObject {
  @HiveField(0)
  final String idempotencyKey; // UUID — يُولَّد على الجهاز

  @HiveField(1)
  final String employeeId;

  @HiveField(2)
  final String eventType; // CHECK_IN | CHECK_OUT

  @HiveField(3)
  final double latitude;

  @HiveField(4)
  final double longitude;

  @HiveField(5)
  final double accuracyMeters;

  @HiveField(6)
  final bool isMockLocation;

  @HiveField(7)
  final DateTime capturedAt; // وقت البصمة الفعلي (ليس وقت الإرسال)

  @HiveField(8)
  final String biometricMethod; // passkey | local_biometric

  @HiveField(9)
  int syncAttempts;

  @HiveField(10)
  String? lastError;

  @HiveField(11)
  DateTime? lastAttemptAt;

  OfflinePunch({
    required this.idempotencyKey,
    required this.employeeId,
    required this.eventType,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.isMockLocation,
    required this.capturedAt,
    required this.biometricMethod,
    this.syncAttempts = 0,
    this.lastError,
    this.lastAttemptAt,
  });
}
```

### 18.4 حد الطابور: 50 بصمة

```dart
// lib/core/offline/offline_queue_service.dart
class OfflineQueueService {
  static const int maxQueueSize = 50;
  static const String boxName = 'offline_punches';

  late Box<OfflinePunch> _box;

  Future<void> init() async {
    _box = await Hive.openBox<OfflinePunch>(
      boxName,
      encryptionCipher: HiveAesCipher(await _getEncryptionKey()),
    );
  }

  /// إضافة بصمة للطابور — ترفض إذا تجاوز الحد
  Future<bool> enqueue(OfflinePunch punch) async {
    if (_box.length >= maxQueueSize) {
      // حذف الأقدم لإفساح المجال (FIFO)
      final oldest = _box.values.first;
      await oldest.delete();
      debugPrint('حذف أقدم بصمة من الطابور: ${oldest.idempotencyKey}');
    }
    await _box.add(punch);
    return true;
  }

  /// البصمات المعلقة مرتبة بالأقدم أولاً
  List<OfflinePunch> get pending =>
      _box.values.toList()..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

  int get pendingCount => _box.length;

  Future<void> remove(OfflinePunch punch) => punch.delete();

  Future<Uint8List> _getEncryptionKey() async {
    // مفتاح تشفير مخزن في flutter_secure_storage
    const storage = FlutterSecureStorage();
    final existing = await storage.read(key: 'hive_encryption_key');
    if (existing != null) return base64Decode(existing);
    final key = Hive.generateSecureKey();
    await storage.write(key: 'hive_encryption_key', value: base64Encode(key));
    return key;
  }
}
```

### 18.5 المزامنة مع Exponential Backoff

```dart
// lib/core/offline/offline_sync_service.dart
class OfflineSyncService {
  final OfflineQueueService _queue;
  final SupabaseClient _supabase;
  Timer? _syncTimer;

  /// محاولة مزامنة كل البصمات المعلقة
  Future<SyncResult> syncAll() async {
    final pending = _queue.pending;
    if (pending.isEmpty) return SyncResult(synced: 0, failed: 0);

    int synced = 0, failed = 0;

    for (final punch in pending) {
      try {
        await _supabase.functions.invoke(
          'verify-attendance-punch',
          body: {
            'employee_id': punch.employeeId,
            'event_type': punch.eventType,
            'latitude': punch.latitude,
            'longitude': punch.longitude,
            'accuracy_meters': punch.accuracyMeters,
            'is_mock': punch.isMockLocation,
            'biometric_method': punch.biometricMethod,
            'idempotency_key': punch.idempotencyKey,
            'captured_at': punch.capturedAt.toIso8601String(),
          },
        );
        await _queue.remove(punch);
        synced++;
      } catch (e) {
        punch.syncAttempts++;
        punch.lastError = e.toString();
        punch.lastAttemptAt = DateTime.now();
        await punch.save();
        failed++;
      }
    }
    return SyncResult(synced: synced, failed: failed);
  }

  /// جدولة المزامنة بـ exponential backoff
  void scheduleRetry(int attempt) {
    _syncTimer?.cancel();
    // 2^attempt ثوانٍ، حد أقصى 5 دقائق
    final delay = Duration(
      seconds: min(pow(2, attempt).toInt(), 300),
    );
    _syncTimer = Timer(delay, () async {
      final result = await syncAll();
      if (result.failed > 0) {
        scheduleRetry(attempt + 1);
      }
    });
  }

  /// تُستدعى عند عودة الاتصال (من ConnectivityNotifier)
  void onReconnected() => scheduleRetry(0);
}
```

### 18.6 دعم Idempotency في الخادم

البنية التحتية موجودة بالفعل — جدول `integration_outbox` يستخدم `idempotency_key` (migration 0038). نحتاج توسيع `record_attendance_event` لقبول مفتاح Idempotency:

```sql
-- migration جديدة: إضافة دعم idempotency للبصمات
-- =====================================================================
-- الهدف: منع تسجيل نفس البصمة مرتين عند إعادة المزامنة من الطابور المحلي.
-- المفتاح يُولَّد على الجهاز (UUID v4) ويُرسل مع كل محاولة.
-- =====================================================================

-- 1) عمود idempotency_key على attendance_events
ALTER TABLE public.attendance_events
  ADD COLUMN IF NOT EXISTS idempotency_key text;

CREATE UNIQUE INDEX IF NOT EXISTS ux_att_events_idempotency
  ON public.attendance_events(idempotency_key)
  WHERE idempotency_key IS NOT NULL;

COMMENT ON COLUMN public.attendance_events.idempotency_key IS
  'مفتاح تفرد يُولَّد على الجهاز (UUID v4). يمنع التكرار عند إعادة المزامنة من الطابور المحلي.';

-- 2) توسيع record_attendance_event بمعامل p_idempotency_key
-- عند وجود صف بنفس المفتاح → إرجاع الـ id الموجود بدل INSERT جديد
CREATE OR REPLACE FUNCTION public.record_attendance_event(
  p_employee_id       uuid,
  p_event_type        text,
  p_latitude          double precision,
  p_longitude         double precision,
  p_accuracy_meters   double precision,
  p_biometric_method  text DEFAULT 'passkey',
  p_selfie_path       text DEFAULT NULL,
  p_passkey_credential_id uuid DEFAULT NULL,
  p_verified          boolean DEFAULT false,
  p_is_mock           boolean DEFAULT false,
  p_idempotency_key   text DEFAULT NULL,     -- ← جديد
  p_captured_at       timestamptz DEFAULT NULL -- ← وقت البصمة الأصلي (offline)
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing_id uuid;
  -- ... باقي المتغيرات كما في الإصدار الحالي (0120)
BEGIN
  -- 0) فحص service_role (القائم)
  -- ...

  -- 0.5) فحص Idempotency — إن وُجد صف بنفس المفتاح → إرجاع مباشر
  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_existing_id
    FROM public.attendance_events
    WHERE idempotency_key = p_idempotency_key;

    IF v_existing_id IS NOT NULL THEN
      RETURN v_existing_id; -- البصمة مسجلة سابقاً — لا تكرار
    END IF;
  END IF;

  -- ... باقي المنطق (geofence, mock detection, impossible travel)
  -- عند INSERT: إضافة idempotency_key و captured_at
END $$;
```

### 18.7 البيانات القابلة وغير القابلة للتخزين المحلي

| البيانات | قابلة للتخزين محليًا | السبب |
|---|---|---|
| بصمات الحضور (CHECK_IN/CHECK_OUT) | نعم | العملية الأكثر حساسية للانقطاع |
| إحداثيات GPS + دقة + is_mock | نعم | جزء أساسي من البصمة |
| وقت البصمة الفعلي (captured_at) | نعم | الخادم يسجل وقت الالتقاط لا وقت الاستلام |
| idempotency_key (UUID) | نعم | يمنع التكرار |
| طلبات الإجازة/المأمورية | لا | تتطلب تحقق لحظي من الرصيد والتعارضات |
| تقييمات KPI | لا | تتطلب مرفقات (أدلة) + تحقق من الدورة |
| بيانات الموقع المباشر (live location) | لا | لحظية بطبيعتها — لا معنى لإرسالها متأخرة |
| الإشعارات المستلمة | نعم (قراءة فقط) | تخزين مؤقت لعرضها بدون اتصال |
| بيانات الملف الشخصي | نعم (قراءة فقط) | cache محلي للعرض السريع |

### 18.8 مؤشرات الحالة في الواجهة

```dart
// lib/core/widgets/sync_status_indicator.dart
class SyncStatusIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final pendingCount = ref.watch(offlinePendingCountProvider);

    if (pendingCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: connectivity == ConnectivityState.online
            ? Colors.orange.shade100
            : Colors.red.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            connectivity == ConnectivityState.online
                ? Icons.sync
                : Icons.cloud_off,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            connectivity == ConnectivityState.online
                ? 'جارٍ مزامنة $pendingCount بصمة...'
                : '$pendingCount بصمة بانتظار الاتصال',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
```

**حالات العرض:**

| الحالة | الأيقونة | الرسالة | اللون |
|---|---|---|---|
| متصل + لا معلقات | (لا شيء) | — | — |
| غير متصل + معلقات | `cloud_off` | "X بصمة بانتظار الاتصال" | أحمر فاتح |
| متصل + جارٍ المزامنة | `sync` (دوّار) | "جارٍ مزامنة X بصمة..." | برتقالي فاتح |
| متصل + فشل مزامنة | `sync_problem` | "فشل مزامنة X بصمة — إعادة بعد Ys" | أحمر |
| إعادة اتصال | `wifi` (نابض) | "عاد الاتصال — بدء المزامنة..." | أخضر فاتح |

### 18.9 حل التعارضات — الخادم مرجع (Server Wins)

```
┌──────────────┐    ┌───────────────┐    ┌──────────────────┐
│  جهاز الموظف │───→│ Edge Function │───→│ record_attendance │
│  (Hive queue) │    │ verify-punch  │    │ _event (SQL)     │
└──────────────┘    └───────────────┘    └──────────────────┘
       │                    │                      │
       │ idempotency_key    │ JWT + validation     │ ON CONFLICT → SKIP
       │ captured_at        │ Zod schema           │ الخادم هو المرجع
       └────────────────────┴──────────────────────┘
```

- **الخادم دائمًا هو المرجع.** لا يُعدَّل سجل خادمي بناءً على بيانات محلية.
- إذا رفض الخادم البصمة (geofence/mock/duplicate) → تُحذف من الطابور المحلي مع تسجيل السبب في `lastError`.
- إذا أعاد الخادم `id` موجود (idempotency hit) → نجاح — تُحذف من الطابور.
- الـ `captured_at` المحلي يُسجل في عمود مخصص — لكن `event_at` يبقى `now()` الخادمي للحفاظ على تسلسل موثوق.

---

## 19. خطة الأمان الشاملة — 4 طبقات

### 19.1 الطبقة الأولى: قاعدة البيانات (PostgreSQL + RLS)

#### 19.1.1 سياسة RLS الشاملة

كل جدول في المنظومة محمي بـ Row Level Security. السياسة العامة:

```
┌─────────────────────────────────────────────────────────┐
│                    قاعدة RLS العامة                       │
├─────────────────────────────────────────────────────────┤
│ • كل جدول: ENABLE ROW LEVEL SECURITY                    │
│ • القراءة: الموظف يرى بياناته + ما يخص فريقه            │
│ • الكتابة: عبر RPC فقط (SECURITY DEFINER)               │
│ • full_access: current_is_full_access() → كل شيء        │
│ • USING(true): جداول مرجعية فقط (6 جداول)                │
│ • anon: لا وصول مطلقاً (revoke all)                      │
└─────────────────────────────────────────────────────────┘
```

#### 19.1.2 جداول `USING(true)` — القائمة الحصرية (6 جداول)

هذه الجداول مرجعية للقراءة فقط — لا تحتوي بيانات شخصية:

| الجدول | المايجريشن | المبرر |
|---|---|---|
| `permissions` | 0002 | كتالوج الصلاحيات — يحتاجه كل مستخدم لفحص واجهته |
| `roles` | 0002 | كتالوج الأدوار — مرجعي |
| `role_permissions` | 0002 | ربط الأدوار بالصلاحيات — مرجعي |
| `kpi_criteria` | 0007 | معايير التقييم — يحتاجها الموظف والمدير |
| `official_holidays` | 0132 | العطل الرسمية — عامة لكل الموظفين |
| `learning_course_sessions` | 0033 | جلسات التعلم المتاحة — كتالوج عام |

**استعلام فحص — كشف أي جدول بـ `USING(true)` خارج القائمة:**

```sql
-- استعلام فحص RLS: كشف سياسات USING(true) غير مصرح بها
-- =====================================================================
-- يُشغَّل دورياً أو في CI للتأكد من عدم تسرب سياسة مفتوحة
-- =====================================================================
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND qual = 'true'
  AND tablename NOT IN (
    'permissions',
    'roles',
    'role_permissions',
    'kpi_criteria',
    'official_holidays',
    'learning_course_sessions'
  )
ORDER BY tablename, policyname;

-- النتيجة المتوقعة: 0 صفوف
-- إذا ظهر أي صف → خرق أمني يجب إصلاحه فوراً
```

#### 19.1.3 دالة `current_is_full_access()`

تحمي كل العمليات الحساسة. مُستخدمة في 768 موضع عبر 90 ملف migration:

```sql
-- التعريف القائم (0002) — لا تعديل، للتوثيق فقط
CREATE OR REPLACE FUNCTION public.current_is_full_access()
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.user_roles ur
    JOIN public.roles r ON r.id = ur.role_id
    WHERE ur.user_id = auth.uid()
      AND r.is_full_access = true
  );
END $$;
```

#### 19.1.4 دالة `provision_employee_record()`

بوابة إنشاء الموظف الوحيدة — تتجاوز `rpc_assign_role`:

```
provision_employee_record()
  ├── إنشاء سجل في auth.users
  ├── إنشاء profile
  ├── إنشاء employee record
  ├── ربط بالقسم والمسمى الوظيفي
  ├── تعيين دور (employee فقط — لا full_access)
  └── إرسال دعوة بالبريد
```

**قاعدة حاسمة:** `provision_employee_record` يتجاوز `rpc_assign_role` — أدوار `full_access` لا تُعطى أبداً عند الإنشاء. الترقية يدوية حصراً عبر `rpc_assign_role` من صاحب `full_access`.

#### 19.1.5 استعلام فحص SECURITY DEFINER

```sql
-- فحص: كل دوال SECURITY DEFINER يجب أن تحتوي SET search_path
-- =====================================================================
-- دالة DEFINER بدون search_path محدد = خطر search_path injection
-- =====================================================================
SELECT
  n.nspname AS schema,
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS args,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND (
    p.proconfig IS NULL
    OR NOT EXISTS (
      SELECT 1 FROM unnest(p.proconfig) c
      WHERE c LIKE 'search_path=%'
    )
  )
ORDER BY p.proname;

-- النتيجة المتوقعة: 0 صفوف
-- أي صف = دالة DEFINER بدون search_path → ثغرة injection محتملة
```

#### 19.1.6 استعلام فحص RLS مفعّل على كل الجداول

```sql
-- فحص: كل جداول public يجب أن يكون RLS مفعلاً عليها
-- =====================================================================
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = false
  AND tablename NOT LIKE 'pg_%'
  AND tablename NOT IN ('schema_migrations')
ORDER BY tablename;

-- النتيجة المتوقعة: 0 صفوف
-- أي صف = جدول بدون RLS → بيانات مكشوفة لأي مستخدم مصادق
```

### 19.2 الطبقة الثانية: Edge Functions (JWT + Rate Limiting + Zod)

#### 19.2.1 بنية الحماية في كل Edge Function

```
┌──────────────────────────────────────────────────────┐
│              Edge Function Security Stack             │
├──────────────────────────────────────────────────────┤
│ 1. JWT Verification  ← Supabase GoTrue تلقائياً      │
│ 2. Rate Limiting     ← DB-level (0120) + in-memory   │
│ 3. Zod Validation    ← shared-contracts schemas      │
│ 4. Authorization     ← RPC permission check          │
│ 5. Audit Logging     ← log_audit_event()             │
└──────────────────────────────────────────────────────┘
```

#### 19.2.2 دوال Edge القائمة وحمايتها

| Edge Function | JWT | Rate Limit | Zod | ملاحظات |
|---|---|---|---|---|
| `identifier-sign-in` | لا (عامة) | نعم — `rate_limited` بعد 5 محاولات/دقيقة | نعم | بوابة الدخول الوحيدة |
| `verify-attendance-punch` | نعم | ضمني (60 ثانية بين بصمتين) | نعم | الأكثر حساسية |
| `admin-create-employee` | نعم | لا | نعم | `full_access` فقط |
| `admin-resend-invite` | نعم | نعم — DB-level (0120) | نعم | حد 3 دعوات/ساعة لكل موظف |
| `webauthn-challenge` | نعم | نعم — 20 تحدي/ساعة | نعم | حماية من brute-force |
| `notification-dispatcher` | service_role | لا (داخلية) | لا | تُستدعى من pg_net فقط |
| `retention-cleanup` | service_role | لا (cron) | لا | مجدولة — لا وصول خارجي |

#### 19.2.3 نموذج Zod Validation (من shared-contracts)

```typescript
// packages/shared-contracts/src/attendance.ts — القائم
import { z } from 'zod';

export const AttendancePunchSchema = z.object({
  employee_id: z.string().uuid(),
  event_type: z.enum(['CHECK_IN', 'CHECK_OUT']),
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracy_meters: z.number().min(0).max(1000),
  is_mock: z.boolean().default(false),
  biometric_method: z.enum(['passkey', 'local_biometric']).default('passkey'),
  // جديد للـ offline
  idempotency_key: z.string().uuid().optional(),
  captured_at: z.string().datetime().optional(),
});
```

### 19.3 الطبقة الثالثة: التطبيق (Mock Location + Geofence + Impossible Travel)

#### 19.3.1 كشف الموقع المزيف (Mock Location)

**القائم (migration 0046):**
- عمود `is_mock_location` على `attendance_events`
- `Position.isMocked` يُقرأ من نظام التشغيل ويُرسل مع البصمة
- البصمة بموقع مزيف تُعلَّم `flagged` + `requires_review` (لا رفض تلقائي)

```dart
// lib/features/mobile_data/location_service.dart — القائم
final position = await Geolocator.getCurrentPosition(
  locationSettings: const LocationSettings(
    accuracy: LocationAccuracy.high,
  ),
);
// position.isMocked → يُرسل مع البصمة
```

#### 19.3.2 فحص Geofence

**القائم (migration 0046):**
- جدول `geofences` مع `latitude, longitude, radius_meters, max_accuracy`
- `geo_distance_meters()` تحسب المسافة بين البصمة ومركز الـ geofence
- خارج النطاق → `flagged` + `outside_geofence`

```sql
-- المنطق القائم في record_attendance_event (0046/0120):
IF v_distance > v_geofence.radius_meters THEN
  v_requires_review := true;
  v_flags := array_append(v_flags, 'outside_geofence');
END IF;

IF v_geofence.max_accuracy IS NOT NULL
   AND p_accuracy_meters > v_geofence.max_accuracy THEN
  v_requires_review := true;
  v_flags := array_append(v_flags, 'low_accuracy');
END IF;
```

#### 19.3.3 حارس الانتقال المستحيل (Impossible Travel)

**القائم (migration 0046، أُعيد في 0120):**
- مقارنة إحداثيات البصمة مع آخر بصمة خلال 6 ساعات
- حد السرعة: 42 م/ث (≈ 150 كم/س)
- تجاوز الحد → `flagged` + `impossible_travel` (لا رفض — مراجعة بشرية)

```sql
-- المنطق القائم (0120 — الإصدار الحالي):
-- حارس الانتقال المستحيل
IF p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
  SELECT ae.event_at, ae.latitude, ae.longitude
    INTO v_prev_at, v_prev_lat, v_prev_lon
  FROM public.attendance_events ae
  WHERE ae.employee_id = p_employee_id
    AND ae.latitude IS NOT NULL
    AND ae.longitude IS NOT NULL
    AND ae.event_at > v_now - INTERVAL '6 hours'
  ORDER BY ae.event_at DESC
  LIMIT 1;

  IF v_prev_at IS NOT NULL THEN
    v_gap_seconds := GREATEST(EXTRACT(EPOCH FROM (v_now - v_prev_at)), 1);
    v_travel := public.geo_distance_meters(
      p_latitude, p_longitude, v_prev_lat, v_prev_lon
    );
    -- 42 م/ث ≈ 150 كم/س — سرعة أعلى من أي وسيلة نقل معقولة
    IF (v_travel / v_gap_seconds) > 42.0 THEN
      v_requires_review := true;
      -- تسجيل التفاصيل للمراجعة
    END IF;
  END IF;
END IF;
```

#### 19.3.4 بصمة الجهاز (Device Fingerprint)

**القائم (migration 0083/0104):**
- جدول `verified_devices` يربط الجهاز بالموظف
- `device_info_plus` يجمع: الشركة المصنعة، الطراز، إصدار النظام، المعرف الفريد
- البصمة من جهاز غير مسجل → مرفوضة

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   الجهاز    │───→│ verified_devices │───→│ passkey_credentials│
│ fingerprint │    │ (0083/0104)      │    │ (0020)           │
└─────────────┘    └──────────────────┘    └─────────────────┘
       │                                          │
       └── الجهاز المسجل فقط يستطيع ──────────────┘
           استخدام مفتاح المرور (Passkey)
```

### 19.4 الطبقة الرابعة: المراقبة (Audit + Alerts + Retention)

#### 19.4.1 جدول `audit_logs` (migration 0011)

```sql
-- التعريف القائم — يسجل كل INSERT/UPDATE/DELETE على الجداول الحساسة
-- trigger: audit_row_change() → SECURITY DEFINER
-- يكتب: table_name, action, actor_user_id, old_data, new_data, changed_fields
-- مرتبط بـ: employees, attendance_events, requests, kpi_evaluations, disputes...
```

#### 19.4.2 جدول `system_alerts` (migration 0054)

```sql
-- القائم — 7 أنواع تنبيهات مع dedup تلقائي:
-- P0: dead_letter, fatal_errors, security_critical
-- P1: queue_overdue, error_spike, notifications_stuck, cron_failed
-- detect_and_raise_alerts() تعمل كل 5 دقائق عبر pg_cron
```

#### 19.4.3 سياسة الاحتفاظ (Retention Cleanup)

```sql
-- Edge Function: retention-cleanup (مجدولة)
-- القائم (0037/0054):
-- • audit_logs: 365 يوم
-- • app_error_events: 90 يوم
-- • security_events: 180 يوم
-- • notification_delivery_log: 30 يوم
-- • integration_outbox (succeeded): 7 أيام
```

#### 19.4.4 استعلام تدقيق أمني شامل (يُشغَّل في CI)

```sql
-- =====================================================================
-- فحص أمني شامل — يُشغَّل قبل كل نشر
-- =====================================================================

-- 1) جداول بدون RLS
SELECT 'NO_RLS' AS check_type, tablename
FROM pg_tables
WHERE schemaname = 'public' AND rowsecurity = false
  AND tablename NOT IN ('schema_migrations');

-- 2) سياسات USING(true) خارج القائمة المصرح بها
SELECT 'OPEN_POLICY' AS check_type, tablename, policyname
FROM pg_policies
WHERE schemaname = 'public' AND qual = 'true'
  AND tablename NOT IN (
    'permissions','roles','role_permissions',
    'kpi_criteria','official_holidays','learning_course_sessions'
  );

-- 3) دوال DEFINER بدون search_path
SELECT 'UNSAFE_DEFINER' AS check_type, proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosecdef = true
  AND (p.proconfig IS NULL OR NOT EXISTS (
    SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'
  ));

-- 4) صلاحيات EXECUTE لـ anon على دوال عامة
SELECT 'ANON_EXECUTE' AS check_type, routine_name
FROM information_schema.routine_privileges
WHERE grantee = 'anon'
  AND routine_schema = 'public'
  AND privilege_type = 'EXECUTE';

-- 5) جداول بدون trigger audit
SELECT 'NO_AUDIT' AS check_type, t.tablename
FROM pg_tables t
WHERE t.schemaname = 'public'
  AND t.tablename IN (
    'employees','attendance_events','requests','kpi_evaluations',
    'disputes','leave_transactions','payslips'
  )
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.triggers tr
    WHERE tr.event_object_table = t.tablename
      AND tr.trigger_name LIKE '%audit%'
  );
```

---

## 20. المراقبة والصحة — لوحة التحكم التشغيلية

### 20.1 دالة `get_system_health()` — القائمة

الدالة موجودة بالفعل في migration 0054 وتُرجع لقطة JSON شاملة:

```sql
-- الاستدعاء (من الويب أو service_role):
SELECT public.get_system_health();

-- النتيجة (jsonb):
{
  "generated_at": "2026-07-25T12:00:00Z",
  "cron": [
    {"jobname": "detect_alerts", "last_status": "succeeded", "last_run": "..."},
    {"jobname": "retention_cleanup", "last_status": "succeeded", "last_run": "..."}
  ],
  "integration_queue": {
    "pending": 3,
    "processing": 1,
    "failed": 0,
    "dead_letter": 0,
    "overdue": 0,
    "max_attempts_seen": 2
  },
  "notifications": {
    "queued": 5,
    "delivered": 142,
    "failed": 1,
    "stuck": 0
  },
  "errors": {
    "errors_1h": 2,
    "fatal_1h": 0,
    "warnings_1h": 8
  },
  "security": {
    "high_sev_1h": 0,
    "critical_1h": 0
  },
  "open_alerts": []
}
```

### 20.2 توسيع صحة النظام — مؤشرات تشغيلية جديدة

```sql
-- migration جديدة: توسيع get_system_health بمؤشرات HR تشغيلية
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_operational_health()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_out jsonb;
BEGIN
  -- فحص الصلاحية
  IF auth.role() <> 'service_role'
     AND NOT public.current_is_full_access()
     AND NOT public.has_any_permission(
       ARRAY['system.release.read','system.release.manage']
     ) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING errcode = '42501';
  END IF;

  v_out := jsonb_build_object(
    'generated_at', now(),

    -- 1) إحصائيات الموظفين
    'employees', (
      SELECT jsonb_build_object(
        'active', COUNT(*) FILTER (WHERE status = 'active'),
        'on_leave', COUNT(*) FILTER (WHERE status = 'on_leave'),
        'suspended', COUNT(*) FILTER (WHERE status = 'suspended'),
        'total', COUNT(*)
      ) FROM public.employees
    ),

    -- 2) بصمات اليوم
    'attendance_today', (
      SELECT jsonb_build_object(
        'check_ins', COUNT(*) FILTER (WHERE event_type = 'CHECK_IN'),
        'check_outs', COUNT(*) FILTER (WHERE event_type = 'CHECK_OUT'),
        'flagged', COUNT(*) FILTER (WHERE requires_review = true),
        'mock_detected', COUNT(*) FILTER (WHERE is_mock_location = true),
        'avg_accuracy_meters', ROUND(AVG(accuracy_meters)::numeric, 1)
      ) FROM public.attendance_events
      WHERE (event_at AT TIME ZONE 'Africa/Cairo')::date = CURRENT_DATE
    ),

    -- 3) طلبات معلقة
    'pending_requests', (
      SELECT jsonb_build_object(
        'total', COUNT(*),
        'older_than_3_days', COUNT(*) FILTER (
          WHERE created_at < now() - INTERVAL '3 days'
        ),
        'by_type', (
          SELECT COALESCE(jsonb_object_agg(request_type, cnt), '{}'::jsonb)
          FROM (
            SELECT request_type, COUNT(*) AS cnt
            FROM public.requests
            WHERE status = 'pending'
            GROUP BY request_type
          ) sub
        )
      ) FROM public.requests
      WHERE status = 'pending'
    ),

    -- 4) صحة الإشعارات (آخر 24 ساعة)
    'notification_health', (
      SELECT jsonb_build_object(
        'total_sent', COUNT(*),
        'delivered', COUNT(*) FILTER (
          WHERE status IN ('sent','delivered')
        ),
        'failed', COUNT(*) FILTER (
          WHERE status IN ('failed','bounced')
        ),
        'delivery_rate_pct', CASE
          WHEN COUNT(*) = 0 THEN 100
          ELSE ROUND(
            100.0 * COUNT(*) FILTER (WHERE status IN ('sent','delivered'))
            / COUNT(*), 1
          )
        END
      ) FROM public.notification_delivery_log
      WHERE created_at > now() - INTERVAL '24 hours'
    ),

    -- 5) صحة طابور Offline (بصمات بـ idempotency_key = أتت من offline)
    'offline_synced_today', (
      SELECT COUNT(*)
      FROM public.attendance_events
      WHERE idempotency_key IS NOT NULL
        AND (event_at AT TIME ZONE 'Africa/Cairo')::date = CURRENT_DATE
    )
  );

  RETURN v_out;
END $$;

COMMENT ON FUNCTION public.get_operational_health() IS
  'لقطة صحة تشغيلية: موظفين، بصمات اليوم، طلبات معلقة، إشعارات. full_access أو system.release.read.';

REVOKE EXECUTE ON FUNCTION public.get_operational_health() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_operational_health() TO authenticated, service_role;
```

### 20.3 مراقبة FCM — تتبع التسليم والتنبيه

```sql
-- عرض مراقبة معدل تسليم FCM
CREATE OR REPLACE VIEW public.v_monitor_fcm_delivery
WITH (security_invoker = true) AS
  SELECT
    -- آخر 24 ساعة
    COUNT(*) FILTER (WHERE channel = 'fcm')                    AS total_fcm_24h,
    COUNT(*) FILTER (WHERE channel = 'fcm'
                     AND status IN ('sent','delivered'))        AS delivered_24h,
    COUNT(*) FILTER (WHERE channel = 'fcm'
                     AND status IN ('failed','bounced'))        AS failed_24h,
    -- معدل التسليم
    CASE WHEN COUNT(*) FILTER (WHERE channel = 'fcm') = 0
      THEN 100.0
      ELSE ROUND(
        100.0 * COUNT(*) FILTER (
          WHERE channel = 'fcm' AND status IN ('sent','delivered')
        ) / COUNT(*) FILTER (WHERE channel = 'fcm'), 1
      )
    END AS delivery_rate_pct,
    -- تنبيه عند فشل > 10%
    CASE WHEN COUNT(*) FILTER (WHERE channel = 'fcm') > 10
          AND (100.0 * COUNT(*) FILTER (
            WHERE channel = 'fcm' AND status IN ('failed','bounced')
          ) / NULLIF(COUNT(*) FILTER (WHERE channel = 'fcm'), 0)) > 10.0
      THEN true ELSE false
    END AS alert_threshold_breached
  FROM public.notification_delivery_log
  WHERE created_at > now() - INTERVAL '24 hours';

-- إضافة فحص FCM في detect_and_raise_alerts()
-- (يُدمج في الدالة القائمة):
--   SELECT alert_threshold_breached INTO v_fcm_alert
--   FROM public.v_monitor_fcm_delivery;
--   IF v_fcm_alert THEN
--     INSERT INTO system_alerts (alert_key, severity, source, title, ...)
--     VALUES ('fcm_delivery_low', 'P0', 'notification',
--             'معدل تسليم FCM أقل من 90%', ...);
--   END IF;
```

### 20.4 أهداف الأداء (SLOs)

| المقياس | الهدف | القياس | التنبيه عند |
|---|---|---|---|
| زمن استجابة RPC | < 200ms (p95) | `app_error_events` + Edge Function logs | > 500ms (p95) |
| تحميل الصفحة الكامل | < 2 ثانية | Lighthouse CI + Web Vitals | > 3 ثوانٍ |
| معدل نجاح البصمة | > 99% | `attendance_events` ÷ محاولات | < 95% |
| تسليم الإشعارات (FCM) | > 95% | `v_monitor_fcm_delivery` | < 90% |
| Dead-letter queue | 0 | `v_monitor_integration_queue` | > 0 (P0) |
| Cron jobs | كلها succeeded | `cron.job_run_details` | أي failed (P1) |
| أخطاء fatal | 0/ساعة | `v_monitor_errors` | > 0 (P0) |

### 20.5 استعلام لوحة المراقبة الموحدة

```sql
-- استعلام واحد يُغذي لوحة المراقبة في الويب
SELECT jsonb_build_object(
  'system', public.get_system_health(),
  'operational', public.get_operational_health(),
  'slo_status', (
    SELECT jsonb_build_object(
      'fcm_delivery_ok', NOT COALESCE(alert_threshold_breached, false),
      'fcm_rate_pct', delivery_rate_pct
    ) FROM public.v_monitor_fcm_delivery
  )
) AS dashboard;
```

---

## 21. دليل النشر التشغيلي

### 21.1 الخطوات بالترتيب الصارم

```
┌─────────────────────────────────────────────────────────────────┐
│                    خط أنابيب النشر (Pipeline)                    │
│                                                                  │
│  1. npm run check:all                                           │
│     ├── typecheck (tsc --noEmit)                                │
│     ├── vitest run (web + contracts)                            │
│     ├── vite build                                              │
│     ├── dart source check                                       │
│     └── secrets scan                                            │
│                           ↓ نجاح فقط                            │
│  2. فحص ترقيم المايجريشن                                        │
│     ├── ls supabase/migrations/ | sort | tail -3                │
│     └── ls supabase/migrations/ | cut -c1-4 | sort | uniq -d   │
│                           ↓ لا تكرارات                          │
│  3. npx supabase db push                                        │
│                           ↓ نجاح                                │
│  4. npx supabase functions deploy                               │
│                           ↓ نجاح                                │
│  5. npx vercel --prod                                           │
│                           ↓ نجاح                                │
│  6. flutter build apk --release                                 │
│                           ↓ نجاح                                │
│  7. Smoke tests                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 21.2 تفصيل كل خطوة

#### الخطوة 1: الفحص الشامل

```bash
# الفحص الكامل — يجب أن ينجح 100% قبل أي نشر
npm run check:all

# ما يشمله:
# 1) npx tsc --noEmit -p apps/admin_web/tsconfig.json
# 2) npx vitest run (32 اختبار ويب + 54 اختبار contracts)
# 3) npx vite build (بناء إنتاج كامل)
# 4) dart source validation
# 5) secrets scan (لا أسرار في المستودع)
```

#### الخطوة 2: فحص ترقيم المايجريشن

```bash
# آخر 3 مايجريشن — للتأكد من الترقيم الصحيح
ls supabase/migrations/ | sort | tail -3
# المتوقع حالياً:
# 0139_v17_request_return_status.sql
# 0140_v17_attendance_history_days.sql
# 0141_v17_dispute_admin_action_catalog.sql

# كشف التكرارات — خطر حقيقي بسبب المحادثات المتوازية
ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
# المتوقع: فارغ (لا تكرارات)
# إذا ظهر رقم → إعادة ترقيم فوراً قبل المتابعة
```

#### الخطوة 3: دفع المايجريشن

```bash
# دفع المايجريشن الجديدة إلى Staging
npx supabase db push --project-ref ujzzvqsodyhnnnpkoaml

# تحقق بعد الدفع:
npx supabase db reset --linked  # ← على بيئة اختبار فقط، ليس إنتاج!
```

#### الخطوة 4: نشر Edge Functions

```bash
# نشر كل Edge Functions
FUNCTIONS=(
  identifier-sign-in
  verify-attendance-punch
  admin-create-employee
  admin-resend-invite
  webauthn-challenge
  notification-dispatcher
  retention-cleanup
  scheduled-report-runner
  live-location-map-url
  live-location-video-url
  passkey-register
  integration-outbox-worker
)

for fn in "${FUNCTIONS[@]}"; do
  echo "نشر $fn..."
  npx supabase functions deploy "$fn" \
    --project-ref ujzzvqsodyhnnnpkoaml
done
```

#### الخطوة 5: نشر الويب

```bash
# نشر على Vercel
npx vercel --prod
# URL: https://ahla-shabab-management-os.vercel.app
```

#### الخطوة 6: بناء التطبيق

```bash
cd apps/mobile_flutter

# APK مقسم حسب المعمارية
flutter build apk --release \
  --split-per-abi \
  --obfuscate \
  --split-debug-info=build/symbols \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY \
  --dart-define=APP_ENVIRONMENT=production

# AAB لـ Google Play
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY \
  --dart-define=APP_ENVIRONMENT=production
```

### 21.3 أمان المايجريشن

```
┌──────────────────────────────────────────────────────────┐
│               قواعد أمان المايجريشن الثابتة                │
├──────────────────────────────────────────────────────────┤
│ 1. لا تعدّل migration منشورة أبداً                       │
│ 2. أنشئ migration جديدة بدلاً من ذلك                     │
│ 3. تحقق من الترقيم قبل الإنشاء (uniq -d)                 │
│ 4. لا BEGIN/COMMIT صريح — Supabase يلفها تلقائياً         │
│ 5. كل migration = COMMENT يشرح الهدف + المرجع            │
│ 6. اختبار pgTAP مصاحب لكل migration تغيّر سلوكاً        │
│ 7. لا DROP TABLE — أضف deprecated + عمود بديل             │
│ 8. لا تكتب أسراراً في ملفات المايجريشن                   │
└──────────────────────────────────────────────────────────┘
```

**خطأ شائع تم مواجهته (0125):**

```sql
-- خاطئ: BEGIN/COMMIT صريح يُعطل db push
BEGIN;
  ALTER TABLE ...;
COMMIT;

-- صحيح: بدون BEGIN/COMMIT — Supabase يلفها تلقائياً
ALTER TABLE ...;
```

### 21.4 خطة التراجع (Rollback)

#### 21.4.1 تراجع المايجريشن

```sql
-- migration تراجعية — تُكتب مسبقاً لكل migration حساسة
-- الملف: supabase/migrations/XXXX_rollback_YYYY.sql

-- مثال: تراجع عن إضافة عمود
ALTER TABLE public.attendance_events
  DROP COLUMN IF EXISTS idempotency_key;

-- مثال: تراجع عن تغيير دالة (استعادة النسخة السابقة)
CREATE OR REPLACE FUNCTION public.record_attendance_event(...)
-- ... النسخة السابقة كاملة
```

#### 21.4.2 تراجع الويب

```bash
# Vercel يحتفظ بكل النشرات — تراجع فوري
npx vercel rollback
# أو من لوحة Vercel → Deployments → Promote to Production
```

#### 21.4.3 تراجع Edge Functions

```bash
# لا تراجع تلقائي — يجب إعادة نشر النسخة السابقة
git checkout HEAD~1 -- supabase/functions/$FUNCTION_NAME/
npx supabase functions deploy "$FUNCTION_NAME" \
  --project-ref ujzzvqsodyhnnnpkoaml
```

#### 21.4.4 شجرة قرار التراجع

```
                    هل المشكلة في الواجهة فقط؟
                          /           \
                        نعم           لا
                        /               \
                 vercel rollback    هل المشكلة في Edge Function؟
                                        /           \
                                      نعم           لا
                                      /               \
                               أعد نشر            هل المشكلة في المايجريشن؟
                               النسخة السابقة           /           \
                                                      نعم           لا
                                                      /               \
                                              migration         فحص شامل
                                              تراجعية          + تصعيد
```

### 21.5 ترقيم الإصدارات (Semantic Versioning)

```
المخطط: Major.Minor.Patch+Build
الحالي: 0.11.1+12

Major (0 → 1): إطلاق إنتاجي أول
Minor (11 → 12): ميزة جديدة (offline, KPI flow, etc.)
Patch (1 → 2): إصلاح خلل بدون ميزات
Build (+12 → +13): يزداد مع كل بناء
```

| الحدث | المثال | التغيير |
|---|---|---|
| ميزة جديدة (offline queue) | 0.11.1 → 0.12.0 | Minor++ |
| إصلاح خلل بصمة | 0.12.0 → 0.12.1 | Patch++ |
| إصلاح أمني عاجل | 0.12.1 → 0.12.2 | Patch++ |
| إطلاق إنتاجي | 0.12.2 → 1.0.0 | Major++ |
| migration فقط (لا تغيير تطبيق) | لا تغيير | النسخة ثابتة |

**أماكن تحديث النسخة:**

```yaml
# 1) apps/mobile_flutter/pubspec.yaml
version: 0.12.0+13

# 2) apps/admin_web/package.json (إن وُجد)
"version": "0.12.0"

# 3) Git tag
git tag -a v0.12.0 -m "feat: offline attendance queue + security hardening"
```

### 21.6 اختبارات Smoke بعد النشر

```bash
#!/usr/bin/env bash
# scripts/smoke-test-post-deploy.sh
# يُشغَّل بعد كل نشر للتأكد من صحة النظام

set -euo pipefail

SUPABASE_URL="${SUPABASE_URL:?مطلوب}"
SUPABASE_KEY="${SUPABASE_PUBLISHABLE_KEY:?مطلوب}"
WEB_URL="https://ahla-shabab-management-os.vercel.app"

echo "=== 1) فحص صحة الويب ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$WEB_URL")
[ "$HTTP_STATUS" = "200" ] && echo "OK: الويب يستجيب 200" \
                            || { echo "FAIL: الويب $HTTP_STATUS"; exit 1; }

echo "=== 2) فحص Supabase REST ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "apikey: $SUPABASE_KEY" \
  "$SUPABASE_URL/rest/v1/roles?select=id&limit=1")
[ "$HTTP_STATUS" = "200" ] && echo "OK: REST يستجيب" \
                            || { echo "FAIL: REST $HTTP_STATUS"; exit 1; }

echo "=== 3) فحص Edge Function (identifier-sign-in) ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "apikey: $SUPABASE_KEY" \
  -d '{"identifier":"smoke-test@invalid.test","password":"x"}' \
  "$SUPABASE_URL/functions/v1/identifier-sign-in")
# 400 أو 401 = الدالة تعمل وترفض المدخل — صحيح
[ "$HTTP_STATUS" = "400" ] || [ "$HTTP_STATUS" = "401" ] \
  && echo "OK: Edge Function تستجيب" \
  || { echo "FAIL: Edge Function $HTTP_STATUS"; exit 1; }

echo "=== 4) فحص صحة النظام ==="
HEALTH=$(curl -s \
  -H "apikey: $SUPABASE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  "$SUPABASE_URL/rest/v1/rpc/get_system_health")
echo "$HEALTH" | python3 -c "
import sys, json
h = json.load(sys.stdin)
dl = h.get('integration_queue',{}).get('dead_letter',0)
fatal = h.get('errors',{}).get('fatal_1h',0)
crit = h.get('security',{}).get('critical_1h',0)
if dl > 0 or fatal > 0 or crit > 0:
    print(f'WARN: dead_letter={dl}, fatal={fatal}, critical={crit}')
    sys.exit(1)
print('OK: لا تنبيهات حرجة')
"

echo ""
echo "=== كل اختبارات Smoke نجحت ==="
```

### 21.7 قائمة مراجعة النشر (Checklist)

```markdown
## قائمة مراجعة النشر — تُملأ قبل كل إصدار

- [ ] `npm run check:all` نجح بالكامل
- [ ] `flutter analyze --no-fatal-infos` بدون أخطاء
- [ ] `flutter test` — كل الاختبارات نجحت
- [ ] ترقيم المايجريشن تحقق — لا تكرارات
- [ ] `supabase test db` — كل pgTAP نجحت (محلياً)
- [ ] نسخة `pubspec.yaml` محدثة
- [ ] Git tag منشأ
- [ ] `db push` نجح على Staging
- [ ] `functions deploy` نجح لكل الدوال
- [ ] `vercel --prod` نجح
- [ ] `flutter build apk --release` نجح
- [ ] Smoke tests نجحت
- [ ] get_system_health() بدون تنبيهات P0
- [ ] migration تراجعية مكتوبة (للتغييرات الحساسة)
- [ ] Co-Authored-By في رسالة الـ commit
```

---

Now I have a comprehensive picture of the codebase. Let me write the four sections.

---

## 22. إعادة هيكلة Flutter

### 22.1 الحالة الحالية

المجلد `apps/mobile_flutter/lib/features/mobile_pages/` يحتوي **42 ملفًا** في بنية مسطحة واحدة:

```
mobile_pages/
  employee_home_page.dart
  executive_home_page.dart
  executive_brief_page.dart
  executive_people_page.dart
  executive_decisions_page.dart
  executive_disputes_page.dart
  executive_governance_page.dart
  executive_reports_page.dart
  executive_risk_center_page.dart
  executive_emergency_page.dart
  executive_attendance_tab.dart
  executive_employee_summary_page.dart
  executive_location_page.dart
  manager_home_page.dart
  manager_operations_page.dart
  mobile_attendance_page.dart
  mobile_attendance_services_page.dart
  attendance_history_page.dart
  monthly_attendance_statement_page.dart
  mobile_requests_page.dart
  mobile_request_detail_page.dart
  mobile_kpi_page.dart
  kpi_evaluation_detail_page.dart
  mobile_disputes_page.dart
  mobile_self_service_page.dart
  mobile_tasks_page.dart
  mobile_team_page.dart
  mobile_daily_reports_page.dart
  mobile_profile_page.dart
  mobile_official_feed_page.dart
  mobile_feed_detail_page.dart
  mobile_notifications_page.dart
  mobile_action_inbox_page.dart
  mobile_action_router.dart
  mobile_action_deep_link_page.dart
  mobile_location_request_deep_link_page.dart
  location_requests_page.dart
  location_incoming_overlay.dart
  live_tracking_session_page.dart
  passkey_devices_page.dart
  org_chart_page.dart
  mobile_widgets.dart
```

المشاكل:
- **لا تصنيف ميزوي (feature-first):** كل الصفحات مختلطة — تنفيذية وموظف ومدير وحضور وطلبات.
- **ملف providers عملاق واحد:** `mobile_providers.dart` (300+ سطر) يضم 25+ provider بلا تصنيف.
- **ملف models عملاق واحد:** `mobile_models.dart` يحتوي كل الكلاسات.
- **لا يُستخدم `AsyncNotifier`:** كل الـ providers من نوع `FutureProvider` بدون إمكانية mutation أو إعادة تحميل مبرمَجة.

### 22.2 الهيكل المستهدف (Feature-First)

```
lib/features/
  home/
    employee_home_page.dart
    manager_home_page.dart
    home_providers.dart
    home_models.dart
  executive/                    ← 14 صفحة
    executive_home_page.dart
    executive_brief_page.dart
    executive_people_page.dart
    executive_decisions_page.dart
    executive_disputes_page.dart
    executive_governance_page.dart
    executive_reports_page.dart
    executive_risk_center_page.dart
    executive_emergency_page.dart
    executive_attendance_tab.dart
    executive_employee_summary_page.dart
    executive_providers.dart
    executive_models.dart
  attendance/
    mobile_attendance_page.dart
    mobile_attendance_services_page.dart
    attendance_history_page.dart
    monthly_attendance_statement_page.dart
    attendance_providers.dart
    attendance_models.dart
  requests/
    mobile_requests_page.dart
    mobile_request_detail_page.dart
    requests_providers.dart
    requests_models.dart
  kpi/
    mobile_kpi_page.dart
    kpi_evaluation_detail_page.dart
    kpi_providers.dart
    kpi_models.dart
  location/
    executive_location_page.dart
    location_requests_page.dart
    location_incoming_overlay.dart
    live_tracking_session_page.dart
    mobile_location_request_deep_link_page.dart
    location_providers.dart    ← نقل من location_service.dart
    location_models.dart
  disputes/
    mobile_disputes_page.dart
    disputes_providers.dart
  feed/
    mobile_official_feed_page.dart
    mobile_feed_detail_page.dart
    feed_providers.dart
  notifications/
    mobile_notifications_page.dart
    notifications_providers.dart
  actions/
    mobile_action_inbox_page.dart
    mobile_action_router.dart
    mobile_action_deep_link_page.dart
    actions_providers.dart
  profile/
    mobile_profile_page.dart
    passkey_devices_page.dart
    profile_providers.dart
  operations/
    manager_operations_page.dart
    mobile_tasks_page.dart
    mobile_team_page.dart
    mobile_daily_reports_page.dart
    mobile_self_service_page.dart
    operations_providers.dart
  organization/
    org_chart_page.dart
  shared/
    mobile_widgets.dart        ← ودجات مشتركة
```

### 22.3 استراتيجية النقل التدريجي — 4 مراحل

#### المرحلة 1: إنشاء المجلدات + نسخ الملفات

```bash
# إنشاء هيكل المجلدات
cd apps/mobile_flutter/lib/features
mkdir -p home executive attendance requests kpi location \
         disputes feed notifications actions profile operations \
         organization shared
```

```dart
// نقل الملف مع الحفاظ على الأصل مؤقتاً
// مثال: نقل executive_home_page.dart → executive/
// الملف الجديد: executive/executive_home_page.dart
// التعديل: تحديث مسارات import الداخلية فقط
```

#### المرحلة 2: إنشاء ملفات Re-Export في الموقع القديم

```dart
// mobile_pages/executive_home_page.dart — re-export مؤقت
export 'package:ahla_shabab_management_os/features/executive/executive_home_page.dart';
```

هذا يضمن عدم كسر أي import خارجي خلال فترة الانتقال.

#### المرحلة 3: تحديث كل الـ imports في المشروع

```dart
// قبل:
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_home_page.dart';

// بعد:
import 'package:ahla_shabab_management_os/features/executive/executive_home_page.dart';
```

التحقق الآلي:

```bash
# البحث عن imports قديمة متبقية
grep -r "mobile_pages/" lib/ --include="*.dart" \
  | grep -v "// re-export" \
  | grep -v "mobile_pages.dart"
```

#### المرحلة 4: حذف ملفات Re-Export + مجلد mobile_pages القديم

```bash
# التحقق من عدم وجود مراجع متبقية
grep -rn "mobile_pages" lib/ --include="*.dart"
# إذا نظيف → حذف
rm -rf lib/features/mobile_pages/
```

### 22.4 توحيد Riverpod — التحول إلى AsyncNotifier

الحالة الحالية: كل الـ providers تستخدم `FutureProvider` الذي لا يدعم mutation أو إعادة بناء مبرمَجة:

```dart
// الحالي — FutureProvider (قراءة فقط، لا mutation)
final employeeHomeProvider = FutureProvider<EmployeeHomeSummary>((ref) async {
  try {
    final data = await _withTimeout(
      ref.watch(supabaseProvider).rpc<dynamic>('get_employee_home'),
    );
    final result = EmployeeHomeSummary.fromJson(_asMap(data));
    OfflineCache.instance.put(OfflineCache.employeeHome, _asMap(data));
    return result;
  } catch (e) {
    final cached = await OfflineCache.instance.get(OfflineCache.employeeHome);
    if (cached != null) return EmployeeHomeSummary.fromJson(_asMap(cached));
    rethrow;
  }
});
```

التحول المستهدف لثلاث فئات:

**الفئة أ — `AsyncNotifier` للمعقّد (يحتاج mutation + refresh):**

```dart
// المستهدف — AsyncNotifier مع mutation + offline cache
class EmployeeHomeNotifier extends AsyncNotifier<EmployeeHomeSummary> {
  @override
  Future<EmployeeHomeSummary> build() async {
    try {
      final sb = ref.watch(supabaseProvider);
      final data = await rpcWithTimeout(
        sb.rpc<dynamic>('get_employee_home'),
      );
      final result = EmployeeHomeSummary.fromJson(_asMap(data));
      OfflineCache.instance.put(OfflineCache.employeeHome, _asMap(data));
      return result;
    } catch (e) {
      final cached = await OfflineCache.instance.get(OfflineCache.employeeHome);
      if (cached != null) {
        return EmployeeHomeSummary.fromJson(_asMap(cached));
      }
      rethrow;
    }
  }

  /// إعادة تحميل البيانات (pull-to-refresh)
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

final employeeHomeProvider =
    AsyncNotifierProvider<EmployeeHomeNotifier, EmployeeHomeSummary>(
  EmployeeHomeNotifier.new,
);
```

```dart
// استخدام في الصفحة — refresh مباشر بدون ref.invalidate
RefreshIndicator(
  onRefresh: () => ref.read(employeeHomeProvider.notifier).refresh(),
  child: /* ... */,
)
```

**الفئة ب — `FutureProvider.family` يبقى كما هو (قراءة بمعامل):**

```dart
// هذا النمط مقبول — لا يحتاج mutation
final mobileRequestDetailProvider =
    FutureProvider.family<MobileRequestDetail, String>((ref, requestId) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_mobile_request_detail', params: {'p_request_id': requestId});
  return MobileRequestDetail.fromJson(_asMap(data));
});
```

**الفئة ج — `Provider` للثابت (بيانات تكوينية):**

```dart
// بيانات ثابتة لا تتغير خلال الجلسة
final releaseGovernanceProvider = Provider<ReleaseGovernance>((ref) {
  return const ReleaseGovernance(
    minimumVersion: '0.11.0',
    updateUrl: 'https://play.google.com/store/apps/details?id=com.ahlashabab.os',
  );
});
```

### 22.5 تقسيم ملف Models

```dart
// قبل: mobile_models.dart (30+ كلاس في ملف واحد)

// بعد: كل feature يمتلك ملف models خاص

// attendance/attendance_models.dart
class AttendanceHistoryItem { /* ... */ }
class MonthlyAttendanceStatement { /* ... */ }
class AttendanceDaySummary { /* ... */ }

// executive/executive_models.dart
class ExecutiveDashboardSummary { /* ... */ }
class ExecutiveBriefItem { /* ... */ }
class ExecutiveDecision { /* ... */ }

// requests/requests_models.dart
class MobileRequest { /* ... */ }
class MobileRequestDetail { /* ... */ }

// shared/shared_models.dart  ← كلاسات مشتركة بين أكثر من feature
class EmployeeHomeSummary { /* ... */ }
class ManagerDashboardSummary { /* ... */ }
```

### 22.6 جدول التنفيذ

| المرحلة | المدة | المحتوى | معيار النجاح |
|---|---|---|---|
| M1 | يوم 1 | إنشاء مجلدات + نقل 14 صفحة executive | `flutter analyze --no-fatal-infos` نظيف |
| M2 | يوم 2 | نقل attendance (4) + requests (2) + kpi (2) + re-exports | `flutter test` — 29 اختبار يمرّ |
| M3 | يوم 3 | نقل location (5) + actions (3) + بقية الميزات | كل imports محدّثة — لا re-exports متبقية |
| M4 | يوم 4 | تقسيم providers + تحويل 8 providers إلى AsyncNotifier | `flutter analyze` + `flutter test` نظيف |

---

## 23. إعادة هيكلة الويب

### 23.1 الحالة الحالية

```
apps/admin_web/src/features/
  actions/          (2 ملفات)   ActionCenterPage + useActionCenter
  advanced/         (4 ملفات)   AttendanceOps + KpiCycles + Disputes + Lifecycle + useAdvancedOperations
  attendance/       (3 ملفات)   AttendancePage + MonthlyStatement + hooks
  auth/             (8 ملفات)   Login + PasswordSetup + WebRelease + AuthProvider + access
  communications/   (2 ملفات)   OfficialFeed
  employees/        (5 ملفات)   Employees + Detail + Create + hooks
  holidays/         (2 ملفات)   OfficialHolidays + useHolidays
  management/       (18 ملفات)  Access + Org + Recruitment + Reports + System + LiveLocation + ...
  mock/             (2 ملفات)   domainMocks + loadDomainMocks
  notifications/    (2 ملفات)   NotificationsPage + useNotifications
  performance/      (4 ملفات)   PerformancePage + KpiEditor + hooks + workflowStatus
  requests/         (2 ملفات)   RequestsPage + useRequests
  workspaces/       (4 ملفات)   Shell + Dashboard + access
```

**13 مجلد feature، 70 ملف TypeScript/TSX.**

المشاكل:
- **مجلد `management/` منتفخ:** 18 ملف يغطي 10 صفحات غير مترابطة (Access، Organization، Recruitment، Reports، LiveLocation، System...).
- **`advanced/` غامض الاسم:** يحتوي AttendanceOperations + KpiCycles + Disputes — ثلاث ميزات مختلفة.
- **7 صفحات ناقصة** لا تزال غير مبنية.

### 23.2 الصفحات الـ 7 الناقصة

| # | الصفحة | المسار المقترح | الصلاحية |
|---|---|---|---|
| 1 | إجازات رسمية (تعديل/إنشاء) | `/hr/holidays/:id` | `holidays.manage` |
| 2 | إعدادات المواعيد والورديات | `/admin/settings/shifts` | `system.settings.manage` |
| 3 | تفاصيل طلب فردي | `/hr/requests/:requestId` | `requests.request.read` |
| 4 | كشف شهري مفصّل (طباعة) | `/hr/attendance/statement/:employeeId` | `attendance.record.read` |
| 5 | إدارة أجهزة الحضور | `/admin/settings/devices` | `system.device.manage` |
| 6 | هيكل تنظيمي تفاعلي | `/admin/organization/chart` | `organization.org_chart.read` |
| 7 | إعدادات عامة (بريد/إشعارات) | `/admin/settings/general` | `system.settings.manage` |

### 23.3 إعادة هيكلة management/ و advanced/

```
features/
  management/           ← يبقى لكن يُقلَّص
    AccessPage.tsx
    useAdminOperations.ts
  organization/         ← يُنقل من management
    OrganizationPage.tsx
    OrgChartInteractivePage.tsx    ← جديد (#6)
  recruitment/          ← يُنقل من management
    RecruitmentPage.tsx
  reports/              ← يُنقل من management
    ReportsPage.tsx
    ReportSchedulerPage.tsx
  system/               ← يُنقل من management
    SystemPage.tsx
    ShiftSettingsPage.tsx           ← جديد (#2)
    DeviceManagementPage.tsx        ← جديد (#5)
    GeneralSettingsPage.tsx         ← جديد (#7)
  live-location/        ← يُنقل من management
    LiveLocationPage.tsx
    LiveLocationMap.tsx
    LiveLocationResultCard.tsx
    ExecutiveMonitoringPage.tsx
    useControlCenters.ts
    controlCenterTypes.ts
  enterprise/           ← يُنقل من management
    EnterpriseManagementPage.tsx
    useEnterpriseOperations.ts
    useEnterpriseManagement.ts
  audit/                ← يُنقل من management
    AuditSecurityPage.tsx
  operations/           ← يُنقل من management
    OperationsCenterPage.tsx
  attendance/           ← يُدمج advanced/AttendanceOps هنا
    AttendancePage.tsx
    AttendanceOperationsPage.tsx    ← من advanced/
    MonthlyStatementSection.tsx
    MonthlyStatementPrintPage.tsx   ← جديد (#4)
    useAttendanceDashboard.ts
    useMonthlyStatement.ts
  disputes/             ← يُنقل من advanced/
    DisputesPage.tsx
  performance/          ← يُدمج advanced/KpiCycles هنا
    PerformancePage.tsx
    KpiCyclesPage.tsx               ← من advanced/
    KpiEvaluationEditor.tsx
    usePerformance.ts
    workflowStatus.ts
  requests/
    RequestsPage.tsx
    RequestDetailPage.tsx           ← جديد (#3)
    useRequests.ts
```

### 23.4 EmployeeDetailPage — 8 تبويبات

الصفحة الحالية تعرض كل الأقسام بشكل عمودي. التحول المطلوب إلى نظام تبويبات:

```tsx
// features/employees/EmployeeDetailPage.tsx
const TABS = [
  { id: 'basic',        label: 'البيانات الأساسية',   icon: UserRound },
  { id: 'employment',   label: 'البيانات الوظيفية',   icon: BriefcaseBusiness },
  { id: 'attendance',   label: 'الحضور والانصراف',    icon: Clock3 },
  { id: 'requests',     label: 'الطلبات',            icon: FileText },
  { id: 'kpi',          label: 'تقييم الأداء',        icon: Gauge },
  { id: 'devices',      label: 'الأجهزة والمفاتيح',   icon: ShieldCheck },
  { id: 'disciplinary', label: 'الإجراءات التأديبية', icon: AlertTriangle },
  { id: 'audit',        label: 'سجل التدقيق',        icon: ScrollText },
] as const;

type TabId = (typeof TABS)[number]['id'];

export function EmployeeDetailPage() {
  const [activeTab, setActiveTab] = useState<TabId>('basic');
  const { employeeId } = useParams();
  const query = useEmployee360(employeeId);

  // ...header + metric cards (يبقيان ثابتين فوق التبويبات)

  return (
    <div className="space-y-6">
      {/* رأس الصفحة + بطاقات المقاييس */}
      <EmployeeHeader item={query.data} />
      <EmployeeMetrics item={query.data} />

      {/* شريط التبويبات */}
      <nav className="flex gap-1 overflow-x-auto border-b border-[var(--border)] pb-px"
           role="tablist" aria-label="أقسام ملف الموظف">
        {TABS.map(tab => (
          <button
            key={tab.id}
            role="tab"
            aria-selected={activeTab === tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`tab-btn ${activeTab === tab.id ? 'tab-btn-active' : ''}`}
          >
            <tab.icon className="size-4" aria-hidden="true" />
            {tab.label}
          </button>
        ))}
      </nav>

      {/* محتوى التبويب */}
      <div role="tabpanel">
        {activeTab === 'basic'        && <BasicInfoTab item={query.data!} />}
        {activeTab === 'employment'   && <EmploymentTab item={query.data!} />}
        {activeTab === 'attendance'   && <AttendanceTab employeeId={employeeId!} />}
        {activeTab === 'requests'     && <RequestsTab item={query.data!} />}
        {activeTab === 'kpi'          && <KpiTab item={query.data!} />}
        {activeTab === 'devices'      && <DevicesTab employeeId={employeeId!} />}
        {activeTab === 'disciplinary' && <DisciplinaryTab employeeId={employeeId!} />}
        {activeTab === 'audit'        && <AuditTab employeeId={employeeId!} />}
      </div>
    </div>
  );
}
```

```tsx
// تبويب الحضور — يدمج MonthlyStatementSection + تفاصيل إضافية
function AttendanceTab({ employeeId }: { employeeId: string }) {
  return (
    <div className="space-y-5">
      <MonthlyStatementSection employeeId={employeeId} />
      <AttendanceCorrectionsSection employeeId={employeeId} />
    </div>
  );
}

// تبويب الأجهزة — مفاتيح Passkey المسجلة للموظف
function DevicesTab({ employeeId }: { employeeId: string }) {
  const devices = useEmployeeDevices(employeeId);
  if (devices.isLoading) return <SkeletonCard className="h-40" />;
  if (devices.isError) return <ErrorState title="تعذر تحميل الأجهزة" onRetry={() => void devices.refetch()} />;
  return (
    <article className="card overflow-hidden">
      <div className="border-b border-[var(--border)] p-5">
        <h3 className="font-black">الأجهزة ومفاتيح الحضور</h3>
      </div>
      <div className="divide-y divide-[var(--border)]">
        {devices.data?.length === 0
          ? <p className="muted p-5 text-sm">لا توجد أجهزة مسجلة.</p>
          : devices.data?.map(device => (
            <div key={device.id} className="flex items-center justify-between p-4">
              <div>
                <p className="font-bold">{device.deviceName}</p>
                <p className="muted mt-1 text-xs">
                  {device.trusted ? 'موثوق' : 'غير موثوق'} • آخر استخدام: {device.lastUsed}
                </p>
              </div>
              <StatusBadge value={device.trusted ? 'active' : 'suspended'} />
            </div>
          ))
        }
      </div>
    </article>
  );
}
```

### 23.5 سير مراجعة الحضور

```tsx
// features/attendance/AttendanceCorrectionReview.tsx
// سير عمل مراجعة تصحيحات الحضور المقدَّمة من الموظفين

interface CorrectionRequest {
  id: string;
  employeeName: string;
  employeeCode: string;
  originalDate: string;
  originalCheckIn: string | null;
  originalCheckOut: string | null;
  requestedCheckIn: string;
  requestedCheckOut: string;
  reason: string;
  status: 'pending_review' | 'approved' | 'rejected';
  submittedAt: string;
}

export function AttendanceCorrectionReview() {
  const corrections = useAttendanceCorrections();
  const reviewMutation = useReviewCorrection();

  const onReview = async (id: string, decision: 'approved' | 'rejected', note: string) => {
    await reviewMutation.mutateAsync({ correctionId: id, decision, reviewNote: note });
    void corrections.refetch();
  };

  return (
    <section className="card overflow-hidden">
      <div className="border-b border-[var(--border)] p-5 flex items-center justify-between">
        <h3 className="font-black">طلبات تصحيح الحضور</h3>
        <span className="badge-warning">{corrections.data?.filter(c => c.status === 'pending_review').length ?? 0} بانتظار المراجعة</span>
      </div>
      <div className="divide-y divide-[var(--border)]">
        {corrections.data?.map(correction => (
          <CorrectionRow
            key={correction.id}
            correction={correction}
            onApprove={(note) => void onReview(correction.id, 'approved', note)}
            onReject={(note) => void onReview(correction.id, 'rejected', note)}
            isPending={reviewMutation.isPending}
          />
        ))}
      </div>
    </section>
  );
}
```

### 23.6 تحديث المسارات في App.tsx

```tsx
// التغييرات المطلوبة في app/App.tsx بعد إعادة الهيكلة

// المسارات الجديدة تحت /hr
<Route path="requests/:requestId" element={
  <RequirePermission perm="requests.request.read">
    <RequestDetailPage />
  </RequirePermission>
} />
<Route path="attendance/statement/:employeeId" element={
  <RequirePermission perm="attendance.record.read">
    <MonthlyStatementPrintPage />
  </RequirePermission>
} />

// المسارات الجديدة تحت /admin
<Route path="settings/shifts" element={
  <RequirePermission perm="system.settings.manage">
    <ShiftSettingsPage />
  </RequirePermission>
} />
<Route path="settings/devices" element={
  <RequirePermission perm="system.device.manage">
    <DeviceManagementPage />
  </RequirePermission>
} />
<Route path="settings/general" element={
  <RequirePermission perm="system.settings.manage">
    <GeneralSettingsPage />
  </RequirePermission>
} />
<Route path="organization/chart" element={
  <RequirePermission perm="organization.org_chart.read">
    <OrgChartInteractivePage />
  </RequirePermission>
} />
```

---

## 24. إعادة هيكلة قاعدة البيانات

### 24.1 الحالة الحالية

- **141 migration** (0001–0141) منشورة على staging.
- دالة الحضور الحالية `finalize_verified_attendance()` في migration 0089 — تتعامل مع WebAuthn فقط ولا تحسب تأخير/انصراف مبكر.
- دوال `calculate_late_minutes()` و `calculate_early_departure_minutes()` موجودة في 0005 لكنها **لا تُستدعى تلقائيًا** — يدوية فقط.
- لا يوجد `pg_cron` job للتسوية اليومية — كل الحسابات تتم عند الاستعلام (query-time).
- عدة RPC overloads متكررة تراكمت عبر الـ migrations.

### 24.2 Migration 0142: توحيد validate_attendance_punch()

```sql
-- 0142_unified_validate_attendance_punch.sql
-- توحيد منطق التحقق من بصمة الحضور لاستخدامه في كلا المسارين:
--   1) WebAuthn (finalize_verified_attendance)
--   2) Manual/Admin (record_manual_attendance)

create or replace function public.validate_attendance_punch(
  p_employee_id   uuid,
  p_event_type    text,     -- 'CHECK_IN' | 'CHECK_OUT'
  p_event_at      timestamptz,
  p_latitude      double precision default null,
  p_longitude     double precision default null,
  p_accuracy      double precision default null,
  p_is_mock       boolean default false,
  p_is_manual     boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_employee    public.employees%rowtype;
  v_shift       public.shifts%rowtype;
  v_geofence    public.geofences%rowtype;
  v_period      public.attendance_periods%rowtype;
  v_distance    double precision;
  v_late_min    integer := 0;
  v_early_min   integer := 0;
  v_overtime    integer := 0;
  v_event_date  date;
  v_shift_start timestamptz;
  v_shift_end   timestamptz;
  v_result      jsonb;
begin
  -- 1) التحقق من وجود الموظف ونشاطه
  select * into strict v_employee
  from public.employees
  where id = p_employee_id and status = 'active';

  if not found then
    return jsonb_build_object(
      'valid', false,
      'error', 'employee_not_active'
    );
  end if;

  -- 2) التحقق من الفترة — غير مقفلة
  v_event_date := (p_event_at at time zone 'Asia/Jerusalem')::date;

  select * into v_period
  from public.attendance_periods
  where v_event_date between start_date and end_date
    and status != 'finalized'
  order by start_date desc
  limit 1;

  if v_period.id is null then
    return jsonb_build_object(
      'valid', false,
      'error', 'attendance_period_finalized'
    );
  end if;

  -- 3) رفض الموقع الوهمي (ما لم يكن يدوياً)
  if p_is_mock and not p_is_manual then
    return jsonb_build_object(
      'valid', false,
      'error', 'attendance_mock_location_rejected'
    );
  end if;

  -- 4) التحقق من Geofence (إذا كان الموقع مطلوباً)
  if p_latitude is not null and not p_is_manual then
    select g.* into v_geofence
    from public.geofences g
    join public.work_sites ws on ws.geofence_id = g.id
    where ws.id = v_employee.work_site_id
      and g.is_active = true
    limit 1;

    if v_geofence.id is not null then
      v_distance := public.geo_distance_meters(
        p_latitude, p_longitude,
        v_geofence.latitude, v_geofence.longitude
      );
      if v_distance > v_geofence.radius_meters then
        return jsonb_build_object(
          'valid', false,
          'error', 'attendance_outside_complex',
          'distance', round(v_distance::numeric, 1),
          'allowed_radius', v_geofence.radius_meters
        );
      end if;
    end if;
  end if;

  -- 5) التحقق من الترتيب (CHECK_IN قبل CHECK_OUT)
  if p_event_type = 'CHECK_OUT' then
    if not exists (
      select 1 from public.attendance_events
      where employee_id = p_employee_id
        and event_type = 'CHECK_IN'
        and (event_at at time zone 'Asia/Jerusalem')::date = v_event_date
        and voided_at is null
    ) then
      return jsonb_build_object(
        'valid', false,
        'error', 'attendance_check_in_required'
      );
    end if;
  end if;

  -- 6) حساب الوردية والتأخير/المبكر/الإضافي
  select s.* into v_shift
  from public.shifts s
  join public.roster_entries re on re.shift_id = s.id
  where re.employee_id = p_employee_id
    and re.roster_date = v_event_date
  limit 1;

  if v_shift.id is not null then
    v_shift_start := v_event_date + v_shift.start_time;
    v_shift_end   := v_event_date + v_shift.end_time;
    -- التعامل مع الورديات الليلية
    if v_shift.end_time < v_shift.start_time then
      v_shift_end := v_shift_end + interval '1 day';
    end if;

    if p_event_type = 'CHECK_IN' then
      v_late_min := public.calculate_late_minutes(
        p_event_at, v_shift.start_time,
        coalesce(v_shift.grace_minutes, 0), v_event_date
      );
    elsif p_event_type = 'CHECK_OUT' then
      v_early_min := public.calculate_early_departure_minutes(
        p_event_at, v_shift.end_time, v_event_date
      );
      -- حساب العمل الإضافي (بعد نهاية الوردية بـ 15 دقيقة على الأقل)
      if p_event_at > (v_shift_end + interval '15 minutes') then
        v_overtime := extract(epoch from (p_event_at - v_shift_end))::integer / 60;
      end if;
    end if;
  end if;

  v_result := jsonb_build_object(
    'valid', true,
    'event_date', v_event_date,
    'period_id', v_period.id,
    'shift_id', v_shift.id,
    'late_minutes', v_late_min,
    'early_departure_minutes', v_early_min,
    'overtime_minutes', v_overtime,
    'distance_meters', round(coalesce(v_distance, 0)::numeric, 1)
  );

  return v_result;
end;
$$;

comment on function public.validate_attendance_punch
  is 'تحقق موحّد من بصمة الحضور — يُستخدم من WebAuthn ومن الإدخال اليدوي. يُرجع late/early/overtime.';
```

### 24.3 Migration 0143: دالة التسوية اليومية (pg_cron 23:59)

```sql
-- 0143_daily_attendance_finalization_cron.sql
-- التسوية اليومية: تعمل عند 23:59 بتوقيت القدس يومياً عبر pg_cron.
-- تحسب: التأخر، الانصراف المبكر، العمل الإضافي، الغياب.

create or replace function public.daily_attendance_finalization()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_today         date := (now() at time zone 'Asia/Jerusalem')::date;
  v_processed     integer := 0;
  v_absent_count  integer := 0;
  v_late_count    integer := 0;
  v_early_count   integer := 0;
  v_overtime_count integer := 0;
  v_rec           record;
  v_check_in      public.attendance_events%rowtype;
  v_check_out     public.attendance_events%rowtype;
  v_shift         public.shifts%rowtype;
  v_late          integer;
  v_early         integer;
  v_overtime      integer;
  v_shift_start   timestamptz;
  v_shift_end     timestamptz;
begin
  -- معالجة كل موظف لديه جدول عمل اليوم
  for v_rec in
    select re.employee_id, re.shift_id, re.roster_date
    from public.roster_entries re
    join public.employees e on e.id = re.employee_id and e.status = 'active'
    where re.roster_date = v_today
      and re.status in ('scheduled', 'present', 'late')
  loop
    v_processed := v_processed + 1;

    -- جلب الوردية
    select * into v_shift from public.shifts where id = v_rec.shift_id;

    -- جلب أول CHECK_IN
    select * into v_check_in
    from public.attendance_events
    where employee_id = v_rec.employee_id
      and event_type = 'CHECK_IN'
      and (event_at at time zone 'Asia/Jerusalem')::date = v_today
      and voided_at is null
    order by event_at asc
    limit 1;

    -- جلب آخر CHECK_OUT
    select * into v_check_out
    from public.attendance_events
    where employee_id = v_rec.employee_id
      and event_type = 'CHECK_OUT'
      and (event_at at time zone 'Asia/Jerusalem')::date = v_today
      and voided_at is null
    order by event_at desc
    limit 1;

    -- حالة الغياب: لا CHECK_IN على الإطلاق
    if v_check_in.id is null then
      -- تسجيل غياب ما لم يكن في إجازة معتمدة
      if not exists (
        select 1 from public.leave_requests lr
        where lr.employee_id = v_rec.employee_id
          and lr.status = 'approved'
          and v_today between lr.start_date and lr.end_date
      ) then
        update public.roster_entries
        set status = 'absent',
            updated_at = now()
        where employee_id = v_rec.employee_id
          and roster_date = v_today;

        v_absent_count := v_absent_count + 1;
      end if;
      continue;
    end if;

    -- حساب التأخر
    v_late := 0;
    if v_shift.id is not null then
      v_late := public.calculate_late_minutes(
        v_check_in.event_at,
        v_shift.start_time,
        coalesce(v_shift.grace_minutes, 0),
        v_today
      );
    end if;

    -- حساب الانصراف المبكر
    v_early := 0;
    if v_check_out.id is not null and v_shift.id is not null then
      v_early := public.calculate_early_departure_minutes(
        v_check_out.event_at,
        v_shift.end_time,
        v_today
      );

      -- حساب العمل الإضافي
      v_shift_end := v_today + v_shift.end_time;
      if v_shift.end_time < v_shift.start_time then
        v_shift_end := v_shift_end + interval '1 day';
      end if;
      v_overtime := 0;
      if v_check_out.event_at > (v_shift_end + interval '15 minutes') then
        v_overtime := extract(epoch from (v_check_out.event_at - v_shift_end))::integer / 60;
      end if;
    end if;

    -- تحديث ملخص اليوم
    insert into public.daily_attendance_summary (
      employee_id, summary_date, shift_id,
      check_in_at, check_out_at,
      late_minutes, early_departure_minutes, overtime_minutes,
      status, finalized_at
    ) values (
      v_rec.employee_id, v_today, v_shift.id,
      v_check_in.event_at, v_check_out.event_at,
      greatest(v_late, 0), greatest(v_early, 0), greatest(coalesce(v_overtime, 0), 0),
      case
        when v_late > 0 then 'late'
        else 'present'
      end,
      now()
    )
    on conflict (employee_id, summary_date) do update set
      check_in_at = excluded.check_in_at,
      check_out_at = excluded.check_out_at,
      late_minutes = excluded.late_minutes,
      early_departure_minutes = excluded.early_departure_minutes,
      overtime_minutes = excluded.overtime_minutes,
      status = excluded.status,
      finalized_at = excluded.finalized_at;

    if v_late > 0 then v_late_count := v_late_count + 1; end if;
    if v_early > 0 then v_early_count := v_early_count + 1; end if;
    if coalesce(v_overtime, 0) > 0 then v_overtime_count := v_overtime_count + 1; end if;
  end loop;

  -- تسجيل حدث تدقيق
  perform public.log_audit_event(
    'attendance.daily_finalization',
    'system',
    jsonb_build_object(
      'date', v_today,
      'processed', v_processed,
      'absent', v_absent_count,
      'late', v_late_count,
      'early_departure', v_early_count,
      'overtime', v_overtime_count
    )
  );

  return jsonb_build_object(
    'date', v_today,
    'processed', v_processed,
    'absent', v_absent_count,
    'late', v_late_count,
    'early_departure', v_early_count,
    'overtime', v_overtime_count
  );
end;
$$;

comment on function public.daily_attendance_finalization()
  is 'تسوية يومية — تُشغَّل عبر pg_cron عند 23:59 بتوقيت القدس. تحسب التأخر/المبكر/الإضافي/الغياب.';

-- جدول الملخص اليومي
create table if not exists public.daily_attendance_summary (
  id                       uuid primary key default gen_random_uuid(),
  employee_id              uuid not null references public.employees(id),
  summary_date             date not null,
  shift_id                 uuid references public.shifts(id),
  check_in_at              timestamptz,
  check_out_at             timestamptz,
  late_minutes             integer not null default 0,
  early_departure_minutes  integer not null default 0,
  overtime_minutes         integer not null default 0,
  status                   text not null default 'pending'
                           check (status in ('pending','present','late','absent','excused','holiday')),
  finalized_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz,
  unique (employee_id, summary_date)
);

create index if not exists ix_daily_summary_date on public.daily_attendance_summary(summary_date);
create index if not exists ix_daily_summary_emp  on public.daily_attendance_summary(employee_id, summary_date desc);

alter table public.daily_attendance_summary enable row level security;

create policy daily_summary_read on public.daily_attendance_summary
  for select using (
    public.current_is_full_access()
    or public.can_access_employee(employee_id)
  );

-- تسجيل pg_cron job — 23:59 بتوقيت القدس يومياً
select cron.schedule(
  'daily-attendance-finalization',
  '59 23 * * *',
  $$select public.daily_attendance_finalization()$$
);

comment on column public.daily_attendance_summary.late_minutes
  is 'دقائق التأخر بعد السماحية. 0 = في الوقت.';
comment on column public.daily_attendance_summary.overtime_minutes
  is 'دقائق العمل الإضافي بعد نهاية الوردية بـ 15 دقيقة.';
```

### 24.4 Migration 0144: تنظيف RPC Overloads

```sql
-- 0144_cleanup_rpc_overloads.sql
-- تنظيف دوال RPC مكررة/متعارضة تراكمت عبر 141 migration.

-- 1) حذف overloads قديمة لـ get_employee_home (أُعيد تعريفها في 0101, 0104, 0125)
-- نحتفظ فقط بالتعريف الأخير (0125)
do $$
declare
  v_count integer;
begin
  -- عدّ التعريفات الحالية
  select count(*) into v_count
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_employee_home';

  if v_count > 1 then
    raise notice 'تنظيف: % تعريفات لـ get_employee_home — سيُحتفظ بالأخير فقط', v_count;
  end if;
end;
$$;

-- 2) إزالة دالة record_attendance_event القديمة (استُبدلت بـ finalize_verified_attendance في 0089)
drop function if exists public.record_attendance_event(uuid, text, double precision, double precision, double precision, text, boolean);

-- 3) توحيد get_my_attendance_history — حذف النسخة بدون p_days
drop function if exists public.get_my_attendance_history(integer);

-- 4) إزالة RPCs تجريبية لم تُستخدم
drop function if exists public.get_employee_timeline(uuid);
drop function if exists public.get_attendance_heatmap(uuid, date, date);

-- تسجيل تدقيق
select public.log_audit_event(
  'system.migration',
  'cleanup',
  '{"migration": "0144", "action": "cleanup_rpc_overloads", "removed": ["record_attendance_event","get_my_attendance_history(int)","get_employee_timeline","get_attendance_heatmap"]}'::jsonb
);
```

### 24.5 ملخص الـ Migrations المقترحة

| Migration | المحتوى | الاعتمادية |
|---|---|---|
| `0142_unified_validate_attendance_punch` | دالة تحقق موحّدة للبصمة | 0005, 0089 |
| `0143_daily_attendance_finalization_cron` | جدول ملخص يومي + pg_cron job | 0142, 0047 |
| `0144_cleanup_rpc_overloads` | حذف دوال مكررة/قديمة | مستقل |

> **تحذير:** قبل ترقيم أي migration جديدة، نفّذ:
> ```bash
> ls supabase/migrations/ | sort | tail -3
> ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
> ```

---

## 25. إعادة هيكلة الصلاحيات وRLS

### 25.1 الفلسفة: Permission-Based لا Role-Based

النظام الحالي (migration 0002) يعتمد بالفعل على هيكل RBAC+ABAC هجين:
- `permissions` — كتالوج بصيغة `module.resource.action`
- `roles` — قوالب أدوار
- `role_permissions` — ربط مع scope
- `user_roles` — إسناد للمستخدمين

**المشكلة:** كثير من سياسات RLS تفحص `current_is_full_access()` مباشرة بدلاً من فحص صلاحية محددة. هذا يعني أن أي تغيير في الأدوار لا ينعكس على RLS.

### 25.2 القاعدة: USING(true) على 6 جداول مرجعية فقط

الجداول المسموح لها بـ `USING(true)` — بيانات مرجعية للقراءة فقط:

| # | الجدول | السبب |
|---|---|---|
| 1 | `permissions` | كتالوج الصلاحيات — لا بيانات حساسة |
| 2 | `roles` | أسماء الأدوار — عامة |
| 3 | `role_permissions` | مصفوفة الربط — عامة |
| 4 | `kpi_criteria` | معايير التقييم — مرجعية |
| 5 | `request_types` | أنواع الطلبات — مرجعية |
| 6 | `shifts` | تعريف الورديات — مرجعية |

**كل جدول آخر** يجب أن يستخدم سياسة RLS مبنية على `has_permission()` أو `can_access_employee()`.

### 25.3 الدوال المحورية

```sql
-- current_is_full_access() — موجودة في 0002
-- تُرجع true فقط لأصحاب أدوار is_full_access=true (admin/super-admin)
create or replace function public.current_is_full_access()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.roles r
    where r.id = any (public.current_role_ids())
      and r.is_full_access = true
  );
$$;

-- provision_employee_record() — موجودة في 0013
-- تُنشئ سجل موظف + ربط profile + إرسال دعوة
-- مهم: لا تمنح أدوار full-access عند الإنشاء
-- يتجاوز rpc_assign_role — الأدوار تُمنح يدوياً بعد الإنشاء
```

### 25.4 مصفوفة الصلاحيات: 32 إجراء x 6 أدوار

```
الأدوار الستة:
  admin            — مدير النظام (full_access)
  executive        — المدير التنفيذي
  executive-secretary — السكرتير التنفيذي
  hr-manager       — مدير الموارد البشرية
  hr-specialist    — أخصائي موارد بشرية
  employee         — موظف عادي
```

```
المصفوفة (✓ = ممنوح، S = self فقط، D = direct_reports، O = organization):

الإجراء                              | admin | exec | sec  | hr-mgr | hr-spec | emp
-------------------------------------|-------|------|------|--------|---------|-----
people.employee.read                 | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
people.employee.create               | ✓ O   |      | ✓ O  | ✓ O    | ✓ O     |
people.employee.update_basic         | ✓ O   |      | ✓ O  | ✓ O    | ✓ O     | S
people.employee.update_sensitive     | ✓ O   |      |      | ✓ O    |         |
people.employee.archive              | ✓ O   |      |      | ✓ O    |         |
people.employee.view_contact         | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
people.employee.view_history         | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
people.employee.manage_documents     | ✓ O   |      | ✓ O  | ✓ O    | ✓ O     |
attendance.record.read               | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
attendance.record.export             | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     |
attendance.record.manual_create      | ✓ O   |      |      | ✓ O    | ✓ O     |
attendance.correction.review         | ✓ O   |      |      | ✓ O    | ✓ O     |
attendance.roster.read               | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
requests.request.read                | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
requests.request.approve             | ✓ O   | ✓ O  | ✓ O  | ✓ O    |         | D
requests.read                        | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     |
requests.leave.balance.read          | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
performance.kpi.read                 | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | S
performance.kpi.evaluate             | ✓ O   | ✓ O  | ✓ O  | ✓ O    |         | D
performance.cycle.manage             | ✓ O   |      | ✓ O  |        |         |
performance.kpi.final_approve        | ✓ O   | ✓ O  |      |        |         |
live_location.request                | ✓ O   | ✓ O  | ✓ O  |        |         |
organization.org_chart.read          | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     |
relations.case.manage                | ✓ O   |      | ✓ O  |        |         |
disputes.admin_action.decide         | ✓ O   | ✓ O  |      |        |         |
comms.announcement.read              | ✓ O   | ✓ O  | ✓ O  | ✓ O    | ✓ O     | ✓ O
comms.announcement.manage            | ✓ O   |      | ✓ O  |        |         |
access.role.read                     | ✓ O   |      | ✓ O  | ✓ O    |         |
access.role.assign                   | ✓ O   |      |      |        |         |
system.settings.read                 | ✓ O   |      | ✓ O  |        |         |
system.settings.manage               | ✓ O   |      |      |        |         |
audit.view                           | ✓ O   |      | ✓ O  |        |         |
```

### 25.5 Migration مقترحة: تحويل RLS من Role إلى Permission

```sql
-- 0145_rls_permission_based_migration.sql
-- تحويل سياسات RLS من فحص الدور مباشرة إلى فحص الصلاحية.
-- هذا يسمح بإعادة تشكيل الأدوار دون تعديل سياسات RLS.

-- ===== مثال 1: attendance_events =====
-- قبل (role-based):
--   USING(current_is_full_access() OR employee_id = current_employee_id())

-- بعد (permission-based):
drop policy if exists attendance_events_read on public.attendance_events;
create policy attendance_events_read on public.attendance_events
  for select using (
    public.has_permission('attendance.record.read')
    and public.can_access_employee(employee_id)
  );

-- ===== مثال 2: employees =====
drop policy if exists employees_read on public.employees;
create policy employees_read on public.employees
  for select using (
    public.has_permission('people.employee.read')
    and public.can_access_employee(id)
  );

-- تحديث (basic fields — الاسم، الهاتف)
drop policy if exists employees_update_basic on public.employees;
create policy employees_update_basic on public.employees
  for update using (
    public.has_permission('people.employee.update_basic')
    and public.can_access_employee(id)
  )
  with check (
    public.has_permission('people.employee.update_basic')
    and public.can_access_employee(id)
  );

-- ===== مثال 3: requests — الموظف يرى طلباته + المدير يرى طلبات فريقه =====
drop policy if exists requests_read on public.requests;
create policy requests_read on public.requests
  for select using (
    -- الموظف يرى طلباته الشخصية
    (requester_id = public.current_employee_id())
    or
    -- صاحب صلاحية القراءة يرى ضمن نطاقه
    (
      public.has_permission('requests.request.read')
      and public.can_access_employee(requester_id)
    )
  );

-- ===== مثال 4: kpi_evaluations =====
drop policy if exists kpi_evaluations_read on public.kpi_evaluations;
create policy kpi_evaluations_read on public.kpi_evaluations
  for select using (
    (employee_id = public.current_employee_id())
    or (
      public.has_permission('performance.kpi.read')
      and public.can_access_employee(employee_id)
    )
  );

-- ===== حماية الجداول المرجعية — USING(true) مقبول =====
-- التأكيد: هذه الجداول الست فقط تبقى USING(true)
-- permissions, roles, role_permissions, kpi_criteria, request_types, shifts
-- لا تغيير مطلوب عليها.

-- ===== إضافة صلاحيات ناقصة للمصفوفة =====
insert into public.permissions (code, module, resource, action, description, risk_level)
values
  ('system.device.manage', 'system', 'device', 'manage', 'إدارة أجهزة الحضور', 'sensitive'),
  ('holidays.manage', 'holidays', 'holiday', 'manage', 'إدارة الإجازات الرسمية', 'normal'),
  ('system.settings.manage', 'system', 'settings', 'manage', 'تعديل إعدادات النظام', 'critical')
on conflict (code) do nothing;
```

### 25.6 دالة مساعدة: فحص النطاق المفصّل

```sql
-- دالة جديدة لفحص الصلاحية مع النطاق — تُستخدم في RLS المتقدمة
create or replace function public.has_scoped_permission(
  p_code text,
  p_employee_id uuid
)
returns boolean
language plpgsql
stable security definer
set search_path = public, pg_temp
as $$
declare
  v_me         uuid;
  v_scope      text;
  v_dept_id    uuid;
  v_branch_id  uuid;
begin
  -- full-access يتخطى كل شيء
  if public.current_is_full_access() then return true; end if;

  v_me := public.current_employee_id();

  -- فحص كل scope ممنوح لهذه الصلاحية
  for v_scope in
    select rp.scope
    from public.role_permissions rp
    join public.permissions p on p.id = rp.permission_id
    where rp.role_id = any(public.current_role_ids())
      and p.code = p_code
      and (rp.effective_from is null or rp.effective_from <= now())
      and (rp.effective_to   is null or rp.effective_to   >  now())
  loop
    case v_scope
      when 'self' then
        if v_me = p_employee_id then return true; end if;

      when 'direct_reports' then
        if exists (
          select 1 from public.manager_relations mr
          where mr.manager_employee_id = v_me
            and mr.employee_id = p_employee_id
            and (mr.effective_to is null or mr.effective_to > now())
        ) then return true; end if;

      when 'department' then
        select department_id into v_dept_id
        from public.employees where id = v_me;
        if v_dept_id is not null and exists (
          select 1 from public.employees
          where id = p_employee_id and department_id = v_dept_id
        ) then return true; end if;

      when 'organization' then
        return true;

      when 'team' then
        if exists (
          select 1 from public.employees e1
          join public.employees e2 on e1.team_id = e2.team_id
          where e1.id = v_me and e2.id = p_employee_id
        ) then return true; end if;

      else
        -- scopes أخرى (branch, management_descendants, ...) — توسَّع لاحقاً
        null;
    end case;
  end loop;

  return false;
end;
$$;

comment on function public.has_scoped_permission(text, uuid)
  is 'هل يملك المستخدم الحالي صلاحية p_code على الموظف p_employee_id ضمن النطاق الممنوح؟';
```

### 25.7 تكامل الويب مع النظام الجديد

دالة `hasPermission` في الويب (ملف `access.ts`) تبقى كما هي — تفحص `context.permissions`:

```typescript
// features/workspaces/access.ts — لا تغيير مطلوب
export function hasPermission(context: AccessContext, permission: string): boolean {
  return context.permissions.includes('*') || context.permissions.includes(permission);
}
```

لكن يُضاف فحص النطاق للعمليات الحساسة:

```typescript
// features/workspaces/access.ts — إضافة
export function hasScopedPermission(
  context: AccessContext,
  permission: string,
  scope: 'self' | 'direct_reports' | 'department' | 'organization',
): boolean {
  if (context.permissions.includes('*')) return true;

  // فحص الصلاحية مع النطاق من البيانات المحمّلة في AccessContext
  const grant = context.grants?.find(
    g => g.permission === permission && g.scope === scope
  );
  return Boolean(grant);
}

// استخدام في المكونات:
const canEditSensitive = hasScopedPermission(
  auth.access,
  'people.employee.update_sensitive',
  'organization'
);
```

### 25.8 مخطط التنفيذ

```
المرحلة 1 (يوم 1):
  - Migration 0145: تحويل سياسات RLS الحرجة (employees, attendance_events, requests, kpi_evaluations)
  - اختبار pgTAP: 15 assertion جديد لكل سياسة

المرحلة 2 (يوم 2):
  - إضافة has_scoped_permission() والتكامل مع 4 سياسات
  - تحديث AccessContext في الويب لتحمل grants[]

المرحلة 3 (يوم 3):
  - تدقيق شامل: grep لكل USING في migrations + التأكد من عدم وجود USING(true) خارج الـ 6 جداول
  - اختبار متكامل: الأدوار الست تعمل كما في المصفوفة
```

```bash
# أمر التحقق النهائي — لا USING(true) خارج الجداول المرجعية
grep -rn "using (true" supabase/migrations/ \
  | grep -v "permissions\|roles\|role_permissions\|kpi_criteria\|request_types\|shifts" \
  | grep -v "^--"
# يجب أن يكون الناتج فارغاً
```

---

# 26. ترتيب التنفيذ

## الجدول الزمني الكامل (16 أسبوع)

| المرحلة | الأسبوع | المحور | المخرجات |
|---|---|---|---|
| **المرحلة 0 — التدقيق** | 1 | فحص شامل | baseline موثّق |
| **المرحلة 1 — P0** | 2 | جهاز + أمان | تسجيل جهاز، device_trust، fingerprint |
| | 3 | حضور | بصمة GPS، تأخر/غياب، سجل يومي |
| | 4 | طلبات | 6 أنواع طلبات + سير اعتماد |
| | 5 | KPI | تقييم شهري + دورات + لوحة أداء |
| | 6 | موقع + تقرير | طلب موقع حي + تقرير حضور شهري |
| **المرحلة 2 — P1** | 7 | ملف موظف | إنشاء/تعديل/تعطيل + صورة + وثائق |
| | 8 | كشف شهر | كشف راتب + خصومات + PDF |
| | 9 | إشعارات | FCM + إشعارات داخلية + تفضيلات |
| | 10 | إجازات رسمية + منشورات | تقويم إجازات + لوحة منشورات |
| **المرحلة 3 — البنية** | 11 | Flutter | إعادة هيكلة، offline، أداء |
| | 12 | ويب | مكوّنات مشتركة، a11y، responsive |
| | 13 | قاعدة بيانات | indexes، RLS audit، تنظيف migrations |
| | 14 | أمان | penetration review، rate-limit، audit log |
| **المرحلة 4 — التلميع** | 15 | اختبارات + أداء | تغطية 80%+، lighthouse، profiling |
| | 16 | نشر نهائي | staging smoke، إطلاق إنتاج |

## تفصيل المرحلة 0 — التدقيق (أسبوع 1)

| اليوم | المهمة | أمر التحقق |
|---|---|---|
| 1 | فحص migrations: ترقيم، تكرارات، ترتيب | `ls supabase/migrations/ \| sort \| tail -5` + `cut -c1-4 \| uniq -d` |
| 2 | فحص RLS: كل جدول له سياسة، لا `using(true)` على بيانات حساسة | مراجعة يدوية + `supabase db reset` |
| 3 | تشغيل كل الاختبارات وتسجيل النتائج | `npm run check:all` + `supabase test db` + `flutter test` |
| 4 | توثيق baseline: عدد migrations، اختبارات، تغطية | ملف `BASELINE.md` |
| 5 | إنشاء فرع العمل وتجهيز بيئة التطوير | `git checkout -b v18/implementation` |

## تفصيل المرحلة 1 — P0 (أسابيع 2-6)

### أسبوع 2: جهاز + أمان

| # | المهمة | النوع | المخرج |
|---|---|---|---|
| 1 | إنشاء جدول `device_registrations` | migration | DDL + RLS |
| 2 | إنشاء RPC `register_device` | migration | function + test |
| 3 | إنشاء RPC `verify_device_fingerprint` | migration | function + test |
| 4 | واجهة تسجيل الجهاز في Flutter | dart | شاشة + provider |
| 5 | لوحة إدارة أجهزة في الويب | tsx | صفحة + hook |
| 6 | اختبارات pgTAP للأجهزة | test | 15+ assertion |

### أسبوع 3: حضور

| # | المهمة | النوع | المخرج |
|---|---|---|---|
| 1 | مراجعة وإصلاح جدول `attendance_records` | migration | أعمدة مفقودة |
| 2 | RPC `clock_in` مع تحقق GPS + جهاز | migration | function + RLS |
| 3 | RPC `clock_out` مع حساب ساعات | migration | function |
| 4 | منطق التأخر والغياب التلقائي | migration | trigger أو cron |
| 5 | شاشة البصمة في Flutter | dart | GPS + UI |
| 6 | سجل الحضور اليومي (موظف + مدير) | dart + tsx | شاشتان |
| 7 | اختبارات pgTAP للحضور | test | 20+ assertion |

### أسبوع 4: طلبات

| # | المهمة | النوع | المخرج |
|---|---|---|---|
| 1 | جدول `requests` الموحد (6 أنواع) | migration | DDL + enum |
| 2 | سير اعتماد (مقدّم → مدير → HR) | migration | function + trigger |
| 3 | اعتماد مُصعَّد (تنفيذي) | migration | function |
| 4 | شاشة تقديم طلب في Flutter | dart | form + provider |
| 5 | شاشة اعتماد طلبات الفريق (مدير) | dart | قائمة + إجراءات |
| 6 | لوحة طلبات في الويب (HR) | tsx | جدول + فلاتر |
| 7 | اختبارات pgTAP للطلبات | test | 20+ assertion |

### أسبوع 5: KPI

| # | المهمة | النوع | المخرج |
|---|---|---|---|
| 1 | مراجعة جداول KPI الحالية | تدقيق | قائمة إصلاحات |
| 2 | إصلاح دورة التقييم الشهري | migration | function fixes |
| 3 | التقييم الذاتي للموظف | dart | شاشة + provider |
| 4 | تقييم المدير للموظف | dart + tsx | شاشتان |
| 5 | لوحة أداء تنفيذية | tsx | dashboard + charts |
| 6 | اختبارات pgTAP لـ KPI | test | 15+ assertion |

### أسبوع 6: موقع + تقرير

| # | المهمة | النوع | المخرج |
|---|---|---|---|
| 1 | تحسين طلب الموقع الحي | migration + dart | إصلاحات |
| 2 | عرض الموقع على الخريطة (ويب) | tsx | Leaflet map |
| 3 | تقرير حضور شهري | migration + tsx | RPC + PDF |
| 4 | تقرير ملخص تنفيذي | tsx | dashboard |
| 5 | اختبارات شاملة لنهاية P0 | test | regression suite |

---

# 27. التنقل حسب الدور

## 27.1 تطبيق الموظف (Mobile)

### شريط التنقل السفلي (Bottom Navigation)

| الترتيب | الأيقونة | التسمية | الشاشة الرئيسية |
|---|---|---|---|
| 1 | 🏠 | يومي | `EmployeeHomePage` — ملخص اليوم + بصمة سريعة |
| 2 | ⏰ | حضور | `MobileAttendancePage` — تسجيل دخول/خروج + سجل |
| 3 | 📋 | طلباتي | `MyRequestsPage` — طلباتي + تقديم جديد |
| 4 | ☰ | المزيد | `MoreMenuPage` — قائمة موسّعة |

### قائمة "المزيد" للموظف

| # | العنصر | الشاشة | الوصف |
|---|---|---|---|
| 1 | كشف الشهر | `MonthlySalaryPage` | كشف راتب + خصومات |
| 2 | تقييم الأداء | `KpiSelfEvalPage` | تقييمي الشهري + نتائج |
| 3 | المشكلات | `DisputesPage` | تقديم مشكلة + متابعة |
| 4 | المنشورات | `AnnouncementsPage` | منشورات الإدارة |
| 5 | الإشعارات | `NotificationsPage` | كل الإشعارات |
| 6 | حسابي | `ProfilePage` | بيانات شخصية + صورة |
| 7 | أجهزتي | `MyDevicesPage` | الأجهزة المسجلة |
| 8 | تسجيل خروج | — | خروج من الحساب |

## 27.2 تطبيق المدير (Mobile)

### شريط التنقل السفلي

| الترتيب | الأيقونة | التسمية | الشاشة الرئيسية |
|---|---|---|---|
| 1 | 🏠 | يومي | `ManagerHomePage` — ملخص الفريق اليومي |
| 2 | 👥 | فريقي | `TeamPage` — قائمة الموظفين + حالاتهم |
| 3 | ⚙️ | العمليات | `OperationsPage` — طلبات معلّقة + اعتمادات |
| 4 | ☰ | المزيد | `MoreMenuPage` — قائمة موسّعة |

### قائمة "المزيد" للمدير

| # | العنصر | الوصف |
|---|---|---|
| 1 | حضور الفريق | سجل حضور كل عضو |
| 2 | تقييم الفريق | تقييم KPI لأعضاء الفريق |
| 3 | طلباتي | طلباتي الشخصية |
| 4 | كشف الشهر | كشف راتبي |
| 5 | المشكلات | مشكلات فريقي |
| 6 | الإشعارات | إشعارات الاعتماد والتنبيهات |
| 7 | حسابي | بياناتي الشخصية |
| 8 | تسجيل خروج | — |

## 27.3 تطبيق التنفيذي (Mobile)

### شريط التنقل السفلي

| الترتيب | الأيقونة | التسمية | الشاشة الرئيسية |
|---|---|---|---|
| 1 | 📊 | الملخص | `ExecutiveHomePage` — KPIs + إحصائيات |
| 2 | ⏰ | الحضور | `ExecAttendancePage` — حضور كل الأقسام |
| 3 | 👥 | الموظفون | `ExecEmployeesPage` — بحث وتصفح |
| 4 | ☰ | المزيد | `MoreMenuPage` — 14 صفحة |

### قائمة "المزيد" للتنفيذي (14 عنصر)

| # | العنصر | الوصف |
|---|---|---|
| 1 | طلب موقع حي | طلب موقع GPS من موظف |
| 2 | الطلبات المُصعَّدة | طلبات تحتاج قرار تنفيذي |
| 3 | دورات KPI | إدارة دورات التقييم |
| 4 | لوحة الأداء | مقارنة أداء الأقسام |
| 5 | المشكلات | لجنة المشكلات + قرارات |
| 6 | الجزاءات | تنفيذ جزاءات |
| 7 | الإجازات الرسمية | تقويم إجازات |
| 8 | المنشورات | إنشاء ونشر |
| 9 | التقارير | تقارير شهرية |
| 10 | إدارة الأجهزة | أجهزة كل الموظفين |
| 11 | سجل التدقيق | audit log |
| 12 | الإشعارات | كل الإشعارات |
| 13 | حسابي | بياناتي |
| 14 | تسجيل خروج | — |

## 27.4 لوحة HR (Web)

### الشريط الجانبي (Sidebar)

| # | الأيقونة | التسمية | المسار | الوصف |
|---|---|---|---|---|
| 1 | 👥 | الموظفون | `/employees` | قائمة + ملف تفصيلي |
| 2 | ⏰ | الحضور | `/attendance` | سجل يومي + تقارير |
| 3 | 📋 | الطلبات | `/requests` | كل الطلبات + اعتماد HR |
| 4 | 📊 | الأداء | `/performance` | KPI + دورات + تقييمات |
| 5 | ⚖️ | المشكلات | `/disputes` | لجنة المشكلات |
| 6 | 🏖️ | الإجازات | `/leaves` | رصيد + طلبات + رسمية |
| 7 | 📑 | التقارير | `/reports` | كل التقارير |

## 27.5 لوحة Admin (Web)

### الشريط الجانبي — يشمل كل عناصر HR بالإضافة إلى:

| # | الأيقونة | التسمية | المسار | الوصف |
|---|---|---|---|---|
| 8 | 🔑 | المستخدمون | `/users` | حسابات + أدوار + صلاحيات |
| 9 | 📱 | الأجهزة | `/devices` | إدارة أجهزة مسجلة |
| 10 | ⚙️ | الإعدادات | `/settings` | إعدادات النظام |
| 11 | 📝 | التدقيق | `/audit` | سجل العمليات |
| 12 | 📢 | المنشورات | `/announcements` | إنشاء وإدارة |

---

# 28. مصفوفة الصلاحيات

## جدول الصلاحيات الكامل (32 إجراء × 6 أدوار)

**الرموز:**
- ✅ مسموح بالكامل
- 🔹 فريقه فقط (الموظفون تحت إدارته)
- 🔸 ذاتي فقط (بياناته الشخصية)
- ❌ ممنوع

### الحضور والانصراف

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 1 | تسجيل حضور (بصمة GPS) | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 2 | تسجيل انصراف | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 3 | عرض سجل حضوري | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 4 | عرض حضور الفريق | ❌ | 🔹 | ✅ | 🔹 | ✅ | ✅ |
| 5 | تعديل سجل حضور (تصحيح) | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |

### الطلبات

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 6 | تقديم طلب إجازة | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 7 | تقديم طلب إذن خروج | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 8 | تقديم طلب عمل إضافي | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 9 | تقديم طلب سلفة | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 10 | تقديم طلب تغيير وردية | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 11 | تقديم طلب استئناف جزاء | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 12 | اعتماد طلب فريقه | ❌ | 🔹 | ❌ | 🔹 | ❌ | ❌ |
| 13 | اعتماد طلب (HR) | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| 14 | اعتماد طلب مُصعَّد | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |

### الأداء (KPI)

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 15 | تقييم ذاتي شهري | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 16 | تقييم موظف في فريقه | ❌ | 🔹 | ❌ | 🔹 | ❌ | ❌ |
| 17 | تقييم أي موظف | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 18 | فتح دورة تقييم | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 19 | إغلاق دورة تقييم | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 20 | عرض لوحة الأداء | ❌ | 🔹 | ✅ | 🔹 | ✅ | ✅ |

### المشكلات والجزاءات

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 21 | تقديم مشكلة | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 | 🔸 |
| 22 | مراجعة مشكلة (لجنة) | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 23 | قرار تنفيذي على مشكلة | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |
| 24 | تنفيذ جزاء | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |

### إدارة الموظفين

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 25 | إنشاء موظف جديد | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| 26 | تعديل بيانات موظف | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ |
| 27 | تعطيل حساب موظف | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |

### النظام والإدارة

| # | الإجراء | موظف | مدير | HR | مدير قسم | تنفيذي | admin |
|---|---|---|---|---|---|---|---|
| 28 | طلب موقع حي من موظف | ❌ | 🔹 | ❌ | 🔹 | ✅ | ✅ |
| 29 | نشر منشور | ❌ | ❌ | ✅ | ❌ | ✅ | ✅ |
| 30 | إدارة أجهزة موظفين | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| 31 | إدارة إعدادات النظام | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| 32 | عرض سجل التدقيق | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |

### ملخص إحصائي

| الدور | ✅ مسموح | 🔹 فريقه | 🔸 ذاتي | ❌ ممنوع |
|---|---|---|---|---|
| موظف | 0 | 0 | 11 | 21 |
| مدير | 0 | 5 | 11 | 16 |
| HR | 11 | 0 | 11 | 10 |
| مدير قسم | 0 | 5 | 11 | 16 |
| تنفيذي | 13 | 0 | 11 | 8 |
| admin | 17 | 0 | 11 | 4 |

---

# 29. بوابات الجودة

## البوابة 0 — قبل البدء (المرحلة 0)

| # | الفحص | الأمر | معيار النجاح |
|---|---|---|---|
| 1 | إنشاء فرع عمل | `git checkout -b v18/implementation` | فرع جديد من `main` |
| 2 | فحص شامل للكود | `npm run check:all` | صفر أخطاء |
| 3 | إعادة بناء قاعدة البيانات | `npx supabase db reset` | كل migrations تمر |
| 4 | اختبارات قاعدة البيانات | `npx supabase test db` | كل pgTAP assertions تمر |
| 5 | فحص Flutter | `flutter analyze --no-fatal-infos` | صفر أخطاء |
| 6 | اختبارات Flutter | `flutter test` | كل الاختبارات تمر |
| 7 | بناء الويب | `npm run build` | بناء ناجح بدون أخطاء |
| 8 | فحص ترقيم migrations | `ls supabase/migrations/ \| cut -c1-4 \| sort \| uniq -d` | لا تكرارات |
| 9 | توثيق baseline | ملف `BASELINE.md` | أرقام مسجلة |

## البوابة 1 — بعد المرحلة P0 (نهاية أسبوع 6)

| # | الفحص | الأمر | معيار النجاح |
|---|---|---|---|
| 1 | TypeScript نظيف | `npx tsc --noEmit -p apps/admin_web/tsconfig.json` | صفر أخطاء |
| 2 | اختبارات Vitest | `npm run test` | كل الاختبارات تمر |
| 3 | Flutter analyze | `flutter analyze --no-fatal-infos` | صفر أخطاء |
| 4 | Flutter test | `flutter test` | كل الاختبارات تمر |
| 5 | pgTAP | `npx supabase test db` | كل assertions تمر |
| 6 | سيناريو: تسجيل جهاز | يدوي | جهاز يُسجَّل ويُعتمَد |
| 7 | سيناريو: بصمة حضور | يدوي | GPS + تسجيل دخول/خروج |
| 8 | سيناريو: تقديم طلب إجازة | يدوي | طلب → مدير → HR → اعتماد |
| 9 | سيناريو: تقييم KPI شهري | يدوي | تقييم ذاتي + مدير + إغلاق |
| 10 | سيناريو: طلب موقع حي | يدوي | طلب → إرسال → عرض خريطة |
| 11 | سيناريو: تقرير حضور شهري | يدوي | تقرير يعمل + PDF |

## البوابة 2 — بعد المرحلة P1 (نهاية أسبوع 10)

| # | الفحص | الأمر | معيار النجاح |
|---|---|---|---|
| 1 | كل فحوصات البوابة 1 | نفس الأوامر | نفس المعايير |
| 2 | سيناريو: إنشاء موظف | يدوي | إنشاء + تفعيل + تسجيل دخول |
| 3 | سيناريو: كشف شهري | يدوي | كشف صحيح + PDF |
| 4 | سيناريو: إشعار FCM | يدوي | إشعار يصل للجهاز |
| 5 | سيناريو: إجازة رسمية | يدوي | تقويم + تأثير على الحضور |
| 6 | اختبار بدور موظف | يدوي (حساب اختبار) | كل الشاشات تعمل، لا وصول غير مصرّح |
| 7 | اختبار بدور مدير | يدوي (حساب اختبار) | يرى فريقه فقط |
| 8 | اختبار بدور HR | يدوي (حساب اختبار) | يصل لكل وظائف HR |
| 9 | اختبار بدور تنفيذي | يدوي (حساب اختبار) | يصل لكل شيء |
| 10 | اختبار بدور admin | يدوي (حساب اختبار) | يصل لكل شيء + إعدادات |

## البوابة 3 — بعد الهيكلة (نهاية أسبوع 14)

| # | الفحص | الأمر | معيار النجاح |
|---|---|---|---|
| 1 | regression = صفر | `npm run check:all` + `supabase test db` + `flutter test` | لا اختبارات فاشلة جديدة |
| 2 | Flutter analyze نظيف | `flutter analyze --no-fatal-infos` | صفر warnings (باستثناء infos) |
| 3 | TypeScript نظيف | `npx tsc --noEmit` | صفر أخطاء |
| 4 | لا console.log في الإنتاج | `grep -r "console.log" apps/admin_web/src/ --include="*.ts" --include="*.tsx"` | صفر نتائج |
| 5 | لا debugPrint بدون kDebugMode | فحص يدوي | كل debugPrint محمي |
| 6 | Lighthouse score | Chrome DevTools | Performance > 80, A11y > 90 |
| 7 | بناء APK release | `flutter build apk --release` | بناء ناجح وموقّع |
| 8 | حجم الحزمة | Vite build output | < 500 KB gzipped |

## البوابة 4 — قبل الإطلاق (نهاية أسبوع 16)

| # | الفحص | البيئة | معيار النجاح |
|---|---|---|---|
| 1 | Smoke test على staging | staging | الموقع يفتح بدون أخطاء |
| 2 | تسجيل دخول بكل الأدوار | staging | 5 حسابات اختبار تدخل بنجاح |
| 3 | بصمة حضور | staging + جهاز حقيقي | GPS + تسجيل يعمل |
| 4 | تقديم طلب إجازة | staging | سير الاعتماد كامل |
| 5 | تقييم KPI | staging | تقييم + إغلاق دورة |
| 6 | إشعار FCM | staging + جهاز حقيقي | إشعار يصل |
| 7 | تقرير حضور | staging | PDF يتولّد |
| 8 | RLS عشوائي | staging | موظف لا يرى بيانات غيره |
| 9 | تصفّح على موبايل | staging + 3 أجهزة | responsive يعمل |
| 10 | فحص أمان نهائي | staging | لا ثغرات مكشوفة |

### مخطط تدفق البوابات

```
[بدء] → البوابة 0 ──✓──→ المرحلة 1 (P0) → البوابة 1 ──✓──→ المرحلة 2 (P1)
                 ✗↓                                    ✗↓
              إصلاح                                 إصلاح
              وإعادة                                وإعادة
              
→ البوابة 2 ──✓──→ المرحلة 3 (بنية) → البوابة 3 ──✓──→ المرحلة 4 (تلميع)
         ✗↓                                    ✗↓
      إصلاح                                 إصلاح
      وإعادة                                وإعادة

→ البوابة 4 ──✓──→ [إطلاق الإنتاج] 🎉
         ✗↓
      إصلاح وإعادة (لا إطلاق حتى تمر كل الفحوصات)
```

---

# 30. القائمة النهائية

## 30.1 قاعدة البيانات (20 بند)

- [ ] 01. إنشاء جدول `device_registrations` مع RLS
- [ ] 02. إنشاء RPC `register_device` مع تحقق من البصمة
- [ ] 03. إنشاء RPC `verify_device_fingerprint`
- [ ] 04. مراجعة وإصلاح جدول `attendance_records` (أعمدة مفقودة)
- [ ] 05. إنشاء RPC `clock_in` مع تحقق GPS + جهاز + geofence
- [ ] 06. إنشاء RPC `clock_out` مع حساب الساعات
- [ ] 07. إنشاء trigger/cron للتأخر والغياب التلقائي
- [ ] 08. إنشاء/مراجعة جدول `requests` الموحد (6 أنواع)
- [ ] 09. إنشاء سير اعتماد الطلبات (مقدّم → مدير → HR)
- [ ] 10. إنشاء RPC للاعتماد المُصعَّد (تنفيذي)
- [ ] 11. مراجعة وإصلاح جداول KPI (دورة شهرية)
- [ ] 12. إنشاء/مراجعة RPC التقييم الذاتي والإداري
- [ ] 13. تحسين RPCs طلب الموقع الحي
- [ ] 14. إنشاء RPC تقرير الحضور الشهري
- [ ] 15. إنشاء جدول `salary_slips` أو view للكشف الشهري
- [ ] 16. إنشاء جدول `notifications` مع RLS
- [ ] 17. إنشاء جدول `official_holidays` مع RLS
- [ ] 18. إنشاء indexes للأداء على الجداول الرئيسية
- [ ] 19. مراجعة RLS شاملة لكل الجداول (لا `using(true)` على بيانات حساسة)
- [ ] 20. تنظيف migrations: ترقيم متسلسل، لا تكرارات، لا تعارضات

## 30.2 تطبيق الموبايل — Flutter (20 بند)

- [ ] 01. شاشة تسجيل الجهاز + تدفق التفعيل
- [ ] 02. provider لإدارة الجهاز (`device_provider.dart`)
- [ ] 03. شاشة البصمة (GPS + geofence + زر تسجيل)
- [ ] 04. provider الحضور مع حالات التحميل والخطأ
- [ ] 05. شاشة سجل الحضور اليومي/الشهري
- [ ] 06. شاشة تقديم طلب (6 أنواع) مع form validation
- [ ] 07. شاشة طلباتي + حالة كل طلب
- [ ] 08. شاشة اعتماد طلبات الفريق (للمدير)
- [ ] 09. شاشة التقييم الذاتي KPI
- [ ] 10. شاشة تقييم المدير لموظف
- [ ] 11. شاشة كشف الشهر
- [ ] 12. شاشة الإشعارات + FCM integration
- [ ] 13. تحسين شاشة طلب الموقع الحي
- [ ] 14. شاشة المنشورات
- [ ] 15. شاشة الملف الشخصي + تحميل صورة
- [ ] 16. شاشة أجهزتي
- [ ] 17. Bottom Navigation حسب الدور (موظف/مدير/تنفيذي)
- [ ] 18. offline support (Hive/drift cache)
- [ ] 19. تحسين أداء: lazy loading، تقليل rebuilds
- [ ] 20. إعادة هيكلة: فصل features، مكوّنات مشتركة

## 30.3 لوحة الويب — React (15 بند)

- [ ] 01. صفحة إدارة الأجهزة (قائمة + اعتماد/رفض)
- [ ] 02. صفحة سجل الحضور اليومي (جدول + فلاتر + تصدير)
- [ ] 03. صفحة تقرير الحضور الشهري + PDF
- [ ] 04. صفحة الطلبات (عرض + اعتماد HR)
- [ ] 05. صفحة KPI: دورات + تقييمات + لوحة أداء
- [ ] 06. تحسين صفحة الموظفين (إنشاء + تعديل + تعطيل)
- [ ] 07. صفحة كشف الشهر (عرض + PDF)
- [ ] 08. صفحة الإشعارات + إعدادات التفضيلات
- [ ] 09. صفحة الإجازات الرسمية (تقويم + CRUD)
- [ ] 10. صفحة المنشورات (إنشاء + نشر)
- [ ] 11. تحسين خريطة الموقع الحي (Leaflet)
- [ ] 12. صفحة سجل التدقيق (audit log)
- [ ] 13. مكوّنات مشتركة: `ErrorState`, `Skeleton`, `EmptyState`, `ConfirmDialog`
- [ ] 14. responsive design لكل الصفحات
- [ ] 15. a11y: aria labels، keyboard navigation، contrast

## 30.4 الأمان (15 بند)

- [ ] 01. RLS على كل الجداول الجديدة
- [ ] 02. `current_is_full_access()` على كل العمليات الحساسة
- [ ] 03. rate limiting على RPCs الحساسة (تسجيل دخول، طلب موقع)
- [ ] 04. device fingerprint validation على كل عملية حضور
- [ ] 05. impossible-travel detection على تسجيلات الحضور
- [ ] 06. audit log لكل العمليات الإدارية
- [ ] 07. لا أسرار في المستودع (فحص تلقائي)
- [ ] 08. لا PII في السجلات (log sanitization)
- [ ] 09. CORS مقيّد على Edge Functions
- [ ] 10. CSP headers على الويب
- [ ] 11. فحص SQL injection على كل RPCs
- [ ] 12. فحص XSS على كل حقول الإدخال
- [ ] 13. تشفير بيانات حساسة at rest
- [ ] 14. session management: انتهاء + تجديد + إبطال
- [ ] 15. penetration test يدوي قبل الإطلاق

## 30.5 التوثيق والإطلاق (10 بنود)

- [ ] 01. تحديث `CLAUDE.md` بالهيكل الجديد
- [ ] 02. توثيق API: كل RPCs مع أمثلة
- [ ] 03. توثيق مصفوفة الصلاحيات (هذا المستند)
- [ ] 04. دليل استخدام للموظف (عربي)
- [ ] 05. دليل استخدام للمدير (عربي)
- [ ] 06. دليل إدارة للـ admin (عربي)
- [ ] 07. نشر الويب على Vercel (staging ثم إنتاج)
- [ ] 08. نشر Edge Functions على Supabase
- [ ] 09. بناء وتوقيع APK release
- [ ] 10. smoke test نهائي على الإنتاج بكل الأدوار

---

### ملخص القائمة النهائية

| القسم | عدد البنود | الحالة |
|---|---|---|
| قاعدة البيانات | 20 | ⬜ لم يبدأ |
| تطبيق الموبايل | 20 | ⬜ لم يبدأ |
| لوحة الويب | 15 | ⬜ لم يبدأ |
| الأمان | 15 | ⬜ لم يبدأ |
| التوثيق والإطلاق | 10 | ⬜ لم يبدأ |
| **الإجمالي** | **80** | **⬜ 0/80** |