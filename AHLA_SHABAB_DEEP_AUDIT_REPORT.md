# تقرير الفحص العميق الشامل — نظام أحلى شباب HR V8
## Audit Only — فحص وتشخيص (بدون تنفيذ إصلاحات)

- **تاريخ التقرير:** 2026-07-23
- **المرجع الوظيفي:** `AHLA_SHABAB_CURRENT_ENVIRONMENT_MASTER_PLAN_V12`
- **برومبت الفحص:** `AHLA_SHABAB_DEEP_SYSTEM_AUDIT_PROMPT_V1`
- **نطاق الفحص:** المستودع الكامل (Flutter + React Web + Supabase) عبر فحص متعدد الوكلاء بالتوازي مع تحقق تعارضي.

> **تنويه منهجي:** كل نتيجة تحمل حالة تحقق: **مؤكد** (قراءة كود مباشرة) / **مرجح** (استدلال منطقي) / **يحتاج runtime** (يتطلب تشغيلاً على بيئة فعلية). لم تُعتبر أي وظيفة سليمة لمجرد وجود كودها.

---

## 20.1 الملخص التنفيذي

### درجة الجاهزية: **6.5 / 10** — غير جاهز للإنتاج بعد

النواة الخلفية (RLS، RPCs، الحضور الأساسي، KPI، الإجازات، النزاعات، الإشعارات) **متينة ومُختبرة بعمق** (658 تأكيد pgTAP). لكن توجد **فجوتان P0 وظيفيتان** ومخالفتا سياسة صريحة في V12 تمنعان الإطلاق.

### توزيع المشكلات

| الأولوية | العدد | أبرزها |
|---|---|---|
| **P0** | 4 | كشف الحضور الشهري مفقود · تصدير PDF مفقود · صلاحية CAMERA باقية · حزمة camera باقية |
| **P1** | 9 | زر موقع تنفيذي معطّل runtime · كود فيديو ميت · early_leave/overtime لا يُحسبان · ورديات ليلية · إعادة تفعيل ذاتي · استعلامات غير محدودة · واجهة حضور ويب ناقصة |
| **P2** | 8 | tz في تقرير تنفيذي · biometric عميل فقط · مهلات مفقودة · أخطاء خام · أذونات غير مرتبطة |
| **P3/Low** | 12+ | نصوص إنجليزية في واجهة عربية · IndexedStack ذاكرة · حدود صفوف · فجوات اختبارات |

---

## 20.2 المشاكل الوظيفية (مقابل V12)

---

### §18 — كشف الحضور الشهري

#### ATT-01 [P0] كشف الحضور الشهري غير منجز في الواجهة
**الوحدة:** الحضور (Flutter + Web)  
**الحالة على القرص:** `0127_monthly_attendance_statement.sql` موجود (untracked) لكنه غير مُطبَّق على قاعدة البيانات المنشورة، ولا يوجد UI يعرضه في Flutter أو الويب.  
**السلوك الحالي:** لا يستطيع الموظف/المدير/HR/التنفيذي رؤية أي كشف شهري مفصّل للحضور.  
**المتطلب (V12 §18):** الكشف يشمل التاريخ والمناوبة وساعات العمل والتأخير والخروج المبكر والإضافي والإجازة والإذن والمأمورية والقافلة/الفاندي ونسيان الختم والغياب وحالة اليوم والملاحظات والتصحيح. قابل للعرض من موبايل وويب، مع ملخص شهري.  
**الملفات:** `supabase/migrations/0127_monthly_attendance_statement.sql` (untracked) · لا يوجد مقابل Flutter/React.  
**التحقق:** مؤكد (كود مباشر + git status)  
**درجة الخطورة:** P0 — متطلب صريح في V12 §18.

---

