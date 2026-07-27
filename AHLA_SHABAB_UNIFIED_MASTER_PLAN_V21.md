# التصحيحات والتحسينات V21 — نظام إدارة أحلى شباب HR

**الحالة:** تصحيح وتطوير لخطة V20 — المرجع التنفيذي المحدّث  
**تاريخ التحقق:** 2026-07-26  
**مصدر التحقق:** فحص مباشر للمستودع الفعلي (branch: `codex/v17-master-plan`)  
**تحل محل:** V20 وجميع الخطط السابقة

---

# قسم 0 — ملخص التصحيحات الجوهرية

## 0.1 جدول التصحيحات الحرجة

| # | البند | القيمة في V20 | القيمة الصحيحة | القسم المتأثر | الخطورة |
|---|---|---|---|---|---|
| 1 | عدد Migrations | 141 | **157** (0001–0157) | §18, §24.4, متعدد | عالية — يؤثر على الترقيم |
| 2 | ملفات pgTAP | 48 ملف / 650 assertion | **62 ملف** | §18, §29 | متوسطة |
| 3 | جداول USING(true) | 6 جداول فقط | **~32 جدول** | §19.1.2, §25.2 | **حرجة — تناقض أمني** |
| 4 | تناقض قائمة USING(true) | §19 ≠ §25 (قائمتان مختلفتان) | قائمة موحدة أدناه | §19.1.2, §25.2 | **حرجة** |
| 5 | `has_scoped_permission()` | مذكورة كقائمة | **غير موجودة — مقترحة** | §25.6 | عالية |
| 6 | `get_operational_health()` | مذكورة كقائمة | **غير موجودة — مقترحة** | §20.2 | عالية |
| 7 | `daily_attendance_summary` | مذكور كقائم | **غير موجود — مقترح** | §24.3 | عالية |
| 8 | Flutter AsyncNotifier | هدف للترحيل | **0 استخدام — كل شيء FutureProvider (47)** | §23 | متوسطة |
| 9 | OfflinePunch | مذكور | **غير موجود في الكود — أُزيل** | §24, §30 | منخفضة |
| 10 | `current_is_full_access` عدد | 768 في 90 ملف | **767 في 97 ملف** | §19.1.3 | تجميلية |
| 11 | Edge Functions | 12 (مع قائمة ناقصة) | **12 — القائمة الكاملة مصححة** | §19.2.2 | متوسطة |
| 12 | بلوكات كود بلا تصنيف | عشرات البلوكات | يجب تصنيف كل بلوك | شامل | عالية |

## 0.2 قاعدة التصنيف الجديدة — إلزامية لكل بلوك كود

كل بلوك كود (SQL/TypeScript/Dart/Bash) يجب أن يحمل واحداً من هذه التصنيفات:

| التصنيف | المعنى | اللون |
|---|---|---|
| `[قائم]` | كود موجود فعلياً في المستودع — للتوثيق فقط، لا تعديل | 🟢 |
| `[مقترح]` | كود جديد يجب إنشاؤه — يحتاج migration/ملف جديد | 🟡 |
| `[توثيقي]` | استعلام فحص أو أداة تحقق — لا يُنشر في الإنتاج | 🔵 |
| `[ملغى]` | كود كان مقترحاً في خطة سابقة وأُلغي | 🔴 |

---

# قسم 1 — تصحيح الأرقام الأساسية (يستبدل الأرقام في §18)

## 1.1 الجرد الفعلي المحدّث (2026-07-26)

```
المستودع: HR_Platform_2
الفرع: codex/v17-master-plan
```

| المكوّن | V20 | V21 (محقق) |
|---|---|---|
| SQL Migrations | 141 | **157** (0001–0157 + README.md) |
| Edge Functions | 12 | **12** ✅ (صحيح) |
| pgTAP Test Files | 48 | **62** |
| Web Feature Files (.tsx) | غير محدد | **45** ملف في `apps/admin_web/src/features/` |
| Flutter Dart Files | غير محدد | **~80** ملف في `apps/mobile_flutter/lib/` |
| Flutter Pages | في `mobile_pages/` | **~42** ملف في `features/mobile_pages/` |
| Flutter Workspaces | غير محدد | **6** ملفات في `features/workspaces/` |
| FutureProvider instances | غير محدد | **47** (في 7 ملفات) |
| AsyncNotifier instances | هدف ترحيل | **0** (لم يبدأ الترحيل) |
| `has_permission()` استخدامات | غير محدد | **671** في 65 ملف migration |
| `current_is_full_access()` استخدامات | 768 في 90 ملف | **767** في 97 ملف |

## 1.2 قائمة Edge Functions الكاملة (12 دالة)

