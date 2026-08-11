# الخطة الموحدة المحصنة V22.1 — نظام أحلى شباب HR
**التاريخ:** 2026-08-11  
**الفرع:** fix/p0-location-security-pipeline  
**الحالة:** المرجع التنفيذي الوحيد — يحل محل V17/V18/V19/V20/V21/V22  
**المؤلف:** Claude Opus 4.8 × Ahla Shabab Dev

---

# 0. جرد الواقع الفعلي للمستودع

> كل رقم هنا مُعتمد من الكود المصدري مباشرةً بتاريخ 2026-08-11.  
> أي مستند قديم يناقض هذه الأرقام — هذا الجرد هو المرجع.

## 0.1 قاعدة البيانات
| العنصر | القيمة الفعلية |
|---|---|
| إجمالي الـ Migrations | **158 ملف** (0001–0158) |
| آخر migration | `0158_grant_employee_devices_select.sql` |
| الرقم التالي المتاح | **0159** |
| استخدامات `has_permission()` | 671 في 65 ملف |
| استخدامات `current_is_full_access()` | 767 في 97 ملف |
| جداول بـ `USING (true)` | **21 حالة في 10 ملفات** (ليس 32 ولا 6) |
| ملفات pgTAP | **61 ملف** |
| إجمالي assertions | **~824 assertion** |

### جداول USING(true) الفعلية [قائم]
| الملف | عدد الحالات |
|---|---|
| 0002_permissions_roles_functions.sql | 3 |
| 0003_organization.sql | 2 |
| 0006_requests_workflow.sql | 3 |
| 0007_kpi_performance.sql | 6 |
| 0009_documents_tasks_policies.sql | 2 |
| 0011_audit_security_system.sql | 1 |
| 0033_talent_learning_documents_reports_notifications.sql | 1 |
| 0058_official_kpi_governance.sql | 1 |
| 0132_v17_official_holidays.sql | 1 |
| 0156_multi_department_support.sql | 1 |

## 0.2 Edge Functions [قائم]
| الدالة | الوصف |
|---|---|
| `identifier-sign-in` | تسجيل الدخول بالبريد/الهاتف/كود الموظف |
| `verify-attendance-punch` | تسجيل الحضور والانصراف |
| `admin-create-employee` | إنشاء موظف جديد (بلا rate limit — ثغرة) |
| `admin-resend-invite` | إعادة إرسال دعوة التفعيل |
| `webauthn-challenge` | توليد تحدي WebAuthn/Passkey |
| `passkey-register` | تسجيل مفتاح Passkey |
| `notification-dispatcher` | إرسال الإشعارات عبر FCM |
| `retention-cleanup` | تنظيف البيانات القديمة |
| `scheduled-report-runner` | تشغيل التقارير المجدولة |
| `integration-outbox-worker` | معالجة أحداث Outbox |
| `live-location-map-url` | رابط خريطة الموقع |
| `live-location-video-url` | رابط (محذوف من V22 — بلا كاميرا/صوت) |
| **_shared/cors.ts** | CORS مشترك |
| **_shared/secret.ts** | إدارة الأسرار |
| **_shared/phone.ts** | تنسيق الهاتف |

## 0.3 الويب (admin_web) [قائم]
| العنصر | القيمة |
|---|---|
| ملفات TSX في features/ | **45 ملف** |
| مساحات العمل | `/hr` + `/admin` + `/committee` |
| ملفات اختبار (web) | **8 ملفات** |
| ملفات اختبار (contracts) | **17 ملفاً** |
| إجمالي Vitest | **25 ملف** |
| مكتبة الـ Router | react-router-dom (Routes/Route) |

### مسارات الويب الفعلية [قائم]
**HR Workspace (`/hr`):**  
dashboard, employees, employees/new, employees/:id, attendance, attendance/operations, performance, recruitment, onboarding, reports, holidays, official-feed, notifications

**Admin Workspace (`/admin`):**  
dashboard, actions, live-location, live-location/monitoring, device-approvals, official-feed, organization, performance/cycles, disputes, access, settings, reports/scheduler, enterprise, operations, audit-security, integrations, notifications

**Committee Workspace (`/committee`):**  
disputes, notifications

## 0.4 Flutter (mobile_flutter) [قائم]
| العنصر | القيمة |
|---|---|
| ملفات Dart | **80 ملف** |
| FutureProvider | **47 استخداماً في 7 ملفات** |
| AsyncNotifier | **0** (لم يبدأ الترحيل بعد) |
| StateNotifier | **0** |
| ملفات اختبار | **6 ملفات** |
| FLAG_SECURE | **غير موجود** (محذوف أو لم يُضف قط) |

### مساحات عمل Flutter [قائم]
employee_workspace, manager_workspace, executive_workspace, operations_workspace, committee_workspace

### ملفات Provider الرئيسية [قائم]
- `mobile_providers.dart` — 36 FutureProvider
- `mobile_operations_providers.dart` — 2
- `mobile_executive_insights_providers.dart` — 3
- `auth_providers.dart` — 1
- `release_governance.dart` — 3
- `org_chart_page.dart` — 1
- `gps_preflight_banner.dart` — 1

## 0.5 CI/CD [قائم]
| الملف | الغرض |
|---|---|
| `web-ci.yml` | Type-check + Vitest + Build |
| `flutter-ci.yml` | analyze + test |
| `supabase-ci.yml` | pgTAP |
| `security-ci.yml` | فحص الأسرار والأمان |
| `release-candidate.yml` | APK/AAB signing |

---

# 1. القواعد الحاكمة — لا تُكسر أبداً