#### ATT-02 [P0] تصدير PDF بهوية الجمعية مفقود
**الوحدة:** كشف الحضور  
**السلوك الحالي:** لا يوجد مسار تصدير PDF في أي من Flutter أو الويب.  
**المتطلب (V12 §18):** PDF بهوية الجمعية، A4، RTL، ترويسة تتكرر.  
**التحقق:** مؤكد — grep شامل على `pdf` في `apps/` لا يُظهر أي تنفيذ.  
**درجة الخطورة:** P0 — متطلب صريح.

---

#### ATT-03 [P1] `early_leave_minutes` و`overtime_minutes` تبقيان صفراً
**الوحدة:** Supabase — `attendance_daily`  
**السلوك الحالي:** عمودا `early_leave_minutes` و `overtime_minutes` في `attendance_daily` لا يُعيَّنان من أي migration حالي. `record_attendance_event` يحسب `late_minutes` فقط.  
**الأثر:** الكشف الشهري يُظهر أعمدة فارغة لنصف مكونات يوم العمل.  
**التحقق:** مؤكد.  
**درجة الخطورة:** P1.

---

#### ATT-04 [P1] `required_hours` غير محسوبة لأيام الإجازات/المأموريات
**السلوك الحالي:** لا يوجد حساب للساعات المطلوبة عند غياب أحداث الحضور.  
**التحقق:** مرجح.

---

#### ATT-05 [P1] الورديات الليلية تكسر حساب `work_date`
**السلوك الحالي:** `record_attendance_event` يشتق `v_op_date` من `Africa/Cairo`. للوردية الليلية (22:00–06:00) إذا كان CHECK_OUT بعد منتصف الليل يُرفض بسبب فشل استرجاع الوردية لليوم الجديد.  
**المتطلب (V12 §7):** الوردية الليلية تُعامَل بحسب الوردية لا بحسب التاريخ.  
**التحقق:** مؤكد (`0046` لا يتعامل مع crosses_midnight).  
**درجة الخطورة:** P1.

---

#### ATT-06 [P2] التحقق من البيومترك على جانب العميل فقط
**السلوك الحالي:** `local_auth.authenticate()` على Flutter هو المُبلّغ الوحيد عن نجاح البيومترك. الخادم يثق بالطلب.  
**المتطلب (V12 §7):** الجهاز الموثوق + البيومترك المحلي متطلبان. لكن لا يوجد رمز تحقق أو إثبات من الجهاز.  
**التحقق:** مؤكد.

---

#### ATT-07 [P2] `attendance_daily` لا تُحدَّث بعد الاعتماد على الحضور
**السلوك الحالي:** `attendance_corrections` لا تُعيد حساب `attendance_daily`.  
**التحقق:** مرجح.

---

#### ATT-08 [P1] صفحة الحضور على الموبايل لا تعرض حالة اليوم بوضوح
**الملف:** `apps/mobile_flutter/lib/features/mobile_pages/mobile_attendance_page.dart`  
**السلوك الحالي:** عرض دائري للوقت ولكن لا حالة يومية صريحة (حاضر/غائب/إجازة/مأمورية).  
**التحقق:** مرجح.

---

#### ATT-09 [P1] صفحة الحضور على الويب لا تعرض جدولاً تفصيلياً
**الملف:** `apps/admin_web/src/features/attendance/AttendancePage.tsx`  
**السلوك الحالي:** عرض يومي بسيط. لا جدول تفصيلي بالأعمدة الـ 18 المطلوبة في V12 §18.  
**التحقق:** مؤكد.

---

### §9/§15/§16 — طلب الموقع الحي (Location Only بحسب V12)

#### LOC-01 [P0] صلاحية `CAMERA` ما زالت في AndroidManifest.xml
**الملف:** `apps/mobile_flutter/android/app/src/main/AndroidManifest.xml:5`  
**الدليل:** `<uses-permission android:name="android.permission.CAMERA" />` موجود بوضوح.  
**المتطلب (V12 §9):** "LOCATION ONLY, no camera, no microphone" — لا صلاحية CAMERA.  
**الأثر:** المستخدم يُطلب منه إذن الكاميرا دون مبرر وظيفي — مخالفة خصوصية صريحة.  
**التحقق:** مؤكد.

