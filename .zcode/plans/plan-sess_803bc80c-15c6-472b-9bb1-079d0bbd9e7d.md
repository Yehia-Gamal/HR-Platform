# خطة تطوير شاملة — تحسينات على كامل المشروع

## الأولوية 1: تطبيق الموبايل — صفحة التقارير اليومية العامة (مفقودة كلياً)
**المشكلة:** الموفّرات (providers) موجودة (`dailyReportsFeedProvider`, `toggleDailyReportLike`, `addDailyReportComment`) لكن **لا توجد صفحة UI** تستخدمها. المستخدمون لا يستطيعون رؤية أو التفاعل مع التقارير من الموبايل.

**الحل:** إنشاء `daily_reports_feed_page.dart` — صفحة فقاعات/بطاقات مع:
- صورة + اسم + مسمى + إدارة لكل تقرير
- محتوى ببارتفاع محدود + تمرير + زر توسيع
- أزرار إعجاب وتعليق
- ربطها في `WorkspaceScaffold._showMore` كخانة جديدة

**الملفات:**
- `apps/mobile_flutter/lib/features/mobile_pages/daily_reports_feed_page.dart` (جديد)
- `apps/mobile_flutter/lib/features/workspaces/workspace_scaffold.dart` (إضافة رابط)

---

## الأولوية 2: تطبيق الموبايل — توجيه إشعارات الميزات الجديدة
**المشكلة:** إشعارات الإعجاب/التعليق على التقارير وحضور/انصراف الموظفين تظهر لكن **غير قابلة للنقر** — لا يوجد routing لها.

**الحل:**
- إضافة cases في `resolveNotificationRoute` (`notification_handler.dart`) لأنواع: `daily_report`, `daily_report_like`, `daily_report_comment`, `attendance_manager_notify`
- إضافة في `hasSupportedAction` (`mobile_models.dart`) ليصبح النقر يفتح الصفحة المناسبة
- إضافة أيقونات مميزة في `mobile_notifications_page.dart`

**الملفات:**
- `apps/mobile_flutter/lib/core/notifications/notification_handler.dart`
- `apps/mobile_flutter/lib/features/mobile_data/mobile_models.dart`
- `apps/mobile_flutter/lib/features/mobile_pages/mobile_notifications_page.dart`

---

## الأولوية 3: لوحة الويب — تفعيل صفحات يتيمة + إصلاحات
**المشكلة:** صفحتان كاملتان منشأتان لكن غير مرتبطتين بأي route أو قائمة جانبية:
- `ExecutiveMonitoringPage.tsx` — مراقبة تنفيذية كاملة (خريطة + قائمة + فلاتر)
- `OrgChartPage.tsx` — هيكل تنظيمي شجري

**الحل:**
- إضافة routes في `App.tsx`: `/admin/executive-monitoring` و `/admin/org-chart`
- إضافة روابط في `WorkspaceShell.tsx` القائمة الجانبية
- إصلاح زر التعليقات في `DailyReportsFeedPage` (يفتح فقط ولا يغلق — toggle ناقص)

**الملفات:**
- `apps/admin_web/src/app/App.tsx`
- `apps/admin_web/src/features/workspaces/WorkspaceShell.tsx`
- `apps/admin_web/src/features/reports/DailyReportsFeedPage.tsx`

---

## الأولوية 4: لوحة الويب — تقديم تقرير يومي من الويب
**المشكلة:** التقارير اليومية تُرفع من الموبايل فقط — لا يوجد طريقة لرفع تقرير من لوحة الويب.

**الحل:** إضافة زر "تقرير جديد" في `DailyReportsFeedPage.tsx` يفتح نموذجاً (إنجازات/معوقات/خطة الغد) ثم يستدعي RPC `upsert_my_daily_report` الموجود.

**الملفات:**
- `apps/admin_web/src/features/reports/DailyReportsFeedPage.tsx` (إضافة نموذج)
- `apps/admin_web/src/features/reports/useDailyReportsFeed.ts` (إضافة mutation)

---

## الأولوية 5: تفعيل Lifecycle flag
**المشكلة:** صفحة Lifecycle كاملة ومنشورة لكن `featureFlags.ts: lifecycle = false` يخفيها من القائمة.

**الحل:** تفعيل `lifecycle: true` في `featureFlags.ts`.

**الملفات:**
- `apps/admin_web/src/ui/featureFlags.ts`

---

## الأولوية 6: نشر
- بناء ونشر لوحة الويب على Vercel
- flutter analyze للتحقق من كود الموبايل
- (تطبيق الموبايل يُبنى عبر CI عند الـ push)

---

## ترتيب التنفيذ
1. صفحة التقارير اليومية للموبايل (الأكبر والأهم)
2. توجيه الإشعارات للموبايل
3. تفعيل صفحات الويب اليتيمة + إصلاح toggle
4. نموذج تقديم تقرير من الويب
5. تفعيل lifecycle flag
6. نشر