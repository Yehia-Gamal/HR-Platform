# تقرير الموروث — LEGACY_REPORT

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## 1. صفحات يجب إزالتها (V23 §13)

قرارات V23 Master تنص على حذف هذه الصفحات من Routes/Navigation/Deep Links مع حفظ التاريخ:

| الصفحة المطلوب إزالتها | الحالة الحالية | الملف | المسار | الإجراء المطلوب |
|---|---|---|---|---|
| **الخصوصية كصفحة مستقلة** | ❌ لا توجد صفحة مستقلة | — | — | لا إجراء |
| **التدريب والمهارات** | 🔒 مخفي (V17 §4.2) | `LearningPage.tsx` | كان `/hr/learning` | حذف الملف |
| **مستنداتي** | 🔒 مخفي (V17 §4.2) | `DocumentStudioPage.tsx` | كان `/admin/documents` | حذف الملف |
| **العهد** | ❌ لا توجد صفحة مستقلة | جداول `asset_*` فقط | — | إبقاء الجداول، لا صفحة |
| **نهاية العقد** | 🔒 مخفي (V17 §4.2) | `LifecycleOperationsPage.tsx` | كان `/admin/lifecycle` | حذف الملف |
| **الرواتب** | 🔒 مخفي (V17 §4.2) | `PeopleFinancePage.tsx` | كان `/admin/people-finance` | حذف الملف |
| **المخاطر والحوكمة الشكلية** | 🔒 مخفي (V17 §4.2) | `ReleaseGovernancePage.tsx` | كان `/admin/governance` | حذف الملف |
| **مكتب الخدمات** | 🔒 مخفي (V17 §4.2) | `ServiceDeskPage.tsx` | كان `/admin/helpdesk` | حذف الملف |
| **التقارير المكررة الفارغة** | ⚠️ يحتاج فحص | `ReportsPage.tsx` | `/hr/reports` | فحص المحتوى |

### ملخص

- **6 صفحات مخفية** بالفعل في V17 §4.2 (imports محذوفة من App.tsx)
- الملفات لا تزال موجودة على القرص لكن لا يمكن الوصول إليها
- V23 يطلب **حذفها نهائياً** مع حفظ التاريخ في Git

---

## 2. كود غير مستخدم

### صفحات ويب مخفية (6 ملفات)

| الملف | آخر استخدام | ملاحظة |
|---|---|---|
| `features/advanced/LifecycleOperationsPage.tsx` | V17 | import محذوف |
| `features/management/LearningPage.tsx` | V17 | import محذوف |
| `features/management/DocumentStudioPage.tsx` | V17 | import محذوف |
| `features/management/PeopleFinancePage.tsx` | V17 | import محذوف |
| `features/management/ReleaseGovernancePage.tsx` | V17 | import محذوف |
| `features/management/ServiceDeskPage.tsx` | V17 | import محذوف |

### Edge Function معطلة

| الملف | الحالة | الملاحظة |
|---|---|---|
| `supabase/functions/live-location-video-url/` | 410 Gone | معطل نهائياً (V17 §9) — يعيد 410 لكل الطلبات |

### جداول بدون واجهة نشطة

| المجموعة | الجداول | الملاحظة |
|---|---|---|
| الرواتب | `salary_structures`, `salary_components`, `employee_compensation`, `payroll_runs`, `payslips`, `payslip_lines` | صفحة الرواتب مخفية |
| القروض | `employee_loans`, `loan_installments` | لا واجهة |
| المشاركة | `engagement_campaigns`, `wellbeing_requests` | لا واجهة |
| التدريب | `learning_courses`, `learning_course_sessions`, `learning_enrollments` | صفحة التدريب مخفية |
| المؤسسية | `strategic_objectives`, `objective_key_results`, `enterprise_projects`, `project_tasks`, `enterprise_risks`, `enterprise_incidents` | واجهة محدودة |
| الخدمات | `service_catalog_items`, `service_requests`, `service_request_messages` | مكتب الخدمات مخفي |
| الجودة | `quality_cases`, `corrective_actions`, `internal_audits`, `audit_findings` | لا واجهة |
| الأتمتة | `automation_rules`, `automation_runs` | لا واجهة |
| البيانات | `data_assets`, `data_quality_rules`, `ai_use_cases` | لا واجهة |
| الفيديو | `live_location_videos_meta`, `live_location_video_access_logs` | الفيديو معطل |

### Migrations Bridge/Placeholder

| Migration | الغرض |
|---|---|
| `0119_bridge_placeholder.sql` | حجز رقم — محتوى فارغ أو تعليق |
| `0122_bridge_placeholder.sql` | حجز رقم — محتوى فارغ أو تعليق |

---

## 3. تناقضات مكتشفة

### أرقام Migration مكررة

| الرقم | المشكلة | التأثير |
|---|---|---|
| 0060 | `v17_request_return_and_attendance_days.sql` + `v23_dispute_committee_alignment.sql` (اختبارات فقط) | تحذير — الاختبارات بنفس الرقم |
| 0062 | `request_escalation_on_behalf.sql` + `v23_rbac_negative_scenarios.sql` + `v23_device_biometric_recovery.sql` + `security_negative_tests.sql` (اختبارات) | تحذير — 3 اختبارات بنفس الرقم |
| 0160 | `v23_dispute_committee_alignment.sql` + `v23_leaves_escalation_split.sql` | ⚠️ **خطير** — ملفا migration بنفس الرقم |

### KPI Schema vs Tests

اختبارات `kpi.test.ts` تتوقع ترتيب مراحل KPI وتوزيع المقيّمين يختلف عن القيم الفعلية في `kpi.ts`. هذا يشير إلى تغيير في V17 لم يُحدّث الاختبار بعده.

### Location Video Remnants

رغم تعطيل الفيديو نهائياً (mig 0124)، لا تزال الجداول والسياسات موجودة:
- `live_location_videos_meta` (mig 0011)
- `live_location_video_access_logs` (mig 0037)
- Edge Function `live-location-video-url` (يعيد 410)

---

## 4. توصيات التنظيف لـ V23

### أولوية عالية
1. إصلاح تكرار migration 0160 قبل أي `db push`
2. حذف 6 صفحات ويب مخفية نهائياً
3. تحديث اختبارات KPI الفاشلة

### أولوية متوسطة
4. تنظيف اختبارات pgTAP بأرقام مكررة (0060, 0062)
5. مراجعة جداول بدون واجهة — تقرير ما إذا كانت ستُفعّل في V23 أم تُوثق كـ "مؤجلة"
6. حذف أو تحويل Edge Function `live-location-video-url` إلى no-op أكثر وضوحاً

### أولوية منخفضة
7. دمج جدولي `live_location_requests` و `location_requests` (يبدو أنهما يؤديان نفس الغرض)
8. مراجعة جداول `employee_locations` vs `location_request_responses` للتداخل
9. حذف bridge placeholders (0119, 0122) إذا كانت فارغة