```
[قائم] — supabase/functions/
├── identifier-sign-in/        — بوابة الدخول (بريد/هاتف/كود → signInWithPassword)
├── verify-attendance-punch/   — تحقق بصمة WebAuthn
├── admin-create-employee/     — إنشاء موظف (full_access فقط)
├── admin-resend-invite/       — إعادة إرسال دعوة
├── webauthn-challenge/        — تحدي WebAuthn
├── passkey-register/          — تسجيل مفتاح مرور
├── notification-dispatcher/   — إرسال FCM (service_role — داخلية)
├── retention-cleanup/         — تنظيف دوري (service_role — cron)
├── scheduled-report-runner/   — تشغيل التقارير المجدولة
├── integration-outbox-worker/ — معالجة صندوق الصادر
├── live-location-map-url/     — رابط خريطة الموقع الحي
├── live-location-video-url/   — رابط فيديو الموقع الحي [ملغى وظيفياً — location-only]
└── _shared/                   — مكتبات مشتركة (ليست Edge Function مستقلة)
```

## 1.3 آخر 10 migrations (للمرجع)

```
[قائم]
0148_v17_announcement_publish_notify.sql
0149_fix_org_chart_recursive_cte.sql
0150_fix_request_live_location_admin_access.sql
0151_admin_sees_hr_workspace.sql
0152_v18_committee_dispute_mobile_portal.sql
0153_fix_kpi_notify_fullname.sql
0154_add_departments_slug_and_fix_seed_timing.sql
0155_fix_attendance_missing_check_null.sql
0156_multi_department_support.sql
0157_fix_seed_timing_permission_grants.sql
```

**⚠️ تحذير Migration Number:** آخر رقم هو **0157**. أي migration جديدة تبدأ من **0158**.

---

# قسم 2 — تصحيح جداول USING(true) (يستبدل §19.1.2 و§25.2)

## 2.1 المشكلة في V20

V20 تحتوي تناقضاً حرجاً:

**§19.1.2** يقول 6 جداول:
- permissions, roles, role_permissions, kpi_criteria, **official_holidays**, **learning_course_sessions**

**§25.2** يقول 6 جداول مختلفة:
- permissions, roles, role_permissions, kpi_criteria, **request_types**, **shifts**

**الواقع:** هناك **~32 جدول** بسياسة `USING(true)` في المستودع.

## 2.2 القائمة الكاملة المحققة من المستودع

### المجموعة أ — جداول التنظيم (15 جدول من اللوب في mig 0003)

هذه الجداول تحصل على `USING(true)` عبر لوب ديناميكي في migration 0003:

| # | الجدول | الحالة | ملاحظة |
|---|---|---|---|
| 1 | `legal_entities` | USING(true) ✅ | |
| 2 | `branches` | USING(true) ✅ | |
| 3 | `work_sites` | USING(true) ✅ | |
| 4 | `cost_centers` | USING(true) ✅ | |
| 5 | `departments` | USING(true) ✅ | |
| 6 | `teams` | USING(true) ✅ | |
| 7 | `positions` | USING(true) ✅ | |
| 8 | `job_titles` | USING(true) ✅ | |
| 9 | `job_grades` | USING(true) ✅ | |
| 10 | `employment_types` | USING(true) ✅ | |
| 11 | `geofences` | ⚠️ **مُلغاة ومُستبدلة** | أُنشئت في اللوب ثم أُعيد تعريفها بسياسة مقيّدة |
| 12 | `shifts` | USING(true) ✅ | |
| 13 | `shift_patterns` | USING(true) ✅ | |
| 14 | `public_holidays` | USING(true) ✅ | مُعاد تعريفها في 0132 أيضاً |
| 15 | `working_calendars` | USING(true) ✅ | |

### المجموعة ب — جداول RBAC (3 جداول من mig 0002)

| # | الجدول | Migration |
|---|---|---|
| 16 | `permissions` | 0002 |
| 17 | `roles` | 0002 |
| 18 | `role_permissions` | 0002 |

### المجموعة ج — جداول KPI والأداء (6 جداول من mig 0007)

| # | الجدول | Migration |
|---|---|---|
| 19 | `kpi_templates` | 0007 |
| 20 | `kpi_criteria` | 0007 |
| 21 | `competencies` | 0007 |
| 22 | `competency_levels` | 0007 |
| 23 | `role_competency_profiles` | 0007 |
| 24 | `review_cycle_templates` | 0007 |

### المجموعة د — جداول سير العمل (3 جداول من mig 0006)

| # | الجدول | Migration |
|---|---|---|
| 25 | `leave_types` | 0006 |
| 26 | `workflow_definitions` | 0006 |
| 27 | `workflow_steps` | 0006 |

### المجموعة هـ — جداول متفرقة

| # | الجدول | Migration | المبرر |
|---|---|---|---|
| 28 | `task_templates` | 0009 | قوالب مهام — مرجعية |
| 29 | `asset_inventory` | 0009 | جرد الأصول — مرجعي |
| 30 | `feature_flags` | 0011 | أعلام الميزات — مرجعية |
| 31 | `learning_course_sessions` | 0033 | جلسات التعلم — كتالوج عام |
| 32 | `kpi_policy_versions` | 0058 | إصدارات سياسة KPI — مرجعية |
| 33 | `employee_departments` | 0156 | ربط الموظف بالأقسام المتعددة |

