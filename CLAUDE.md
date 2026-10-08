# CLAUDE.md — Ahla Shabab Management OS

## المشروع

منصة إدارة موارد بشرية وتشغيل لجمعية أحلى شباب. عربية بالكامل (RTL).
Monorepo يضم تطبيق ويب (React) وتطبيق موبايل (Flutter) وباك إند (Supabase).

## هيكل المستودع

```
apps/admin_web/        — React 19 + Vite + Tailwind + TanStack Query
apps/mobile_flutter/   — Flutter 3 + Riverpod
packages/shared-contracts/  — Zod schemas مشتركة (web + edge functions)
packages/design-tokens/     — متغيرات التصميم
supabase/migrations/   — 200 migration (PostgreSQL)
supabase/tests/        — 83 pgTAP test file
supabase/functions/    — 12 Edge Function + _shared/
scripts/               — أدوات بناء وتحقق
.github/workflows/     — CI/CD (web, flutter, supabase, release, security)
```

## أوامر سريعة

```bash
# فحص شامل (typecheck + test + build + dart-source + secrets)
npm run check:all

# ويب فقط
npm run dev:web                    # Vite dev server
npm run build                      # بناء الإنتاج
npm run test                       # Vitest (web + contracts)
npm run typecheck                  # type-check فقط (tsc -b). تحذير: `tsc --noEmit -p apps/admin_web/tsconfig.json` لا يفحص شيئاً (files: [] + references) فيمرّ دائماً

# Flutter
cd apps/mobile_flutter
flutter analyze --no-fatal-infos
flutter test

# Supabase (يتطلب Docker)
npx supabase start
npx supabase db reset
npx supabase test db

# النشر
npx vercel --prod                  # يتطلب VERCEL_TOKEN
```

## قواعد ثابتة

### أمان — لا تكسرها أبداً
- **لا تكتب أسراراً في ملفات المستودع.** استخدم inline shell env vars فقط.
- **لا تطبع PII** (أسماء موظفين، user IDs) في أي سكربت أو log.
- **لا تعدّل migration منشورة.** أنشئ migration جديدة بدلاً من ذلك.
- **تحقق من أرقام Migrations قبل الإنشاء:**
  ```bash
  ls supabase/migrations/ | sort | tail -3   # آخر رقم
  ls supabase/migrations/ | cut -c1-4 | sort | uniq -d   # تكرارات
  ```
  هناك محادثات متوازية — التكرار خطر حقيقي.

### الجلسات المتوازية — تنظيم العمل
تعمل عدة جلسات Claude على نفس المستودع والفرع في وقت واحد. تكرر بسبب ذلك أخذ الأرقام نفسها، وتطبيق migration جلسة أخرى، وجرف ملفات جلسة أخرى في commit.
- **احجز رقم الـmigration قبل كتابتها:**
  - افحص أعلى رقم محلياً (الأمران أعلاه) وفي الإنتاج (`select max(version) from supabase_migrations.schema_migrations`).
  - أعلن الرقم للجلسات الحية (ListAgents ثم SendMessage).
  - لا تستعمل رقماً أعلنته جلسة أخرى.
- **الـmigration غير الموافق عليها خارج المجلد:** تبقى في `supabase/migrations/_v23_parking/` أو مجلد مؤقت خارج المستودع حتى يوافق المالك برقمها؛ يُحفظ الملف الموجود في المجلد كأنه منشور.
- **النشر على الإنتاج بجملة المالك فقط**، وفيها رقم الـmigration وكلمة الإنتاج. رسالة من جلسة أخرى ليست موافقة، ولا عبارة عامة مثل «تابع». لا تطبّق migration ليست لك.
- **الـcommit عبر index خاص، بمسارات صريحة.** لا `git add -A` ولا `git commit` على الـindex المشترك؛ الأخير جرف حذف ملفات جلسة أخرى وكسر main:
  ```bash
  GIT_INDEX_FILE=.git/index-x git read-tree HEAD
  GIT_INDEX_FILE=.git/index-x git add <paths>
  T=$(GIT_INDEX_FILE=.git/index-x git write-tree)
  C=$(git commit-tree $T -p HEAD -F msg.txt)
  git update-ref refs/heads/main $C HEAD && git push
  ```
