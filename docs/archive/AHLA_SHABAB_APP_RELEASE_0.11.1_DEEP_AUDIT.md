# تقرير الفحص العميق لتطبيق أحلى شباب HR

## الملف المفحوص

- اسم الملف: `app-release.apk`
- Package: `org.ahlashabab.ahla_shabab_management_os`
- اسم التطبيق: `أحلى شباب HR`
- الإصدار: `0.11.1`
- Version Code: `12`
- الحجم: نحو `62 MB`
- Min SDK: `24` — Android 7
- Target SDK: `35` — Android 15
- Compile SDK: `36`
- SHA-1 الفعلي: `01b9910d12d1a86eefa6070042a930d5bc3b1769`
- SHA-256: `cdc5dd73bd0fc295a58599e4838a2fb6fa897bc99089580303ad96b3222e1176`
- ملف SHA-1 المرفق يطابق التطبيق بالفعل.

---

# 1. الحكم التنفيذي

## درجة الجاهزية الحالية

- سلامة الحزمة والتوقيع: **7.5/10**
- الأمان الثابت داخل APK: **6.5/10**
- جاهزية الحضور والبصمة: **2.5/10**
- جاهزية طلب الموقع والفيديو: **3/10**
- جاهزية الإشعارات خارج التطبيق: **2/10**
- جاهزية النظام ككل للاستخدام الفعلي: **4/10**

التطبيق مبني كنسخة Release فعلية ويحتوي على معظم الوحدات المطلوبة، لكن وجود الوحدة داخل الكود لا يعني أن رحلتها تعمل. أخطر العيوب الحالية في **معمارية الإشعار العاجل، استخدام Passkey بدل بصمة الحضور، تفعيل الصوت أثناء فيديو التحقق، وتعارض حالة الجهاز مع الخادم**.

لا أنصح بتوزيع هذه النسخة كنسخة تشغيل نهائية للموظفين قبل إغلاق مشكلات P0 واختبارها على أجهزة Samsung وAndroid حقيقية.

---

# 2. نطاق الفحص وحدوده

تم فحص:

- بنية APK وملفاته.
- AndroidManifest.
- التوقيع والشهادة.
- الصلاحيات.
- Activities وServices وReceivers وProviders.
- إعدادات الشبكة والنسخ الاحتياطي.
- مكتبات Flutter وAndroid.
- Native Libraries والـABI ومحاذاة 16KB.
- النصوص والمسارات والدوال المضمنة داخل Dart AOT.
- روابط Supabase وFirebase والخرائط.
- مؤشرات تنفيذ الحضور، Passkeys، KPI، الإشعارات، الموقع، الفيديو، الطلبات والخلافات.

لا يمكن من APK وحده إثبات:

- صحة RLS Policies.
- صلاحيات Supabase Storage.
- كود Edge Functions الفعلي.
- هل الخادم يرسل FCM عند إنشاء طلب الموقع.
- سلامة جداول الأجهزة والحضور.
- صحة SQL/RPC من الداخل.
- حذف الفيديو فعليًا بعد 24 ساعة.

هذه النقاط تحتاج الكود المصدري وSupabase migrations وLogs وحسابات اختبار.

---

# 3. تحسينات مؤكدة في هذه النسخة

## 3.1 توقيع Release حقيقي

التطبيق ليس موقعًا بمفتاح Android Debug.

- Scheme: APK Signature V2
- Subject: `CN=Ahla Shabab HR, OU=IT, O=Association, L=Riyadh, ST=Riyadh, C=SA`
- المفتاح: RSA 2048-bit
- Signature Hash: SHA-384
- الصلاحية: من 20 يوليو 2026 حتى 5 ديسمبر 2053

هذه نقطة جيدة. تحذير Play Protect يمكن أن يظهر لأن الشهادة جديدة والتطبيق موزع خارج المتجر، وليس دليلًا وحده على وجود برمجية خبيثة.

ملاحظة: يجب حفظ الـKeystore وكلمات مروره خارج Git وعمل نسخة احتياطية مشفرة؛ فقدانه يمنع تحديث التطبيق المثبت بنفس التوقيع.