1. **العمل داخل المستودع الحالي** — نفس Flutter/Web/Supabase/Firebase/Package Name/Keystore.
2. **لا migration منشورة تُعدَّل** — migration جديدة برقم `<NEXT>` دائماً.
3. **لا حذف بيانات Production.**
4. **لا تعطيل RLS.**
5. **لا Service Role داخل Flutter أو المتصفح.**
6. **لا صفحة شكلية بلا Backend.**
7. **لا تكتب «تم» دون:**
   - Root Cause
   - الملفات المعدلة
   - Migration/RPC/RLS عند الحاجة
   - Tests
   - Runtime Evidence
8. **ابدأ بـ Discovery** قبل إنشاء أي جدول أو Function أو Route.
9. **لا أسرار في الكود** — env vars وSupabase secrets فقط.
10. **commit فوري بعد كل تغيير** — مع push لمنع ضياع العمل (حادثة الفرع المتشعب 2026-07-31).

## 1A. تصنيف الكود الإلزامي
كل مثال SQL أو Dart أو TypeScript في هذه الخطة يحمل:
- `[قائم]` — موجود فعلاً ومُتحقق منه
- `[مقترح]` — تصميم مطلوب، يُنسخ بعد مطابقة Schema الفعلي
- `[توثيقي]` — مثال للشرح فقط
- `[ملغى]` — قرار رسمي بالإلغاء، لا يعود

## 1B. قاعدة Migrations
- استمرار بالترقيم التسلسلي `NNNN_description.sql` (لا تحويل لـ Timestamp — يكسر الترتيب)
- الرقم التالي: **0159**
- فحص قبل الإنشاء دائماً:
  ```bash
  ls supabase/migrations/ | sort | tail -3
  ls supabase/migrations/ | cut -c1-4 | sort | uniq -d
  ```

## 1C. USING(true) — Default Deny
- لا قائمة ثابتة مسبقة.
- أي جدول يُطلب له `USING(true)` → يذهب لـ Security Reviewer أولاً.
- الجداول الـ 10 الحالية تبقى كما هي (موثقة في §0.1) — لا توسيع بلا مراجعة.
- يُنشأ: `docs/security/RLS_PUBLIC_REFERENCE_ALLOWLIST.md`

## 1D. RLS — ترحيل تدريجي
ممنوع استبدال `current_is_full_access()` دفعة واحدة (767 استخدام في 97 ملف).

المراحل:
1. إنشاء `has_scoped_permission()` واختبارها عزلاً [مقترح]
2. إضافة السياسة الجديدة بجانب القديمة (Shadow mode)
3. مقارنة القرارات في Shadow Logs
4. تحويل Domain واحد فقط
5. RLS negative tests لكل دور
6. مراقبة Staging
7. إزالة المسار القديم بعد التحقق
8. تكرار Domain-by-Domain

---

# 2. نموذج الوكلاء الواقعي

> V22 اقترحت 15 وكيلاً × 4–9 مساعدين = 60–135 جلسة. هذا مناسب لفريق بشري.  
> الواقع: 4–5 وكلاء متخصصين بفروع منفصلة + Integration Lead.

## 2.1 الوكلاء
| الوكيل | الفرع | النطاق |
|---|---|---|
| **DB Agent** | `agent/db` | Migrations + RLS + RPC + pgTAP |
| **Web Agent** | `agent/web` | React/TypeScript + Contracts + Web tests |
| **Mobile Agent** | `agent/mobile` | Flutter + Dart + Riverpod migration |
| **Security Agent** | `agent/security` | RLS hardening + Edge Function security + IDOR |
| **Integration Lead** | `main` (merge) | Contracts + Merge queue + Traceability |

## 2.2 قواعد الوكلاء
- **لا وكيلان على الملف نفسه** في نفس الوقت.
- **File Ownership Registry** يُحدَّث قبل التعديل.
- **Migration Reservation** يُسجَّل قبل إنشاء الملف.
- كل وكيل يسلّم تقرير 10 نقاط (انظر §9).

## 2.3 ترتيب الدمج
1. shared-contracts/types
2. Database migrations
3. RLS/RPC/Edge Functions
4. Repositories/Services
5. State/Application layer
6. UI
7. Tests
8. Documentation

---

# 3. الأدوار الوظيفية المحسومة

## 3.1 الأدوار السبعة
| القالب | Slugs الداخلية | منح من |
|---|---|---|
| السكرتير التنفيذي (Main Admin) | `main-admin`, `executive-secretary` | نفسه فقط |
| مدير الموارد البشرية | `hr-manager` | Main Admin |
| المدير التنفيذي | `executive-director` | Main Admin |
| مدير التشغيل | `operations`, `operations-manager-*` | Main Admin |
| عضو اللجنة | capability إضافية | Main Admin |
| المدير المباشر | `direct-manager` | HR أو Main Admin |
| الموظف | `employee` | HR أو Main Admin |

## 3.2 صلاحيات الإنشاء
**HR** ينشئ: موظف + مدير مباشر + Operations  
**Main Admin** ينشئ: الجميع بما فيهم Admin + Executive + Committee  
**ممنوع**: HR يمنح دوراً علياً أو Executive أو Admin

## 3.3 نظام الصلاحيات — إعادة البناء [مقترح]
- إلغاء عرض 300+ Permission خام
- قوالب أدوار ثابتة بالعربية
- اختيار الدور يطبق مجموعة الصلاحيات تلقائياً
- Slug التقني في وضع متقدم للقراءة فقط
- Main Admin فقط يمنح الدور من واجهة Admin

---

# 4. الموظفون وإدارتهم