## 2.3 التصنيف الأمني المقترح

```
[مقترح] — إعادة تصنيف جداول USING(true)
```

| التصنيف | الجداول | الخطر | القرار |
|---|---|---|---|
| **آمنة — تبقى USING(true)** | permissions, roles, role_permissions, kpi_criteria, kpi_templates, competencies, competency_levels, role_competency_profiles, review_cycle_templates, leave_types, workflow_definitions, workflow_steps, task_templates, feature_flags, learning_course_sessions, kpi_policy_versions, shifts, shift_patterns, working_calendars, employment_types, job_titles, job_grades | لا بيانات شخصية — كتالوجات مرجعية بحتة | ✅ إبقاء |
| **تحتاج مراجعة** | legal_entities, branches, work_sites, cost_centers, departments, teams, positions, public_holidays, employee_departments | قد تكشف هيكل المؤسسة | ⚠️ مقبولة حالياً — كل authenticated يحتاج رؤية الهيكل |
| **مقيّدة بالفعل** | geofences | إحداثيات GPS — سياسة مقيّدة مطبقة | ✅ محمية |
| **تحتاج فحص** | asset_inventory | قد يحتوي بيانات حساسة عن أصول المؤسسة | ⚠️ فحص مطلوب |

## 2.4 استعلام الفحص المصحح

```sql
-- [توثيقي] — استعلام فحص RLS: كشف سياسات USING(true) غير مصرح بها
-- يستبدل الاستعلام في §19.1.2
-- القائمة البيضاء تشمل كل الجداول المرجعية المعتمدة (~32 جدول)
SELECT
  schemaname,
  tablename,
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND qual = 'true'
  AND tablename NOT IN (
    -- RBAC (0002)
    'permissions', 'roles', 'role_permissions',
    -- التنظيم (0003) — ما عدا geofences المقيّدة
    'legal_entities', 'branches', 'work_sites', 'cost_centers',
    'departments', 'teams', 'positions', 'job_titles', 'job_grades',
    'employment_types', 'shifts', 'shift_patterns', 'public_holidays',
    'working_calendars',
    -- سير العمل (0006)
    'leave_types', 'workflow_definitions', 'workflow_steps',
    -- KPI (0007)
    'kpi_templates', 'kpi_criteria', 'competencies',
    'competency_levels', 'role_competency_profiles', 'review_cycle_templates',
    -- متفرقة
    'task_templates', 'asset_inventory', 'feature_flags',
    'learning_course_sessions', 'kpi_policy_versions', 'employee_departments'
  )
ORDER BY tablename, policyname;

-- النتيجة المتوقعة: 0 صفوف
-- (geofences لن تظهر لأن سياستها ليست USING(true) — أُعيد تعريفها)
```

---

# قسم 3 — تصنيف بلوكات الكود (تصحيح شامل)

## 3.1 بلوكات يجب تصنيفها `[قائم]`

هذه البلوكات موجودة فعلاً في المستودع — للتوثيق فقط:

| القسم في V20 | البلوك | الملف الفعلي |
|---|---|---|
| §19.1.3 | `current_is_full_access()` | `0002_permissions_roles_functions.sql` |
| §19.1.4 | `provision_employee_record()` مخطط | `0013_foundation_access_and_provisioning.sql` |
| §19.2.3 | `AttendancePunchSchema` | `packages/shared-contracts/src/attendance.ts` |
| §20.1 | `get_system_health()` | `0054_observability_and_alerting.sql` |
| §25.3 | `current_is_full_access()` (مكرر) | `0002_permissions_roles_functions.sql` |
| §25.7 | `hasPermission()` في access.ts | `apps/admin_web/src/features/workspaces/access.ts` |

## 3.2 بلوكات يجب تصنيفها `[مقترح]`

هذه البلوكات **غير موجودة** في المستودع — تحتاج إنشاء:

| القسم في V20 | البلوك | الحالة |
|---|---|---|
| §20.2 | `get_operational_health()` | ❌ غير موجودة — تحتاج migration جديدة |
| §24.2 | unified attendance security checks | ❌ غير موجودة — تحتاج migration |
| §24.3 | `daily_attendance_summary` + `daily_attendance_finalization()` | ❌ غير موجود — تحتاج migration |
| §24.4 | cleanup_rpc_overloads | ❌ غير موجودة — تحتاج migration |
| §25.5 | RLS permission-based migration | ❌ غير موجودة — تحتاج migration |
| §25.6 | `has_scoped_permission()` | ❌ غير موجودة — تحتاج migration |
| §25.7 | `hasScopedPermission()` في access.ts | ❌ غير موجودة — تحتاج إضافة |

