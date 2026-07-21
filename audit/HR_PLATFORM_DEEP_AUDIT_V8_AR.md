# تقرير الفحص العميق — Ahla Shabab Management OS V8

**الإصدار:** 0.10.0 (build 10) · **تاريخ الفحص:** 2026-07-15 · **المنهج:** فحص متعدد الوكلاء
عبر 7 مسارات (RLS/Grants · SECURITY DEFINER · Edge Functions · Workflow/Ledger · حدود ثقة
العميل · جاهزية الإصدار · البنية) مع **تحقق عدائي مستقل** لكل نتيجة قبل قبولها.

**النطاق المفحوص:** `supabase/` (48 migration + 30 اختبار pgTAP + 9 Edge Functions) ·
`apps/admin_web` (React/Vite) · `apps/mobile_flutter` · ملفات الإصدار والتوثيق و CI.

---

## 1. الحكم التنفيذي

المنصة مبنية على أساس أمني **قوي في مجمله**: نموذج RBAC+ABAC حقيقي، سياسات RLS واسعة،
دوال SECURITY DEFINER محصّنة (`search_path` مثبّت، حراسة تصعيد الصلاحيات في دوال الأدوار،
منع الموافقة الذاتية في مسار الطلبات و break-glass)، ودخول موحّد مقاوم لتعداد الحسابات في
معظم مساراته. التصميم واعٍ أمنياً (تقييد `geofences` يدوياً، فصل جداول الأسرار).

لكن الفحص كشف **ثغرة حرجة واحدة (P0)** و**أربع ثغرات عالية (P1)** تمنع الترقية إلى
Production قبل إصلاحها، أبرزها **انهيار نطاق ABAC على جداول الرواتب** يتيح لأي حامل صلاحية
`payroll.structure.manage` مقيّدة النطاق قراءة وتعديل رواتب وقروض **كل** موظفي المؤسسة.

**production_ready: لا.** يجب إغلاق P0 و P1 (خمس نتائج) وإعادة تشغيل pgTAP + persona
tests قبل اعتماد الإنتاج. النتائج P2/P3 لا تمنع Staging لكنها ضمن قائمة ما قبل الإنتاج.

**ملخص العدد:** 23 نتيجة مؤكَّدة (P0×1 · P1×4 · P2×10 · P3×8) + 3 نتائج فُحصت ورُفضت
(إيجابيات كاذبة، انظر §7).

---

## 2. جدول النتائج

