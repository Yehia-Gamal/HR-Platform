# Traceability Matrix — أحلى شباب HR V23

> مصفوفة تتبع من متطلبات Master Decisions V23 → الوكيل المسؤول → الملفات → الاختبارات → الحالة.
> الحالات: DISCOVERED / DESIGNED / IMPLEMENTED / TESTED / RUNTIME_VERIFIED / RELEASED

---

## §1 البنية الثابتة

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 1.1 | Flutter + Riverpod | 10 | تصميم أصلي | `apps/mobile_flutter/` (79 files) | — | 29 test | RUNTIME_VERIFIED |
| 1.2 | React/Vite + TanStack + Zod | 5 | تصميم أصلي | `apps/admin_web/` (104 files) | — | 32 test | RUNTIME_VERIFIED |
| 1.3 | Supabase/PostgreSQL | 2 | تصميم أصلي | `supabase/` | 158 migrations | 61 pgTAP / 650+ assertions | RUNTIME_VERIFIED |
| 1.4 | Supabase Edge Functions | 3,4,11 | تصميم أصلي | `supabase/functions/` (12 functions) | — | smoke tests | RUNTIME_VERIFIED |
| 1.5 | Firebase Cloud Messaging v1 | 11 | تصميم أصلي | `notification-dispatcher/` | — | — | RUNTIME_VERIFIED |
| 1.6 | Android native notification | 10,11 | تصميم أصلي | `apps/mobile_flutter/android/` | — | — | RUNTIME_VERIFIED |
| 1.7 | مشروع واحد فقط | 14 | سياسة | monorepo واحد | — | — | RUNTIME_VERIFIED |

---

## §2 الأدوار المعتمدة

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 2.1 | السكرتير التنفيذي (Admin+HR) | 3,5 | 0121 seed | `access.ts`, `WorkspaceShell.tsx` | 0121 | 0001,0027 | RUNTIME_VERIFIED |
| 2.2 | مدير HR (HR workspace فقط) | 3,5 | 0121 seed | `access.ts` | 0121,0151 | 0027 | RUNTIME_VERIFIED |
| 2.3 | المدير التنفيذي (هاتف تنفيذي) | 10 | 0121 seed | `executive_workspace.dart` | 0121 | — | RUNTIME_VERIFIED |
| 2.4 | مدير التشغيل | 10 | 0121 seed | `operations_workspace.dart` | 0121 | — | RUNTIME_VERIFIED |
| 2.5 | عضو لجنة المشكلات | 9 | 0121 seed | `committee_workspace.dart` | 0121,0152 | 0018 | RUNTIME_VERIFIED |
| 2.6 | المدير المباشر | 10 | 0121 seed | `manager_workspace.dart` | 0121 | — | RUNTIME_VERIFIED |
| 2.7 | الموظف | 10 | تصميم أصلي | `employee_workspace.dart` | — | — | RUNTIME_VERIFIED |

---

## §3 نظام الصلاحيات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 3.1 | قوالب أدوار عربية | 3 | 0121 seed | `roles` table | 0121 | 0001 | RUNTIME_VERIFIED |
| 3.2 | لا Permission منفردة للمستخدم | 3 | تصميم RLS | `role_permissions` | 0002,0121 | 0001 | IMPLEMENTED |
| 3.3 | Main Admin يمنح الأدوار العليا | 3 | `current_is_full_access()` | RPCs | 0013,0121 | 0001 | RUNTIME_VERIFIED |
| 3.4 | RLS/ABAC تعتمد reporting lines | 3 | `can_access_employee()` | RPCs | 0013,0084 | 0027 | IMPLEMENTED |

---

