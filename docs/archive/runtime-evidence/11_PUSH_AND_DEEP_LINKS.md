# 11 — Push & Deep Links (P1.5–P1.6)

**التاريخ / Date:** 2026-07-15 (تحديث: نُشرت ملفات `.well-known` على Vercel)
**الحالة / Status:** 🟡 **PARTIAL** — ملفات Passkey/Deep-Link مُستضافة ومُتحقَّق منها حيًّا على نطاق Vercel؛
Push (FCM/APNs) وبصمة التوقيع الإنتاجية وTeam ID لـ iOS لا تزال محظورة (تتطلب حسابات/أجهزة خارجية).

---

## 0. ملفات `.well-known` — ✅ مُستضافة على Vercel ومُتحقَّق منها حيًّا (2026-07-15)

استُضيفت عبر `apps/admin_web/public/.well-known/` (يُنسخ إلى `dist/`)، مع ضبط `vercel.json`:
Content-Type = `application/json` لكليهما، واستثناء `.well-known` من SPA rewrite (تُخدَم مباشرة لا index.html).

| الملف | الرابط | التحقق الحي |
|---|---|---|
| `assetlinks.json` (Android) | `https://ahla-shabab-management-os.vercel.app/.well-known/assetlinks.json` | ✅ HTTP 200، `Content-Type: application/json`، package `org.ahlashabab.ahla_shabab_management_os` + بصمة SHA-256 **debug** |
| `apple-app-site-association` (iOS) | `https://ahla-shabab-management-os.vercel.app/.well-known/apple-app-site-association` | ✅ HTTP 200، `application/json`، بلا امتداد، bundle `org.ahlashabab.ahlaShababManagementOs` + `webcredentials` |

> **جاهز الآن:** Passkey على **الويب** يعمل مباشرة (RP_ID = `ahla-shabab-management-os.vercel.app`، مضبوط في أسرار Supabase — لا يحتاج ملف well-known).
> **قبل الإنتاج للموبايل يجب إكمال:**
> - `assetlinks.json`: إضافة بصمة SHA-256 لشهادة **الإصدار** + بصمة **Play App Signing** (الحالية = debug keystore فقط، تكفي لاختبار debug APK).
> - `apple-app-site-association`: استبدال `TEAMID` بمعرّف فريق Apple الحقيقي (غير متوفر — لا حساب Apple Developer/macOS).

## السبب (Push فقط — لا يزال محظورًا)

- **Push**: يتطلب Firebase/FCM (Android) وAPNs (iOS) + Provider Adapter + أجهزة فعلية لاستقبال الإشعارات.
- **Passkey domains / Deep Links**: يتطلب استضافة على نطاق HTTPS حقيقي:
  - `https://<RP_ID>/.well-known/assetlinks.json` (Android + SHA-256 لكل شهادات التوقيع بما فيها Play App Signing).
  - `https://<RP_ID>/.well-known/apple-app-site-association` + `webcredentials:<RP_ID>` (iOS).

## ما تم تجهيزه في الكود

- ✅ Deep-link intent-filter في AndroidManifest: `android:scheme="ahlashabab" android:host="action"`.
- ✅ iOS `CFBundleURLTypes` لـ scheme `ahlashabab` في Info.plist.
- ✅ دالة `webauthn-challenge` تُصدر تحديات صالحة لمرة واحدة بعمر محدود.
- ✅ `passkey-register` + `verify-attendance-punch` يتحققان من RP_ID وAllowed Origins.

## ما لا يمكن إثباته هنا

- تسجيل/استخدام Passkey على جهاز حقيقي.
- استلام Push + Badge reset + Deep Link إلى الشاشة الصحيحة.
- Deduplication + إلغاء Token عند الإبطال/الخروج.
- عدم وضع بيانات حساسة/إحداثيات في حمولة Push.

## المطلوب لفكّ الحظر

1. مشروع FCM + شهادة APNs + Push provider مضبوط عبر Secrets.
2. نطاق HTTPS يستضيف ملفَّي `.well-known`.
3. أجهزة Android/iOS فعلية.

> لم تُزيَّف أي نتيجة. بوابة خارجية تتطلب بنية تحتية غير متوفرة محليًا.
