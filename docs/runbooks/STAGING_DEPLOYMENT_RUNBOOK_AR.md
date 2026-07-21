# تشغيل بيئة Staging

## بوابات إلزامية قبل النشر

1. تدوير جميع الأسرار القديمة وعدم نقل أي قيمة من النظام السابق.
2. إنشاء مشروع Supabase منفصل لـStaging.
3. ضبط أسرار Edge Functions: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `ALLOWED_ORIGINS`, `CRON_SECRET`, إعدادات WebAuthn، وموصل Push.
4. تشغيل `supabase db reset` ثم `supabase test db` محليًا أو داخل CI.
5. ربط المشروع: `supabase link --project-ref <STAGING_REF>` ثم `supabase db push`.
6. نشر Edge Functions كل واحدة باسمها، ثم تشغيل اختبارات Smoke.
7. بناء React بمتغيرات Staging و`VITE_ENABLE_DEV_MOCKS=false`.
8. بناء Flutter باستخدام `--dart-define` وعدم تضمين Service Role.
9. إنشاء حسابات Persona تجريبية: موظف، مدير، HR، سكرتير تنفيذي، مدير تنفيذي، أدمن، عضو لجنة.
10. اختبار RLS بطلبات API مباشرة قبل إعطاء البيئة للمستخدمين.

## الوظائف المجدولة

- `scheduled-report-runner`: استدعاء دوري مع `x-cron-secret`.
- `notification-dispatcher`: استدعاء كل عدة دقائق مع نفس آلية الحماية.
- وظائف Retention للفيديو والمستندات المؤقتة يجب ربطها قبل الإنتاج.

## بوابة الإطلاق

لا يتم التحويل إلى Production إذا فشل أي من: migrations، RLS personas، WebAuthn على هاتف فعلي، GPS والكاميرا، النسخ الاحتياطي والاستعادة، أو وجود مشكلة P0/P1 مفتوحة.

## الاحتفاظ والحذف التلقائي

- انشر `retention-cleanup` واضبط `CRON_SECRET` داخل Supabase Secrets.
- استدعِ الوظيفة دوريًا مع `x-cron-secret` مرة كل ساعة على الأقل.
- الوظيفة تحذف فيديوهات التحقق بعد 24 ساعة، ما لم يكن عليها `Legal Hold` ساريًا.
- تسجل عملية الحذف داخل `live_location_video_access_logs`، وتنظف تحديات WebAuthn وطلبات إعادة التعيين والـQueues القديمة.
- اختبر الحذف على Staging بملف تجريبي قبل تفعيل الجدولة في Production.

## نشر آلي إلى Staging

يمكن استخدام السكربت التالي بعد ضبط المتغيرات محليًا وعدم وضعها داخل Git:

```bash
CONFIRM_STAGING=YES \
STAGING_PROJECT_REF=... \
VITE_SUPABASE_URL=... \
VITE_SUPABASE_PUBLISHABLE_KEY=... \
./scripts/deploy-staging.sh
```

## نشر الواجهة (React) على Vercel

`deploy-staging.sh` ينشر الـbackend ويبني الواجهة، لكنه لا يرفعها لأي مضيف.
رفع الواجهة يتم على Vercel وفق دليل مستقل: `VERCEL_FRONTEND_DEPLOYMENT_AR.md`.

التسلسل الصحيح:
1. انشر الـbackend أولًا عبر `deploy-staging.sh` (link + db push + edge functions).
2. ثم اربط Vercel بالـrepo واضبط متغيرات `VITE_*` (بلا أي سر خادمي).
3. بعد أول نشر، خذ نطاق Vercel وضعه في `ALLOWED_ORIGINS` و`WEBAUTHN_RP_ID` داخل Supabase Secrets (CORS + Passkey).
4. تحقّق من الـSPA rewrites (تحديث مسار داخلي مثل `/hr/employees` بلا 404) ومن نجاح نداء RPC بلا خطأ CORS.

`vercel.json` بجذر المشروع يضبط أمر البناء (`npm run build`)، مجلد الإخراج (`apps/admin_web/dist`)،
وإعادة توجيه كل المسارات إلى `index.html` (ضروري لأن الواجهة تستخدم `BrowserRouter`).

## حوكمة الإصدار والوصول والتكاملات

- انشر `integration-outbox-worker` بالإضافة إلى بقية الوظائف.
- اضبط `VITE_APP_VERSION`, `VITE_APP_BUILD`, `VITE_APP_ENVIRONMENT=staging` أثناء بناء الويب.
- مرر `--dart-define=APP_ENVIRONMENT=staging` لبناء Flutter.
- شغّل `integration-outbox-worker` كل 1–5 دقائق و`retention-cleanup` كل ساعة.
- نفّذ سيناريوهات `RELEASE_ACCESS_PRIVACY_GOVERNANCE_AR.md` قبل اعتماد Staging.