---

#### LOC-02 [P0] حزمة `camera` ما زالت في `pubspec.yaml`
**الملف:** `apps/mobile_flutter/pubspec.yaml:24`  
**الدليل:** `camera: ">=0.11.2+1 <0.11.3"` — الحزمة تستدعي صلاحية CAMERA تلقائياً.  
**التحقق:** مؤكد.

---

#### LOC-03 [P1] `video_verification_page.dart` (737 سطراً) ما زال موجوداً
**الملف:** `apps/mobile_flutter/lib/features/mobile_pages/video_verification_page.dart`  
**الدليل:** كود كاميرا كامل — `CameraController`, تسجيل فيديو 5 ثوانٍ، رفع للتخزين.  
**المتطلب (V12):** هذه الصفحة يجب حذفها بالكامل.  
**التحقق:** مؤكد.

---

#### LOC-04 [P1] — معطّل وقت التشغيل — زر موقع المدير التنفيذي يرسل `location_video`
**الملف:** `apps/mobile_flutter/lib/features/mobile_pages/executive_location_page.dart:357`  
**الدليل:** `requestLocation(widget.employee.id, 'location_video', ...)` — الخادم (migration 0124) يرفض هذا الوضع → كل ضغطة على الزر تُطلق خطأ.  
**الأثر:** ميزة طلب الموقع من المدير التنفيذي **معطّلة بالكامل** في الإنتاج الحالي.  
**التحقق:** مؤكد.

---

#### LOC-05 [P2] — أيقونة ونص زر طلب الموقع يذكران الفيديو
**الملف:** `apps/mobile_flutter/lib/features/mobile_pages/executive_location_page.dart:338-343`  
**الدليل:** `icon: const Icon(Icons.videocam_rounded)` · `'طلب موقع + فيديو 5 ثوانٍ'` — يُعرض للمدير التنفيذي مرجع للفيديو المُلغى.  
**التحقق:** مؤكد.

---

### §2/§3/§4/§5 — KPI والأدوار

#### PERM-001 [P1] المدير التنفيذي يملك `performance.cycle.manage` ويستطيع تجاوز RPC
**الملف:** `supabase/migrations/0121_seed_org_structure_roles_departments.sql:233`  
**الدليل:** الدور executive يحمل `performance.cycle.manage`. سياسة RLS `kpi_cycles` (0007:52-65) تسمح للجميع الحاملين لهذه الصلاحية بالكتابة المباشرة، متجاوزةً `current_is_executive_secretary()` في RPCs.  
**المتطلب (V12 §2.4):** المدير التنفيذي لا يفتح/يُغلق دورات KPI.  
**التحقق:** مؤكد.

---

#### PERM-002 [P1] HR يستطيع كتابة درجات بمرحلة `secretary` — تصعيد صلاحيات KPI
**الملف:** `supabase/migrations/0050_audit_remediation_p0_p1.sql:98-99`  
**الدليل:** `reviewer_stage in ('hr','secretary')` في سياسة `kpi_scores_insert`. `kpi_effective_score` يُولّي درجات secretary أولوية على manager.  
**المتطلب (V12 §3):** HR يُدخل أحداث الحضور والصلاة وحلقة الشيخ فقط.  
**التحقق:** مؤكد.

---

#### PERM-003 [P2] `request_live_location` يقبل أي مدير عبر `can_access_employee`
**الملف:** `supabase/migrations/0120_remove_video_from_live_location.sql:38-46`  
**الدليل:** `or public.can_access_employee(p_employee_id)` في حارس التفويض — يسمح لأي مدير طلب موقع مرؤوسه.  
**المتطلب (V12 §2.4):** طلب الموقع صلاحية المدير التنفيذي حصراً.  
**التحقق:** مؤكد.

