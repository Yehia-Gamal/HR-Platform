# File Ownership — أحلى شباب HR V23

> يحدد هذا الملف ملكية كل ملف/مجلد في المستودع لوكيل معين.
> لا يعدل وكيل ملفًا مملوكًا لوكيل آخر دون Cross-Agent Request في CROSS_AGENT_REQUESTS.md.
> الملفات المشتركة (shared) تتطلب موافقة Integration Lead (وكيل 14).

---

## 1. وكيل 1 — Discovery وArchitecture

| المسار | النوع | ملاحظات |
|---|---|---|
| `AHLA_SHABAB_UNIFIED_MASTER_PLAN_V21.md` | doc | المرجع التنفيذي المحدث |
| `_v22_review/` | doc | مراجعة V22 السابقة |

---

## 2. وكيل 2 — Database وMigrations

| المسار | النوع | ملاحظات |
|---|---|---|
| `supabase/migrations/*.sql` | migration | جميع الـ 163 migration |
| `supabase/migrations/README.md` | doc | توثيق الـ migrations |
| `supabase/tests/*.sql` | test | جميع الـ 67 pgTAP test |
| `supabase/tests/README.md` | doc | توثيق الاختبارات |
| `supabase/config.toml` | config | إعدادات Supabase المحلي |
| `supabase/seed.sql` | data | بيانات البذر |

---

## 3. وكيل 3 — Security وRLS وRoles

| المسار | النوع | ملاحظات |
|---|---|---|
| `supabase/functions/_shared/cors.ts` | shared | CORS helper |
| `supabase/functions/_shared/secret.ts` | shared | timing-safe comparison |
| `supabase/functions/_shared/phone.ts` | shared | phone normalization |
| `supabase/functions/identifier-sign-in/` | edge fn | multi-identifier login |
| `supabase/functions/webauthn-challenge/` | edge fn | WebAuthn challenge |
| `supabase/functions/passkey-register/` | edge fn | passkey registration |
| `supabase/functions/verify-attendance-punch/` | edge fn | attendance verification |
| `scripts/check-no-secrets.mjs` | script | secret scanning |
| `scripts/edge-smoke-tests.sh` | script | edge function smoke tests |
| `.github/workflows/security-ci.yml` | CI | security checks |

---

## 4. وكيل 4 — Employee وOrg وMulti-Department

| المسار | النوع | ملاحظات |
|---|---|---|
| `supabase/functions/admin-create-employee/` | edge fn | employee creation |
| `supabase/functions/admin-resend-invite/` | edge fn | invite resend |
| `packages/shared-contracts/src/employee.ts` | contract | employee schemas |
| `packages/shared-contracts/src/employee.test.ts` | test | employee contract tests |
| `apps/admin_web/src/features/employees/` | web feature | 5 files — employees CRUD |

---

## 5. وكيل 5 — Web Admin وHR UI

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/admin_web/src/app/App.tsx` | router | main router — 35 routes |
| `apps/admin_web/src/main.tsx` | entry | web entry point |
| `apps/admin_web/src/styles.css` | styles | global styles |
| `apps/admin_web/src/vite-env.d.ts` | types | Vite env types |
| `apps/admin_web/src/ui/` | shared UI | 24 files — shared components |
| `apps/admin_web/src/core/` | infra | 3 files — env, supabase, rpc |
| `apps/admin_web/src/features/workspaces/` | web feature | workspace shell + access |
| `apps/admin_web/src/features/auth/` | web feature | 9 files — auth flow |
| `apps/admin_web/src/features/actions/` | web feature | action center |
| `apps/admin_web/src/features/management/` | web feature | 27 files — admin pages |
| `apps/admin_web/src/features/mock/` | web feature | dev mocks |
| `apps/admin_web/src/features/notifications/` | web feature | notifications |
| `apps/admin_web/src/test/` | test | test setup |
| `apps/admin_web/vite.config.ts` | config | Vite config |
| `apps/admin_web/tsconfig.json` | config | TypeScript config |
| `apps/admin_web/tailwind.config.js` | config | Tailwind config |
| `apps/admin_web/index.html` | entry | HTML entry |

---

## 6. وكيل 6 — Attendance وDevice وBiometrics

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/admin_web/src/features/attendance/` | web feature | 4 files — attendance |
| `apps/admin_web/src/features/devices/` | web feature | device approval |
| `packages/shared-contracts/src/attendanceConfig.ts` | contract | attendance config schemas |
| `packages/shared-contracts/src/attendanceConfig.test.ts` | test | attendance config tests |

---

## 7. وكيل 7 — Leaves وAssignments وHolidays

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/admin_web/src/features/holidays/` | web feature | official holidays |
| `apps/admin_web/src/features/requests/` | web feature | requests/leaves |
| `packages/shared-contracts/src/requests.ts` | contract | request schemas |
| `packages/shared-contracts/src/requests.test.ts` | test | request contract tests |
| `packages/shared-contracts/src/holidays.ts` | contract | holiday schemas |
| `packages/shared-contracts/src/holidays.test.ts` | test | holiday contract tests |

---

## 8. وكيل 8 — KPI Workflow

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/admin_web/src/features/performance/` | web feature | 4 files — KPI |
| `apps/admin_web/src/features/advanced/KpiCyclesPage.tsx` | web page | KPI admin cycles |
| `packages/shared-contracts/src/kpi.ts` | contract | KPI schemas |
| `packages/shared-contracts/src/kpi.test.ts` | test | KPI contract tests |

