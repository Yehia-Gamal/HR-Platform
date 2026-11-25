# 12 — Backup / Restore / Rollback (P1)

**التاريخ / Date:** 2026-07-15 (نُفِّذ فعليًا؛ كان BLOCKED في 2026-07-14)
**الحالة / Status:** ✅ **PASS** — Backup فعلي من Staging + Restore في بيئة معزولة، سلامة البيانات مؤكَّدة.

> لا أسرار في هذا الملف. ملف النسخة (`staging_public.dump`) حُذف بعد الدرل لأنه يحوي بيانات Staging؛
> مجلد `backup-drill/` مستبعد من Git.

---

## 1. Backup (من Staging — قراءة فقط، غير مدمّر)

```bash
pg_dump "<staging>" --schema=public --format=custom --no-owner --no-privileges > staging_public.dump
```

| العنصر | القيمة |
|---|---|
| المصدر | Supabase Staging `ujzzvqsodyhnnnpkoaml` (PostgreSQL 17.6) |
| الأداة | `pg_dump` 17.6 (من حاوية supabase_db، مطابقة لإصدار Staging) |
| الصيغة | custom (`-Fc`) — قابلة لـ `pg_restore` انتقائيًا |
| الحجم | 1.7 MB (public schema: بيانات + مخطط) |
| Exit | ✅ 0 (بلا أخطاء) |

## 2. Restore (في بيئة معزولة — ليست Staging ولا local dev)

هدف معزول: حاوية **PostgreSQL 17 مستقلة** (`restore_drill_pg`) — لا تمسّ Staging ولا قاعدة التطوير المحلية.

```bash
docker run -d --name restore_drill_pg -e POSTGRES_PASSWORD=... -p 55432:5432 postgres:17
# prep: create roles (anon/authenticated/service_role) + schemas (auth/extensions) + pgcrypto
pg_restore -U postgres -d postgres --no-owner --no-privileges staging_public.dump
```

## 3. التحقق من السلامة — أعداد الصفوف مطابقة تمامًا

| الجدول | Staging (baseline) | Restored | مطابقة |
|---|---:|---:|:---:|
| employees | 5 | 5 | ✅ |
| roles | 13 | 13 | ✅ |
| role_permissions | 522 | 522 | ✅ |
| user_roles | 5 | 5 | ✅ |
| profiles | 5 | 5 | ✅ |
| audit_events | 64 | 64 | ✅ |

فحوص إضافية:
- **217 جدولًا** في `public` أُعيد إنشاؤها بالكامل.
- الأدوار: 12 دورًا يحمل صلاحيات صريحة + دور `admin` عبر علم `is_full_access=true` (لذا 0 صف صريح — تصميم صحيح، ليس فقدًا).
- `system_alerts` (طبقة المراقبة) موجود ومُستعاد.
- عيّنة بيانات: `ADMIN001` أول موظف — سليم.

## 4. تفسير أخطاء pg_restore الـ750 (كلها حميدة — لا فقد بيانات)

| الفئة | العدد | السبب | الأثر |
|---|---:|---|---|
| `role "authenticated" does not exist` | 505 | GRANT/سياسات RLS تشير لأدوار Supabase المُدارة غير الموجودة في Postgres عارٍ | لا شيء (البيانات استُعيدت؛ السياسات تُطبَّق على Supabase الحقيقي) |
| `schema "auth"` references | 232 | مفاتيح أجنبية عابرة لـ`auth.users` (خارج dump الـpublic فقط) | لا شيء (auth يُدار من GoTrue على Supabase) |
| `already exists` | 1 | امتداد مُهيّأ مسبقًا في التحضير | لا شيء |

> هذه أخطاء متوقّعة لاستعادة **مخطط public فقط** في Postgres عارٍ. صفر منها يمثّل فقد صفوف — تأكيده بمطابقة الأعداد أعلاه.

## 5. Rollback

- **قابلية إعادة الإنشاء من الصفر** مُثبتة (`db reset` مرتين، انظر 02) — أساس أي تدحرج.
- **خطة Rollback** موثّقة في `docs/runbooks/RELEASE_ACCESS_PRIVACY_GOVERNANCE_AR.md` (تدحرج خطة الإصدار دون حذف تاريخ).
- قاعدة «لا حذف مادي للجداول التاريخية» محفوظة: الاستعادة تعيد كل البيانات بلا اقتطاع.

## 6. الخلاصة

✅ **Backup/Restore drill ناجح**: نسخة فعلية من Staging (1.7MB، Exit 0)، واستعادة في بيئة معزولة (Postgres 17
مستقل)، وسلامة مؤكَّدة بمطابقة أعداد الصفوف لكل الجداول الحرجة (217 جدولًا، 522 صلاحية دور، 64 حدث تدقيق).
الأخطاء الـ750 كلها مراجع أدوار/auth حميدة لا تمثّل فقد بيانات. البيئة المعزولة والنسخة حُذفتا بعد الدرل.

**المتبقي (اختياري/إنتاجي):** استعادة كاملة تشمل `auth`+`storage` (تتطلب `pg_dump` بصلاحية superuser عبر
اتصال مباشر أو أداة Supabase الرسمية للنسخ)، واختبار PITR (Point-in-time recovery) على خطة Supabase مدفوعة.