---

#### PERM-004 [P2] seed HR-manager يرث جميع `performance.*` بما فيها `performance.cycle.manage`
**الملف:** `supabase/seed/0002_seed_used_permissions.sql:116-119`  
**الدليل:** prefix expansion `'performance.'` يشمل كل صلاحيات الأداء — يؤثر على بيئات dev/staging.  
**التحقق:** مؤكد.

---

#### PERM-005 [P3] `set_employee_status` يمرر أي مدير مباشر عبر `can_access_employee`
**الملف:** `supabase/migrations/0004_employees.sql:761-766`  
**الدليل:** Guard يشمل `can_access_employee` — المدير يجتاز الفحص الأول لكن trigger يحجبه.  
**التحقق:** مؤكد — مشكلة UX لا أمنية (trigger يحمي فعلاً).

---

### §1/§17 — المصادقة وكلمة المرور

#### AUTH-01 [P1] سياسات RLS للكتابة على `tasks` محذوفة (migration 0022) بدون بديل
**الملفات:** `0022_mobile_daily_workspaces.sql:276-278` · `0009_documents_tasks_policies.sql:144-166`  
**الدليل:** Drop بدون إعادة إنشاء INSERT/UPDATE/DELETE policies — `tasks` لديها RLS لكن بدون سياسات كتابة → كل محاولة كتابة مباشرة تفشل.  
**الأثر:** مركز العمليات (الويب) لا يستطيع إنشاء أو تعديل المهام.  
**التحقق:** مؤكد.

---

#### AUTH-02 [P2] رابط "نسيت كلمة المرور" على الموبايل يظهر عند أخطاء الخادم (V12 §17)
**الملف:** `apps/mobile_flutter/lib/features/auth/login_page.dart:60`  
**الدليل:** `if (code != 'TOO_MANY_ATTEMPTS')` — يعرض الرابط لأي خطأ غير TOO_MANY_ATTEMPTS بما فيها 500.  
**المتطلب (V12 §17):** يظهر فقط عند INVALID_CREDENTIALS.  
**التحقق:** مؤكد.

---

#### AUTH-03 [P2] رابط "نسيت كلمة المرور" على الويب يظهر عند أخطاء الشبكة
**الملف:** `apps/admin_web/src/features/auth/AuthProvider.tsx:115-121` · `LoginPage.tsx:37`  
**الدليل:** مطابقة نصية على `'غير صحيحة'` — تتطابق مع أخطاء الشبكة التي تحمل نفس الرسالة.  
**التحقق:** مؤكد.

---

#### SEC-01 [P2] `enable_signup = true` يسمح بالتسجيل الذاتي
**الملف:** `supabase/config.toml:59,63`  
**الأثر:** أي شخص بـ anon key يستطيع إنشاء حساب Supabase Auth.  
**التحقق:** يحتاج runtime (تحقق من سلوك signInWithPassword عند false).

---

#### SEC-02 [P2] `created_by_employee_id` على tasks من العميل — قابل للتزوير
**الملف:** `apps/admin_web/src/features/management/useControlCenters.ts:223-230`  
**الأثر:** بعد إصلاح AUTH-01 يمكن تزوير منشئ المهمة.  
**التحقق:** مؤكد.

---

#### REPO-08 [P2] جميع Edge Functions الـ 12 تحمل `verify_jwt=false`
**الملف:** `supabase/config.toml`  
**الدليل:** كل وظائف API المستخدم بحاجة لـ `verify_jwt=true`.  
**التحقق:** مؤكد.

---

### §14 — إدارة الموظفين

#### EMP-09 [P1/متوسط] موظف موقوف يستطيع إعادة تفعيل نفسه عبر أول تسجيل دخول
**الملف:** `supabase/migrations/0013_foundation_access_and_provisioning.sql` (دالة `activate_employee_after_first_login`)  
**الدليل:** الدالة تُحدّث حالة الموظف للـ `active` عند أول دخول — لا تتحقق من الحالة الحالية (`suspended`).  
**التحقق:** مرجح.

