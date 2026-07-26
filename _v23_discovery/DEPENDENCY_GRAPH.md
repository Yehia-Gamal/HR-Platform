# رسم بياني للاعتماديات — DEPENDENCY_GRAPH

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## 1. هيكل Monorepo

```
ahla-shabab-management-os@0.10.0 (root)
├── apps/admin_web        → @ahla/admin-web@0.10.0
├── packages/shared-contracts → @ahla/shared-contracts@0.10.0
├── packages/design-tokens    → @ahla/design-tokens@0.10.0
├── apps/mobile_flutter       → ahla_shabab_management_os@0.11.1+12 (Flutter/Dart)
├── supabase/functions/       → 12 Edge Functions (Deno)
└── supabase/migrations/      → 162 ملف SQL
```

### علاقات الحزم الداخلية

```
@ahla/admin-web
  ├── depends on → @ahla/shared-contracts (Zod schemas)
  └── depends on → @ahla/design-tokens (theme.css, tokens.json)

ahla_shabab_management_os (Flutter)
  └── depends on → ahla_design_tokens (path: ../../packages/design-tokens)

Edge Functions (_shared/)
  └── تستخدم وحدات مشتركة: cors.ts, phone.ts, secret.ts
```

---

## 2. اعتماديات الويب (npm)

### @ahla/admin-web — Production Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `react` | ^19.2.0 | إطار الواجهة |
| `react-dom` | ^19.2.0 | عرض DOM |
| `react-router-dom` | ^7.9.6 | التوجيه |
| `@tanstack/react-query` | ^5.90.10 | إدارة الحالة البعيدة |
| `@supabase/supabase-js` | ^2.86.0 | Supabase client |
| `zod` | ^4.1.12 | التحقق من البيانات |
| `react-hook-form` | ^7.66.1 | إدارة النماذج |
| `@hookform/resolvers` | ^5.2.2 | ربط Zod بالنماذج |
| `leaflet` | ^1.9.4 | خرائط |
| `react-leaflet` | ^5.0.0 | مكونات خرائط React |
| `@types/leaflet` | ^1.9.21 | أنواع خرائط |
| `lucide-react` | ^0.554.0 | أيقونات |
| `clsx` | ^2.1.1 | دمج CSS classes |
| `@ahla/shared-contracts` | workspace:* | عقود مشتركة |
| `@ahla/design-tokens` | workspace:* | متغيرات التصميم |

### @ahla/admin-web — Dev Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `vite` | ^8.1.4 | أداة البناء |
| `@vitejs/plugin-react` | ^5.1.1 | إضافة React لـ Vite |
| `typescript` | ^5.9.3 | TypeScript |
| `tailwindcss` | ^4.3.0 | CSS framework |
| `@tailwindcss/vite` | ^4.3.0 | إضافة Tailwind لـ Vite |
| `vitest` | ^4.0.14 | إطار الاختبارات |
| `@testing-library/react` | ^16.3.0 | اختبار مكونات React |
| `@testing-library/jest-dom` | ^6.9.1 | matchers إضافية |
| `jsdom` | ^27.2.0 | DOM افتراضي للاختبارات |
| `@types/react` | ^19.2.7 | أنواع React |
| `@types/react-dom` | ^19.2.3 | أنواع React DOM |
| `@types/node` | ^24.10.1 | أنواع Node.js |

### @ahla/shared-contracts — Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `zod` | ^4.1.12 | التحقق من البيانات |
| `typescript` | ^5.9.3 | (dev) TypeScript |
| `vitest` | ^4.0.14 | (dev) إطار الاختبارات |

### @ahla/design-tokens

| الصادرات | الغرض |
|---|---|
| `./theme.css` | متغيرات CSS للتصميم |
| `./tokens.json` | قيم التصميم الخام (JSON) |

### Root — Dev Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `supabase` | ^2.109.1 | Supabase CLI |

---

## 3. اعتماديات Flutter (pub)

