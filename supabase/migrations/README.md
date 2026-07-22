# Migrations — أحلى شباب Management OS V8

تُطبَّق الملفات بالترتيب الرقمي. بعد تطبيق أي Migration لا تُعدّل في Production؛ تُنشأ Migration جديدة. الملفات الحالية هي مصدر البناء النظيف من قاعدة فارغة، وأي تعديل قبل أول نشر فعلي يجب أن يبقى موثقًا ومختبرًا.

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
