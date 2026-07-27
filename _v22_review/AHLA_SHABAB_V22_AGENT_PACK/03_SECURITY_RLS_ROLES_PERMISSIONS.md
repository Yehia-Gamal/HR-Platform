# المهمة 03 — الأمن وRLS والأدوار والصلاحيات

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

## الأهداف

1. تحويل واجهة 300+ Permission إلى قوالب أدوار عربية.
2. فرض الصلاحيات Server-side.
3. ترحيل RLS تدريجيًا دون كسر.
4. حماية العمليات الحساسة.

## القوالب العربية

- السكرتير التنفيذي — Main Admin.
- مدير الموارد البشرية.
- المدير التنفيذي.
- مدير التشغيل.
- عضو لجنة حل المشكلات كCapability إضافية.
- المدير المباشر.
- الموظف.

## قواعد الإسناد

- Main Admin يمنح الأدوار العليا وعضوية اللجنة.
- HR يمنح Employee/Direct Manager/Operations ضمن نطاقه.
- HR لا ينشئ Admin/Executive/Executive Secretary.
- لا Permission منفردة للمستخدم.
- Slug التقني في وضع قراءة متقدم فقط.
- كل إسناد Audit.

## RLS

- Default Deny.
- لا قائمة ثابتة لـ`USING(true)`.
- إنشاء Allowlist موثقة للجداول المرجعية فقط.
- اختبار Anonymous/Authenticated.
- Negative tests لكل دور.
- `SECURITY DEFINER` مع `search_path`.
- منع IDOR وclient-supplied employee_id.

## الترحيل التدريجي

- إنشاء `has_scoped_permission()` واختبارها.
- Shadow evaluation.
- Domain واحد في كل مرة.
- Feature Flag.
- مقارنة النتائج.
- إزالة القديم بعد Staging verification فقط.

## Break-glass

- سبب.
- نطاق.
- مدة قصوى 60 دقيقة.
- انتهاء تلقائي.
- إشعار.
- Audit.
- موافقة ثانية للعمليات الحرجة عند الإمكان.

## Rate limiting

- إنشاء موظف.
- Role assignment.
- Login/reset.
- Device registration.
- Attendance.
- Location request.
- Publishing.

## Web security

- CSP.
- CORS allowlist.
- Referrer policy.
- frame-ancestors.
- no secrets in client.
- secure headers.

## اختبارات القبول

يجب أن تفشل:

- HR يفتح Admin.
- HR ينشئ Executive.
- موظف يقرأ تقييم غيره.
- مدير يرى فريقًا آخر.
- Operations يعتمد طلبه.
- غير Executive يطلب موقعًا.
- HR ينفذ جزاء غير معتمد.
- Anonymous يقرأ بيانات حساسة.

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
