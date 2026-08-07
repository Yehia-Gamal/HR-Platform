# خطة إكمال مبادرة المراقبة (Observability)

## نظرة عامة
المشروع على فرع `feature/initiative-1-observability`. طبقة DB للمراقبة موجودة ومُنشَرة (`system_alerts`, `get_system_health()`, 4 `v_monitor_*` views, `cron_job_health`), و Sentry للويب موجود. لكن:
- **الـ logger المنظّم `_shared/logger.ts` غير مستخدم إطلاقاً** — كل 13 edge function تستخدم `console.error` خام
- **لا توجد لوحة مراقبة في الواجهة** — الـ RPCs والجداول موجودة لكن لا تستهلكها أي صفحة
- **`RouteErrorBoundary` لا يبلّغ Sentry**
- **لا health endpoint** في الـ edge functions
- **`VITE_SENTRY_DSN` غير موثّق** في `.env.example`

---

## المرحلة 1 — توصيل الـ logger المنظّم في كل edge functions (الأولوية القصوى)

### 1.1 إنشاء `_shared/withHandler.ts` — wrapper موحّد
ملف جديد في `supabase/functions/_shared/withHandler.ts`:
- ينشئ `createLogger({ functionName, version, requestId })` لكل طلب
- يولّد `requestId` من `x-request-id` header أو `crypto.randomUUID()`
- يلفّ `Deno.serve` handler بـ try/catch موحّد
- على الخطأ: `log.error("unhandled error", err, { ... })` ثم `json(req, { error: "INTERNAL_ERROR", request_id }, 500)`
- يضيف `x-request-id` header في الاستجابة
- يدعم `timed()` للأقسام الحرجة داخل الدالة
- يدعم `ENVIRONMENT` env var (يضبطه production افتراضياً)

### 1.2 توصيل الـ wrapper في 13 edge function
لكل دالة من الدوال التالية:
- استبدال `console.error(...)` بـ `log.error(...)` 
- استيراد `withHandler` و`createLogger`
- توليد requestId في بداية الـ handler وتمريره للاستجابات
- الحفاظ على الـ error codes الموجودة (لا تغيير في الـ API)

الدوال الـ 13:
1. `admin-create-employee` — 4 console.error calls (lines 215, 272, 301, 308, 360, 375)
2. `admin-resend-invite`
3. `admin-set-password`
4. `admin-update-email`
5. `identifier-sign-in`
6. `integration-outbox-worker`
7. `live-location-map-url`
8. `live-location-video-url`
9. `notification-dispatcher`
10. `passkey-register`
11. `retention-cleanup`
12. `scheduled-report-runner`
13. `verify-attendance-punch`
14. `webauthn-challenge`

## المرحلة 2 — لوحة المراقبة في الواجهة (admin web)

### 2.1 migration جديد: `0303_observability_permissions_seed.sql`
- إدراج `system.release.read` و `system.release.manage` و `observability.read` في `public.permissions`
- منحها لـ `admin` / `super-admin` roles عبر `role_permissions`

### 2.2 hook جديد: `features/observability/useSystemHealth.ts`
- `useSystemHealth()` — يستدعي `get_system_health()` RPC عبر `rpc()` helper الموجود
- يعيد JSON snapshot: `{ cron, integration_queue, notifications, errors, security, open_alerts }`
- polling كل 30 ثانية + زر تحديث يدوي

### 2.3 hook جديد: `features/observability/useSystemAlerts.ts`
- `useSystemAlerts()` — يقرأ `system_alerts` table مباشرة (RLS يسمح لـ full_access / system.release.read)
- `useAcknowledgeAlert()` — mutation لتحديث `status` إلى `acknowledged` (عبر RPC جديدة أو تحديث مباشر)

