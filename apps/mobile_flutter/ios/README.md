# حالة دعم iOS (غير مدعوم حالياً في الإنتاج)

التطبيق موجّه حالياً رسمياً إلى أجهزة **Android** عبر حزم APK الموزّعة داخلياً، بينما **بناء iOS غير مفعّل ولا مدعوم حالياً** للأسباب التالية:

1. غياب ملف تهيئة Firebase الخاص بـ iOS (`ios/Runner/GoogleService-Info.plist`).
2. غياب ملف صلاحيات Xcode (`ios/Runner/Runner.entitlements`) ومفتاح `aps-environment` الخاص بإشعارات APNs الفورية.
3. عدم ربط حساب Apple Developer Team وشهادات التوقيع/APNs في Firebase Console.

## خطوات التفعيل مستقبلاً عند الحاجة لدعم iPhone
1. إضافة `GoogleService-Info.plist` داخل `ios/Runner/` (خارج Git ومُدرج في `.gitignore`).
2. إنشاء `ios/Runner/Runner.entitlements` متضمناً `aps-environment` وربطه في إعدادات Xcode target.
3. تفعيل قدرات **Push Notifications** و**Background Modes (`remote-notification`, `fetch`)** ورفع مفتاح APNs إلى Firebase.
4. اختبار استقبال الإشعارات العاجلة والبصمة والموقع على جهاز iPhone فعلي قبل النشر.
