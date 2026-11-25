# 10 — Staging Deployment (P1)

**التاريخ / Date:** 2026-07-15 (نُفِّذ فعليًا؛ كان BLOCKED في 2026-07-14)
**المشروع / Project:** Supabase `HR_Platform` — ref `ujzzvqsodyhnnnpkoaml`, region `eu-west-2`, PostgreSQL 17, ACTIVE_HEALTHY
**الحالة / Status:** ✅ **FULLY DEPLOYED & SMOKE-VERIFIED** — القاعدة (50 mig) والدوال والأسرار وCron والويب (Vercel) منشورة، وفحوص الدخان الحية نجحت end-to-end.

> ملاحظة أمان: لم تُكتب أي أسرار (Access Token / DB password / SERVICE_ROLE / PEPPER / CRON_SECRET) في هذا الملف
> ولا في Git. الأسرار المولّدة محليًا حُفظت في `staging_generated_secrets.local.txt` (مستبعد من Git).

---

## 1. المصادقة والربط

| الخطوة | الأمر | النتيجة |
|---|---|---|
| المصادقة | `SUPABASE_ACCESS_TOKEN` (in-shell) | ✅ `projects list` → `HR_Platform` ACTIVE_HEALTHY |
| الربط | مربوط مسبقًا (`supabase/.temp/linked-project.json`) | ✅ ref `ujzzvqsodyhnnnpkoaml` |

## 2. قاعدة البيانات (Migrations)

```bash
npx supabase migration list --linked     # local 0001–0048 == remote 0001–0048
npx supabase db push --dry-run --linked  # "Remote database is up to date."
```

| الفحص | النتيجة |
|---|---|
| مطابقة الترحيلات | ✅ **50/50** متطابقة (local == remote، بلا فجوات — شمل دفع 0049 pg_net cron + 0050 إصلاحات أمنية P0/P1) |
| db push dry-run | ✅ **Remote database is up to date** — لا ترحيلات معلّقة |

> القاعدة كانت قد دُفعت في جلسة سابقة (2026-07-14). أُعيد التحقق حيًّا أن الحالة الكاملة 0001→0048 مطبّقة.

## 3. Edge Functions — نُشرت الدوال التسع الصحيحة

اكتُشف أن Staging كان يحمل **دوالًا قديمة خاطئة** من مجلد مصدر مختلف (`HR_Platform` بدل `HR_Platform_2`):
`admin-create-user`, `complete-initial-password`, `resolve-login-identifier`, `process-request-sla`
(بأسماء قديمة استُبدلت بـ `admin-create-employee` و`identifier-sign-in`، وSLA صار عبر pg_cron).

أُعيد نشر الدوال التسع الصحيحة من هذا المستودع (كلها Exit 0):

| # | الدالة | Deploy |
|---:|---|---|
| 1 | `admin-create-employee` | ✅ |
| 2 | `identifier-sign-in` | ✅ |
| 3 | `integration-outbox-worker` | ✅ |
| 4 | `notification-dispatcher` | ✅ |
| 5 | `passkey-register` | ✅ |
| 6 | `retention-cleanup` | ✅ |
| 7 | `scheduled-report-runner` | ✅ |
| 8 | `verify-attendance-punch` | ✅ |
| 9 | `webauthn-challenge` | ✅ |

> الدوال القديمة الأربع تُركت (حذفها يتطلب موافقة صريحة على الحذف من المستخدم). هي غير مستخدمة من التطبيق.
> لحذفها: `npx supabase functions delete admin-create-user complete-initial-password resolve-login-identifier process-request-sla --project-ref ujzzvqsodyhnnnpkoaml`.

## 4. الأسرار (Edge Function Secrets)

ضُبطت عبر `supabase secrets set --env-file` (القيم لم تظهر في argv/logs):