### 2.4 صفحة جديدة: `features/observability/ObservabilityDashboardPage.tsx`
تتكون من:
- **رأس الصفحة** (`PageHeader`): "لوحة مراقبة النظام" + زر تحديث + آخر تحديث
- **بطاقات الصحة الإجمالية**: 4 `MetricCard` للحالة (تنبيهات P0, P1, أخطاء آخر ساعة, أحداث أمنية حرجة)
- **قسم التنبيهات المفتوحة**: جدول/قائمة بكل `system_alerts` المفتوحة (severity, title, source, occurrences, last_seen_at) + زر تأكيد
- **قسم صحة Cron**: جدول `cron_job_health` (jobname, schedule, last_status, health_status, failures_24h) — ألوان حسب health_status
- **4 أقسام مراقبة** (من `get_system_health()`):
  - طابور التكامل (`v_monitor_integration_queue`): pending/failed/dead_letter/overdue
  - الإشعارات (`v_monitor_notifications`): queued/delivered/failed/stuck
  - الأخطاء (`v_monitor_errors`): errors/fatal/warnings last 1h
  - الأمان (`v_monitor_security`): high/critical last 1h

### 2.5 مسار + تنقّل
- في `App.tsx`: `<Route path="observability" element={<RequirePermission perm="system.release.read"><ObservabilityDashboardPage /></RequirePermission>} />` بعد `audit-security`
- في `WorkspaceShell.tsx`: إضافة `{ label: 'لوحة المراقبة', to: '/admin/observability', icon: Activity, permission: 'system.release.read' }` في قسم "الحوكمة والنظام"

## المرحلة 3 — إصلاحات سريعة عالية التأثير

### 3.1 `RouteErrorBoundary.tsx` — إبلاغ Sentry
- إضافة `import { captureError } from '../core/sentry';`
- في `componentDidCatch`: `captureError(error, { componentStack: info.componentStack, boundary: 'RouteErrorBoundary', errorId: this.state.errorId });`

### 3.2 `.env.example` — توثيق `VITE_SENTRY_DSN`
- إضافة سطر: `# Sentry DSN (public) — يُفعّل رصد الأخطاء. اتركه فارغًا للتعطيل.` + `VITE_SENTRY_DSN=`

### 3.3 إزالة `StatItem` غير المستخدم من `attendanceShared.tsx`
- بعد ترحيل `MonthlyStatementSection` لـ `QuickStat`، `StatItem` أصبح كود ميت

## المرحلة 4 — تشغيل الفحوصات
- `tsc -b` على admin_web
- اختبارات الحضور + Sentry + ErrorBoundary الموجودة
- التحقق من أن الـ edge functions لا تنكسر (Deno format check)

---

## الملفات المتأثرة

| الملف | التغيير |
|---|---|
| `supabase/functions/_shared/withHandler.ts` | **جديد** — wrapper موحّد |
| `supabase/functions/*/index.ts` (13 ملف) | توصيل logger + requestId |
| `supabase/migrations/0303_observability_permissions_seed.sql` | **جديد** — seed permissions |
| `apps/admin_web/src/features/observability/ObservabilityDashboardPage.tsx` | **جديد** — لوحة المراقبة |
| `apps/admin_web/src/features/observability/useSystemHealth.ts` | **جديد** — hook |
| `apps/admin_web/src/features/observability/useSystemAlerts.ts` | **جديد** — hook |
| `apps/admin_web/src/app/App.tsx` | إضافة route |
| `apps/admin_web/src/features/workspaces/WorkspaceShell.tsx` | إضافة nav item |
| `apps/admin_web/src/ui/RouteErrorBoundary.tsx` | إضافة captureError |
| `apps/admin_web/.env.example` | توثيق VITE_SENTRY_DSN |
| `apps/admin_web/src/features/attendance/attendanceShared.tsx` | إزالة StatItem الميت |

## ما لن نلمسه (خارج النطاق)
- Mobile crash reporting (يحتاج `firebase_crashlytics` dependency + Flutter init — نطاق منفصل)
- OpenTelemetry / distributed tracing (احتياج مبالغ فيه الآن)
- تغيير `[analytics]` config في `supabase/config.toml`