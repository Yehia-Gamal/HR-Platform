# تقرير الفحص العميق — HR_Platform

## الحكم التنفيذي
الحزمة الحالية **ليست منصة مكتملة ولا Production-Ready**. هي أساس Backend يتكوّن من 11 migration وملفّي seed وEdge Function واحدة. لا يوجد Flutter أو React أو CI/CD أو اختبارات RLS تشغيلية داخل الملف الأصلي.

## ما هو موجود فعلاً
- 138 جدولًا مُعرّفًا في migrations.
- 46 دالة PostgreSQL.
- نحو 400 سياسة RLS بين سياسات صريحة وسياسات مولّدة ديناميكيًا.
- Edge Function واحدة: `verify-attendance-punch`.
- ملفات تخطيط وتنفيذ مختصرة.

## ملاحظات P0/P1 المكتشفة

### P0-01 — ادعاء الجاهزية غير مدعوم بالاختبارات
`BUILD_MASTER.md` يعلن أن قاعدة البيانات والصلاحيات والحضور جاهزة، بينما الحزمة الأصلية لا تحتوي `supabase/config.toml` ولا مجلد `supabase/tests/` ولا نتائج تشغيل `db reset` أو pgTAP. لا يجوز اعتماد حالة ✅ قبل تشغيلها مرتين على الأقل محليًا ثم على Staging.

### P0-02 — ABAC/Scopes غير مطبق فعليًا في سياسات RLS
تم إنشاء overload باسم `can_access_employee(employee_id, permission_code)`، لكن لا توجد أي Policy تستدعيه بالـpermission code. أغلب السياسات تستخدم `has_permission(...)` وحدها أو النسخة ذات المعامل الواحد؛ وبالتالي قد تتحول صلاحية بنطاق `direct_reports` أو `department` إلى وصول على مستوى المؤسسة.

### P0-03 — `management_descendants` يعامل كـdirect reports فقط
الدالة الحالية لا تنفذ traversal متكررًا لشجرة المديرين. أُضيف في migration 0012 تنفيذ recursive حقيقي.

### P0-04 — Workflow متعدد المراحل غير منفذ
`decide_request` في النسخة الأصلية يغلق كل الخطوات والـworkflow عند أول موافقة. هذا يلغي عمليًا المسار متعدد المراحل. أُعيد تعريفه في migration 0012 ليعالج الخطوة النشطة فقط ثم ينقل للخطوة التالية، ولا يغلق الطلب إلا بعد آخر خطوة.

### P0-05 — الكتابة المباشرة على بيانات Passkey
السياسات الأصلية تسمح للموظف بإدراج وتحديث `passkey_credentials` مباشرة. حتى مع trigger، هذا يوسع سطح الهجوم. migration 0012 يلغي الكتابة المباشرة ويجعل التسجيل/التعديل عبر Edge/RPC موثوق فقط.

### P0-06 — تحقق WebAuthn كان ناقصًا
الـEdge Function الأصلية:
- تبحث عن `credential_id` في عمود `id` بدل عمود `credential_id`.
- لا تتحقق من RP ID hash.
- لا تتحقق من User Presence/User Verification flags.
- لا تفحص أو تحدث sign counter.
- تستهلك challenge قبل التحقق من التوقيع.
- قد تعيد تفاصيل خطأ قاعدة البيانات للعميل.
تم استبدالها بنسخة أقوى، لكن يجب اختبارها مع طريقة تخزين المفتاح العام في `passkey-register`.

### P0-07 — تعارض KPI مع القرار الوظيفي الأخير
الخطة الأصلية تستخدم `self→manager→hr→secretary→executive`. القرار الأحدث هو أن HR يزوّد النظام ببيانات موضوعية ولا يكون مرحلة اعتماد إلزامية؛ المسار الرسمي: `self→manager→secretary→executive`. يجب تطبيق ذلك في migration لاحقة بعد اعتماد قواعد الرؤية والتعديل.

### P1-01 — الحزمة الأصلية ليست مكتفية ذاتيًا
`BUILD_MASTER.md` يشير إلى `../HR_UNIFIED_MASTER_PROMPT_AR.md` وهو غير موجود داخل ZIP. أُضيفت مواصفة V8 إلى مجلد `spec/` وأصبحت المرجع الأعلى.

### P1-02 — ترتيب التنفيذ في الخطة كان متعارضًا
الخطة تذكر 0004 employees قبل 0003 organization داخل R1، رغم اعتماد 0004 على 0003. يجب دائمًا تطبيق migrations رقميًا 0001→0012.

### P1-03 — لا يوجد تطبيق أو لوحة ويب
لا يوجد `apps/mobile_flutter` أو `apps/admin_web`. الحزمة Backend foundation فقط.

### P1-04 — لا توجد بقية Edge Functions
ما زال مطلوبًا: `passkey-register`, `admin-create-user`, `admin-update-user`, `resolve-login-identifier`, `process-request-sla`, push, backups وغيرها.

### P1-05 — لا توجد Storage migrations/policies كاملة
المواصفة تتطلب buckets خاصة للصور والمرفقات وفيديو الموقع والأدلة. يجب إنشاؤها بسياسات ومسارات وretention واضحة.

## ما تم إضافته في النسخة Reviewed
- `0012_core_p0_hardening.sql` لتقوية Scope وRLS وWorkflow وPasskey.
- نسخة أقوى من `verify-attendance-punch`.
- Edge Function لإصدار WebAuthn challenge.
- `supabase/config.toml` كبداية محلية.
- اختبارات pgTAP بنيوية أولية.
- مواصفة V8 واختباراتها وخارطة الطريق داخل `spec/`.
- README جديد يوضح أن الحزمة تحتاج تشغيلًا فعليًا قبل اعتمادها.

## حدود الفحص
لم يتم تشغيل PostgreSQL/Supabase داخل هذه الجلسة لعدم توفر Supabase CLI/PostgreSQL runtime في البيئة. الإصلاحات Static/Code Review ويجب التحقق منها عبر:
1. `supabase db reset` مرتين.
2. `supabase test db`.
3. اختبارات RLS بهويات Employee/Manager/HR/Admin/Executive.
4. اختبار WebAuthn على جهاز ومتصفح حقيقيين.