## 4.1 حالة الموظف عند الإنشاء
أي موظف ينشأ من HR أو Main Admin:
- `employment_status = active` فوراً
- يظهر فوراً في: الدليل + الحضور + الهيكل + تطبيق المدير التنفيذي + التقارير
- **لا "غير نشط" أو "تحت الدعوة"** — حالة العمل منفصلة عن حالة الدخول

حالات الدخول (منفصلة عن حالة العمل):
- نشط
- لم يسجل الدخول بعد
- إعداد كلمة المرور معلق
- جاهز

## 4.2 الموظف متعدد الإدارات [مقترح]

### P0 (أساسي)
- Primary Assignment: إدارة أساسية + وظيفة + مدير + وردية + موقع عمل
- Secondary Assignments: إدارة + وظيفة + نسبة تخصيص + بداية/نهاية + مدير وظيفي اختياري
- الموظف يظهر مرة واحدة في الدليل
- طلب الإجازة → المدير الأساسي
- KPI → Primary Assignment

### P1 (موسع — يأتي لاحقاً)
- تقارير توزيع الوقت
- نسب التخصيص في التقارير
- لوحات متعددة الإدارات

## 4.3 عمليات الموظف
| العملية | من يملكها |
|---|---|
| تعديل البيانات | HR + Main Admin |
| تغيير المدير | HR + Main Admin |
| إدارة الجهاز | HR + Main Admin |
| تعطيل | HR + Main Admin |
| أرشفة | HR + Main Admin |
| حذف دائم | Main Admin فقط (بعد تحقق قوي) |
| استعادة | Main Admin |

---

# 5. الحضور والأجهزة والجيوفنس

## 5.1 المواعيد والتذكيرات
- حضور: 10:00 | انصراف: 18:00
- تذكيرات: 09:45 / 10:00 / 17:45 / 18:00

**لا تذكير عند:** إجازة + مأمورية + قافلة + فاندي + إجازة رسمية + يوم راحة + حساب معطل + المدير التنفيذي

## 5.2 Geofence [قائم في mig 0003، قابل للضبط مقترح]
- النطاق الافتراضي: **300 متر** لكل موقع عمل
- الحقول المقترحة للضبط: `attendance_radius_meters`, `max_location_age_seconds`, `max_accuracy_meters`
- تعديل من Main Admin/HR بصلاحية منفصلة
- كل تعديل يسجل في Audit
- يطبق على الطلبات الجديدة فقط
- حدود آمنة: لا قيمة صفر، لا نطاق مبالغ فيه

## 5.3 قواعد الموقع
- Fresh Location — لا يتجاوز عمره **15 ثانية**
- دقة ≤ 100 متر
- Mock Location: رفض
- Impossible Travel: رفض
- لا قبول `captured_at` كوقت معتمد — `server_received_at` هو المرجع
- PostGIS/Haversine موحد

## 5.4 الورديات الليلية [مقترح — إصلاح]
ممنوع إغلاق اليوم عند 23:59 تلقائياً.  
الإغلاق يعتمد: `work_date + shift_start + shift_end + crosses_midnight + grace_period`  
المنطقة: `Africa/Cairo`

## 5.5 حالة الزر
- قبل الحضور → "تسجيل الحضور"
- بعد الحضور → "تسجيل الانصراف"
- بعد الانصراف → "اليوم مكتمل" (حتى اليوم التالي)
- نسيان الانصراف → "بصمة انصراف مفقودة" + طلب تصحيح (لا وقت وهمي)

## 5.6 الجهاز
**حالات الجهاز:** بانتظار الموافقة / نشط / ملغى / ملغى تلقائياً / محظور

**قواعد:**
- جهاز نشط واحد للموظف
- تسجيل جهاز جديد → HR أو Main Admin يعتمد وفق Recovery Flow
- Operations لا يعتمد جهازه الشخصي
- لا حضور بجهاز غير نشط
- عند فقد الهاتف: HR يسحب الجهاز + يسحب الجلسات + يطلب إعادة توثيق

## 5.7 حضور بلا اتصال
- **لا يعتبر حضوراً أبداً**
- يُخزَّن سجل محلي محدود: وقت المحاولة + سبب الفشل + حالة الشبكة
- لا نجاح أخضر
- بعد تكرار الفشل: إشعار للموظف + خيار طلب تصحيح

---

# 6. الإجازات والتكليفات والتصحيحات

## 6.1 التسمية
- في التنقل: **"طلب إجازة"**
- داخل الصفحة: **"الإجازات والتكليفات"**
- 4 تبويبات: الإجازات | أذونات الحضور | تصحيحات الحضور | تكليفات العمل

## 6.2 سياسة الإجازات
> القيم قابلة للتعديل من Main Admin — تتطلب مراجعة قانونية قبل Production.

| النوع | الرصيد |
|---|---|
| اعتيادية | 15 يوماً |
| عارضة/طارئة | 6 أيام |
| مرضية | يومان شهرياً |
| 50+ سنة أو 10+ سنوات خدمة | 30 إجمالاً (20 اعتيادية + 10 عارضة) |

**الإجازة العارضة/الطارئة:**
- تنفذ فوراً إذا: `emergency_leave_auto_approval_enabled = true` + رصيد كافٍ + لا تداخل
- Audit + إشعار المدير وHR
- عند التعطيل: تسلك مسار المدير المباشر

**محذوف [ملغى]:** إجازة وضع، إجازة رعاية طفل (الطلبات التاريخية تبقى)

## 6.3 التصعيد
**مدير الموظف هو المدير التنفيذي:**
- مهلة: 6 ساعات → يصعد لـ Operations المخول
- القرار يسجل "بالإنابة"