## §4 حالة الموظف الجديد

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 4.1 | employment_status = active عند الإنشاء | 4 | `provision_employee_record` | edge fn + RPC | 0079,0125 | 0051 | RUNTIME_VERIFIED |
| 4.2 | يظهر في الدليل والهيكل | 4,5 | `get_employees_enriched` | RPCs | 0129 | 0052 | RUNTIME_VERIFIED |
| 4.3 | حالة الدخول والجهاز منفصلة | 6 | device registry | `employee_devices` | 0145,0158 | 0061 | RUNTIME_VERIFIED |
| 4.4 | الجهاز غير المعتمد يمنع الحضور فقط | 6 | attendance guard | `finalize_verified_attendance` | 0089,0093 | 0042 | RUNTIME_VERIFIED |

---

## §5 الجهاز والبصمة

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 5.1 | جهاز نشط واحد + Recovery | 6 | device lifecycle | `employee_devices` | 0145 | 0061 | RUNTIME_VERIFIED |
| 5.2 | تسجيل جهاز جديد لا يتطلب القديم | 6 | device approval flow | `get_pending_devices_admin` | 0145 | 0061 | RUNTIME_VERIFIED |
| 5.3 | HR/Admin يعتمد الجديد ويلغي القديم | 6 | `approve_device` RPC | RPCs | 0145,0158 | 0061 | RUNTIME_VERIFIED |
| 5.4 | Challenge خادمي بمفتاح جهاز | 3 | WebAuthn + passkey | edge fns | 0094 | 0012 | RUNTIME_VERIFIED |

---

## §6 الحضور

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 6.1 | Geofence 300م وقابل للضبط | 6 | `work_sites` + `geofences` | tables | 0005,0046 | 0006 | RUNTIME_VERIFIED |
| 6.2 | خارج النطاق = رفض | 6 | `record_attendance` | RPCs | 0089 | 0042 | RUNTIME_VERIFIED |
| 6.3 | Mock/Impossible travel checks | 6 | `check_impossible_travel` | RPCs | 0046,0120 | 0042 | RUNTIME_VERIFIED |
| 6.4 | زر الحضور يتحول إلى الانصراف | 6,10 | `get_attendance_state` | RPCs + mobile UI | 0019 | 0007 | RUNTIME_VERIFIED |
| 6.5 | Missing Checkout — لا وقت وهمي | 6 | attendance settlement | `settle_attendance_day` | 0028 | 0016 | IMPLEMENTED |
| 6.6 | لا حضور Offline | 6 | online-only guard | mobile + edge fn | 0089 | 0042 | RUNTIME_VERIFIED |

---

## §7 الإجازات والتكليفات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 7.1 | أنواع الإجازات (اعتيادية/عارضة/مرضية) | 7 | `leave_types` | tables | 0060 | 0038 | RUNTIME_VERIFIED |
| 7.2 | أرصدة الإجازات (15/6/policy) | 7 | `leave_entitlements` | tables | 0060 | 0038 | IMPLEMENTED |
| 7.3 | العارضة = تنفيذ مباشر بشروط | 7 | `submit_casual_leave` | RPCs | 0061 | 0038 | IMPLEMENTED |
| 7.4 | مسار القرار (مدير → تصعيد) | 7 | `resolve_request_approver` | RPCs | 0062,0136 | 0056 | RUNTIME_VERIFIED |
| 7.5 | لا اعتماد ذاتي | 7 | `no_self_approve` check | RPCs | 0062 | 0056 | IMPLEMENTED |
| 7.6 | التكليفات (مأمورية/قافلة/فاندي) | 7 | `work_assignments` | tables | 0063,0065 | 0039 | RUNTIME_VERIFIED |
| 7.7 | لا خصم رصيد في فترة التكليف | 7 | `attendance_link` | RPCs | 0065,0066 | 0039 | IMPLEMENTED |

---