---

## 9. وكيل 9 — Disputes وCommittee

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/admin_web/src/features/advanced/DisputesPage.tsx` | web page | disputes admin |
| `packages/shared-contracts/src/disputes.ts` | contract | dispute schemas |
| `packages/shared-contracts/src/disputes.test.ts` | test | dispute contract tests |

---

## 10. وكيل 10 — Executive Mobile وPosts وReports

| المسار | النوع | ملاحظات |
|---|---|---|
| `apps/mobile_flutter/lib/` | mobile app | 79 Dart files — entire mobile app |
| `apps/mobile_flutter/test/` | test | 6 test files — 29 tests |
| `apps/mobile_flutter/pubspec.yaml` | config | Flutter dependencies |
| `apps/mobile_flutter/android/` | platform | Android native config |
| `apps/mobile_flutter/ios/` | platform | iOS native config |
| `apps/admin_web/src/features/communications/` | web feature | official feed |
| `packages/shared-contracts/src/postPublishing.ts` | contract | post schemas |
| `packages/shared-contracts/src/postPublishing.test.ts` | test | post contract tests |

---

## 11. وكيل 11 — Live Location وFCM وNotifications + Database Security Continuous

| المسار | النوع | ملاحظات |
|---|---|---|
| `supabase/functions/notification-dispatcher/` | edge fn | FCM push |
| `supabase/functions/live-location-map-url/` | edge fn | map URL signer |
| `supabase/functions/live-location-video-url/` | edge fn | video URL (stub — 410) |
| `supabase/functions/retention-cleanup/` | edge fn | location retention |
| `packages/shared-contracts/src/liveLocation.ts` | contract | location schemas |
| `packages/shared-contracts/src/liveLocation.test.ts` | test | location contract tests |
| `supabase/migrations/0163_v23_security_search_path_hardening.sql` | migration | search_path hardening — 4 utility functions |
| `supabase/tests/0068_v23_security_search_path_audit.sql` | test | 30 pgTAP assertions — search_path + RLS + USING(true) audit |
| `RLS_PUBLIC_REFERENCE_ALLOWLIST.md` | doc | USING(true) allowlist — default deny |

---

## 12. وكيل 12 — Monthly Statement وReporting

| المسار | النوع | ملاحظات |
|---|---|---|
| `supabase/functions/scheduled-report-runner/` | edge fn | report scheduling |
| `packages/shared-contracts/src/operations.ts` | contract | statement schemas (shared مع 5/6/7) |
| `packages/shared-contracts/src/operations.test.ts` | test | operations contract tests |

---

## 13. وكيل 13 — UI/UX وRTL وTheme

| المسار | النوع | ملاحظات |
|---|---|---|
| `packages/design-tokens/` | tokens | design tokens — CSS + Dart |

---

## 14. وكيل 14 — Integration وMerge وTraceability (هذا الوكيل)

| المسار | النوع | ملاحظات |
|---|---|---|
| `MIGRATION_REGISTRY.md` | doc | سجل الـ migrations |
| `FILE_OWNERSHIP.md` | doc | ملكية الملفات (هذا الملف) |
| `CROSS_AGENT_REQUESTS.md` | doc | طلبات التعديل بين الوكلاء |
| `TRACEABILITY.md` | doc | مصفوفة التتبع |
| `MERGE_QUEUE.md` | doc | طابور الدمج |
| `BLOCKERS.md` | doc | سجل العوائق |
| `packages/shared-contracts/src/index.ts` | barrel | نقطة التصدير المشتركة |
| `packages/shared-contracts/package.json` | config | package config |
| `scripts/validate-foundation.mjs` | script | foundation validation |
| `scripts/generate-manifest.mjs` | script | build manifest |
| `scripts/deploy-staging.sh` | script | staging deployment |
| `scripts/deploy-staging-manual.sh` | script | manual staging deployment |
| `scripts/runtime_preflight.sh` | script | preflight checks |
| `.github/workflows/web-ci.yml` | CI | web + contracts CI |
| `.github/workflows/flutter-ci.yml` | CI | Flutter CI |
| `.github/workflows/supabase-ci.yml` | CI | Supabase CI |
| `.github/workflows/release-candidate.yml` | CI | release candidate |
| `CLAUDE.md` | doc | project instructions |
| `package.json` | config | root monorepo config |
| `vercel.json` | config | Vercel deployment |

---

## الملفات المشتركة (تتطلب موافقة وكيل 14)

| المسار | الوكلاء المعنيون | ملاحظات |
|---|---|---|
| `packages/shared-contracts/src/*.ts` | 4,5,6,7,8,9,10,11,12,14 | أي تعديل على العقود المشتركة |
| `packages/design-tokens/` | 5,10,13 | تغييرات التصميم |
| `apps/admin_web/src/app/App.tsx` | 5,6,7,8,9 | إضافة routes |
| `apps/admin_web/src/ui/` | 5,13 | مكونات مشتركة |
| `supabase/functions/_shared/` | 3,4,11 | أدوات Edge المشتركة |
| `.github/workflows/` | 14 | CI/CD pipelines |
