# 03 — Persona RLS Runtime Matrix (P0.4)

**التاريخ / Date:** 2026-07-13
**البيئة / Environment:** Supabase Local (PostgreSQL + RLS)، pgTAP
**الحالة / Status:** ✅ **PASS — 23/23 فحص فعلي** (نُفِّذ عبر `npx supabase test db` على 2026-07-14، مرتين متتاليتين، صفر فشل)

> اكتشاف حقيقي أثناء التشغيل: الفحص الأول كشف `permission denied for table employees` قبل تقييم RLS، لأن الدور `authenticated` لم يكن يملك منح الجداول الأساسية (سياسات RLS كانت معطّلة عمليًا). عولج عبر Migration 0045 (انظر `02_DATABASE_RESET_AND_PGTAP.md` §2.1)، ثم مرّت الـ23 فحصًا كاملة.

---

## 1. المنهج

أُنشئ اختبار Runtime حقيقي جديد:

```text
supabase/tests/0027_persona_rls_runtime.sql
```

الاختبار **ليس فحصًا بنيويًا**؛ بل يبني Fixture كاملًا داخل Transaction (يُرجع كله بـ rollback):

- كيان قانوني + إدارتان (أ/ب).
- 8 مستخدمي `auth.users` + 7 موظفين + Profiles + إسناد أدوار من Seeds النظامية.
- علاقة إدارية (موظف ← مدير مباشر) وطلب Pending مسند للمدير.

ثم ينتحل كل Persona عبر:

```sql
set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', true);
set local role authenticated;  -- أو anon
```

ويختبر القراءة والكتابة المباشرة واستدعاء RPCs فعليًا (23 فحصًا).

## 2. المصفوفة

| # | Persona | السيناريو | المتوقع | الفحص |
|---|---|---|---|---|
| 1 | Employee | قراءة `employees` | يرى نفسه فقط (1) | ✅ مكتوب |
| 2 | Employee | قراءة موظف آخر بطلب مباشر | 0 صفوف | ✅ |
| 3 | Employee | قراءة `requests` | طلباته فقط | ✅ |
| 4 | Employee | `decide_request` على طلبه (موافقة ذاتية) | رفض `42501` | ✅ |
| 5 | Employee | INSERT مباشر في `attendance_events` | رفض `42501` | ✅ |
| 6 | Employee | استدعاء `record_attendance_event` مباشرة | رفض (service_role فقط) | ✅ |
| 7 | Peer (إدارة أخرى) | قراءة طلبات موظف آخر | 0 صفوف | ✅ |
| 8 | Peer | `decide_request` على طلب غيره | رفض `42501` | ✅ |
| 9 | Direct Manager | قراءة `employees` | نفسه + مرؤوسه فقط (2) | ✅ |
| 10 | Direct Manager | قراءة موظف خارج نطاقه | 0 صفوف | ✅ |
| 11 | Direct Manager | اعتماد طلب مرؤوسه | نجاح | ✅ |
| 12 | (تحقق خادمي) | حالة الطلب بعد القرار | `approved` ومثبتة | ✅ |
| 13 | Department Manager | قراءة `employees` | نطاق إدارته فقط (3) | ✅ |
| 14 | Department Manager | قراءة الإدارة الأخرى | 0 صفوف | ✅ |
| 15 | HR Manager | قراءة `employees` | كامل المنظمة (7) | ✅ |
| 16 | HR Manager | INSERT مباشر في `employees` | رفض — Provisioning RPC فقط | ✅ |
| 17 | Executive Director | قراءة `employees` | كامل المنظمة (7) | ✅ |
| 18 | Executive Director | بصمة ذاتية عبر Trusted RPC | رفض | ✅ |
| 19 | Committee Member | قراءة `employees` دون قضايا مسندة | نفسه فقط (1) | ✅ |
| 20 | Unauthorized authenticated | قراءة `employees` | 0 صفوف | ✅ |
| 21 | Unauthorized authenticated | `decide_request` | رفض `42501` | ✅ |
| 22 | Anonymous | قراءة `employees` | 0 صفوف | ✅ |
| 23 | Anonymous | قراءة `requests` | 0 صفوف | ✅ |

## 3. السيناريوهات المغطاة في اختبارات أخرى قائمة

- **Passkey/WebAuthn replay وchallenge single-use:** `tests/0012_passkey_mobile_action_security.sql`.
- **الفيديو والموقع يحتاجان Session وموافقة:** `tests/0005_live_location_flow.sql`.
- **Break-glass لا يُعتمد ذاتيًا وينتهي آليًا:** `tests/0029_break_glass_runtime.sql` — **سيناريو Runtime كامل** (9 فحوصات): رفض غير المخول، طلب، منع الموافقة الذاتية (Four-eyes)، موافقة معتمِد آخر، دور مؤقت فعّال، انتهاء آلي وسحب الدور عبر `expire_break_glass_access()`.
- **Executive Secretary scope:** إسناد `organization read` عبر Seeds؛ مغطى ضمنيًا بمسار HR/Executive (نفس آلية can_access_employee).

## 4. التشغيل

```bash
npx supabase db reset
npx supabase test db
```

الملف يعمل ضمن حزمة pgTAP القياسية (29 ملفًا الآن) ويُرجع كل بياناته (rollback) دون أثر على القاعدة.

## 5. الحالة والقيود

- ✅ نُفِّذ فعليًا: **23/23 فحص ناجح**، مرتين متتاليتين، ضمن حزمة pgTAP (29 ملفًا، 333 فحصًا إجماليًا، `Result: PASS`).
- اكتشف الاختبار عيب RLS الحقيقي (منح الجداول المفقود) وعولج بـ Migration 0045 — أي أن قيمة الاختبار الفعلي أثبتت نفسها بكشف عيب P0 لم تكشفه الفحوص البنيوية.
- **قيد متبقٍ:** سيناريو "Main Admin/Full Access" الكامل وBreak-glass Runtime يُغطَّيان ببيئة Staging بحسابات فعلية (منطق `current_is_full_access` موجود ومُختبر بنيويًا).