## 3.3 بلوكات يجب تصنيفها `[توثيقي]`

استعلامات فحص فقط — لا تُنشر:

| القسم في V20 | البلوك |
|---|---|
| §19.1.2 | استعلام فحص USING(true) |
| §19.1.5 | استعلام فحص SECURITY DEFINER |
| §19.1.6 | استعلام فحص RLS مفعّل |

## 3.4 بلوكات يجب تصنيفها `[ملغى]`

| البند | السبب |
|---|---|
| أي ذكر لـ `OfflinePunch` | غير موجود في الكود — القرار: لا حضور Offline |
| أي ذكر لفيديو في طلب الموقع | القرار: location-only بلا كاميرا/ميكروفون |

---

# قسم 4 — تصحيح §19.1.3 (current_is_full_access)

## النص الأصلي (V20):
> مُستخدمة في 768 موضع عبر 90 ملف migration

## النص المصحح (V21):
> مُستخدمة في **767** موضع عبر **97** ملف migration (محقق 2026-07-26)

---

# قسم 5 — تصحيح §19.2.2 (Edge Functions وحمايتها)

## الجدول المصحح والمكتمل

| Edge Function | JWT | Rate Limit | Zod | ملاحظات |
|---|---|---|---|---|
| `identifier-sign-in` | لا (عامة) | نعم — 5 محاولات/دقيقة (DB) | نعم | بوابة الدخول الوحيدة |
| `verify-attendance-punch` | نعم | ضمني (60 ثانية بين بصمتين) | نعم | الأكثر حساسية |
| `admin-create-employee` | نعم | **⚠️ لا — يجب إضافة rate limit** | نعم | `full_access` فقط |
| `admin-resend-invite` | نعم | نعم — 3 دعوات/ساعة (DB 0120) | نعم | |
| `webauthn-challenge` | نعم | نعم — 20 تحدي/ساعة | نعم | حماية brute-force |
| `passkey-register` | نعم | ضمني (تحقق WebAuthn) | نعم | تسجيل مفتاح مرور |
| `notification-dispatcher` | service_role | لا (داخلية) | لا | تُستدعى من pg_net فقط |
| `retention-cleanup` | service_role | لا (cron) | لا | مجدولة — لا وصول خارجي |
| `scheduled-report-runner` | service_role | لا (cron) | لا | تقارير مجدولة |
| `integration-outbox-worker` | service_role | لا (داخلية) | لا | معالجة صندوق الصادر |
| `live-location-map-url` | نعم | ضمني (طلب واحد نشط) | نعم | رابط خريطة موقّع |
| `live-location-video-url` | نعم | ضمني | نعم | **⚠️ ملغى وظيفياً — location-only** |

### ⚠️ فجوة مكتشفة: `admin-create-employee` بدون Rate Limit

```sql
-- [مقترح] — إضافة rate limiting لـ admin-create-employee
-- يمنع إنشاء موظفين بشكل مفرط (حماية من أخطاء أو سوء استخدام)
-- الحد المقترح: 20 موظف/ساعة لكل admin
INSERT INTO public.rate_limits (function_name, max_requests, window_seconds, scope)
VALUES ('admin-create-employee', 20, 3600, 'per_user')
ON CONFLICT (function_name) DO NOTHING;
```

---

# قسم 6 — تصحيح §24.4 (عدد Migrations في cleanup)

## النص الأصلي (V20):
> تنظيف دوال RPC مكررة/متعارضة تراكمت عبر 141 migration

## النص المصحح (V21):
> تنظيف دوال RPC مكررة/متعارضة تراكمت عبر **157** migration

---

# قسم 7 — تصحيح Flutter (يستبدل أقسام هيكلة Flutter في §23)

## 7.1 الوضع الفعلي للهيكلة

V20 تذكر ترحيل Flutter من `FutureProvider` إلى `AsyncNotifier`. الواقع:

| المقياس | القيمة الفعلية |
|---|---|
| FutureProvider | **47 استخدام** في 7 ملفات |
| AsyncNotifier | **0 استخدام** |
| هيكل الصفحات | `features/mobile_pages/` (مسطح — ~42 ملف) |
| هيكل Workspaces | `features/workspaces/` (6 ملفات) |
| هيكل البيانات | `features/mobile_data/` (7 ملفات) |
| المصادقة | `features/auth/` (3 ملفات) |
| Core | `core/` (widgets, theme, network, config, security) |

## 7.2 خارطة ترحيل FutureProvider → AsyncNotifier

```
[مقترح] — خطة الترحيل على مراحل

المرحلة 1 (P0 — حرجة):
  mobile_providers.dart          — 36 FutureProvider → AsyncNotifier
  auth_providers.dart            — 1 FutureProvider

المرحلة 2 (P1):
  mobile_operations_providers.dart — 2 FutureProvider
  mobile_executive_insights_providers.dart — 3 FutureProvider
  release_governance.dart        — 3 FutureProvider

المرحلة 3 (P2):
  org_chart_page.dart            — 1 FutureProvider (inline)
  gps_preflight_banner.dart      — 1 FutureProvider (inline)
```