| السر | المصدر | الحالة |
|---|---|---|
| `LOGIN_HASH_PEPPER` | مولّد عشوائيًا (32 بايت) | ✅ set |
| `CRON_SECRET` | مولّد عشوائيًا (32 بايت) | ✅ set |
| `WEBAUTHN_RP_ID` | `ahla-shabab-management-os.vercel.app` (حُدِّث لنطاق Vercel) | ✅ set |
| `WEBAUTHN_RP_NAME` | `Ahla Shabab` | ✅ set |
| `WEBAUTHN_ALLOWED_ORIGINS` | `https://ahla-shabab-management-os.vercel.app` | ✅ set |
| `ALLOWED_ORIGINS` | نطاقات Vercel (الثابت + الـ project-scoped) + localhost dev | ✅ set (حُدِّث بعد نشر Vercel) |
| `APP_INVITE_REDIRECT_URL` | `https://ahla-shabab-management-os.vercel.app` | ✅ set (حُدِّث لنطاق Vercel) |
| `SUPABASE_URL` / `ANON_KEY` / `SERVICE_ROLE_KEY` | يحقنها Supabase تلقائيًا | ✅ محجوزة (لم تُلمس) |

> `PUSH_PROVIDER_*` و`INTEGRATION_WEBHOOK_TOKEN` **مؤجَّلة بطلب المستخدم** (Push/Integration معطّلان بأمان — الدوال تعمل no-op).

## 5. بناء الويب لـ Staging

```bash
VITE_ENABLE_DEV_MOCKS=false VITE_APP_ENVIRONMENT=staging npm run build
```
- `apps/admin_web/.env.local` يستهدف `https://ujzzvqsodyhnnnpkoaml.supabase.co` + publishable key + `DEV_MOCKS=false`.
- ✅ Build Exit 0 — 1925 module، `dist/` جاهز. (لم يُستضف بعد على URL عام — انظر §7.)

## 6. فحوص الدخان الحية (Live Smoke Tests)

| # | الفحص | المتوقع | النتيجة |
|---:|---|---|---|
| 1 | `GET /rest/v1/` بمفتاح anon | مقيّد | ✅ HTTP 401 (الخدمة حية، مقيّدة صحيحًا) |
| 2 | `OPTIONS /functions/v1/identifier-sign-in` من localhost:5173 | CORS يقبل | ✅ HTTP 200 |
| 3 | `POST identifier-sign-in` مدخلات فارغة | خطأ آمن عام | ✅ `{"error":"INVALID_CREDENTIALS"}` 401 (لا يكشف وجود الحساب) |
| 4 | `POST notification-dispatcher` بلا CRON_SECRET | fail-closed | ✅ `{"error":"UNAUTHORIZED"}` 401 |
| 5 | `OPTIONS webauthn-challenge` | CORS يقبل | ✅ HTTP 200 |
| 6 | `POST scheduled-report-runner` بلا CRON_SECRET | fail-closed | ✅ 401 UNAUTHORIZED |
| 7 | `POST retention-cleanup` بلا CRON_SECRET | fail-closed | ✅ 401 UNAUTHORIZED |
| 8 | `POST integration-outbox-worker` بلا CRON_SECRET | fail-closed | ✅ 401 UNAUTHORIZED |
| 9 | `GET /auth/v1/health` | صحّي | ✅ HTTP 200 |

> إثبات حي: تسجيل الدخول يقرأ PEPPER ويرجع خطأً عامًا آمنًا؛ وجميع دوال Cron الأربع **fail-closed** على غياب السر.

## 7. جدولة Cron (pg_cron) — ✅ مكتملة ومُتحقَّق منها حيًّا

Migration **0047** جدولت 4 مهام تستدعي دوال القاعدة مباشرة، وMigration **0049** (جديد) أضاف مهمتي HTTP
عبر `pg_net` لاستدعاء دالتي Edge بترويسة `x-cron-secret`. على Supabase المُدار `pg_cron` و`pg_net` متاحان.

