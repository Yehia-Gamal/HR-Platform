# المهمة 14 — QA والأمن واختبارات الحمل والإطلاق

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

## مسؤوليتك

التحقق المستقل، وليس إصلاح كل شيء بنفسك.

## الاختبارات

- Unit.
- Widget.
- Integration.
- E2E.
- RLS negative.
- RPC/pgTAP.
- Visual regression.
- Real Android devices.
- Load/performance.
- Security/abuse.
- Migration/rollback.

## الأدوار

- Employee.
- Direct Manager.
- Operations.
- Executive.
- HR.
- Main Admin.
- Committee Member.

## Load tests

على Staging:

- الذروة.
- 2×.
- 3× لفترة قصيرة.
- حضور متزامن.
- كشف الشهر.
- منشور للجميع.
- موقع متزامن ضمن الاستخدام.
- RLS query load.

افحص:

- DB connections/pool.
- Edge latency.
- deadlocks.
- duplicate punch.
- lost outbox event.
- permission regressions.

## Android matrix

- Samsung.
- شركة أخرى.
- Android 13/14/15.
- بصمة/بلا بصمة.
- GPS off/on.
- notifications denied.
- foreground/background/terminated/locked.

## Security

- IDOR.
- modified APK.
- spoofed location.
- rate limits.
- secrets.
- CSP/CORS.
- service role.
- break-glass expiry.
- audit completeness.

## Release Gate

- صفر P0.
- صفر P1 غير معتمد.
- Build release.
- signed APK/AAB.
- migrations verified.
- staging soak/monitoring.
- backup/rollback tested.
- release readiness report.

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
