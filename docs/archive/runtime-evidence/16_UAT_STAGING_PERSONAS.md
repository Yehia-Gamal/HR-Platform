# 16 — UAT: Persona Sign-in & Authorization (Staging)

**التاريخ / Date:** 2026-07-15
**البيئة / Environment:** الموقع المنشور `https://ahla-shabab-management-os.vercel.app` ↔ Supabase Staging `ujzzvqsodyhnnnpkoaml`
**الحالة / Status:** ✅ **PASS** — تسجيل الدخول والتخويل (إيجابي وسلبي) يعملان end-to-end لكل الشخصيات.

> لا أسرار في هذا الملف. كلمات المرور التجريبية مخزّنة في ذاكرة الجلسة فقط، وحسابات Staging لا تحوي PII حقيقية.

---

## 1. تسجيل الدخول (identifier-sign-in) — الشخصيات الخمس

نفس مسار الدخول الذي يستخدمه الويب المنشور (edge function `identifier-sign-in`، Origin = نطاق Vercel):

| الشخصية | البريد | HTTP | الجلسة |
|---|---|---|---|
| admin (full access) | admin@ahla.local | 200 | ✅ SESSION OK |
| hr-manager | hr@ahla.local | 200 | ✅ SESSION OK |
| employee | employee@ahla.local | 200 | ✅ SESSION OK |
| direct-manager | manager@ahla.local | 200 | ✅ SESSION OK |
| executive-director | executive@ahla.local | 200 | ✅ SESSION OK |

## 2. التخويل الإيجابي — `get_my_access_context()` بجلسة كل شخصية

| الشخصية | Workspaces | Default | ملاحظة |
|---|---|---|---|
| admin | employee, manager, executive, hr, main_admin, committee, field_operations (7) | main_admin | `permissions: ["*"]` — يؤكّد Migration 0053 |
| hr-manager | employee, hr | hr | نطاق HR + عرض الموظف الذاتي |
| employee | employee | employee | ذاتي فقط |
| direct-manager | employee, manager | manager | إدارة + ذاتي |
| executive-director | executive | executive | تنفيذي فقط · `selfPunchEnabled=false` (لا حضور شخصي) |

> كل شخصية تحصل على **بالضبط** مساحات العمل والصلاحيات التي يفرضها دورها — لا توسّع صلاحيات.

## 3. التخويل السلبي — RLS يُفرَض على مستوى API (لا مجرد إخفاء واجهة)

بجلسة **employee** عبر REST المباشر:

| الفحص | المتوقع | النتيجة |
|---|---|---|
| قراءة كل `employees` | صف الموظف نفسه فقط | ✅ **صف واحد** (EMP001 الذاتي)، لا الجدول كاملًا |
| قراءة `credential_vault` | مرفوض | ✅ **HTTP 403** |
| قراءة `system_alerts` (مراقبة) | مرفوض/فارغ | ✅ **0 صف** (RLS يقصرها على full_access/system.release) |

## 4. الخلاصة

✅ **UAT ناجح على Staging**: الشخصيات الخمس تسجّل الدخول، وتحصل على مساحات العمل الصحيحة،
وRLS يمنع فعليًا القراءة عبر النطاق والوصول للجداول الحساسة عبر الـAPI المباشر (لا اعتماد على إخفاء الواجهة).
يؤكّد هذا صحّة مسار الدخول + RBAC/ABAC + RLS في وقت التشغيل على البيئة المنشورة.

**المتبقي لـ UAT كامل:** مراجعة بصرية بشرية للوحات كل دور على النطاق المنشور (تتطلب مُراجعًا)،
واختبار شخصيات الموبايل (employee/manager/executive) داخل تطبيق Flutter على جهاز فعلي.
