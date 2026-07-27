# المهمة 01 — Discovery والمعمارية والجرد

## قواعد مشتركة ملزمة

- المرجع الوظيفي هو خطة V22 المختصرة والمحصنة، وهذه المهمة جزء منها وليست مشروعًا منفصلًا.
- العمل داخل المستودع الحالي ونفس Flutter/Web/Supabase/Firebase/Package Name/Keystore.
- ابدأ بـDiscovery داخل نطاقك قبل التعديل، ولا تفترض أسماء ملفات أو جداول أو دوال.
- لا تعدّل Migration منشورة، ولا تحذف بيانات Production، ولا تعطّل RLS.
- استخدم Migration جديدة باسم Timestamp UTC كامل بعد حجزها في سجل التنسيق.
- لا تعرض بيانات Demo أو نجاحًا وهميًا.
- لا تكتب «تم» دون Root Cause، Commit، Tests، Runtime Evidence، وRollback.
- لا تعدّل ملفات مملوكة لوكيل آخر دون موافقة Orchestrator وتحديث File Ownership Registry.
- كل واجهة جديدة يجب أن ترتبط بخادم فعلي وصلاحيات واختبارات.
- عند خطر فقد بيانات: أوقف الجزء الخطر فقط، سجله في BLOCKERS، واستمر في المهام المستقلة.
- سلّم تقريرًا ختاميًا يتضمن: قبل/بعد، الملفات، المايجريشن، الاختبارات، الصور، السجلات، القيود، وخطوات الرجوع.

## الهدف

إنتاج خريطة واقعية للمشروع قبل أي إعادة هيكلة أو إنشاء مكرر.

## نطاق الفحص

### Flutter

- Routes وShells وBottom Navigation.
- الصفحات والـWidgets.
- State management.
- Models/Repositories/Services.
- Supabase calls داخل UI.
- Notifications/Android channels.
- Legacy/duplicate/dead code.
- Theme/RTL/SafeArea.

### Web

- Admin وHR routes.
- Guards.
- Components/Dialogs.
- Supabase queries.
- Role/permission UI.
- Reports.
- Duplicate pages.

### Supabase

- Tables/columns/FKs/constraints/indexes.
- Enums/views/materialized views.
- RPCs/overloads/triggers.
- RLS policies.
- Storage buckets.
- Edge Functions وSecrets.
- pg_cron/jobs.

### Android/Firebase

- Manifest.
- FCM setup.
- Notification channels.
- Background handlers.
- FirebaseMessagingService.
- Biometrics/WebAuthn.
- Full-screen intent.
- `FLAG_SECURE`.
- Deep links.

## المخرجات

أنشئ:

- `CURRENT_ARCHITECTURE.md`
- `SCREEN_INVENTORY.md`
- `DATABASE_SCHEMA_INVENTORY.md`
- `RLS_RPC_EDGE_INVENTORY.md`
- `ROUTE_MAP.md`
- `LEGACY_DUPLICATION_REPORT.md`
- `DATA_INTEGRITY_BASELINE.md`
- `PERFORMANCE_BASELINE.md`
- `DEPENDENCY_GRAPH.md`
- `SHARED_CONTRACTS_DRAFT.md`

## ممنوع

- إعادة بناء واسعة قبل تسليم الجرد.
- حذف ملفات Legacy قبل إثبات عدم استخدامها Runtime.
- افتراض أن Migration موجودة تعني أن الوظيفة تعمل.

## اختبارات/أدلة

- Baseline Flutter analyze/test.
- Baseline web build/test.
- Baseline database tests.
- Screenshots للشاشات الحالية.
- قائمة أخطاء P0/P1 قابلة للتتبع.

## تقسيم وكلاء فرعيين مقترح

- Flutter inventory.
- Web inventory.
- Database/RLS inventory.
- Android/FCM inventory.
- Data/performance inventory.
- Reviewer لتوحيد النتائج.

## صيغة التسليم الإلزامية

1. **ملخص التنفيذ**
2. **الأسباب الجذرية**
3. **الملفات المعدلة**
4. **Migrations/RPC/RLS/Edge Functions**
5. **الاختبارات الناجحة والفاشلة**
6. **أدلة Runtime وصور قبل/بعد**
7. **المخاطر والقيود المتبقية**
8. **Commit hashes**
9. **تعليمات الدمج**
10. **Rollback**