## 3.2 حماية النسخ الاحتياطي

الإعدادات الحالية جيدة:

- `android:allowBackup="false"`
- استثناء Shared Preferences وقواعد البيانات والملفات من Cloud Backup وDevice Transfer.

## 3.3 منع HTTP غير المشفر

- `usesCleartextTraffic="false"`
- Network Security Config يثق في شهادات النظام فقط.

لم يتم العثور على خوادم HTTP غير مشفرة داخل منطق التطبيق.

## 3.4 صلاحيات خدمة الموقع الأمامية موجودة

توجد:

- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION`
- خدمة Geolocator محددة كخدمة Location.

وهذا يصلح فجوة كانت تمنع العمل الصحيح على Android 14 و15.

## 3.5 لا توجد مفاتيح خادم سرية واضحة

تم العثور على:

- Supabase URL.
- Supabase Publishable Key.
- Firebase config/API key.

هذه القيم عامة بطبيعتها داخل تطبيقات العميل. لم يتم العثور على:

- Supabase Service Role Key.
- JWT إداري ثابت.
- Private Key.
- Firebase Admin Credential.
- AWS Secret Key.

يجب مع ذلك تقييد مفاتيح Google حسب Package والتوقيع عند الإمكان، وعدم الاعتماد على إخفاء المفتاح بدل RLS.

## 3.6 Native Libraries حديثة ومحاذاة 16KB

جميع مكتبات `.so` غير مضغوطة ومحاذاة داخل ZIP على حدود 16KB، كما أن LOAD segments مناسبة. هذه نقطة جيدة لأجهزة Android الحديثة.

---

# 4. المشكلات الحرجة P0

## P0-01: منظومة إشعار طلب الموقع خارج التطبيق غير مكتملة معماريًا

### الدليل داخل APK

التطبيق يحتوي على:

- `POST_NOTIFICATIONS`
- `USE_FULL_SCREEN_INTENT`
- `VIBRATE`
- `WAKE_LOCK`
- Firebase Messaging services.
- Dart background handler باسم `firebaseBackgroundHandler`.
- Channel ID باسم `urgent_location_v3`.
- `fullScreenIntent` داخل كود Flutter.
- Activity باسم `LocationRequestFullActivity` مع:
  - `showOnLockScreen=true`
  - `turnScreenOn=true`
  - طلب إغلاق شاشة القفل.

لكن توجد فجوات مهمة:

1. **لا توجد خدمة FirebaseMessagingService خاصة بالتطبيق**؛ الموجود هو Service العامة الخاصة بإضافة FlutterFire فقط.
2. `MainActivity` فارغة تمامًا ولا تنفذ معالجة Native للطلب العاجل.
3. لم يتم العثور على أي مرجع ثابت من الكود إلى `LocationRequestFullActivity` خارج الكلاس نفسه؛ يرجح أنها غير موصولة فعليًا بمسار الإشعار.
4. التطبيق يعتمد بدرجة كبيرة على Dart Background Isolate و`flutter_local_notifications`، وهي رحلة أقل موثوقية على Samsung عند إغلاق التطبيق، تقييد البطارية أو توقف Dart.
5. لا توجد `default_notification_channel_id` في Manifest لرسائل FCM التي تأتي كـnotification payload.
6. لا يوجد ملف صوت مخصص داخل `res/raw`؛ المورد الخام الوحيد هو `firebase_common_keep`.
7. توجد قناة `urgent_location_v3`. إعدادات قنوات Android لا تتغير بعد إنشائها؛ تعديل الصوت مع نفس ID لن يصلح الأجهزة المثبت عليها القناة القديمة.
8. لا توجد صلاحية `SYSTEM_ALERT_WINDOW` أو Overlay Service، لذلك التطبيق لا يملك «شاشة عائمة حقيقية فوق أي تطبيق». الموجود يمكن أن يكون Full-Screen Activity أو Heads-up Notification فقط.

### النتيجة المتوقعة

هذا يفسر السلوك المبلغ عنه:

- الطلب لا يصدر صوتًا أو اهتزازًا خارج التطبيق.
- لا تظهر شاشة كاملة إلا بعد فتح التطبيق أو تحريك واجهته.
- قد يصل الطلب عبر Supabase Realtime/Polling بعد فتح التطبيق بدل Push حقيقية لحظية.

### الإصلاح المطلوب

1. عند إنشاء طلب الموقع في الخادم، يجب إرسال FCM HTTP v1 فورًا من Edge Function/Backend، وعدم الاكتفاء بإضافة صف في قاعدة البيانات.
2. إنشاء Native `FirebaseMessagingService` خاص بالتطبيق للطلبات العاجلة.
3. إنشاء Notification Channel جديدة مثل:
   - `urgent_location_v4`
   ولا تعِد استخدام `v3` بعد تغيير الصوت والاهتزاز.
4. إضافة ملف صوت مخصص داخل `android/app/src/main/res/raw/`.
5. إنشاء القناة Native عند بدء التطبيق، وليس فقط بعد بدء Dart.
6. إعداد:
   - Importance MAX.
   - Priority HIGH/MAX.
   - Category ALARM أو CALL حسب السياسة التقنية.
   - صوت مخصص.
   - Vibration pattern واضح.
   - Lock-screen visibility.
   - Full-screen PendingIntent.
7. ربط PendingIntent صراحة بـ`LocationRequestFullActivity` وتمرير `request_id`.
8. يجب أن يفتح Activity الطلب المحدد، لا الصفحة الرئيسية.
9. تسجيل FCM token عند أول دخول وعند `onTokenRefresh` عبر `upsert_my_push_token`.
10. إضافة Delivery Status:
    - token_missing
    - sent
    - delivered
    - opened
    - failed
11. اختبار Foreground / Background / Terminated / Locked screen على هاتف Samsung حقيقي.
12. عند Force Stop يدوي من إعدادات Android، لا يمكن لأي تطبيق ضمان استقبال FCM حتى يفتحه المستخدم مرة أخرى؛ يجب توضيح هذا كقيد لنظام Android.

### معيار القبول

لا يعتبر البند مغلقًا حتى يصل الطلب بصوت واهتزاز وإشعار خارجي وشاشة كاملة عند التطبيق بالخلفية أو مغلقًا من Recent Apps، دون فتح المستخدم للتطبيق أولًا.

---

## P0-02: الحضور مبني على Passkey/WebAuthn بدل بصمة محلية مستقلة

### الدليل داخل APK

تم العثور على:

- `passkey_attendance_service.dart`
- `PasskeyAttendanceService`
- `passkeyAttendanceServiceProvider`
- مكتبات:
  - passkeys
  - passkeys_android
  - passkeys_doctor
  - Android Credential Manager
  - Google FIDO
- أخطاء:
  - `attendance_passkey_not_trusted`
  - `attendance_trusted_server_required`
  - `assertion_verification_failed`
  - `webauthn-challenge`
- صلاحيات Credential Manager وUSE_CREDENTIALS.

لم يتم العثور على حزمة Flutter المعتادة `local_auth` ضمن حزم التطبيق.

### النتيجة

رحلة الحضور تستدعي Samsung Pass/Google Credential Manager كـPasskey، بدل إظهار Fingerprint Prompt محلي مخصص لتأكيد الحضور. هذا يفسر ظهور نافذة «هل تريد تسجيل الدخول باستخدام مفتاح المرور المحفوظ؟» أثناء الحضور.

### الإصلاح المطلوب

1. فصل تسجيل الدخول بـPasskey عن تأكيد الحضور.
2. Passkey يبقى خيارًا داخل شاشة تسجيل الدخول فقط.
3. الحضور يستخدم Local Biometric Authentication مستقلًا.
4. استخدام `local_auth` أو Native BiometricPrompt.
5. بعد نجاح البصمة:
   - الحصول على الموقع.
   - التحقق من الجهاز.
   - تسجيل الحدث على الخادم.
6. عدم تشغيل Samsung Pass أو Credential Manager في مسار الحضور.
7. عدم إرسال بيانات البصمة الحيوية إلى الخادم؛ الخادم يستقبل فقط نتيجة تحقق موثوقة/Nonce وتوقيع الجهاز حسب التصميم.

### معيار القبول

ضغط «تسجيل الحضور» يظهر Fingerprint/Biometric Prompt، ولا يظهر Samsung Pass، وبعد النجاح يسجل الحضور في الخادم ويحدث «حالة اليوم».

---

## P0-03: تعارض حالة الجهاز مع الخادم

### الدليل

الكود يحتوي على:

- `register_my_device`
- `get_my_passkeys`
- `revoke_my_passkey`
- `device_not_active`
- `credential_disabled`
- `credential_already_registered`

والاختبارات الواقعية تظهر أن التطبيق يعرض الجهاز كمسجل أو نشط، بينما RPC الحضور ترجع:

`403 device_not_active`

### السبب المرجح

وجود أكثر من مصدر لحالة الجهاز أو اختلاف بين:

- device_id
- installation_id
- credential_id
- auth_user_id
- employee_id
- public_key
- status/is_active

### الإصلاح المطلوب

1. مصدر واحد للحقيقة لحالة الجهاز.
2. الواجهة تقرأ نفس View/RPC التي تعتمد عليها وظيفة الحضور.
3. لا تعرض «نشط» إلا إذا كان `punchAttendance` سيقبله.
4. دعم الحالات:
   - Pending approval.
   - Active.
   - Revoked.
   - Replaced.
5. معالجة إعادة تثبيت التطبيق وتغيير مفتاح الجهاز.
6. منع سجلات الأجهزة المكررة.
7. تمكين Main Admin من اعتماد/إلغاء/إعادة تفعيل الجهاز.
8. Audit Log كامل.

### معيار القبول

جهاز يظهر نشطًا في شاشة الأجهزة يجب أن يسجل حضورًا فعليًا، والجهاز الملغى يجب أن يُرفض برسالة مفهومة لا تحتوي على FunctionException.

---

## P0-04: فيديو التحقق مهيأ للصوت ويفشل في التسجيل أو الإكمال

### الدليل داخل APK

- صلاحية `RECORD_AUDIO` موجودة.
- CameraX Video 1.5.0 موجودة.
- توجد نصوص:
  - `enableAudio`
  - `withAudioEnabled`
  - `startVideoRecording`
  - `register_live_location_video`
  - Bucket: `live-location-videos`
- توجد صفحة `video_verification_page.dart`.
- الاختبار الواقعي أظهر SecurityException بسبب محاولة تمكين الصوت.

### المشكلة

الفيديو المطلوب هدفه التحقق البصري لمدة 5 ثوانٍ، وليس تسجيل الصوت. تفعيل الصوت يجعل رفض/غياب صلاحية الميكروفون يمنع الفيديو كله.

### الإصلاح المطلوب

1. إنشاء CameraController بـ`enableAudio: false`.
2. إزالة طلب الميكروفون إذا لم يعد مطلوبًا.
3. إدارة Lifecycle الكاميرا عند:
   - الانتقال للخلفية.
   - فتح الصلاحيات.
   - العودة من Samsung Pass.
   - تغيير الشاشة.
4. State Machine منفصلة:
   - initializing
   - ready
   - recording
   - recorded
   - uploading
   - metadata_saved
   - location_saved
   - completed
5. التحقق من الملف بعد التسجيل:
   - موجود.
   - الحجم > 0.
   - المدة 5 ثوانٍ.
   - MIME صحيح.
6. لا تحذف الملف المحلي قبل نجاح الرفع والربط.
7. Storage Bucket Private وSigned URLs قصيرة.
8. منع إكمال طلب `video_required=true` بدون فيديو.
9. Retry آمن عند انقطاع الإنترنت.
10. عدم تكرار الفيديو عند الضغط مرتين.
11. ربط الفيديو بـrequest_id وemployee_id ووقت التسجيل.
12. إظهاره مع الموقع والخريطة للمدير التنفيذي.
13. حذف تلقائي بعد 24 ساعة.

### معيار القبول

فيديو أمامي صامت مدته 5 ثوانٍ يتم تسجيله ورفعه وربطه بالطلب ويظهر للمدير التنفيذي مع الخريطة، دون ميكروفون ودون SecurityException.

---

## P0-05: Activity الشاشة الكاملة يرجح أنها غير مستخدمة فعليًا

`LocationRequestFullActivity` تنفذ ما يلي عند فتحها:

1. إظهار النشاط فوق شاشة القفل.
2. تشغيل الشاشة.
3. محاولة إغلاق Keyguard.
4. قراءة `request_id`.
5. فتح URI:
   `ahlashabab://action/live_location_request/{request_id}`