**قاعدة الترحيل:**
- كل `FutureProvider.autoDispose` → `AsyncNotifierProvider` مع `ref.invalidate()`
- الاحتفاظ بنفس المفاتيح والأسماء لتسهيل المراجعة
- اختبار كل provider بعد الترحيل مباشرة
- لا ترحيل inline providers في الصفحات إلا بعد استقرار المرحلة 1

## 7.3 هيكل Flutter المقترح (بعد إعادة الهيكلة)

```
[مقترح] — الهيكل المستهدف
apps/mobile_flutter/lib/
├── core/
│   ├── config/          — app_config.dart
│   ├── network/         — connectivity_*, offline_cache
│   ├── security/        — secure_session_storage
│   ├── theme/           — app_theme, theme_mode_controller
│   └── widgets/         — brand_logo, app_avatar, connectivity_banner, gps_preflight_banner
├── features/
│   ├── auth/            — login_page, set_password_page, auth_providers
│   ├── attendance/      — mobile_attendance_page, attendance_history_page, monthly_statement
│   ├── requests/        — mobile_requests_page, mobile_request_detail_page
│   ├── kpi/             — mobile_kpi_page, kpi_evaluation_detail_page
│   ├── disputes/        — mobile_disputes_page, committee_dispute_list_page
│   ├── location/        — location_*, live_tracking_*, executive_location_page
│   ├── feed/            — mobile_official_feed_page, mobile_feed_detail_page
│   ├── team/            — mobile_team_page, org_chart_page
│   ├── profile/         — mobile_profile_page
│   ├── executive/       — executive_*_page (8 صفحات)
│   ├── manager/         — manager_*_page (2 صفحة)
│   ├── actions/         — mobile_action_*, deep_link
│   ├── notifications/   — mobile_notifications_page
│   ├── self_service/    — mobile_self_service_page
│   └── data/            — providers, models, services
├── shared/              — access_context
└── workspaces/          — *_workspace, workspace_scaffold, app_gate
```

**ملاحظة:** الهيكل الحالي (`features/mobile_pages/` المسطح) يعمل. إعادة الهيكلة تحسين وليس إصلاح عاجل.

---

# قسم 8 — تصحيح §25.2 (USING(true) في قسم الصلاحيات)

## النص المصحح (يستبدل §25.2 بالكامل)

### 25.2 القاعدة: USING(true) على جداول مرجعية فقط

> **تصحيح V21:** العدد الفعلي ليس 6 جداول بل **~32 جدول**. جميعها جداول مرجعية/كتالوجية لا تحتوي بيانات شخصية. هذا سلوك مقصود في التصميم الأصلي (mig 0003 تطبق USING(true) على كل جداول التنظيم عبر لوب).

**المبدأ:** USING(true) مسموح فقط على:
1. جداول كتالوجية/مرجعية (لا بيانات شخصية)
2. الكتابة محمية دائماً بـ `current_is_full_access()` أو `has_permission()`
3. أي جدول يحتوي بيانات موظفين → **ممنوع USING(true)**

**القائمة الكاملة:** انظر قسم 2.2 أعلاه (32 جدول مصنف ومبرر).

---

# قسم 9 — تصحيح §25.6 (has_scoped_permission)

## التصنيف المصحح

```sql
-- [مقترح] — هذه الدالة غير موجودة في المستودع حالياً
-- يجب إنشاؤها في migration جديدة (0158 أو لاحقاً)
-- تعتمد على: current_is_full_access(), current_employee_id(), current_role_ids()
-- تعتمد على: جدول manager_relations, جدول employees (team_id, department_id)
-- ملاحظة: عمود team_id في employees — محقق: موجود (mig 0004)
```

---

# قسم 10 — تصحيح §20.2 (get_operational_health)

## التصنيف المصحح

```
[مقترح] — get_operational_health() غير موجودة في المستودع
الموجود فعلياً: get_system_health() في mig 0054
get_operational_health() توسيع مقترح يجب إنشاؤه في migration جديدة
```

---

# قسم 11 — تصحيح §24.3 (daily_attendance_summary)

## التصنيف المصحح

```
[مقترح] — جدول daily_attendance_summary ودالة daily_attendance_finalization()
غير موجودين في المستودع حالياً
يحتاجان migration جديدة + إعداد pg_cron
يعتمدان على: attendance_events, employees, shifts, public_holidays
```

---

# قسم 12 — إضافات مفقودة من V20

## 12.1 اختبار الحمل (Load Testing) — قسم جديد

