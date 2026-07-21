# 07 — Flutter Analyze / Test / Build (P0.7)

**التاريخ / Date:** 2026-07-14
**البيئة / Environment:** Windows 10 Pro 19045, Flutter 3.32.8 (stable), Dart 3.8.1
**JDK للبناء:** Android Studio JBR OpenJDK 21.0.6 (مضبوط عبر `flutter config --jdk-dir`)
**الحالة / Status:** ✅ Analyze نظيف (0 مشاكل) + Test 20/20 ناجح + **Debug APK مبني بنجاح (Exit 0)** — انظر القسم 4

> **إصلاح بيئي (2026-07-14):** كان `JAVA_HOME` يشير إلى `jdk-24.0.2`، فتعطّل تحقّق Flutter من إصدار Java
> (`Could not determine java version`) وانهار خادم تحليل Dart (`analysis server exited with code -1073740791`).
> الإصلاح: `flutter config --jdk-dir="C:\Program Files\Android\Android Studio\jbr"` (JBR 21)، فعاد analyze/test للعمل.
> كما أُصلح lint حقيقي واحد في الكود (انظر القسم 2).

---

## 1. Bootstrap (flutter create + configure + pub get)

مشروع Flutter مصدري فقط (بدون مجلدات المنصات). جرى تنفيذ سكربت الإقلاع كما تحدده الخطة:

```bash
cd apps/mobile_flutter
flutter create . --project-name ahla_shabab_management_os --org org.ahlashabab --platforms android,ios
python ../../scripts/configure_flutter_platforms.py
flutter pub get
```

النتائج:
- ✅ أُنشئ مجلدا `android` و`ios`.
- ✅ Package name / namespace: `org.ahlashabab.ahla_shabab_management_os` (صحيح، لم يُغيَّر).
- ✅ `minSdk = 24` (طبّقه سكربت configure).
- ✅ أذونات AndroidManifest المضافة تلقائيًا: `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `CAMERA`, `RECORD_AUDIO`.
- ✅ Deep-link intent-filter: `android:scheme="ahlashabab" android:host="action"`.
- ✅ iOS Info.plist: أوصاف استخدام الموقع/الكاميرا/الميكروفون + `CFBundleURLTypes` لـ scheme `ahlashabab`.
- ✅ `flutter pub get` → `Got dependencies!` (Exit 0).

> ملاحظة: عند أول محاولة تحليل ظهر خطأ عابر في pub cache
> (`Could not find a file named "pubspec.yaml" in ...analyzer-7.7.1`).
> السبب الحقيقي: سباق مع `pub get` الذي لم يكن قد أنهى الكتابة للكاش بعد. الإصلاح: إعادة `flutter pub get`
> حتى `Got dependencies!` ثم إعادة `flutter analyze`. لم يكن خطأً في كود المشروع.

## 2. flutter analyze

المحاولة الأولى (بعد إصلاح JDK) كشفت lint حقيقيًا واحدًا:
```
warning - The '!' will have no effect because the receiver can't be null
  - lib\features\mobile_pages\executive_people_page.dart:240:64 - unnecessary_non_null_assertion
```
**الإصلاح:** إزالة التأكيد الفائض `value!` → `value` بعد فحص `value != null` (ترقية عدم القابلية للـ null تلقائية في Dart).

بعد الإصلاح:
```
Analyzing mobile_flutter...
No issues found! (ran in 11.8s)
```
**Exit Code: 0** — ✅ صفر مشاكل تحليل (lints/errors).

## 3. flutter test

```
00:09 +20: All tests passed!
```
**Exit Code: 0** — ✅ **20/20 اختبار ناجح**، منها اختبارات أمنية مهمة:
- `access_context_test`: **executive context disables self attendance** (المدير التنفيذي لا يسجّل حضورًا شخصيًا).
- `attendance_security_models_test`: تحليل حقول التحقق الخادمي وبيانات إلغاء/نسخ Passkey.
- `mobile_models_test`: الحفاظ على UUID كامل بعد حل action id، تحليل نماذج KPI/الطلبات/المهام.
- `mobile_operations_models_test`: عمليات المدير ومركز قيادة المدير التنفيذي.
- `widget_test`: عرض أخطاء الإعداد بالعربية.

الملفات (test/): `access_context_test.dart`, `attendance_security_models_test.dart`,
`mobile_models_test.dart`, `mobile_operations_models_test.dart`, `widget_test.dart`.

## 4. flutter build apk --debug

```bash
flutter build apk --debug \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_ANON_KEY> \
  --dart-define=APP_ENVIRONMENT=development