**مدير الموظف مدير آخر:**
- مهلة: 12 ساعة → يخطر السكرتير التنفيذي
- يستطيع: تمديد المهلة + نقل الطلب + قرار Break-glass

## 6.4 المأموريات والقوافل والفاندي
- عمل رسمي — لا تخصم من الإجازات — لا تحسب غياباً
- الفاندي الكامل: لا يحتاج بصمة
- التكليف الجزئي: يغطي ساعاته فقط

## 6.5 تصحيحات الحضور
```text
الموظف → المدير يراجع → HR ينفذ → إعادة حساب اليوم والشهر وKPI
```
- لا يعدل الحدث الخام — يضيف حدث Correction
- أنواع: نسيت حضور / نسيت انصراف / وقت غير صحيح / موقع خاطئ / حالة يوم خاطئة

---

# 7. KPI — المسار المحسوم

## 7.1 المسار الوحيد
```text
السكرتير التنفيذي يفتح الدورة
→ الموظف يقيّم نفسه ويرسل
→ HR والمدير المباشر يراجعان بالتوازي (حقول منفصلة)
→ Barrier بعد اكتمال الاثنين
→ السكرتير التنفيذي يراجع ويرسل للمدير التنفيذي
→ المدير التنفيذي يقر أو يطلب مراجعة
→ السكرتير يغلق الدورة
```
أي مسار تسلسلي قديم **[ملغى]**.

## 7.2 توزيع الدرجات
**HR (30 درجة):**
- الحضور والانصراف: 20
- الصلاة في المسجد: 5
- حلقة الشيخ وليد: 5

**المدير المباشر (70 درجة):**
- الأهداف: 40
- الكفاءة: 20
- السلوك: 5
- المبادرات: 5

## 7.3 القيود
- الموظف يرى نموذج نفسه فقط
- HR يعدل حقوله فقط / المدير يعدل حقوله فقط
- Version Lock لمنع الكتابة المتعارضة
- المدير التنفيذي **لا يخضع للتقييم**
- Audit لكل درجة

---

# 8. لجنة حل المشكلات

## 8.1 نموذج الشكوى
**يبقى:** العنوان + الوصف (3–300 كلمة) + الأطراف + الشهود + الإقرارات  
**محذوف [ملغى]:** الأولوية + مكان الواقعة + الأدلة

## 8.2 المسار
```text
الموظف → السكرتير التنفيذي → اللجنة → حل داخلي أو إجراء مقترح → المدير التنفيذي → HR للتنفيذ → الإغلاق
```

## 8.3 الصلاحيات
- الموظف يرى قضيته فقط
- اللجنة ترى المسند إليها فقط
- HR ينفذ فقط بعد موافقة المدير التنفيذي
- عضوية اللجنة = Capability إضافية بجانب الدور الأساسي (يمنحها Main Admin)

---

# 9. الموقع المباشر والإشعارات

## 9.1 رحلة طلب الموقع
```text
Executive → RPC → Location Request → Notification Outbox → Dispatcher → FCM → Android → فتح الطلب → Fresh GPS → Response → Map/Address/Accuracy
```

## 9.2 قناة الإشعار [مقترح]
- Channel: `urgent_location_v6`
- High Priority + صوت مخصص + اهتزاز + Heads-up + Full-Screen Intent
- يعمل: Foreground/Background/Terminated/Locked
- Native `FirebaseMessagingService`

## 9.3 القيود المحسومة [ملغى]
- **لا Video** — `live-location-video-url` موجودة في الكود لكن مقيدة أو محذوفة وظيفياً
- **لا Camera/Microphone**
- **لا Tracking خفي**
- **لا ضمان تجاوز Do Not Disturb**

## 9.4 إشعارات Android عند الرفض
إذا رفض المستخدم `POST_NOTIFICATIONS` أو Full-Screen Intent:
- In-app banner واضح
- صفحة إعدادات الإشعارات
- المدير التنفيذي يرى "الجهاز غير قادر على استقبال التنبيه العاجل"

---

# 10. الويب — الإصلاحات المطلوبة

## 10.1 نظام النوافذ المنبثقة [مقترح — إصلاح شامل]
كل Modal/Dialog يجب أن:
- يستخدم `createPortal` إلى `document.body`
- `position: fixed`, `inset: 0`
- يظهر في منتصف الشاشة
- أعلى من Header وSidebar (z-index مضبوط)
- يقفل Body Scroll
- يدعم ESC وFocus Trap
- أقصى ارتفاع `90dvh`
- المحتوى الطويل يمرر **داخل** النافذة

## 10.2 مساحات العمل
**Main Admin** يفتح: `/admin` + `/hr`  
**HR** يفتح: `/hr` فقط — `/admin/*` = Forbidden  
المنع: UI + Route Guard + Server RLS

## 10.3 معالجة الأخطاء
- **لا Zod Stack للمستخدم** — رسالة عربية واضحة
- **لا Supabase errors خام**
- Error mapper موحد (Zod → رسالة عربية، Supabase code → رسالة عربية)

---

# 11. Flutter — الإصلاحات المطلوبة

## 11.1 ترحيل Riverpod [مقترح — تدريجي]
**الوضع الحالي:** 47 FutureProvider في 7 ملفات / 0 AsyncNotifier

**الأولوية:**
1. ملفات الـ Provider الحرجة: `mobile_providers.dart` (36 استخداماً)
2. ترحيل تدريجي: FutureProvider → AsyncNotifierProvider
3. لا ترحيل جماعي في commit واحد