6. إنهاء نفسها.

لكن لم يظهر أي مرجع ثابت لها من MainActivity أو Service خاصة بالتطبيق أو Dart snapshot باسم الكلاس. يجب ربطها صراحة بـFull-Screen PendingIntent؛ مجرد وجودها في Manifest لا يجعل Android يفتحها.

---

## P0-06: أخطاء الخادم وRLS لا يمكن إصلاحها من APK

توجد دوال حساسة داخل التطبيق:

- `punchAttendance`
- `request_live_location`
- `respond_live_location_request`
- `submit_live_location_point`
- `register_live_location_video`
- `register_live_location_map_snapshot`
- `complete_my_live_location_request`
- `register_my_device`
- `upsert_my_push_token`
- `advance_kpi_stage`
- `return_kpi_stage`
- `decide_request`
- `submit_my_dispute`

كما توجد أكواد أخطاء:

- `PGRST203`
- `record_failed`
- `device_not_active`
- `attendance_idempotency_conflict`
- `attendance_passkey_not_trusted`
- `location_request_not_available`

يجب فحص التواقيع الفعلية لهذه RPCs وRLS وسياسات Storage. لا يكفي تعديل تطبيق Flutter.

---

# 5. مشكلات مرتفعة P1

## P1-01: لا توجد خلفية Location Permission للتتبع المستمر

