# BUILD MASTER — أحلى شباب Management OS V8
## نقطة الدخول التنفيذية المراجعة

> هذه الحزمة Backend Foundation مُراجعة، وليست النظام الكامل ولا دليلًا على نجاح التشغيل. لا تبدأ Flutter/React قبل اجتياز بوابة قاعدة البيانات والأمان فعليًا.

## 1. المصدر الوحيد للحقيقة
اقرأ بالترتيب:
1. `spec/00_START_HERE_V8_AR.md`
2. `spec/01_V8_SINGLE_SOURCE_OF_TRUTH_AR.md`
3. `audit/HR_PLATFORM_DEEP_AUDIT_AR.md`
4. `docs/IMPLEMENTATION_PLAN_AR.md`
5. `supabase/migrations/README.md`

## 2. المعمارية المعتمدة
- تطبيق Flutter واحد يفتح Workspaces حسب الصلاحية: Employee / Manager / Executive.
- React Web واحدة: HR Workspace + Main Admin Workspace.
- Supabase Backend واحد مع RLS + ABAC + RPCs + Edge Functions.
- المدير التنفيذي يستخدم Executive Workspace على الهاتف ولا يحتاج الويب في أعماله التشغيلية.
- HR لا يرى Main Admin Workspace إلا بصلاحيات مستقلة صريحة.

## 3. الحالة الفعلية
| الجزء | الحالة |
|---|---|
| migrations 0001–0011 | موجودة، تحتاج تشغيل واختبار فعلي |
| migration 0012 P0 hardening | مضافة، تحتاج db reset + pgTAP |
| Seed الصلاحيات | موجود، يحتاج مراجعة least-privilege بأدوار حقيقية |
| WebAuthn challenge | مضاف، يحتاج اختبار Browser/Device حقيقي |
| verify-attendance-punch | مُقوّى، يحتاج توافق passkey-register والمفتاح SPKI |
| pgTAP structural tests | مضافة كبداية |
| Persona RLS tests | غير مكتملة |
| Storage buckets/policies | غير مكتملة |
| Flutter | غير موجود |
| React | غير موجود |
| CI/CD | غير موجود |
| بقية Edge Functions | غير مكتملة |

## 4. بوابة قاعدة البيانات
نفّذ بعد تثبيت Supabase CLI:

```bash
cd HR_Platform_V8_Reviewed
supabase start
supabase db reset
supabase test db
supabase db reset
supabase test db
```

لا تعتبر البوابة ناجحة إلا إذا نجح البناء والاختبارات مرتين متتاليتين، ثم يتكرر على Staging.

## 5. شروط عدم البدء بالواجهات
لا تبدأ Flutter أو React عند وجود أي من التالي:
- Migration تفشل.
- Policy تسمح بوصول خارج Scope.
- Workflow ينتهي عند أول موافقة بدل الانتقال للمرحلة التالية.
- authenticated يستطيع إدراج attendance event مباشرة.
- Passkey يمكن تعديل حقولها الحساسة من العميل.
- اختبارات Employee/Manager/HR/Admin/Executive غير موجودة.

## 6. ملاحظات حاسمة
- مسار KPI المستهدف: Employee Self → Direct Manager → Executive Secretary → Executive Director. HR يضيف مدخلات موضوعية ولا يكون مرحلة اعتماد إلزامية، ما لم تعتمد المؤسسة Workflow مختلفًا بإصدار موثق.
- لا Chat داخليًا في الإصدار الأساسي؛ Official News & Decisions Feed فقط.
- Payroll خارج الإطلاق الأول ويحتاج اعتماد HR/Finance/Legal.