## 11.2 UX — إصلاحات عامة
- RTL كامل — الأرقام والهواتف والـ IDs تبقى LTR
- Light/Dark/System
- SafeArea — لا محتوى خلف Bottom Bar
- حالات: Loading / Empty / Error / Offline / Forbidden
- لا Spinner بلا نهاية
- لا أرقام صفرية عند فشل الاستعلام
- صفحات ثقيلة: Pagination + Cache + Cancellation + Indexes

## 11.3 الصفحات المحذوفة [ملغى]
- الخصوصية وبياناتي (كصفحة مستقلة)
- التدريب والتعليم والمهارات
- مستنداتي
- العهد
- نهاية العقد
- الرواتب
- مكتب الخدمات (يعود فقط كنظام Tickets كامل)

---

# 12. الأمان

## 12.1 Rate Limiting المفقود [مقترح — P0]
| Edge Function | الوضع الحالي | المطلوب |
|---|---|---|
| `admin-create-employee` | **بلا rate limit** | يُضاف فوراً |
| `identifier-sign-in` | — | فحص |
| `verify-attendance-punch` | — | فحص |
| `webauthn-challenge` | — | فحص |
| `passkey-register` | — | فحص |
| `notification-dispatcher` | — | فحص |

مفتاح Rate Limit يجمع: `user_id + IP + device_id + action`  
رسائل عربية + Retry-After + Audit

## 12.2 Break-glass
- يطلبه Main Admin مخول + سبب إلزامي + نطاق محدد
- مدة قصوى: **60 دقيقة** (افتراضي) — انتهاء تلقائي
- إشعار أمني + Audit قبل/بعد
- لا يصبح Role دائماً

## 12.3 CSP وCORS
**الويب:** Content-Security-Policy + frame-ancestors + Referrer-Policy + X-Content-Type-Options  
**Edge Functions:** Allowlist origins — لا wildcard مع credentials — OPTIONS صحيح — JWT validation

## 12.4 اختبارات الأمان السلبية
يجب أن تفشل:
- موظف يفتح تقييم غيره
- مدير يرى فريقاً آخر
- Operations يعتمد طلبه الشخصي
- HR يفتح `/admin/*`
- HR ينشئ Executive
- المدير يغير HR Score
- غير Executive يطلب موقعاً
- HR ينفذ جزاء غير معتمد
- حساب غير مرتبط يقرأ بيانات موظفين

---

# 13. كشف الحضور الشهري

## 13.1 محتوى اليوم (18 حقلاً)
التاريخ + اليوم + الحالة + الحضور + الانصراف + جدول العمل + الساعات المطلوبة + الساعات الفعلية + التأخير + الانصراف المبكر + الإضافي + غياب + إجازة + إجازة رسمية + إذن حضور + إذن انصراف + مأمورية + قافلة + فاندي + بصمة ناقصة + تصحيح + ملاحظات

## 13.2 ملخص الشهر (15 حقلاً)
أيام الشهر + أيام العمل المطلوبة + أيام الحضور + أيام الغياب + الإجازات + المأموريات + القوافل + الفاندي + التأخيرات + ساعات العمل المطلوبة والفعلية + المتوسط + الإضافي + نسبة الحضور + نسبة الالتزام + البصمات الناقصة

## 13.3 قواعد الحساب
- المقام = أيام العمل المطلوبة فقط (لا أيام الإجازة والعطل)
- `Boolean` يرجع `Boolean` — لا Object (إصلاح عقد قائم)
- التطبيق + الويب + PDF/CSV = أرقام متطابقة

---

# 14. Feature Flags

| الـ Flag | الغرض |
|---|---|
| `permission_based_rls_rollout` | ترحيل RLS تدريجي |
| `kpi_parallel_workflow` | مسار KPI الموازي |
| `org_chart_v2` | الهيكل الوظيفي الجديد |
| `multi_department_support` | الموظف متعدد الإدارات |
| `new_notifications` | قناة urgent_location_v6 |
| `requests_center` | مركز الطلبات |

**قاعدة:** Flags للتحكم في العرض والتدفق — لا لتجاوز RLS.

---

# 15. ترتيب التنفيذ

## المرحلة 0 — التأسيس (قبل أي تغيير)
- [ ] Backup وGit Tag
- [ ] قراءة جرد §0 كاملاً
- [ ] تأكيد آخر Migration رقم وصحة الـ Stack
- [ ] إنشاء `docs/security/RLS_PUBLIC_REFERENCE_ALLOWLIST.md`
- [ ] إنشاء `docs/FILE_OWNERSHIP_REGISTRY.md`

## المرحلة 1 — الأدوار والهوية
- [ ] مراجعة وإصلاح Role Templates في الويب
- [ ] إصلاح واجهة إسناد الصلاحيات (إلغاء عرض 300+ permission)
- [ ] قوالب الأدوار العربية
- [ ] اختبار: HR لا ينشئ Executive أو Admin

## المرحلة 2 — الموظفون والجهاز
- [ ] إصلاح `employment_status = active` عند الإنشاء
- [ ] Recovery Flow للجهاز
- [ ] إصلاح rate limit على `admin-create-employee` (P0)
- [ ] Multi-Department P0 Schema

## المرحلة 3 — الحضور والجيوفنس
- [ ] Geofence قابل للضبط لكل موقع عمل
- [ ] إصلاح الورديات الليلية
- [ ] تدقيق `server_received_at` vs `captured_at`
- [ ] اختبار: رفض خارج 300م + رفض Mock Location

## المرحلة 4 — الإجازات والتكليفات
- [ ] تحقق من حالات الإجازة العارضة التلقائية
- [ ] إصلاح التصعيد (6h / 12h)
- [ ] ربط المأموريات بالحضور وKPI
- [ ] 4 تبويبات في واجهة الطلبات