التطبيق يحتوي على `live_tracking_session_page.dart` وخدمة موقع أمامية، لكن لا يطلب `ACCESS_BACKGROUND_LOCATION`.

- هذا مناسب لطلب موقع لحظي بعد فتح شاشة واضحة.
- لكنه لا يكفي لتتبع مستمر طويل أثناء خروج التطبيق للخلفية في كل السيناريوهات.

يجب تحديد المنتج بوضوح: الأفضل للخصوصية هو التقاط موقع لحظي بعد موافقة الموظف، لا مراقبة مستمرة.

## P1-02: Custom Deep Link قابل للاختطاف

MainActivity تستقبل:

- `ahlashabab://action/...`
- `https://ahla-shabab-management-os.vercel.app/action/...`

المشكلة:

- أي تطبيق آخر يمكنه تسجيل Scheme `ahlashabab`.
- `autoVerify=true` لا يفيد مع Custom Scheme.

الإصلاح:

1. استخدام HTTPS Verified App Links كمسار أساسي.
2. التحقق من `assetlinks.json` على الخادم.
3. قبول custom scheme كFallback فقط.
4. التحقق الخادمي من request_id والموظف والحالة قبل عرض أي بيانات.
5. منع IDOR وReplay.

## P1-03: أيقونة الإشعار الصغيرة غير مناسبة لمعايير Android

