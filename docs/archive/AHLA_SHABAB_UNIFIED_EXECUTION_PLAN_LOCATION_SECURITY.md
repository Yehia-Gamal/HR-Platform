أنت الآن Senior Flutter Engineer + Backend Engineer + Supabase/PostgreSQL Engineer
ومسؤول عن إصلاح منظومة Production حقيقية، وليس إعداد تقرير أو تنفيذ واجهات شكلية.


> **ملاحظة تنفيذية معتمدة:** التطبيق سيتم توزيعه داخليًا خارج Google Play، ولذلك يجب الإبقاء على `USE_FULL_SCREEN_INTENT` وميزة الإشعار كامل الشاشة وعدم حذفهما. قيود Android نفسها ما زالت واجبة الاختبار؛ إذا منع النظام الظهور الكامل على جهاز معين، يُستخدم Heads-up قوي مع فتح شاشة الطلب الكاملة فور تفاعل المستخدم، دون إزالة المسار الأساسي كامل الشاشة.

## أمر تنفيذي ملزم

لا تكتب تقريرًا نظريًا فقط.
لا تقل إن المشكلة أُصلحت قبل تعديل الملفات فعليًا.
لا تخفِ الأخطاء باستخدام try/catch أو رسائل نجاح وهمية.
لا تستخدم بيانات Mock أو TODO أو حلول مؤقتة.
لا تتوقف بعد إصلاح أول Error.

افتح كامل المشروع وافحص:

- تطبيق الموظف Flutter.
- تطبيق المدير التنفيذي Flutter.
- خدمات Backend.
- Supabase Database.
- SQL migrations.
- Edge Functions.
- Firebase Cloud Messaging.
- Supabase Storage.
- RLS policies.
- AndroidManifest.xml.
- إعدادات Android Native.
- إدارة الصلاحيات.
- Deep Links والتنقل من الإشعارات.

نفّذ الإصلاحات فعليًا داخل المشروع، ثم اختبر الدورة كاملة End-to-End.

# الهدف النهائي

تنفيذ رحلة كاملة للمدير التنفيذي الشيخ محمد يوسف:

1. فتح شاشة المتابعة الميدانية.
2. رؤية جميع موظفي الجمعية والمديرين دون استثناء.
3. رؤية حالة كل شخص اليوم:
   - حاضر.
   - متأخر.
   - غائب.
   - في مأمورية.
   - في إجازة.
   - لم يسجل انصرافه.
4. إرسال طلب تحقق موقع إلى أي موظف أو مدير، ومنهم المدير يحيى.
5. لا يوجد حقل لكتابة سبب الطلب.
6. الخيار الوحيد في طلب المدير التنفيذي:
   - موقع فعلي عالي الدقة.
   - فيديو أمامي مدته 5 ثوانٍ.
7. وصول إشعار قوي وفوري للموظف في الحالات التالية:
   - التطبيق مفتوح.
   - التطبيق في الخلفية.
   - التطبيق مغلق.
8. الضغط على الإشعار يفتح طلب الموقع نفسه مباشرة.
9. تظهر شاشة كاملة داخل التطبيق لطلب التحقق.
10. بعد ضغط الموظف على «أرسل موقعي الآن»:
    - فحص GPS.
    - فحص صلاحية الموقع.
    - فحص صلاحية الكاميرا.
    - التقاط الموقع الحالي عالي الدقة.
    - Reverse Geocoding إلى عنوان عربي.
    - عرض خريطة حقيقية.
    - إنشاء لقطة خريطة.
    - فتح الكاميرا الأمامية.
    - تسجيل فيديو 5 ثوانٍ بالضبط.
    - رفع الفيديو والموقع.
    - إظهار النتيجة للمدير التنفيذي.
    - حفظ النتيجة في سجل الموظف.

لا تجمع الموقع أو تشغل الكاميرا سرًا.
تبدأ عملية الالتقاط بعد تفاعل الموظف مع الطلب، مع الالتزام بصلاحيات Android.

# P0 — إصلاح الأعطال المانعة

## 1. إصلاح RPC log_audit_event

الخطأ الحالي:

PostgrestException:
function public.log_audit_event(unknown, unknown, uuid, jsonb) does not exist
code 42883

ابحث في المشروع عن جميع الاستدعاءات:

- log_audit_event
- supabase.rpc
- audit event

ثم افحص الدوال الموجودة فعليًا باستخدام استعلام مثل:

select
  n.nspname as schema_name,
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname = 'log_audit_event';

بعد ذلك:

- أنشئ Migration idempotent للدالة إن كانت مفقودة.
- أو وحّد توقيع الدالة مع الاستدعاء.
- استخدم أسماء معاملات متطابقة.
- استخدم أنواعًا صريحة بدل unknown.
- راجع ترتيب uuid وjsonb والنصوص.
- امنح EXECUTE للأدوار المطلوبة بصورة آمنة.
- لا تجعل فشل Audit Logging يؤدي إلى حالة بيانات جزئية.
- استخدم Transaction أو Compensation مناسبًا.
- طبّق Migration على بيئة Supabase الفعلية.
- اختبر الاستدعاء مباشرة من SQL ومن التطبيق.

## 2. إصلاح تسجيل البصمة والجهاز

الأخطاء الحالية:

- registration_verification_failed
- HTTP 403 Forbidden
- PasskeyAuthCancelledException

افحص دورة التسجيل كاملة:

- إنشاء challenge.
- تخزين challenge.
- user_id.
- device_id.
- expires_at.
- used_at.
- RP ID.
- origin.
- clientDataJSON.
- attestationObject.
- credentialId.
- base64url encoding.
- Session JWT.
- RLS.
- Edge Function logs.
- package name.
- Android app association.
- SHA-256 fingerprints.

لا تكتفِ بإخفاء 403.

بعد الإصلاح يجب أن:

- يسجل الموظف جهازه بنجاح.
- تظهر البصمة الأصلية للنظام.
- يُحفظ الجهاز في employee_devices.
- يظهر الجهاز في «أجهزة البصمة الموثوقة».
- يستطيع الموظف إثبات هويته بالبصمة عند الحضور والانصراف.
- لا تُرسل بيانات البصمة الخام إلى الخادم.

إن كانت بنية Passkeys الحالية غير مناسبة لتطبيق Android Native، استخدم معمارية موحدة:

1. إنشاء مفتاح Hardware-backed داخل Android Keystore.
2. حماية استخدام المفتاح بالبصمة المحلية.
3. حفظ المفتاح العام في الخادم.
4. إصدار Challenge للحضور من الخادم.
5. توقيع Challenge بعد نجاح البصمة.
6. تحقق الخادم من التوقيع.

لا تترك Passkeys ونظام Keystore يعملان بالتوازي بشكل متضارب.

تعامل مع إلغاء المستخدم للبصمة كحالة Cancel طبيعية، وأظهر:
«تم إلغاء التحقق بالبصمة».

## 3. إصلاح الكاميرا والفيديو

الخطأ الحالي:

CameraException SecurityException:
Attempted to enable audio for recording but RECORD_AUDIO permission was not granted.

الفيديو المطلوب لا يحتاج صوتًا، لذلك:

- أنشئ CameraController باستخدام enableAudio: false.
- لا تطلب RECORD_AUDIO دون حاجة.
- اطلب CAMERA وقت التشغيل.
- استخدم الكاميرا الأمامية.
- انتظر await controller.initialize().
- لا تعرض CameraPreview قبل اكتمال التهيئة.
- أصلح AppLifecycleState.
- أعد تهيئة الكاميرا عند الرجوع من الخلفية.
- امنع Dispose أثناء التسجيل.
- أضف Retry واضح عند الخطأ.
- سجل 5 ثوانٍ بالضبط.
- أوقف التسجيل تلقائيًا.
- لا تسمح بالضغط المتكرر أثناء التسجيل.
- اعرض Progress واضح 1 إلى 5.
- تحقق أن ملف الفيديو موجود وحجمه أكبر من صفر قبل الرفع.

أصلح تمدد الصورة باستخدام:

- AspectRatio بالقيمة الأصلية للكاميرا.
- sensorOrientation.
- orientation lock أثناء الالتقاط.
- BoxFit دون تشويه الوجه.
- اختبار portrait على هاتف Samsung حقيقي.

