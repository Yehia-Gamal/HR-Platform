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
npx tsc --noEmit -p apps/admin_web/tsconfig.json   # type-check فقط

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

## ملاحظات مهمة

- الفرع الرئيسي: `main`.
- عند الـ commit أضف `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Vercel URL: `https://ahla-shabab-management-os.vercel.app`
- Supabase ref: `ujzzvqsodyhnnnpkoaml`

### Supabase محلي — عقبات على Windows/WSL2
- **Studio قد يرفض الإقلاع** (crash-loop بخطأ `ERR_INVALID_PACKAGE_CONFIG` أو `container is not ready: unhealthy`) مع CLI 2.111.0 وصورة `studio:2026.07.06` — خلل upstream (supabase/cli#4254) يظهر تحت الإقلاع المتوازي. لا يُصلح بترقية CLI (أحدثها 2.111.0). الحل البديل: عطّل مؤقتاً `[studio] enabled = false` في `supabase/config.toml` → `npx supabase start` يعمل (DB/API/storage/auth لا تحتاج Studio) → ثم أعد التفعيل إذا أردت.
- **`supabase db reset` قد يفشل** بـ `LegacyDbResetNotRunningError` ("supabase start is not running") لغياب `~/.supabase/profile` — يعمل عادةً عندما يكون الـ stack قائماً وصحياً. البديل اليدوي: `docker exec supabase_db_ahla-shabab-management-os-v8 psql -U postgres -d postgres -f <migration>` ثم إدراج السطر في `supabase_migrations.schema_migrations(version, name, statements)`.
- Docker Desktop قد يعطي 500 على كل الطلبات بعد إقلاع الـ engine — أعد تشغيل Docker Desktop بالكامل.
