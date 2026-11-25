# 00 — Environment and Tool Versions

**التاريخ / Date:** 2026-07-13
**البيئة / Host:** محطة تطوير محلية / Local developer workstation
**المشروع / Project:** Ahla Shabab Management OS V8 — Build 0.10.0
**مسار المشروع / Project path:** `d:\Coder\HR\HR_Platform_2`

> ملاحظة: هذا الملف يوثّق البيئة الفعلية التي جرى فيها التشغيل والإثبات. لا يحتوي على أي أسرار أو مفاتيح.

---

## 1. نظام التشغيل / Operating System

| العنصر | القيمة |
|---|---|
| OS Name | Microsoft Windows 10 Pro |
| OS Version | 10.0.19045 Build 19045 (22H2) |
| Architecture | x64 |
| Shell used | Git Bash (POSIX sh) |

## 2. سلسلة أدوات JavaScript / Node toolchain

| الأداة | الإصدار المكتشف | المطلوب في الخطة | الحالة |
|---|---|---|---|
| Node.js | `v24.18.0` | `>=22.12` | ✅ يتجاوز الحد الأدنى |
| npm | `11.16.0` | حديث | ✅ |
| Git | `2.55.0.windows.1` | مطلوب | ✅ |

> ملاحظة: `package.json` يحدد `engines.node >= 22.12.0`. الإصدار الحالي 24.18.0 يستوفي الشرط.

## 3. Supabase / Docker

| الأداة | الإصدار المكتشف | ملاحظة |
|---|---|---|
| Supabase CLI (`npx supabase`) | `2.109.1` | مثبّت كتبعية dev في `node_modules` (devDependency `supabase@^2.109.1`) |
| Docker CLI | `29.6.1` (build 8900f1d) | العميل مثبّت |
| Docker Desktop | مثبّت في `C:\Program Files\Docker\Docker\Docker Desktop.exe` | ✅ موجود |
| Docker daemon (وقت البدء) | **متوقف** عند بدء الجلسة | يُشغّل يدويًا لتنفيذ مراحل قاعدة البيانات — انظر 02/03/04/05 |

## 4. Flutter / Dart / Android

| الأداة | الإصدار المكتشف | المطلوب | الحالة |
|---|---|---|---|
| Flutter | `3.32.8` (channel stable, revision edada7c56e) | Stable | ✅ |
| Dart | `3.8.1 (stable) windows_x64` | `>=3.8` | ✅ |
| Android SDK | `36.0.0` (عبر flutter doctor) | مطلوب | ✅ |
| `ANDROID_HOME` | `C:\Users\Elhamd\AppData\Local\Android\Sdk` | مضبوط | ✅ |
| Android Studio | `2025.1.2` | مطلوب لبناء Android | ✅ |
| JDK (نظام / system `java`) | `1.8.0_251` | JDK 17+ لبناء Android | ⚠️ قديم جدًا — لا يُستخدم للبناء |
| JDK (Android Studio JBR) | OpenJDK `21.0.6` (2025-01-21) في `C:\Program Files\Android\Android Studio\jbr` | JDK 17+ | ✅ Gradle يستخدم هذا الـ JBR تلقائيًا |

> **قرار مهم:** الـ `java` الافتراضي على النظام هو 1.8 وهو غير كافٍ لبناء Android عبر Gradle الحديث.
> ومع ذلك فإن Flutter/Gradle يعتمد افتراضيًا على الـ JDK المرفق مع Android Studio (JBR 21)،
> لذا فإن بناء Android APK ممكن دون الحاجة لتغيير `java` النظامي.

## 5. الويب / متصفحات / Web browsers

| العنصر | القيمة |
|---|---|
| Google Chrome | `150.0.7871.101` (مكتشف بواسطة flutter devices) |
| Microsoft Edge | `150.0.4078.65` |
| Chrome exe | موجود في `C:\Program Files\Google\Chrome\Application\chrome.exe` |

## 6. الأجهزة المتصلة / Connected devices (flutter devices)

```
Windows (desktop) • windows • windows-x64    • Microsoft Windows [Version 10.0.19045.6466]
Chrome (web)      • chrome  • web-javascript • Google Chrome 150.0.7871.101
Edge (web)        • edge    • web-javascript • Microsoft Edge 150.0.4078.65
```

> **لا يوجد جهاز Android/iOS فعلي أو محاكي متصل.** أجهزة الاختبار الفعلية (Passkey/GPS/Camera/Push)
> موثّقة كـ **BLOCKED** في `08_ANDROID_DEVICE_QA.md` و`09_IOS_DEVICE_QA.md`.

## 7. flutter doctor (ملخص)

```
[√] Flutter (Channel stable, 3.32.8, Windows 10 Pro 19045, en-US)
[√] Windows Version (10 Pro 64-bit, 22H2)
[√] Android toolchain — Android SDK 36.0.0
[√] Chrome — develop for the web
[X] Visual Studio — not installed (مطلوب فقط لتطبيقات Windows الأصلية — غير مطلوب لهذا المشروع)
[√] Android Studio (2025.1.2)
[√] VS Code
[√] Connected device (3 available)
[√] Network resources
```

> الفشل الوحيد هو Visual Studio لتطوير تطبيقات Windows الأصلية، وهو **غير ذي صلة** بهذا المشروع
> (الأهداف: Android + iOS + Web). لا يؤثر على أي بوابة تشغيل.

## 8. القيود المعروفة في هذه البيئة / Known environment constraints

| القيد | الأثر | البوابات المتأثرة |
|---|---|---|
| لا يوجد جهاز Android/iOS فعلي أو محاكي | لا يمكن اختبار Passkey/GPS/Camera/Push على جهاز | P2 (08, 09, 11) |
| لا يوجد macOS/Xcode | لا يمكن بناء أو توقيع iOS | P0.7 (iOS), P2 (09) |
| لا يوجد Supabase Staging project أو أسرار | لا يمكن تنفيذ نشر Staging | P1 (10) |
| لا يوجد إعداد نسخ احتياطي/استعادة على بيئة حقيقية | لا يمكن تنفيذ Backup/Restore drill | P3 (12) |
| لا مُراجع بشري على أجهزة مستهدفة | Visual QA البشري غير مكتمل | P2.3 (06 جزئيًا) |

جميع هذه القيود مُسجّلة كـ **BLOCKED** مع بيان السبب والمطلوب لفكّها، ولم تُزيَّف أي بوابة على أنها ناجحة.