`ic_notification` عبارة عن Vector متعدد الألوان وله خلفية زرقاء. Android Small Notification Icon يجب أن تكون Silhouette بيضاء مع خلفية شفافة؛ وإلا قد تظهر كمربع أو شكل غير واضح.

يجب إنشاء أيقونة Monochrome بيضاء شفافة خاصة بالإشعارات.

## P1-04: صلاحيات قديمة أو غير لازمة

توجد:

- `READ_EXTERNAL_STORAGE`
- `WRITE_EXTERNAL_STORAGE` حتى SDK 28
- `RECEIVE_BOOT_COMPLETED`
- `AD_ID`
- `ACCESS_ADSERVICES_AD_ID`
- `ACCESS_ADSERVICES_ATTRIBUTION`

الملاحظات:

- Image Picker الحديث لا يحتاج غالبًا صلاحيات التخزين القديمة.
- لا توجد Receivers مجدولة من flutter_local_notifications في Manifest رغم وجود RECEIVE_BOOT_COMPLETED، لذلك راجع الحاجة إليها.
- تطبيق HR حساس ولا يحتاج Advertising ID في العادة.

الإصلاح:

- إزالة الصلاحيات غير المستخدمة.
- إزالة/تعطيل Advertising ID وAdServices إذا لم يوجد هدف تحليلي مبرر.
- مراجعة Firebase Analytics وخصوصية الموظفين.