```
[مقترح] — يُضاف كقسم فرعي في بوابة الجودة 4

اختبار الحمل المطلوب قبل الإطلاق:
┌────────────────────────────────────────────────────┐
│                  سيناريوهات الحمل                    │
├────────────────────────────────────────────────────┤
│ 1. بصمة حضور متزامنة:                              │
│    - 50 موظف يسجلون حضور في نافذة 5 دقائق          │
│    - المتوقع: كل البصمات تنجح، لا timeout            │
│                                                     │
│ 2. طلبات متزامنة:                                   │
│    - 20 طلب إجازة في نفس الدقيقة                    │
│    - المتوقع: كل الطلبات تُسجل بدون تكرار           │
│                                                     │
│ 3. KPI concurrent evaluation:                       │
│    - 30 موظف يملأون التقييم الذاتي معاً             │
│    - المتوقع: لا deadlock، لا data loss               │
│                                                     │
│ 4. إشعارات FCM bulk:                                │
│    - منشور رسمي لـ 100+ موظف                        │
│    - المتوقع: كل الإشعارات تصل خلال 30 ثانية        │
│                                                     │
│ أدوات مقترحة:                                       │
│ - k6 (أو Artillery) لاختبار Edge Functions           │
│ - pgbench لاختبار RPCs المباشرة                      │
│ - Firebase Test Lab لاختبار FCM                      │
└────────────────────────────────────────────────────┘
```

## 12.2 Feature Flags — تفصيل مفقود

```
[قائم] — جدول feature_flags موجود في mig 0011
[مقترح] — آلية الاستخدام التفصيلية

الأعلام المطلوبة:
| العلم | الافتراضي | الغرض |
|---|---|---|
| kpi_enabled | true | تعطيل/تفعيل دورة KPI |
| disputes_enabled | true | تعطيل/تفعيل لجنة المشكلات |
| location_request_enabled | true | تعطيل/تفعيل طلب الموقع الحي |
| offline_attendance_queue | false | [ملغى — لا حضور offline] |
| multi_department | true | تفعيل الأقسام المتعددة (mig 0156) |
| device_approval_required | true | إلزام اعتماد الجهاز قبل البصمة |

آلية الفحص في Flutter:
  final flags = ref.watch(featureFlagsProvider);
  if (!flags['kpi_enabled']) return SizedBox.shrink();

آلية الفحص في Web:
  const { data: flags } = useFeatureFlags();
  if (!flags?.kpi_enabled) return null;

آلية الفحص في RPC:
  IF NOT public.is_feature_enabled('kpi_enabled') THEN
    RAISE EXCEPTION 'feature disabled' USING ERRCODE = 'P0001';
  END IF;
```

## 12.3 Rollback Strategy — قسم مفقود

```
[مقترح] — استراتيجية التراجع

لكل migration مقترحة جديدة، يجب تحضير:

1. Forward Migration: الملف العادي (0158_xxx.sql)
2. Rollback Script: ملف مصاحب (rollback_0158.sql) يحتوي:
   - DROP TABLE IF EXISTS للجداول الجديدة
   - DROP FUNCTION IF EXISTS للدوال الجديدة
   - DROP POLICY IF EXISTS للسياسات الجديدة
   - لا يُنشر — يُحفظ في scripts/rollbacks/

3. قاعدة Rollback:
   - Rollback ممكن فقط قبل backfill بيانات
   - بعد backfill → forward-fix migration فقط
   - لا rollback أبداً على migration منشورة في staging/production
```

---

# قسم 13 — تصحيح بوابات الجودة §29

## 13.1 تصحيح البوابة 0

| # | الفحص | الأمر | V20 | V21 تصحيح |
|---|---|---|---|---|
| 8 | فحص ترقيم migrations | `ls supabase/migrations/ \| cut -c1-4 \| sort \| uniq -d` | ✅ | ✅ صحيح |
| 9 | توثيق baseline | ملف `BASELINE.md` | أرقام مسجلة | **يجب تسجيل: 157 migration, 62 test, 45 web, ~80 flutter** |

## 13.2 إضافة للبوابة 4 — اختبار الحمل

| # | الفحص | الأمر | معيار النجاح |
|---|---|---|---|
| جديد | اختبار حمل بصمة | k6/pgbench | 50 بصمة متزامنة بدون timeout |
| جديد | اختبار حمل إشعارات | سيناريو FCM | 100 إشعار خلال 30 ثانية |
| جديد | فحص USING(true) | استعلام §2.4 أعلاه | 0 جداول غير مصرح بها |

---

# قسم 14 — تصحيح الجدول الزمني

## 14.1 ملاحظات على الجدول الزمني في V20

الجدول الزمني في V20 يذكر أسابيع نسبية (أسبوع 6، 10، 14، 16) بدون تاريخ بداية محدد. هذا يسبب غموضاً.

## 14.2 الجدول المصحح (تقديري من تاريخ اليوم)