## المرحلة 5 — KPI
- [ ] تدقيق مسار KPI الموازي في الكود
- [ ] Version Lock
- [ ] استثناء المدير التنفيذي من التقييم
- [ ] اختبار الحاجز (Barrier) بعد HR والمدير

## المرحلة 6 — اللجنة والمنشورات
- [ ] إصلاح نموذج الشكوى (حذف الأولوية/المكان/الأدلة)
- [ ] ربط عضوية اللجنة بـ Capability
- [ ] 9 أنواع منشورات في الويب والموبايل

## المرحلة 7 — كشف الشهر والتقارير
- [ ] إصلاح Boolean في عقد كشف الشهر
- [ ] 18 حقل يوم + 15 حقل ملخص
- [ ] تطابق الأرقام بين الهاتف والويب والـ PDF

## المرحلة 8 — الموقع والإشعارات
- [ ] إصلاح قناة `urgent_location_v6`
- [ ] Native FirebaseMessagingService
- [ ] سجلات Outbox: sent/delivered/opened/responded

## المرحلة 9 — UI/UX وأداء
- [ ] إصلاح Modal system (Portal + fixed + 90dvh)
- [ ] Error mapper (Zod + Supabase → عربي)
- [ ] Pagination + Cancellation في الصفحات الثقيلة
- [ ] ترحيل FutureProvider → AsyncNotifierProvider (تدريجي)

## المرحلة 10 — أمان وRLS
- [ ] إنشاء `has_scoped_permission()` [مقترح]
- [ ] Shadow evaluation لدومين واحد
- [ ] اختبارات RLS السلبية التسع
- [ ] CSP + CORS headers

## المرحلة 11 — الإطلاق
- [ ] Load tests على Staging (ذروة / 2× / 3×)
- [ ] Android matrix (Samsung + أخرى / 13/14/15)
- [ ] Release Build + signed APK/AAB
- [ ] Rollback مختبر

---

# 16. صيغة تسليم كل وكيل (10 نقاط إلزامية)

1. **ملخص التنفيذ** — ماذا تغير وماذا بقي
2. **الأسباب الجذرية** — لماذا كان المشكلة موجودة
3. **الملفات المعدلة** — مسار كامل لكل ملف
4. **Migrations/RPC/RLS/Edge Functions** — أرقام وأسماء
5. **الاختبارات الناجحة والفاشلة** — عدد + نتائج
6. **أدلة Runtime** — صور قبل/بعد أو logs
7. **المخاطر والقيود المتبقية** — ما لم يُحل
8. **Commit hashes** — SHA كامل
9. **تعليمات الدمج** — Merge Queue step
10. **Rollback** — الخطوات الكاملة

---

# 17. فحص ما بعد التطبيق — Audit Framework كامل

> هذا الجزء هو ما يميز V22.1 — خطة الفحص الشامل بعد انتهاء عمل الوكلاء.

## 17.1 Audit Phase 0 — فحص البنية

### DB Integrity Check [مقترح — سكربت]
```sql
-- [مقترح] فحص أرقام Migrations
SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;

-- [مقترح] فحص تكرار الأرقام
SELECT LEFT(filename, 4) AS prefix, COUNT(*) 
FROM (SELECT regexp_replace(name, '^(\d+).*', '\1') AS filename 
      FROM supabase_migrations.schema_migrations) t
GROUP BY prefix HAVING COUNT(*) > 1;

-- [مقترح] فحص أعداد الجداول
SELECT schemaname, COUNT(*) FROM pg_tables WHERE schemaname = 'public' GROUP BY schemaname;

-- [مقترح] فحص policies مفتوحة
SELECT tablename, policyname, qual 
FROM pg_policies 
WHERE qual = 'true' AND schemaname = 'public'
ORDER BY tablename;
```

### RLS Coverage Check [مقترح]
```sql
-- [مقترح] جداول بلا RLS
SELECT tablename FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename NOT IN (SELECT tablename FROM pg_policies WHERE schemaname = 'public')
ORDER BY tablename;
```

### Orphan Auth Users Check [مقترح]
```sql
-- [مقترح] مستخدمون في auth.users بلا employee record
SELECT u.id, u.email, u.created_at
FROM auth.users u
LEFT JOIN public.employees e ON e.auth_user_id = u.id
WHERE e.id IS NULL AND u.deleted_at IS NULL;
```

## 17.2 Audit Phase 1 — فحص الأمان

### SECDEF RPC Leak Pattern [الأكثر خطورة]
هذا النمط المتكرر: RPCs بـ SECURITY DEFINER تحمي بـ `auth.uid() IS NULL` فقط — تسرب بيانات الجميع لأي موظف مصادق.

```sql
-- [مقترح] اكتشاف RPCs بلا scoping
SELECT p.proname, p.prosecdef
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' 
AND p.prosecdef = true
AND p.prosrc NOT ILIKE '%auth.uid()%'
ORDER BY p.proname;
```

فحص يدوي لكل RPC: هل تصفي النتائج بـ `employee_id` أو `org_id` مرتبط بالمستخدم الحالي؟

### Rate Limit Audit
```bash
# [مقترح] فحص rate limiting في Edge Functions
grep -l "rateLimit\|rate_limit\|retry-after\|Retry-After" supabase/functions/*/index.ts
```

**المتوقع:** `admin-create-employee` غائبة من النتائج (ثغرة P0 موثقة).

