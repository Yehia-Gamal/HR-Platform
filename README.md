# Ahla Shabab Management OS V8 — Build 0.10.0

مشروع موحّد لإدارة الموارد البشرية والتشغيل والاعتمادات والحوكمة داخل جمعية أحلى شباب.

## المعمارية

- Flutter App واحدة حسب الدور والصلاحيات.
- React Web واحدة تضم HR Workspace وMain Admin Workspace.
- Supabase Backend واحد مع PostgreSQL وRLS/ABAC وRPCs وEdge Functions وPrivate Storage.

## أبرز الوحدات

- الموظف 360° والهيكل والمناصب والأدوار والصلاحيات.
- الحضور والورديات وPasskey وGPS والروستر والإغلاق الشهري.
- الإجازات والطلبات والـWorkflow وKPI متعدد المراحل.
- القرارات والأخبار والتصويت والتقارير التنفيذية.
- الموقع الحي وفيديو 5 ثوانٍ والاحتفاظ وLegal Hold.
- التوظيف وOnboarding والتدريب والمستندات والعهد وOffboarding.
- النزاعات واللجان والمشروعات والمخاطر والجودة والتدقيق والأتمتة.
- حوكمة الإصدارات والأجهزة وAccess Review وBreak-glass والخصوصية وIntegration Outbox.
- App Shell جديد للويب، لوحات قيادة حسب الدور، Dark Mode وبحث سريع.
- تجربة Flutter يومية محسنة ودخول بالبريد أو الهاتف أو كود الموظف.

## الحجم الحالي

- 56 Migration.
- 34 اختبار SQL/pgTAP.
- 9 Edge Functions قابلة للنشر + مجلد `_shared` مشترك.
- 61 ملف Dart.
- 75 ملف TypeScript/TSX داخل الويب.
- 33 اختبار TypeScript/React ناجحًا عبر 11 ملف اختبار (19 عقود مشتركة + 14 ويب).

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

## التشغيل والإطلاق

- راجع `docs/runbooks/STAGING_DEPLOYMENT_RUNBOOK_AR.md`.
- راجع `docs/runbooks/RELEASE_ACCESS_PRIVACY_GOVERNANCE_AR.md`.
- لا تفعل Payroll في Production قبل اعتماد HR وFinance وLegal.

## الحالة

Staging Candidate. لا يصبح Production Release قبل نجاح PostgreSQL/RLS Runtime Tests وFlutter Builds واختبارات الأجهزة الفعلية والنسخ الاحتياطي والاستعادة والتوقيع الإنتاجي.
