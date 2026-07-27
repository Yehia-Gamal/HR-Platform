# المهمة 13 — UI/UX وRTL وTheme وOffline والأداء

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

## Design system

- Light/Dark/System.
- ألوان وهوية أحلى شباب.
- Typography.
- Cards/Buttons/Inputs.
- Empty/Error/Loading/Forbidden/Offline.
- Avatar.
- Dialog system بالتنسيق مع Agent 05.

## RTL

- العربية افتراضيًا.
- الأرقام/الهاتف/IDs LTR.
- لا نصوص خام أو Enums.
- responsive chips/tabs.
- دعم text scaling.

## Navigation

- Shell موحد لكل دور.
- SafeArea.
- لا محتوى خلف Bottom Bar.
- حفظ حالة Tabs.
- لا reload عند التبديل.
- إخفاء الصفحات الملغاة عبر Feature Flags.

## Screenshots

- إزالة `FLAG_SECURE` العام.
- لا شاشة سوداء.
- حماية انتقائية فقط بقرار مستقل.

## Offline

- الحفاظ على الجلسة.
- cache للقراءة.
- retry/backoff.
- لا نجاح حضور Offline.
- sync safe للعمليات المسموح بها.
- لا raw Socket/Supabase errors.

## الأداء

- Pagination.
- cancellation.
- no subscription leaks.
- indexes بالتنسيق مع DB.
- no N+1.
- image cache.
- startup/page timings.
- memory/rebuild profiling.

## اختبارات

- أحجام شاشات مختلفة.
- RTL/LTR fragments.
- Light/Dark.
- Accessibility.
- offline/reconnect.
- visual regression.
- لا spinner بلا نهاية.
- لا صفر كاذب.

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