| المعرّف | البُعد | الخطورة | الملف:السطر | الوصف المختصر | التحقق |
|---|---|---|---|---|---|
| **RLS-01** | أمن | **P0** | `0036_...payroll.sql:88` | انهيار نطاق: رواتب/قروض كل الموظفين مقروءة+قابلة للتعديل org-wide لأي حامل `payroll.structure.manage` | static |
| **RLS-02** | أمن | **P1** | `0007_kpi_performance.sql:254,274` | كتابة درجات KPI لأي موظف: مراحل manager/hr/exec بلا `can_access_employee` | static |
| **LEDGER-01** | صحّة | **P1** | `0026_...sla.sql:147` | ازدواج تطبيق رصيد الإجازات: idempotency بنافذة 5 ثوانٍ بدل قيد فريد | static |
| **DECISION-01** | صحّة | **P1** | `0027_decision...sql:177` | لا فصل واجبات: منشئ القرار الإداري يعتمده بنفسه (بلا four-eyes) | static |
| **ATT-01** | صحّة | **P1** | `0005_attendance.sql:63` | حساب التأخير يعامل بداية الوردية كـUTC بينما التاريخ محلي → تأخير مُبخَّس (مدخل رواتب) | static+runtime |
| **SDEF-01** | أمن | P2 | `0036:117` · `0035:218` · `0033` | دوال DEFINER في 0033/0035/0036 لا تسحب `execute` من PUBLIC (دفاع بالعمق) | static |
| **ESI-01** | أمن | P2 | `identifier-sign-in:56` | تعداد حسابات عبر توقيت: `minimumDelay` أرضية لا سقف + مسار «موجود» أثقل | runtime |
| **ESI-02** | أمن | P2 | `identifier-sign-in:39` | تحديد معدّل IP على ترويسة `x-forwarded-for` القابلة للتزوير (تجاوز) | static |
| **CTB-02** | أمن | P2 | `useControlCenters.ts:179` | صاحب التذكرة ينقل حالتها لأي قيمة (resolve/close) عبر كتابة مباشرة | runtime |
| **CTB-04** | صحّة | P2 | `useControlCenters.ts:216` | `handled_by` من العميل على `security_events`: تزوير مُسنِد معالجة الحدث (يتطلب صلاحية) | static |
| **CTB-01** | صحّة | P2 | `App.tsx:122` | لا بوابة صلاحية لكل مسار؛ فقط `WorkspaceGuard` (دفاع بالعمق) | static |
| **DISPUTE-01** | صحّة | P2 | `0030_disputes...sql:230` | نصاب اللجنة قابل للحشو بأعضاء غير نشطين/من قضية أخرى (من داخلي مخوّل) | plausible |
| **ARCH-02** | بنية | P2 | `useEnterpriseManagement.ts:6` | بيانات mock (بأشكال PII) تُشحن في حزمة الإنتاج (تضخّم؛ لا تسريب حيّ) | static |
| **REL-01** | إصدار | P2 | `BUILD_MANIFEST.json` | التصديق (manifest) قديم: hash الـREADME/RELEASE_STATUS لا يطابق القرص | static |
| **REL-02** | أمن | P2 | `check-no-secrets.mjs:15` | ماسح الأسرار لا يكشف pepper/project-ref ويتخطى ملفات .ps1؛ ادعاء «تم التحقق» ناقص | static |
| **REL-04** | إصدار | P2 | `tmp_inspect.sql` · `*.internal-bak` | ملفات scratch/lockfile مكرّر تُشحن ضمن الإصدار المُصدَّق | static |
| **REL-05** | إصدار | P2 | `docs/runtime-evidence/02_...md:19` | صفّان موسومان «الحالية» في جدول الأدلة (46/29 قديم بجانب 48/30) | static |
| **REL-06** | إصدار | P2 | `features/auth/AuthProvider.tsx` | صفر اختبارات لمسار المصادقة/الجلسة/الحُرّاس في admin_web | static |
| **RLS-03** | أمن | P3 | `0034_...storage.sql:34` | bucket `course-materials` مقروء لأي مستخدم مصادَق بلا تحقق تسجيل | static |
| **SDEF-02** | أمن | P3 | `0036:101` وغيرها | `search_path=public,auth` بلا `pg_temp` (شذوذ عن المعيار؛ لا استغلال) | plausible |
| **ESI-03** | أمن | P3 | `scheduled-report-runner:9` | مقارنة سرّ الـcron بـ`!==` غير ثابتة الزمن (×4 دوال) | static |
| **LEDGER-02** | صحّة | P3 | `0026:196` | إلغاء إجازة معتمدة لا يُعيد `consumed_units` (تضخّم الرصيد المستهلَك) | static |
| **CTB-05** | بنية | P3 | `useControlCenters.ts:19` | coercion يدوي بدل zod (اتساق بيانات صامت) | static |
| **ARCH-01** | بنية | P3 | `useEnterpriseManagement.ts:17` | مساعد `rpc()` مكرَّر في 6 ملفات بتوقيعات متباينة | static |
| **ARCH-03** | بنية | P3 | `packages/shared-contracts/src/index.ts` | افتراض single-tenant غير موثّق | static |
| **ARCH-05** | بنية | P3 | `useEnterpriseManagement.ts` | مصدر مُصغّر يدوياً (أسطر 295–455 حرف) يُضعف مراجعة الـdiff | plausible |

> ملاحظة منهجية: «static» = مؤكَّد بقراءة الكود؛ «runtime» = يحتاج/أُكِّد بتشغيل قاعدة
> البيانات؛ «plausible» = ثغرة حقيقية لكن مداها الدقيق يستحسن تأكيده تشغيلياً.

---

## 3. البُعد الأمني (Security)

### RLS-01 — [P0] انهيار نطاق ABAC على جداول الرواتب والقروض
**الملف:** [`0036_workforce_compensation_payroll_engagement.sql:88`](supabase/migrations/0036_workforce_compensation_payroll_engagement.sql:88)

حلقة `DO` تنشئ سياسة واحدة `for all to authenticated` على خمسة جداول، منها ثلاثة تحمل
بيانات مالية لكل موظف: `employee_compensation` (base_salary, bank_account_masked,
statutory_profile)، `employee_loans` (principal/outstanding)، `loan_installments`.
الشرط الوحيد:
```sql
using (public.current_is_full_access() or public.has_permission('payroll.structure.manage'))
with check (نفس الشرط)
```
`has_permission()` ([`0002:105`](supabase/migrations/0002_permissions_roles_functions.sql:105))
**يتجاهل عمود `role_permissions.scope` عمداً** — يفحص عضوية الدور فقط. فلا يوجد شرط نطاق صف
(`can_access_employee(employee_id)`) ولا فلترة `current_employee_id()`. بالمقابل سياسة
`payslips_read` (السطر 90) في نفس الملف **تضيف `can_access_employee(employee_id)` صحيحاً** —
ما يثبت أن التقييد كان مقصوداً وسقط سهواً هنا.

**الاستغلال:** موظف رواتب دوره يمنحه `payroll.structure.manage` بنطاق `branch`/`department`
(مقصود: فرعه فقط) يستطيع `select base_salary, bank_account_masked from employee_compensation`
لكل موظفي المؤسسة، و`insert/update/delete` أي راتب أو رصيد قرض (رفع راتبه أو تصفير قرض).
**كشف وتلاعب بالرواتب على مستوى المؤسسة من مشغّل مقيّد النطاق.** رُفعت من P1 إلى P0 لمسّها
الرواتب + السماح بالكتابة.