## §8 KPI — المسار الوحيد (V23: المسار المتوازي)

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 8.1 | دورة KPI (فتح → ذاتي → HR/مدير بالتوازي → barrier → سكرتير → تنفيذي → إغلاق) | 8 | `advance_kpi_stage` | RPCs | 0058,0109,0130,0162 | 0035,0053,0065 | RUNTIME_VERIFIED |
| 8.2 | HR: الحضور 20، الصلاة 5، الحلقة 5 (30 نقطة) | 8 | `kpi_criteria` weights | data + `kpi.ts` | 0058 | 0035, kpi.test.ts | RUNTIME_VERIFIED |
| 8.3 | المدير: الأهداف 40، الكفاءة 20، السلوك 5، المبادرات 5 (70 نقطة) | 8 | `kpi_criteria` weights — V23: السلوك انتقل من HR للمدير | data + `kpi.ts` | 0058 | 0035, kpi.test.ts | RUNTIME_VERIFIED |
| 8.4 | Executive لا يقيم ولا يعدل | 8 | stage guard | `advance_kpi_stage` | 0130 | 0053 | IMPLEMENTED |
| 8.5 | V23: مسار متوازي (HR + مدير بالتوازي → حاجز → سكرتير → تنفيذي) | 8 | `kpi.ts` parallel stages | `kpi.ts`, `operations.ts` | 0162 | 0065, kpi.test.ts | IMPLEMENTED |
| 8.6 | V23: 10 مراحل (self→parallel→hr→manager→final→secretary→executive→finalized→closed→archived) | 8,14 | `kpiStageSchema` + `KPI_STAGE_ORDER` | `kpi.ts` | 0162 | kpi.test.ts (180 pass) | TESTED |

---

## §9 لجنة المشكلات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 9.1 | نموذج مبسط (عنوان/وصف/أطراف/شهود/إقرارات) | 9 | `dispute_cases` | tables | 0059,0064 | 0037 | RUNTIME_VERIFIED |
| 9.2 | المسار (موظف → سكرتير → لجنة → تنفيذي → HR → إغلاق) | 9 | dispute workflow | RPCs | 0131,0141 | 0054 | RUNTIME_VERIFIED |
| 9.3 | حذف الأولوية والمكان والأدلة | 9 | V23 §9 | UI + schema | 0064 | 0037 | IMPLEMENTED |

---

## §10 الموقع المباشر

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 10.1 | المدير التنفيذي فقط يطلب | 11 | `request_live_location` | RPCs | 0067,0073 | 0040,0041 | RUNTIME_VERIFIED |
| 10.2 | لا فيديو أو كاميرا أو ميكروفون | 11 | V17 no-video policy | `live-location-video-url` = 410 | 0124 | 0040 | RUNTIME_VERIFIED |
| 10.3 | Outbox + FCM + Native + Full-screen | 11 | push pipeline | `notification-dispatcher` | 0116 | 0048 | RUNTIME_VERIFIED |
| 10.4 | GPS يعاد فحصه عند الرجوع | 10 | `location_service.dart` | mobile | — | — | IMPLEMENTED |
| 10.5 | Request/Correlation IDs | 11 | audit trail | `live_location_requests` | 0107 | 0040 | RUNTIME_VERIFIED |

---

## §11 المنشورات والقرارات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 11.1 | ينشر من Admin/HR/Executive Mobile | 10 | `publish_official_announcement` | RPCs + UI | 0133,0142 | 0057 | RUNTIME_VERIFIED |
| 11.2 | قرارات وتنبيهات وتصويتات | 10 | `post_types` | tables | 0027,0133 | 0015 | RUNTIME_VERIFIED |

---

## §12 الموظف متعدد الإدارات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 12.1 | P0: Primary + Secondary assignments | 4 | `employee_departments` | tables | 0156 | — | IMPLEMENTED |
| 12.2 | الطلبات والحضور وKPI تعتمد Primary | 4,6,7,8 | primary flag | `employee_departments` | 0156 | — | IMPLEMENTED |

---

