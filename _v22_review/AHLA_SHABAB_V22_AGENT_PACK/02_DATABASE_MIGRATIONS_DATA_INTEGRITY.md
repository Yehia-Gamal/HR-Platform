# المهمة 02 — قاعدة البيانات والـMigrations وسلامة البيانات

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

## الملكية الأساسية

- `supabase/migrations/**`
- Schema contracts.
- Backfill scripts.
- Verification queries.
- Data integrity reports.

أي وكيل آخر يحتاج Migration يحجزها عبرك أو Orchestrator.

## الأهداف

- توحيد مصادر الحقيقة.
- منع الجداول/الأعمدة المكررة.
- إصلاح FKs/constraints/indexes.
- دعم Primary وSecondary Assignments.
- دعم Work Sites وGeofence settings.
- دعم Attendance day state/corrections.
- دعم الإجازات والتكليفات منفصلة.
- دعم KPI parallel states.
- دعم complaints/admin actions.
- دعم posts/polls/read receipts.
- دعم location request timeline/outbox.

## قواعد الـMigration

- Timestamp UTC كامل.
- لا تعديل Migration منشورة.
- Dry Run.
- عدد سجلات قبل/بعد.
- Verification.
- Rollback notes.
- Generated types بعد كل تغيير.
- لا DROP قبل Compatibility period.

## سلامة البيانات

افحص وأصلح:

- Auth users بلا employee.
- Employees بلا active assignment.
- مدير لنفسه.
- Reporting cycle.
- موظفون مكررون.
- أجهزة نشطة متعددة.
- KPI للمدير التنفيذي.
- طلبات بلا صاحب/مسؤول.
- قضايا منفذة بلا موافقة وتنفيذ.
- Attendance rows بعقود Boolean خاطئة.
- Work assignments مخصومة من رصيد الإجازة.

## الورديات

- `work_date` مستقل.
- `crosses_midnight`.
- نهاية الوردية + grace.
- Job idempotent.
- Retry/alerts/backfill.

## Work Site settings

- `attendance_radius_meters` افتراضي 300.
- `max_location_age_seconds` افتراضي 15.
- `max_accuracy_meters` افتراضي 100.
- قيود آمنة وAudit.

## الجداول المرجعية وUSING(true)

لا تفتح أي جدول تلقائيًا.
أرسل لكل جدول مرشح إلى وكيل الأمن:

- الحقول.
- الحساسية.
- الاستخدام.
- سبب القراءة العامة.
- البديل.

## المخرجات

- Schema before/after.
- ERD.
- Migration plan.
- Backfill report.
- Integrity report.
- Index/query-plan report.
- Rollback.

## اختبارات القبول

- Schema diff متوقع فقط.
- لا فقد سجلات.
- لا FK orphan.
- db reset/staging migration ناجحة.
- pgTAP/verification ناجحة.
- الورديات الليلية محسوبة صحيحًا.

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