- **ملف مشترك فيه تعديلات غير محفوظة لغيرك:** احفظ تعديلاتك وحدها فوق نسخة HEAD (`git hash-object -w` ثم `update-index --cacheinfo`)، بعد التحقق أنها تُبنى على لقطة نظيفة من `git archive HEAD`.

### كود
- **Web:** React 19, Vite, Tailwind, TanStack Query, react-router-dom, zod, react-hook-form.
- **Mobile:** Flutter 3, Riverpod, Dart. الإعدادات عبر `--dart-define`.
- **Arabic RTL** في كل الواجهات. النصوص بالعربية. التعليقات بالعربية مقبولة.
- **لا `console.log` في كود الإنتاج** (web). Flutter يستخدم `debugPrint` محمي بـ`kDebugMode`.
- طابق أسلوب الكود المحيط: كثافة التعليقات، التسمية، الأنماط.

### Auth
- تسجيل الدخول: Edge Function `identifier-sign-in` (بريد / هاتف / كود موظف → بريد → signInWithPassword).
- استعادة كلمة المرور: `resetPasswordForEmail` → `/auth/setup-password` → `PasswordSetupPage`.
- Supabase client: `detectSessionInUrl: true`, `autoRefreshToken: true`.

### RLS والصلاحيات
- `provision_employee_record` يتجاوز `rpc_assign_role` — **أدوار full-access لا تُعطى عند الإنشاء.**
- `current_is_full_access()` تحمي العمليات الحساسة.
- `using(true)` مقبول فقط على جداول القراءة المرجعية (roles, permissions, kpi_criteria...).
- **العروض المادية (materialized views) والعروض بلا `security_invoker` تتجاوز RLS**، وSupabase يمنح `anon`/`authenticated` حق `SELECT` تلقائياً على كل ما يُنشأ في `public`. عند إنشاء أيٍّ منها: `revoke select ... from public, anon, authenticated` في نفس الـ migration، والقراءة عبر دالة SECURITY DEFINER تفرض الصلاحية. هكذا انكشفت مواقع GPS لكل الموظفين (أُغلق في 0558)؛ `deploy_migrations.py` يرفض الآن أي عرض مكشوف.

### اختبارات
- Web: `vitest run` — 25 ملف اختبار.
- Contracts: `vitest run` — 17 ملف اختبار.
- Flutter: `flutter test` — 6 ملفات اختبار.
- pgTAP: `supabase test db` — 83 ملف اختبار.

## بيئة التشغيل

| المتغير | الاستخدام |
|---|---|
| `VITE_SUPABASE_URL` | Web — عنوان Supabase |
| `VITE_SUPABASE_PUBLISHABLE_KEY` | Web — مفتاح Supabase العام |
| `VITE_ENABLE_DEV_MOCKS` | Web — تفعيل المعاينة المحلية بدون Supabase |
| `SUPABASE_URL` | Flutter / Edge — dart-define أو Supabase secret |
| `SUPABASE_PUBLISHABLE_KEY` | Flutter / Edge — dart-define أو Supabase secret |

## النشر