**الإصلاح:** استبدال الشرط للجداول الثلاثة بـ
`current_is_full_access() or can_access_employee(employee_id,'payroll.structure.manage')`
(ولـ`loan_installments` عبر ربط `employee_loans`)، مع إبقاء الصيغة العمياء للكتالوجات
`salary_structures`/`salary_components` فقط. + اختبار persona يثبت 0 صف خارج النطاق.

### RLS-02 — [P1] كتابة درجات KPI لأي موظف خارج النطاق
**الملف:** [`0007_kpi_performance.sql:254`](supabase/migrations/0007_kpi_performance.sql:254) (insert) و`:274` (update)

سياسة SELECT على `kpi_scores` (جدول موسوم «حساس») تُقيّد النطاق عبر
`can_access_employee(e.employee_id)`، لكن سياستَي INSERT/UPDATE تحرسان المراحل غير الذاتية
(manager/hr/secretary/executive/finalized) على `has_permission('<stage>')` **وحدها بلا أي
شرط نطاق موظف**. فرع `self` فقط مربوط بـ`current_employee_id()`. وهي سياسات كتابة مباشرة
(ليست RPC-only)، فالإدراج الخام ينجح دون المرور بـ`advance_kpi_stage()`.

**الاستغلال:** مدير يحمل `performance.kpi.manager_assess` (نطاق مقصود: مرؤوسوه) يدرج/يعدّل
درجات مرحلة المدير لأي موظف في قسم آخر، مفسداً تقييمات الأداء.
**الإصلاح:** إضافة شرط `can_access_employee(e2.employee_id,'<stage>')` لكل فرع، أو حذف سياسات
الكتابة المباشرة وإجبار المرور عبر `advance_kpi_stage()`.

### SDEF-01 — [P2] دوال DEFINER لا تسحب `execute` من PUBLIC
**الملف:** [`0036:117`](supabase/migrations/0036_workforce_compensation_payroll_engagement.sql:117) · [`0035:218`](supabase/migrations/0035_enterprise_strategy_projects_service_governance.sql:218) · معظم `0033`

Postgres يمنح `execute` لـ PUBLIC افتراضياً على كل دالة جديدة. ملفات 0033/0035/0036 تنشئ
دوال SECURITY DEFINER وتكتفي بـ`grant ... to authenticated` **دون `revoke ... from public`**
المسبق — خلافاً للمعيار الموثّق في المشروع نفسه ([`0043:5`](supabase/migrations/0043_grant_service_role_sla_processor.sql:5)
ونمط 0025/0038/0044). لا تسريب حالياً لأن كل دالة تحرس داخلياً (تردّ anon لأن
`current_employee_id()` = null)، لكنها **فشل دفاع بالعمق**: أي دالة مستقبلية بلا حارس تصبح
قابلة للاستدعاء من anon مباشرة عبر PostgREST.
**الإصلاح:** إضافة `revoke execute on function ... from public, anon;` قبل كل `grant`.

### ESI-01 — [P2] تعداد حسابات عبر قناة توقيت في الدخول الموحّد
**الملف:** [`identifier-sign-in/index.ts:56`](supabase/functions/identifier-sign-in/index.ts:56)

`minimumDelay()` يرفع الزمن حتى 280–400ms لكنه **لا يضع سقفاً**. مسار «المعرّف موجود»
(phone/employee_code) يؤدي عملاً أثقل (استعلام profiles + `getUserById` عبر الشبكة +
تحقق bcrypt فعلي) من مسار «غير موجود» (يُرفض `invalid-...@invalid.local` بلا bcrypt). حين
يتجاوز العمل الحقيقي الأرضية، يتسرّب فرق الزمن كاشفاً وجود الحساب.
**الإصلاح:** تنفيذ bcrypt وهمي بتكلفة مكافئة على مسار «غير موجود»، وفرض موعد نهائي مطلق ثابت
(انتظار حتى `startedAt + target` دائماً) بدل أرضية.

### ESI-02 — [P2] تحديد معدّل IP على ترويسة قابلة للتزوير
**الملف:** [`identifier-sign-in/index.ts:39`](supabase/functions/identifier-sign-in/index.ts:39)

`clientIp()` يشتق مفتاح تحديد المعدّل بالكامل من ترويسات العميل
(`cf-connecting-ip`/`x-real-ip`/`x-forwarded-for`) دون حدّ ثقة. مهاجم يرسل `X-Forwarded-For`
فريداً لكل طلب فيتجاوز سقف `IP_MAX_ATTEMPTS=10/دقيقة` تماماً. يبقى حدّ المعرّف (6/5د) فعّالاً
فيمنع كسر حساب واحد، لكن **credential stuffing / spraying** عبر آلاف الحسابات ممكن.
**الإصلاح:** عدم الوثوق بالترويسات المعاد توجيهها إلا من proxy موثوق يجرّد قيم العميل؛ إضافة
حدّ حجم إجمالي كخط دفاع.

