# Ahla Shabab Management OS V8 — Build 0.11.1

مشروع موحّد لإدارة الموارد البشرية والتشغيل والاعتمادات والحوكمة داخل جمعية أحلى شباب.

## المعمارية

| الطبقة | التقنية |
|---|---|
| **Mobile** | Flutter 3 · Riverpod · Dart |
| **Web** | React 19 · Vite · Tailwind · TanStack Query · RTL كامل |
| **Backend** | Supabase (PostgreSQL + RLS/ABAC + RPCs + Edge Functions + Private Storage) |
| **عقود مشتركة** | `packages/shared-contracts` — Zod schemas مشتركة بين Web وEdge Functions |

- Flutter App واحدة حسب الدور والصلاحيات.
- React Web واحدة تضم HR Workspace وMain Admin Workspace وCommittee Workspace.
- Supabase Backend واحد مع PostgreSQL وRLS/ABAC وRPCs وEdge Functions وPrivate Storage.

## أبرز الوحدات

- الموظف 360° والهيكل والمناصب والأدوار والصلاحيات.
- الحضور والورديات وPasskey وGPS والروستر والإغلاق الشهري.
- الإجازات والطلبات والـWorkflow وKPI متعدد المراحل.
- القرارات والأخبار والتصويت والتقارير التنفيذية.
- الموقع الحي والتتبع المباشر والاحتفاظ وLegal Hold.
- التوظيف وOnboarding والتدريب والمستندات والعهد وOffboarding.
- النزاعات واللجان والمشروعات والمخاطر والجودة والتدقيق والأتمتة.
- حوكمة الإصدارات والأجهزة وAccess Review وBreak-glass والخصوصية وIntegration Outbox.
- App Shell للويب، لوحات قيادة حسب الدور، Dark Mode وبحث سريع.
- تجربة Flutter يومية محسنة ودخول بالبريد أو الهاتف أو كود الموظف.
- استعادة كلمة المرور عبر البريد الإلكتروني.

## الحجم الحالي

| المكوّن | العدد |
|---|---|
| Migrations | 285 |
| pgTAP tests (assertions) | 102 ملف (1483 assertion) |
| Edge Functions | 13 + مجلد `_shared` مشترك |
| Dart files | 90 |
| TypeScript/TSX files (web) | 204 |
| اختبارات كود (web + contracts + Flutter) | 802 اختبار عبر 88 ملف ويب/عقود + 142 اختبار Flutter عبر 12 ملف |

## فحص المصدر

```bash
npm ci
npm run check:all
```

## Supabase Runtime

يتطلب Docker:

```bash
npx supabase start
npx supabase db reset
npx supabase test db
```

## Flutter Runtime

```bash
cd apps/mobile_flutter
flutter pub get
flutter analyze
flutter test
flutter run \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=... \
  --dart-define=APP_ENVIRONMENT=staging
```

## Web Runtime

```bash
cd apps/admin_web
cp .env.example .env.local   # ثم عدّل القيم
npm run dev                   # Vite dev server
npm run build                 # بناء الإنتاج
npm run test                  # Vitest
```

## التشغيل والإطلاق

- راجع `docs/runbooks/STAGING_DEPLOYMENT_RUNBOOK_AR.md`.
- راجع `docs/runbooks/RELEASE_ACCESS_PRIVACY_GOVERNANCE_AR.md`.
- لا تفعل Payroll في Production قبل اعتماد HR وFinance وLegal.
- النشر عبر Vercel CLI: `npx vercel --prod` (يتطلب token صالح).

## الحالة

Production على Vercel: `https://ahla-shabab-management-os.vercel.app`
Supabase ref: `ujzzvqsodyhnnnpkoaml`