لا يجب أن تظهر شاشة سوداء في أي حالة.
عند الفشل اعرض رسالة عربية وزر «إعادة فتح الكاميرا».

## 4. إصلاح GPS والموقع

عند إغلاق GPS لا تحفظ الخطأ التالي داخل سجل الطلب:

Bad state: خدمة الموقع غير مفعلة

نفّذ State Machine:

- checkingService
- requestingPermission
- waitingForGps
- acquiringLocation
- validatingAccuracy
- reverseGeocoding
- ready
- capturingVideo
- uploading
- completed
- failedRecoverable

عند إغلاق GPS:

- اعرض Dialog عربي.
- زر «فتح إعدادات الموقع».
- بعد عودة المستخدم افحص GPS تلقائيًا.
- استكمل نفس الطلب دون إنشاء طلب جديد.
- لا تعتبر الطلب فاشلًا نهائيًا.

التقط موقعًا حديثًا باستخدام أعلى دقة مناسبة.
احفظ:

- latitude.
- longitude.
- accuracy.
- altitude إن كانت متاحة.
- captured_at من الخادم.
- provider.
- address.
- map snapshot.

لا تعتمد على lastKnownPosition وحده.
ارفض الموقع القديم أو غير الدقيق، ثم أعد المحاولة برسالة مفهومة.

## 5. إصلاح الإشعارات

أنشئ Pipeline حقيقي:

Executive App
→ Backend authenticated endpoint
→ إنشاء location_request
→ إرسال FCM
→ Android receives request
→ full-screen/heads-up notification
→ deep link إلى requestId
→ employee response
→ realtime update للمدير

استخدم:

- FCM high priority.
- Notification channel بأهمية قصوى `IMPORTANCE_HIGH/MAX` وفق التنفيذ المتاح.
- صوت مخصص قوي وواضح داخل `android/app/src/main/res/raw`.
- vibration pattern قوي ومميز، مع إيقافه عند فتح الطلب أو الإقرار به.
- `POST_NOTIFICATIONS`.
- الإبقاء على `USE_FULL_SCREEN_INTENT` وعدم حذفه.
- إنشاء Full-screen PendingIntent يفتح طلب الموقع نفسه بواسطة `request_id`.
- فحص `NotificationManager.canUseFullScreenIntent()` على Android 14+.
- إذا كانت صلاحية Full-screen Intent غير مفعلة، افتح شاشة إعداد السماح للمستخدم أو الإدارة بدل حذف الميزة.
- Full-screen notification هو المسار الأساسي في التوزيع الداخلي.
- Heads-up notification قوي هو Fallback تشغيلي فقط عندما يمنع Android الظهور الكامل.
- عند فتح التطبيق أو عودته للواجهة، تظهر شاشة الطلب الكاملة داخل التطبيق فورًا.
- `FirebaseMessaging.onBackgroundMessage`.
- `FirebaseMessaging.instance.getInitialMessage()`.
- `FirebaseMessaging.onMessageOpenedApp`.
- foreground listener.
- عدم الاعتماد على Flutter Process وحده؛ أضف معالجة Android Native عند الحاجة لإظهار Full-screen Intent بسرعة وثبات.

لا تعتمد على بقاء Flutter process حيًا طوال الوقت.

عندما يكون التطبيق مفتوحًا:
- افتح شاشة الطلب الكاملة داخل التطبيق.

عندما يكون في الخلفية أو مغلقًا:
- أظهر إشعار النظام.
- الضغط عليه يفتح الطلب المحدد، وليس Home.

استخدم request_id لمنع تكرار نفس الإشعار.

سجل حالات الإشعار:

- queued.
- sent.
- delivered إن أمكن.
- opened.
- failed.

## 6. إصلاح عرض جميع الموظفين

افحص Query وRLS الخاصة بشاشة المتابعة.

يجب أن يرى المدير التنفيذي جميع الحسابات الوظيفية النشطة، وليس role=employee فقط.

ضمّن:

- الموظفين.
- مديري الإدارات.
- المديرين المباشرين.
- المدير يحيى.
- المستخدمين الذين لا يملكون صورة.
- المستخدمين الذين لم يسجلوا البصمة بعد.

لا تستخدم inner join يؤدي إلى إسقاط الموظف بسبب بيانات اختيارية.
استخدم left join عند الحاجة.
أزل limits غير المقصودة أو نفّذ pagination.
راجع is_active وorganization_id وbranch_id.
راجع RLS بحيث يستطيع executive role قراءة جميع موظفي الجمعية.

أضف اختبارًا صريحًا يؤكد ظهور المدير يحيى.

## 7. إعادة إرسال الطلب

يستطيع المدير التنفيذي إرسال طلب جديد لنفس الشخص كل 30 ثانية دون إلغاء الطلب السابق.

نفّذ القاعدة على الخادم:

- cooldown = 30 seconds per requester + target employee.
- كل طلب له UUID مستقل.
- لا يوجد شرط يلزم إغلاق الطلب السابق.
- لا يوجد unique constraint يمنع الطلب الجديد.
- الطلبات السابقة محفوظة في السجل.
- قبل مرور 30 ثانية اعرض عدادًا.
- بعد مرورها يُفعل الزر تلقائيًا.
- لا تعتمد على عداد الواجهة وحده؛ تحقق من الخادم.


# P0 إضافي — نتائج الفحص العميق للـAPK الواجب دمجها في التنفيذ

تم فحص APK الإصدار `0.10.0`، واتضح أن رحلة الموقع والفيديو موجودة فعليًا، لكن توجد مشكلات أمان وتشغيل وإصدار يجب إصلاحها ضمن نفس المهمة، وليس في تقرير منفصل.

## 8. إصلاح توقيع نسخة Android

النسخة الحالية موقعة بشهادة:

`CN=Android Debug, O=Android, C=US`

حتى مع التوزيع الداخلي وعدم الرفع على Google Play، يجب عدم اعتماد Debug Keystore للإصدار التشغيلي، لأنه يضعف هوية التطبيق ومسار التحديثات ويعرض التوقيع للخطأ أو الفقد.

نفّذ:

- إنشاء Release Keystore مخصص للمؤسسة.
- حفظ كلمات المرور في Secrets/CI وعدم وضعها داخل Git.
- توثيق SHA-256 لشهادة الإصدار وربطها بالخدمات التي تحتاج App Fingerprint.
- الحفاظ على نفس مفتاح الإصدار لكل التحديثات الداخلية القادمة.
- بناء APK Release موقع فعليًا والتحقق باستخدام `apksigner verify --verbose --print-certs`.
- لا تستخدم Debug Certificate في النسخة المسلمة للموظفين.

## 9. إصلاح صلاحيات Foreground Location على Android 14 و15

الـAPK يحتوي على خدمة Location من نوع Foreground، لكن الفحص لم يثبت وجود جميع الصلاحيات المطلوبة.

افحص `AndroidManifest.xml`، وعند استخدام تتبع الموقع في Foreground Service أضف حسب الحاجة:

- `android.permission.FOREGROUND_SERVICE`
- `android.permission.FOREGROUND_SERVICE_LOCATION`
- `android.permission.ACCESS_FINE_LOCATION`
- `android.permission.ACCESS_COARSE_LOCATION`

وتأكد من:

- تحديد `foregroundServiceType="location"`.
- إنشاء إشعار Foreground Service واضح أثناء جلسة التحقق الحية فقط.
- عدم استمرار الخدمة بعد اكتمال الطلب أو إلغائه.
- عدم بدء الخدمة من الخلفية في حالة يمنعها Android.
- اختبار الشاشة مقفلة، والتطبيق في الخلفية، وAndroid 14 و15.
- عدم طلب `ACCESS_BACKGROUND_LOCATION` إلا إذا كان هناك احتياج حقيقي ومعلن؛ رحلة لقطة الموقع الحالية لا تحتاج مراقبة مستمرة.

## 10. تأمين النسخ الاحتياطي واستخراج البيانات

حدّد صراحة داخل التطبيق:

- `android:allowBackup="false"` إذا لم تكن هناك حاجة لنسخ بيانات التطبيق.
- أو استخدم `dataExtractionRules` و`fullBackupContent` لاستثناء البيانات الحساسة.

يجب استثناء:

- Supabase sessions وRefresh Tokens.
- Flutter Secure Storage.
- مفاتيح الجهاز والبصمة.
- بيانات Passkeys/Keystore.
- ملفات الموقع المؤقتة.
- فيديوهات التحقق.
- لقطات الخرائط.
- أي Cache يحتوي معلومات موظفين.

اختبر النسخ والاستعادة ولا تسمح باستعادة جلسة موظف على جهاز آخر بصورة غير مشروعة.

## 11. تأمين Deep Links والتنقل من الإشعارات

المسار الحالي يستخدم Custom Scheme مثل:

`ahlashabab://action`

يمكن الإبقاء عليه للتوافق الداخلي، لكن يجب تأمينه بالكامل:

- لا تنفذ أي إجراء حساس اعتمادًا على الرابط فقط.
- تحقق من جلسة المستخدم ودوره وصاحب الطلب على الخادم.
- تحقق من `request_id` وأنه موجه للمستخدم الحالي وغير منتهي.
- استخدم allowlist للـactions المسموحة.
- ارفض القيم غير المعروفة أو المعدلة.
- امنع IDOR عند تغيير `request_id`.
- أضف HTTPS App Links موثقة كمسار إضافي إن أمكن، دون كسر الـCustom Scheme الحالي.
- اختبر رابطًا مزورًا ورابط موظف آخر ورابط طلب منتهي.

## 12. فحص RLS وRPCs وStorage فعليًا

وجود الصلاحيات داخل Flutter لا يكفي.

افحص كل RPC حساس، خصوصًا:

- `request_live_location`
- `respond_live_location_request`
- `submit_live_location_point`
- `register_live_location_video`
- `complete_my_live_location_request`
- `log_audit_event`
- عمليات الحضور وKPI والإجازات والخلافات المرتبطة.

القواعد الإلزامية:

- اشتق هوية المستخدم من `auth.uid()` ولا تثق في `employee_id` أو `role` المرسلين من العميل.
- المدير التنفيذي يرى ويطلب جميع موظفي الجمعية وفق المؤسسة الحالية فقط.
- المدير المباشر يطلب موظفيه فقط إذا كانت الصلاحية مفعلة.
- الموظف يستجيب لطلبه فقط.
- اربط الاستجابة بالمستخدم والجهاز والطلب الفعّال.
- اجعل `SECURITY DEFINER` عند الضرورة فقط، مع `search_path` آمن وفحوص صريحة.
- امنع تعديل الإحداثيات أو الفيديو بعد إكمال الطلب.
- اختبر كل Role باستخدام JWT مستقل.

## 13. تأمين Supabase Storage وحذف البيانات بعد 24 ساعة

Bucket الفيديو ولقطات الخرائط يجب أن يكونا Private.

نفّذ:

- منع Public Read وPublic List.
- منع الموظف من رفع ملف لمسار موظف آخر.
- استخدام Signed URLs قصيرة الصلاحية.
- التحقق من صلاحية المشاهدة قبل إصدار Signed URL.
- تسجيل من شاهد أو حمّل الفيديو.
- حذف الفيديو ولقطة الخريطة تلقائيًا بعد 24 ساعة.
- الاحتفاظ بسجل نصي للطلب والنتيجة وحالة الحذف دون الاحتفاظ بالوسائط.
- إضافة Retry وDead-letter/failed-cleanup report عند فشل الحذف.
- عدم استخدام Service Role داخل تطبيق الهاتف.

## 14. منع Replay والتكرار والتعارض

نفّذ حماية خادمية ضد:

- إكمال الطلب مرتين.
- رفع أكثر من فيديو لنفس الطلب دون Version واضح.
- إعادة استخدام فيديو قديم.
- إرسال Response نيابة عن موظف آخر.
- تغيير request ID أثناء الرفع.
- تكرار Push Notification لنفس Event.
- تكرار Audit Event.

استخدم:

- Idempotency Keys.
- Unique Constraints مناسبة.
- Transactions.
- Server timestamps.
- State transition validation.
- checksum للفيديو.
- رقم نسخة أو lock عند تحديث الحالة.

## 15. إزالة صلاحيات التخزين القديمة

افحص الحاجة إلى:

- `READ_EXTERNAL_STORAGE`
- `WRITE_EXTERNAL_STORAGE`

إذا لم تكن هناك حاجة حقيقية، احذفها واستخدم:

- App-specific storage.
- Cache directory مؤقتة.
- Android Photo Picker أو SAF عند اختيار مستند من المستخدم.

لا تحفظ فيديو التحقق داخل معرض الهاتف.

## 16. إضافة الصوت والأيقونة وإعدادات قناة الإشعار

الفحص أثبت عدم وجود ملف صوت مخصص داخل الـAPK الحالي.

نفّذ:

- ملف صوت مخصص قصير وقوي داخل `res/raw`.
- Notification Channel جديد بمعرّف إصدار جديد حتى تُطبق خصائص الصوت والاهتزاز.
- أيقونة Monochrome مخصصة للإشعارات.
- `default_notification_icon` و`default_notification_color` في الـManifest.
- صوت واهتزاز قويان دون Loop غير منتهٍ.
- إيقاف الصوت والاهتزاز عند فتح الطلب أو انتهاء صلاحيته.
- اختبار Samsung وXiaomi/Oppo إن كانت ضمن الأجهزة الفعلية للجمعية.

## 17. تفعيل Dart Obfuscation وحفظ رموز التصحيح

ابنِ نسخة التشغيل باستخدام:

```bash
flutter build apk --release \
  --obfuscate \
  --split-debug-info=build/symbols/<version>
```

مع:

- حفظ ملفات Symbols في مكان آمن.
- ربط الإصدار بالـcommit والـversion code.
- عدم نشر Symbols داخل APK أو مستودع عام.
- استمرار تفعيل R8/ProGuard للجزء Native.

## 18. منع الاتصالات غير المشفرة وتأمين WebView

نفّذ:

- `android:usesCleartextTraffic="false"`.
- Network Security Config يمنع HTTP غير المشفر.
- Allowlist للنطاقات التي يمكن فتحها داخل التطبيق.
- فتح الروابط الخارجية في المتصفح الافتراضي عند الإمكان.
- عدم فتح URL قادم من Push أو قاعدة البيانات دون Validation.
- تعطيل JavaScript في WebView إذا لم يكن مطلوبًا.
- لا تطبق Certificate Pinning إلا مع خطة Rotation وFallback صحيحة.

## 19. تحسين هوية وحجم نسخة Android

- غيّر الاسم الظاهر من `ahla_shabab_management_os` إلى `أحلى شباب HR`.
- استخدم `--split-per-abi` عند توزيع APK داخليًا لتقليل الحجم.
- أنشئ على الأقل نسخة `arm64-v8a` للأجهزة الحديثة، مع نسخة أخرى فقط عند الحاجة.
- لا تحذف ABI مدعومًا قبل حصر أجهزة الموظفين.
- حدّث Version Code وVersion Name لكل تسليم.

## 20. Crash Reporting وCorrelation IDs

- أضف Crash Reporting مناسبًا للنسخ الداخلية.
- اربط أخطاء التطبيق والـEdge Functions وRPCs باستخدام `correlation_id`.
- لا تسجل الفيديو أو الإحداثيات الكاملة داخل Crash Logs.
- لا تعرض Stack Trace للمستخدم.
- أنشئ لوحة للأخطاء المتكررة ومعدل فشل طلب الموقع ورفع الفيديو والإشعار.


# نموذج البيانات المطلوب

راجع أو أنشئ الجداول التالية بصورة متوافقة مع بنية المشروع:

## location_requests

- id uuid primary key
- organization_id
- requester_id
- target_employee_id
- type = location_video_5s
- status
- requested_at
- expires_at
- delivered_at
- opened_at
- completed_at
- failed_at
- failure_code
- created_at
- updated_at

لا تضف reason كحقل مطلوب في رحلة المدير التنفيذي.

## location_request_responses