| المرحلة | البوابة | الأسبوع النسبي | التاريخ التقديري | المحتوى |
|---|---|---|---|---|
| P0 — الأساسيات الحرجة | بوابة 1 | أسبوع 1–6 | 2026-07-27 → 2026-09-06 | أجهزة، حضور، طلبات، KPI، موقع حي |
| P1 — التكاملات | بوابة 2 | أسبوع 7–10 | 2026-09-07 → 2026-10-04 | FCM، كشف شهري، إجازات رسمية، Onboarding |
| P2 — إعادة الهيكلة | بوابة 3 | أسبوع 11–14 | 2026-10-05 → 2026-11-01 | Flutter restructure، RLS permission-based، تنظيف |
| P3 — الإطلاق | بوابة 4 | أسبوع 15–16 | 2026-11-02 → 2026-11-15 | اختبار حمل، staging verification، إطلاق |

**ملاحظة:** هذه تقديرات. التاريخ الفعلي يعتمد على قرار الإدارة ببدء التنفيذ.

---

# قسم 15 — Migrations المقترحة المحدّثة (يستبدل §24.5)

## 15.1 ملخص Migrations المطلوبة

| الترتيب | الرقم المقترح | المحتوى | الاعتمادية | التصنيف |
|---|---|---|---|---|
| 1 | 0158 | `unified_attendance_security_checks` — دالة تحقق موحّدة | 0005, 0089, 0094 | [مقترح] |
| 2 | 0159 | `daily_attendance_finalization_cron` — ملخص يومي + pg_cron | 0158, 0047 | [مقترح] |
| 3 | 0160 | `cleanup_rpc_overloads` — حذف دوال مكررة/قديمة | مستقل | [مقترح] |
| 4 | 0161 | `has_scoped_permission` — دالة فحص النطاق | 0002 | [مقترح] |
| 5 | 0162 | `rls_permission_based_phase1` — تحويل RLS للجداول الحساسة | 0161 | [مقترح] |
| 6 | 0163 | `rate_limit_admin_create_employee` — حد إنشاء موظفين | 0120 | [مقترح] |

**⚠️ تحذير:** الأرقام 0158–0163 تقديرية. يجب تنفيذ:
```bash
ls supabase/migrations/ | sort | tail -3
ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
```
قبل إنشاء أي migration جديدة — خطر التكرار حقيقي بسبب المحادثات المتوازية.

---

# قسم 16 — ملاحظات هيكلية على V20

## 16.1 مشاكل هيكلية في V20

1. **الحجم:** 9082 سطر / 389 كيلوبايت — أكبر من أن يقرأه شخص واحد بفعالية
2. **التكرار:** `current_is_full_access()` مشروحة في §19.1.3 و§25.3
3. **USING(true)** مذكورة بقوائم مختلفة في §19.1.2 و§25.2
4. **مزج التوثيق بالمقترح:** بلوكات كود بدون تمييز بين القائم والمقترح

## 16.2 اقتراح إعادة هيكلة الوثيقة

```
[مقترح] — تقسيم V20 إلى 5 وثائق مستقلة

1. DECISIONS.md (أقسام 0–15)
   → القرارات الوظيفية والإدارية وتجربة المستخدم
   → ~4000 سطر

2. TECHNICAL_INVENTORY.md (أقسام 16–18)
   → الجرد الفعلي للمستودع (migrations, functions, pages, tests)
   → ~1500 سطر
   → يُحدَّث تلقائياً من سكربت فحص

3. SECURITY_MODEL.md (أقسام 19–20)
   → RLS, Edge Functions, طبقات الأمان
   → ~1500 سطر

4. IMPLEMENTATION_PLAN.md (أقسام 21–27)
   → Migrations المقترحة, هيكلة Flutter/Web, خطة النشر
   → ~1500 سطر

5. QUALITY_GATES.md (أقسام 28–30)
   → مصفوفة الصلاحيات, بوابات الجودة, القائمة النهائية
   → ~1000 سطر

فائدة التقسيم:
- كل وثيقة يمكن مراجعتها مستقلاً
- TECHNICAL_INVENTORY.md يمكن توليدها آلياً
- DECISIONS.md لا يتغير إلا بقرار إداري
- IMPLEMENTATION_PLAN.md يتغير مع التقدم
```

---

# قسم 17 — القائمة النهائية المصححة (يكمّل §30)

## 17.1 إضافات لـ §30.2 (الأجهزة والحضور)

- [ ] **جديد:** Rate limit على `admin-create-employee` (20/ساعة)
- [ ] **جديد:** اختبار حمل بصمة متزامنة (50 بصمة في 5 دقائق)
- [ ] **تصحيح:** WebAuthn وLocal Biometric يستخدمان تحققاً موحداً ← **[مقترح — migration 0158]**

## 17.2 إضافات لـ §30.8 (Supabase/Security)