## P1-05: Offline/Error Handling غير ناضج

الكود يحتوي على:

- `connectivity_service.dart`
- `connectivity_banner.dart`
- package `retry`

لكن الأخطاء الواقعية تظهر Raw Exceptions وعنوان Supabase للمستخدم عند فشل DNS أو Refresh Token.

المطلوب:

- عدم تسجيل خروج المستخدم عند انقطاع مؤقت.
- عدم كشف Endpoint أو Stack Trace.
- Cache لآخر بيانات سليمة.
- Retry Backoff.
- إعادة مزامنة عند عودة الشبكة.
- Global Error Boundary.

## P1-06: عدم تفعيل Dart Obfuscation

تم استخراج عشرات أسماء الملفات والدوال وRPCs بسهولة من `libapp.so`، مثل:

- `passkey_attendance_service.dart`
- `video_verification_page.dart`
- `executive_location_page.dart`
- `request_live_location`
- `register_live_location_video`

التطبيق AOT وNative libraries stripped، لكنه لم يُبنَ غالبًا بـ:

`--obfuscate --split-debug-info`

هذا لا يحل الأمان بدل RLS، لكنه يقلل كشف البنية الداخلية ويجب استخدامه في Release مع حفظ Symbols لفك Crash Reports.

## P1-07: حماية الجلسات والمفاتيح تحتاج مراجعة المصدر

توجد حزمتا:

- `flutter_secure_storage`
- `shared_preferences`

كما أن Supabase Default Local Storage موجود داخل الحزمة. لا يمكن إثبات من APK أي مخزن مستخدم فعليًا للجلسة ومفاتيح الجهاز.

يجب التأكد أن:

- Device private keys/tokens الحساسة في Android Keystore/Secure Storage.
- لا تُخزن مفاتيح حساسة في SharedPreferences كنص واضح.

---

# 6. مشكلات متوسطة P2

## P2-01: حجم APK كبير جدًا

التوزيع التقريبي:

- arm64-v8a: 19.67 MB
- armeabi-v7a: 17.50 MB
- x86_64: 20.87 MB
- DEX: 4.88 MB غير مضغوط

النسخة Universal تجمع عدة ABIs، لذلك وصلت إلى 62 MB.

الإصلاح:

- بناء Split APK لكل ABI أو App Bundle داخليًا.
- غالبية الهواتف الحديثة تحتاج arm64 فقط.

## P2-02: دعم x86 جزئي وغير متناسق

مجلد `lib/x86` يحتوي مكتبات Plugins صغيرة، لكنه لا يحتوي `libapp.so` أو `libflutter.so`. قد يسبب تثبيتًا/تشغيلًا غير متوقع على محاكي x86 32-bit.

- إما إضافة دعم x86 كامل.
- أو استبعاده تمامًا.

## P2-03: التوقيع V2 فقط

V2 كافٍ لأن Min SDK 24، لكنه لا يستخدم V3/V4.

- V3 مفيد لدعم Key Rotation مستقبلًا.
- ليس عيبًا مانعًا حاليًا.

## P2-04: بيانات شهادة التوقيع غير متسقة تنظيميًا

