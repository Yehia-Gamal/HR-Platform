# إعداد Passkeys للحضور — متطلبات النشر

هذا المشروع يستخدم حزمة Flutter `passkeys` مباشرة، ولا يحتوي على جسر Android/iOS مخصص أو MethodChannel موازٍ.

## أسرار Edge Functions

اضبط القيم التالية عبر Supabase Secrets، ولا تضعها داخل Git:

- `WEBAUTHN_RP_ID`: النطاق المعتمد، مثل `app.example.org`.
- `WEBAUTHN_RP_NAME`: اسم المؤسسة الظاهر للمستخدم.
- `ALLOWED_ORIGINS`: قائمة Origins مفصولة بفواصل للويب والتطبيقات المسموحة.
  يجب أن تتضمن أصول Android (انظر أدناه) بالإضافة إلى نطاقات الويب.

## Android

### 1. assetlinks.json

استضف الملف التالي دون Redirect وبنوع `application/json`:

`https://<WEBAUTHN_RP_ID>/.well-known/assetlinks.json`

ويجب أن يحتوي على Package Name الفعلي وبصمات SHA-256 لجميع شهادات التوقيع المستخدمة، ومنها مفتاح Play App Signing عند النشر.

### 2. أصول Android في ALLOWED_ORIGINS

تطبيقات Android ترسل origin مختلف عن المتصفح عند WebAuthn. الصيغتان المحتملتان:

- **Credential Manager API** (Android 14+): `android:apk-key-hash-sha256:<base64url بدون حشو>`
- **FIDO2 API** (أقدم): `android:apk-key-hash:<base64 قياسي مع حشو>`

لحساب الأصل من بصمة SHA-256 (colon-hex من `keytool -list`):
1. حوّل البصمة من hex إلى bytes خام.
2. رمّز بـ base64url (بلا `=`) لصيغة Credential Manager.
3. رمّز بـ base64 قياسي (مع `=`) لصيغة FIDO2.

**مثال (Release)** — SHA-256 `0E:95:BD:EE:73:...`:
```
android:apk-key-hash-sha256:DpW97nOzEgf-6cEmOEtYjncayrADGQXto8AP_hNHXKY
android:apk-key-hash:DpW97nOzEgf+6cEmOEtYjncayrADGQXto8AP/hNHXKY=
```

يجب إضافة **كلتا الصيغتين** لكل شهادة (release + debug) في `ALLOWED_ORIGINS`.

> ⚠️ عدم إضافة هذه الأصول هو السبب الأساسي لرفض تسجيل البصمة على بعض أجهزة Android.

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
