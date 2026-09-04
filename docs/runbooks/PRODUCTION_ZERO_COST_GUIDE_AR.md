# دليل تشغيل ونشر المنظومة الإنتاجية بنسبة 100% بدون أي تكلفة مالية (Zero-Cost Production Runbook)

هذا الدليل يشرح بالتفصيل كيفية تفعيل وتشغيل كافة خدمات منظومة «أحلى شباب HR» في بيئة الإنتاج الميدانية الحقيقية **دون دفع دولار واحد** لأي شركة خارجية، مع ضمان استقرار وأمان المنظومة بالكامل.

---

## 1. تفعيل WhatsApp Business Cloud API مجاناً (1,000 محادثة شهرياً للأبد)

توفر شركة **Meta (فيسبوك)** لكل حساب أعمال شريحة مجانية دائمة تشمل **1,000 محادثة خدمة شهرية مجانية**.

### خطوات التفعيل في 5 دقائق:
1. اذهب إلى [Meta for Developers](https://developers.facebook.com/) وسجل الدخول بحساب فيسبوك مجاني.
2. أنشئ تطبيقاً جديداً من نوع **Business** باسم `Ahla Shabab HR`.
3. من لوحة التطبيق، اختر منتج **WhatsApp** واضغط **Set up**.
4. ستحصل فوراً على:
   - **Phone Number ID**: رقم المعرف المجاني للاختبار والتشغيل.
   - **Temporary Access Token**: توكن الاتصال.
5. لربط رقم هاتفك الخاص بالشركة مجاناً:
   - انتقل إلى **API Setup > Step 5: Add a phone number**.
   - أدخل رقم هاتف مخصص للمنظومة واستقبل كود التحقق SMS لتوثيقه.
6. انسخ هذه المتغيرات إلى إعدادات Supabase Edge Functions:
   ```bash
   WHATSAPP_PHONE_NUMBER_ID="your_phone_id"
   WHATSAPP_ACCESS_TOKEN="your_meta_system_user_token"
   ```

---

## 2. الإشعارات الفورية غير المحدودة عبر Firebase Cloud Messaging (FCM v1)

خدمة **Firebase Cloud Messaging** من Google مجانية 100% بدون أي حدود على عدد الإشعارات أو الأجهزة.

### خطوات التفعيل:
1. اذهب إلى [Google Firebase Console](https://console.firebase.google.com/) وأنشئ مشروعاً مجانياً باسم `ahla-shabab-hr`.
2. أضف تطبيق Android وأدخل Package Name: `org.ahla_shabab.hr`.
3. حمّل ملف `google-services.json` وضعه داخل مجلد:
   `apps/mobile_flutter/android/app/google-services.json`.
4. من إعدادات المشروع (Project Settings > Service Accounts)، اضغط **Generate New Private Key**.
5. حمّل ملف الـ JSON وانسخ محتواه إلى متغير Supabase:
   ```bash
   FCM_PROJECT_ID="ahla-shabab-hr"
   FCM_SERVICE_ACCOUNT_JSON='{"type": "service_account", ...}'
   ```
الآن كل إشعارات الورديات والقرارات والإجازات ستصل للموظفين فورياً في أجزاء من الثانية مجاناً للأبد.

---

## 3. ربط النطاق الخاص (Custom Domain) وحماية الـ CDN مجاناً عبر Cloudflare

توفر **Cloudflare** باقة مجانية دائمة تقدم:
- شهادات أمان **SSL/TLS مجانية ومجددة تلقائياً**.
- حماية ضد هجمات حجب الخدمة **DDoS Protection**.
- تسريع التصفح عبر شبكة توصيل المحتوى العالمية **Global CDN**.

### خطوات الربط:
1. سجل حساباً مجانياً على [Cloudflare](https://www.cloudflare.com/).
2. أضف اسم النطاق الخاص بك (مثلاً: `yourdomain.com`).
3. غيّر الـ Nameservers في موقع حجز الدومين إلى خوادم Cloudflare المجانية الموضحة.
4. في قسم **DNS Records** في Cloudflare، أضف السجلات التالية:
   - للويب الإداري (المستضاف على Vercel):
     - `Type: CNAME` | `Name: hr` | `Target: cname.vercel-dns.com` | `Proxy status: Proxied (سحابة برتقالية)`
   - سيصبح رابط النظام الإداري رسمياً: `https://hr.yourdomain.com` ومحمياً بأعلى درجات التشفير مجاناً.

---

## 4. النسخ الاحتياطي اللحظي لقاعدة البيانات (PITR Alternative) مجاناً عبر GitHub Actions

بدلاً من الاشتراك في باقات قواعد البيانات الباهظة، تم إعداد سير عمل آلي ومجاني بالكامل يقوم بأخذ نسخة احتياطية يومية من قاعدة بيانات Supabase وضغطها وتشفيرها:

### طريقة العمل:
- يعمل سكربت مجاني في الخلفية عبر **GitHub Actions Scheduled Cron** كل 24 ساعة في منتصف الليل.
- يقوم بتصدير الـ Schema وكافة جداول المنظومة بصيغة `.sql.gz`.
- يتم حفظ النسخة في مستودع GitHub الخاص بك أو في Google Drive مجاناً مع الاحتفاظ بسجل آخر 30 يوماً من النسخ الاحتياطية تلقائياً.

---

## 5. رفع تطبيق الموبايل إلى متجري Google Play و Apple App Store

### المتطلبات المجهزة تلقائياً في المنظومة:
1. **صفحة سياسة الخصوصية الرسمية:** متاحة مباشرة على الرابط: `https://hr.yourdomain.com/privacy`.
2. **صفحة شروط الاستخدام:** متاحة على الرابط: `https://hr.yourdomain.com/terms`.
3. **أمر بناء الحزمة لمتجر Google Play:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/build-mobile-release.ps1 -Target android
   ```
   سيتم إنشاء ملف `app-release.aab` في مجلد `build/app/outputs/bundle/release/` جاهزاً للرفع المباشر على Google Play Console.

4. **بناء حزمة iOS:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/build-mobile-release.ps1 -Target ios
   ```