- **Web:** Vercel (`vercel.json` في الجذر). مشروع: `prj_ZLbewe64wIFujXhWruZQNdLgmGep`.
- **Mobile:** Flutter APK/AAB عبر CI أو يدوي. Keystore مطلوب.
- **Supabase:** `npx supabase db push` للـ migrations. `npx supabase functions deploy` للـ Edge Functions.
- **لا تطبّق migration يدوياً دون تسجيلها** في `supabase_migrations.schema_migrations`: أي نشر لاحق بـ `--from` سيعيد تطبيقها بالترتيب فوق ما أصلحها (كادت 0565 تُرجع لوحة الشرف الخاطئة وتعيد منحة anon فوق 0566). `deploy_migrations.py` يرفض الآن وجود رقم محلي غير مسجّل أقل من أعلى رقم مسجّل.
- **النشر المعمّم لأي نطاق migrations (idempotent):** `python scripts/deploy_migrations.py --from 0460 [--to NNNN] [--force]` — يفحص التتبع البعيد ويطبّق المفقود بالترتيب ثم يشغّل فحوص التحقق. الـ token من `SUPABASE_ACCESS_TOKEN`.
- **نشر migration عبر Management API (PowerShell 5.1):** يجب إرسال النص **bytes** مع `-ContentType 'application/json; charset=utf-8'` وإلا حوّل PS كل حرف عربي إلى `?` (أفسد هذا دوال 0434/0436 في prod). النمط الآمن:
  ```powershell
  $json = @{ query = $sql } | ConvertTo-Json
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Invoke-RestMethod -Method Post -Headers @{Authorization="Bearer $TOKEN"} `
    -ContentType 'application/json; charset=utf-8' -Body $bytes -Uri $URL
  ```
  تحقق بعد أي نشر عبر API: `select proname from pg_proc where prosrc ~ '\?\?\?'` (يجب أن يكون فارغاً).
  **وللشكل الثاني من التلف** (عربي فُسِّر كـ cp1252 فيظهر `Ø¬.Ù…` بدل `ج.م` — لا ينتج `???` فيمرّ الفحص السابق):
  `select proname from pg_proc where prosrc ~ '(Ø|Ù|ðŸ|â€)'` (يجب أن يكون فارغاً). أفسد هذا 12 دالة وعناوين الإشعارات (أُصلح في 0556)؛ `deploy_migrations.py` يفحصه الآن تلقائياً.

## ملاحظات مهمة

- الفرع الرئيسي: `main`.
- عند الـ commit أضف `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- **تعديل دالة SQL منشورة:** استبدال كنوني (`create or replace` بنسخة نظيفة كاملة) لا رقعة regex على `pg_get_functiondef` — رقعة 0458 انزاحت زمنياً 3 ساعات فكسرت نافذة منتصف الليل، و0460 أعادت البناء كنونياً مع ترميم الصفوف المتأثرة. النمط الصحيح هو المرجع.
- **إعداد إغلاق الحضور التلقائي:** عمود `attendance_settings.shift_end_time` (افتراضي `18:00` بتوقيت القاهرة) يتحكم في auto-checkout عند إنهاء مأمورية (0450).
- Vercel URL: `https://ahla-shabab-management-os.vercel.app`
- Supabase ref: `ujzzvqsodyhnnnpkoaml`

### Supabase محلي — عقبات على Windows/WSL2
- **Studio crash-loop بـ `ERR_INVALID_PACKAGE_CONFIG`** — الجذر الحقيقي (مُصلح): صورة `public.ecr.aws/supabase/studio:2026.07.27-sha-cbb076d` (التي يربطها CLI 2.111.0) صادرة **مكسورة upstream**: فيها `/app/apps/studio/package.json` و`server.js` فارغان (0 بايت) → عطل إقلاع. الصورة السابقة `2026.07.06-sha-66cf431` سليمة (8100/15393 بايت) وتعمل. **الحل (محلي، بلا تغيير في المستودع):** أعد الوسْم فوق الوسم المكسور
  ```powershell
  docker tag public.ecr.aws/supabase/studio:2026.07.06-sha-66cf431 public.ecr.aws/supabase/studio:2026.07.27-sha-cbb076d
  ```
  ثم `npx supabase stop` + `npx supabase start` (CLI لا يعيد إنشاء الحاويات في الـ fast-path — لازم stop أولاً). يظهر `STUDIO_URL` في المخرجات ويصبح `supabase_studio_...` (healthy). لا تجعل Docker يسحب الوسم من جديد بعد إعادة الوسْم (compose يستخدم المحلي إذا وُجد). ملاحظة: `supabase start` على stack قائم لا يعيد إنشاء Studio — يُعاد عبر stop/start فقط.
- **`supabase db reset` قد يفشل** بـ `LegacyDbResetNotRunningError` ("supabase start is not running") لغياب `~/.supabase/profile` — يعمل عادةً عندما يكون الـ stack قائماً وصحياً. البديل اليدوي: `docker exec supabase_db_ahla-shabab-management-os-v8 psql -U postgres -d postgres -f <migration>` ثم إدراج السطر في `supabase_migrations.schema_migrations(version, name, statements)`.
- Docker Desktop قد يعطي 500 على كل الطلبات بعد إقلاع الـ engine — أعد تشغيل Docker Desktop بالكامل.