```

**النتيجة النهائية:** ✅ **Exit 0 — Debug APK مبني بنجاح** (`_flutter_build3.log`).

```
√ Built build\app\outputs\flutter-apk\app-debug.apk
BUILD3_EXIT=0
```

- **الملف:** `apps/mobile_flutter/build/app/outputs/flutter-apk/app-debug.apk` (~213 MB).
- **JDK المستخدم للبناء:** Android Studio JBR OpenJDK 21، متجاوزًا Java 1.8 النظامي غير الكافي.

**عقبة عابرة تم حلّها (ليست خطأ في كود المشروع):**
المحاولات الأولى فشلت بـ `Error resolving plugin dev.flutter.flutter-plugin-loader` /
`Could not read workspace metadata from ...\.gradle\caches\8.12\transforms\...\metadata.bin`،
بسبب **تلف في Gradle transforms cache** (نتج عن مسح جزئي للكاش أثناء تشغيل daemon نشط →
"Device or resource busy"). السبب الجذري: محاولة مسح الكاش بينما daemon يحتجز الملفات.

**الإصلاح الصحيح المُطبَّق (أوقف الـ daemon أولًا ثم امسح ثم أعد البناء):**

```bash
cd apps/mobile_flutter/android && ./gradlew --stop      # أوقف 2 daemon
rm -rf "$USERPROFILE/.gradle/caches/8.12/transforms"    # امسح الكاش التالف (لا daemon يحتجزه الآن)
cd .. && flutter build apk --debug \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<LOCAL_ANON_KEY> \
  --dart-define=APP_ENVIRONMENT=development
# → √ Built app-debug.apk (Exit 0)
```

> درس: لا تمسح `caches\8.12\transforms` بينما daemon نشط. استخدم `gradlew --stop` أولًا دائمًا.
> الـ Gradle يستخدم JBR 21 من Android Studio تلقائيًا، متجاوزًا Java 1.8 النظامي غير الكافي.

**تحذيرات بناء أُصلحت بعد نجاح البناء (لضمان نظافة الأبنية القادمة):**
- `flutter_secure_storage` يتطلب compileSdk 36 (كان 35 من `flutter.compileSdkVersion`) →
  ثُبِّت `compileSdk = 36` في `android/app/build.gradle.kts` **وفي** `scripts/configure_flutter_platforms.py`
  (حتى يبقى الإصلاح بعد أي `flutter create` مستقبلي). `targetSdk` لم يتغير.
- NDK كان مثبتًا مسبقًا على `27.0.12077973` (مطلوب لـ passkeys/camera/geolocator).

## 5. iOS build — BLOCKED

- ⛔ **BLOCKED:** بناء وتوقيع iOS يتطلب macOS + Xcode، وهما غير متوفرين في بيئة Windows الحالية.
- المطلوب لفكّ الحظر: جهاز macOS مع Xcode، ثم `flutter build ios` / `flutter build ipa`.
- مُوثَّق أيضًا في `09_IOS_DEVICE_QA.md`.

## 6. إعادة الاختبار / Re-run

```bash
cd apps/mobile_flutter
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<KEY> --dart-define=APP_ENVIRONMENT=development
```
