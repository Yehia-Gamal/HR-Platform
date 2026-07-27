# المهمة 11 — طلب الموقع وFCM وإشعارات Android

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

## الرحلة

```text
Executive tap
→ RPC
→ request row
→ outbox
→ dispatcher
→ FCM HTTP v1
→ Android service
→ full-screen/heads-up
→ fresh GPS
→ response
→ map/address/accuracy
```

## لا فيديو

احذف الاستخدام الجديد لـ:

- Camera.
- Microphone.
- Video.
- video_required/video_id.
- upload flow.

احتفظ بالتاريخ القديم بأمان.

## التتبع

- Request ID.
- Correlation ID.
- queued/sent/delivered/opened/responded.
- failure code.
- retry count.
- expiry.

## GPS بعد الإعدادات

على `AppLifecycleState.resumed`:

- فحص service/permission.
- مسح الخطأ.
- Fresh position.
- تفعيل الزر.
- نفس request ID.
- منع duplicate response.

## Android

- Channel جديدة مثل `urgent_location_v6`.
- High priority.
- صوت مخصص قوي.
- اهتزاز.
- Heads-up.
- Full-screen intent حيث يسمح.
- showWhenLocked/turnScreenOn.
- Native FirebaseMessagingService.
- Foreground service أثناء الطلب النشط فقط.
- اختبار Android 13/14/15.

## القيود

- لا ضمان لتجاوز DND.
- لا tracking خفي.
- لا overlay permission افتراضيًا.
- عند رفض الإشعارات: fallback داخل التطبيق وإظهار عدم جاهزية الجهاز للمدير.

## Outbox/Dedup

- Event ID فريد.
- Realtime لتحديث UI فقط.
- طلب نشط واحد حسب السياسة.
- Retry idempotent.

## اختبارات

- Foreground/background/terminated/locked.
- Token missing/expired.
- Dispatcher failure.
- GPS disabled then enabled.
- الصوت والقناة الجديدة.
- Full-screen fallback.
- لا duplicate.
- لا رسالة عامة بلا سبب.

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
