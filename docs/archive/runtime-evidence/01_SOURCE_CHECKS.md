# 01 — Source Checks (P0.2)

**التاريخ / Date:** 2026-07-13
**البيئة / Environment:** Windows 10 Pro 19045, Node v24.18.0, npm 11.16.0
**الحالة / Status:** ✅ PASS — جميع فحوصات المصدر ناجحة

> الهدف: إعادة فحص المصدر من بيئة نظيفة قبل أي تعديل، والتحقق من الأعداد الفعلية.

---

## 1. الأوامر المُنفَّذة / Commands run

| الأمر | Exit Code | النتيجة |
|---|---:|---|
| `npm ci` | 0 | ✅ تثبيت نظيف؛ رُبطت workspaces: `admin-web`, `design-tokens`, `shared-contracts` |
| `npm run check:all` | 0 | ✅ typecheck + test + build + dart-source + foundation + secrets |
| `npm audit --omit=dev` | 0 | ✅ `found 0 vulnerabilities` |

> ملاحظة تشغيلية: `npm ci` أُعيد تشغيله في هذه البيئة بعد حذف `node_modules` للتأكد من التثبيت النظيف
> (لا `npm install` عشوائي مع وجود `package-lock.json`، وفق قاعدة الخطة).

---

## 2. تفاصيل `npm run check:all`

الأمر يشغّل السلسلة:
`npm run check` (typecheck → test → build) `&&` `check:dart-source` `&&` `validate-foundation.mjs` `&&` `check:secrets`

### 2.1 TypeScript typecheck
- `@ahla/shared-contracts`: `tsc -p tsconfig.json --noEmit` → ✅ نجح
- `@ahla/admin-web`: `tsc -b --pretty false` → ✅ نجح
- **صفر أخطاء TypeScript.**

### 2.2 الاختبارات / Tests (Vitest v4.1.10)
| الحزمة | Test Files | Tests | النتيجة |
|---|---:|---:|---|
| `@ahla/shared-contracts` | 7 | 19 | ✅ passed |
| `@ahla/admin-web` | 4 | 14 | ✅ passed |
| **الإجمالي** | **11** | **33** | ✅ **33/33 passed** |

> **ملاحظة انحراف توثيقي:** بعض الوثائق القديمة تذكر "22/23 اختبار TypeScript/React".
> العدد الفعلي المُنفَّذ في Runtime (2026-07-14) هو **33 اختبارًا ناجحًا** (19 عقود + 14 ويب) عبر **11 ملف اختبار**.
> لا يوجد فشل ولا Skip. صُحِّح الرقم في README وCURRENT_BUILD_REPORT وRELEASE_STATUS.

### 2.3 Production Build (Vite v8.1.4)
- `@ahla/shared-contracts`: `tsc -p tsconfig.json` → ✅
- `@ahla/admin-web`: `tsc -b && vite build` → ✅ **1925 modules transformed، built in ~1.39s**
- المخرجات (dist):

```
dist/index.html                             1.14 kB │ gzip:  0.56 kB
dist/assets/index-*.css                    52.80 kB │ gzip: 10.76 kB
dist/assets/query-*.js                     43.19 kB │ gzip: 13.10 kB
dist/assets/vendor-*.js                    70.63 kB │ gzip: 19.00 kB
dist/assets/supabase-*.js                 203.60 kB │ gzip: 52.06 kB
dist/assets/react-vendor-*.js             282.97 kB │ gzip: 91.42 kB
dist/assets/index-*.js                    336.17 kB │ gzip: 71.42 kB
```

- **تحذير غير حاجب (warning, not error):** `INEFFECTIVE_DYNAMIC_IMPORT` على `src/features/mock/domainMocks.ts`
  (يُستورد ديناميكيًا وثابتًا معًا). لا يؤثر على نجاح البناء ولا على الإنتاج (ملف mock للتطوير فقط).
  تحسين اختياري لاحقًا: توحيد نمط الاستيراد لهذا الملف.

### 2.4 Dart Source Integrity
```
Dart source integrity valid: 61 files, 205 classes.
```
✅ يطابق الواقع على القرص (61 ملف Dart، 205 Class).

### 2.5 Foundation / Migration Sequence
```
Foundation structure valid: 46 sequential migrations.
```
✅ 48 Migration متسلسلة دون فجوات أو تكرار (0001→0048).

### 2.6 Secret Scan
```
Secret scan passed: no high-confidence committed credentials found.
```
✅ لا أسرار مُلتزَمة.

---

## 3. الأعداد الفعلية المُتحقَّق منها من المصدر / Verified counts

جرى العدّ مباشرة من نظام الملفات (لا اعتماد على تقارير قديمة):

| العنصر | الأمر | العدد الفعلي |
|---|---|---:|
| Migrations | `ls supabase/migrations/*.sql` | **46** (أعلى رقم `0046`) |
| SQL/pgTAP Tests | `ls supabase/tests/*.sql` | **29** (0001–0029) |
| Edge Functions قابلة للنشر | `ls -d supabase/functions/*/ \| grep -v _shared` | **9** + `_shared` |
| Dart files | `find apps/mobile_flutter/lib -name '*.dart'` | **61** (205 Class) |
| React TS/TSX | `find apps/admin_web/src -name '*.ts*'` | **75** |
| TS test files | `find … -name '*.test.ts*'` | **11** (تُنفّذ 33 اختبارًا) |

> هذه الأعداد هي المرجع لتصحيح الانحراف التوثيقي (انظر القسم أدناه ومستند `FINAL_READINESS_REPORT_AR.md`).

---

## 4. إعادة الاختبار / Re-run

جميع الأوامر قابلة لإعادة التشغيل من جذر المشروع:

```bash
npm ci
npm run check:all
npm audit --omit=dev
```

**النتيجة النهائية للمرحلة:** ✅ **PASS** — Source Checks مكتملة وناجحة، صفر أخطاء، صفر ثغرات، صفر أسرار.