الشهادة مسجلة بـRiyadh وSA بينما سياق الجمعية في مصر. لا تؤثر تقنيًا، لكنها تحتاج توحيدًا قبل الانتشار الواسع إذا لم تكن مقصودة. تغيير المفتاح بعد تثبيت التطبيق يمنع التحديث المباشر، لذلك لا تغيّره دون خطة.

## P2-05: لا يوجد Certificate Pinning

الاتصالات HTTPS وتثق في شهادات النظام، وهذا جيد. Pinning اختياري للنظام الحساس، لكنه يحتاج سياسة Rotation حتى لا يوقف التطبيق عند تغيير الشهادة.

---

# 7. الوحدات الموجودة فعليًا داخل التطبيق

تم تأكيد وجود كود للوحدات التالية:

## الهوية والدخول

- Login.
- Set password.
- Supabase Auth.
- Google Sign-in.
- Passkeys/WebAuthn.
- Secure Storage.

## الموظف

- الصفحة الرئيسية.
- الحضور والانصراف.
- سجل الحضور.
- تصحيح الحضور.
- الملف الشخصي.
- الخصوصية.
- الأجهزة/Passkeys.
- الطلبات.
- المهام.
- التعلم والتدريب.
- التقارير اليومية.

## المدير المباشر

- Manager home.
- Manager dashboard.
- عمليات الفريق.
- المهام والتنبيهات والتقارير الناقصة.

## المدير التنفيذي

- Dashboard.
- حضور اليوم.
- دليل الموظفين.
- ملخص الموظف.
- المواقع وطلبات الموقع.
- القرارات.
- التقارير.
- الحوكمة.
- مركز المخاطر.
- وضع الطوارئ.

## KPI

- Inbox.
- أهداف.
- جلسة مراجعة.
- Compliance metrics.
- Advance/Return stage.
- Acknowledge.

## الخلافات والطلبات

- Disputes.
- Appeals.
- Requests.
- Decisions/Votes.
- Notifications.

وجود هذه الملفات والدوال يؤكد أن الوحدات مضمنة، لكنه لا يثبت صحة البيانات أو صلاحياتها.

---

# 8. مراجعة KPI من APK

تم العثور على مراحل وصلاحيات مثل:

- `performance.kpi.self_assess`
- `performance.kpi.manager_assess`
- `performance.kpi.hr_assess`
- `performance.kpi.hr_review`
- `performance.kpi.secretary_review`
- `performance.kpi.executive_review`

ودوال:

- `get_kpi_inbox`
- `get_kpi_evaluation_form`
- `save_kpi_goal`
- `save_kpi_review_session`
- `save_kpi_compliance_metric`
- `advance_kpi_stage`
- `return_kpi_stage`

البنية موجودة. لكن لا يمكن إثبات من APK أن الأوزان مطبقة فعلًا كالآتي:

- Target: 40
- الكفاءة: 20
- الحضور الآلي: 20
- السلوك: 5
- الصلاة: 5
- حلقة الشيخ وليد: 5
- التبرعات والمبادرات: 5

يجب اختبار Backend Form وCalculation وSnapshot وسياسات الأدوار.

---

# 9. مراجعة طلب الموقع والفيديو

توجد دوال صريحة:

- `request_live_location`
- `respond_live_location_request`
- `get_my_live_location_requests`
- `submit_live_location_point`
- `register_live_location_map_snapshot`
- `register_live_location_video`
- `complete_my_live_location_request`

وتوجد Buckets:

- `live-location-videos`
- `live-location-map-snapshots`

كما يوجد:

- كشف Mock Location (`p_is_mock` / `is_mocked`).
- Map snapshot باستخدام package `screenshot` وFlutter Map.
- OpenStreetMap tiles عبر HTTPS.
- رابط فتح Google Maps.

المطلوب في فحص الباك إند:

1. Bucket Private.
2. الموظف يرفع لطلبه فقط.
3. المدير التنفيذي يرى ما تسمح به صلاحياته.
4. Signed URL قصيرة.
5. Delete Job بعد 24 ساعة.
6. عدم اعتبار الطلب مكتملًا قبل الموقع والفيديو عند إلزام الفيديو.
7. Idempotency لكل مرحلة.
8. Realtime/FCM update للمدير التنفيذي بعد الإكمال.

