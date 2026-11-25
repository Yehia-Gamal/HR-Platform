# 06 — Web Runtime and Visual QA (P0.8 / P2.3)

**التاريخ / Date:** 2026-07-14
**البيئة / Environment:** Windows 10 Pro, Node v24.18.0, Vite v8.1.4, Chrome 150 / Edge 150
**الحالة / Status:** ✅ البناء والفحوص الآلية ناجحة — ⚠️ Visual QA البشري على الأجهزة المستهدفة يتطلب مُراجعًا.

---

## 1. إعداد البيئة المحلية / .env.local

أُنشئ `apps/admin_web/.env.local` (غير متتبَّع، بلا أسرار — يستخدم مفتاح Supabase المحلي demo العام):

```dotenv
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_PUBLISHABLE_KEY=<LOCAL_PUBLISHABLE_KEY>
VITE_ENABLE_DEV_MOCKS=false
VITE_APP_VERSION=0.10.0
VITE_APP_BUILD=10
VITE_APP_ENVIRONMENT=development
```

## 2. Production Build (مُثبت)

جرى إثبات بناء الإنتاج ضمن `npm run check:all` (انظر `01_SOURCE_CHECKS.md`, `_check_all.log`):

```
> @ahla/admin-web build: tsc -b && vite build
vite v8.1.4 building client environment for production...
✓ 1925 modules transformed.
✓ built in ~1.39s
```

المخرجات (dist) — أحجام معقولة مع gzip:

| الملف | الحجم | gzip |
|---|---:|---:|
| index.html | 1.14 kB | 0.56 kB |
| index CSS | 52.80 kB | 10.76 kB |
| query.js | 43.19 kB | 13.10 kB |
| vendor.js | 70.63 kB | 19.00 kB |
| supabase.js | 203.60 kB | 52.06 kB |
| react-vendor.js | 282.97 kB | 91.42 kB |
| index.js | 336.17 kB | 71.42 kB |

- ✅ **صفر أخطاء TypeScript** (tsc -b).
- ✅ **أُصلح تحذير `INEFFECTIVE_DYNAMIC_IMPORT`:** أُنشئ `src/features/mock/loadDomainMocks.ts` — loader موحّد
  محروس بـ `import.meta.env.DEV` (يُستبدل بثابت وقت البناء)، فيُستبعد `domainMocks.ts` **كليًا** من حزمة الإنتاج
  (Dead-code elimination) بدل أن يُدمج فيها. جميع الاستدعاءات الثمانية حُوِّلت إلى الـ loader.
  فائدة إضافية: بيانات الـ mock لم تعد تُشحن للإنتاج إطلاقًا حتى لو فُعِّل `isMock` بخطأ.
- ✅ **23 اختبار Vitest ناجح** عبر 11 ملف (18 shared-contracts + 5 admin-web).

> ملاحظة تشغيلية: عند محاولة `npm run build` منفردًا لاحقًا في الجلسة ظهر فشل shell عابر
> (`operable program or batch file` / `tsc` مفقود) بسبب **إعادة تثبيت `node_modules` متزامنة** كانت تفرغ
> `node_modules/.bin` مؤقتًا — ليست مشكلة كود. البناء الموثّق أعلاه من `check:all` نظيف وحاسم.

## 3. Dev Server / التشغيل

- الأمر: `npm run dev:web` (Vite dev server، منفذ 5173).
- التطبيق يتصل بـ Supabase المحلي عبر `.env.local`.
- Routes وWorkspace Guards موجودة (App Shell، تنقّل حسب الدور والصلاحيات، بحث سريع، Dark Mode).

## 4. Visual QA — ما يتطلب مُراجعًا بشريًا (P2.3)

⚠️ **BLOCKED (بشري):** البنود التالية تتطلب فتح المتصفح ومعاينة بصرية على أجهزة مستهدفة، ولا يمكن
إثباتها آليًا في هذه البيئة دون مُراجع:

- RTL، Light/Dark، تكبير الخط، الشاشات الصغيرة، Overflow.
- Keyboard navigation، Loading/Empty/Error/Offline states.
- Contrast، TalkBack/VoiceOver، Reduced Motion.
- عدم إظهار مصطلحات تقنية للمستخدم النهائي.
- ظهور الصفحات حسب الدور فقط (بحسابات الأدوار المختلفة).

## 5. المطلوب لفكّ حظر Visual QA

1. `npm run dev:web` مع Supabase محلي فعّال + حسابات أدوار مبذورة.
2. مُراجع بشري على Chrome Desktop + Laptop صغير + محاكاة موبايل.
3. Screenshots توثيقية للحالات الحرجة دون بيانات حقيقية.

**النتيجة:** ✅ الويب يُبنى للإنتاج بنجاح (صفر أخطاء TS، 23 اختبار ناجح)؛ التشغيل المحلي جاهز.
Visual QA البشري يبقى بندًا مفتوحًا يتطلب مُراجعًا (ليس عيبًا في الكود).
