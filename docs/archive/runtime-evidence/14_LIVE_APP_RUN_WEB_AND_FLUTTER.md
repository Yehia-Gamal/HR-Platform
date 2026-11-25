# 14 — تشغيل حيّ لبوابة الأدمن وتطبيق Flutter

**التاريخ / Date:** 2026-07-14
**البيئة / Environment:** Windows 10 Pro 19045 · Node v24 · Vite 8.1.4 · Flutter 3.32.8 (Chrome/Edge web)
**الحالة / Status:** ✅ **كلا التطبيقين يعملان حيًّا**

---

## 1. بوابة الأدمن (React / Vite) — ✅ RUNNING

```bash
cd apps/admin_web && vite   # server.port = 4173 (vite.config.ts)
```

- ✅ `VITE v8.1.4 ready in ~1.75s`
- ✅ يخدم على `http://localhost:4173/` — **HTTP 200**
- ✅ `/src/main.tsx` يُرجع JS مُترجمًا (خادم dev فعلي مع HMR، وليس preview)
- ✅ `index.html`: `lang="ar" dir="rtl"`، `id="root"`، `<script type="module" src="/src/main.tsx">`
- البيئة: `.env.local` → Supabase Staging (publishable key فقط، لا أسرار خادمية).

## 2. تطبيق Flutter — ✅ RUNNING (Chrome Web)

> لا جهاز Android/iOS فعلي في البيئة (Blocker موثّق)، فالهدف القابل للتشغيل هو Flutter Web
> على Chrome/Edge (كلاهما ظهر في `flutter devices`). APK Debug مبني بالفعل (انظر 07).

```bash
cd apps/mobile_flutter
flutter run -d chrome --web-port 4174 \
  --dart-define=SUPABASE_URL=<staging> \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable> \
  --dart-define=APP_ENVIRONMENT=staging \
  --dart-define=BYPASS_RELEASE_GATE=true   # مخرج غير-إنتاجي لمعاينة الواجهة (AppConfig.releaseGateBypassed)
```

- ✅ تجميع dart2js ناجح، الاتصال بخدمة التصحيح: `ws://127.0.0.1:11263`
- ✅ يخدم على `http://localhost:4174/` — **HTTP 200**
- ✅ `supabase.supabase_flutter: INFO: ***** Supabase init completed *****`
- ✅ شاشة الدخول ظهرت وتفاعلت: التطبيق نفّذ مسار **تسجيل الدخول متعدد المعرّفات** فعليًا
  (استدعاءات حيّة لـ Edge Function `identifier-sign-in`).

## 3. الملاحظات الصادقة (ليست عيوبًا في الكود)

- استدعاء `identifier-sign-in` يُرجع `ClientException: Failed to fetch` لأن الوظيفة **غير منشورة/غير
  قابلة للوصول** على مشروع Staging من أصل المتصفح `localhost:4174` (بوابة نشر Staging — Blocker موثّق
  في `10_STAGING_DEPLOYMENT.md` و`04_EDGE_FUNCTION_SMOKE_TESTS.md`). هذا يثبت أن الواجهة تُصيّر،
  وتقبل الإدخال، وتُوصّل مسار الدخول إلى الشبكة فعليًا.
- التحقق من الأدوار الكاملة (موظف/مدير/HR/تنفيذي/أدمن) عبر تسجيل دخول حقيقي يتطلب نشر Edge Functions
  على Staging + حسابات بذور — مغطّى ببوابة Staging، وليس محليًا.

## 4. الخلاصة

| التطبيق | المنفذ | الحالة |
|---|---|---|
| Admin Web (React) | `:4173` | ✅ يعمل — HTTP 200، dev server + HMR |
| Flutter (Chrome web) | `:4174` | ✅ يعمل — Supabase init، شاشة دخول تفاعلية |
| Flutter Debug APK | — | ✅ مبني مسبقًا (~238MB، انظر 07) |