### ESI-03 — [P3] مقارنة سرّ الـcron غير ثابتة الزمن
**الملفات:** `scheduled-report-runner:9`، `notification-dispatcher:8`، `retention-cleanup:10`،
`integration-outbox-worker:28` — كلها تقارن `x-cron-secret` بـ`!==` (قصر دائرة على أول بايت
مختلف). تفشل مغلقة عند غياب السرّ (سلوك صحيح) ولا تسجّله. الاستغلال العملي شبه معدوم عبر
الشبكة، لكنه شذوذ عن المقارنة ثابتة الزمن. **الإصلاح:** مقارنة digest عبر SHA-256 للطرفين.

### RLS-03 — [P3] bucket `course-materials` مقروء لأي مصادَق
**الملف:** [`0034:34`](supabase/migrations/0034_private_storage_buckets_and_retention.sql:34) —
سياسة قراءة `using (bucket_id='course-materials')` بلا تحقق تسجيل/صلاحية، خلافاً لكل
buckets الأخرى المقيَّدة. محتوى تدريبي (لا PII) لكنه يخالف مبدأ الأقل امتيازاً.
**الإصلاح:** تقييد القراءة بالمسجّلين أو حاملي `learning.course.manage`.

### SDEF-02 — [P3] `search_path=public,auth` بلا `pg_temp`
دوال في 0033/0035/0036/0037/0044 تثبّت `public,auth` (لا `pg_temp`). لا استغلال (المراجع
مؤهَّلة بالمخطط بالكامل)، لكن تصحيح المعيار هو `public, auth, pg_temp` (كما في
[`0013:9`](supabase/migrations/0013_foundation_access_and_provisioning.sql:9)).

---

## 4. بُعد الصحّة المنطقية (Correctness)

### LEDGER-01 — [P1] ازدواج تطبيق رصيد الإجازات
**الملف:** [`0026_leave_ledger_and_request_sla.sql:147`](supabase/migrations/0026_leave_ledger_and_request_sla.sql:147)

`apply_leave_ledger_entry()` يزيل التكرار عبر `on conflict(source_key) do update ...
returning * into v_entry`، ثم يقرر تطبيق المجاميع بحارس زمني:
`if v_entry.created_at < clock_timestamp() - interval '5 seconds' then return; end if;`.
عند تعارض حقيقي، تُرجع `RETURNING` الصفّ **الموجود** (created_at قبل ثوانٍ)، فيكون الحارس
FALSE وتُطبَّق مجاميع `accrued/reserved/consumed_units` **مرة ثانية**. القيد الفريد يمنع
تكرار الصفّ لكن **لا يمنع تكرار تحديث المجاميع**. لا advisory lock.

**الاستغلال:** معاملتان (أو double-submit خلال 5ث) بنفس `source_key`: A تدرج وتضيف الاستحقاق،
B تصطدم بالتعارض وتضيفه **ثانيةً**. شهر واحد يمنح استحقاقاً مضاعفاً، أو حجز إجازة مضاعف.
يمسّ المسارات الثلاثة (reserve/consume/release) والاستحقاق الشهري. اختبار pgTAP 0030 يتحقق من
عدم تكرار الصفّ فقط، لا من المجموع — فالثغرة غير مغطاة.
**الإصلاح:** idempotency بنيوي: `on conflict do nothing` + كشف الإدراج الفعلي (`xmax=0` أو
`if not found`) وتطبيق المجاميع عند الإدراج الحقيقي فقط، مع
`pg_advisory_xact_lock(hashtext(p_source_key))`.

### DECISION-01 — [P1] لا فصل واجبات على القرارات الإدارية
**الملف:** [`0027_decision_lifecycle_polls_and_execution.sql:177`](supabase/migrations/0027_decision_lifecycle_polls_and_execution.sql:177)

`transition_decision` في فرع `approve` يتطلب `comms.decision.approve` فقط ولا يقارن المعتمِد
بـ`issued_by`/`created_by`/مقدّم القرار. مستخدم واحد (full-access يكفي، فهو يجتاز فرعَي manage
و approve) يستطيع: `create_decision_draft` → `submit_review` → `approve` → publish على قراره
بنفسه. المشروع يطبّق four-eyes في نظائره
([`approve_break_glass` 0038:562](supabase/migrations/0038_release_access_privacy_integration_governance.sql:562)
و decide_request) — فالثغرة انحراف عن معيار قائم.
**الإصلاح:** رفض الاعتماد عند تطابق المعتمِد مع المؤلف/المقدّم (على غرار break-glass).

### ATT-01 — [P1] حساب التأخير يخلط التوقيت المحلي بـUTC
**الملف:** [`0005_attendance.sql:63`](supabase/migrations/0005_attendance.sql:63) (أُكِّد تشغيلياً)

