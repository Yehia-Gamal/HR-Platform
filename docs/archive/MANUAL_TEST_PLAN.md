# خطة الاختبار اليدوي — أحلى شباب HR V23

> المهام التي تتطلب بيئة شغّالة (Staging / Docker / أجهزة فعلية)
> Agent 13 — QA, Security, Load & Release

---

## المتطلبات الأولية

```bash
# 1. تشغيل Supabase محلياً
npx supabase start
npx supabase db reset      # يطبق كل الـ migrations

# 2. تشغيل تطبيق الويب
npm run dev:web

# 3. بيانات الاختبار
# استخدم الحسابات في staging-test-accounts.md
# أو أنشئ حسابات محلية عبر provision_employee_record
```

---

## ١. اختبارات الأمان (Security)

### ١.١ IDOR — الوصول غير المصرح عبر معرفات مباشرة

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | سجّل دخول كموظف عادي | نجاح |  |
| 2 | احصل على JWT من DevTools → Application → Local Storage | JWT ظاهر |  |
| 3 | استبدل `employee_id` في RPC بـ UUID موظف آخر: | |  |
|   | `curl -X POST $URL/rest/v1/rpc/get_employee_monthly_attendance_statement -H "Authorization: Bearer $JWT" -d '{"p_employee_id":"<other-uuid>"}'` | 403 أو بيانات فارغة — لا تسريب |  |
| 4 | جرّب نفس الشيء مع: `get_live_location_response`, `get_employee_profile` | 403 لكل منها |  |
| 5 | جرّب إنشاء طلب موقع كموظف عادي (بدون صلاحية): | |  |
|   | `rpc/create_location_request` | 403 — permission denied |  |

### ١.٢ Modified APK — تعديل تطبيق الموبايل

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | فكّ APK بـ `apktool d app.apk` | يفكّ بنجاح |  |
| 2 | عدّل `AndroidManifest.xml` — غيّر `package` name | |  |
| 3 | أعد البناء `apktool b` + وقّع بمفتاح مختلف | |  |
| 4 | ثبّت وحاول تسجيل الدخول | **فشل** — signature mismatch |  |
| 5 | تحقق أن Supabase لا يقبل طلبات من APK معدّل | الخادم يرفض |  |

### ١.٣ Spoofed Location — تزييف الموقع

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | فعّل Mock Location على جهاز Android | |  |
| 2 | استخدم Fake GPS (مثل Lockito) | |  |
| 3 | سجّل حضور بموقع مزيّف | |  |
| 4 | تحقق من `isMock` في `attendance_events` | `isMock = true` |  |
| 5 | تحقق من `live_location_points.is_mock` | `is_mock = true` |  |
| 6 | تحقق أن النظام يُعلم عن المواقع المزيفة | إشعار أمني |  |

### ١.٤ CSP / CORS

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | افتح DevTools → Network → تحقق من headers: | |  |
|   | `Content-Security-Policy` | موجود ومقيّد |  |
|   | `X-Frame-Options` | `DENY` أو `SAMEORIGIN` |  |
|   | `Strict-Transport-Security` | موجود |  |
| 2 | من موقع خارجي، أرسل `fetch('$SUPABASE_URL/rest/v1/...')` | CORS يمنع |  |
| 3 | تحقق من Vercel headers في `vercel.json` | headers أمنية مضافة |  |

### ١.٥ Service Role Exposure

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | `grep -r "service_role" apps/ packages/` | **صفر نتائج** في كود العميل |  |
| 2 | `grep -r "supabase_admin" apps/ packages/` | صفر |  |
| 3 | تحقق من Edge Functions: | |  |
|   | `grep -r "service_role" supabase/functions/` | موجود فقط في `_shared/` server-side |  |
| 4 | تحقق أن `SUPABASE_SERVICE_ROLE_KEY` ليس في أي ملف عام | لا يظهر |  |

### ١.٦ Break-glass Expiry

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | منح صلاحية break-glass مؤقتة (إن وُجدت) | |  |
| 2 | انتظر انتهاء المدة | |  |
| 3 | حاول استخدام الصلاحية بعد الانتهاء | **مرفوض** |  |
| 4 | تحقق من `audit_events` — تسجيل الانتهاء | مسجّل |  |

### ١.٧ Audit Completeness

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | نفّذ عمليات حساسة: تعيين دور، حذف، تعديل | |  |
| 2 | `SELECT * FROM audit_events ORDER BY created_at DESC LIMIT 20` | كل عملية مسجلة |  |
| 3 | تحقق أن كل سجل يحتوي: `actor_id`, `action`, `target_id`, `ip`, `timestamp` | حقول كاملة |  |
| 4 | تحقق أن محاولات الدخول الفاشلة مسجلة في `login_auth_attempts` | مسجلة |  |

---

## ٢. اختبارات الحمل على Staging

