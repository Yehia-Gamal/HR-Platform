# المهمة 15 — الدمج والتتبع والقبول النهائي

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

## الدور

أنت Integration Lead. لا تعيد تنفيذ المجالات؛ توحد العقود وتراجع الدمج.

## Merge order

1. Shared contracts/types.
2. Database migrations.
3. RLS/RPC/Edge.
4. Repositories/services.
5. State/application.
6. UI.
7. Tests.
8. Documentation.

## Merge Queue

لكل Branch:

- Task ID.
- owner/reviewer.
- dependencies.
- migration reservation.
- tests.
- evidence.
- rollback.
- conflicts.

## منع التعارض

- لا «take all changes».
- فهم الغرض.
- تشغيل الاختبارات بعد الحل.
- تحديث generated types.
- فحص duplicate routes/providers/models.
- فحص duplicate migrations.
- فحص Legacy references.

## Traceability

أنشئ جدولًا:

| Requirement | Source task | Root cause | Files | Migration | Tests | Evidence | Status |
|---|---|---|---|---|---|---|---|

الحالات:

- DISCOVERED.
- DESIGNED.
- IMPLEMENTED.
- TESTED.
- RUNTIME_VERIFIED.
- RELEASED.

لا تستخدم DONE العامة.

## Definition of Done

- كل متطلب له Owner ودليل.
- كل P0/P1 مغلق أو قرار قبول رسمي.
- الأرقام متطابقة بين الهاتف والويب والتقارير.
- RLS السلبية ناجحة.
- Release build ناجح.
- Rollback قابل للتنفيذ.
- المستند النهائي لا يحتوي تعارضًا أو Workflow قديمًا.

## التسليم النهائي

- Release readiness.
- Known limitations.
- Deferred P1/P2.
- Migration manifest.
- Security sign-off.
- QA sign-off.
- Product acceptance checklist.
- Rollback runbook.

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