### Production Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `flutter_riverpod` | ^3.3.2 | إدارة الحالة |
| `go_router` | >=17.0.0 <17.1.0 | التوجيه |
| `supabase_flutter` | >=2.15.4 <2.16.0 | Supabase client |
| `flutter_secure_storage` | ^10.3.1 | تخزين آمن |
| `intl` | ^0.20.2 | ترجمة وتنسيق |
| `geolocator` | >=14.0.2 <14.0.3 | تحديد الموقع |
| `passkeys` | ^2.21.1 | WebAuthn/Passkeys |
| `local_auth` | ^2.3.0 | بصمة محلية |
| `package_info_plus` | >=9.0.1 <10.0.0 | معلومات التطبيق |
| `device_info_plus` | ^11.5.0 | معلومات الجهاز |
| `uuid` | ^4.5.1 | توليد UUID |
| `url_launcher` | ^6.3.2 | فتح روابط |
| `firebase_core` | >=3.6.0 <4.0.0 | Firebase أساسي |
| `firebase_messaging` | >=15.1.3 <16.0.0 | إشعارات FCM |
| `flutter_local_notifications` | >=18.0.1 <19.0.0 | إشعارات محلية |
| `image_picker` | ^1.2.1 | اختيار صور |
| `flutter_map` | ^8.2.2 | خرائط |
| `latlong2` | ^0.9.1 | إحداثيات |
| `screenshot` | ^3.0.0 | لقطات شاشة |
| `web` | ^1.1.1 | Web APIs |
| `ahla_design_tokens` | path | متغيرات التصميم المشتركة |

### Dev Dependencies

| الحزمة | الإصدار | الغرض |
|---|---|---|
| `flutter_test` | sdk | إطار الاختبارات |
| `flutter_lints` | ^6.0.0 | قواعد Lint |
| `flutter_launcher_icons` | ^0.14.4 | توليد أيقونات |

### قيود البيئة

| المتطلب | القيمة |
|---|---|
| Dart SDK | >=3.8.0 <4.0.0 |
| Node.js | >=22.12.0 |
| min Android SDK | 24 |

---

## 4. اعتماديات Edge Functions (Deno)

Edge Functions تعمل على Deno runtime وتستورد من:

| المصدر | الاستخدام |
|---|---|
| `npm:@supabase/supabase-js` | Supabase admin/service client |
| `jsr:@std/http` | HTTP server |
| `../_shared/cors.ts` | CORS headers |
| `../_shared/phone.ts` | Phone normalization |
| `../_shared/secret.ts` | Timing-safe comparison |

---

## 5. مخاطر الاعتماديات

| المخاطر | التفاصيل | الأولوية |
|---|---|---|
| Zod v4 (حديث) | v4.1.12 — إصدار major حديث، قد تتغير API | مراقبة |
| Flutter pinning صارم | `go_router`, `supabase_flutter`, `geolocator` مثبتة بنطاقات ضيقة بسبب توافق Dart 3.8 | مراقبة عند الترقية |
| React 19 | إصدار major حديث — بعض المكتبات قد لا تدعمه بالكامل | مراقبة |
| Vite 8 | إصدار major — تأكد من توافق الإضافات | مراقبة |
| `passkeys` ^2.21.1 | تحتاج Dart <3.9 — سيحتاج ترقية عند الانتقال لـ Dart 3.9+ | تخطيط |

---

## 6. رسم بياني للاعتماديات

```
                    ┌──────────────────┐
                    │   Root Monorepo  │
                    │   Node >=22.12   │
                    │   supabase CLI   │
                    └───────┬──────────┘
                            │
            ┌───────────────┼───────────────┐
            │               │               │
    ┌───────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │  admin_web   │ │  shared-    │ │  design-    │
    │  React 19    │ │  contracts  │ │  tokens     │
    │  Vite 8      │ │  Zod 4      │ │  CSS+JSON   │
    │  Tailwind 4  │ │  vitest     │ │             │
    │  TanStack Q  │ └──────┬──────┘ └──────┬──────┘
    │  Supabase JS │        │               │
    │  Leaflet     │◄───────┘               │
    │  RHF + Zod   │◄──────────────────────-┘
    └──────────────┘
            
    ┌──────────────┐        ┌───────────────────┐
    │ Flutter App  │        │  Edge Functions   │
    │ Dart >=3.8   │        │  Deno Runtime     │
    │ Riverpod     │        │  _shared/ modules │
    │ go_router    │        │  supabase-js      │
    │ Supabase FL  │        └───────────────────┘
    │ Firebase FCM │
    │ WebAuthn     │
    │ flutter_map  │
    │ geolocator   │
    └──────────────┘
```