- id
- request_id
- employee_id
- latitude
- longitude
- accuracy_meters
- address
- captured_at
- video_storage_path
- map_snapshot_storage_path
- device_id
- video_duration_ms
- upload_status
- created_at

## employee_devices

- id
- employee_id
- device_identifier_hash
- credential_id أو public_key
- device_name
- platform
- status
- registered_at
- last_used_at
- revoked_at

أنشئ Indexes وForeign Keys وRLS اللازمة.

# تخزين الفيديو

استخدم Bucket خاص Private مثل:

location-verification-videos

المسار:

organization/{organizationId}/employees/{employeeId}/requests/{requestId}/verification.mp4

ولقطة الخريطة:

location-map-snapshots/.../{requestId}/map.png

- لا تجعل الملفات Public.
- استخدم Signed URLs.
- اعرض الفيديو فقط للموظف نفسه والصلاحيات الإدارية المعتمدة.
- احذف فيديو التحقق ولقطة الخريطة آليًا بعد 24 ساعة.
- لا تحذف سجل الطلب والنتيجة النصية قبل مدة الاحتفاظ المعتمدة.
- عالج فشل الرفع وإعادة المحاولة.
- اعرض Upload progress.
- لا تعتبر الطلب Completed قبل نجاح حفظ DB والملفات.

# رحلة المدير التنفيذي اليومية

أنشئ أو أصلح شاشة تعرض كل موظفي الجمعية مع الحالة المحسوبة من الخادم:

- present
- late
- absent
- on_mission
- on_leave
- checked_out
- missing_checkout
- pending

اربط الحساب بـ:

- جدول الدوام.
- سجل الحضور.
- الانصراف.
- الإجازات المعتمدة.
- المأموريات المعتمدة.
- العطلات.
- timezone Africa/Cairo.

يجب فتح بروفايل الموظف وإظهار:

- حالة اليوم.
- سجل الحضور.
- سجل طلبات الموقع.
- آخر موقع تحقق.
- العنوان.
- لقطة الخريطة.
- فيديو التحقق إن لم تنتهِ مدة الاحتفاظ.
- وقت الطلب.
- وقت الاستجابة.
- الموظف الإداري الذي أرسل الطلب.
- حالة الفشل بصورة عربية واضحة.

# إصلاح سجل الطلبات

احذف النصوص العشوائية والرسائل التقنية مثل:

- VDXBCXCFB
- Bad state
- CameraException
- FunctionException
- PostgrestException

لا تعرض stack traces للمستخدم.

اعرض الحالات التالية بصورة مفهومة:

- في انتظار وصول الإشعار.
- تم تسليم الإشعار.
- فتح الموظف الطلب.
- جارٍ الحصول على الموقع.
- جارٍ تسجيل الفيديو.
- جارٍ الرفع.
- اكتمل التحقق.
- انتهت صلاحية الطلب.
- رفض الموظف الطلب.
- تعذر تشغيل الموقع.
- تعذر استخدام الكاميرا.

احفظ error_code تقنيًا في Logs فقط مع correlation_id.

# إصلاح UI/UX

- أزل «السبب:» من شاشة الفيديو.
- أزل أي خيارات أخرى غير «موقع + فيديو 5 ثوانٍ» لطلب المدير التنفيذي.
- استخدم SafeArea أعلى وأسفل.
- أضف bottom padding يساوي ارتفاع Bottom Navigation.
- لا تسمح للمحتوى أو الأزرار بالدخول خلف Bottom Bar.
- لا تعرض Snackbar يغطي الأزرار والبيانات.
- استخدم Dialog أو Banner قصير للأخطاء المهمة.
- أصلح تباين النصوص فوق الخلفية الزرقاء.
- أصلح البطاقات التي تتجاوز الشاشة.
- أصلح التفاف الأسماء والأكواد.
- استخدم صورة الموظف، وإن لم توجد استخدم Avatar منسقًا.
- اعرض Loading وEmpty وError وRetry states.
- اجعل الشبكة Responsive دون فراغات غير منطقية.
- لا تعرض أخطاء Dart أو Supabase أو Java للمستخدم.

# الأمان والصلاحيات

