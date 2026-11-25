# BASELINE.md — نقطة الانطلاق V18

**التاريخ:** 2026-07-25
**الفرع:** `codex/v17-master-plan`
**المرجع:** AHLA_SHABAB_MASTER_PLAN_V18.md §26 — المرحلة 0

---

## ملخص الفحص الشامل

| الفحص | النتيجة | التفاصيل |
|---|---|---|
| Migration numbering | ✅ نظيف | 143 ملف (0001–0143)، لا تكرارات |
| TypeScript `tsc --noEmit` | ✅ نظيف | 0 أخطاء |
| Web build (`npm run build`) | ✅ نظيف | vite 8.1.4، 1990 module |
| Vitest — shared-contracts | ✅ 90/90 | 17 ملف اختبار |
| Vitest — admin-web | ✅ 32/32 | 8 ملفات اختبار |
| Flutter analyze | ✅ نظيف | 8 infos فقط (لا أخطاء ولا تحذيرات) |
| Staging max migration | 0141 | 0142–0143 محلية فقط |

## الأرقام الحالية

| المكوّن | العدد |
|---|---|
| Migrations | 143 (0001–0143) |
| pgTAP test files | 60 |
| pgTAP assertions | ~810 |
| Edge Functions | 12 + `_shared/` |
| Flutter pages | ~42 |
| Web feature dirs | 13 |
| Web source files | ~98 |
| Shared contracts (Zod) | 18 |

## الإصلاحات المطبّقة خلال التدقيق

1. **`mobile_kpi_page.dart`** — إضافة import مفقود لـ `connectivity_service.dart` و `mobile_models.dart` (كان يسبب خطأ `humanizeError` و `MobileKpiEvaluation` غير معرّف)
2. **حذف مجلدات worktree قديمة** — `.claude/worktrees/` (7 مجلدات) كانت تسبب التقاط vitest لـ 185 ملف اختبار بدلاً من 43

## المرحلة التالية

المرحلة 1 — P0 (أسابيع 2–6): تسجيل جهاز، حضور، طلبات، KPI، موقع حي.