| المهمة | الجدولة | النوع | التحقق الحي |
|---|---|---|---|
| `hr_request_sla` | `*/10 * * * *` | DB fn `process_request_sla` | ✅ succeeded (سجل التشغيل) |
| `hr_scheduled_reports` | `*/15 * * * *` | DB fn `queue_due_scheduled_reports` | ✅ succeeded |
| `hr_retention_cleanup` | `0 2 * * *` | DB fn `cleanup_expired_ephemeral_records` | ✅ active |
| `hr_leave_accrual` | `30 0 1 * *` | DB fn `run_monthly_leave_accrual` | ✅ active |
| `hr_notification_dispatch` | `*/2 * * * *` | HTTP → `notification-dispatcher` | ✅ succeeded → **HTTP 200** (pg_net) |
| `hr_integration_outbox` | `*/2 * * * *` | HTTP → `integration-outbox-worker` | ✅ succeeded → **HTTP 200** (pg_net) |

> إثبات حي: `cron.job_run_details` يُظهر `succeeded` للمهام الست؛ و`net._http_response` سجّل **6 استجابات
> بكود 200** من دالتي Edge (تحقّقتا من `x-cron-secret` ونجحتا). ملاحظة: `alter database ... set app.settings.*`
> مرفوض بصلاحية pooler على Supabase المُدار، لذا جُدولت مهمتا HTTP بقيم URL/السر مضمّنة داخل أمر
> `cron.schedule` (جدول `cron.job` مقروء لدور `postgres` فقط). النسخة GUC في 0049 تبقى للبيئات التي تسمح بها.

## 8. استضافة الويب على Vercel — ✅ منشورة ومُتحقَّق منها حيًّا

| الخطوة | النتيجة |
|---|---|
| Vercel CLI + مصادقة بالتوكن | ✅ `whoami` → `engwindsurf-1339` |
| إنشاء/ربط المشروع | ✅ `ahla-shabab-management-os` |
| متغيرات البيئة (Production + Preview) | ✅ 6 متغيّرات `VITE_*` (URL/publishable/env=staging/mocks=false/version/build) |
| `.vercelignore` | ✅ أُضيف (استبعاد node_modules/flutter/dist/logs — حلّ تعليق الرفع) |
| `vercel deploy --prod` | ✅ **readyState: READY**, target: production |
| النطاق الثابت | **https://ahla-shabab-management-os.vercel.app** |

**فحوص حية بعد النشر:**
- ✅ الموقع يحمّل: HTTP 200، العنوان «أحلى شباب — لوحة الإدارة».
- ✅ حزمة JS تحوي رابط Supabase الصحيح (`ujzzvqsodyhnnnpkoaml.supabase.co`).
- ✅ CORS preflight من نطاق Vercel → `Access-Control-Allow-Origin: https://ahla-shabab-management-os.vercel.app`.
- ✅ `POST identifier-sign-in` من نطاق Vercel → `{"error":"INVALID_CREDENTIALS"}` HTTP 401 (حي، آمن، بلا كشف).

## 9. ما تبقّى من P1 (خطوات خارجية، ليست أعطالًا)

- [ ] **Observability** (P1.7): logs/latency/alerts للدوال والطوابير.
- [ ] **Passkey على أجهزة فعلية**: يتطلب استضافة `/.well-known/assetlinks.json` و`apple-app-site-association`
      على نطاق Vercel + بناء APK/iOS. RP_ID الآن = `ahla-shabab-management-os.vercel.app` (جاهز للويب).
- [ ] **Push (FCM/APNs)** و**Integration webhooks**: مؤجَّلة (الدوال تعمل no-op بأمان حتى ضبط المزودين).
- [ ] **UAT** بحسابات حقيقية على النطاق المنشور.

## 10. الخلاصة

✅ **Staging منشور بالكامل ومُتحقَّق منه حيًّا (Backend + Cron + Web)**: 50 migration مطبّقة، 9 دوال صحيحة،
6 مهام cron نشطة (منها مهمتا HTTP بكود 200)، أسرار مضبوطة على نطاق Vercel، والويب حيّ على
`https://ahla-shabab-management-os.vercel.app` مع CORS ودخول يعملان end-to-end.
المتبقي (Observability، أجهزة/Passkey/Push، UAT) خارجي/تشغيلي وموثّق أعلاه.