- [ ] **جديد:** فحص USING(true) يشمل القائمة الكاملة (~32 جدول) لا 6 فقط
- [ ] **جديد:** `has_scoped_permission()` مُنشأة ومختبرة ← **[مقترح — migration 0161]**
- [ ] **جديد:** اختبار حمل إشعارات FCM (100 إشعار / 30 ثانية)

## 17.3 إضافات لـ §30.9 (دليل الجاهزية)

- [ ] **جديد:** كل بلوك كود في الخطة مصنف [قائم/مقترح/توثيقي/ملغى]
- [ ] **جديد:** TECHNICAL_INVENTORY.md محدّث من سكربت آلي
- [ ] **جديد:** Rollback scripts جاهزة لكل migration مقترحة

---

# قسم 18 — سكربت التحقق الآلي

```bash
#!/bin/bash
# [توثيقي] — سكربت تحقق من الأرقام الأساسية
# يُشغَّل بعد كل تغيير لتحديث TECHNICAL_INVENTORY.md

echo "=== جرد المستودع ==="

MIG_COUNT=$(ls supabase/migrations/*.sql 2>/dev/null | wc -l)
echo "Migrations: $MIG_COUNT"

TEST_COUNT=$(ls supabase/tests/*.sql 2>/dev/null | wc -l)
echo "pgTAP Tests: $TEST_COUNT"

EF_COUNT=$(ls -d supabase/functions/*/index.ts 2>/dev/null | wc -l)
echo "Edge Functions: $EF_COUNT"

WEB_COUNT=$(find apps/admin_web/src/features -name '*.tsx' 2>/dev/null | wc -l)
echo "Web Feature Files: $WEB_COUNT"

FLUTTER_COUNT=$(find apps/mobile_flutter/lib -name '*.dart' 2>/dev/null | wc -l)
echo "Flutter Dart Files: $FLUTTER_COUNT"

FP_COUNT=$(grep -r 'FutureProvider' apps/mobile_flutter/lib/ --include='*.dart' 2>/dev/null | wc -l)
echo "FutureProvider: $FP_COUNT"

AN_COUNT=$(grep -r 'AsyncNotifier' apps/mobile_flutter/lib/ --include='*.dart' 2>/dev/null | wc -l)
echo "AsyncNotifier: $AN_COUNT"

CIFA_COUNT=$(grep -r 'current_is_full_access' supabase/migrations/ --include='*.sql' 2>/dev/null | wc -l)
echo "current_is_full_access refs: $CIFA_COUNT"

HP_COUNT=$(grep -r 'has_permission' supabase/migrations/ --include='*.sql' 2>/dev/null | wc -l)
echo "has_permission refs: $HP_COUNT"

LAST_MIG=$(ls supabase/migrations/*.sql | sort | tail -1 | grep -oP '\d{4}')
echo "Last Migration: $LAST_MIG"

echo ""
echo "=== فحوصات أمنية ==="

DUPES=$(ls supabase/migrations/ | cut -c1-4 | sort | uniq -d)
if [ -z "$DUPES" ]; then
  echo "Migration duplicates: ✅ no duplicates"
else
  echo "Migration duplicates: ❌ $DUPES"
fi

echo ""
echo "=== date: $(date '+%Y-%m-%d %H:%M') ==="
```

---

# ملحق أ — خريطة التناقضات المحلولة

| # | التناقض | §19 يقول | §25 يقول | الحل في V21 |
|---|---|---|---|---|
| 1 | قائمة USING(true) | 6 جداول (permissions, roles, role_permissions, kpi_criteria, official_holidays, learning_course_sessions) | 6 جداول (permissions, roles, role_permissions, kpi_criteria, request_types, shifts) | **~32 جدول** — قائمة كاملة في §2.2 |
| 2 | request_types USING(true) | غير مذكور | نعم | **لا — ليس لديه سياسة USING(true)** في المستودع |
| 3 | shifts USING(true) | غير مذكور | نعم | **نعم — من لوب mig 0003** |
| 4 | official_holidays USING(true) | نعم (0132) | غير مذكور | **نعم — من لوب mig 0003 + إعادة تعريف في 0132** |
| 5 | learning_course_sessions USING(true) | نعم (0033) | غير مذكور | **نعم — mig 0033** |

---

# ملحق ب — الملفات المتأثرة بالتصحيحات

عند تطبيق V21، هذه الملفات تحتاج تحديث:

| الملف | التغيير |
|---|---|
| `CLAUDE.md` | تحديث: 157 migration, 62 test file, 12 Edge Function |
| `BASELINE.md` (إن وُجد) | تحديث الأرقام الأساسية |
| `IMPLEMENTATION_TRACEABILITY.md` (إن وُجد) | تسجيل التصحيحات |

---

**نهاية وثيقة التصحيحات V21**

تاريخ الإنشاء: 2026-07-26  
مصدر التحقق: فحص مباشر للمستودع عبر Glob/Grep/Read  
الفرع: `codex/v17-master-plan`  
آخر migration: 0157_fix_seed_timing_permission_grants.sql