`calculate_late_minutes` يعامل `shifts.start_time` (وقت محلي بلا منطقة) كأنه UTC، بينما
المُستدعي يمرّر التاريخ المرجعي بتوقيت `Africa/Cairo`
([`0046:60,179`](supabase/migrations/0046_attendance_mock_location_and_travel_guard.sql:60)).
النتيجة: التأخير يُبخَّس بمقدار فرق التوقيت (2–3 ساعات). **تحقق تشغيلي:** وردية 09:00،
حضور 10:30 بتوقيت القاهرة يُحتسب **0 دقيقة تأخير** (الصحيح ~90). هذا مدخل رواتب (late-pay)،
فيفسد الخصومات على كل نشر غير UTC (المنطقة الافتراضية Asia/Riyadh). رُفعت P2→P1.
**الإصلاح:** بناء بداية الوردية بمنطقة الفرع:
`(v_op_date::timestamp + p_shift_start) at time zone <org_tz>` والمقارنة بالـtimestamptz.

### CTB-02 — [P2] صاحب التذكرة ينقل حالتها لأي قيمة
**الملفات:** [`useControlCenters.ts:179`](apps/admin_web/src/features/management/useControlCenters.ts:179)
· [`0035:189`](supabase/migrations/0035_enterprise_strategy_projects_service_governance.sql:189)

`transition` يُحدّث `service_requests` مباشرة (بلا RPC). سياسة `service_requests_manage` تسمح
بالتحديث عند `requester_employee_id = current_employee_id()`، فيستطيع صاحب التذكرة نقلها لأي
حالة (resolved/closed/cancelled) وضبط `resolved_at` دون `service.request.manage`، مزوّراً
مقاييس SLA وسجلّ من عالج التذكرة. النطاق: تذاكره فقط.
**الإصلاح:** توجيه الانتقالات عبر RPC يفرض الصلاحية، أو تضييق `with check` للمالك لحالات
محدودة فقط.

### CTB-04 — [P2] `handled_by` من العميل على `security_events`
**الملف:** [`useControlCenters.ts:216`](apps/admin_web/src/features/management/useControlCenters.ts:216)

`handleEvent` يرسل `handled_by: auth.session?.user.id` (من العميل)؛ لا trigger يستبدله.
حامل `security.event.manage` يقدر يسند معالجة حدث أمني لمستخدم آخر، مزوّراً سجلّ المساءلة.
يتطلب فاعلاً مخوّلاً (لذا P2 لا P0). **الإصلاح:** ضبط `handled_by = auth.uid()` عبر trigger
أو RPC.

### CTB-01 — [P2] لا بوابة صلاحية لكل مسار
**الملف:** [`App.tsx:122`](apps/admin_web/src/app/App.tsx:122) — `WorkspaceGuard` يفحص عضوية
الـworkspace فقط؛ صلاحيات `WorkspaceShell` تُخفي عناصر التنقّل بصرياً فقط. أي عضو workspace
يستطيع الوصول لأي صفحة عبر URL مباشر. **دفاع بالعمق** فقط لأن الجداول محمية بـRLS خادمياً
(تحقّقنا أن `audit_events`/`security_events` تعيد صفراً بلا صلاحية). **الإصلاح:** حارس مسار
واعٍ بالصلاحية + إبقاء الفرض الخادمي.

### DISPUTE-01 — [P2] حشو نصاب اللجنة بأعضاء غير نشطين
**الملف:** [`0030_disputes_committee_quorum_decisions_and_appeals.sql:230`](supabase/migrations/0030_disputes_committee_quorum_decisions_and_appeals.sql:230)

حلقة الحضور في `finalize_dispute_session` و العدّ في `issue_dispute_decision` (السطر 248) لا
يفلتران `committee_members` بـ`case_id`/`is_active`. المعرّفات المزوّرة يمنعها FK والمكرّرة
يمنعها PK (خلافاً للوصف الأولي)، لكن يبقى **حشو النصاب بأعضاء معطّلين/مُنحّين أو من قضية
أخرى** من رئيس اللجنة نفسه. مشكلة نزاهة من داخلي مخوّل.
**الإصلاح:** العدّ فقط `where committee_member_id in (select id from committee_members where
case_id=v_case.id and is_active)`.

### LEDGER-02 — [P3] إلغاء إجازة معتمدة لا يُعيد المستهلَك
**الملف:** [`0026:196`](supabase/migrations/0026_leave_ledger_and_request_sla.sql:196) — عند
`approved→cancelled/expired` يُطلق trigger فرع `release` (يخصم من `reserved` المُصفّر) ولا
يُعيد `consumed_units`. لا يبلغ إلا عبر تحديث مباشر من full-access. **الإصلاح:** إصدار
`refund` عند الانتقال من `approved`.

---

## 5. بُعد جاهزية الإصدار (Release)

- **REL-01 [P2]** — [`BUILD_MANIFEST.json`](BUILD_MANIFEST.json) وُلِّد 06:47 بينما
  `README.md`/`RELEASE_STATUS.json` عُدِّلا 06:49، فصار hash الملفين لا يطابق التصديق (تأكّد
  بحساب sha256 مستقل). **الإصلاح:** جعل `npm run manifest` آخر خطوة قبل الوسم + فحص CI يفشل
  عند وجود diff.
