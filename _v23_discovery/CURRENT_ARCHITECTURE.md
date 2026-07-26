# البنية الحالية — CURRENT_ARCHITECTURE

> **تاريخ الجرد:** 2026-07-26 | **الإصدار:** V23 Discovery Baseline | **Agent 00A**

---

## مخطط معماري عام

```
┌─────────────────────────────────────────────────────────────────┐
│                        المستخدمون                               │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│   │  ويب (Admin) │    │ موبايل      │    │ تنفيذي      │      │
│   │  React 19    │    │ Flutter 3   │    │ Flutter 3   │      │
│   └──────┬───────┘    └──────┬───────┘    └──────┬───────┘      │
└──────────┼───────────────────┼───────────────────┼──────────────┘
           │                   │                   │
           ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Supabase (Backend)                           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ Auth        │  │ Edge Fns    │  │ Realtime / Storage      │ │
│  │ (GoTrue)    │  │ (Deno) ×12  │  │                         │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │              PostgreSQL + pgTAP                              ││
│  │  238 جدول | 583 سياسة RLS | 500+ دالة | 162 migration      ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
           │                   │
           ▼                   ▼
┌──────────────────┐  ┌──────────────────┐
│  Vercel (Web)    │  │  Firebase (FCM)  │
│  SPA Deploy      │  │  Push Notifs     │
└──────────────────┘  └──────────────────┘
```

---

## 1. هيكل Monorepo

| العنصر | القيمة |
|---|---|
| الاسم | `ahla-shabab-management-os` |
| الإصدار | `0.10.0` |
| مدير الحزم | npm workspaces |
| Node المطلوب | `>= 22.12.0` |
| نوع الوحدات | ESM (`"type": "module"`) |

### مساحات العمل

```
ahla-shabab-management-os/
├── apps/
│   ├── admin_web/              — تطبيق ويب React 19
│   └── mobile_flutter/         — تطبيق Flutter (موظف + مدير + تنفيذي)
├── packages/
│   ├── shared-contracts/       — مخططات Zod مشتركة (18 ملف مصدر)
│   └── design-tokens/          — متغيرات التصميم (CSS + Dart)
├── supabase/
│   ├── migrations/             — 162 ملف migration
│   ├── tests/                  — 65 ملف pgTAP
│   └── functions/              — 12 Edge Function + _shared/
├── scripts/                    — أدوات بناء وتحقق
├── .github/workflows/          — 7 CI/CD workflows
└── docs/                       — توثيق وأدلة تشغيل
```

---

## 2. تطبيق الويب (apps/admin_web/)

### المكدس التقني

| التقنية | الإصدار | الغرض |
|---|---|---|
| React | 19.2.0 | إطار واجهة المستخدم |
| Vite | 8.1.4 | أداة البناء والتطوير |
| TypeScript | 5.9.3 | نظام الأنماط |
| Tailwind CSS | 4.3.0 | أنماط CSS |
| TanStack Query | 5.90.10 | إدارة حالة الخادم |
| react-router-dom | 7.9.6 | التوجيه |
| Zod | 4.1.12 | التحقق من المدخلات |
| react-hook-form | 7.66.1 | إدارة النماذج |
| lucide-react | 0.554.0 | أيقونات |
| Leaflet | 1.9.4 | خرائط |
| vitest | 4.0.14 | اختبارات |

### بنية التطبيق

```
src/
├── app/
│   └── App.tsx                 — مكون الجذر + تعريف المسارات
├── core/                       — أدوات مساعدة أساسية
├── features/
│   ├── actions/                — مركز الإجراءات
│   ├── advanced/               — عمليات متقدمة (حضور، KPI، شكاوى)
│   ├── attendance/             — الحضور والتقارير الشهرية
│   ├── auth/                   — المصادقة (login, password, release)
│   ├── communications/         — المنشورات والقرارات
│   ├── devices/                — اعتماد الأجهزة
│   ├── employees/              — إدارة الموظفين
│   ├── holidays/               — الإجازات الرسمية
│   ├── management/             — 19 صفحة إدارية
│   ├── mock/                   — بيانات تجريبية
│   ├── notifications/          — الإشعارات
│   ├── performance/            — تقييم الأداء
│   ├── requests/               — الطلبات
│   └── workspaces/             — الهيكل العام + Dashboard
├── ui/                         — 22 مكون مشترك
└── test/                       — إعدادات الاختبار
```

