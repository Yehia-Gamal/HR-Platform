# 09 — iOS Device QA (P2)

**التاريخ / Date:** 2026-07-14
**الحالة / Status:** ⛔ **BLOCKED** — لا يوجد macOS/Xcode ولا جهاز iOS في بيئة Windows الحالية.

---

## السبب

بناء وتوقيع iOS يتطلب **macOS + Xcode**. البيئة الحالية Windows 10 Pro؛ لا يمكن تشغيل
`flutter build ios` / `flutter build ipa` ولا فتح مشروع Runner في Xcode.

## ما لا يمكن إثباته هنا

- `flutter build ios` / أرشيف iOS موقّع.
- Bundle ID + Associated Domains (`webcredentials:<RP_ID>`) + Entitlements.
- Passkey على جهاز iPhone فعلي.
- APNs Push + Deep Links على iOS.
- رحلات P2.2 على iPhone.

## المطلوب لفكّ الحظر

1. جهاز macOS مع Xcode (أو خدمة CI مثل macOS runner).
2. حساب Apple Developer + شهادات/Provisioning profiles.
3. استضافة `/.well-known/apple-app-site-association` على نطاق RP ID (انظر 11).
4. Supabase Staging + أسرار Push/Passkey.

> ملاحظة: مشروع `ios/` أُنشئ بنجاح عبر `flutter create` وسكربت `configure_flutter_platforms.py`
> أضاف أوصاف الاستخدام (Location/Camera/Mic) و`CFBundleURLTypes` لـ scheme `ahlashabab` في Info.plist.
> لكن البناء/التوقيع/الاختبار على جهاز فعلي محظور بيئيًا. لم تُزيَّف أي نتيجة.