- **REL-02 [P2]** — [`check-no-secrets.mjs:15`](scripts/check-no-secrets.mjs:15) لا يملك قاعدة
  لـ`LOGIN_HASH_PEPPER` ولا لـ project-ref، ويتخطى ملفات `.ps1` كلياً، بينما
  `RELEASE_STATUS.json` يعلن `secret_scan` مُتحقَّقاً. لا سرّ إنتاجي مسرَّب فعلاً (القيم
  placeholder/معرّفات عامة) لكنه فجوة تغطية وادعاء زائد. **الإصلاح:** إضافة قواعد
  `*_PEPPER`/`*_SECRET`، إضافة `.ps1`، تليين ادعاء التحقق.
- **REL-04 [P2]** — [`tmp_inspect.sql`](tmp_inspect.sql) و`package-lock.json.internal-bak`
  (lockfile متباعد) و`fix_staging_backend.ps1` تُشحن ضمن الإصدار المُصدَّق وغير مُتجاهَلة.
  **الإصلاح:** حذفها + إضافة `tmp_*`/`*.internal-bak` لـ.gitignore + إعادة توليد manifest.
- **REL-05 [P2]** — [`docs/runtime-evidence/02_DATABASE_RESET_AND_PGTAP.md:19`](docs/runtime-evidence/02_DATABASE_RESET_AND_PGTAP.md:19)
  يوسم صفّ 46/29 القديم بـ«الحالية» بجانب صفّ 48/30 الحالي فعلاً. **الإصلاح:** وسم القديم
  «تاريخية».
- **REL-06 [P2]** — صفر اختبارات لـ`features/auth/` (AuthProvider/LoginPage/accessService/
  الحُرّاس) في admin_web رغم حساسية المصادقة. **الإصلاح:** اختبارات دورة الجلسة والدخول
  الموحّد والحُرّاس كبوابة إصدار.

### مصفوفة تسوية الجرد (المرجع = القرص 2026-07-15)

| العنصر | القرص (الحقيقة) | RELEASE_STATUS.json | README.md | الذاكرة |
|---|---|---|---|---|
| Migrations (.sql) | **48** (0001–0048) | 46 ❌ | 46 ❌ | 44 ❌ |
| اختبارات pgTAP (.sql) | **30** | 29 ❌ | 29 ❌ | 28 ❌ |
| Edge Functions | **9** + `_shared` | 9 ✅ | 9 ✅ | — |

> ملاحظة: بعض أدوات الاستكشاف عدّت 49/31 لتضمينها ملف `README.md` داخل كل مجلد. العدد
> الحقيقي لملفات `.sql` هو **48 migration / 30 test**.

---

## 6. بُعد البنية والجودة (Architecture)

- **ARCH-02 [P2]** — بيانات mock بأشكال أسماء عربية تُشحن في حزمة الإنتاج (لا تُشذَّب لأنها
  مرتبطة بحالة runtime `auth.isMock` لا بـ`import.meta.env.DEV`). لا تسريب حيّ (isMock يبقى
  false في الإنتاج) لكنها تضخّم + كشف أشكال بيانات. **الإصلاح:** نمط `loadDomainMocks()`
  الكسول (كما في `useManagementOverviews`).
- **CTB-05 [P3]** — coercion يدوي بدل zod في `useControlCenters.ts` → اتساق صامت خاطئ عند
  انحراف المخطط.
- **ARCH-01 [P3]** — `rpc()` مكرَّر في 6 ملفات بتوقيعات متباينة → استخراج مساعد مشترك.
- **ARCH-03 [P3]** — single-tenant غير موثّق (لا `tenant_id`) → إضافة ملاحظة معمارية.
- **ARCH-05 [P3]** — مصدر مُصغّر يدوياً يُضعف مراجعة الـdiff → إعادة تنسيق Prettier.

---

## 7. نتائج فُحصت ورُفِضت (إيجابيات كاذبة)

التحقق العدائي أسقط 3 نتائج، ما يرفع الثقة ببقية القائمة:

- **CTB-03 (مرفوضة):** ادّعاء تزوير `created_by_employee_id` على `tasks.insert` يعتمد على
  سياسة INSERT في 0009، لكن [`0022:276`](supabase/migrations/0022_mobile_daily_workspaces.sql:276)
  **تحذف** سياسات insert/update/delete على `tasks` ولا تعيد إنشاءها (المهام تُنشأ عبر RPC فقط).
  فالإدراج المباشر يُرفض أصلاً بـRLS للجميع.
- **REL-03 (مرفوضة):** «تسريب» project-ref في `fix_staging_backend.ps1` — القيمة **معرّف
  عام** (subdomain لعنوان API العام `https://<ref>.supabase.co`) يُشحن لكل عميل بالتصميم،
  ليست سرّاً. (يُنصح رغم ذلك بحذف الملف ضمن REL-04.)