- المدير التنفيذي فقط والصلاحيات المعتمدة يمكنهم إرسال طلب الموقع.
- تحقق من الصلاحية على الخادم، وليس الواجهة فقط.
- الموظف لا يستطيع إرسال Response نيابة عن موظف آخر.
- اربط response بالطلب والمستخدم والجهاز.
- استخدم server timestamps.
- امنع تعديل الإحداثيات بعد إكمال الطلب.
- سجل Audit Events لجميع العمليات.
- لا تحفظ GPS أو فيديو دون طلب فعال وتفاعل صريح.
- لا ترسل مفاتيح Service Role داخل التطبيق.
- لا تجعل Storage Public.
- راجع RLS لكل الجداول الجديدة.
- امنع IDOR وتغيير request_id للوصول إلى طلبات موظف آخر.

# اختبارات قبول إلزامية

لا تعتبر العمل منتهيًا إلا بعد نجاح السيناريوهات التالية على هاتف حقيقي:

1. المدير التنفيذي يرى جميع الموظفين، ومنهم المدير يحيى.
2. يرسل طلبًا بدون سبب وبخيار موقع + فيديو 5 ثوانٍ فقط.
3. يصل الإشعار والتطبيق مفتوح.
4. يصل الإشعار والتطبيق في الخلفية.
5. يصل الإشعار بعد إغلاق التطبيق.
6. الضغط على الإشعار يفتح نفس الطلب.
7. عند إغلاق GPS تظهر مطالبة بفتحه ثم يستكمل الطلب.
8. الكاميرا الأمامية تفتح دون شاشة سوداء.
9. الصورة غير ممدودة.
10. يُسجل فيديو 5 ثوانٍ فعليًا دون صلاحية صوت.
11. يتم التقاط موقع حديث ودقيق.
12. تظهر خريطة وعنوان ولقطة خريطة.
13. يُرفع الفيديو بنجاح.
14. تظهر النتيجة فورًا عند المدير التنفيذي.
15. تظهر النتيجة داخل بروفايل الموظف.
16. يمكن إرسال طلب جديد بعد 30 ثانية دون إلغاء السابق.
17. تسجيل الجهاز والبصمة ينجح.
18. الحضور والانصراف بالبصمة ينجحان.
19. لا يظهر أي نص تقني أو Exception للمستخدم.
20. لا يغطي Bottom Bar أي محتوى أو زر.

# التحقق النهائي

نفّذ:

flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release --obfuscate --split-debug-info=build/symbols/<version>
flutter build apk --release --split-per-abi --obfuscate --split-debug-info=build/symbols/<version>-split
apksigner verify --verbose --print-certs <release-apk>

وشغّل اختبارات قاعدة البيانات والـEdge Functions.

قدّم في نهاية العمل فقط:

1. قائمة الملفات التي تم تعديلها.
2. أسماء SQL migrations المطبقة.
3. أسماء Edge Functions المعدلة.
4. السبب الجذري لكل عطل.
5. نتائج الاختبارات الفعلية.
6. لقطات أو Logs تثبت نجاح السيناريوهات.
7. أي نقطة لم تُختبر فعليًا مع توضيح صريح.

ممنوع كتابة «تم الإصلاح» دون دليل تشغيل فعلي End-to-End.

## قرار نهائي غير قابل للتغيير أثناء التنفيذ

- لا تحذف `USE_FULL_SCREEN_INTENT`.
- لا تلغِ شاشة الإشعار الكاملة الخاصة بطلب الموقع.
- لا تستبدلها بإشعار عادي فقط.
- فعّلها واختبرها في التوزيع الداخلي على Android 12 و13 و14 و15.
- عند منع Android لها على جهاز بعينه، استخدم Heads-up قوي كـFallback مع فتح شاشة الطلب الكاملة فور الضغط، وسجّل سبب عدم ظهور Full-screen.
- لا تستخدم Overlay سريًا، ولا تفتح الكاميرا أو تجمع الموقع قبل تفاعل الموظف ومنح الصلاحيات.

ابدأ الآن بالفحص والتنفيذ على كامل المشروع، ولا تتوقف عند إصلاح الواجهات فقط.