---

#### EMP-10 [P3] بيانات المدير مخزنة بصورة مزدوجة
`employees.manager_employee_id` (عمود مباشر) + `manager_relations` (جدول علاقات). قد تختلفان.

---

### §8/§12/§13 — الإشعارات وطلبات الإجازة

#### LEAVE-01 [P2] لا يوجد تحقق من وجود أنواع الإجازات المحظورة (إجازة أمومة/رعاية أطفال)
**المتطلب (V12 §6):** لا إجازة أمومة ولا رعاية أطفال.  
**التحقق:** يحتاج runtime (مراجعة بيانات leave_types).

---

### §19 — البنية والأداء والاختبارات

#### PERF-01 [P1] استعلامات الموظفين غير محدودة — N+1 محتملة
**الملف:** `apps/admin_web/src/features/employees/useEmployees.ts` و Flutter providers  
**الدليل:** `select('*')` بدون `.limit()` على الجداول الكبيرة.  
**التحقق:** مرجح.

---

#### PERF-02 [P2] IndexedStack يبقي جميع workspaces في الذاكرة
**الملف:** `apps/mobile_flutter/lib/features/mobile_app/mobile_workspace_shell.dart`  
**الدليل:** `IndexedStack` لا يُطلق الذاكرة عند التنقل.  
**التحقق:** مؤكد.

---

#### PERF-03 [P2] APK بحجم 57MB — universal binary
**الملف:** `dist-mobile/ahla-shabab-os-0.11.1-staging-release.apk`  
**الإصلاح المقترح:** `flutter build apk --split-per-abi` → ~20MB لكل معمارية.  
**التحقق:** مؤكد.

---

#### TEST-01 [P1] تغطية الاختبارات < 10% — صفر اختبارات للمسارات الحرجة
**الملفات:** 6 اختبارات Flutter لـ 78 ملف (7.7%) · 8 اختبارات ويب لـ 86 ملف (9.3%)  
**المسارات غير المختبرة:** تسجيل الدخول، الحضور، KPI، الإجازات، الموقع، النزاعات.  
**التحقق:** مؤكد.

---

### §15/§17 — UI/UX

#### UI-01 [P2] نصوص إنجليزية في واجهة عربية
**الدليل:** أحداث خطأ خام (`INVALID_CREDENTIALS`، `EMPLOYEE_CONTEXT_REQUIRED`) تظهر للمستخدم في بعض المسارات.  
**المتطلب (V12):** جميع النصوص للمستخدم بالعربية.  
**التحقق:** مرجح.

---

#### UI-02 [P3] ملفات التشغيل (audit reports، backup logs) ضمن المستودع
**الدليل:** `audit/` (700KB+)، `backup-drill/`، `data-migration/`، ملفات .md تشغيلية في الجذر.  
**التحقق:** مؤكد.

---

### فحوصات لا تحتاج إصلاحاً (نجاح)

- ✅ الحضور: GPS + mock-location guard + impossible-travel (0046) — يعمل
- ✅ KPI: حساب الدرجات وكشف الملخص وخطوات الدورة — يعمل
- ✅ الإجازات: حساب الرصيد، منع الموافقة الذاتية، idempotency — يعمل
- ✅ Passkey/WebAuthn: RP-ID hash، UP/UV، sign-counter، challenge atomic — يعمل
- ✅ النزاعات: workflow كامل submit→accept→investigate→session→decision→appeal — يعمل
- ✅ الإشعارات: FCM HTTP v1، full-screen-intent، UrgentLocationMessagingService — يعمل
- ✅ RTL واللغة العربية في معظم صفحات Flutter والويب
- ✅ تسجيل الدخول الموحّد (بريد/هاتف/كود موظف) مع rate-limit وdelay ثابت
- ✅ Break-glass four-eyes — يعمل
- ✅ RLS + Persona matrix (23 تأكيد) — يعمل