---

# 10. قائمة اختبارات إلزامية قبل الاعتماد

## الإشعارات

1. التطبيق مفتوح.
2. في الخلفية.
3. مغلق من Recent Apps.
4. شاشة الهاتف مقفلة.
5. وضع توفير البطارية على Samsung.
6. Notification Permission مرفوضة ثم مفعلة.
7. Full-screen permission مفعلة وغير مفعلة.
8. FCM Token تغير.
9. موظف بلا Token.
10. منع تكرار الإشعار.

## الحضور

1. جهاز جديد.
2. جهاز Active.
3. جهاز Pending.
4. جهاز Revoked.
5. بصمة محلية.
6. GPS مغلق ثم تفعيله.
7. الموقع دقته منخفضة.
8. Mock Location.
9. خارج النطاق.
10. ضغط متكرر.
11. حضور ثم انصراف.
12. انقطاع الإنترنت في منتصف العملية.

## الفيديو

1. صلاحية Camera مسموحة.
2. مرفوضة ثم مفعلة.
3. لا توجد صلاحية Microphone والفيديو يعمل صامتًا.
4. تسجيل 5 ثوانٍ.
5. الملف موجود وحجمه > 0.
6. انقطاع الإنترنت أثناء الرفع.
7. استكمال الرفع.
8. Storage Policy denied.
9. Metadata failed بعد نجاح الرفع.
10. ظهور الفيديو للمدير.
11. حذف بعد 24 ساعة.

## KPI والبيانات

1. تطابق الهاتف والويب.
2. دورة 20–25.
3. مجموع 100.
4. الحضور الآلي لا يخصم الإجازات/المأموريات/القوافل/الفاندي.
5. الصلاحيات لكل دور.
6. فتح وإغلاق الدورة من Main Admin.

---

# 11. ترتيب الإصلاح المقترح

## P0 — قبل أي توزيع

1. إعادة بناء Pipeline إشعار الموقع Native + Server FCM.
2. إنشاء قناة `urgent_location_v4` بصوت مخصص.
3. توصيل `LocationRequestFullActivity` فعليًا.
4. فصل Passkey Login عن بصمة الحضور.
5. إصلاح Device Identity و`device_not_active`.
6. فيديو صامت 5 ثوانٍ وإصلاح Upload/Complete workflow.
7. فحص RPC/RLS/Storage policies.
8. Error handling وعدم كشف الأخطاء التقنية.

## P1 — قبل التشغيل المؤسسي

1. Deep Links/IDOR.
2. Offline state والمزامنة.
3. تأمين Storage/Signed URLs/Retention.
4. إزالة الصلاحيات غير اللازمة وAdvertising ID.
5. إصلاح Notification Icon.
6. Dart Obfuscation.
7. تطابق البيانات بين الهاتف والويب.

## P2 — تحسين الإصدار

1. Split APK.
2. تنظيف ABI x86.
3. توقيع V3 مستقبلًا.
4. توحيد بيانات الشهادة.
5. تحسين الأداء والواجهة.

---

# 12. الخلاصة النهائية

هذه النسخة **أفضل من النسخة السابقة من ناحية التغليف والأمان الأساسي**: توقيع Release، منع Backup، منع Cleartext، صلاحيات Foreground Location، أيقونة وهوية، ووجود مكونات FCM/Full Screen.

لكن الوظائف الأكثر أهمية ما زالت غير موثوقة لأن التصميم الحالي يعتمد على:

- Dart background handler للإشعار العاجل بدل Pipeline Native موثوقة.
- Passkey/WebAuthn داخل الحضور بدل بصمة محلية مستقلة.
- تسجيل فيديو مع Audio رغم عدم الحاجة إليه.
- حالة جهاز غير موحدة بين التطبيق والباك إند.

الحكم: **لا تعتمد النسخة 0.11.1 كنسخة تشغيل نهائية قبل إغلاق P0 وإثبات الرحلات على أجهزة حقيقية.**