### مساحات العمل الويب

| المساحة | المسار | الوصف |
|---|---|---|
| HR | `/hr` | إدارة الموارد البشرية |
| Main Admin | `/admin` | الإدارة العامة + سكرتير تنفيذي |
| Committee | `/committee` | لجنة المشكلات |

### نمط المصادقة والحماية

1. **WorkspaceGuard** — يتحقق من صلاحية الوصول للمساحة
2. **RequirePermission** — حماية كل مسار بـ permission slug محدد
3. **AuthProvider** — يوفر حالة المصادقة عبر `useAuth()`
4. **WebReleasePolicy** — فحص صيانة/تحديث قبل عرض التطبيق

### مكونات الواجهة المشتركة (src/ui/)

AppErrorBoundary, AppLogo, DialogOverlay, DialogPortal, EmptyState, ErrorState, FeatureGate, FilterBar, ForbiddenState, LoadingScreen, MetricCard, OfflineState, PageHeader, Skeletons, StatusBadge, ThemeToggle, UserAvatar, WorkspaceSearch, featureFlags, avatarImage, postImage, theme

---

## 3. تطبيق الموبايل (apps/mobile_flutter/)

### المكدس التقني

| التقنية | الإصدار | الغرض |
|---|---|---|
| Flutter | 3.x | إطار التطبيق |
| Dart SDK | >=3.8.0 <4.0.0 | لغة البرمجة |
| flutter_riverpod | 3.3.2 | إدارة الحالة |
| go_router | >=17.0.0 | التوجيه |
| supabase_flutter | >=2.15.4 | اتصال بالخادم |
| flutter_secure_storage | 10.3.1 | تخزين آمن |
| geolocator | >=14.0.2 | GPS |
| passkeys | 2.21.1 | WebAuthn / مفاتيح المرور |
| local_auth | 2.3.0 | بصمة محلية |
| firebase_core | >=3.6.0 | Firebase |
| firebase_messaging | >=15.1.3 | إشعارات FCM |
| flutter_local_notifications | >=18.0.1 | إشعارات محلية |
| flutter_map | 8.2.2 | خرائط (OSM، ليس Google) |
| image_picker | 1.2.1 | التقاط الصور |
| screenshot | 3.0.0 | لقطات خريطة |

### بنية التطبيق

```
lib/
├── main.dart                   — نقطة الدخول + تهيئة Supabase + FCM
├── app.dart                    — GoRouter + MaterialApp.router
├── core/
│   ├── config/app_config.dart  — إعدادات dart-define
│   ├── network/                — فحص الاتصال + cache
│   ├── security/               — تخزين آمن للجلسة
│   ├── theme/                  — سمة فاتحة/داكنة
│   └── widgets/                — مكونات مشتركة (avatar, logo, GPS, connectivity)
├── features/
│   ├── auth/                   — تسجيل دخول + كلمة مرور + providers
│   ├── mobile_data/            — نماذج + providers + خدمات
│   ├── mobile_pages/           — 40 صفحة
│   └── workspaces/             — 5 مساحات عمل + بوابة + scaffold
└── shared/
    └── access_context.dart     — سياق الصلاحيات
```

### مساحات العمل

| المساحة | الملف | المستخدم |
|---|---|---|
| Employee | employee_workspace.dart | الموظف |
| Manager | manager_workspace.dart | المدير المباشر |
| Executive | executive_workspace.dart | المدير التنفيذي |
| Operations | operations_workspace.dart | مدير التشغيل |
| Committee | committee_workspace.dart | عضو لجنة المشكلات |

---

## 4. الخادم (Supabase)

### قاعدة البيانات

| المقياس | القيمة |
|---|---|
| ملفات Migration | 162 |
| الجداول | ~238 |
| سياسات RLS | ~583 |
| دوال/RPCs | ~500+ |
| Triggers | ~1 صريح + عديد ديناميكي |
| المرجع | `ujzzvqsodyhnnnpkoaml` |

### Edge Functions (Deno)

