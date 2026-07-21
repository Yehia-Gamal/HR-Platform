# إعداد Passkeys للحضور — متطلبات النشر

هذا المشروع يستخدم حزمة Flutter `passkeys` مباشرة، ولا يحتوي على جسر Android/iOS مخصص أو MethodChannel موازٍ.

## أسرار Edge Functions

اضبط القيم التالية عبر Supabase Secrets، ولا تضعها داخل Git:

- `WEBAUTHN_RP_ID`: النطاق المعتمد، مثل `app.example.org`.
- `WEBAUTHN_RP_NAME`: اسم المؤسسة الظاهر للمستخدم.
- `ALLOWED_ORIGINS`: قائمة Origins مفصولة بفواصل للويب والتطبيقات المسموحة.

## Android

استضف الملف التالي دون Redirect وبنوع `application/json`:

`https://<WEBAUTHN_RP_ID>/.well-known/assetlinks.json`

ويجب أن يحتوي على Package Name الفعلي وبصمات SHA-256 لجميع شهادات التوقيع المستخدمة، ومنها مفتاح Play App Signing عند النشر.

## iOS

استضف:

`https://<WEBAUTHN_RP_ID>/.well-known/apple-app-site-association`

وأضف Associated Domain التالي إلى Runner:

`webcredentials:<WEBAUTHN_RP_ID>`

## بوابة الإطلاق

لا تُفعّل الحضور عبر Passkey في Production قبل نجاح:

1. التسجيل على جهاز Android حقيقي وجهاز iOS حقيقي.
2. الحضور والانصراف مع Challenge جديد لكل عملية.
3. رفض Challenge مستخدم أو منتهي.
4. رفض Origin/RP ID غير مطابق.
5. اختبار Counter وReplay Detection.
6. اختبار نطاق GPS ودقة الموقع.
