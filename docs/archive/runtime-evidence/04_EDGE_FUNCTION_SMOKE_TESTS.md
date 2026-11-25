# 04 — Edge Functions Smoke Tests (P0.5)

**التاريخ / Date:** 2026-07-14
**البيئة / Environment:** Supabase محلي (Docker). خدمة edge_runtime المساعدة كانت متوقفة في هذه الجلسة،
لذا الإثبات الحالي هو **تحليل أمني مُتحقَّق من المصدر** لكل دالة + بنية التحقق الداخلي؛ اختبار HTTP الحي الكامل
(Happy/Unauthorized/Replay) يُستكمل على Staging في `10_STAGING_DEPLOYMENT.md`.
**الحالة / Status:** ✅ الوضع الأمني مؤكَّد من المصدر — لا اعتماد على `verify_jwt=false` كإذن عام.

---

## 1. الوظائف القابلة للنشر (9) + `_shared`

```
admin-create-employee   identifier-sign-in       integration-outbox-worker
notification-dispatcher passkey-register         retention-cleanup
scheduled-report-runner verify-attendance-punch  webauthn-challenge
```

## 2. نقطة حرجة: `verify_jwt=false` ليست «وصولًا عامًا»

`config.toml` يضبط `verify_jwt=false` لجميع الدوال. **هذا مقصود وآمن** لأن كل دالة تتحقق من التخويل
داخليًا (Bearer JWT عبر `auth.getUser`، أو `x-cron-secret`)، بدل الاعتماد على بوابة Kong. جرى التحقق من ذلك
من المصدر لكل دالة:

| الدالة | نموذج التخويل الداخلي | مصدر التحقق |
|---|---|---|
| `identifier-sign-in` | عام بحكم التصميم (تسجيل دخول) + **rate limiting** (IP: 10/دقيقة، Identifier: 6/5دقائق) + تأخير ثابت لمنع التعداد + أخطاء عامة `INVALID_CREDENTIALS` + تدقيق | `index.ts` 62–179 |
| `verify-attendance-punch` | يستخرج Bearer → `admin.auth.getUser(token)` (401 عند الغياب/البطلان) + حد حجم 256KB + تحقق إحداثيات + WebAuthn assertion + RP_ID + Allowed Origins + كتابة عبر RPC خادمي فقط | `index.ts` 47–70 |
| `retention-cleanup` | يتطلب `x-cron-secret == CRON_SECRET` (401 خلاف ذلك) | `index.ts` 9–12 |
| `notification-dispatcher` | `x-cron-secret` (وظيفة مجدولة) | مصدر الدالة |
| `integration-outbox-worker` | `x-cron-secret` (وظيفة مجدولة) | مصدر الدالة |
| `scheduled-report-runner` | `x-cron-secret` (وظيفة مجدولة) | مصدر الدالة |
| `admin-create-employee` | Bearer JWT + فحص صلاحية admin داخليًا | مصدر الدالة |
| `passkey-register` | Bearer JWT + تحدي WebAuthn | مصدر الدالة |
| `webauthn-challenge` | يصدر تحديًا صالحًا لمرة واحدة بعمر محدود | مصدر الدالة |

## 3. الضوابط الأمنية المشتركة (تحقّق من المصدر)

- ✅ **CORS مقفل:** `_shared/cors.ts` — لا wildcard؛ `Access-Control-Allow-Origin` من قائمة `ALLOWED_ORIGINS`
  فقط (+ نطاقات dev محلية عند بيئة التطوير)، مع `Vary: Origin`.
- ✅ **الأساليب:** `POST, OPTIONS` فقط؛ غير ذلك 405.
- ✅ **أخطاء آمنة:** رسائل عامة (`INVALID_CREDENTIALS`, `unauthorized`) دون تسريب تفاصيل قاعدة البيانات.
- ✅ **Rate limiting:** مُطبّق في `identifier-sign-in` (نافذتان IP/Identifier) مع تسجيل المحاولات.
- ✅ **Audit / Correlation:** `log_audit_event` وسجلات محاولات الدخول (`login_auth_attempts`).
- ✅ **لا تسريب أسرار:** لا تُرجع الدوال مفاتيح/توكنات في أجسام الاستجابة؛ فقط أعداد/حالات.
- ✅ **الكتابة الحساسة عبر RPC خادمي:** `verify-attendance-punch` لا يكتب في `attendance_events` مباشرة
  بل عبر RPC (متسق مع carve-out المنع المباشر في Migration 0045).

## 3.1 تقوية أمنية طُبِّقت أثناء المراجعة (Fail-closed hardening)

| الدالة | العيب المكتشف | الإصلاح المطبق |
|---|---|---|
| `notification-dispatcher` | لا يوجد فحص Method (أي Verb يبدأ المعالجة بعد السر)، ومقارنة السر لا ترفض صراحة عند غياب `CRON_SECRET` من البيئة | رفض غير-POST بـ405 + `if (!cronSecret || ...)` fail-closed |
| `scheduled-report-runner` | نفس نمط السر + كان يسرّب `error.message` من قاعدة البيانات في استجابة `QUEUE_FAILED` | Method check + fail-closed + الرسالة إلى `console.error` فقط والاستجابة عامة |

> لا تغيير على السلوك الشرعي: Cron بالسر الصحيح عبر POST يعمل كما كان.

## 3.2 سكربت Smoke تنفيذي جاهز

أُنشئ `scripts/edge-smoke-tests.sh` — يختبر الدوال التسع ضد العقود الأمنية
(401 بلا توكن/سر، 405 لغير POST، 400 لمدخلات ناقصة، عدم كشف وجود الحساب،
عدم عكس Origin غير موثوق في CORS، وفحص كل استجابة ضد تسريب رسائل قاعدة البيانات):

```bash
npx supabase start
npx supabase functions serve &
BASE_URL=http://127.0.0.1:54321/functions/v1 ANON_KEY=<LOCAL_ANON_KEY> bash scripts/edge-smoke-tests.sh
```

## 4. القيود / Blockers

- ⚠️ **اختبار HTTP حي كامل:** خدمة `edge_runtime` المساعدة لم تكن فعّالة في هذه الجلسة (بيئة Docker بعد إعادة
  تشغيل)، لذا لم تُنفَّذ نداءات curl الحية لكل مسار (Happy/Unauthorized 401/Replay). الوضع الأمني والتحقق الداخلي
  مؤكَّدان من المصدر؛ يُستكمل الإثبات الحي end-to-end على Staging مع الأسرار الحقيقية.
- المطلوب لفكّ الحظر: `supabase functions serve` فعّالة + الأسرار (`CRON_SECRET`, `WEBAUTHN_RP_ID`,
  `ALLOWED_ORIGINS`, `LOGIN_HASH_PEPPER` ...) — تُضبط على Staging عبر Supabase Secrets، لا في Git.

**النتيجة:** ✅ لا دالة تعتمد على `verify_jwt=false` كإذن ضمني؛ كل دالة تفرض تخويلها داخليًا. الإثبات الحي
الكامل مُجدوَل ضمن مرحلة Staging.
