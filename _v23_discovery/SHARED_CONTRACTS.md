# العقود المشتركة — SHARED_CONTRACTS

> **تاريخ الجرد:** 2026-07-26 | **Agent 00A**

---

## 1. ملخص

| المقياس | القيمة |
|---|---|
| الحزمة | `@ahla/shared-contracts@0.10.0` |
| المكتبة الأساسية | Zod v4.1.12 |
| ملفات المصدر | 17 وحدة + index.ts |
| ملفات الاختبارات | 17 ملف اختبار |
| الاختبارات | 90 (90 ناجح، 0 فاشل) ✅ |
| المستهلكون | `@ahla/admin-web` (web)، Edge Functions (Deno) |

### ملاحظة معمارية (ARCH-03)

النظام **أحادي المستأجر** (Single-Tenant). لا يوجد عمود `tenant_id` في أي مكان. عزل البيانات عبر الهيكل التنظيمي (`legal_entities → branches → departments → teams`) + RLS + ABAC (`can_access_employee`).

---

## 2. وحدات العقود

### الوحدات الأساسية (مُصدّرة من index.ts)

| الوحدة | الملف | الوصف | الاختبار |
|---|---|---|---|
| **Access** | `access.ts` | أدوار، صلاحيات، مستويات الوصول | `access.test.ts` |
| **Employee** | `employee.ts` | بيانات الموظف، الحالات، الأنواع | `employee.test.ts` |
| **Operations** | `operations.ts` | عمليات تشغيلية (حضور، مواقع) | `operations.test.ts` |
| **Management** | `management.ts` | إدارة (إدارات، فرق، مناصب) | `management.test.ts` |
| **Admin Operations** | `adminOperations.ts` | عمليات إدارية (تأهيل، تقارير) | `adminOperations.test.ts` |
| **Advanced Operations** | `advancedOperations.ts` | عمليات متقدمة (حياة وظيفية) | `advancedOperations.test.ts` |
| **Enterprise Operations** | `enterpriseOperations.ts` | عمليات مؤسسية (مشاريع، مخاطر) | `enterpriseOperations.test.ts` |
| **Enterprise Management** | `enterpriseManagement.ts` | إدارة مؤسسية (استراتيجية، جودة) | `enterpriseManagement.test.ts` |
| **Release Governance** | `releaseGovernance.ts` | حوكمة الإصدارات | `releaseGovernance.test.ts` |
| **Live Location** | `liveLocation.ts` | طلبات الموقع المباشر | `liveLocation.test.ts` |
| **KPI** | `kpi.ts` | مراحل KPI، معايير، مقيّمون | `kpi.test.ts` ⚠️ |
| **Disputes** | `disputes.ts` | شكاوى، لجان، جلسات | `disputes.test.ts` |
| **Requests** | `requests.ts` | طلبات (إجازات، مهمات، مرافقة) | `requests.test.ts` |
| **Attendance Config** | `attendanceConfig.ts` | إعدادات الحضور | `attendanceConfig.test.ts` |
| **Holidays** | `holidays.ts` | عطل رسمية | `holidays.test.ts` |
| **Post Publishing** | `postPublishing.ts` | نشر إعلانات | `postPublishing.test.ts` |
| **Validation** | `validation.ts` | دوال تحقق مشتركة | `validation.test.ts` |

### ✅ اختبارات فاشلة سابقة — تم الإصلاح

> في جرد سابق (2026-07-26) كانت 3 اختبارات KPI فاشلة (ترتيب المراحل + توزيع المقيّمين).
> تم إصلاحها — جميع 90 اختبار تمر الآن بنجاح.

---

## 3. متغيرات التصميم — Design Tokens

| المقياس | القيمة |
|---|---|
| الحزمة | `@ahla/design-tokens@0.10.0` |
| الصادرات | `./theme.css`, `./tokens.json` |
| المستهلكون | `@ahla/admin-web` (CSS)، Flutter `ahla_design_tokens` (Dart) |

### الملفات

| الملف | الغرض |
|---|---|
| `theme.css` | متغيرات CSS (ألوان، خطوط، أبعاد) |
| `tokens.json` | قيم التصميم الخام بصيغة JSON |
| `lib/` | مكتبة Dart للاستخدام في Flutter |
| `pubspec.yaml` | تعريف حزمة Dart |
| `analysis_options.yaml` | قواعد تحليل Dart |

### نمط الاستهلاك

```
design-tokens/
├── theme.css       → Web: @import '@ahla/design-tokens/theme.css'
├── tokens.json     → Web: import tokens from '@ahla/design-tokens/tokens.json'
└── lib/            → Flutter: import 'package:ahla_design_tokens/...'
```

---

## 4. خريطة الاستهلاك

```
┌─────────────────────┐
│  shared-contracts   │
│  (Zod schemas)      │
│  17 وحدة            │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
admin_web    Edge Functions
(import)     (npm:@ahla/shared-contracts)

┌─────────────────────┐
│  design-tokens      │
│  CSS + JSON + Dart  │
└─────────┬───────────┘
          │
    ┌─────┴─────┐
    │           │
    ▼           ▼
admin_web    Flutter
(CSS vars)   (Dart lib)
```

---

## 5. توصيات

1. **إصلاح اختبارات KPI** — تحديث `kpi.test.ts` ليطابق القيم الفعلية في `kpi.ts` بعد تغييرات V17
2. **توحيد أسماء الصادرات** — بعض الوحدات تستخدم `.js` suffix وبعضها لا (في index.ts)
3. **توثيق العقود** — إضافة JSDoc للوحدات الأساسية (access, employee, operations)
4. **فحص توافق Deno** — التأكد من أن جميع Edge Functions تستطيع استيراد العقود
5. **مراجعة وحدات "Enterprise"** — `enterpriseOperations` و `enterpriseManagement` و `releaseGovernance` قد تكون مرتبطة بصفحات مخفية ← فحص ما إذا كانت مستخدمة فعلياً
