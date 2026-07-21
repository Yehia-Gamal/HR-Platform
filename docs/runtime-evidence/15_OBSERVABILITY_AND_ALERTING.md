# 15 — Observability & Alerting (P1.7)

**التاريخ / Date:** 2026-07-15
**الحالة / Status:** ✅ **DEPLOYED & VERIFIED LIVE على Staging** — طبقة مراقبة وتنبيهات DB-native تعمل آليًا.

---

## 1. ما بُني (Migration 0054 + Test 0033)

طبقة مراقبة داخل قاعدة البيانات (لا اعتماد على خدمة خارجية)، تبني على جداول الأحداث القائمة
(`app_error_events`, `security_events`, `integration_outbox`, `notification_delivery_log`) دون تكرارها:

| المكوّن | الوصف |
|---|---|
| جدول `system_alerts` | تنبيهات P0/P1 فقط، مع dedup عبر فهرس فريد جزئي `(alert_key) where status='open'` (تنبيه مفتوح واحد لكل مفتاح؛ التكرار يزيد `occurrences` بدل صف جديد) — يمنع Spam |
| RLS على `system_alerts` | قراءة/تحديث لـ `full_access` أو `system.release.read/manage` فقط؛ لا INSERT/DELETE مباشر (الكتابة عبر DEFINER) |
| 4 عروض مراقبة | `v_monitor_integration_queue` (dead-letter/overdue)، `v_monitor_notifications` (عالقة/فاشلة)، `v_monitor_errors` (error/fatal آخر ساعة)، `v_monitor_security` (high/critical آخر ساعة) — `security_invoker` + **REVOKE من anon/authenticated** (least-privilege) |
| `get_system_health()` | لقطة JSON واحدة (cron + queues + errors + security + open_alerts). `service_role`/`full_access`/`system.release.read` |
| `detect_and_raise_alerts()` | كاشف الشذوذ: dead-letter>0 (P0)، fatal>0 (P0)، أمني حرج (P0)، طابور متأخر>20 (P1)، أخطاء>50/ساعة (P1)، إشعارات عالقة (P1)، فشل cron (P1). `service_role` فقط |
| `resolve_stale_alerts()` | يُغلق التنبيهات المتعافية (لم تُرصَد منذ 30د) |
| جدولة pg_cron | `hr_monitor_alerts` كل 5د + `hr_monitor_resolve` كل 15د (حارس آمن محليًا) |

## 2. المراجعة الخصامية قبل النشر (Ultracode workflow)

شُغّل Workflow متعدد الوكلاء (3 عدسات: أمن/RLS، صحّة، idempotency/عمليات) + تحقق خصامي مستقل لكل نتيجة.
**النتيجة: 4 نتائج مؤكَّدة، صفر P0/P1، صفر مانع.** أُصلحت الثلاث القابلة للتنفيذ قبل الدفع:

| # | الخطورة | النتيجة | الإصلاح |
|---:|---|---|---|
| 1 | P3 | عروض المراقبة ورثت `SELECT` لـ anon/authenticated من default privileges في 0045 (غير مستغَلّة: `security_invoker` فوق RLS → صفر صفوف) | `revoke select ... from anon, authenticated` + `grant ... to service_role` |
| 2 | P2 | `WHEN OTHERS` في حلقة cron-failed يبتلع أخطاء الكتابة الحقيقية (يُخفي فشل التنبيه كنجاح) | حُصر إلى `insufficient_privilege or undefined_table` فقط |
| 3 | P3 | `WHEN OTHERS` في `get_system_health` يُخفي فشل استعلام cron كـ`[]` فارغ | حُصر + يُبرز `{"cron_error": ...}` بدل الإخفاء |
| 4 | P3 | (تحقق) لا مخاطر تشغيلية — المigration idempotent وآمن لإعادة التطبيق على Staging | لا إجراء (تأكيد) |

## 3. التحقق الحي (Local + Staging)

| الفحص | النتيجة |
|---|---|
| local `db reset` ×2 + `test db` ×2 | ✅ Files=33, Tests=367 PASS (شمل 0033) |
| `check:all` | ✅ exit 0 (55 migration متسلسلة) |
| Staging `db push` (0051–0055) | ✅ exit 0 — 0054 جدولت مهمتي المراقبة |
| Staging cron `hr_monitor_alerts` (*/5) | ✅ **succeeded \| 1 row** (تشغيل حي) |
| Staging cron `hr_monitor_resolve` (*/15) | ✅ active |
| Staging `get_system_health()` | ✅ يُرجع لقطة JSON كاملة (cron/errors/queue/security/alerts) |
| صحة النظام الحالية | ✅ 0 errors, 0 fatal, 0 dead-letter, **0 open alerts** (لا إيجابيات كاذبة) |

## 4. تغطية متطلبات P1.7

| المتطلب | التغطية |
|---|---|
| Structured logs | `app_error_events` (level/source/error_code/request_id/context/route/http_status) |
| Correlation IDs | `request_id` على الأخطاء؛ worker UUID في دوال Edge |
| Edge function failure | `detect_and_raise_alerts` يرصد فشل cron (يشمل استدعاءات Edge عبر pg_net) |
| DB slow queries | مؤجّل: يُغطّى عبر Supabase Dashboard (Reports → Query Performance) |
| Push delivery status | `v_monitor_notifications` (queued/delivered/failed/stuck) |
| Queue size / Dead-letter | `v_monitor_integration_queue` (pending/failed/dead_letter/overdue) + تنبيه P0 |
| Storage failures | جزئي: عبر `app_error_events(source='storage')` — تنبيه مخصّص لاحق |
| Alerts P0/P1 only دون Spam | `system_alerts` (P0/P1 فقط) + dedup عبر فهرس فريد جزئي |

## 5. المتبقي (تشغيلي/خارجي)

- توصيل `system_alerts` بقناة خارجية (Slack/Email/PagerDuty) — يتطلب مزوّد + سر webhook.
- Supabase Dashboard Reports (latency/slow queries) — مراقبة مُدارة جاهزة، تُفعّل من الواجهة.
- Flutter crash reporting (Sentry/Crashlytics) — يتطلب مشروع مزوّد.

## 6. الخلاصة

✅ **طبقة Observability كاملة منشورة ومُتحقَّق منها حيًّا على Staging**: كشف تنبيهات P0/P1 آلي كل 5 دقائق
مع dedup، لقطة صحة واحدة عبر RPC مؤمّن، و7 أنواع تنبيهات تغطي الطوابير والأخطاء والأمن وفشل cron.
مرّت مراجعة خصامية (4 نتائج، 0 مانع، أُصلحت الثلاث القابلة للتنفيذ). المتبقي (قناة تنبيه خارجية،
تقارير Dashboard، crash reporting) خارجي ويتطلب مزوّدين.
