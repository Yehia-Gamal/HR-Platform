# المهمة 05 — لوحة Admin وHR والنوافذ المنبثقة

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

## مساحات العمل

### Main Admin

يفتح:

- Admin Workspace.
- HR Workspace.

### HR

- HR Workspace فقط.
- لا يرى Admin switch.
- `/admin/*` ممنوع UI + server + RLS.

## النوافذ المنبثقة

توحيد Modal System:

- Portal إلى `document.body`.
- `position: fixed; inset: 0`.
- center.
- z-index موحد.
- body scroll lock.
- focus trap.
- ESC.
- max-height 90dvh.
- internal scroll.
- responsive.

يشمل:

- إنشاء إدارة.
- إسناد دور.
- تعديل موظف.
- إنشاء منشور.
- إجازة رسمية.
- أي Dialog.

## صفحة الأدوار

- بطاقات عربية بدل 300 Checkbox.
- اسم ووصف وفئات وقدرات.
- لا إنشاء دور مخصص في Production.
- Slug في advanced read-only.

## صفحات HR

- موظفون.
- الهيكل.
- الحضور.
- كشف الشهر.
- الإجازات والتكليفات.
- الأجهزة.
- KPI HR.
- الجزاءات.
- الإجازات الرسمية.
- المنشورات.

## Error handling

- لا Zod/Supabase stack للمستخدم.
- Error mapper عربي.
- Correlation ID.
- Loading/Empty/Error/Forbidden منفصلة.

## اختبارات

- Modal من أعلى/أسفل الصفحة في المكان نفسه.
- Keyboard accessibility.
- HR Forbidden على Admin.
- Main Admin يبدل للمساحتين.
- Responsive/RTL.
- Visual regression.

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