### ٢.١ التنفيذ

```bash
# تأكد من تثبيت k6
k6 version

# متغيرات البيئة
export BASE_URL=https://ujzzvqsodyhnnnpkoaml.supabase.co
export ANON_KEY=<from-supabase-dashboard>
export AUTH_TOKEN=<jwt-from-login>
export ADMIN_TOKEN=<admin-jwt>
export READER_TOKEN=<employee-jwt>
export MANAGER_TOKEN=<manager-jwt>
export EXEC_TOKEN=<executive-jwt>
export EMPLOYEE_TOKEN=<employee-jwt>

# تشغيل كل سيناريو
k6 run tests/load/attendance-punch.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env AUTH_TOKEN=$AUTH_TOKEN
k6 run tests/load/attendance-concurrent.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env AUTH_TOKEN=$AUTH_TOKEN
k6 run tests/load/auth-login.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY
k6 run tests/load/monthly-report.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env AUTH_TOKEN=$AUTH_TOKEN
k6 run tests/load/reports-heavy-rpcs.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env AUTH_TOKEN=$AUTH_TOKEN
k6 run tests/load/broadcast-post.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env ADMIN_TOKEN=$ADMIN_TOKEN --env READER_TOKEN=$READER_TOKEN
k6 run tests/load/location-concurrent.js --env BASE_URL=$BASE_URL --env ANON_KEY=$ANON_KEY --env MANAGER_TOKEN=$MANAGER_TOKEN --env EXEC_TOKEN=$EXEC_TOKEN --env EMPLOYEE_TOKEN=$EMPLOYEE_TOKEN
```

### ٢.٢ قائمة الفحص أثناء الحمل

| # | البند | كيفية القياس | الحد | ✅/❌ |
|---|-------|-------------|------|------|
| 1 | DB connections/pool | Supabase Dashboard → Database → Connections | < 80% من الحد |  |
| 2 | Edge Function latency | Supabase Dashboard → Edge Functions → Invocations | p95 < 3s |  |
| 3 | Deadlocks | `SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock'` | صفر deadlocks |  |
| 4 | Duplicate punch | بعد اختبار الحضور: `SELECT employee_id, event_type, COUNT(*) FROM attendance_events GROUP BY 1,2 HAVING COUNT(*) > 1` | لا تكرار غير متوقع |  |
| 5 | Lost outbox events | `SELECT COUNT(*) FROM notification_outbox WHERE status = 'pending' AND created_at < NOW() - INTERVAL '5 min'` | صفر عالق |  |
| 6 | Permission regressions | مراجعة k6 output: `http_req_failed` rate | < 5% |  |
| 7 | Memory usage | Supabase Dashboard → Infrastructure | < 80% |  |
| 8 | Response size | k6 metrics: avg response body size | < 500KB لأي RPC |  |

---

## ٣. مصفوفة أجهزة Android

### ٣.١ الأجهزة المطلوبة

| # | الجهاز | إصدار Android | ملاحظات |
|---|--------|--------------|---------|
| 1 | Samsung Galaxy A14/A34 | Android 13 | الأكثر انتشاراً |
| 2 | Samsung Galaxy S23/S24 | Android 14 | flagship |
| 3 | Xiaomi Redmi Note 12/13 | Android 13/14 | شركة ثانية |
| 4 | أي جهاز يدعم Android 15 | Android 15 | أحدث إصدار |

### ٣.٢ سيناريوهات الاختبار لكل جهاز

| # | السيناريو | الخطوات | المتوقع | ✅/❌ |
|---|-----------|---------|---------|------|
| 1 | **بصمة — تسجيل حضور** | فتح التطبيق → تسجيل حضور بالبصمة | نجاح + إشعار |  |
| 2 | **بلا بصمة — تسجيل حضور** | تعطيل البصمة → محاولة تسجيل | fallback إلى رمز PIN أو يرفض |  |
| 3 | **GPS off — طلب موقع** | تعطيل GPS → فتح التطبيق → طلب موقع | رسالة خطأ واضحة |  |
| 4 | **GPS on — تسجيل موقع** | GPS مفعّل → تسجيل حضور | إحداثيات صحيحة |  |
| 5 | **إشعارات مرفوضة** | رفض إذن الإشعارات → طلب موقع وارد | التطبيق يعمل بدون crash |  |
| 6 | **إشعارات مسموحة** | قبول إذن الإشعارات → طلب موقع وارد | إشعار FCM يظهر |  |
| 7 | **Foreground** | التطبيق مفتوح → طلب موقع | overlay يظهر فوراً |  |
| 8 | **Background** | التطبيق في الخلفية → طلب موقع | إشعار يظهر + فتح overlay |  |
| 9 | **Terminated** | التطبيق مغلق تماماً → طلب موقع | إشعار FCM → فتح التطبيق → overlay |  |
| 10 | **Locked screen** | الشاشة مقفلة → طلب موقع | إشعار على شاشة القفل |  |
| 11 | **RTL layout** | فتح كل الشاشات | كل النصوص RTL، لا انقلاب |  |
| 12 | **Offline → Online** | فتح بدون إنترنت → إعادة الاتصال | رسالة واضحة + sync بعد الاتصال |  |