- **ARCH-04 (مرفوضة):** حقول `z.unknown()` في shared-contracts هي حقول عرض للقراءة فقط؛
  التفويض يقرأ `scope_override` من الجدول عبر RLS خادمياً لا من عقد العميل.

---

## 8. ما يتطلب تحقّقاً تشغيلياً (db reset + pgTAP + persona)

Docker و Supabase CLI متوفران، فالتحقق ممكن. الـassertions المطلوب إضافتها:

1. **RLS-01/RLS-02:** persona بدور `payroll.structure.manage` نطاق `branch` → يجب 0 صف من
   `employee_compensation` خارج فرعه، ورفض `update` على راتب خارج النطاق. مثله لـ`kpi_scores`.
2. **LEDGER-01:** معاملتان متزامنتان بنفس `source_key` → التأكّد أن `accrued_units` زاد مرة
   واحدة (يفشل حالياً).
3. **ATT-01:** تثبيت منطقة `Africa/Cairo`، حضور متأخر معلوم → التأكّد أن `late_minutes`
   صحيح (يعيد 0 حالياً — أُكِّد الفشل تشغيلياً).
4. **DECISION-01:** نفس الفاعل draft→submit→approve → يجب `FOUR_EYES_REQUIRED`.
5. **CTB-02/CTB-04:** إدراج بحقل هوية/حالة مزوّر → يجب رفض/استبدال خادمي.

---

## 9. قائمة الإصلاحات المرتّبة (Remediation Backlog)

**أولوية قصوى (تمنع الإنتاج):**
1. **RLS-01 (P0):** migration جديد يصلح سياسات جداول الرواتب لتستخدم `can_access_employee` +
   اختبار persona.
2. **RLS-02 (P1):** إضافة شرط نطاق لكتابة `kpi_scores` أو تحويلها لـRPC.
3. **LEDGER-01 (P1):** idempotency بنيوي + advisory lock في `apply_leave_ledger_entry`.
4. **DECISION-01 (P1):** حارس four-eyes في `transition_decision`.
5. **ATT-01 (P1):** تصحيح منطقة التوقيت في `calculate_late_minutes`.

**قبل الإنتاج (P2):** SDEF-01 (revoke public) · ESI-01/02 (تحصين الدخول) · CTB-02/CTB-04
(فرض الهوية/الحالة خادمياً) · CTB-01 (حارس مسار) · DISPUTE-01 (فلترة النصاب) · REL-01/02/04/05/06
(تسوية الإصدار/التوثيق/الأسرار/التغطية) · ARCH-02 (mocks كسولة).

**جودة (P3):** RLS-03 · SDEF-02 · ESI-03 · LEDGER-02 · CTB-05 · ARCH-01/03/05.

**مقارنة بالفحص السابق (P0-01…P0-07):** كلها **مُصلَحة** في المخطط الحالي (48 migration):
ABAC مطبَّق عبر `can_access_employee` 2-arg، `management_descendants` تكراري حقيقي، workflow
متعدد المراحل، منع الكتابة المباشرة على passkey، WebAuthn محصّن، مسار KPI محدّث. النتائج
أعلاه **جديدة** كُشِفت على حالة البناء الحالية.

---

## 10. حالة الإصلاح والتحقق (2026-07-15)

**تم تطبيق إصلاحات P0/P1 الخمسة** في
[`0050_audit_remediation_p0_p1.sql`](supabase/migrations/0050_audit_remediation_p0_p1.sql)
مع اختبار تشغيلي
[`tests/0031_audit_remediation_runtime.sql`](supabase/tests/0031_audit_remediation_runtime.sql)
(9 تأكيدات):

| المعرّف | الإصلاح | التحقق التشغيلي |
|---|---|---|
| RLS-01 | سياسات `employee_compensation`/`employee_loans`/`loan_installments` صارت تستخدم `can_access_employee(employee_id, code)` | ✅ كاتب رواتب نطاق `department` يرى 0 صف خارج النطاق ولا يستطيع تحديثه |
| RLS-02 | إضافة `can_access_employee` لكل مراحل كتابة `kpi_scores` | ✅ (سياسة؛ persona في 0031) |
| LEDGER-01 | idempotency بنيوي (`on conflict do nothing` + `found`) + `pg_advisory_xact_lock` | ✅ استدعاء مكرّر بنفس `source_key` طبّق الاستحقاق مرة واحدة (5 لا 10) |
| DECISION-01 | حارس four-eyes في `transition_decision` (المعتمِد ≠ المؤلف/المقدّم) | ✅ مؤلف القرار يُرفض اعتماده (42501) |
| ATT-01 | `calculate_late_minutes` يفسّر بداية الوردية بمنطقة زمنية (افتراضي Africa/Cairo) | ✅ حضور متأخر بالقاهرة يُحتسب متأخراً لا 0 |