### IDOR Test Matrix [مقترح — اختبارات يدوية]
| السيناريو | الدور المهاجم | الهدف | النتيجة المتوقعة |
|---|---|---|---|
| قراءة تقييم KPI غيره | Employee A | Employee B KPI | 403 / empty |
| تعديل بيانات موظف آخر | Employee | أي موظف | 403 |
| رؤية فريق إدارة أخرى | Manager A | Department B | empty |
| طلب موقع | Employee | أي موظف | 403 |
| اعتماد طلب شخصي | Operations | نفسه | 403 |
| فتح `/admin` | HR | admin routes | 403 |
| إنشاء Executive | HR | أي مستخدم | 403 |
| تنفيذ جزاء غير معتمد | HR | أي موظف | 403 |

## 17.3 Audit Phase 2 — فحص الوظائف

### KPI Parallel Flow Verification
```sql
-- [مقترح] تحقق من أن HR و Manager يعملان بالتوازي
-- حالة: كلاهما submitted لكن Barrier لم يُفعَّل
SELECT k.id, k.employee_id, k.hr_submitted_at, k.manager_submitted_at, k.status
FROM kpi_evaluations k
WHERE k.hr_submitted_at IS NOT NULL 
AND k.manager_submitted_at IS NOT NULL
AND k.status != 'secretary_review'
LIMIT 10;
```

### Attendance Integrity Check
```sql
-- [مقترح] تحقق من عدم وجود وردية مغلقة عند 23:59 بشكل عام
SELECT COUNT(*) as suspicious_closes
FROM attendance_records
WHERE EXTRACT(HOUR FROM check_out) = 23 
AND EXTRACT(MINUTE FROM check_out) = 59
AND EXTRACT(SECOND FROM check_out) BETWEEN 55 AND 59;
```

### Monthly Statement Consistency
```sql
-- [مقترح] تحقق من تطابق المجاميع
-- مثال: إجمالي أيام الحضور + الغياب + الإجازات = أيام العمل المطلوبة
SELECT 
  employee_id,
  month_year,
  required_working_days,
  (present_days + absent_days + leave_days + holiday_days + assignment_days) AS calculated_total,
  ABS(required_working_days - (present_days + absent_days + leave_days + holiday_days + assignment_days)) AS discrepancy
FROM monthly_attendance_summaries
WHERE ABS(required_working_days - (present_days + absent_days + leave_days + holiday_days + assignment_days)) > 0
LIMIT 20;
```

## 17.4 Audit Phase 3 — فحص الكود

### Web — فحص تلقائي
```bash
# Type-check كامل
npx tsc --noEmit -p apps/admin_web/tsconfig.json

# Lint
npx eslint apps/admin_web/src --max-warnings 0

# Tests
npm run test --workspace=apps/admin_web
npm run test --workspace=packages/shared-contracts

# Build
npm run build
```

**عتبة القبول:** 0 type errors / 0 lint errors / 0 test failures / build ناجح

### Flutter — فحص تلقائي
```bash
cd apps/mobile_flutter
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release
```

**عتبة القبول:** 0 errors / 0 test failures / APK ناجح

### pgTAP — فحص كامل
```bash
npx supabase test db
```

**عتبة القبول:** جميع الـ 61+ ملف PASS — الرقم يزيد بعد إضافة اختبارات جديدة

## 17.5 Audit Phase 4 — فحص RLS السلبية

### قالب pgTAP للـ RLS السلبية [مقترح]
```sql
-- [مقترح] قالب اختبار RLS سلبي
BEGIN;
SELECT plan(9);

-- إعداد: موظفان مختلفان
SET LOCAL role = authenticated;
SET LOCAL "request.jwt.claims" = '{"sub": "employee-a-uuid"}';

-- 1. موظف لا يرى KPI غيره
SELECT is_empty(
  $$ SELECT * FROM kpi_evaluations WHERE employee_id != auth.uid()::uuid $$,
  'موظف لا يرى تقييمات غيره'
);

-- 2. مدير لا يرى فرق أخرى
SELECT is_empty(
  $$ SELECT * FROM employees WHERE department_id NOT IN (SELECT department_id FROM managers WHERE manager_id = auth.uid()::uuid) $$,
  'مدير لا يرى موظفين خارج فريقه'
);

-- ... إلخ (9 اختبارات من القائمة في §12.4)
SELECT * FROM finish();
ROLLBACK;
```

## 17.6 Audit Phase 5 — Load Tests

### Staging Load Profile
| السيناريو | الحمل | معيار القبول |
|---|---|---|
| ذروة الحضور المتزامن | 100% موظفين نشطين × دقيقة | لا duplicate punch |
| 2× الذروة | 200% | لا deadlock |
| 3× لفترة قصيرة | 300% / 60 ثانية | لا DB connection overflow |
| فتح كشف الشهر للجميع | query load | < 5 ثوان |
| منشور للجميع | FCM dispatch | لا lost event |
| طلبات موقع متزامنة | 10 concurrent | لا race condition |

**ما يُفحص:**
- DB connections/pool utilization
- Edge Function P99 latency
- Deadlocks في pg_stat_activity
- Notification Outbox: لا أحداث مفقودة
- Permission regressions تحت الحمل

## 17.7 Audit Phase 6 — Android Device Matrix

| الجهاز | Android | بصمة | GPS | إشعارات | الحضور | الموقع العاجل |
|---|---|---|---|---|---|---|
| Samsung Galaxy | 13 | ✓ | on | granted | تسجيل | فتح |
| Samsung Galaxy | 14 | ✓ | off→on | granted | رفض→نجاح | تأخير |
| Samsung Galaxy | 15 | ✗ | on | denied | تسجيل | banner |
| جهاز آخر | 13 | ✓ | on | granted | تسجيل | فتح |
| جهاز آخر | 14 | ✓ | on | granted | تسجيل | فتح |
| أي جهاز | 15 | ✓ | on | granted | Terminated | Full-Screen |