---

## ٤. pgTAP على Supabase محلي

```bash
# تأكد من تشغيل Docker
docker version

# تشغيل Supabase محلياً
npx supabase start
npx supabase db reset

# تشغيل كل اختبارات pgTAP
npx supabase test db

# التحقق من نتائج 0062
npx supabase test db --filter 0062
```

### ٤.١ الاختبارات المتوقعة

| ملف | عدد الـ assertions | الوصف |
|-----|-------------------|-------|
| `0062_security_negative_tests.sql` | 22 | RLS, SECURITY DEFINER, privileges, constraints |
| + 48 ملف موجود | ~650 | كل اختبارات pgTAP الموجودة |

---

## ٥. Migration / Rollback

### ٥.١ اختبار التطبيق الأمامي

```bash
# تطبيق كل الـ migrations
npx supabase db reset

# تحقق من عدد الـ migrations
ls supabase/migrations/ | wc -l

# تحقق من عدم وجود تكرار
ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
# المتوقع: لا مخرجات
```

### ٥.٢ اختبار الـ Rollback

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | `npx supabase db reset` — تطبيق كل migrations | نجاح بدون أخطاء |  |
| 2 | تحقق من وجود كل الجداول والدوال المتوقعة | موجودة |  |
| 3 | شغّل `npx supabase test db` | كل الاختبارات تنجح |  |
| 4 | أنشئ بيانات تجريبية (موظف + حضور + طلب) | نجاح |  |
| 5 | تحقق من سلامة البيانات بعد الـ migrations | سليمة |  |

---

## ٦. Staging Soak / Monitoring

### ٦.١ خطة الـ Soak Test

| المرحلة | المدة | الحمل | المراقبة |
|---------|-------|-------|---------|
| Warm-up | 10 دقائق | 10 VUs | Supabase Dashboard |
| Sustained | 30 دقيقة | 30 VUs | DB connections + Edge latency |
| Peak | 10 دقائق | 50 VUs | Memory + CPU |
| Cool-down | 10 دقائق | 5 VUs | Error rates + recovery |

### ٦.٢ المراقبة أثناء الـ Soak

```bash
# مراقبة كل 5 دقائق
# 1. Supabase Dashboard → Database → Active connections
# 2. Supabase Dashboard → Edge Functions → Error rate
# 3. Supabase Dashboard → Storage → Usage
# 4. Vercel Dashboard → Functions → Errors

# استعلامات مراقبة مباشرة
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
psql $DATABASE_URL -c "SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock'"
psql $DATABASE_URL -c "SELECT relname, n_dead_tup FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY n_dead_tup DESC LIMIT 5"
```

---

## ٧. Backup / Rollback Verified

| # | الخطوة | المتوقع | ✅/❌ |
|---|--------|---------|------|
| 1 | `npx supabase db dump -f backup.sql` | ملف backup كامل |  |
| 2 | `npx supabase db reset` ثم `psql < backup.sql` | استعادة ناجحة |  |
| 3 | تحقق من عدد السجلات قبل وبعد | متطابق |  |
| 4 | وثّق حجم الـ backup ووقت الاستعادة | |  |

---

## ٨. Release Readiness Checklist

| # | البند | الحالة | ملاحظات |
|---|-------|--------|---------|
| 1 | صفر P0 من Release Gate | ☐ | `npm run release-gate` |
| 2 | صفر P1 غير معتمد | ☐ | `npm run release-gate --strict` |
| 3 | Build release (web) | ☐ | `npm run build` |
| 4 | Signed APK/AAB | ☐ | `flutter build apk --release` |
| 5 | Migrations verified | ☐ | `npx supabase db reset` + `test db` |
| 6 | Staging soak passed | ☐ | 30+ دقيقة بدون أخطاء |
| 7 | Backup/rollback tested | ☐ | dump + restore + verify |
| 8 | Android matrix (4 أجهزة) | ☐ | كل السيناريوهات أعلاه |
| 9 | Security checklist | ☐ | IDOR + CSP + audit |
| 10 | Load test thresholds | ☐ | كل k6 scripts تمر |

---

## ملاحظات

- **لا تستخدم بيانات حقيقية** في اختبارات الحمل — استخدم بيانات تجريبية فقط.
- **احذف بيانات اختبار الحمل** بعد الانتهاء من staging.
- **وثّق كل نتيجة** في هذا الملف (✅ أو ❌ مع السبب).
- **أي ❌ في الأمان** = P0 blocker — لا يُطلق حتى يُصلح.