**نتائج التحقق النهائي:**
- `supabase db reset` **مرتين متتاليتين** (0001→0050) نجح — قابلية من الصفر مثبتة.
- `supabase test db`: **31 ملف / 350 تأكيد — PASS** (مرتين).
- `npm run check:all`: typecheck + 33 اختبار React + build + Dart (61 ملف) +
  **50 migration متسلسلة** + secret scan — كلها نجحت.
- إصلاحات الإصدار المطبَّقة: تحديث عدّادات الجرد (50/31/350) في README و RELEASE_STATUS
  (REL-01/05)، حذف ملفات scratch وإضافة أنماط .gitignore (REL-04)، تقوية
  `check-no-secrets.mjs` (قاعدة pepper/secret + دعم .ps1) (REL-02)، وإعادة توليد
  `BUILD_MANIFEST.json` (1269 ملفاً، متطابق مع القرص).

**تحديث — إصلاحات P2/P3 المطبَّقة (migration 0052 + edge + web):**
تم لاحقاً إغلاق معظم P2/P3 في
[`0052_audit_remediation_p2_p3.sql`](supabase/migrations/0052_audit_remediation_p2_p3.sql)
+ تعديلات Edge/Web + اختبار [`tests/0032`](supabase/tests/0032_audit_remediation_p2.sql):

| المعرّف | الإصلاح | التحقق |
|---|---|---|
| SDEF-01 | `revoke execute ... from public, anon` على دوال DEFINER في 0033/0035/0036 | ✅ pgTAP: anon لا يستطيع تنفيذ RPCs الرواتب/الخدمات |
| CTB-04 | trigger يفرض `security_events.handled_by = auth.uid()` | ✅ pgTAP: قيمة مزوّرة تُستبدل بالمستدعي الفعلي |
| CTB-02 | trigger يمنع مقدّم التذكرة من نقلها لحالة امتيازية (يُسمح cancel فقط) | ✅ pgTAP: self-resolve مرفوض (42501)، cancel مسموح |
| DISPUTE-01 | عدّ النصاب يقتصر على أعضاء اللجنة النشطين لهذه القضية | ✅ static (فلترة `case_id`+`is_active` في finalize/issue) |
| RLS-03 | قراءة `course-materials` مقيّدة بالمسجّلين أو `learning.course.manage` | ✅ static (سياسة storage.objects) |
| ESI-01 | موعد نهائي مطلق ثابت بدل أرضية + عدم تسريب فرق التوقيت | ✅ مراجعة كود (edge) |
| ESI-02 | عدم الوثوق بترويسات IP إلا خلف `TRUSTED_PROXY=1` | ✅ مراجعة كود (edge) |
| ESI-03 | مقارنة ثابتة الزمن لسرّ الـcron (`_shared/secret.ts`) في الدوال الأربع | ✅ مراجعة كود (edge) |
| CTB-01 | حارس مسار `RequirePermission` لكل مسار حسّاس في `App.tsx` | ✅ typecheck + build |

**تحديث — إصلاحات P3 المطبَّقة:**

| المعرّف | الإصلاح | التحقق |
|---|---|---|
| LEDGER-02 | trigger الإجازات يُصدر `refund` عند إلغاء طلب معتمد (بدل `release`) — [`0055`](supabase/migrations/0055_audit_remediation_p3_ledger.sql) | ✅ pgTAP [`0034`](supabase/tests/0034_audit_remediation_p3_ledger.sql): إلغاء طلب معتمد يُعيد `consumed_units` إلى 0 |
| ARCH-01 | استخراج مساعد `rpc<T>()` مشترك في [`core/rpc.ts`](apps/admin_web/src/core/rpc.ts) وحذف النسخ الستّ المكرّرة | ✅ typecheck + build |
| ARCH-03 | توثيق نموذج single-tenant في [`shared-contracts/src/index.ts`](packages/shared-contracts/src/index.ts) | ✅ |

**متروك عمداً (المخاطرة تفوق الفائدة، جودة بحتة بلا أثر أمني/وظيفي):**
- **SDEF-02** (`search_path=public,auth` بلا `pg_temp`) — لا استغلال (كل المراجع مؤهّلة
  بالمخطط)، وإصلاحه يتطلب إعادة تعريف ~28 دالة كاملة (خطر نسخ عالٍ، فائدة صفرية).
- **ARCH-02** (mocks في الحزمة) — غير قابلة للوصول في الإنتاج (`isMock` لا يصبح true).
- **ARCH-05** (كود كثيف) و**CTB-05** (coercion بدل zod) — تنسيق/اتساق فقط؛ إعادة الكتابة
  تُدخل خطراً دون مكسب وظيفي. جميعها موثّقة كدَين تقني اختياري.

**المتبقّي فعلاً:** الاختبارات الخارجية فقط (أجهزة فعلية Passkey/GPS، iOS build،
backup/restore drill) المذكورة في §8 و RELEASE_STATUS — لا تُنفَّذ في هذه البيئة.

*انتهى التقرير.*
