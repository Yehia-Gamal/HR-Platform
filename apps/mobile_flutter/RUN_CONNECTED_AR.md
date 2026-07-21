# تشغيل تطبيق Flutter متصلاً بالباك إند (Supabase)

يقرأ التطبيق إعدادات الاتصال من `--dart-define` أثناء البناء (لا يوجد `.env` داخل Dart).
لتبسيط ذلك أضفنا ملف إعدادات JSON يُمرَّر عبر `--dart-define-from-file`.

## الإعداد لمرة واحدة

الملف `dart_define/staging.json` موجود ومضبوط على نفس مشروع Supabase المستخدم في الويب
(بيئة staging). إذا لم يكن موجوداً على جهاز جديد، انسخ القالب:

```powershell
Copy-Item dart_define/staging.example.json dart_define/staging.json
```

ثم املأ القيم:

| المفتاح | الوصف |
|---|---|
| `SUPABASE_URL` | رابط مشروع Supabase (نفس قيمة الويب `VITE_SUPABASE_URL`). |
| `SUPABASE_PUBLISHABLE_KEY` | المفتاح العام (publishable/anon) — آمن للتطبيق، ليس service_role. |
| `APP_ENVIRONMENT` | `development` \| `staging` \| `production`. |
| `BYPASS_RELEASE_GATE` | اختياري؛ يتجاوز فحص بوابة الإصدار في غير الإنتاج فقط (للمعاينة على الويب دون باك إند حي). |

> `dart_define/staging.json` مستبعد من Git (يبقى محلياً فقط)، بينما `*.example.json` مُتتبَّع كقالب.

## التشغيل

على جهاز/محاكي:

```powershell
./run_staging.ps1
```

للمعاينة على متصفح:

```powershell
./run_staging.ps1 -d chrome
```

أو من VS Code: اختر تهيئة **Flutter (Staging)** ثم F5.

يدوياً:

```bash
flutter run --dart-define-from-file=dart_define/staging.json
```

## بناء APK للأجهزة

```powershell
./build_staging_apk.ps1
```

الناتج: `build/app/outputs/flutter-apk/app-release.apk`.

## ملاحظات حول الاتصال الكامل

- الويب (`apps/admin_web`) والموبايل يشيران الآن إلى **نفس** مشروع Supabase، فتظهر
  نفس البيانات في الطرفين بعد تسجيل الدخول بنفس الحساب.
- لكي تعمل الشاشات ببيانات حقيقية يجب أن تكون قاعدة البيانات مُهيّأة على المشروع:
  تشغيل الـ migrations في `supabase/migrations`، ونشر الـ Edge Functions، وضبط
  سياسات التخزين. هذه خطوات على الخادم (Supabase CLI / لوحة التحكم) وليست تعديلات كود.
- إذا كان المشروع غير مُهيّأ بعد، سيتصل التطبيق لكن قد تعيد بعض الاستعلامات نتائج
  فارغة أو أخطاء صلاحيات (RLS) حتى يكتمل إعداد الباك إند.