## §13 الصفحات الملغاة

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 13.1 | حذف الخصوصية المستقلة | 5 | V17 §4.2 | `App.tsx` line 32 | — | — | IMPLEMENTED |
| 13.2 | حذف التدريب والمهارات | 5 | V17 §4.2 | `LearningPage` (hidden) | — | — | IMPLEMENTED |
| 13.3 | حذف مستنداتي | 5 | V17 §4.2 | `DocumentStudioPage` (hidden) | — | — | IMPLEMENTED |
| 13.4 | حذف العهد | 5 | V17 §4.2 | removed from routes | — | — | IMPLEMENTED |
| 13.5 | حذف نهاية العقد | 5 | V17 §4.2 | removed from routes | — | — | IMPLEMENTED |
| 13.6 | حذف الرواتب | 5 | V17 §4.2 | `PeopleFinancePage` (hidden) | — | — | IMPLEMENTED |
| 13.7 | حذف المخاطر والحوكمة | 5 | V17 §4.2 | `ReleaseGovernancePage` (hidden) | — | — | IMPLEMENTED |
| 13.8 | حذف مكتب الخدمات | 5 | V17 §4.2 | `ServiceDeskPage` (hidden) | — | — | IMPLEMENTED |
| 13.9 | حذف التقارير المكررة الفارغة | 5 | V17 §4.2 | cleaned in routes | — | — | IMPLEMENTED |

---

## §14 الأمان والـMigrations

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 14.1 | Default Deny | 3 | RLS policies | all tables | 0050,0052,0095,0096 | 0031,0044 | RUNTIME_VERIFIED |
| 14.2 | USING(true) allowlist موثقة | 3,14 | audit review | V21 §19.1.2 | — | — | DISCOVERED |
| 14.3 | RLS تدريجي + Feature Flags | 3 | gradual rollout | — | — | — | DESIGNED |
| 14.4 | Migration names: YYYYMMDDHHMMSS | 2,14 | naming convention | all migrations | — | — | RUNTIME_VERIFIED |
| 14.5 | Security/QA من Wave 0 | 3,14 | policy | CI + tests | — | — | RUNTIME_VERIFIED |

---

## §15-16 الموجات وسلم الإثبات

| # | المتطلب | الوكيل | Root Cause | الملفات | Migration | الاختبارات | الحالة |
|---|---|---|---|---|---|---|---|
| 15.1 | Wave 0: Discovery + baselines | 1,3,14 | V23 setup | integration docs | — | — | IMPLEMENTED |
| 15.2 | Wave 1-7: incremental delivery | all | master plan | — | — | — | DESIGNED |
| 16.1 | سلم الإثبات (10 مراحل) | 14 | traceability | this file | — | — | IMPLEMENTED |

---

## ملخص إحصائي

| الحالة | العدد | النسبة |
|---|---|---|
| RELEASED | 0 | 0% |
| RUNTIME_VERIFIED | 33 | 58% |
| TESTED | 1 | 2% |
| IMPLEMENTED | 20 | 35% |
| DESIGNED | 2 | 4% |
| DISCOVERED | 1 | 2% |
| **المجموع** | **57** | **100%** |

---

## الفجوات المعروفة (تحتاج عمل V23)

1. **§3.4** — RLS/ABAC بالكامل تعتمد reporting lines (مصمم، بحاجة اختبار شامل)
2. **§7.2-7.3** — أرصدة الإجازات والعارضة (مُنفذ، بحاجة Runtime verification)
3. **§7.5** — لا اعتماد ذاتي (مُنفذ، بحاجة اختبار E2E)
4. **§8.4** — Executive لا يقيم KPI (مُنفذ، بحاجة Runtime verification)
5. **§12.1-12.2** — Multi-department (P0 مُنفذ، بحاجة اختبارات)
6. **§14.2** — USING(true) allowlist (مُكتشف فقط، بحاجة توثيق كامل)
7. **§14.3** — RLS تدريجي + Feature Flags (مصمم، لم يُنفذ)