## 17.8 Audit Phase 7 — E2E Checklist

| المسار | الحالة |
|---|---|
| إنشاء موظف → فوري في الدليل | ☐ |
| تسجيل جهاز → اعتماد HR → حضور | ☐ |
| حضور داخل 300م → قبول | ☐ |
| حضور خارج 300م → رفض | ☐ |
| Mock Location → رفض | ☐ |
| نسيان الانصراف → طلب تصحيح | ☐ |
| إجازة عارضة تلقائية (flag=true) | ☐ |
| إجازة يرفضها المدير | ☐ |
| تصعيد تلقائي بعد 6 ساعات | ☐ |
| KPI: HR + Manager بالتوازي → Barrier | ☐ |
| شكوى → لجنة → Executive → HR | ☐ |
| منشور → يصل لجميع الأجهزة | ☐ |
| طلب موقع كامل (Executive → Employee) | ☐ |
| كشف شهر: الهاتف = الويب = PDF | ☐ |
| HR لا يفتح `/admin` | ☐ |
| Admin يفتح `/admin` + `/hr` | ☐ |

## 17.9 Release Gate — شرط الإطلاق

**لا يُطلق النظام حتى:**
- [ ] صفر P0
- [ ] صفر P1 غير معتمد
- [ ] جميع Audit Phases (0–8) مكتملة
- [ ] Release Build ناجح (web + APK/AAB)
- [ ] Migrations verified على Staging
- [ ] Soak period: 48 ساعة على Staging دون أخطاء
- [ ] Backup + Rollback مختبران
- [ ] Release Readiness Report موقّع

---

# 18. تتبع المتطلبات (Traceability)

| المتطلب | الوكيل | الملفات | Migration | Tests | الحالة |
|---|---|---|---|---|---|
| rate limit على admin-create-employee | Security | functions/admin-create-employee/index.ts | — | — | DISCOVERED |
| Geofence قابل للضبط | DB | migrations/0159_* | 0159 | pgTAP | DISCOVERED |
| USING(true) Allowlist | Security | docs/security/RLS_PUBLIC_REFERENCE_ALLOWLIST.md | — | — | DISCOVERED |
| has_scoped_permission() | DB | migrations/0160_* | 0160 | pgTAP | DISCOVERED |
| Modal Portal system | Web | features/**/*.tsx | — | Vitest | DISCOVERED |
| FutureProvider → AsyncNotifier | Mobile | mobile_providers.dart | — | Flutter test | DISCOVERED |
| KPI Parallel Barrier | DB+Web+Mobile | — | تدقيق فقط | pgTAP | DISCOVERED |
| employment_status=active | DB | migrations | تدقيق | pgTAP | DISCOVERED |

**حالات التتبع:** DISCOVERED → DESIGNED → IMPLEMENTED → TESTED → RUNTIME_VERIFIED → RELEASED

---

# 19. Definition of Done

لا يُعتبر النظام جاهزاً حتى:

### أمان
- [ ] IDOR tests: 9/9 PASS
- [ ] RLS negative tests: جميع السيناريوهات PASS
- [ ] rate limit على جميع Edge Functions الحساسة
- [ ] SECDEF RPC leak pattern: محلول أو موثق
- [ ] CSP + CORS مضبوطان

### وظائف
- [ ] الصلاحيات بالقوالب العربية تعمل
- [ ] Modals في المنتصف (لا اقتطاع خلف Header)
- [ ] الموظف الجديد نشط فوراً
- [ ] HR لا يمنح أدواراً عليا
- [ ] Multi-Assignment P0 يعمل
- [ ] الحضور داخل 300م فقط
- [ ] الجهاز والبصمة يعملان
- [ ] كشف الشهر متسق (هاتف = ويب = PDF)
- [ ] الإجازات والتكليفات تعمل
- [ ] KPI بالمسار النهائي (Parallel + Barrier)
- [ ] اللجنة والجزاء يعملان
- [ ] المنشورات والتصويتات تعمل
- [ ] الموقع يعمل خارج التطبيق

### جودة
- [ ] Web: 0 type errors / 0 lint errors / 0 test failures
- [ ] Flutter: 0 errors / 0 test failures
- [ ] pgTAP: كل الملفات PASS
- [ ] Release Build ناجح
- [ ] Load tests اجتازت معايير القبول
- [ ] Android matrix: 6 سيناريوهات PASS

### توثيق
- [ ] `docs/security/RLS_PUBLIC_REFERENCE_ALLOWLIST.md` موجود ومحدث
- [ ] `docs/FILE_OWNERSHIP_REGISTRY.md` موجود ومحدث
- [ ] Traceability table: جميع المتطلبات RELEASED
- [ ] Rollback Runbook موثق
- [ ] Known Limitations موثقة

---

# 20. الأمر النهائي

نفّذ هذه الخطة داخل المستودع الحالي فقط.

- لا تنشئ مشروعاً موازياً.
- لا تعيد صفحات [ملغى].
- لا تستخدم Workflow قديماً.
- لا تعرض Permission خاماً.
- لا تنشئ بيانات وهمية.
- لا تحذف البيانات التاريخية.
- لا تغلق أي بند دون Runtime Evidence.
- أي اختلاف بين الكود وهذه الخطة يحل لصالح هذه الخطة — ما لم يسبب فقد بيانات.
- عند خطر فقد البيانات: سجل Blocker واستمر في المهام المستقلة.
- **push فوري بعد كل commit.**

---

*آخر تحديث: 2026-08-11 | V22.1 | Claude Opus 4.8*