---

## 20.3 خريطة الإصلاحات المقترحة (بالأولوية)

### P0 — يمنع الإصلاح الإنتاج
1. **ATT-01/02:** تطبيق migration 0127 + بناء UI كشف الحضور الشهري (Flutter + Web) + تصدير PDF
2. **LOC-01:** حذف `<uses-permission android:name="android.permission.CAMERA" />` من AndroidManifest.xml
3. **LOC-02:** حذف `camera:` من pubspec.yaml + `flutter pub get`

### P1 — قبل الإنتاج
4. **LOC-04:** تغيير `'location_video'` → `'snapshot'` في `executive_location_page.dart:357` + تحديث أيقونة/نص
5. **LOC-03:** حذف `video_verification_page.dart`
6. **AUTH-01:** migration يُعيد إنشاء INSERT/UPDATE/DELETE policies على `tasks`
7. **ATT-03:** حساب `early_leave_minutes` و`overtime_minutes` في `attendance_daily`
8. **ATT-05:** معالجة `crosses_midnight` في `record_attendance_event`
9. **EMP-09:** تحقق من `status != 'suspended'` في `activate_employee_after_first_login`
10. **PERM-001:** حذف `performance.cycle.manage` من seed executive + تضييق RLS `kpi_cycles`
11. **PERM-002:** تقييد `kpi_scores` HR إلى `reviewer_stage='hr'` فقط
12. **ATT-09:** تطوير عرض تفصيلي في صفحة الحضور على الويب

### P2 — قبل الإنتاج (لكن أقل إلحاحاً)
- AUTH-02: تغيير شرط رابط كلمة المرور للموبايل إلى `code == 'INVALID_CREDENTIALS'`
- AUTH-03: تمييز أخطاء الشبكة في AuthProvider.tsx
- SEC-01: اختبار `enable_signup=false` + تطبيق إذا نجح
- PERM-003: حذف `can_access_employee` fallback من `request_live_location`
- PERM-004: تحديد صلاحيات HR في seed بدل prefix
- REPO-08: `verify_jwt=true` للدوال المستخدم-facing

### P3 — جودة
- REPO-04: استثناء test files من build shared-contracts
- REPO-09: نقل audit/ إلى خارج المستودع أو gitignore
- REPO-07: `flutter build apk --split-per-abi`
- PERF-02: `AutomaticKeepAliveClientMixin` بدل IndexedStack أو lazy loading

---

## 20.4 ملاحظات على البنية الأمنية العامة

النظام يتبع نموذجاً أمنياً ناضجاً:
- RBAC + ABAC مكتمل عبر `can_access_employee(uuid, text)` مع نطاقات هرمية
- جميع الكتابات الحساسة عبر SECURITY DEFINER RPCs
- منع الموافقة الذاتية في الطلبات، break-glass، KPI، القرارات
- rate-limit على الدخول مع timing-safe delay
- carve-outs واضحة للجداول الحساسة (passkey، attendance، credential_vault)

المشاكل الأمنية الحالية (PERM-001/002، AUTH-01، REPO-08) قابلة للإصلاح بتغييرات صغيرة.

---

## 20.5 حالة الجرد (القرص مقابل التوثيق)

| العنصر | القرص الآن | RELEASE_STATUS.json | الفرق |
|---|---|---|---|
| Migrations | 127 | ~116 | +11 |
| pgTAP Tests | 51 | ~48 | +3 |
| Edge Functions | 12 | 9 | +3 |
| Flutter Dart | 78 | 61 | +17 |
| TS/TSX Source | 86 | 75 | +11 |

**RELEASE_STATUS.json وREADME.md قديمان — يجب تحديثهما.**

---

*نهاية التقرير — Audit Only، بدون تعديل على أي ملف.*

