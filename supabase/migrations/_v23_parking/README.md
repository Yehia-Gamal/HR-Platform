# ملفات migration معلَّقة (parking)

ملفات وُقفت لتعارض ترقيم أو لأنها صارت متجاوَزة. **لا تُطبَّق** — مجلد خارج مسار
`supabase/migrations/` الذي يقرأه CLI والفاحص، ويُذكَر في فحص السلامة كتحذير فقط.

## `0523_fix_association_project_search_path_v2.sql` — 2026-09-19

**سبب التعليق:** تعارض رقم 0523 مع `0523_notifications_expose_metadata.sql`
(جلسة متوازية). الرقم 0523 مُسجَّل في الإنتاج فعلاً باسم
`notifications_expose_metadata.sql`، فلم يعد متاحاً لهذا الملف.

**لماذا لم يُعَد ترقيمه للأمام بدل التعليق:** محتواه **متجاوَز**. الملف يضبط
`search_path = public, auth, pg_temp` ويعيد تعريف `get_association_projects`
بلا `STABLE`. بينما الإنتاج الآن — بعد سلسلة الإصلاحات اللاحقة —يحمل الدالتين
`get_association_projects` و`get_association_project_detail` بالحالة:

```
provolatile = s (STABLE), proconfig = search_path=public, pg_temp
```

أي أن تطبيقه بأي رقم جديد **سيُرجِع الدالتين إلى حالة أقدم** (تراجع، لا إصلاح).

**الإجراء المطلوب:** يراجعه صاحب سلسلة `association_projects`؛ إن لم يعد له داعٍ
يُحذف نهائياً. لا تُعِد نقله إلى `supabase/migrations/` دون مقارنته بالتعريف
الحيّ في الإنتاج أولاً.