| الوظيفة | النوع | الغرض |
|---|---|---|
| `identifier-sign-in` | عام | تسجيل دخول موحد |
| `admin-create-employee` | مصادق | إنشاء موظف |
| `admin-resend-invite` | مصادق | إعادة إرسال الدعوة |
| `passkey-register` | مصادق | تسجيل مفتاح مرور |
| `webauthn-challenge` | مصادق | إنشاء تحدي WebAuthn |
| `verify-attendance-punch` | مصادق | تحقق من حضور WebAuthn |
| `notification-dispatcher` | cron | إرسال إشعارات FCM |
| `integration-outbox-worker` | cron | معالجة Webhooks |
| `retention-cleanup` | cron | تنظيف بيانات منتهية |
| `scheduled-report-runner` | cron | تشغيل التقارير المجدولة |
| `live-location-map-url` | مصادق | رابط خريطة موقع مؤقت |
| `live-location-video-url` | معطل | ⛔ معطل نهائياً (410 Gone) |

### وحدات مشتركة (_shared/)

| الملف | الصادرات |
|---|---|
| `cors.ts` | `corsHeaders()`, `json()`, `preflight()` |
| `phone.ts` | `normalizePhone()` — تطبيع أرقام مصرية |
| `secret.ts` | `timingSafeEqual()` — مقارنة آمنة زمنياً |

---

## 5. مسار المصادقة

```
المستخدم
  │
  ├─ ويب: LoginPage → identifier-sign-in Edge Function
  │        → (email/phone/code → lookup → signInWithPassword)
  │        → AuthProvider → useAuth() → session
  │
  ├─ موبايل: login_page.dart → identifier-sign-in
  │           → SecureSessionStorage (flutter_secure_storage)
  │           → PKCE flow
  │
  ├─ استعادة كلمة المرور:
  │    resetPasswordForEmail → /auth/setup-password → PasswordSetupPage
  │
  └─ FCM: عند تسجيل الدخول → getToken() → upsert_my_push_token RPC
```

### خيارات الجلسة
- `detectSessionInUrl: true`
- `autoRefreshToken: true`
- Mobile: `SecureSessionStorage` + `SecurePkceStorage`

---

## 6. النشر

### الويب — Vercel
- **الرابط:** https://ahla-shabab-management-os.vercel.app
- **البناء:** `npm run build` → `apps/admin_web/dist`
- **إعادة التوجيه:** SPA catch-all (ما عدا `.well-known/` و `assets/`)
- **أمان:** HSTS 2yr, CSP صارم, X-Frame-Options: DENY, nosniff

### الموبايل — Flutter APK/AAB
- بناء محلي أو عبر CI
- Keystore في `android/keystore.properties` (gitignored)
- Debug و Release builds

### Supabase
- `npx supabase db push` — Migrations
- `npx supabase functions deploy` — Edge Functions

---

## 7. CI/CD

| Workflow | المشغل | المهام |
|---|---|---|
| `web-ci.yml` | PR + push main | typecheck + test + build + validate-foundation + secrets |
| `flutter-ci.yml` | PR + push main | analyze + test + debug APK |
| `supabase-ci.yml` | PR + push main | db reset×2 (idempotency) + test + deno check |
| `security-ci.yml` | PR + push main | secrets + npm audit + typecheck |
| `release-candidate.yml` | tag v* / يدوي | full check:all + db test + Vercel + signed APK/AAB + iOS |
| `e2e-ci.yml` | PR + push main | اختبارات E2E |
| `edge-smoke-ci.yml` | PR + push main | اختبارات Edge Functions |

---

## 8. رموز التصميم (Design Tokens)

### الألوان الأساسية
| الرمز | القيمة |
|---|---|
| Primary | `#0B4FA2` |
| Primary Strong | `#073B7A` |
| Accent | `#00A8D6` |
| Success | `#22C55E` |
| Warning | `#F59E0B` |
| Danger | `#EF4444` |
| Info | `#8B5CF6` |

### السمات
- فاتحة: خلفية `#F4F7FB`، سطح `#FFFFFF`، نص `#10233F`
- داكنة: خلفية `#020611`، سطح `#061127`، نص `#F5F8FF`
- التبديل عبر `[data-theme='dark']` في CSS و `ThemeMode` في Flutter
