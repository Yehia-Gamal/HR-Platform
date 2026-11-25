# MASTER BUILD PROMPT V8 — منصة «أحلى شباب Management OS» — المصدر الوحيد للحقيقة

> **الإصدار الموحّد النهائي:** V8 Enterprise Governance, Automation & Process Intelligence — مبني فوق V7 Unified Applications Complete — يدمج V1–V6 ويثبت نهائيًا تطبيق Flutter واحدًا للموظف والمدير والمدير التنفيذي، ولوحة React Web واحدة تضم HR Workspace وMain Admin Workspace، مع Backend موحد وصلاحيات خادمية.
> هذا الملف أمر تنفيذي شامل لوكيل ذكاء اصطناعي برمجي يعمل داخل مستودع المشروع. يجب إرفاقه مع: النظام القديم، الخطط والتقارير، التصميمات التخيلية، APK تطبيق التبرعات المرجعي، وملفات البيانات المتاحة.

---

## 1. دورك ومسؤوليتك

أنت الآن **Principal Software Architect + Senior Flutter Engineer + Senior React/TypeScript Engineer + Supabase/PostgreSQL Security Engineer + Product Manager + HRIS Domain Analyst + UI/UX Lead + QA/DevOps Lead**.

مهمتك إنشاء منصة موارد بشرية إنتاجية جديدة باسم:

**Ahla Shabab HR V2 — أحلى شباب HR**

لا تقم بترقيع النظام القديم أو نقل طبقاته. استخدم القديم فقط لاستخراج المتطلبات وقواعد العمل والبيانات واختبارات القبول. أنشئ مشروعًا جديدًا نظيفًا، قابلًا للصيانة والتوسع، ويعمل فعليًا على:

- Android وiOS عبر Flutter.
- Web Dashboard عبر React + TypeScript + Tailwind CSS.
- Backend/Data/Auth/Storage عبر Supabase.

اللغة الأساسية عربية، واتجاه الواجهة RTL، والمنطقة الزمنية التشغيلية `Africa/Cairo`، مع تخزين جميع timestamps في UTC وعرضها حسب المنطقة الزمنية المحددة.

---

## 2. النتيجة المطلوبة

أنشئ نظامًا حقيقيًا وليس Prototype أو مجموعة شاشات ثابتة. يجب أن يشمل:

1. قاعدة بيانات منظمة ومهاجرات قابلة لإعادة التشغيل.
2. RLS وصلاحيات فعلية مختبرة.
3. Edge Functions/RPCs للعمليات الحساسة.
4. تطبيق Flutter واحد موحّد للموظف والمدير المباشر والمدير التنفيذي والأدوار الميدانية؛ يفتح Workspace مختلفًا حسب الصلاحيات، مع بقاء الحماية الحقيقية في RLS/RPC/Edge Functions.
5. المدير التنفيذي Mobile-Only تشغيليًا داخل Executive Workspace في نفس تطبيق Flutter، ولا يحتاج إلى لوحة الويب لأي وظيفة ضمن اختصاصه.
6. لوحة React Web واحدة للأدمن الرئيسي/السكرتير التنفيذي/المبرمج وHR والأدوار الإدارية، مقسمة إلى HR Workspace وMain Admin Workspace حسب الصلاحيات.
7. Design System موحد بين تطبيق Flutter الواحد وTailwind.
8. اختبارات Unit/Integration/E2E/RLS/Accessibility/Performance.
9. CI/CD وبيئات Development/Staging/Production.
10. توثيق كامل وخطة ترحيل من النظام القديم.
11. Builds إنتاجية قابلة للتكرار والتحقق.

لا تدّعِ نجاح أي شيء لم تنفذه وتتحقق منه فعليًا.

---

## 3. قواعد تنفيذ غير قابلة للتفاوض

### 3.1 قبل كتابة الكود

ابدأ بفحص جميع الملفات المرفقة واستخراج:

- الوظائف الحالية.
- الشاشات.
- قواعد الحضور والطلبات وKPI.
- الأدوار والصلاحيات.
- تصميمات UI المرجعية.
- الجداول والبيانات المطلوب نقلها.
- المشكلات الأمنية والهندسية التي يجب منع تكرارها.

ثم أنشئ أولًا:

- `docs/01_PRODUCT_REQUIREMENTS.md`
- `docs/02_DOMAIN_AND_WORKFLOWS.md`
- `docs/03_ARCHITECTURE.md`
- `docs/04_DATABASE_ERD.md`
- `docs/05_ROLE_PERMISSION_MATRIX.md`
- `docs/06_UI_UX_SCREEN_MAP.md`
- `docs/07_TEST_STRATEGY.md`
- `docs/08_MIGRATION_PLAN.md`
- `docs/09_RELEASE_RUNBOOK.md`
- `docs/10_PERMISSION_ROLE_CATALOG.md`
- `docs/11_ACCEPTANCE_SCENARIOS.md`
- `docs/12_FEATURE_CATALOG_AND_ROADMAP.md`
- `docs/13_DATA_DICTIONARY.md`
- `docs/14_PRIVACY_RETENTION_MATRIX.md`
- `docs/15_NOTIFICATION_CATALOG.md`
- `docs/ASSUMPTIONS_AND_DECISIONS.md`

لا تبدأ في بناء عشرات الشاشات قبل تثبيت Foundation واختبار أول Vertical Slice.

### 3.2 إدارة الغموض

- لا توقف العمل بسبب سؤال صغير.
- اختر افتراضًا آمنًا وقابلًا للضبط، وسجله في `ASSUMPTIONS_AND_DECISIONS.md`.
- توقف فقط عندما تحتاج سرًا غير موجود، قرارًا قانونيًا/ماليًا لا يجوز تخمينه، أو إجراءً قد يسبب فقد بيانات.
- لا hard-code أسماء أشخاص أو قواعد قابلة للتغيير؛ اجعلها إعدادات وبيانات.

### 3.3 محظورات

ممنوع:

- نسخ Vanilla JS/CSS القديم إلى المشروع الجديد.
- وضع Service Role أو secrets داخل Flutter/React/Git.
- استخدام كلمة مرور افتراضية تساوي رقم الهاتف.
- قبول قرار أمني يرسله العميل مثل `isTrusted`, `riskScore`, `isAdmin`.
- تخزين biometric raw.
- حفظ نسخة يدوية موازية من access/refresh tokens.
- استخدام `localStorage` لبيانات حساسة أو كبديل لقاعدة البيانات.
- إظهار نجاح وهمي عند فشل API.
- إنشاء أزرار أو صفحات غير موصولة ببيانات فعلية.
- ترك بيانات demo داخل Production.
- استخدام `USING (true)` أو `WITH CHECK (true)` على جداول حساسة.
- استخدام `dangerouslySetInnerHTML` أو HTML غير منقّى إلا باستثناء موثق ومختبر.
- ملفات عملاقة متعددة المسؤوليات أو طبقات `patches` متراكمة.
- تعديل migration طُبقت؛ أنشئ migration جديدة.
- تنفيذ تغييرات Production يدويًا خارج Runbook/CI إلا كإجراء طوارئ موثق.
- تجاوز الاختبارات أو حذفها لتصبح خضراء.
- نشر APK Debug أو توقيع Release بشهادة Debug.

---

## 4. التقنية المستهدفة

استخدم أحدث إصدارات Stable المتوافقة وقت التنفيذ، وثبّت الإصدارات وملفات القفل وسجلها في `docs/TECH_STACK.md`.

### 4.1 Flutter

- Flutter stable + Dart stable.
- `flutter_riverpod` لإدارة الحالة والاعتماديات.
- `go_router` للتنقل والحراس وDeep Links.
- `freezed` + `json_serializable` للنماذج immutable.
- `supabase_flutter`.
- Secure storage عبر Keychain/Keystore للجلسات اللازمة وفق SDK الرسمي.
- قاعدة محلية للكاش غير الحساس وDrafts فقط.
- Feature-first + طبقات Presentation/Application/Domain/Data عند الحاجة.
- Flavors: dev/staging/prod.
- Android signed AAB وiOS archive عند تفعيل iOS.

### 4.2 React Web

- React + TypeScript strict.
- Vite.
- Tailwind CSS عبر المسار الرسمي المتوافق مع Vite.
- TanStack Query لـserver state.
- React Hook Form + Zod للنماذج.
- React Router أو TanStack Router؛ اختر واحدًا ووثّق القرار.
- Radix/Headless primitives عند الحاجة للوصول، مع Design System خاص بالمشروع.
- Vitest + React Testing Library + Playwright.
- لا تخلط server state وform state وglobal UI state.

### 4.3 Supabase

- Supabase Auth.
- PostgreSQL.
- Storage private buckets.
- Edge Functions بـTypeScript/Deno للعمليات الحساسة.
- Realtime فقط حيث توجد قيمة فعلية.
- Supabase CLI محليًا وفي CI.
- pgTAP أو اختبارات SQL مكافئة للسياسات والمنطق.
- Generated TypeScript types من قاعدة البيانات للويب.
- عقود Dart مولدة أو محدثة بصورة منضبطة للموبايل.

### 4.4 المستودع

```text
ahla-shabab-hr-v2/
├── apps/
│   ├── mobile_flutter/
│   └── admin_web/
├── packages/
│   ├── design_tokens/
│   ├── shared_contracts/
│   └── tooling/
├── supabase/
│   ├── migrations/
│   ├── functions/
│   ├── seed/
│   └── tests/
├── docs/
├── scripts/
└── .github/workflows/
```

استخدم `pnpm` للويب والأدوات، وثبت lockfile. استخدم أوامر Flutter القياسية للموبايل. لا تضف Turborepo أو أدوات معقدة بلا حاجة مثبتة.

---

## 5. مبادئ المنتج

- Mobile-first للموظف والمدير المباشر.
- Mobile-only تشغيليًا للمدير التنفيذي داخل Executive Workspace مخصص لاتخاذ القرار من الهاتف في نفس تطبيق Flutter.
- Desktop-first للأدمن الرئيسي/السكرتير التنفيذي/المبرمج وHR والإدارة، مع Responsive كامل.
- لا يُجبر المدير التنفيذي على فتح لوحة الويب لتنفيذ أي وظيفة ضمن اختصاصه.
- تطبيق Flutter واحد يضم Employee Workspace وManager Workspace وExecutive Workspace؛ الصلاحيات تحدد تجربة العرض، وRLS/RPC/Edge Functions تحدد الوصول الحقيقي.
- لوحة React واحدة تحتوي Workspaces حسب الدور.
- البساطة البصرية المستوحاة من تطبيق التبرعات، مع الاحتفاظ بهوية أحلى شباب الزرقاء.
- لا نسخ Pixel-perfect للتصميمات التخيلية؛ استخرج منها الأفكار والهوية فقط.
- كل شاشة لها هدف رئيسي واضح.
- لا تعتمد الحالة على اللون وحده؛ استخدم Icon + Label + Color.
- جميع الوحدات قابلة للتفعيل عبر Feature Flags/Settings عند الحاجة.
- القواعد التشغيلية Versioned وEffective-dated.


## 5.1 قرار معماري ملزم — تطبيق واحد وويب واحد

### تطبيق Flutter الواحد

استخدم تطبيق Flutter واحدًا فقط لجميع مستخدمي الهاتف، ولا تنشئ تطبيقًا أو Package مستقلًا للمدير التنفيذي. بعد تسجيل الدخول، يجلب التطبيق من الخادم:

- الأدوار الفعالة.
- الصلاحيات والنطاقات.
- التكليفات المؤقتة.
- `mobile_experience_mode` للعرض فقط.
- سياسة الحضور الخاصة بالمستخدم.

ثم يفتح أحد أوضاع التجربة التالية:

```text
Employee Workspace
Manager Workspace
Executive Workspace
```

قواعد مهمة:

1. المدير المباشر هو موظف أيضًا؛ يحتفظ بوظائف الموظف، ويظهر له قسم إضافي باسم «إدارة فريقي».
2. المدير التنفيذي يستخدم نفس التطبيق، لكن `Executive Workspace` يستبدل التنقل والرئيسية بالكامل بتجربة تنفيذية.
3. المدير التنفيذي يكون `attendance_required = false` و`self_punch_enabled = false` عبر Attendance Policy/Assignment، وليس عبر شرط واجهة فقط؛ لذلك لا تعرض له الحضور الشخصي أو البصمة أو مشاركة موقعه أو فيديوه الشخصي.
4. يمكن للمدير التنفيذي طلب موقع وفيديو الموظفين المصرح بهم، لكن لا يرسل موقعه باعتباره موظفًا.
5. عند تعدد الأدوار، يستطيع المستخدم التبديل بين Workspaces المسموحة من Workspace Switcher، باستثناء أن Executive Workspace هو الافتراضي للمدير التنفيذي.
6. إخفاء الوحدة لا يمثل حماية؛ كل استعلام وإجراء يجب أن يمر عبر RLS/RPC/Edge Function.
7. استخدم Bottom Navigation ثابتًا لكل Workspace:
   - الموظف: الرئيسية، الحضور، الطلبات، الإشعارات، المزيد.
   - المدير: الرئيسية، فريقي، الاعتمادات، التقارير، المزيد.
   - التنفيذي: الرئيسية، الإجراءات، الخريطة، التقارير، المزيد.
8. حافظ على Shared Core واحد، واستخدم Feature Modules مستقلة وLazy Loading للوحدات التنفيذية والخرائط والفيديو.

### لوحة React Web الواحدة

استخدم React Web App واحدة فقط، وداخلها:

```text
HR Workspace
Main Admin Workspace
```

- **HR Workspace:** الموظفون، الحضور، الطلبات، KPI الخاص بـHR، التوظيف، Onboarding، المستندات، التدريب، وتقارير HR.
- **Main Admin Workspace:** السكرتير التنفيذي، إدارة النظام، Role/Permission Builder، القرارات والنزاعات، Executive Dispatch Center، الإعدادات، التدقيق والأمان، التكاملات، الإدارة التقنية، النسخ الاحتياطي، Feature Flags، وRelease Control.
- الأدمن الرئيسي يستطيع التبديل بين الـWorkspaces بعد MFA، بينما HR لا يرى Main Admin Workspace ولا مساراته أو عناوينه دون صلاحية.
- استخدم App Shell واحدًا، Login واحدًا، Design System واحدًا، Router واحدًا، مع Route Manifest مصدره Permission Catalog.
- يجب فصل Business Admin Mode عن Technical Admin Mode، وطلب Step-up Authentication قبل الأسرار والمهاجرات والنسخ الاحتياطي والصلاحيات الحساسة.
- لا تسمح للأدمن بانتحال المدير التنفيذي؛ يتم إرسال Action Packets إلى Executive Workspace للاعتماد الحقيقي.

### نموذج البيانات المساند للـWorkspaces

أضف أو ثبّت كيانات مثل:

- `experience_profiles`
- `user_experience_assignments`
- `workspace_routes`
- `workspace_permission_requirements`
- `attendance_policy_assignments`
- `user_workspace_preferences`

هذه الكيانات تضبط تجربة العرض فقط، ولا تستبدل `permissions`, `role_permissions`, `user_roles`, `scope_assignments`, أو RLS.

---

## 6. نظام الهوية والأدوار والصلاحيات — Dynamic RBAC + ABAC

لا تُنشئ الصلاحيات كقائمة أدوار ثابتة داخل الكود. أنشئ **Permission Catalog** مركزيًا، ثم أنشئ منه **مجموعات صلاحيات Role Templates** يمكن نسخها وتعديلها وتحديد نطاقها وتاريخ سريانها.

### 6.1 المبادئ الأساسية

- المستخدم قد يملك دورًا أو أكثر.
- الدور عبارة عن مجموعة صلاحيات، وليس شرطًا برمجيًا من نوع `if role == hr`.
- يمكن إنشاء دور مخصص دون تعديل الكود.
- كل صلاحية تتكون من:

```text
module.resource.action.scope
```

أمثلة:

```text
people.employee.read.self
people.employee.read.direct_reports
people.employee.read.department
people.employee.read.organization
people.employee.create.organization
people.employee.update.basic
people.employee.update.sensitive
people.employee.assign_manager.department
access.account.create.organization
access.role.assign.selected_roles
attendance.records.read.team
attendance.correction.approve.department
requests.leave.approve.direct_reports
performance.kpi.finalize.organization
relations.case.read.assigned_cases
live_location.request.direct_reports
live_location.request.organization
reports.attendance.export.department
system.settings.update.security
```

لا تعتمد أسماء الصلاحيات حرفيًا فقط؛ أنشئ Catalog منظمًا يحتوي `code`, `module`, `resource`, `action`, `allowed_scopes`, `risk_level`, `description_ar`, `description_en`, `requires_mfa`, `requires_reason`, `conflicts_with`, `is_sensitive`.

### 6.2 نطاقات الوصول Scopes

ادعم على الأقل:

- `self`
- `direct_reports`
- `management_descendants`
- `selected_employees`
- `team`
- `department`
- `selected_departments`
- `branch`
- `selected_branches`
- `organization`
- `assigned_cases`
- `workflow_inbox`
- `records_created_by_user`
- `read_only_archive`

النطاق ليس مجرد فلتر واجهة؛ يجب تطبيقه داخل RLS/RPC/Edge Functions واختباره بطلب API مباشر.

### 6.3 مجموعات الصلاحيات الجاهزة Role Templates

أنشئ Templates أولية قابلة للتعديل والنسخ، ولا تربطها بأسماء أشخاص:

1. **موظف `employee`**
   - ملفه الشخصي المسموح.
   - حضوره وجدوله وطلباته وتقييمه ومستنداته وإشعاراته فقط.
   - إنشاء طلبات وشكاوى والاطلاع على القرارات الموجهة إليه.

2. **أوبريشن / مسؤول تشغيل `operations_officer`**
   - المهام والقوافل والمأموريات والتشغيل اليومي في نطاقه.
   - متابعة حالات التنفيذ دون فتح بيانات HR الحساسة.
   - يمكن منحه قراءة حضور تشغيلية محدودة دون الرواتب أو العقود.

3. **مدير تشغيل `operations_manager`**
   - إدارة فريق التشغيل والمهام والورديات والمأموريات.
   - الموافقة على طلبات تشغيلية حسب Workflow.
   - طلب موقع مباشر لموظفين في نطاقه فقط إذا منحت السياسة هذه الصلاحية.
   - لا يرى الشكاوى السرية أو الرواتب دون صلاحية إضافية.

4. **مدير مباشر `direct_manager`**
   - التقارير المباشرة فقط.
   - الحضور، الطلبات، التقييم، الجدول، والتوفر الوظيفي لفريقه.

5. **مدير إدارة / مدير عادي `department_manager`**
   - موظفو الإدارة أو شجرة الإدارة وفق النطاق.
   - تقارير الإدارة واعتماداتها دون إعدادات النظام.

6. **مدير فرع `branch_manager`**
   - نطاق الفرع المحدد فقط.
   - تشغيل وحضور وطلبات وتقارير الفرع.

7. **HR Specialist `hr_specialist`**
   - ملفات الموظفين والحضور والإجازات والعقود والمستندات في نطاقه.
   - لا يغير الأدوار الحساسة ولا إعدادات الأمان ولا الرواتب إلا إذا أضيفت صلاحية مستقلة.

8. **HR Manager `hr_manager`**
   - إدارة عمليات HR والسياسات ودورات الأداء داخل النطاق.
   - Maker/Reviewer وفق قواعد الفصل بين المسؤوليات.

9. **سكرتير تنفيذي `executive_secretary`**
   - صندوق متابعة تنفيذي، المراسلات، القرارات، مهام المتابعة، دورات KPI والموافقات الممنوحة.
   - لا يحصل تلقائيًا على إدارة أسرار النظام.

10. **مدير تنفيذي `executive_director`**
    - Dashboard تنفيذية، الموافقات النهائية، القرارات، المخاطر، لجنة الخلافات، التقارير العليا.
    - طلب الموقع المباشر وفق سياسة واضحة وسجل تدقيق.
    - الوصول التفصيلي للبيانات الحساسة يمنح صراحة وليس تلقائيًا لكل شيء.

11. **عضو لجنة `committee_member`**
    - القضايا التي عُيّن فيها فقط.
    - لا يرى باقي القضايا أو ملفات الموظف الكاملة.

12. **رئيس لجنة `committee_chair`**
    - إدارة الجلسة، النصاب، المحضر، القرار والتوقيع في القضايا المعينة.

13. **مقرر/سكرتير لجنة `committee_secretary`**
    - إعداد جدول الأعمال والمحاضر والمرفقات والمتابعة دون صلاحيات قرار منفردة.

14. **Auditor Read-only `auditor_readonly`**
    - قراءة سجلات وتدقيق وتقارير محددة، دون تعديل أو تصدير غير مصرح.

15. **Payroll Specialist / Payroll Approver**
    - فصل Maker عن Approver.

16. **System Admin `system_admin`**
    - إعداد المنصة والتكاملات والصحة التقنية.
    - لا يصبح HR Manager أو Payroll Approver تلقائيًا.

17. **Super Admin / Break-glass**
    - حساب طوارئ محدود جدًا، MFA إلزامي، سبب، مدة انتهاء، تنبيه فوري، وتدقيق كامل.

### 6.4 منشئ الأدوار Role Builder

أنشئ داخل لوحة React شاشة كاملة لإدارة الأدوار:

- إنشاء دور جديد.
- اختيار Template أو البدء فارغًا.
- اسم عربي/إنجليزي، وصف، لون/أيقونة للعرض فقط.
- اختيار مجموعات صلاحيات كاملة ثم تعديل صلاحيات منفردة.
- اختيار Scope افتراضي لكل مجموعة.
- تحديد الإدارات/الفروع/الموظفين المسموحين.
- قيود زمنية وتاريخ بداية/نهاية.
- تفعيل MFA لصلاحيات معينة.
- اشتراط كتابة سبب قبل العمليات الحساسة.
- تعيين حد اعتماد أو قيمة مالية عند الوحدات المالية.
- منع مجموعات متعارضة عبر Segregation of Duties.
- Clone role.
- Compare roles.
- Version history.
- Effective-dated changes.
- Preview as role / Preview as user دون انتحال جلسة حقيقية.
- Impact analysis: عدد المستخدمين المتأثرين قبل الحفظ.
- Approval workflow لتغيير الأدوار الحساسة.
- إبطال الجلسات عند تقليل صلاحيات حرجة.

### 6.5 مجموعات الصلاحيات داخل الواجهة

نظّمها في Tabs/Accordions واضحة:

1. الأشخاص والملفات.
2. الهيكل والمديرون.
3. الحسابات والدخول.
4. الحضور والورديات.
5. الإجازات والطلبات.
6. المهام والتشغيل والمأموريات.
7. الموقع المباشر.
8. الأداء وKPI.
9. المستندات والعقود.
10. الشكاوى ولجنة الخلافات.
11. القرارات والتواصل.
12. التدريب والعهد.
13. الرواتب والمزايا.
14. التقارير والتصدير.
15. التدقيق والأمان.
16. إعدادات النظام والتكاملات.

لكل صلاحية اعرض شرحًا بشريًا، مستوى الخطورة، النطاق، وهل تكشف PII أو بيانات مالية.

### 6.6 Field-level permissions

طبّق صلاحيات حقول منفصلة للبيانات الحساسة، مثل:

- الرقم القومي/الهوية.
- العنوان الشخصي.
- أرقام الطوارئ.
- الراتب والبدلات.
- المستندات الطبية.
- ملاحظات التحقيق.
- ملاحظات المراجعين في KPI.
- بيانات الحساب والدخول.

ادعم `visible`, `masked`, `editable`, `hidden`, ولا ترسل الحقل من الخادم أصلًا عند عدم السماح.

### 6.7 الصلاحيات المؤقتة والتفويض

- تفويض مدير أثناء الإجازة.
- صلاحية مؤقتة لمشروع أو لجنة.
- تاريخ بداية ونهاية.
- منع التفويض المتسلسل غير المنضبط.
- إيقاف تلقائي عند انتهاء المدة.
- تنبيهات عند البدء والانتهاء.
- سجل من فوّض ماذا ولماذا.

### 6.8 قواعد منع تضارب المصالح

أمثلة إلزامية:

- منشئ Payroll Run لا يعتمدها منفردًا.
- المستخدم لا يعتمد طلبه الشخصي.
- عضو اللجنة لا يشارك في قضية يكون طرفًا فيها أو مديرًا مباشرًا لطرف وفق السياسة.
- HR لا يغير دور System Admin دون Workflow مستقل.
- من يغير سياسة حضور لا يعتمد تصحيحًا جماعيًا مبنيًا عليها في نفس العملية دون مراجعة.

### 6.9 جداول الصلاحيات

أضف على الأقل:

`permission_modules`, `permissions`, `permission_scopes`, `role_templates`, `roles`, `role_versions`, `role_permissions`, `user_roles`, `scope_assignments`, `permission_constraints`, `permission_conflicts`, `temporary_access_grants`, `delegations`, `access_change_requests`, `access_change_approvals`, `access_reviews`.

نفّذ Access Review دورية لإعادة اعتماد الصلاحيات الحساسة.

---

## 7. النطاق الوظيفي الكامل

### 7.1 الهوية والمصادقة

- لا تسجيل ذاتي للموظفين.
- إنشاء الحساب عبر HR/عملية Onboarding مصرح بها.
- Login identifier آمن برقم الهاتف أو البريد دون user enumeration.
- دعوة أولية أو OTP/كلمة مرور مؤقتة عشوائية مع تغيير إجباري.
- MFA إلزامي للأدوار الحساسة.
- إدارة الأجهزة والجلسات وإبطالها.
- Session timeout قابل للضبط حسب الدور مع حفظ Drafts غير الحساسة.
- Account lock/rate limit/audit.
- Passkey اختياري بعد تأسيس الحساب.

### 7.2 المؤسسة والهيكل

- Legal entities.
- Branches/work sites.
- Cost centers/projects.
- Departments/sections/teams.
- Positions/job titles/job grades.
- Employment types.
- Manager hierarchy effective-dated.
- Delegation أثناء الغياب.
- Organizational chart.
- نقل/ترقية/تكليف بتاريخ سريان وسجل تاريخي.

### 7.3 ملف الموظف 360°

- Profile وبيانات شخصية واتصال وطوارئ.
- بيانات وظيفية وعقد ودرجة ومدير وموقع.
- مؤهلات وخبرات ومهارات وشهادات.
- مستندات وتواريخ انتهاء.
- تاريخ وظيفي.
- حضور وإجازات وطلبات وKPI.
- تدريب وترقيات ومكافآت وجزاءات.
- عهد وأصول.
- Payroll summary محمي عند تفعيله.
- Field-level permissions وmasking.
- Change history.

حالات الموظف:

```text
draft -> invited -> onboarding -> active
active -> suspended -> active
active -> notice_period -> terminated -> archived
onboarding -> probation_failed -> terminated
```

لا يتم حذف الموظف الذي لديه تاريخ؛ يستخدم Archive/Termination.

### 7.3.1 إنشاء الموظف والحساب — Employee Creation Wizard

أنشئ معالجًا متعدد الخطوات في React، مع نسخة مبسطة للهاتف للأدوار المصرح لها. يجب أن يدعم الحفظ كمسودة والاستكمال لاحقًا.

#### الخطوة 1 — الهوية الأساسية

- الاسم الكامل بالعربية، والاسم بالإنجليزية اختياري.
- كود الموظف: تلقائي وفق Sequence قابل للضبط أو إدخال يدوي مع منع التكرار.
- صورة شخصية: رفع، قص، تدوير، ضغط، معاينة، وبديل بأحرف الاسم.
- الجنس وتاريخ الميلاد والحالة الاجتماعية عند الحاجة القانونية، مع صلاحيات وخصوصية.
- الرقم القومي/رقم الهوية، جهة الإصدار، وتاريخ الانتهاء عند الحاجة.
- الجنسية.
- حالة الموظف.

#### الخطوة 2 — بيانات الاتصال

- رقم هاتف أساسي بصيغة موحدة E.164.
- رقم بديل.
- بريد إلكتروني شخصي.
- بريد عمل اختياري أو مولد تلقائيًا.
- العنوان.
- جهة اتصال للطوارئ وعلاقتها ورقمها.
- منع التكرار مع إظهار تعارض آمن للمستخدم المصرح دون كشف بيانات غير لازمة.

#### الخطوة 3 — البيانات الوظيفية

- المؤسسة/الكيان القانوني.
- الفرع وموقع العمل.
- الإدارة والقسم والفريق.
- المسمى الوظيفي والوظيفة Position والدرجة الوظيفية.
- نوع التوظيف والعقد.
- تاريخ التعيين، تاريخ مباشرة العمل، وتاريخ نهاية العقد إن وجد.
- فترة الاختبار.
- مركز التكلفة/المشروع.
- حالة الدوام: كامل/جزئي/مؤقت/متطوع/متدرب/مستشار حسب السياسات.
- نظام العمل: مكتبي/ميداني/هجين/عن بعد.

#### الخطوة 4 — المدير والعلاقات الإدارية

- مدير مباشر أساسي.
- مدير وظيفي Functional Manager اختياري.
- مشرف تشغيل اختياري.
- Dotted-line manager.
- تاريخ سريان العلاقة.
- منع أن يكون الموظف مديرًا لنفسه.
- كشف ومنع الحلقات الدائرية في الهيكل.
- عرض Preview للشجرة التنظيمية قبل الحفظ.
- إمكانية نقل المدير لاحقًا مع الاحتفاظ بالتاريخ.

#### الخطوة 5 — الوردية والحضور

- Work calendar.
- الوردية أو Shift Pattern.
- موقع/مواقع الحضور المسموحة.
- سياسة Geofence.
- هل يحتاج Passkey/Device binding/Selfie.
- تاريخ بدء سياسة الحضور.
- استثناءات موثقة ومؤقتة.

#### الخطوة 6 — حساب الدخول

يدعم اختيار معرف دخول واحد أو أكثر وفق سياسة المؤسسة:

- رقم الهاتف.
- البريد الإلكتروني.
- بريد العمل.
- اسم مستخدم.
- كود الموظف.

المطلوب:

- Resolve identifier على الخادم دون كشف وجود الحساب للمستخدم غير المصرح.
- إنشاء الحساب فقط من مسار خادمي مصرح.
- اختيار إحدى طريقتين:
  1. يولد النظام كلمة مرور مؤقتة عشوائية قوية.
  2. يدخل المسؤول كلمة مرور أولية مطابقة لسياسة القوة.
- **ممنوع** أن تكون كلمة المرور رقم الهاتف أو رقم الهوية أو كود الموظف.
- إجبار تغييرها عند أول دخول.
- لا تعرض كلمة المرور مرة ثانية بعد إغلاق شاشة الإنشاء.
- إرسال رابط تفعيل/OTP أو تسليم آمن حسب القناة المعتمدة.
- خيار اشتراط MFA من أول دخول للأدوار الحساسة.
- تفعيل/تعطيل الحساب، تاريخ انتهاء الدعوة، وإعادة إرسال الدعوة.

#### الخطوة 7 — الدور ومجموعات الصلاحيات

- اختيار Template: موظف، أوبريشن، مدير تشغيل، مدير مباشر، مدير إدارة، HR، سكرتير تنفيذي، مدير تنفيذي، عضو لجنة، إلخ.
- إمكانية إسناد أكثر من دور.
- تحديد Scope لكل دور.
- إظهار ملخص "سيستطيع هذا المستخدم... ولن يستطيع...".
- كشف التعارضات قبل الحفظ.
- الصلاحيات الحساسة تحتاج موافقة أو MFA وفق السياسة.

#### الخطوة 8 — المستندات والعقد

- صورة الهوية.
- العقد.
- المؤهل.
- شهادات.
- مستندات مطلوبة حسب نوع الوظيفة.
- تاريخ انتهاء وتنبيهات.
- تحقق من نوع/حجم الملف وفيروسات عند توفر خدمة فحص.
- Storage خاص وروابط موقعة.

#### الخطوة 9 — الراتب والمزايا عند تفعيل Payroll

- Salary structure.
- مكونات الراتب والبدلات.
- الحساب البنكي المشفر/المقنع.
- التأمينات/الضرائب وفق السياسة المعتمدة.
- لا يستطيع منشئ الموظف رؤية أو تعديل هذا القسم دون صلاحية منفصلة.

#### الخطوة 10 — Onboarding والعهد

- اختيار Onboarding Template.
- إنشاء مهام تلقائية لـHR وIT والمدير والموظف.
- تسليم جهاز/شريحة/مفاتيح/زي/عهدة.
- سياسات وإقرارات مطلوبة.
- اجتماع تعريف ومراجعة فترة الاختبار.

#### الخطوة 11 — المراجعة والإنشاء

- Summary كامل مع Validation.
- كشف البيانات الناقصة والتعارضات.
- خيار `Create as draft` أو `Create and invite`.
- عملية الإنشاء Transactional قدر الإمكان؛ لا تترك Auth User بلا Employee أو العكس.
- عند فشل جزء، نفّذ Compensation موثقًا أو حالة `provisioning_failed` قابلة للاستكمال.
- Audit يشمل المنشئ والقيم الحساسة المتغيرة دون تسجيل كلمات المرور.

### 7.3.2 الاستيراد الجماعي للموظفين

- CSV/XLSX Template رسمي.
- Mapping للأعمدة.
- Preview وDry Run.
- Validation للأسماء والهواتف والمديرين والأدوار والإدارات.
- مطابقة المدير بالـEmployee Code لا بالاسم فقط.
- كشف التكرارات والحلقات الإدارية.
- نتيجة لكل صف: جاهز/تحذير/مرفوض.
- لا تنشئ الحسابات إلا بعد اعتماد Batch.
- Rollback/compensation وإعادة المحاولة الآمنة.
- تقرير نهائي بعدد الموظفين والحسابات والصور والمستندات والأخطاء.

### 7.3.3 صفحة الموظف 360° التفصيلية

استخدم Tabs حسب الصلاحية:

- نظرة عامة.
- البيانات الشخصية.
- الوظيفة والهيكل.
- الحساب والأجهزة والجلسات.
- الحضور والورديات.
- الإجازات والطلبات.
- الأداء وKPI.
- العقود والمستندات.
- التدريب والمهارات.
- العهد.
- المكافآت والجزاءات.
- الشكاوى والقضايا المصرح بها.
- القرارات والإقرارات.
- الراتب والمزايا بصلاحية منفصلة.
- السجل التاريخي وAudit.

كل تعديل حساس يجب أن يوضح القيمة السابقة والجديدة وتاريخ السريان والسبب.


### 7.4 Recruitment / ATS

- Manpower requisition واعتمادها.
- Job openings.
- Candidates and sources.
- CV/private attachments.
- Stages: new, screened, shortlisted, interview, assessment, offer, hired, rejected, talent_pool.
- Interview panels and scorecards.
- Offer letters.
- Conversion to employee.
- Audit and privacy/retention.

### 7.5 Onboarding وProbation

- Templates حسب الوظيفة/الإدارة.
- Tasks مع owner وdue date وstatus.
- المستندات والسياسات والإقرارات.
- إنشاء الحساب والصلاحيات.
- تسليم العهد.
- مراجعات 30/60/90 أو سياسة قابلة للضبط.
- تنبيه قبل نهاية الاختبار.
- تثبيت/تمديد/إنهاء بموافقة موثقة.

### 7.6 الحضور والورديات

- Work calendars والإجازات الرسمية.
- Fixed/rotating/flexible/split shifts.
- Shift assignments effective-dated.
- Breaks, grace, late, early leave, overtime, night work.
- Check-in/check-out server-authoritative.
- GPS accuracy + geofence + timestamp من السيرفر.
- Passkey/device verification عند السياسة.
- Selfie فقط عند الحاجة مع retention واضح.
- Attendance risk flags ومراجعة بشرية.
- Correction requests.
- Missing punch resolution.
- Field/remote work.
- Monthly attendance sheet.
- Closing period وexceptional unlock audited.
- No biometric raw.
- Anti-replay/idempotency.

حالات حدث الحضور:

```text
pending_verification -> accepted
pending_verification -> rejected
accepted -> flagged_for_review -> confirmed | corrected | voided
```

حالات يوم الحضور:

```text
scheduled | rest_day | holiday | leave | mission | present | late | absent | incomplete | excused
```

قواعد حسم التعارض يجب أن تكون موثقة ومختبرة.

### 7.7 الإجازات والأذونات

- Leave types Versioned.
- Accrual ledger لا رقم رصيد قابل للتعديل مباشرة.
- Opening balance/carryover/expiry/adjustment.
- Full day/half day/hours.
- Required attachments.
- Eligibility by service/grade/type.
- Overlap prevention.
- Workday calculation.
- Substitute/handover.
- Cancel/recall/return for correction.
- Balance reservation عند تقديم الطلب ثم التسوية عند القرار.

### 7.8 الطلبات ومحرك الموافقات

أنشئ Workflow Engine عامًا يدعم:

- Request definitions and versions.
- Dynamic steps.
- Sequential/parallel approvals.
- Conditions by amount/duration/department/type.
- Delegation.
- SLA/escalation/reminders.
- Return for correction.
- Withdraw/cancel.
- Comments/attachments.
- Conflict-of-interest guard.
- Immutable action log.
- Idempotency.

أنواع أولية:

- Leave.
- Mission.
- Late arrival permit.
- Early departure permit.
- Attendance correction.
- Convoy/Fandi/operational assignment.
- Expense/advance عند التفعيل.
- Training request.
- Transfer/promotion.
- Resignation.

حالات عامة:

```text
draft -> submitted -> in_review -> approved | rejected | returned
submitted/in_review -> withdrawn
approved -> cancelled only by authorized compensating workflow
```

### 7.9 KPI والأداء

- KPI cycles.
- Versioned templates/criteria/weights.
- Employee self evaluation.
- Direct manager review.
- HR review.
- Executive secretary review.
- Executive director final approval.
- Attendance-derived score server-side.
- Organization-specific criteria configurable and access-controlled.
- Progress, reminders, overdue.
- Calibration.
- Historical immutable finalized cycles.
- PIP and development plan.
- Visibility matrix for comments/scores by stage.

حالات الدورة:

```text
draft -> open_for_self -> manager_review -> hr_review -> executive_secretary_review -> final_review -> finalized -> archived
```

لا تعدّل دورة finalized؛ استخدم amendment بإصدار وتدقيق.

### 7.10 الرواتب والتعويضات — Module gated

صممها كوحدة منفصلة قابلة للتفعيل، ولا تستخدم Production قبل اعتماد HR/Finance/Legal:

- Salary structures/components/formulas/versioning.
- Earnings/deductions/allowances/bonuses/overtime.
- Taxes/social insurance as effective-dated configurable rules.
- Loans/advances/installments.
- Attendance inputs snapshot.
- Payroll runs.
- Validation exceptions.
- Maker/checker approval.
- Lock/post/reversal by compensating run.
- Payslips.
- Bank/accounting exports.
- Retro adjustments.
- Final settlement.

حالات Payroll:

```text
draft -> calculated -> validation_failed | ready_for_review -> approved -> posted -> paid -> closed
```

لا تسمح بتعديل run posted مباشرة.

### 7.11 المصروفات والسلف والقروض

- Categories/limits/policies.
- Receipt attachments.
- Cost center/project.
- Approval and finance review.
- Cash advance settlement.
- Employee loan schedule.
- Payroll deduction integration.

### 7.12 التدريب والتطوير

- Courses/providers/sessions.
- Requests/nominations/approvals.
- Attendance/result/certificate/cost.
- Skills and competency matrix.
- Development plans.
- Certificate expiry alerts.

### 7.13 الترقيات والمواهب

- Promotion/transfer requests.
- Eligibility rules.
- Job grade history.
- Succession plans.
- Talent pools.
- Career paths.

### 7.14 المستندات والعقود

- Private buckets.
- Document types and required matrix.
- Versioning.
- Expiry alerts.
- Signed URLs قصيرة العمر.
- Acknowledgement/e-sign integration abstraction.
- Watermark/download audit for sensitive files.
- Retention and legal hold.

### 7.15 العهد والأصول

- Asset catalog/serial/status/location.
- Assign/transfer/return.
- Condition/photos/maintenance.
- Lost/damaged workflow.
- Offboarding clearance blocker.

### 7.16 الشكاوى والخلافات والجزاءات

- Confidential intake.
- Visibility levels.
- Assignment/investigation.
- Evidence/witnesses/sessions.
- Committee minutes/members/decision/sign-off.
- Disciplinary action.
- Appeal.
- Whistleblower protection and access log.
- SLA and escalation.

### 7.17 القرارات والتواصل

- Announcement/reminder/decision/action required.
- Target by organization/branch/department/role/users.
- Priority/publish/expiry.
- In-app + Push.
- Read receipt and acknowledgement timestamp.
- Attachments.
- No sensitive content in push payload.
- Surveys/polls optional.

### 7.18 الصحة والسلامة

- Incident report.
- Injury/near miss categories.
- Location/time/witnesses.
- Investigation/corrective action.
- Restricted health fields.
- Closure and trend reports.

### 7.19 Offboarding

- Resignation/termination/end contract/retirement.
- Notice and last day.
- Handover tasks.
- Account deprovisioning.
- Asset clearance.
- Exit interview.
- Final settlement hook.
- Experience letter/document pack.
- Revoke sessions at effective time.

### 7.20 HR Helpdesk

- Ticket categories/priorities/SLA.
- Assignment/escalation/comments/attachments.
- Knowledge base/FAQs/policies/forms.
- Satisfaction rating.

### 7.21 Audit/Security/Administration

- Append-only audit events.
- Security events.
- Permission changes.
- Login/device/session history.
- Break-glass access with reason, MFA, expiry, and alert.
- Settings version history.
- Feature flags.
- Jobs/queues health.
- No secret values visible in UI/logs.

---

### 7.22 مركز التشغيل والمهام اليومية

أنشئ وحدة تشغيل مستقلة تناسب أدوار أوبريشن ومدير التشغيل:

- تعريف أنواع المهام: يومية، عاجلة، دورية، ميدانية، قافلة، فاندي، فعالية، متابعة متبرع، تجهيز مقر، نقل مواد، صيانة.
- إنشاء المهمة وتحديد الأولوية والوصف والموقع والموعد والمالك والفريق.
- Checklists وقوالب جاهزة.
- إسناد فردي أو جماعي.
- قبول/بدء/إيقاف/إكمال/تعذر.
- صور ومستندات وإثبات تنفيذ اختياري.
- تعليقات وMentions.
- وقت متوقع ووقت فعلي.
- Dependencies وBlocking issues.
- Shift handover بين فرق التشغيل.
- Daily operations board: متأخر، اليوم، قادم، متعطل، مكتمل.
- SLA وتصعيد إلى مدير التشغيل.
- ربط المهمة بالمأمورية أو القافلة أو طلب المصروف.
- عدم تحويل النظام إلى أداة مراقبة مفرطة؛ لا تسجل الحركة المستمرة بلا حاجة وسياسة.

جداول مقترحة:

`operation_task_types`, `operation_tasks`, `operation_task_assignees`, `operation_task_steps`, `operation_task_updates`, `operation_task_attachments`, `operation_shift_handovers`, `operation_incidents`.

### 7.23 نظام طلب الموقع المباشر — Live Location Request

هذه الميزة حساسة ويجب تصميمها كعملية خادمية محددة المدة، لا كتتبع سري دائم.

#### الصلاحيات

- صلاحية مستقلة `live_location.request`.
- Scope: direct reports / department / branch / selected employees / organization.
- يمكن منحها للمدير التنفيذي أو مدير التشغيل أو مدير محدد.
- الموظف العادي وHR لا يحصلان عليها تلقائيًا.

#### إنشاء الطلب

- يختار المدير الموظف أو مجموعة صغيرة مصرح بها.
- يكتب سبب الطلب من قائمة + ملاحظة.
- يحدد نوع الطلب:
  - موقع لحظي Snapshot.
  - جلسة مباشرة محددة المدة مثل 5/10/15 دقيقة وفق السياسة.
  - تحقق موقع + صورة أو فيديو قصير عند الحاجة المشروعة.
- يحدد مدة الانتهاء.
- الخادم يتحقق من الصلاحية والنطاق والحالة الوظيفية.
- ينشئ Notification وPush دون وضع الإحداثيات أو تفاصيل حساسة داخل Push payload.

#### استجابة الموظف

- شاشة واضحة تشرح من طلب الموقع والسبب والمدة.
- حالات: `pending`, `seen`, `accepted`, `declined_if_allowed`, `permission_denied`, `location_unavailable`, `expired`, `streaming`, `completed`, `cancelled`.
- توجيه المستخدم لتفعيل GPS والأذونات دون خداع.
- عرض Accuracy ومصدر الموقع والوقت.
- لا تقبل إحداثيات قديمة خارج حد زمني.
- منع replay وspoofing بقدر الإمكان، مع Risk Flags بدل ادعاء ضمان غير ممكن.
- عند العمل بالخلفية، التزم بقيود Android/iOS وأظهر الإشعار المطلوب نظاميًا.

#### شاشة المدير

- خريطة تعرض فقط الموظفين الذين استجابوا لطلب صالح.
- الاسم، الصورة، المسمى، الحالة، وقت آخر تحديث، Accuracy، هل داخل موقع عمل أم خارجه.
- لا تحتفظ بخط مسار تاريخي افتراضيًا.
- زر إلغاء الطلب.
- فتح Google Maps/خرائط الجهاز.
- تنبيه عند انتهاء الجلسة أو فقد الإشارة.

#### الخصوصية والاحتفاظ

- سياسة Retention قصيرة وقابلة للضبط.
- سبب الوصول وسجل من شاهد الموقع.
- عدم إظهار الموقع لمستخدم خرج من النطاق بعد تغيير الصلاحية.
- حذف/إخفاء البيانات بعد انتهاء الغرض وفق السياسة.
- لا يسمح بالتتبع الجماعي المفتوح بلا مدة أو سبب.

جداول:

`live_location_requests`, `live_location_request_targets`, `live_location_updates`, `live_location_access_logs`, `live_location_risk_flags`, `live_location_retention_jobs`.

### 7.24 لجنة حل المشكلات والخلافات — Dispute Resolution Committee

أنشئ وحدة كاملة، لا مجرد نموذج شكوى.

#### أنواع الحالات

- خلاف بين موظفين.
- شكوى ضد مدير أو موظف.
- سوء تفاهم أو سلوك غير لائق.
- مخالفة تسلسل إداري.
- تظلم من قرار أو جزاء.
- تنمر/تحرش/تمييز ضمن سياسات وقوانين المؤسسة.
- نزاع تشغيلي أو مالي.
- بلاغ سري/Whistleblowing.
- إحالة من HR أو المدير التنفيذي.

#### استقبال الحالة

- مقدم البلاغ، الأطراف، النوع، مستوى السرية، وصف الواقعة، التاريخ والمكان.
- مرفقات وأدلة وشهود.
- خيار سري/مقيد مع توضيح حدود السرية.
- رقم قضية غير قابل للتخمين.
- Confirmation لمقدمها دون كشف التوزيع الداخلي.
- Triage لتحديد الخطورة والتعارض والاختصاص والإجراء العاجل.

#### تشكيل اللجنة

- إنشاء لجنة دائمة أو لجنة خاصة للقضية.
- رئيس، مقرر/سكرتير، أعضاء، مستشار/مراقب اختياري.
- قواعد النصاب Quorum.
- إقرار تعارض مصالح لكل عضو.
- تنحي واستبدال العضو.
- صلاحية العضو مقصورة على القضايا المعينة.
- قرار التشكيل وتاريخ السريان.

#### التحقيق والجلسات

- خطة تحقيق.
- طلب إفادات من الأطراف.
- مقابلات وشهود.
- جلسات بتاريخ ووقت ومكان/رابط.
- جدول أعمال.
- حضور وغياب وأسباب.
- أدلة مرتبة مع Hash/Metadata وسجل تنزيل/عرض.
- ملاحظات داخلية منفصلة عن النص القابل للمشاركة.
- طلب معلومات من HR أو الإدارة بصلاحية محددة.
- Timeline لا يمكن حذف أحداثه الحساسة.

#### محضر اللجنة

- بيانات القضية واللجنة والأعضاء.
- ملخص الوقائع والطلبات.
- أقوال الأطراف والشهود بصياغة معتمدة.
- الأدلة التي تمت مراجعتها.
- المداولات المسموح بتوثيقها.
- القرار والتوصيات والإجراءات التصحيحية.
- المسؤولون عن التنفيذ والمواعيد.
- توقيع/اعتماد أعضاء اللجنة.
- إصدار PDF برقم وتاريخ وQR/verification code اختياري.
- Versions/Amendments؛ لا يتم تعديل محضر معتمد بصمت.

#### القرارات والإجراءات

- صلح ودي.
- اعتذار رسمي.
- تنبيه أو إنذار وفق السياسة.
- تدريب/إرشاد/وساطة.
- إعادة توزيع مسؤوليات.
- إحالة لـHR/إدارة قانونية/إدارة تنفيذية.
- جزاء مع Workflow منفصل.
- إغلاق لعدم كفاية الأدلة.
- Action Items ومتابعة التنفيذ.

#### الاستئناف والتصعيد

- نافذة استئناف قابلة للضبط.
- أسباب الاستئناف ومرفقاته.
- لجنة مختلفة أو جهة اعتماد أعلى.
- منع نفس صاحب القرار من اعتماد الاستئناف منفردًا.
- SLA وتنبيهات وتصعيد.

#### حالات القضية

```text
submitted -> triage -> accepted | rejected_out_of_scope | returned_for_information
accepted -> committee_formation -> investigation -> hearing -> deliberation
hearing/deliberation -> decision_draft -> awaiting_signatures -> decided
submitted..decided -> urgent_escalation
accepted..decision_draft -> mediation -> resolved | investigation
resolved/decided -> action_followup -> closed
closed -> appealed -> appeal_review -> upheld | amended | reopened
```

#### الخصوصية

- Field-level security.
- No push sensitive text.
- Watermark عند عرض مستندات شديدة الحساسية.
- Download restrictions عند الحاجة.
- Access log مرئي للمراجع المصرح.
- Retention/Legal hold.

جداول:

`relation_case_types`, `relation_cases`, `relation_case_parties`, `relation_case_witnesses`, `relation_case_evidence`, `committee_templates`, `committees`, `committee_members`, `committee_conflict_declarations`, `committee_sessions`, `session_attendees`, `session_statements`, `committee_minutes`, `committee_minute_versions`, `committee_decisions`, `committee_signatures`, `case_action_items`, `case_appeals`, `case_access_logs`.

### 7.25 نظام الأداء وتقييم الموظف المتطور

وسّع KPI ليغطي:

- أهداف سنوية/ربع سنوية/شهرية.
- قوالب مختلفة حسب الوظيفة والإدارة والدرجة.
- Versioning للأوزان والمعايير.
- معايير رقمية وسلوكية وBoolean وMilestones.
- Self assessment.
- تقييم المدير المباشر.
- مراجعة HR.
- مراجعة السكرتير التنفيذي عند السياسة.
- اعتماد المدير التنفيذي عند السياسة.
- Calibration meeting لمنع التفاوت بين المديرين.
- Evidence ومرفقات وتعليقات.
- 1:1 meetings وخطة تطوير.
- Competency matrix.
- Peer/360 feedback كميزة اختيارية وبسرية واضحة.
- أهداف مرتبطة بمهام التشغيل أو مشاريع محددة.
- درجة حضور محسوبة على الخادم من Snapshot الشهر المعتمد.
- معايير أحلى شباب الخاصة مثل الصلاة/الحلقة/المبادرات أو المشاركة المجتمعية تكون **Template قابلًا للضبط** وليست حقولًا ثابتة في الكود.
- عدم كشف درجات أو ملاحظات مرحلة غير مصرح بها للموظف.
- PIP وخطة تحسين بأهداف ومواعيد ومراجعات.
- Rewards/recognition recommendations منفصلة عن الاعتماد المالي.
- تاريخ تقييم كامل ومقارنة الاتجاه دون تشهير أو Ranking علني غير ضروري.

### 7.26 تخطيط القوى العاملة والجدولة

- Headcount plan وActual vs Plan.
- Vacancies وPositions.
- Capacity حسب الفرق.
- Skill gaps.
- Shift roster مع Drag/Drop وValidation.
- كشف التعارض وتجاوز ساعات العمل.
- بديل/مناوبة/Swap request.
- Demand forecast بسيط قابل للتطوير.
- فراغات الورديات وتنبيهات النقص.
- تقويم موحد للإجازات والمأموريات والتدريب.

### 7.27 خدمات الموظف الذاتية

أضف مركز خدمات يدعم:

- طلب خطاب HR.
- شهادة دخل عند تفعيل الرواتب.
- بيان حالة وظيفية.
- تحديث بيانات شخصية بمراجعة.
- طلب نسخة عقد/مستند.
- طلب عهدة أو صيانة عهدة.
- طلب تدريب.
- استفسار راتب/خصم بصلاحية وخصوصية.
- حجز مقابلة مع HR.
- اقتراح/مبادرة.
- تتبع SLA والتقييم بعد الإغلاق.

### 7.28 المكافآت والتقدير والتحفيز

- مكافأة مالية/غير مالية وفق الصلاحيات.
- شهادات شكر ونقاط تقدير اختيارية.
- ترشيح من المدير أو الزملاء مع مراجعة.
- ربط بالإنجازات والمبادرات.
- منع التحويل التلقائي من تقييم إلى مكافأة بلا اعتماد.
- سجل وعدالة توزيع وتقارير تحيز.

### 7.29 التنبيهات الذكية والأتمتة

أنشئ Rules Engine/Jobs للآتي:

- انتهاء عقد/هوية/مستند/فترة اختبار.
- عدم تسجيل حضور أو انصراف.
- تكرار التأخير.
- رصيد إجازة يوشك على الانتهاء.
- طلب متأخر عن SLA.
- KPI لم يبدأ أو متأخر.
- مهمة تشغيل متأخرة.
- قرار لم يتم الاطلاع عليه.
- قضية خلاف دون جلسة أو دون إجراء متابعة.
- صلاحية مؤقتة أو تفويض ينتهي.
- جهاز دخول جديد أو نشاط أمني مريب.

كل Rule تكون قابلة للتشغيل/الإيقاف وتحديد المستهدف والقنوات والتكرار، مع منع Spam وDeduplication.

### 7.30 التقارير والتحليلات الموسعة

أضف:

- Headcount movement.
- Turnover/retention.
- Absence and lateness trends.
- Overtime and workload.
- Leave utilization/liability.
- Recruitment funnel/time-to-hire.
- Onboarding/probation completion.
- Performance distribution and completion.
- Training hours/cost/effectiveness.
- Document expiry.
- Asset inventory/overdue returns.
- Complaints by category/SLA/outcome مع إخفاء الهوية عند الحاجة.
- Operations tasks completion and delays.
- Permission/access review status.
- Live-location request usage/privacy report.
- Executive scheduled digest.

يجب أن يدعم Report Builder محدودًا وآمنًا عبر Dimensions/Measures معتمدة، لا SQL حر من المتصفح.

### 7.31 التكاملات

صمم Integration Layer/Outbox يدعم مستقبلًا:

- Email provider.
- SMS/WhatsApp Business عبر مزود رسمي عند الاعتماد.
- Firebase/APNs Push.
- Google/Microsoft Calendar.
- Accounting/ERP export.
- Biometric/attendance devices عبر Adapter منفصل.
- Identity provider/SSO عند الحاجة.
- Webhooks موقعة، retries، dead-letter، idempotency.

لا تربط منطق الدومين مباشرة بمزود واحد.

### 7.32 ميزات الذكاء الاصطناعي الاختيارية والآمنة

يمكن إضافتها بعد استقرار البيانات، خلف Feature Flags:

- تلخيص تقارير تنفيذية مع روابط للأرقام الأصلية.
- صياغة مسودة إعلان أو قرار للمراجعة البشرية.
- البحث الدلالي في السياسات المسموح بها.
- اقتراح تصنيف تذكرة أو شكوى دون اتخاذ قرار.
- كشف شذوذ حضور كإشارة للمراجعة، لا كإدانة آلية.
- اقتراح أهداف تطوير أو تدريب.

ممنوع:

- قرار فصل/جزاء/تقييم نهائي آلي.
- استخدام بيانات حساسة في مزود غير معتمد.
- عرض مخرجات غير قابلة للتفسير كمعلومة مؤكدة.

### 7.33 قابلية التوسع الخاصة بالجمعية

ادعم ككيانات/Modules اختيارية:

- الموظفون والمتطوعون والمتدربون.
- الفرق الميدانية والقوافل والفعاليات.
- المشاريع والمبادرات.
- فروع ومقار متعددة.
- تكليفات مؤقتة بين الإدارات.
- ساعات تطوع ومساهمات مجتمعية عند الحاجة.
- عدم خلط بيانات المتبرعين/المستفيدين مع HR إلا عبر تكامل وصلاحيات وغرض واضح.

### 7.34 إعدادات النظام القابلة للضبط

كل القواعد التالية يجب ألا تكون مدفونة في الكود:

- أنواع العقود والموظفين.
- حالات ومسارات الموافقات.
- الورديات وGrace period وGeofence.
- أنواع الإجازات والاستحقاق.
- أنواع الطلبات والقوافل والمأموريات.
- قوالب KPI والأوزان والمراحل.
- أنواع الشكاوى واللجان والنصاب.
- قوالب القرارات والإعلانات.
- سياسات الموقع المباشر والاحتفاظ.
- قنوات الإشعارات.
- سياسات كلمات المرور والجلسات وMFA.
- Feature flags.

استخدم Settings Versioning وتاريخ سريان، مع Preview واختبارات قبل النشر.

---

## 8. الشاشات المطلوبة — Flutter

### عامة

- Splash/secure bootstrap.
- Maintenance/forced upgrade عند الحاجة.
- Login/OTP/password reset/MFA.
- Device/session management.
- No permission/offline/error screens.

### الموظف

- Home مختصرة: الحضور، الرصيد، الطلبات، الإعلانات، KPI.
- Attendance action + status + map/accuracy/policy explanation.
- Monthly attendance calendar/table.
- Schedule.
- Requests center.
- Create request forms.
- My leave balances.
- My KPI and history.
- My documents/contracts.
- My assets.
- My training.
- Payslips/loans when enabled.
- Decisions and acknowledgements.
- Notifications inbox.
- Complaints/helpdesk.
- Profile/security/settings.

### المدير

- Team dashboard.
- Pending approvals.
- Team attendance.
- Team calendar/availability.
- Employee summaries حسب الصلاحية.
- KPI reviews.
- Delegations.
- Team documents expiry summary without unauthorized content.
- Operations tasks/shift handover عند منح الدور.
- Live location request/status داخل النطاق المصرح فقط.
- Team risk/alerts دون كشف بيانات غير مصرح بها.

### المدير التنفيذي — Executive Workspace داخل تطبيق Flutter الموحد (Mobile-Only تشغيليًا)

أنشئ داخل تطبيق Flutter الموحد تجربة تنفيذية مستقلة وظيفيًا ومصممة للهاتف فقط. تُفعّل بعد حل الصلاحيات من الخادم، ويجب أن يستطيع المدير التنفيذي تنفيذ **كل وظائفه دون اللابتوب**، وتشمل:

- Executive Home تعرض ملخص اليوم، الحضور، الغياب، التأخير، المهام، القضايا، طلبات الاعتماد، القرارات، المخاطر، والتقارير الجديدة.
- Morning Brief وEvening Brief قابلان للضبط، مع ملخص نصي ورسوم مختصرة.
- Executive Inbox موحد لملفات الاعتماد المرسلة من السكرتير التنفيذي/الأدمن الرئيسي.
- Action Packets تحتوي على: ملخص، صاحب الطلب، مصدر البيانات، المرفقات، الرسوم، الإجراء المطلوب، الموعد النهائي، تاريخ الإصدارات، والتعليقات.
- اعتماد/رفض/إعادة للتعديل/طلب معلومات إضافية، مع سبب إلزامي عند الرفض أو الإعادة.
- توقيع أو اعتماد إلكتروني باستخدام إعادة المصادقة أو القياسات الحيوية عند العمليات الحساسة.
- إنشاء أو اعتماد ونشر القرارات والأخبار الرسمية من الهاتف.
- متابعة نسبة الاطلاع على القرارات والأشخاص المتأخرين.
- إنشاء تصويت رسمي أو استشاري ومراجعة النتائج والنصاب.
- Final KPI Approval ومراجعة مقارنة تقييم الموظف والمدير والسكرتير التنفيذي.
- Live Attendance Map وخريطة الموظفين الميدانيين وفق السياسة.
- طلب موقع مباشر من أي موظف نشط، وطلب فيديو تحقق حي لمدة 5 ثوانٍ، وبدء جلسة تتبع محددة المدة.
- مشاهدة آخر موقع ودقته وزمنه، وحالة استجابة الموظف، وانتهاء الجلسة تلقائيًا.
- طلب موقع جماعي لحالة طوارئ ضمن نطاق مصرح، مع سبب ومدة وتدقيق.
- Employee Executive Summary دون كشف الحقول غير الضرورية، مع فتح ملف الموظف التنفيذي المختصر.
- متابعة لجنة الخلافات والقضايا المصعدة ومحاضرها واعتماداتها.
- Executive Reports Inbox للتقارير اليومية والأسبوعية والشهرية وPDF/Excel والرسوم.
- التعليق على التقرير، وضع Annotation، وإعادته للسكرتير التنفيذي بطلب إجراء.
- Decision Execution Tracker لمتابعة تنفيذ القرارات والمهام الناتجة عنها.
- Executive Calendar للاجتماعات، آجال القرارات، جلسات اللجان، التقييمات، والتقارير.
- Risk & Incident Center للتنبيهات العاجلة والحوادث والمشكلات الأمنية والتشغيلية.
- Push Notifications عميقة Deep Links تفتح الشاشة أو العنصر المطلوب مباشرة.
- دعم الأوامر الصوتية الآمنة لإنشاء مسودة ملاحظة أو قرار، على أن يراجع المدير النص قبل الحفظ أو الإرسال.
- دعم Light/Dark، خطوط كبيرة، وضع يد واحدة، وتخطيط مناسب للشاشات الصغيرة.
- وضع اتصال ضعيف: كاش للقراءة، ضغط الصور، تحميل الخرائط عند الطلب، وعدم تنفيذ اعتماد حساس Offline.
- حماية الشاشات الحساسة من screenshots/recording حيث يسمح النظام، وروابط فيديو موقعة قصيرة العمر.
- إدارة الجلسات والأجهزة، وإلغاء الجهاز عن بعد، وMFA/Step-up Authentication.

Bottom Navigation المقترح للتنفيذي: **الرئيسية — الإجراءات — الخريطة — التقارير — المزيد**.

لا تضع إعدادات النظام المعقدة أو إنشاء الموظفين أو Role Builder داخل Executive Workspace؛ هذه مسؤولية Main Admin Workspace على الويب.

### عضو اللجنة على الموبايل عند الحاجة

- Assigned cases only.
- Session schedule.
- Read evidence حسب الصلاحية.
- Conflict declaration.
- Minutes review/signature.
- Action items.

Bottom navigation لا يزيد عادة على 4–5 عناصر رئيسية مع More، ويختلف حسب الدور دون تغيير مربك في أماكن العناصر الأساسية.

---

## 9. الشاشات المطلوبة — React Web

أنشئ App Shell واحدًا مع Workspaces:

1. Dashboard.
2. People + Employee Creation Wizard + Employee 360.
3. Organization + Org Chart + Manager Assignments.
4. Access Control + Roles + Permission Builder + Access Reviews.
5. Recruitment.
6. Onboarding.
7. Attendance & Scheduling.
8. Live Location Command Center.
9. Leave & Requests.
10. Approvals Inbox.
11. Operations & Tasks & Convoys.
12. Payroll & Compensation عند التفعيل.
13. Performance/KPI.
14. Learning.
15. Documents & Contracts.
16. Assets.
17. Employee Relations + Dispute Committee Case Center.
18. Official News & Decisions Feed + Executive Dispatch Center.
19. HR Helpdesk.
20. Reports & Analytics.
21. Audit & Security.
22. Integrations & Jobs.
23. Settings.

لكل List:

- Search/filter/sort.
- Saved views.
- Pagination أو virtualization.
- Column permissions.
- Export guarded.
- Empty/loading/error states.
- Bulk actions بصلاحيات وتأكيد وAudit.

لكل Detail:

- Summary.
- Timeline.
- Related records.
- Actions by permission.
- Audit/history where authorized.

---

## 10. Design System

أنشئ Tokens مشتركة قابلة للتوليد إلى Dart وCSS:

- Brand colors.
- Neutral surfaces.
- Semantic colors.
- Typography Cairo مع fallbacks.
- Spacing 4/8 grid.
- Radius set محدود.
- Elevation/shadows هادئة.
- Motion durations/easing.
- Breakpoints.
- Touch target >= 44–48px.
- Focus ring.
- Disabled/read-only states.

متطلبات:

- RTL كامل دون hacks.
- Light وDark صالحان بالتباين.
- WCAG AA.
- Text scaling 200%.
- Screen reader semantics.
- Keyboard navigation وfocus trap للويب.
- Reduced motion.
- لا neon/glow زائد.
- الزخرفة الخاصة بالهوية في Login/Hero/Empty states فقط.
- Components: Button, Input, Select, Date/Time, Upload, Card, Badge, Alert, Dialog, Drawer, Table, Tabs, Stepper, Timeline, EmptyState, Skeleton, Toast, Pagination, FilterBar, ApprovalCard, KPI components, Attendance components.

أنشئ Storybook أو catalog مرئي للويب، وWidget catalog/Golden tests لـFlutter.

---

## 11. قاعدة البيانات

أنشئ ERD وData Dictionary قبل DDL النهائي. استخدم schemas منطقية عند الحاجة مثل `public`, `private`, `audit` مع أقل صلاحيات.

مجموعات الجداول المطلوبة تشمل:

### Identity/Organization

`profiles`, `organizations`, `legal_entities`, `branches`, `work_sites`, `cost_centers`, `departments`, `teams`, `positions`, `job_grades`, `employment_types`, `employee_assignments`, `manager_relations`, `delegations`.

### Employees

`employees`, `employee_contacts`, `emergency_contacts`, `employee_qualifications`, `employee_experiences`, `employee_skills`, `employee_status_history`, `contracts`, `contract_versions`, `probation_reviews`.

### Access

`permission_modules`, `permissions`, `permission_scopes`, `role_templates`, `roles`, `role_versions`, `role_permissions`, `user_roles`, `scope_assignments`, `permission_constraints`, `permission_conflicts`, `temporary_access_grants`, `delegations`, `access_change_requests`, `access_change_approvals`, `access_reviews`, `session_events`, `user_devices`.

### Recruitment/Onboarding

`manpower_requests`, `job_openings`, `candidates`, `candidate_applications`, `recruitment_stages`, `interviews`, `interview_scores`, `offers`, `onboarding_templates`, `onboarding_instances`, `onboarding_tasks`.

### Attendance

`work_calendars`, `calendar_days`, `shifts`, `shift_patterns`, `shift_assignments`, `geofences`, `attendance_events`, `attendance_days`, `attendance_identity_checks`, `attendance_risk_flags`, `attendance_corrections`, `attendance_period_locks`.

### Leave/Workflow

`leave_policies`, `leave_types`, `leave_ledger`, `workflow_definitions`, `workflow_versions`, `workflow_steps`, `requests`, `request_steps`, `request_actions`, `request_attachments`, `sla_events`.

### KPI

`kpi_cycles`, `kpi_templates`, `kpi_template_versions`, `kpi_criteria`, `kpi_assignments`, `kpi_evaluations`, `kpi_scores`, `kpi_actions`, `performance_improvement_plans`.

### Payroll optional

`salary_structures`, `salary_components`, `employee_compensation`, `payroll_periods`, `payroll_runs`, `payroll_run_employees`, `payroll_lines`, `payroll_adjustments`, `payslips`, `loans`, `loan_installments`.

### Other HR

`training_courses`, `training_sessions`, `training_enrollments`, `skills`, `employee_skill_assessments`, `assets`, `asset_assignments`, `documents`, `document_versions`, `document_acknowledgements`,
`operation_task_types`, `operation_tasks`, `operation_task_assignees`, `operation_task_steps`, `operation_task_updates`, `operation_task_attachments`, `operation_shift_handovers`, `operation_incidents`,
`live_location_requests`, `live_location_request_targets`, `live_location_updates`, `live_location_access_logs`, `live_location_risk_flags`,
`relation_case_types`, `relation_cases`, `relation_case_parties`, `relation_case_witnesses`, `relation_case_evidence`, `committee_templates`, `committees`, `committee_members`, `committee_conflict_declarations`, `committee_sessions`, `session_attendees`, `session_statements`, `committee_minutes`, `committee_minute_versions`, `committee_decisions`, `committee_signatures`, `case_action_items`, `case_appeals`, `case_access_logs`, `disciplinary_actions`,
`administrative_decisions`, `decision_recipients`, `decision_reads`, `announcements`, `surveys`, `survey_responses`, `helpdesk_tickets`, `safety_incidents`, `offboarding_cases`, `offboarding_tasks`.

### Platform

`notifications`, `notification_deliveries`, `push_devices`, `feature_flags`, `system_settings`, `scheduled_jobs`, `audit_logs`, `security_events`, `integration_outbox`, `idempotency_keys`.

قواعد DDL:

- UUID consistent.
- `created_at`, `updated_at`, actor fields حيث يلزم.
- UTC.
- Check constraints.
- Foreign keys وسياسات delete مدروسة.
- Unique constraints business-specific.
- Effective dating.
- Indexes مبنية على الاستعلامات والسياسات.
- لا تخزن derived totals دون استراتيجية إعادة حساب واضحة.
- لا تخزن PII في JSON عشوائي إذا كانت تحتاج query/permission.
- Audit append-only.

---

## 12. RLS والأمان

### القاعدة

فعّل RLS على كل جدول معرض للـAPI، واكتب اختبارات لكل عملية ودور.

اختبر على الأقل:

- Anonymous denied.
- Employee self only.
- Manager direct reports only أو scope المعتمد.
- HR حسب الوظيفة والنطاق.
- Executive حسب الموافقات والنطاق.
- Admin platform access دون صلاحيات أعمال غير ممنوحة.
- Committee case membership.
- Payroll segregation.
- Field masking عبر views/RPCs عند الحاجة.

### العمليات الحساسة

استخدم Edge Function/RPC خادمية للآتي:

- إنشاء/تحديث المستخدمين.
- تغيير الأدوار.
- WebAuthn challenge/verification.
- Attendance verification.
- Payroll calculation/posting.
- Bulk notifications.
- Export sensitive data.
- Finalizing KPI.
- Break-glass access.
- Scheduled escalations/backups.

### الأسرار

- `.env.example` placeholders فقط.
- Secrets في منصة النشر/Supabase secrets.
- Secret scanning في CI.
- Rotation runbook.
- لا تطبع JWT/OTP/password/private URLs.

### التخزين

Buckets خاصة:

- `employee-documents`
- `avatars`
- `attendance-selfies` إن فُعلت
- `complaint-evidence`
- `recruitment-cvs`
- `generated-reports`

استخدم مسارات ownership منظمة، وسياسات Storage، وروابط موقعة قصيرة العمر، وفحص نوع/حجم الملف، ومنع executable content.

### حماية إضافية

- MFA للأدوار الحساسة.
- Rate limiting.
- Replay protection.
- Idempotency.
- Security headers/CSP للويب.
- Dependency and SAST scanning.
- CSV injection prevention.
- PII masking.
- Audit access to sensitive records.
- Session revocation after privilege/termination changes.

---

## 13. الخصوصية والاحتفاظ

أنشئ `docs/DATA_CLASSIFICATION_AND_RETENTION.md` ويشمل:

- تصنيف كل نوع بيانات.
- سبب الجمع والغرض.
- من يراه.
- مدة الاحتفاظ.
- الحذف/الإخفاء/الأرشفة.
- Legal hold.
- GPS/selfie/video policy.
- Complaint/health/payroll restrictions.
- Export and correction process.

لا تحدد نسبًا أو مددًا قانونية من الذاكرة؛ اجعلها إعدادات Draft تحتاج اعتماد Legal/HR، ثم سجّل تاريخ السريان.

---

## 14. الإشعارات

أنشئ Notification Matrix تحدد:

- Event.
- Recipient rule.
- Channel: in-app/push/email/SMS إن فُعل.
- Priority.
- Template AR/EN.
- Deep link.
- Quiet hours.
- Retry.
- Dedupe.
- Sensitive data rule.

أحداث أساسية:

- Request submitted/approved/rejected/returned/escalated.
- Missing attendance/reminder.
- Attendance risk review.
- Leave balance/expiry.
- Document/contract/certificate expiry.
- KPI stage/open/overdue/finalized.
- Decision requiring acknowledgement.
- Onboarding/probation task.
- Asset return.
- Helpdesk SLA.
- Offboarding task.
- Payroll payslip only when enabled.

الإشعار داخل DB هو المصدر؛ Push قناة توصيل إضافية وليست المصدر الوحيد.

---

## 15. التقارير

أنشئ Report Catalog مع permission لكل تقرير:

- Employee master/headcount.
- Organization/position vacancies.
- Attendance daily/monthly.
- Late/absence/overtime.
- Leave balances and utilization.
- Request SLA and bottlenecks.
- KPI progress/results/distribution.
- Recruitment funnel/time-to-hire.
- Onboarding/probation.
- Training/skills/cost.
- Contract/document expiry.
- Assets/custody.
- Complaints/cases with restricted output.
- Turnover/offboarding.
- Payroll/cost reports when enabled.
- Audit/security.
- Executive dashboard.

متطلبات التصدير:

- PDF RTL صحيح.
- CSV/XLSX محمي من formula injection.
- Pagination/streaming للبيانات الكبيرة.
- Watermark وAudit للتقارير الحساسة.
- Scheduled reports عند الحاجة.

---

## 16. Offline ومزامنة البيانات

- العمليات الحساسة مثل الحضور النهائي والموافقة وتغيير الصلاحيات والرواتب تحتاج اتصالًا وتحققًا خادميًا.
- يسمح Offline بـread cache غير حساس وDrafts فقط.
- كل Draft يحمل local id وtimestamp وحالة sync.
- عند التعارض، لا overwrite صامت؛ اعرض resolution واضحًا.
- Cache encrypted إذا احتوى بيانات شخصية.
- Logout/termination يمسح الكاش الحساس.

---

## 17. الأداء والقابلية للتوسع

ضع Budgets قابلة للقياس:

- Web initial route مع code splitting.
- P95 API latency goals موثقة حسب البيئة.
- لا استعلامات unbounded.
- Pagination/cursor.
- Indexes للاستعلامات وRLS.
- عدم تحميل ملفات الموظفين جميعًا في الذاكرة.
- Thumbnails للصور.
- Background jobs للعمليات الثقيلة.
- Load test على Staging.
- Query plans للاستعلامات الحرجة.
- Bundle and app size monitoring.

لا تختر Microservices. استخدم Modular Monolith وحدود واضحة، مع Outbox/Jobs عند الحاجة.

---

## 18. Observability والتشغيل

- Structured logs بلا PII/secrets.
- Correlation IDs.
- Error tracking للموبايل والويب والFunctions.
- Metrics: auth failures, API latency, job failures, notification delivery, attendance failures, SLA.
- Alert thresholds.
- Health dashboard.
- Incident runbook.
- Backup policy وrestore drill.
- RPO/RTO محددان ومعتمدان.
- Audit for production admin actions.
- Status page أو internal health view بلا أسرار.

---

## 19. الاختبارات الإلزامية

### Supabase/Database

- Migration up from empty.
- Migration against staging snapshot.
- pgTAP/RLS tests لكل role/action.
- Constraints/triggers/functions.
- SECURITY DEFINER search_path checks.
- No exposed table without RLS.
- Performance indexes.

### Edge Functions

- Auth/JWT/role/ownership.
- Input validation.
- Rate limit/idempotency.
- Success/failure/retry.
- No secret leakage.

### Flutter

- Unit tests للDomain.
- Provider/state tests.
- Widget tests.
- Golden tests لـRTL/Light/Dark/text scaling.
- Integration tests login/attendance/request/KPI.
- Device tests Android حقيقي للكاميرا/GPS/Push/Passkey.
- iOS tests عند تفعيل iOS.

### React

- Unit/component tests.
- Form validation.
- Permission rendering.
- Playwright E2E لكل دور.
- Keyboard/focus/a11y tests.
- Responsive visual tests.

### Security/Quality

- Secret scan.
- Dependency audit.
- SAST/lint/typecheck.
- CSP/headers.
- Upload abuse.
- CSV injection.
- Authorization negative tests.
- Session revocation.
- Release signature verification.

### سيناريوهات قبول أساسية

نفّذ أيضًا جميع السيناريوهات الموجودة في `docs/11_ACCEPTANCE_SCENARIOS.md`، ولا تعتبر القائمة التالية بديلًا عنها.

1. HR ينشئ موظفًا بدعوة آمنة ويعينه لإدارة ومدير.
2. الموظف يدخل ويغير بيانات الدخول المطلوبة.
3. الموظف يسجل حضورًا صحيحًا؛ الخادم يتحقق من الوقت والموقع والهوية حسب السياسة.
4. محاولة حضور مكررة أو خارج السياسة تُرفض وتُسجل.
5. الموظف يقدم إجازة؛ الرصيد يُحجز ومسار الموافقة يعمل.
6. المدير يرى فريقه فقط ولا يستطيع رؤية موظف خارج نطاقه عبر API مباشر.
7. HR لا يرى أسرار النظام ولا الرواتب دون صلاحية.
8. دورة KPI تمر بكل المراحل ولا تكشف تعليقات ممنوعة.
9. قرار إداري يصل للمستهدفين ويسجل وقت الاطلاع.
10. شكوى سرية لا يراها غير الأطراف المصرح بها.
11. إنهاء موظف يلغي جلساته ويبدأ Clearance.
12. Backup restore drill يعيد بيئة اختبار بنجاح.

---

## 20. CI/CD والبيئات

أنشئ:

- `dev` محلي.
- `staging` مستقل.
- `production` مستقل.

Pipeline يجب أن ينفذ:

1. Format/lint/typecheck.
2. Unit tests.
3. Database/RLS tests.
4. Edge tests.
5. React build/E2E subset.
6. Flutter analyze/test/build smoke.
7. Secret/dependency/security scans.
8. Migration preview على Staging/branch.
9. Artifact version/signature checks.
10. Manual approval للإنتاج.

Version واحد موحد عبر Web/Flutter/DB release metadata. استخدم SemVer + build number + commit hash، وولّد changelog.

لا تنشر من جهاز مطور باستخدام أوامر يدوية كمسار طبيعي.

---

## 21. ترحيل البيانات من القديم

لا تربط V2 مباشرة بجداول القديم دون طبقة Migration.

نفذ:

1. Inventory لكل جدول وحقل.
2. Data profiling.
3. Mapping old->new.
4. Normalize phones/names/statuses/roles.
5. Duplicate detection.
6. Orphan detection.
7. Attachment mapping.
8. Dry runs.
9. Reconciliation counts and totals.
10. User acceptance on staging.
11. Parallel run.
12. Cutover window.
13. Read-only old system.
14. Rollback plan.
15. Signed migration report.

لا تنقل demo users أو secrets أو session tokens أو broken local cache.

---

## 22. مراحل التنفيذ

### Phase 0 — Secure Reset

- Repo جديد.
- Secret rotation checklist.
- Environments.
- Architecture/requirements extraction.
- No production changes unless authorized.

### Phase 1 — Foundation

- Monorepo.
- CI/CD.
- Design tokens.
- Flutter/React shells.
- Supabase local/staging.
- Auth, Permission Catalog, Role Builder, scopes, access reviews, audit.

### Phase 2 — First Vertical Slice

نفذ End-to-End:

- Organization.
- Employee Creation Wizard: profile + manager + role + login + photo + shift + invite.
- Employee import dry run.
- Employee creation/invite.
- Login.
- Basic attendance.
- Monthly attendance.
- Leave request + manager/HR approval.
- Notifications.

لا تنتقل قبل نجاح RLS/E2E/device QA الأساسي.

### Phase 3 — Core HR

- Advanced shifts/leave/workflow.
- Operations task center and shift handover.
- Live Location Request with privacy/retention.
- Missions/permits/convoys.
- Documents.
- Manager self-service.
- Reports.

### Phase 4 — KPI/Governance

- KPI workflow.
- Decisions/acknowledgements.
- Dispute Resolution Committee: triage, formation, sessions, minutes, signatures, decisions, appeals.
- Complaints/disputes/discipline.
- Executive dashboards.

### Phase 5 — Lifecycle

- Recruitment.
- Onboarding/probation.
- Training.
- Assets.
- Offboarding/helpdesk.

### Phase 6 — Payroll optional

لا تبدأ إلا بعد اعتماد مواصفة مالية وقانونية منفصلة، ثم نفذها كوحدة كاملة بلا واجهات وهمية.

### Phase 7 — Migration/Release

- Dry runs.
- Parallel run.
- Production security review.
- Signed builds.
- Monitoring/backups.
- Cutover.

---

## 23. بروتوكول عملك كوكيل AI

في كل مرحلة:

1. افحص الوضع الحالي.
2. اكتب/حدّث خطة المرحلة.
3. أنشئ tests أو acceptance criteria أولًا للمنطق الحرج.
4. نفذ تغييرات صغيرة مترابطة.
5. شغل كل الفحوصات.
6. أصلح السبب الجذري لكل فشل.
7. لا تخفِ فشلًا.
8. حدّث docs/changelog/decision log.
9. أنشئ تقرير مرحلة يذكر:
   - ما تم.
   - الملفات المعدلة.
   - migrations.
   - tests/results.
   - المخاطر.
   - ما لم يتم ولماذا.
10. لا تنتقل للمرحلة التالية مع P0/P1 مفتوح داخل نطاق المرحلة.

حافظ على:

- مكونات صغيرة ذات مسؤولية واحدة.
- Domain logic خارج UI.
- Validation مشتركة وعقود typed.
- Naming ثابت.
- Error handling مركزي.
- لا duplication بين Flutter/Web في قواعد الأعمال؛ المصدر الخادمي هو الحقيقة.
- Comments تشرح السبب لا الواضح.
- ADR لأي قرار معماري كبير.

---

## 24. Definition of Done

الميزة لا تُعتبر مكتملة إلا إذا:

- Requirements وedge cases موثقة.
- DB migration موجودة ومختبرة.
- RLS واختبارات negative access ناجحة.
- Backend logic خادمي للقرار الحساس.
- Flutter/Web يعملان حسب النطاق.
- Loading/empty/error/offline/no permission موجودة.
- RTL/Light/Dark/Accessibility مختبرة.
- Unit/Integration/E2E ناجحة.
- Audit event موجود.
- لا أسرار أو PII في logs.
- Performance budget ناجح.
- Docs/changelog محدثان.
- QA واقعي تم على جهاز/متصفح مستهدف.
- Artifact Release موقع ومتحقق منه.

---

## 25. مخرجات التسليم النهائي

أنشئ في النهاية:

- Source repository نظيف.
- Flutter Android AAB Release موقع.
- iOS build instructions/archive عند التفعيل.
- React production build/deployment.
- Supabase migrations/functions/tests.
- ERD.
- Data dictionary.
- Permission matrix.
- Permission catalog and role templates.
- Employee creation/account provisioning specification.
- Dispute committee workflow and minute templates.
- Live-location privacy and retention matrix.
- Acceptance scenarios evidence.
- Feature catalog and future roadmap.
- Screen map.
- Notification matrix.
- Report catalog.
- Migration and reconciliation report.
- Security audit report.
- Test report.
- Accessibility report.
- Performance report.
- Release runbook.
- Backup restore evidence.
- Admin/HR/Employee user manuals بالعربية.
- `FINAL_PRODUCTION_READINESS_REPORT.md` مع نسبة جاهزية مبنية على أدلة، لا تقدير دعائي.

الحزمة النهائية لا تحتوي:

- `.env` حقيقي.
- secrets.
- node_modules/build cache/logs.
- debug keys.
- test credentials.
- production database dump غير مشفر.

---

## 26. أمر البدء

ابدأ الآن بالترتيب التالي:

1. افحص جميع الملفات المرفقة ولا تفترض أن التقارير السابقة دقيقة دون مطابقة السورس.
2. أنشئ `CURRENT_SYSTEM_INVENTORY.md` و`REQUIREMENTS_CONFLICTS.md`.
3. أنشئ Product Requirements وDomain Workflows وPermission Matrix وERD Draft.
4. صنّف كل ميزة: Keep / Redesign / Defer / Remove with reason.
5. أنشئ Repo V2 نظيف وFoundation فقط بعد تثبيت الوثائق الأساسية.
6. نفذ First Vertical Slice كاملًا بقاعدة البيانات وRLS وFlutter وReact والاختبارات.
7. استمر مرحلة بمرحلة حتى التسليم، مع عدم تقديم أي شاشة أو ميزة على أنها مكتملة قبل نجاح Definition of Done.

**المعيار النهائي:** منصة HR قابلة للاستخدام الحقيقي، آمنة، عربية RTL، بسيطة بصريًا، موثقة، مختبرة، قابلة للنشر والتوسع، ولا تحمل أي طبقة أو سر أو توقيع Debug أو منطق ثقة بالعميل من النظام القديم.

---

# ملحق V4 — التحول إلى ERP إداري متكامل ومحور تواصل وقرارات وتحليلات

> هذا الملحق جزء إلزامي من المواصفة، ويكمّل جميع البنود السابقة ولا يلغيها. عند التعارض تُطبّق القاعدة الأكثر أمانًا والأوضح في حماية البيانات والصلاحيات.

## 27. الرؤية النهائية للمنتج

أنشئ **Ahla Shabab HR & Administration ERP V2** كمنصة إدارية مؤسسية حديثة تتمحور حول دورة حياة الموظف الكاملة، ولا تقتصر على الحضور والإجازات. يجب أن تجمع في منتج واحد مترابط:

- إدارة رأس المال البشري ودورة حياة الموظف.
- التشغيل والمهام والورديات والعمل الميداني.
- التواصل الداخلي والأخبار والقرارات المؤسسية.
- اللجان ومحاضر الاجتماعات وحل المشكلات والخلافات.
- التصويت والاستطلاعات وقياس التفاعل.
- الأداء وKPI ومسارات الاعتماد.
- التتبع الميداني المنضبط والموقع والفيديو عند الطلب.
- التقارير اليومية والأسبوعية والشهرية المجدولة.
- التحليلات والرسوم البيانية ولوحات القيادة.
- المستندات والمراسلات والتوقيعات وسجل التدقيق.

يجب أن تعمل المنصة كـ **نظام تشغيل إداري للمؤسسة** وليست مجموعة صفحات منفصلة. كل حدث مهم يجب أن ينعكس بصورة مترابطة في الملف الوظيفي، والإشعارات، والتقارير، وسجل التدقيق، والصلاحيات.

## 28. القناة الرسمية للأخبار والقرارات — Official Broadcast Feed

> **تبسيط V6 ملزم:** لا تنفّذ Chat داخليًا عامًا، ولا Direct Messages، ولا قنوات فرق، ولا Threads أو محادثات جماعية في الإصدار الأساسي. الهدف هو تقليل الوقت والتعقيد وإنشاء قناة رسمية أحادية الاتجاه للأخبار والقرارات والتنبيهات المؤسسية. يمكن إضافة المحادثات مستقبلًا كوحدة مستقلة بعد نجاح النواة.

### 28.1 المرسلون المسموح لهم

- المدير التنفيذي.
- السكرتير التنفيذي/الأدمن الرئيسي.
- HR ضمن نطاق أخبار وسياسات الموارد البشرية.
- أي ناشر آخر يحتاج صلاحية صريحة مؤقتة أو دائمة واعتمادًا مناسبًا.

### 28.2 مستويات المحتوى والسلطة

1. **خبر مؤسسي:** يكتبه وينشره المخولون.
2. **إعلان HR:** ينشره HR أو السكرتير التنفيذي.
3. **قرار إداري:** يُعده السكرتير التنفيذي/الأدمن أو HR حسب الموضوع، ويحتاج اعتماد الجهة صاحبة الصلاحية.
4. **توجيه تنفيذي:** يصدر أو يعتمد من المدير التنفيذي فقط.
5. **تنبيه عاجل:** يصدر من المدير التنفيذي أو الأدمن الرئيسي وفق سياسة الطوارئ.
6. **سياسة محدثة:** تمر بمراجعة واعتماد وإقرار اطلاع.

لا يجوز أن يظهر قرار أعده السكرتير التنفيذي وكأنه صدر منه إذا كان اعتماده للمدير التنفيذي؛ خزّن دائمًا `prepared_by`, `reviewed_by`, `approved_by`, `published_by`.

### 28.3 خصائص القناة

- Feed رسمي مرتب زمنيًا مع تثبيت العناصر المهمة.
- استهداف الجميع أو إدارة/فرع/دور/فريق/موظفين محددين.
- مسودة، مراجعة، إرسال للتنفيذي، اعتماد، جدولة، نشر، سريان، أرشفة، إلغاء، استبدال.
- صورة غلاف، PDF، مستندات وروابط آمنة.
- إشعار داخل التطبيق وPush مع Deep Link.
- زر «تم الاطلاع» وحفظ وقت وإصدار المحتوى.
- تذكير تلقائي لمن لم يطّلع.
- بحث وفلترة وأرشيف.
- منع التعديل الصامت بعد النشر؛ استخدم إصدارًا أو تصحيحًا موثقًا.
- التعليقات العامة معطلة افتراضيًا.
- يمكن إرفاق تصويت أو استطلاع منظم بدل النقاش الحر.
- يمكن إرفاق «طلب إجراء» أو مهمة أو موعد نهائي بالقرار.
- لوحة قياس الوصول والقراءة والتنفيذ.

### 28.4 رحلة النشر من اللابتوب إلى هاتف المدير التنفيذي

1. السكرتير التنفيذي/الأدمن الرئيسي ينشئ الخبر أو القرار من React Web.
2. يرفق الملخص والمراجع والأشخاص المتأثرين والمهام والتاريخ المقترح.
3. يرسله كـExecutive Action Packet.
4. يصل Push إلى Executive Workspace داخل تطبيق Flutter الموحد ويفتح العنصر الصحيح عبر Deep Link بعد التحقق من الصلاحية.
5. يراجع المدير النص والمرفقات والتأثير والتصويت إن وجد.
6. يعتمد أو يعدل أو يعيد للسكرتير بتعليق.
7. عند الاعتماد يمكنه النشر من الهاتف فورًا أو جدولة النشر.
8. يتابع المدير والسكرتير نسبة الاطلاع والتنفيذ من لوحتيهما.

### 28.5 الخصوصية والأمان

- لا يظهر محتوى خارج الجمهور المستهدف.
- Push لا يحتوي بيانات شديدة الحساسية؛ يعرض عنوانًا عامًا ويفتح المحتوى بعد المصادقة.
- الروابط والمرفقات الحساسة موقعة قصيرة العمر.
- جميع عمليات الإنشاء والتعديل والإرسال والاعتماد والنشر مسجلة في Audit.
- لا حذف فعلي لقرار رسمي؛ استخدم إلغاء/استبدال مع حفظ التاريخ.

## 29. صفحة الأخبار والقرارات — Newsroom & Decision Center

### 29.1 الصفحة الرئيسية للأخبار

أنشئ Feed عصريًا يعرض:

- خبر رئيسي Hero.
- أحدث الأخبار.
- القرارات الجديدة.
- الإعلانات العاجلة.
- الفعاليات القادمة.
- أخبار الإدارات.
- الترقيات والتعيينات المسموح نشرها.
- إنجازات الفرق.
- السياسات المحدثة.
- المحتوى المثبت.

يدعم Feed التخصيص حسب دور المستخدم وإدارته وفرعه، مع فلتر شامل، بحث، وحالة مقروء/غير مقروء.

### 29.2 نظام إدارة المحتوى الداخلي

- محرر محتوى آمن يدعم RTL.
- مسودة، مراجعة، اعتماد، جدولة، نشر، إيقاف، أرشفة.
- صورة غلاف ومرفقات وروابط.
- تصنيف ووسوم.
- جمهور مستهدف: الجميع، أدوار، إدارات، فروع، فرق، موظفون محددون.
- تاريخ نشر وانتهاء.
- أولوية ودرجة حساسية.
- معاينة للموبايل والويب قبل النشر.
- نسخة محفوظة لكل تعديل.
- لا يمكن تعديل قرار رسمي منشور بصمت؛ ينشأ إصدار جديد أو تصحيح موثق.

### 29.3 القرارات الإدارية الرسمية

كل قرار يجب أن يتضمن:

- رقم قرار فريد وقابل للبحث.
- العنوان والموضوع.
- نص القرار.
- الجهة أو الشخص المصدر.
- تاريخ الإصدار وتاريخ السريان.
- الجمهور المستهدف.
- حالة القرار: مسودة، تحت المراجعة، معتمد، منشور، نافذ، موقوف، ملغى، مستبدل.
- القرار السابق الذي يستبدله إن وجد.
- مرفقات ومراجع.
- الجهة المسؤولة عن التنفيذ.
- موعد تنفيذ أو متابعة.
- هل يتطلب إقرار اطلاع؟
- هل يسمح بالتعليق أو التصويت الاستشاري؟
- توقيع أو اعتماد إلكتروني.
- PDF رسمي ورمز تحقق.

### 29.4 إقرار الاطلاع

- زر واضح باسم «تم الاطلاع».
- حفظ المستخدم ووقت الاطلاع وإصدار القرار الذي قرأه.
- لا يُعتبر الاطلاع موافقة على القرار إلا إذا نص النوع على ذلك بوضوح.
- عرض نسبة الاطلاع والأشخاص المتأخرين للمخولين فقط.
- إرسال تذكيرات تلقائية.
- إمكانية طلب اختبار فهم قصير للسياسات الحساسة.

### 29.5 التعليقات والمناقشة

- السماح بالتعليق حسب نوع الخبر والجمهور.
- التعليقات الرسمية تظهر بالاسم والدور.
- التعليقات السرية أو المجهولة لا تُستخدم إلا في استطلاعات مصممة لهذا الغرض.
- إمكانية تحويل ملاحظة متكررة إلى تذكرة متابعة.
- Moderation وAudit كاملان.

## 30. نظام التصويت والاستطلاع — Voting & Polling

### 30.1 أنواع التصويت

- استطلاع رأي غير ملزم.
- تصويت استشاري على قرار مقترح.
- تصويت لجنة رسمي.
- تصويت اعتماد عند السماح بالحوكمة.
- اختيار خيار واحد.
- اختيار متعدد.
- نعم/لا/امتناع.
- ترتيب تفضيلات.
- تقييم رقمي.
- استطلاع مجهول مع حماية الهوية.
- تصويت مفتوح يظهر فيه اختيار العضو للمخولين.

### 30.2 إعداد التصويت

يحدد المنشئ:

- السؤال والوصف والخيارات.
- المرفقات والقرار المرتبط.
- الناخبون المؤهلون وفق الدور والنطاق وعضوية اللجنة.
- وقت البداية والنهاية.
- النصاب Quorum.
- نسبة النجاح أو قاعدة الحسم.
- السماح بالامتناع.
- سري أو معلن.
- إظهار النتائج لحظيًا أو بعد الإغلاق.
- إمكانية تغيير الصوت قبل الإغلاق أم لا.
- هل التصويت ملزم أو استشاري.
- صاحب اعتماد النتيجة.

### 30.3 النزاهة والأمان

- صوت واحد لكل هوية مؤهلة ما لم يسمح النوع بترتيب أو خيارات متعددة.
- منع التصويت بالنيابة إلا بتفويض رسمي موثق.
- عدم تخزين اختيار الناخب بجانب هويته في التصويت السري بطريقة تسمح بالكشف المباشر.
- إثبات أهلية التصويت دون كشف الاختيار في الوضع السري.
- قفل النتائج بعد الإغلاق.
- حفظ Snapshot لقائمة الناخبين المؤهلين وقت بدء التصويت.
- Audit لعمليات الإنشاء والتعديل والفتح والإغلاق، دون كشف سرية الاختيارات.
- لا يحل التصويت محل الاعتماد القانوني أو الإداري المطلوب إلا إذا كانت سياسة المؤسسة تنص على ذلك.

### 30.4 النتائج

- عدد المؤهلين والمشاركين ونسبة المشاركة.
- الأصوات لكل خيار والنسبة.
- النصاب والنتيجة النهائية.
- حالات غير مكتمل النصاب أو تعادل.
- تصدير تقرير PDF.
- نشر النتيجة في الخبر أو القرار المرتبط حسب الصلاحية.

## 31. مسار تقييم الموظف الإلزامي

### 31.1 المسار الافتراضي

طبّق المسار التالي كقالب افتراضي قابل للضبط دون حذف مراحله من الكود:

```text
الموظف يقيّم نفسه
→ المدير المباشر يراجع ويعتمد أو يعدل مع توضيح السبب
→ السكرتير التنفيذي يراجع ويعيد أو يوصي بالإرسال
→ المدير التنفيذي يعتمد نهائيًا
→ نشر النتيجة للموظف حسب سياسة العرض
```

يمكن إدخال HR أو لجنة Calibration في قالب آخر، لكن المسار أعلاه يجب أن يكون متاحًا وجاهزًا.

### 31.2 حالات التقييم

- DRAFT_SELF.
- SELF_SUBMITTED.
- MANAGER_REVIEW.
- MANAGER_RETURNED.
- MANAGER_APPROVED.
- EXECUTIVE_SECRETARY_REVIEW.
- EXECUTIVE_SECRETARY_RETURNED.
- SENT_TO_EXECUTIVE_DIRECTOR.
- EXECUTIVE_DIRECTOR_RETURNED.
- FINAL_APPROVED.
- EMPLOYEE_ACKNOWLEDGED.
- APPEAL_SUBMITTED.
- CLOSED.

### 31.3 قواعد التعديل

- الموظف يعدل المسودة قبل الإرسال فقط.
- بعد الإرسال لا يعيد فتحها إلا بإرجاع رسمي.
- المدير يمكنه تعديل درجات مرحلته مع تعليق إلزامي عند اختلاف كبير عن تقييم الموظف.
- لا يمحو تعديل المدير تقييم الموظف الأصلي؛ يعرض النظام المقارنة.
- السكرتير التنفيذي يراجع الاتساق والاكتمال ولا ينتحل هوية المدير.
- المدير التنفيذي يعتمد أو يعيد مع سبب.
- كل مرحلة لها SLA وتذكيرات وتصعيد.
- حفظ كل نسخة ودرجة وتعليق ومن عدلها ومتى.
- نتيجة الحضور تُحسب من مصدر الخادم ولا يسمح للمستخدم بكتابتها يدويًا إلا عبر Adjustment موثق.

### 31.4 شاشة المقارنة

يجب عرض:

- تقييم الموظف.
- تقييم المدير.
- الفارق لكل معيار.
- الأدلة والمرفقات.
- نتيجة الحضور.
- التعليقات حسب مستوى الرؤية.
- تاريخ كل مرحلة.
- Chart Radar للمعايير.
- Trend للأشهر السابقة.
- نقاط القوة وفرص التطوير.

### 31.5 الاعتراض

- نافذة زمنية للاعتراض بعد النشر.
- سبب ومرفقات.
- المراجع لا يكون الشخص الوحيد صاحب القرار المتنازع عليه.
- قرار الاعتراض موثق ولا يغير السجل السابق بصمت.

## 32. الموقع المباشر والفيديو والتتبع المنضبط

### 32.1 صلاحية المدير التنفيذي

- أنشئ صلاحية مستقلة `location.request.any_employee` تمنح للمدير التنفيذي فقط افتراضيًا.
- تسمح للمدير التنفيذي بطلب الموقع من أي موظف نشط داخل المؤسسة.
- يمكن تفويض صلاحيات أقل لمدير التشغيل ضمن نطاق إدارته أو فرق التشغيل.
- لا يعني امتلاك الصلاحية فتح موقع الموظف بصورة صامتة أو دائمة.

### 32.2 أنواع الطلب

1. نقطة موقع واحدة الآن.
2. موقع + فيديو تحقق مدته 5 ثوانٍ.
3. جلسة تتبع مؤقتة 5 أو 10 أو 15 أو 30 دقيقة.
4. جلسة مرتبطة بمأمورية أو مهمة حتى وقت انتهائها وبحد أقصى محدد.
5. طلب طوارئ وفق سياسة خاصة مع إشعار واضح للموظف.

### 32.3 دورة الطلب

- المدير يختار الموظف أو مجموعة موظفين.
- يكتب سببًا إلزاميًا ويحدد النوع والمدة.
- ينشأ الطلب بحالة REQUESTED ويرسل Push آمنًا.
- الموظف يرى اسم الطالب والسبب والمدة والبيانات المطلوبة.
- عند التنفيذ يلتقط النظام موقعًا حديثًا، الدقة، الوقت، معرف الجلسة، ومؤشرات سلامة الجهاز المتاحة.
- في نوع الفيديو يسجل فيديوًا حيًا مدته 5 ثوانٍ ثم يرفعه إلى Storage خاص.
- ترسل إحداثيات الموقع ورابطًا موقّعًا قصير العمر للفيديو إلى المستلمين المصرح لهم.
- يبدأ التتبع المؤقت فقط أثناء الجلسة، مع مؤشر واضح دائم على جهاز الموظف.
- تنتهي الجلسة تلقائيًا ولا تستمر في الخلفية بعد انتهائها.

### 32.4 حالات الطلب

- REQUESTED.
- DELIVERED.
- OPENED.
- ACCEPTED أو POLICY_REQUIRED.
- CAPTURING.
- STREAMING.
- COMPLETED.
- EXPIRED.
- DECLINED_WITH_REASON عند السماح.
- PERMISSION_DENIED.
- GPS_UNAVAILABLE.
- CAMERA_UNAVAILABLE.
- UPLOAD_FAILED.
- CANCELLED.
- FLAGGED_FOR_REVIEW.

### 32.5 شاشة التتبع

- خريطة حديثة بها Marker لكل جلسة نشطة.
- اسم وصورة الموظف وحالته ومهمته.
- دقة الموقع ووقت آخر تحديث.
- خط زمني محدود للجلسة، وليس سجلًا دائمًا لكل تحركات الموظف.
- فيديو التحقق مع صلاحية ومدة انتهاء.
- تنبيه عند توقف التحديث أو ضعف الدقة أو محاولة إرسال نقطة قديمة.
- زر إنهاء الطلب.
- سجل بمن فتح الموقع أو الفيديو.

### 32.6 حماية الخصوصية

- لا تتبع سريًا.
- لا تتبع خارج ساعات العمل إلا في مهمة أو طوارئ موثقة.
- لا تخزن مسارات التتبع أكثر من مدة الاحتفاظ المعتمدة.
- حذف الفيديو تلقائيًا بعد المدة المحددة، والافتراضي 24 ساعة ما لم تكن هناك قضية أو Legal Hold.
- لا تضع الإحداثيات أو صورة الفيديو داخل نص الإشعار.
- تشفير النقل والتخزين، وStorage خاص، وروابط موقعة قصيرة.
- جميع الطلبات والمشاهدات والتنزيلات مسجلة في Audit.

## 33. التقارير المجدولة اليومية والأسبوعية والشهرية

### 33.1 المستلمون

- المدير التنفيذي يستلم تقريرًا مؤسسيًا شاملًا.
- كل مدير يستلم تقريرًا عن الموظفين الواقعين ضمن نطاقه الإداري فقط.
- مدير التشغيل يستلم تقرير التشغيل والمهام والورديات والموقع ضمن نطاقه.
- HR يستلم تقارير HR المصرح بها.
- الموظف يستلم ملخصه الشخصي عند تفعيل ذلك.

### 33.2 التقرير اليومي للمدير التنفيذي

يشمل على الأقل:

- عدد الموظفين المجدولين والحاضرين والمتأخرين والغائبين.
- من لم يسجل حضورًا أو انصرافًا.
- حالات خارج النطاق والمراجعات الأمنية.
- الإجازات والمأموريات والتصاريح اليوم.
- الطلبات المتأخرة أو العاجلة.
- المهام والفعاليات الجارية والمتأخرة.
- طلبات الموقع ونتائجها وحالات الفشل.
- القرارات أو الأخبار التي تحتاج إجراء.
- القضايا الجديدة والتصعيدات دون كشف تفاصيل غير مصرح بها.
- تقدم KPI الجاري.
- تنبيهات جودة البيانات والأمان.

### 33.3 التقرير الأسبوعي

- اتجاه الحضور والتأخير والغياب.
- مقارنة الإدارات والفروع.
- إجمالي ساعات العمل والعمل الإضافي.
- الطلبات المقدمة والمعتمدة والمرفوضة ومتوسط مدة الاعتماد.
- أداء الفرق والمهام.
- تقارير الموقع والتغطية الميدانية.
- الأخبار والقرارات ونسب الاطلاع والتصويت.
- القضايا المفتوحة والمغلقة وSLA.
- التقييمات المتأخرة.
- العقود والمستندات التي تقترب من الانتهاء.

### 33.4 التقرير الشهري

- كشف حضور شهري كامل.
- KPI ونتائج الأداء ومسار الاعتماد.
- ملخص القوى العاملة والتعيينات والنقل وإنهاء الخدمة.
- أرصدة الإجازات.
- التدريب والمهارات.
- المخالفات والمكافآت وفق الصلاحية.
- تحليل الطلبات وSLA.
- تحليل التواصل والتفاعل دون تحويله إلى مراقبة غير ضرورية.
- جودة البيانات.
- مؤشرات المخاطر والتوصيات البشرية.

### 33.5 محرك الجدولة والتوصيل

- جدولة حسب `Africa/Cairo` مع دعم تغيير المنطقة الزمنية من الإعدادات.
- إنشاء التقرير في Queue خلفية مع Idempotency.
- إرسال داخل النظام، والبريد الإلكتروني، وPDF آمن، مع روابط منتهية الصلاحية.
- عدم إرفاق ملفات شديدة الحساسية بالبريد المفتوح؛ استخدم رابطًا مصادقًا.
- سجل نجاح وفشل وإعادة محاولة.
- منع التكرار عند إعادة تشغيل Job.
- إمكانية إيقاف تقرير أو تعديل مستلميه وقوالبه من لوحة الإدارة.
- صفحة Report Inbox داخل النظام.

## 34. الرسوم البيانية والتحليلات الكثيفة والمنضبطة

### 34.1 المبدأ

يجب أن يكون النظام بصريًا وغنيًا بالبيانات، لكن لا تضع Chart لمجرد الزينة. كل Chart يجب أن يجيب عن سؤال إداري واضح ويتيح Drill-down إلى البيانات المصدرية.

### 34.2 أنواع الرسوم المطلوبة

- KPI Cards مع مقارنة بالفترة السابقة.
- Sparklines داخل البطاقات.
- Line وArea للاتجاهات الزمنية.
- Grouped وStacked Bar للمقارنات.
- Donut/Pie للاستخدام المحدود عندما تكون الفئات قليلة.
- Calendar Heatmap للحضور والتأخير.
- Heatmap للإدارات والأيام والساعات.
- Radar لتقييم المهارات وKPI.
- Funnel لمسار التوظيف والموافقات.
- Gauge أو Progress Ring للنسب المستهدفة.
- Timeline وGantt للمهام وOnboarding.
- Map Layers للحضور والمهمات والموقع المباشر.
- Cohort للاحتفاظ أو فترة التجربة.
- Scatter لتحليل الأداء مقابل الحضور دون اتخاذ قرار آلي.
- Distribution/Histogram للدرجات وساعات العمل.
- Org Chart تفاعلي للهيكل.
- Sankey اختياري لمسارات النقل أو الطلبات إذا كانت البيانات تبرر ذلك.

### 34.3 لوحات القيادة

#### لوحة المدير التنفيذي

- Headcount.
- الحضور اللحظي.
- الالتزام الشهري.
- حالة الطلبات والموافقات.
- تقدم KPI.
- العمليات والمهام.
- خريطة المواقع النشطة.
- القضايا والتصعيدات.
- الأخبار والقرارات ونسبة الاطلاع والتصويت.
- جودة البيانات والمخاطر.

#### لوحة المدير

- فريقي الآن.
- حضور الفريق.
- المهام المتأخرة.
- الطلبات المنتظرة.
- تقدم تقييم الفريق.
- الإجازات القادمة.
- تحذيرات العقود أو التدريب المسموح بها.

#### لوحة HR

- قوة العمل.
- التوظيف.
- Onboarding/Probation.
- Attendance/Leave.
- KPI cycles.
- Training/Skills.
- Documents/Contracts.
- Offboarding.
- Data Quality.

### 34.4 معايير Chart UX

- فلاتر موحدة للتاريخ والفرع والإدارة والفريق.
- Drill-down وDrill-through.
- Tooltip واضح بالعربية.
- تعريف المعادلة ومصدر الرقم.
- Empty وLoading وError states.
- تصدير صورة وPDF وCSV حسب الصلاحية.
- دعم Light/Dark تلقائيًا.
- ألوان ثابتة للحالات: نجاح، تحذير، خطر، معلومات، محايد.
- لا يعتمد المعنى على اللون فقط؛ استخدم نصًا ورمزًا ونمطًا.
- دعم قارئ الشاشة ونسخة جدولية من البيانات.

## 35. الوصف البصري الدقيق المستخرج من التصميمات

### 35.1 الهوية العامة

التصميمات المرسلة توضح هوية عربية تقنية حديثة تتمحور حول شعار «أحلى شباب»، مع إطار علوي مستوحى من القوس الإسلامي/المحراب، وخطوط ضوئية زرقاء تعطي النظام شخصية مميزة. يجب تحويل هذا التصور إلى Design System حقيقي، لا نسخ الصور حرفيًا ولا استخدام خلفيات مولدة كنصوص غير قابلة للتفاعل.

### 35.2 الثيم الداكن

- خلفية أساسية كحلية شديدة العمق تميل إلى الأسود الأزرق.
- طبقات Surface كحلية متدرجة بدل الأسود المسطح.
- حدود رفيعة زرقاء شفافة وإضاءة خارجية محسوبة.
- اللون الرئيسي أزرق كهربائي، والثانوي Cyan.
- الأخضر للحالات الناجحة، البرتقالي للتحذير، الأحمر للخطر، البنفسجي للمعلومات الخاصة.
- بطاقات مستديرة تقريبًا 16–24px، بداخلها Header صغير وقيمة كبيرة ووصف أو Trend.
- عناصر Hero تحتوي على صورة المؤسسة أو الخريطة أو رسم بصمة محاط بحلقة ضوئية.
- استخدام القوس العلوي في صفحات الدخول والصفحات الرئيسية، مع تقليل استخدامه في الجداول الكثيفة.
- Bottom Navigation داكن بخمس وجهات أساسية، والوجهة النشطة داخل Halo أزرق مضيء.
- الأزرار الأساسية ممتدة بعرض واضح، بتدرج أزرق/Cyan وإضاءة خفيفة، دون Glows مبالغ فيها.
- الجداول داخل الويب ذات خلفية داكنة، صفوف واضحة، Sticky headers، وحالات على هيئة Chips.

### 35.3 الثيم الفاتح

يأخذ بساطة تطبيق التبرعات وهوية الشعار الأزرق:

- خلفية رمادية مزرقة فاتحة جدًا أو أبيض دافئ.
- بطاقات بيضاء نظيفة وظلال ناعمة وحدود رمادية زرقاء.
- أزرق الهوية كلون رئيسي، مع Cyan محدود للعناصر التفاعلية.
- نص أساسي كحلي غامق وليس أسودًا حادًا.
- مساحات بيضاء أوسع وكثافة أقل قليلًا من الوضع الداكن.
- الحفاظ على نفس البنية والأبعاد وحالات الألوان كي لا يتغير معنى الواجهة عند تبديل الثيم.
- منع تكرار مشكلة النص الأبيض على الأبيض أو العناصر منخفضة التباين.

### 35.4 Tokens مرجعية

استخدم Design Tokens دلالية قابلة للتعديل، ولا تضع الألوان مباشرة داخل المكونات. نقطة بداية مقترحة وليست عذرًا لعدم اختبار التباين:

```text
Dark background: #020611
Dark surface-1:  #061127
Dark surface-2:  #0B1B3B
Primary:         #1677FF
Secondary/Cyan:  #00CFF4
Success:         #22C55E
Warning:         #F59E0B
Danger:          #EF4444
Info/Purple:     #8B5CF6

Light background: #F4F7FB
Light surface:    #FFFFFF
Light surface-2:  #EDF3FA
Light text:       #10233F
Light border:     #D8E3F0
Brand blue:       #0B4FA2
```

أنشئ Tokens للألوان والخطوط والمسافات والزوايا والظلال والحركة وارتفاعات العناصر وChart palettes، وشارك التعريف نفسه بين Flutter وTailwind قدر الإمكان.

### 35.5 الخطوط والأيقونات

- خط عربي واضح مثل Cairo أو خط معتمد من الهوية، بأوزان 400/500/600/700.
- دعم أرقام عربية أو لاتينية من إعداد المستخدم دون كسر المحاذاة.
- أيقونات SVG موحدة مثل Lucide أو مجموعة متوافقة، لا Emojis ولا صور أيقونات متراكمة.
- الشعار يظهر بجودة Vector وعلى مساحة تنفس واضحة.

### 35.6 الحركة

- انتقالات سريعة 150–250ms.
- Skeleton loading بدل القفز.
- Micro-interactions للحفظ والاعتماد والتصويت.
- Animation للCharts عند أول عرض فقط، مع منع إعادة التشغيل المستمر.
- احترام `prefers-reduced-motion` وإعداد تقليل الحركة في Flutter.
- منع أي اهتزاز Layout أو إعادة تدفق Loop.

### 35.7 Responsive

#### Flutter

- Mobile-first.
- Bottom navigation بخمس وجهات + More Sheet.
- Tablet يستخدم Navigation Rail أو Split View.
- Safe areas ودعم أحجام النص.
- الأزرار اللمسية لا تقل عن 44–48dp.

#### React Web

- Sidebar RTL قابلة للطي.
- Top bar للبحث والإشعارات والثيم والحساب.
- شبكة Dashboard مرنة 12 columns.
- الجداول تتحول إلى Cards مدروسة على الشاشات الصغيرة، وليس Scroll أفقيًا عشوائيًا.
- دعم 1366px و1920px والشاشات العريضة دون تمدد نصوص غير مقروء.

## 36. إدارة الثيمين Light/Dark

- ثيمان مكتملان متساويا الجودة، وليس Dark مكتمل وLight تجميلي.
- اختيار يدوي: Light، Dark، System.
- حفظ التفضيل على الحساب ومزامنته بين الأجهزة.
- منع Flash of Wrong Theme قبل تحميل الجلسة.
- مكونات Charts وMaps وPDF Preview تتوافق مع الثيم.
- رسائل البريد وPDF تستخدم قالبًا مناسبًا للطباعة ولا تعتمد على الثيم الداكن.
- اختبارات Snapshot وVisual Regression للثيمين على جميع الشاشات الأساسية.
- اختبار تباين WCAG AA لكل Theme.

## 37. وحدات ERP الإدارية الإضافية

### 37.1 الاجتماعات والمحاضر

- جدولة اجتماع وربطه بلجنة أو إدارة.
- جدول أعمال وحضور واعتذارات.
- محضر وبنود قرار.
- تحويل بند إلى مهمة أو قرار.
- توقيعات واعتماد المحضر.
- متابعة Action Items وSLA.

### 37.2 المراسلات الداخلية

- وارد وصادر داخلي.
- رقم مرجعي وتصنيف وسرية.
- إحالة ومتابعة ورد.
- مرفقات ونسخ.
- إقرار استلام.
- أرشفة وبحث.

### 37.3 إدارة القرارات والتنفيذ

- كل قرار يمكن أن ينتج مهام تنفيذ.
- مسؤول وموعد وحالة ونسبة إنجاز.
- تذكير وتصعيد.
- إثبات تنفيذ.
- إغلاق ومراجعة أثر القرار.

### 37.4 مركز المهام المؤسسية

- مهام شخصية وفريق ومشروعات.
- أولوية وSLA واعتماد.
- Subtasks وChecklists.
- تبعيات.
- تعليق ومرفقات.
- Timeline وKanban وCalendar.
- ربط بالحضور والمأمورية والقرار والقضية.

## 38. جداول قاعدة البيانات الجديدة أو الموسعة

أنشئ مخططًا منظمًا بأسماء واضحة، ومنه على الأقل:

### Communications

- `communication_channels`
- `communication_channel_members`
- `communication_messages`
- `communication_message_versions`
- `communication_threads`
- `communication_reactions`
- `communication_read_receipts`
- `communication_reports`
- `communication_pins`

### News/Decisions

- `news_posts`
- `news_post_versions`
- `news_audiences`
- `administrative_decisions`
- `administrative_decision_versions`
- `decision_audiences`
- `decision_acknowledgements`
- `decision_execution_actions`

### Voting

- `polls`
- `poll_options`
- `poll_eligibility_snapshots`
- `poll_ballots`
- `poll_results_snapshots`
- `poll_audit_events`

صمم التصويت السري بحيث تفصل أهلية الناخب عن محتوى الاختيار قدر الإمكان، ولا تسمح باستعلام مباشر يكشف الربط لمدير عادي.

### Location

- `live_location_requests`
- `live_location_sessions`
- `live_location_points`
- `live_location_media`
- `live_location_view_events`
- `live_location_policy_rules`

### Scheduled Reporting

- `report_definitions`
- `report_subscriptions`
- `report_schedules`
- `report_runs`
- `report_artifacts`
- `report_deliveries`
- `report_delivery_attempts`

### Meetings/ERP

- `meetings`
- `meeting_attendees`
- `meeting_agenda_items`
- `meeting_minutes`
- `meeting_action_items`
- `internal_correspondence`
- `correspondence_routing`

كل جدول حساس يحتاج RLS، Indexes، Constraints، timestamps، actor fields، soft-delete عندما يلزم، وسياسة احتفاظ.

## 39. صلاحيات جديدة إلزامية

أضف إلى Permission Catalog على الأقل:

```text
communications.channel.create
communications.channel.manage
communications.channel.moderate
communications.message.post
communications.message.pin
communications.message.delete_limited
communications.search

news.create
news.review
news.publish
news.schedule
news.archive
news.view_analytics

decisions.create
 decisions.review
 decisions.approve
 decisions.publish
 decisions.acknowledgement_view
 decisions.execution_manage

polls.create
polls.configure_eligibility
polls.vote
polls.close
polls.certify_result
polls.view_identified_results
polls.view_aggregate_results

location.request.any_employee
location.request.scope
location.view.active_session
location.view_video
location.cancel_session
location.export_audit

reports.schedule.organization
reports.schedule.scope
reports.view.organization
reports.view.team
reports.manage_templates
reports.view_delivery_logs

meetings.create
meetings.minutes_write
meetings.minutes_approve
meetings.action_items_manage
```

صحح المسافات في أسماء الأكواد عند التنفيذ واجعلها lowercase dotted identifiers ثابتة. لا تستخدم الدور وحده داخل RLS؛ استخدم الصلاحية والنطاق والعلاقة والملكية وحالة السجل.

## 40. اختبارات قبول إضافية إلزامية

أضف السيناريوهات التالية إلى الاختبارات، ولا تعتبر الوحدة مكتملة بدونها:

1. موظف في إدارة A لا يرى قناة سرية لإدارة B.
2. نقل موظف يزيل عضويته المستقبلية من القناة القديمة ويضيف الجديدة مع حفظ التاريخ.
3. تعديل رسالة رسمية يحفظ النسخة السابقة.
4. Push لا يحتوي نص قضية أو إحداثيات حساسة.
5. خبر مجدول لا يظهر قبل وقته.
6. قرار يتطلب اطلاعًا يسجل إصدار القرار ووقت القراءة.
7. تحديث القرار بعد الاطلاع ينشئ إصدارًا ويطلب اطلاعًا جديدًا عند الحاجة.
8. مستخدم غير مؤهل لا يستطيع التصويت حتى باستدعاء API مباشر.
9. الناخب لا يستطيع التصويت مرتين.
10. التصويت السري لا يكشف اختيار الفرد في تقارير المدير.
11. لا تعتمد النتيجة عند عدم اكتمال النصاب.
12. الموظف يحتفظ بتقييمه الأصلي بعد تعديل المدير.
13. المدير لا يراجع موظفًا خارج نطاقه.
14. السكرتير التنفيذي يعيد التقييم بسبب نقص دون تعديل هوية المدير.
15. المدير التنفيذي يعتمد النسخة النهائية فقط.
16. طلب الموقع من المدير التنفيذي يصل لأي موظف نشط.
17. مدير التشغيل لا يطلب موقع موظف خارج نطاقه.
18. فيديو التحقق يقبل مدة 5 ثوانٍ بهامش تقني مضبوط ويرفض ملفًا قديمًا معاد الرفع.
19. جلسة التتبع تنتهي تلقائيًا وتتوقف تحديثاتها.
20. المستخدم يرى مؤشرًا واضحًا أثناء التتبع.
21. رابط الفيديو ينتهي ولا يعمل بعد مدة الصلاحية.
22. كل مشاهدة للفيديو أو الموقع تظهر في Audit.
23. التقرير اليومي للمدير يحتوي فريقه فقط.
24. التقرير المؤسسي لا يصل إلا للمخولين.
25. فشل إرسال التقرير يعاد بدون إنتاج تقرير مكرر.
26. Charts تعرض نفس الأرقام الموجودة في Drill-down.
27. Light Theme ينجح في اختبارات التباين.
28. Dark Theme لا يخفي النصوص أو Focus states.
29. تغيير الثيم لا يغير معنى ألوان الحالات.
30. News feed يعمل في Offline read cache دون نشر أو تصويت مزدوج.
31. نتائج التصويت تظهر في جدول بديل لقارئ الشاشة.
32. القرار الملغى لا يظهر كنافذ في التقارير.
33. مهمة ناتجة عن قرار تحتفظ برابط مرجعي إلى القرار.
34. محضر الاجتماع المعتمد لا يعدل مباشرة.
35. موظف منتهي الخدمة يفقد وصول القنوات والجلسات فورًا وفق السياسة.

## 41. Definition of Done لهذه الإضافات

لا تعتبر أي وحدة من هذا الملحق مكتملة إلا عند وجود:

- Domain model موثق.
- جداول ومهاجرات قابلة للإعادة والاختبار.
- RLS واختبارات سلبية وإيجابية.
- Edge Functions أو RPCs للعمليات الحساسة.
- Flutter UI وReact UI حسب الأدوار.
- Light/Dark كاملان.
- Loading/Empty/Error/Offline states.
- Audit وRetention.
- Notifications.
- Analytics وCharts عند الحاجة.
- اختبارات Unit/Integration/E2E/Visual/Accessibility.
- وثيقة تشغيل ومراقبة واسترجاع.
- بيانات Seed غير حساسة للاختبار فقط.
- إثبات Build فعلي وليس تقريرًا وصفيًا.

## 42. ترتيب التنفيذ المقترح لهذا الملحق

1. Design Tokens والثيمان والمكونات الأساسية.
2. Permission additions وRLS foundation.
3. News + Decisions + Acknowledgements كأول Vertical Slice.
4. Communication Channels والرسائل.
5. Voting/Polls.
6. Evaluation Workflow الجديد.
7. Live Location + 5s video + timed tracking.
8. Scheduled Reports.
9. Executive and Manager dashboards with charts.
10. Meetings, minutes, correspondence, and decision execution.
11. اختبارات أمان وخصوصية وأداء شاملة.

## 43. أمر تنفيذي إضافي للوكيل

لا تنفذ هذه المتطلبات كواجهات شكلية. عند تنفيذ الأخبار مثلًا يجب تنفيذ دورة المسودة والمراجعة والنشر والجمهور والإشعارات والقراءة والتحليلات وRLS. وعند تنفيذ الموقع يجب تنفيذ الطلب والجلسة والفيديو والتخزين الخاص والانتهاء التلقائي وسجل المشاهدة والاحتفاظ. وعند تنفيذ Chart يجب ربطه باستعلام موحد وتوفير Drill-down واختبار تطابق الأرقام.

ابدأ بإنتاج وثائق تصميم تفصيلية لكل Vertical Slice، ثم نفذها من قاعدة البيانات حتى واجهة المستخدم، ولا تنتقل للتي تليها قبل نجاح معايير القبول وDefinition of Done.

---

# ملحق V5 — التحول إلى Ahla Shabab Management OS

> **حالة هذا الملحق:** إلزامي ومكمّل لكل ما سبق. جميع متطلبات V1–V4 باقية وسارية، وعند وجود تعارض تكون الأولوية للأكثر أمانًا، والأكثر قابلية للتكوين، والأشد تحديدًا في V5.
>
> **الهدف النهائي:** بناء منصة تشغيل وإدارة مؤسسية حديثة تجمع HRIS وERP الإداري والتشغيل والتواصل والحوكمة والاستراتيجية والتحليلات داخل نواة واحدة قابلة للتوسع، دون تحويل المشروع إلى كتلة مترابطة أو نسخ المنظومة القديمة.

## 44. إعادة تعريف المنتج

اسم المنتج:

`Ahla Shabab Management OS — HR & Operations Platform`

المنتج ليس تطبيق حضور فقط، ولا لوحة HR فقط. يجب أن يعمل كنظام تشغيل إداري يغطي:

1. دورة حياة الموظف كاملة.
2. الهيكل والأدوار والصلاحيات.
3. الحضور والورديات والموقع الميداني.
4. الطلبات والموافقات والسياسات.
5. الأداء والتقييم والتطوير.
6. التواصل والأخبار والقرارات والتصويت.
7. الاجتماعات والمهام والمشروعات.
8. اللجان والشكاوى والتحقيقات.
9. المتطوعين والقوافل والفعاليات.
10. المعرفة والمستندات والتدريب.
11. التخطيط الاستراتيجي والمخاطر.
12. التقارير والتحليلات والذكاء المساعد.
13. الأمان والخصوصية والتدقيق واستمرارية الأعمال.

### 44.1 المبدأ المعماري الأعلى

ابنِ المنصة حول محركات عامة قابلة للتكوين، ثم ابنِ الوحدات الوظيفية فوقها:

```text
Identity & Access Engine
Organization & People Engine
Policy Engine
Workflow Engine
Form Builder
Communication Engine
Decision & Voting Engine
Task & Project Engine
Committee & Case Engine
Document & Template Engine
Notification Engine
Reporting & Analytics Engine
Search & Knowledge Engine
Audit & Security Engine
Automation & Rules Engine
Integration Engine
```

ممنوع دفن قواعد الأعمال في Widgets أو React Components أو استدعاءات Supabase مباشرة من الصفحات.

## 45. مركز القيادة المؤسسية — Executive Command Center

أنشئ لوحة قيادة مخصصة للمدير التنفيذي تعرض صورة المؤسسة الحالية بصورة لحظية وقابلة للتعمق.

### 45.1 مناطق اللوحة

- ملخص القوى العاملة: نشطون، في إجازة، مأموريات، غياب، وظائف شاغرة.
- الحضور اللحظي: حاضر، متأخر، غائب، خارج النطاق، لم يسجل انصرافًا.
- التغطية التشغيلية لكل موقع ووردية.
- الطلبات العاجلة والمتأخرة عن SLA.
- التقييمات المتوقفة في كل مرحلة.
- القرارات غير المنفذة ونسبة الاطلاع عليها.
- التصويتات المفتوحة والنصاب الحالي.
- جلسات الموقع المباشر النشطة والمتوقفة.
- المشروعات والمبادرات المتأخرة.
- المخاطر والقضايا والحوادث المفتوحة.
- العقود والشهادات والمستندات القريبة من الانتهاء.
- جودة البيانات والصلاحيات الحساسة.
- ملخص الأخبار والتواصل المؤسسي.
- ملخص الأهداف الاستراتيجية ونسبة التنفيذ.

### 45.2 Drill-down

كل رقم أو Chart يجب أن يفتح قائمة السجلات التي كوّنته مع:

- الفلاتر المستخدمة.
- الفترة الزمنية.
- تعريف المؤشر.
- وقت آخر تحديث.
- مصدر البيانات.
- نسخة قاعدة الحساب.

### 45.3 Executive Brief

أنشئ ملخصًا يوميًا قابلًا للمراجعة البشرية يوضح:

- أهم خمسة تغييرات.
- المخاطر التي تحتاج قرارًا.
- الطلبات المتوقفة.
- اتجاهات الحضور والأداء.
- عناصر تحتاج متابعة اليوم.

لا يجوز للذكاء الاصطناعي اختلاق سبب أو نسبة؛ يجب إرفاق روابط البيانات الأصلية.

## 46. الاستراتيجية والأهداف — Strategy, OKR & Execution Tree

### 46.1 هيكل الربط

```text
Vision
→ Strategic Pillars
→ Strategic Objectives
→ Department Objectives
→ Initiatives / Projects
→ Milestones / Tasks
→ Employee Goals
→ KPI / Evidence / Outcome
```

### 46.2 الخصائص

- أهداف سنوية وربع سنوية وشهرية.
- OKR وKPI قابلان للاستخدام معًا.
- مالك ومشاركون لكل هدف.
- وزن وأولوية وحالة.
- خط أساس وقيمة مستهدفة وقيمة فعلية.
- أدلة الإنجاز ومرفقاته.
- مخاطر وعوائق مرتبطة.
- ربط الهدف بقرار أو اجتماع أو مشروع.
- Roll-up تلقائي مضبوط لقيمة الإنجاز.
- منع تجاوز 100% دون سياسة تسمح بذلك.
- سجل تاريخي لكل تعديل على الهدف والقيمة.
- اعتماد نتيجة الهدف قبل دخولها في تقييم الموظف.

### 46.3 شاشات الاستراتيجية

- Strategy Map.
- Objective Tree.
- OKR Board.
- Initiative Portfolio.
- Alignment Matrix.
- Progress Timeline.
- Executive Strategy Dashboard.

## 47. سجل القرارات المؤسسي — Decision Register

طوّر مركز القرارات ليصبح سجل حوكمة كاملًا.

### 47.1 بيانات القرار

- رقم فريد لا يعاد استخدامه.
- العنوان والنص والملخص التنفيذي.
- نوع القرار ودرجة السرية.
- مصدر القرار وصاحب الصلاحية.
- الاجتماع أو القضية أو التصويت المرتبط.
- المشكلة أو الدافع.
- البدائل التي تمت دراستها.
- المشاركون والمستشارون.
- نتيجة التصويت إن وجدت.
- تاريخ الإصدار والسريان والمراجعة والانتهاء.
- الإدارات والفروع والوظائف المتأثرة.
- المهام والإجراءات الناتجة.
- مؤشرات قياس أثر القرار.
- القرار السابق واللاحق والعلاقة بينهما.
- حالة التنفيذ: لم يبدأ، جارٍ، متأخر، مكتمل، متعذر.

### 47.2 مراجعة أثر القرار

عند موعد المراجعة، يطلب النظام:

- هل تحقق الهدف؟
- ما النتائج غير المتوقعة؟
- هل يحتاج تعديلًا أو إلغاءً؟
- ما الأدلة؟
- ما القرارات أو المهام التالية؟

## 48. محرك السياسات ومحاكاة الأثر — Policy Engine & Simulation

### 48.1 إدارة السياسات

كل سياسة يجب أن تحتوي على:

- اسم وكود ونطاق.
- نسخة وتاريخ سريان.
- حالة: مسودة، مراجعة، معتمدة، سارية، منتهية.
- الجمهور المستهدف.
- الأولوية عند التعارض.
- القواعد والاستثناءات.
- صاحب الاعتماد.
- سجل التغييرات.
- إقرار اطلاع إن لزم.

### 48.2 أمثلة السياسات

- الحضور والتأخير والانصراف المبكر.
- الورديات والعمل الليلي.
- الإجازات والترحيل والاستحقاق.
- العمل الإضافي.
- الموقع والسيلفي والفيديو.
- فترة الاختبار.
- العمل الميداني والعمل عن بعد.
- التقييم والتدرج الوظيفي.
- الاحتفاظ بالمستندات والموقع.

### 48.3 المحاكاة قبل التطبيق

أنشئ Sandbox يسمح بتجربة سياسة على Snapshot تاريخية دون تعديل الإنتاج، ويعرض:

- عدد الموظفين المتأثرين.
- مقارنة Before/After.
- أثرها على الحضور والغياب والعمل الإضافي.
- أثرها المالي التقديري عند وجود بيانات مصرح بها.
- الحالات التي ستتغير.
- الاستثناءات والتعارضات.

المحاكاة لا تفعّل السياسة ولا تنشئ خصومات أو قرارات حقيقية.

## 49. مركز المعرفة والسياسات — Knowledge & Policy Center

### 49.1 المحتوى

- اللوائح والسياسات.
- الوصف الوظيفي.
- أدلة العمل.
- إجراءات الطلبات.
- الأسئلة الشائعة.
- التدريب ومقاطع الفيديو.
- القرارات السارية.
- النماذج والخطابات.
- دليل استخدام النظام.

### 49.2 القدرات

- تصنيف ووسوم وملاك محتوى.
- نسخ وإصدارات واعتماد.
- بحث عربي مع دعم الأخطاء الإملائية المعقولة.
- صلاحيات حسب المستخدم والنطاق.
- إقرار الاطلاع.
- اختبارات قصيرة بعد السياسات الحرجة.
- روابط داخلية بين المحتوى والنماذج والطلبات.
- تقارير البحث دون نتيجة لاكتشاف فجوات المعرفة.

### 49.3 مساعد المعرفة

يجوز للمساعد الإجابة فقط من مصادر مصرح بها، مع إظهار:

- اسم الوثيقة.
- رقم النسخة.
- الفقرة أو القسم.
- تاريخ السريان.

## 50. البحث المؤسسي الشامل — Enterprise Search

شريط بحث موحد في Flutter وReact يبحث داخل الكيانات المصرح بها:

- الموظفون والهيكل.
- الأخبار والرسائل والقنوات.
- القرارات والسياسات.
- المستندات.
- المهام والمشروعات.
- الاجتماعات والمحاضر.
- القضايا واللجان.
- الطلبات والتقارير.
- التدريب والمعرفة.

### 50.1 قيود الأمان

- لا يظهر اسم أو Snippet لعنصر غير مصرح به.
- الفهرس يطبق نفس نطاقات RLS.
- الملفات الحساسة تستخدم فهرسة معزولة.
- سجل عمليات البحث الحساسة حسب السياسة.
- منع البحث العام في الرواتب أو القضايا السرية دون صلاحية مستقلة.

## 51. Timeline المؤسسة والموظف

### 51.1 Timeline المؤسسة

يعرض الأحداث المهمة مثل التعيينات والترقيات والقرارات والفعاليات وتغييرات الهيكل والمشروعات والحوادث والسياسات.

### 51.2 Timeline الموظف

يعرض أحداث الموظف 360° مع Field-level permissions:

- تعيين ونقل وترقية.
- مديرون سابقون وحاليون.
- عقود ومستندات.
- حضور وإجازات.
- تقييمات وتدريب.
- عهد ومهام.
- مكافآت وجزاءات مصرح بها.
- Offboarding.

## 52. تجربة «يومي» للموظف — My Day

أنشئ الصفحة الرئيسية للموبايل حول يوم الموظف، وتشمل:

- الوردية ووقت الحضور.
- حالة الحضور وزر الإجراء الصحيح فقط.
- مهام اليوم والأولوية.
- الاجتماعات والمواعيد.
- الطلبات التي تحتاج استكمالًا.
- القرارات والسياسات غير المقروءة.
- الأخبار المهمة.
- تقييم أو Check-in مطلوب.
- رصيد الإجازات المختصر.
- تنبيهات المستندات.
- رسالة أو إعلان من المدير.
- ملخص اليوم عند الانصراف.

## 53. المساعد الشخصي للموظف

المساعد يستطيع:

- عرض الرصيد والحالة من مصدر موثوق.
- فتح نموذج طلب مناسب.
- شرح مراحل الطلب.
- البحث في السياسات.
- تلخيص مهام اليوم.
- الإشارة للبيانات الناقصة.
- توجيه الموظف للقناة أو المسؤول الصحيح.

المساعد لا:

- يعتمد طلبًا.
- يعدل رصيدًا.
- يقدم وعدًا بقبول إجازة.
- يكشف بيانات موظف آخر.

## 54. المسار المهني والمواهب — Career & Talent

- Career Levels وJob Families.
- متطلبات كل درجة ووظيفة.
- Skills Matrix.
- فجوات المهارات.
- خطة تطوير فردية.
- الشهادات وتواريخ الانتهاء.
- Readiness للترقية مع تفسير البيانات.
- Succession Planning للمناصب الحرجة.
- Talent Pools.
- Internal Mobility.
- عدم اعتبار التوصيات الآلية قرار ترقية نهائيًا.

## 55. الرفاهية وبيئة العمل

وحدة اختيارية ذات حماية خصوصية عالية:

- Pulse Surveys.
- قياس عبء العمل.
- طلب دعم سري.
- مبادرات تحسين البيئة.
- اقتراحات الموظفين.
- تنبيه تكرار ساعات العمل الزائدة.

ممنوع استخدام بيانات الصحة النفسية أو طلب الدعم تلقائيًا في التقييم أو الجزاء أو الترقية.

## 56. لوحة المدير «فريقي»

- أعضاء الفريق الحاليون.
- الحضور والتأخير اليومي.
- التغطية والغيابات القادمة.
- الطلبات المنتظرة.
- التقييمات المتوقفة.
- المهام والمشروعات المتأخرة.
- عبء العمل.
- أهداف الفريق.
- اجتماعات 1:1 القادمة.
- مستندات وشهادات قاربت الانتهاء.
- تنبيهات تحتاج تدخلًا.

كل البيانات مقيدة بنطاق الفريق الفعلي وتاريخ العلاقة الإدارية.

## 57. اجتماعات One-to-One

- جدول دوري قابل للتعديل.
- أجندة مشتركة.
- أهداف وإنجازات وعوائق.
- ملاحظات مشتركة وملاحظات خاصة مصرح بها.
- خطة تطوير.
- Actions مع مسؤول وتاريخ.
- Follow-up في الاجتماع التالي.
- تذكيرات وإلغاء وإعادة جدولة.
- قياس اكتمال الاجتماعات دون تحويله إلى أداة تجسس.

## 58. تسليم واستلام الإدارة والتفويض

عند إجازة أو نقل أو مغادرة مدير:

- اختيار بديل وتاريخ سريان.
- نقل الطلبات والمهام المعلقة حسب سياسة.
- تفويض صلاحيات محددة فقط.
- عرض القضايا والاجتماعات والقرارات المفتوحة.
- محضر تسليم واستلام.
- إنهاء التفويض تلقائيًا.
- سجل كامل لما تم نقله ومن اطلع عليه.

## 59. المشروعات والمبادرات — Projects & Initiatives

### 59.1 القدرات

- Portfolio وPrograms وProjects.
- مراحل وMilestones.
- Tasks وSubtasks وChecklists.
- Kanban وList وCalendar وGantt.
- Dependencies.
- Teams وRoles.
- ميزانية اختيارية وصلاحيات مالية مستقلة.
- مخاطر وعوائق وقرارات.
- مستندات واجتماعات.
- Status Reports تلقائية.
- Lessons Learned.
- إغلاق واعتماد النتائج.

### 59.2 الارتباطات

يمكن ربط المشروع بـ:

- هدف استراتيجي.
- قرار.
- فعالية أو قافلة.
- إدارة أو فرع.
- KPI موظف أو فريق.
- مصروفات وعهد.

## 60. الإجراءات الدورية — Recurring Operations

محرك إجراءات ينشئ مهام دورية مثل:

- تقرير الحضور.
- مراجعة العقود.
- فتح دورة KPI.
- جرد العهد.
- مراجعة الصلاحيات.
- النسخ الاحتياطي واختبار الاستعادة.
- اجتماع الإدارة.
- متابعة القرارات.

يدعم المسؤول، البديل، المهلة، التصعيد، الإثبات، والتقرير النهائي.

## 61. إدارة المخاطر المؤسسية — Enterprise Risk Register

- فئات المخاطر: بشرية، تشغيلية، تقنية، مالية، قانونية، سمعة، سلامة.
- الاحتمالية والتأثير والدرجة.
- مالك الخطر.
- الضوابط الحالية.
- خطة المعالجة.
- مؤشرات إنذار مبكر.
- مراجعات دورية.
- حوادث وقضايا مرتبطة.
- Heatmap.
- قبول أو تخفيف أو نقل أو تجنب الخطر مع اعتماد.

## 62. إدارة الحوادث والطوارئ

- بلاغ سريع.
- الموقع والتاريخ.
- الأشخاص المتأثرون.
- صور وفيديو ومرفقات.
- درجة الشدة.
- فريق الاستجابة.
- إجراءات فورية.
- Root Cause Analysis.
- Corrective/Preventive Actions.
- Timeline كامل.
- تقرير إغلاق واعتماد.
- ربطه بالمخاطر والمهام والعهد.

## 63. Town Hall والاجتماعات العامة

- إنشاء حدث داخلي.
- جمهور وحضور.
- رابط بث أو اجتماع.
- أسئلة قبل الاجتماع.
- تصويت على الأسئلة.
- Q&A أثناء الاجتماع.
- تسجيل الحضور.
- نشر التسجيل والمواد.
- مسودة ملخص ومحضر.
- استخراج القرارات والمهام بعد مراجعة بشرية.
- استطلاع رضا.

## 64. صندوق الاقتراحات والابتكار

- اقتراح معلن أو مجهول حسب السياسة.
- تصنيف وفريق مراجعة.
- تصويت استشاري.
- دراسة جدوى مختصرة.
- تحويل لمشروع أو قرار.
- حالة التنفيذ.
- أثر الاقتراح.
- مكافأة أو تقدير اختياري.
- منع كشف هوية الاقتراح السري.

## 65. حملات التواصل الداخلي

- هدف وجمهور وفترة.
- سلسلة أخبار ورسائل وإشعارات.
- محتوى تدريبي أو سياسة.
- Poll أو Quiz.
- قياس الوصول والقراءة والتفاعل.
- مقارنة الإدارات.
- تقرير نتيجة وخطة تحسين.

## 66. قاموس المؤشرات — KPI & Metric Dictionary

كل مؤشر يجب أن يحتوي على:

- كود واسم وتعريف.
- المالك.
- المعادلة.
- الجداول والحقول المصدرية.
- نطاق الزمن.
- الاستثناءات.
- وحدة القياس.
- Refresh cadence.
- قواعد التقريب.
- صلاحية العرض.
- رقم نسخة التعريف.

ممنوع إنشاء مؤشرين بالاسم نفسه ومعادلات مختلفة دون تمييز واضح.

## 67. Data Lineage وExplain This Number

عند عرض مؤشر، وفر شاشة تشرح:

- كيف حُسب.
- أي بيانات دخلت أو استُبعدت.
- أي سياسة ونسخة استخدمت.
- آخر تحديث.
- رابط السجلات المصدرية للمصرح لهم.
- أثر أي تعديل يدوي.

## 68. شاشة «ما الجديد منذ آخر دخول؟»

تعرض حسب الدور:

- تغييرات الموظفين والهيكل.
- الطلبات والمهام الجديدة.
- القرارات والأخبار.
- مؤشرات تغيرت بشكل جوهري.
- عقود أو شهادات ستنتهي.
- قضايا أو مخاطر صُعّدت.
- صلاحيات تغيرت.
- تقارير نُشرت.

## 69. اكتشاف الشذوذ والتنبيهات التحليلية

استخدم Rules أولًا، ويمكن إضافة Models لاحقًا.

أمثلة:

- زيادة مفاجئة في الغياب.
- بصمات متقاربة أو أجهزة غير معتادة.
- طلبات موقع كثيرة على موظف أو إدارة.
- مدير يرفض نسبة شاذة من الطلبات.
- تعديلات كثيرة على بيانات حساسة.
- دورة KPI متوقفة.
- تعارض أرصدة أو حسابات.

كل نتيجة هي **تنبيه للمراجعة** وليست اتهامًا أو قرارًا.

## 70. توقعات القوى العاملة

- احتياج الإدارات.
- تغطية الورديات المستقبلية.
- أثر الإجازات المخططة.
- الوظائف الحرجة والشاغرة.
- العقود القريبة من الانتهاء.
- فجوات المهارات.
- سيناريوهات نمو أو تقليص.

يجب إظهار الافتراضات ومستوى الثقة، والحفاظ على القرار البشري.

## 71. جودة البيانات — Data Quality Center

### 71.1 قواعد الجودة

- حساب بلا موظف أو موظف بلا حساب.
- موظف بلا مدير أو وظيفة أو إدارة.
- مدير لنفسه أو Cycle إداري.
- هاتف أو بريد أو كود مكرر.
- عقد أو هوية أو شهادة منتهية.
- صورة أو مستندات ناقصة.
- دور غير مستخدم أو صلاحية مفرطة.
- مستخدم منتهي الخدمة بجلسة فعالة.
- أرصدة غير منطقية.
- سجلات حضور متعارضة.

### 71.2 جودة ملف الموظف

اعرض Completion Score مع قائمة واضحة لما ينقص، دون إخفاء أهمية كل عنصر.

### 71.3 إصلاح البيانات

- اقتراح إصلاح.
- Preview قبل التطبيق.
- Bulk actions بصلاحيات.
- سجل قبل/بعد.
- إمكانية التراجع حيث تسمح طبيعة البيانات.

## 72. تعدد الفروع والاستعداد لتعدد المؤسسات

التصميم الحالي يجب أن يدعم Organization وBranch وSite وDepartment ككيانات مستقلة.

- فصل البيانات حسب المؤسسة عند تفعيل Multi-tenant مستقبلًا.
- سياسات وثيمات وتقويمات مختلفة.
- مسؤول مركزي ومسؤول محلي.
- تقارير مجمعة ومقارنة.
- منع أي استعلام أو Storage path بلا organization_id عند الحاجة.

لا تفعل Multi-tenancy الكامل في V1 إن لم يكن مطلوبًا، لكن لا تبنِ Schema يمنعه.

## 73. Feature Flags وProgressive Delivery

- تفعيل ميزة حسب البيئة أو المستخدم أو الدور أو الفرع.
- Rollout تدريجي.
- Kill Switch.
- تاريخ بداية ونهاية.
- Audit لكل تغيير.
- عدم استخدام Feature Flag لتجاوز صلاحية أمنية.

## 74. هندسة Flutter الإلزامية

طبقات مقترحة:

```text
presentation/
application/
domain/
data/
platform/
core/
```

القواعد:

- لا استدعاء Supabase من Widget.
- Repositories بعقود واضحة.
- State management موحد.
- Typed failures.
- Navigation guards.
- Secure local storage.
- Offline queue مع Idempotency.
- Integration tests للمسارات الحرجة.
- دعم Light/Dark وRTL والوصول من Design Tokens مشتركة.

## 75. هندسة React الإلزامية

- TypeScript strict.
- Feature-based modules.
- Data access layer مستقلة.
- Query caching مضبوط.
- Form schemas مشتركة.
- Route guards ليست بديلًا لـRLS.
- Tailwind design tokens دون Utility chaos.
- Storybook أو بديل لتوثيق المكونات.
- Visual regression للثيمين والأحجام.
- Charts مع جدول بديل قابل للوصول.

## 76. Observability وSRE

### 76.1 Signals

- Logs منظمة مع correlation_id.
- Metrics.
- Traces.
- Errors وCrashes.
- Slow queries.
- Edge Function latency/failure.
- Push delivery.
- Report generation duration.
- Workflow SLA.
- Offline sync failures.

### 76.2 التشغيل

- Health checks.
- Dashboards.
- Alert routing.
- Runbooks.
- Incident severity.
- SLOs للعمليات الحرجة.
- Postmortem دون لوم.

يجب تنقيح PII من Logs وعدم تسجيل كلمات المرور أو Tokens أو محتوى شديد الحساسية.

## 77. Privacy Center

أنشئ مركز خصوصية يدير:

- أنواع البيانات المجموعة.
- الغرض القانوني والتشغيلي.
- مدة الاحتفاظ.
- من يملك الوصول.
- سجل مشاهدة الموقع والفيديو والقضايا والرواتب.
- حذف أو إخفاء تلقائي بعد المدة.
- Legal Hold.
- طلب تصحيح البيانات.
- تصدير بيانات المستخدم المسموح بها.
- تقارير استخدام صلاحية طلب الموقع.

## 78. Zero-Trust وStep-up Authentication

كل عملية حساسة تتحقق من:

- المستخدم والجلسة.
- الدور والصلاحية والنطاق.
- المؤسسة والفرع.
- العلاقة الإدارية.
- حساسية العملية.
- الجهاز وحالته عند الحاجة.
- MFA أو إعادة إدخال كلمة المرور لعمليات مثل الرواتب والصلاحيات وتصدير البيانات.

لا تعتبر شبكة المكتب أو IP داخليًا دليل ثقة كافيًا.

## 79. إمكانية الوصول — Accessibility

استهدف WCAG 2.2 AA للويب، واختبر Flutter مع TalkBack وVoiceOver.

- Keyboard navigation.
- Focus order وFocus trap.
- Contrast في Light/Dark.
- Text scaling 200%.
- Touch targets.
- Reduced motion.
- Semantics وLabels.
- أخطاء مفهومة.
- عدم الاعتماد على اللون وحده.
- بديل نصي/جدولي للرسوم.

## 80. الذكاء الاصطناعي المساعد — Guardrailed AI

### 80.1 حالات الاستخدام المسموحة

- Executive Brief.
- Natural-language report builder.
- مسودة أخبار وقرارات ومحاضر.
- تلخيص اجتماعات بعد الإذن.
- استخراج مهام وقرارات كمسودة.
- البحث في المعرفة.
- تصنيف تذاكر أو اقتراح Routing.
- كشف جودة البيانات.
- OCR واستخراج حقول المستندات.

### 80.2 ضوابط إلزامية

- احترام RLS والصلاحيات قبل الاسترجاع.
- Citation للبيانات أو الوثائق.
- Human review قبل الحفظ الرسمي.
- إخفاء PII غير الضروري.
- عدم اتخاذ قرار فصل أو جزاء أو راتب أو ترقية أو رفض شكوى.
- سجل لكل استخدام حساس.
- إمكانية تعطيل الميزة حسب المؤسسة أو الوحدة.

## 81. OCR ومعالجة المستندات

- رفع المستند.
- فحص نوع الملف والحجم والبرمجيات الضارة حسب المتاح.
- OCR عربي/إنجليزي.
- استخراج حقول كاقتراح.
- مقارنة ببيانات الموظف.
- إبراز الاختلافات.
- مراجعة بشرية.
- حفظ النسخة الأصلية والبيانات المعتمدة.
- البحث داخل النص المصرح به.

## 82. إدارة المتطوعين والقوافل بصورة موسعة

### 82.1 المتطوعون

- ملف مستقل.
- المهارات والتوفر والمناطق.
- الموافقات والتعهدات.
- المشاركة والساعات.
- التقييم والشهادات.
- التحويل إلى موظف بمسار مستقل.

### 82.2 القوافل والفعاليات

- خطة وموعد وموقع.
- احتياجات الأفراد والمهارات.
- المركبات والسائقون.
- المعدات والعهد.
- Check-in/Check-out.
- مهام ومصروفات.
- حوادث وملاحظات.
- تقرير ما بعد الفعالية.

افصل بيانات المتبرعين والعمل الخيري الحساسة عن HR إلا عبر تكامل محدد الصلاحيات والغرض.

## 83. التكاملات وIntegration Hub

- Webhooks موقعة.
- API keys ذات Scopes وانتهاء.
- Retry وDead-letter queue.
- Idempotency.
- Integration logs.
- Connectors للبريد وSMS وWhatsApp Business والتقويم وأجهزة الحضور والنظام المحاسبي.
- منع Service Role من الوصول إلى طرف خارجي دون Edge Function محكومة.

## 84. قاعدة البيانات الإضافية المقترحة

أضف أو صمم كيانات مكافئة مع أسماء متسقة:

### Strategy

- `strategic_pillars`
- `objectives`
- `key_results`
- `initiatives`
- `objective_links`
- `objective_updates`

### Decisions/Policies

- `decision_register`
- `decision_impacts`
- `decision_reviews`
- `policies`
- `policy_versions`
- `policy_rules`
- `policy_assignments`
- `policy_simulation_runs`
- `policy_simulation_results`

### Knowledge/Search

- `knowledge_spaces`
- `knowledge_articles`
- `knowledge_versions`
- `knowledge_acknowledgements`
- `search_audit_events`

### Projects/Risks/Incidents

- `project_portfolios`
- `projects`
- `project_milestones`
- `project_tasks`
- `project_dependencies`
- `risk_register`
- `risk_reviews`
- `incidents`
- `incident_actions`

### Talent/Meetings

- `career_families`
- `career_levels`
- `skills`
- `employee_skills`
- `development_plans`
- `succession_plans`
- `one_on_one_meetings`
- `one_on_one_actions`
- `delegations`
- `handover_records`

### Analytics/Quality

- `metric_definitions`
- `metric_definition_versions`
- `metric_snapshots`
- `data_quality_rules`
- `data_quality_findings`
- `anomaly_rules`
- `anomaly_findings`
- `executive_briefs`

### Platform

- `feature_flags`
- `feature_flag_targets`
- `privacy_policies`
- `data_access_events`
- `integration_connections`
- `integration_runs`
- `automation_rules`
- `automation_runs`

الجداول ذات البيانات الحساسة يجب أن تمتلك RLS وسياسات Storage واختبارات سلبية وإيجابية.

## 85. صلاحيات V5 الإضافية

أضف صلاحيات دقيقة مثل:

```text
strategy.view
strategy.manage
objectives.create
objectives.update_own
objectives.approve
executive.command_center.view
policy.view
policy.create
policy.review
policy.approve
policy.simulate
policy.activate
knowledge.view
knowledge.publish
knowledge.admin
enterprise_search.use
enterprise_search.sensitive
projects.view
projects.manage
projects.close
risks.view
risks.manage
incidents.report
incidents.manage
incidents.close
data_quality.view
data_quality.fix
data_quality.bulk_fix
metrics.view_definition
metrics.manage_definition
analytics.explain_number
features.manage
privacy.view_access_log
privacy.manage_retention
ai.executive_brief
ai.report_assistant
ai.meeting_assistant
ai.ocr_review
```

كل صلاحية ترتبط بـScope، ولا تُمنح ضمن Wildcard عام للأدوار التشغيلية.

## 86. شاشات V5 الجديدة

### Flutter

- My Day.
- My Career.
- My Skills & Development.
- Knowledge Center.
- Enterprise Search.
- Suggestions.
- One-to-One.
- Project Tasks.
- Incident Report.
- Privacy & My Data.

### React

- Executive Command Center.
- Strategy Map وOKR Board.
- Decision Register.
- Policy Builder وSimulation Lab.
- Knowledge CMS.
- Enterprise Search Admin.
- Project Portfolio وGantt.
- Risk Register وHeatmap.
- Incident Command Center.
- Workforce Forecast.
- Data Quality Center.
- Metric Dictionary وData Lineage.
- Feature Flags.
- Privacy Center.
- Observability Dashboard.
- AI Governance Settings.

## 87. اختبارات قبول V5 الإلزامية

على الأقل، نفّذ الاختبارات التالية بالإضافة إلى كل اختبارات V1–V4:

1. المدير التنفيذي يفتح مؤشرًا ويرى السجلات المصدرية المصرح بها فقط.
2. مدير إدارة لا يرى Command Center العام دون صلاحية.
3. هدف موظف يتدرج إلى هدف الإدارة دون مضاعفة الوزن.
4. تعديل تعريف KPI ينشئ Version ولا يغير التقارير التاريخية.
5. قرار منشور لا يعدل صامتًا؛ ينشئ Amendment أو Version.
6. Policy Simulation لا تغير أي سجل إنتاج.
7. تفعيل سياسة جديدة يحفظ النسخة المستخدمة على العمليات اللاحقة.
8. بحث مستخدم لا يعرض اسم قضية سرية غير مصرح بها.
9. Knowledge Assistant يذكر المصدر والنسخة.
10. My Day يعرض الإجراء الصحيح للحضور حسب الحالة.
11. المساعد لا يعتمد طلبًا أو يكشف بيانات زميل.
12. مدير يرى فريقه حسب العلاقة السارية في التاريخ المطلوب.
13. Delegation تنتهي تلقائيًا ولا تظل الصلاحية فعالة.
14. One-to-One private note لا تظهر للطرف غير المصرح له.
15. مهمة مشروع مرتبطة بهدف تحدث التقدم وفق قاعدة معتمدة فقط.
16. حذف مشروع مرفوض إن كان له سجلات رسمية؛ يستخدم Archive.
17. Risk Heatmap تطابق الدرجات المصدرية.
18. Incident closure يتطلب إغلاق الإجراءات الإلزامية.
19. اقتراح سري لا يكشف هوية صاحبه في الواجهة أو التصدير.
20. Metric Explain يعرض المعادلة والفترة ومصدر البيانات.
21. Data Quality rule تكشف حسابًا بلا موظف.
22. Bulk fix يعرض Preview ويسجل Before/After.
23. Feature Flag لا يمنح صلاحية غير موجودة.
24. Step-up auth مطلوب قبل تصدير بيانات حساسة.
25. Privacy log يسجل فتح فيديو موقع.
26. AI Brief لا يحتوي نسبة بلا مصدر.
27. AI Meeting Assistant يحفظ مسودة فقط قبل الاعتماد.
28. OCR لا يكتب البيانات المستخرجة نهائيًا دون مراجعة.
29. النظام يعمل في Light وDark دون تباين فاشل.
30. كل Chart رئيسي له بديل جدولي قابل للوصول.
31. Feature rollout يمكن إيقافه Kill Switch.
32. Integration retry لا يكرر إنشاء سجل بسبب Idempotency.
33. موظف منتهي الخدمة لا يظهر في اقتراحات إسناد مهمة.
34. سجل البيانات التاريخية لا يتغير عند تغيير مدير الموظف الحالي.
35. اختبارات RLS تمنع cross-organization access عند تفعيل العزل.

## 88. ترتيب التنفيذ النهائي — تجنب Big Bang

### Release 1 — Production Core

- Foundation والأمان والهوية.
- الموظفون والحسابات والهيكل.
- Role Builder وRLS.
- الحضور والورديات والطلبات.
- KPI ومسار الاعتماد.
- الأخبار والقرارات والتواصل.
- لجنة الخلافات.
- الموقع والفيديو والتقارير.
- Light/Dark وAudit وObservability أساسية.

### Release 1.5 — Management Operations

- المهام والمشروعات.
- الاجتماعات والمحاضر.
- Decision Register.
- Knowledge Center.
- HR Helpdesk.
- المتطوعون والقوافل.
- العهد والحوادث والمخاطر الأساسية.

### Release 2 — Full Employee Lifecycle

- ATS والتوظيف.
- Onboarding وProbation.
- العقود والمستندات.
- التدريب والمهارات والمسار المهني.
- Workforce Planning.
- Offboarding.
- Compensation/Payroll بعد اعتماد متخصص.

### Release 3 — Configurable Enterprise

- Policy Builder وSimulation.
- Form/Workflow/Report Builders.
- Strategy وOKR.
- Data Warehouse وMetric Dictionary.
- Integration Hub.
- Multi-organization readiness.
- DR وSRE كاملان.

### Release 4 — Intelligence

- Executive Brief.
- Natural Language Reporting.
- OCR.
- Anomaly Detection.
- Forecasting.
- Knowledge Assistant.

كل Release مقسم إلى Vertical Slices قابلة للاستخدام والاختبار. لا تنشئ عشرات الصفحات غير المربوطة ثم تعلن اكتمال المرحلة.

## 89. بروتوكول تنفيذ V5 للوكيل

1. اقرأ المواصفة كاملة قبل التعديل.
2. أنشئ Requirements Traceability Matrix تربط كل Feature بـ:
   - Requirement ID.
   - Database entities.
   - RLS policies.
   - Backend/Edge Functions.
   - Flutter screens.
   - React screens.
   - Tests.
   - Status.
3. أنشئ Architecture Decision Records للقرارات الكبرى.
4. ابدأ بـFoundation ثم First Vertical Slice.
5. لا تستخدم بيانات Mock كبديل دائم.
6. لا تضع TODO غير موثق داخل المسار الإنتاجي.
7. لا تدّعي أن وظيفة تعمل دون اختبارها.
8. لا تعدل إنتاجًا أو أسرارًا من ملفات قديمة.
9. لا تكسر الهجرة أو التاريخ لتسهيل واجهة جديدة.
10. عند تعذر ميزة بسبب سر أو جهاز أو اعتماد خارجي، نفّذ كل الجزء الممكن، واكتب Blocker دقيقًا واختبارًا قابلًا للتشغيل لاحقًا.

## 90. Definition of Done النهائي للمنصة

لا تعتبر المنصة أو أي وحدة مكتملة إلا عند توفر:

- متطلبات وقواعد عمل موثقة.
- ERD وData Dictionary.
- Migrations قابلة للتكرار على بيئة نظيفة.
- RLS واختبارات وصول إيجابية وسلبية.
- Backend/Edge Functions للعمليات الحساسة.
- Flutter وReact بحالات Loading/Empty/Error/Offline.
- Light/Dark وRTL وAccessibility.
- Audit وSecurity Events.
- Telemetry بلا أسرار أو PII زائدة.
- Unit/Integration/E2E tests.
- Performance checks.
- Backup/restore considerations.
- Documentation وRunbooks.
- Acceptance criteria ناجحة.
- No P0/P1 open داخل نطاق الإصدار.

## 91. أمر البدء النهائي للوكيل

ابدأ بإنشاء مجلد `docs/discovery-v5/` وأضف داخله:

1. `requirements-traceability-matrix.md`
2. `domain-map.md`
3. `role-permission-scope-matrix.md`
4. `employee-lifecycle.md`
5. `workflow-catalog.md`
6. `database-erd.md`
7. `data-dictionary.md`
8. `rls-threat-model.md`
9. `screen-map-flutter.md`
10. `screen-map-react.md`
11. `design-system-tokens.md`
12. `migration-plan.md`
13. `test-strategy.md`
14. `release-roadmap.md`
15. `open-questions-and-assumptions.md`

ثم نفّذ Phase 0 وPhase 1 فقط، وشغّل اختبارات الأساس، وقدّم تقريرًا موثقًا قبل الانتقال لأول Vertical Slice.

**لا تبدأ ببناء كل الشاشات دفعة واحدة. لا تنسخ النظام القديم. لا تختصر المتطلبات. لا تعتبر وجود UI دليلًا على اكتمال الميزة.**


# ملحق V7 الملزم — Unified Flutter Workspaces + Unified React Workspaces + Official Broadcast

> **قاعدة الأولوية:** هذا الملحق هو الأعلى أولوية، ويلغي أي بند سابق يطلب تطبيقًا منفصلًا للمدير التنفيذي أو أكثر من React Web App. المعمارية النهائية: تطبيق Flutter واحد بثلاثة Workspaces، ولوحة React واحدة باثنين من Workspaces، وقناة أخبار وقرارات رسمية دون Chat عام.

## 92. التوزيع النهائي للتطبيقات والـWorkspaces

أنشئ المنتجين الأماميين التاليين فقط، بالإضافة إلى Backend واحد:

### 92.1 تطبيق Flutter موحّد — Mobile Workspaces

يستخدم جميع مستخدمي الهاتف نفس التطبيق ونفس Bundle ID/App ID، مع Workspaces داخلية:

- **Employee Workspace:** الحضور والانصراف، Passkey/GPS/الفيديو عند السياسة، الطلبات، KPI الذاتي، المهام، المستندات، الإشعارات، والسياسات.
- **Manager Workspace:** جميع وظائف الموظف، بالإضافة إلى إدارة الفريق وحضوره وطلباته وتقييماته وتقاريره، وفق النطاق.
- **Executive Workspace:** لا يعرض حضورًا أو بصمة أو موقعًا شخصيًا للمدير التنفيذي؛ يعرض القيادة التنفيذية، الاعتمادات النهائية، التقارير العامة، القرارات، التصعيدات، الخرائط، طلب الموقع والفيديو، والـAction Packets.

يحدد الخادم الـWorkspace المتاح من الصلاحيات والتكليفات، ويظل RLS هو الحماية الفعلية. لا تعتمد على إخفاء القوائم.

### 92.2 لوحة الإدارة المركزية — React Web موحّدة

المستخدم الأساسي لها هو:

- **الأدمن الرئيسي** الذي يجمع صلاحيات السكرتير التنفيذي والإدارة التقنية/البرمجية وفق تكليف المؤسسة.
- HR ضمن صلاحيات الموارد البشرية فقط.
- مسؤولو التشغيل والمالية والتوظيف حسب الصلاحيات.

الأدمن الرئيسي يملك Full Access Business/Technical داخل النظام، لكن يجب تطبيق الآتي:

- حساب شخصي واحد غير مشترك ومحمٍ بـMFA/Passkey.
- فصل منطقي بين وضع الإدارة التشغيلية ووضع الإدارة التقنية، مع Step-up Authentication للعمليات الحساسة.
- لا يجوز انتحال هوية المدير التنفيذي أو نشر قرار باسمه دون `approved_by` حقيقي.
- كل إجراء تقني أو تعديل صلاحية أو بيانات حساسة يسجل السبب وBefore/After.
- دعم Break-glass مؤقت مع تنبيه وتقرير مراجعة.

### 92.3 Backend واحد

- Supabase/PostgreSQL/Auth/RLS/Storage/Edge Functions مشتركة مع فصل الصلاحيات والنطاقات.
- لا تكرر قواعد العمل بين Flutter والويب؛ الخادم مصدر الحقيقة.

## 93. مصفوفة المسؤوليات النهائية

| الوظيفة | Employee/Manager Workspace في Flutter | Executive Workspace في Flutter | React Web Workspaces |
|---|---:|---:|---:|
| إنشاء موظف وحساب ومدير ودور | — | عرض مختصر فقط | نعم |
| Role/Permission Builder | — | — | نعم — الأدمن الرئيسي فقط |
| إعداد السياسات وWorkflow | — | مراجعة/اعتماد عند اللزوم | إعداد كامل |
| إدارة الحضور والتصحيح | ذات/فريق حسب الدور | مراقبة واعتماد حساس | إدارة كاملة |
| طلب موقع أي موظف | نطاق الفريق فقط عند المنح | نعم — المؤسسة كلها | إعداد/تجهيز، أو تنفيذ بصلاحية مستقلة |
| عرض الفيديو 5 ثوانٍ | الموظف يرسله | نعم | وفق صلاحية وتدقيق |
| إعداد قرار | مسودة عند منح الصلاحية | نعم | نعم |
| الاعتماد التنفيذي النهائي | — | نعم | لا يُنسب للأدمن |
| نشر خبر HR | — | نعم | HR/الأدمن |
| التقارير | ذات/فريق | المؤسسة كلها | بناء وجدولة وإرسال |
| KPI | ذات/فريق | اعتماد نهائي | إدارة الدورة وتجهيزها |
| النظام والأسرار والمهاجرات | — | — | الأدمن التقني فقط |

## 94. Executive Dispatch Center — مركز الإرسال للمدير التنفيذي

أنشئ في لوحة الويب مركزًا موحدًا يرسل إلى هاتف المدير التنفيذي:

- قرار للمراجعة أو الاعتماد.
- تقرير يومي/أسبوعي/شهري.
- تقييمات موظفين للاعتماد النهائي.
- طلب حساس.
- محضر لجنة.
- مشكلة أو حادث عاجل.
- خطة أو مشروع أو مخاطرة.
- حزمة موظف Executive Summary.
- تصويت يحتاج فتحًا أو اعتماد نتيجة.

كل **Executive Action Packet** يجب أن يحتوي:

- عنوانًا ونوعًا وأولوية.
- ملخصًا تنفيذيًا قصيرًا.
- من أعده ومن راجعه.
- مصدر البيانات ووقت آخر تحديث.
- المرفقات والرسوم والروابط.
- الأثر المتوقع والأشخاص/الإدارات المتأثرة.
- الإجراء المطلوب من المدير.
- موعدًا نهائيًا وSLA.
- تاريخ النسخ والتغييرات.
- خيارات: اعتماد، رفض، إعادة للتعديل، طلب توضيح، تفويض، تأجيل بموعد.
- توقيع/إعادة مصادقة عند الحساسية.

## 95. التقييم النهائي ومسار الاعتماد

المسار الافتراضي الملزم:

`employee_self → direct_manager_review → executive_secretary_review → executive_director_final → employee_acknowledgement`

- HR يراقب الدورة ويضيف عناصر HR المصرح بها مثل الحضور، ويمكن إدراجه كمرحلة configurable دون أن يلغي المسار المطلوب.
- يحتفظ النظام بدرجة الموظف الأصلية ودرجة المدير وتعديلات السكرتير والدرجة النهائية.
- كل تعديل يحتاج سببًا عند تجاوز Threshold قابل للضبط.
- المدير التنفيذي يعتمد من تطبيق الهاتف.
- يرسل النظام نسخة النتيجة للموظف مع حق الاطلاع والاعتراض وفق السياسة.
- توجد تذكيرات وتصعيدات وتقارير عن التقييمات المتأخرة في كل مرحلة.

## 96. الموقع المباشر والفيديو والتتبع التنفيذي

- المدير التنفيذي يملك افتراضيًا صلاحية `location.request.any_active_employee`.
- يستطيع من هاتفه طلب:
  - موقع فوري.
  - موقع + فيديو حي 5 ثوانٍ.
  - جلسة تتبع 5/10/15/30 دقيقة.
  - تتبع مرتبط بمأمورية أو مهمة حتى نهايتها ضمن حد أقصى وسياسة.
- يجب تحديد سبب الطلب ودرجة الأولوية.
- يظهر للموظف اسم الجهة الطالبة والسبب والمدة، مع مؤشر واضح أثناء التتبع.
- الفيديو يلتقط بعد موافقة واضحة ويضاف له watermark زمني ومعرف طلب، ويُرفع إلى Bucket خاص.
- يمنع استخدام فيديو قديم أو ملف من المعرض كفيديو تحقق إلا إذا كانت السياسة تسمح بوضع Evidence منفصل.
- لا يحتوي Push على الإحداثيات أو الفيديو.
- تنتهي الجلسة تلقائيًا ولا تستمر في الخلفية بعد انتهائها.
- سجّل كل من طلب وشاهد وصدّر الموقع أو الفيديو.
- طبّق سياسة احتفاظ قابلة للضبط، وافتراضيًا حذف فيديو التحقق خلال 24 ساعة ما لم يوجد Legal Hold.
- موقع الموظف ليس دليل إدانة تلقائيًا؛ الحالات غير الطبيعية تنتقل للمراجعة البشرية.

## 97. القناة الرسمية المبسطة

لا تبنِ Slack/Teams داخليًا في V1. نفّذ فقط:

- صفحة أخبار وقرارات رسمية.
- ناشرون: المدير التنفيذي، السكرتير التنفيذي/الأدمن الرئيسي، HR ضمن نطاقه.
- إعداد المحتوى على الويب، واعتماده ونشره من الويب أو تطبيق التنفيذي حسب الصلاحية.
- زر تم الاطلاع، تذكيرات، تقارير قراءة.
- تصويت/استطلاع منظم مرفق عند الحاجة.
- لا تعليقات عامة ولا محادثات مباشرة في الإصدار الأساسي.
- يمكن للمستخدم إرسال تذكرة HR أو اقتراح عبر وحدات منفصلة، وليس عبر Chat.

## 98. تقارير المدير التنفيذي والمديرين

### المدير التنفيذي

يستلم في تطبيقه:

- Daily Executive Brief.
- Weekly Management Review.
- Monthly Organization Report.
- التقارير العاجلة عند تجاوز Threshold.
- تقارير قابلة للضغط للوصول إلى الموظف أو الحدث أو القرار.

### المديرون

- كل مدير يستلم تقرير فريقه فقط عبر تطبيق الموظف/المدير أو البريد/Report Inbox.
- لا يرى مدير موظفين خارج نطاقه حتى لو عرف الرابط أو المعرف.

### السكرتير التنفيذي/الأدمن

- ينشئ القوالب، يحدد الجدولة، يراجع جودة البيانات، ويجهز الحزم التنفيذية.
- يمكنه إعادة إرسال تقرير أو طلب تحديثه دون تعديل الأرقام يدويًا.

## 99. تطويرات قوية إضافية إلزامية أو عالية الأولوية

### 99.1 Mobile Executive Daily Brief

- بطاقة صباحية وبطاقة نهاية اليوم.
- أهم خمسة تنبيهات فقط مع إمكانية فتح التفاصيل.
- مقارنة مع أمس والأسبوع السابق.
- «ما الذي يحتاج قرارك الآن؟».

### 99.2 Secure Batch Approval

- السماح باعتماد مجموعة عناصر متجانسة منخفضة/متوسطة الخطورة.
- منع الاعتماد الجماعي للجزاءات والقضايا والرواتب والتقييمات النهائية إلا بسياسة صريحة.
- عرض عدد العناصر وإجمالي الأثر قبل التأكيد.

### 99.3 Executive Delegation

- تعيين قائم بأعمال المدير التنفيذي لمدة محددة وبصلاحيات محددة.
- انتهاء التفويض تلقائيًا.
- إظهار أن القرار اتخذ بالإنابة.
- عدم السماح بتفويض Break-glass أو إدارة الأسرار.

### 99.4 Voice-to-Draft

- تسجيل ملاحظة صوتية من المدير التنفيذي وتحويلها إلى مسودة قرار أو توجيه أو مهمة.
- لا يتم النشر تلقائيًا؛ يعرض النص للمراجعة ثم يرسله للسكرتير أو ينشره بعد الاعتماد.

### 99.5 Executive Annotation & Return

- المدير يستطيع الكتابة أو الرسم على PDF/Chart Screenshot داخل التطبيق وإعادته كتعليق موثق.
- الأصل لا يتغير؛ يحفظ Annotation كطبقة أو مرفق إصدار.

### 99.6 Decision Implementation Score

- لكل قرار: نسبة قراءة، نسبة بدء التنفيذ، نسبة الإنجاز، المتأخرون، المعوقات، والأثر بعد التنفيذ.
- لا يعتبر القرار ناجحًا لمجرد نشره.

### 99.7 Emergency Operations Mode

- شاشة طوارئ مبسطة للتنبيهات العاجلة، المواقع، الفرق المتاحة، الحوادث، وأرقام الاتصال.
- تفعيلها بصلاحية وسبب ومدة.
- تسجل كل طلبات الموقع الجماعية والإجراءات.

### 99.8 Data Freshness Badges

- اعرض على كل رقم أو خريطة أو تقرير وقت آخر تحديث ومصدره.
- تحذير واضح عند البيانات المتأخرة أو الجزئية.

### 99.9 Mobile Performance Budget

- فتح الصفحة الرئيسية بسرعة على هاتف متوسط واتصال متوسط.
- Lazy loading للخرائط والفيديو والرسوم الثقيلة.
- ضغط ومقاسات متعددة للصور.
- عدم تحميل جميع بيانات المؤسسة دفعة واحدة.

### 99.10 Executive Usability Tests

- اختبارات بيد واحدة.
- أحجام لمس مناسبة.
- عدم دفن الإجراءات الحساسة داخل قوائم عميقة.
- تأكيد قوي وواضح قبل النشر/الرفض/طلب الموقع/التوقيع.
- دعم النص الكبير وإمكانية الوصول.

### 99.11 Separation of Preparation and Approval

- السكرتير التنفيذي يجهز ويصحح وينظم المحتوى.
- المدير التنفيذي يعتمد ما يحتاج سلطته.
- لا تستخدم Impersonation.
- كل شاشة تعرض بوضوح: أعده، راجعه، اعتمده، نشره.

### 99.12 QR الآمن خارج الحضور

- QR للتحقق من المستندات والقرارات ومحاضر اللجان وتسليم العهد.
- **لا تستخدم QR كبصمة حضور**؛ الحضور يظل Passkey/GPS/Server Verification.

## 100. جداول V6 الجديدة أو الموسعة

أضف أو وسّع:

- `executive_action_packets`
- `executive_packet_versions`
- `executive_packet_attachments`
- `executive_packet_actions`
- `executive_delegations`
- `executive_briefs`
- `executive_brief_items`
- `official_feed_items`
- `official_feed_versions`
- `official_feed_audiences`
- `official_feed_acknowledgements`
- `decision_execution_items`
- `decision_execution_updates`
- `location_request_view_events`
- `location_video_access_events`
- `executive_annotations`
- `mobile_device_sessions`
- `data_freshness_snapshots`

كلها بـRLS وAudit واختبارات.

## 101. صلاحيات V6

- `executive.mobile.access`
- `executive.packet.receive`
- `executive.packet.prepare`
- `executive.packet.approve`
- `executive.packet.return`
- `executive.delegate.manage`
- `official_feed.prepare`
- `official_feed.review`
- `official_feed.publish.hr`
- `official_feed.publish.executive`
- `decision.executive.approve`
- `decision.executive.publish`
- `location.request.any_active_employee`
- `location.request.team`
- `location.video.request`
- `location.video.view`
- `location.session.view_live`
- `executive.report.view_all`
- `executive.report.annotate`
- `admin.principal.full_access`
- `admin.technical.manage`
- `admin.business.manage`

لا تجعل `HR` Full Access. لا تمنح Role Slug وحده قرار وصول؛ استخدم Permission + Scope + RLS.

## 102. اختبارات قبول V6 الحرجة

1. يستطيع المدير التنفيذي تنفيذ جميع إجراءاته من الهاتف دون Web.
2. لا تظهر إعدادات Role Builder أو الأسرار في Executive Workspace داخل Flutter.
3. يستطيع الأدمن تجهيز قرار وإرساله للتنفيذي، لكن لا يصبح معتمدًا قبل اعتماد المدير.
4. يظهر في القرار prepared_by وapproved_by بصورة صحيحة.
5. لا يستطيع HR نشر توجيه تنفيذي إلا إذا اعتمده المدير التنفيذي.
6. لا يستطيع مستخدم عادي النشر في القناة الرسمية.
7. لا توجد محادثات مباشرة أو قنوات عامة في V1.
8. يصل Action Packet إلى الهاتف عبر Push وDeep Link.
9. رفض المدير أو إعادته يتطلب سببًا ويسجل Audit.
10. توقيع العملية الحساسة يطلب Re-authentication.
11. طلب الموقع من المدير التنفيذي يصل لأي موظف نشط فقط.
12. موظف منتهي الخدمة لا يقبل طلب موقع جديد.
13. الفيديو مدته 5 ثوانٍ حسب السياسة ويرتبط بطلب واحد.
14. رابط الفيديو ينتهي ولا يعمل لمستخدم غير مصرح.
15. تنتهي جلسة التتبع تلقائيًا ولا تستمر بعدها.
16. يرى المدير التنفيذي تقرير المؤسسة، والمدير العادي يرى فريقه فقط.
17. يعمل مسار KPI من الموظف إلى المدير إلى السكرتير إلى التنفيذي.
18. لا يمحو تعديل المدير تقييم الموظف الأصلي.
19. يستطيع المدير التنفيذي اعتماد KPI نهائيًا من الهاتف.
20. ينشر الخبر/القرار إلى الجمهور المحدد فقط.
21. يحفظ تم الاطلاع إصدار المحتوى ووقت القراءة.
22. لا يسمح بتعديل قرار منشور دون Version/Amendment.
23. يعرض كل Chart وقت آخر تحديث ومصدر البيانات.
24. لا ينفذ Batch Approval لعناصر عالية الخطورة دون سياسة.
25. ينتهي تفويض المدير التنفيذي تلقائيًا في موعده.
26. لا يستطيع القائم بالأعمال إدارة الأسرار أو Break-glass.
27. لا تحتوي Push Notifications على موقع أو بيانات قضية حساسة.
28. يعمل Executive Workspace في Light/Dark وRTL والنص الكبير داخل تطبيق Flutter الموحد.
29. لا يقبل اعتماد حساس Offline.
30. ينجح فصل حساب الأدمن الرئيسي عن هوية المدير التنفيذي دون Impersonation.

## 103. تعديل خارطة التنفيذ

### Release 1 — الأساس والأدوار والمنتجات الثلاثة

- Flutter Employee/Manager.
- Flutter Executive Mobile مستقل.
- React Web Control Center.
- Auth/RBAC/ABAC/RLS/Audit.
- Employee creation and hierarchy.
- Official Feed بدل Chat.
- Executive Dispatch Center.

### Release 2 — العمليات الأساسية

- الحضور والطلبات والورديات.
- KPI workflow الكامل.
- الموقع والفيديو والتتبع.
- القرارات والتصويت وإقرار الاطلاع.
- التقارير المجدولة.
- لجنة الخلافات.

### Release 3 — دورة حياة الموظف

- ATS/Onboarding/Contracts/Training/Offboarding.
- Assets/Helpdesk/Knowledge.
- Workforce Planning.

### Release 4 — الإدارة المؤسسية

- Strategy/OKR/Projects/Risks/Meetings.
- Builders/Simulation/Data Warehouse.
- Payroll بعد اعتماد متخصص.

### Release 5 — الذكاء والتكامل

- AI Brief/OCR/Natural Language Reports/Forecasting/Integrations.

## 104. دمج الملف التفصيلي الجديد

الملف التفصيلي المرفق أدناه مرجع إلزامي لقواعد العمل والجداول ودوال الخادم والأمان ودورة حياة الموظف. عند وجود تعارض:

1. **Flutter + React + Supabase في V6** يتقدم على أي ذكر لـVanilla JS أو Capacitor أو PWA كبنية أساسية.
2. **Executive Workspace داخل تطبيق Flutter الموحد، Mobile-Only تشغيليًا** يتقدم على أي ذكر لتطبيق تنفيذي منفصل أو بوابة تنفيذية Web كمسار عمل يومي.
3. **Official Broadcast Feed** يتقدم على Internal Chat Hub في الإصدار الأساسي.
4. نموذج الأمان الخادمي، Passkey/GPS/RLS، والجداول والوحدات الوظيفية في الملف تبقى متطلبات إلزامية ما لم تعدّل صراحةً في V6.

---

# APPENDIX A — الملف التفصيلي المرسل من المالك

# برومت إعادة بناء نظام "أحلى شباب HR" — من الصفر (ستاك حديث، نفس المميزات)

> **كيف تستخدم هذا الملف:** الصقه كاملاً كـ system/spec prompt لأي وكيل AI أو فريق تطوير. هو مواصفة تنفيذية كاملة لإعادة بناء نظام موارد بشرية عربي (RTL) قائم حالياً على Supabase + Vanilla JS + Capacitor، لكن **بنسخة نظيفة على ستاك حديث** مع الحفاظ على **كل** المميزات والقواعد والبيانات. لا تُسقط أي ميزة، ولا تخترع مميزات غير موجودة هنا.

---

## 0) ملخص تنفيذي

نظام موارد بشرية (HR) عربي-أولاً (RTL, `lang=ar`) لمنشأة واحدة ("مجمع منيل شيحة / أحلى شباب" — جمعية خيرية بموقع جغرافي واحد). يعمل كـ **PWA + تطبيق أصلي (Android/iOS)** عبر أربع بوابات منفصلة، مع باك-إند قائم على Postgres + صلاحيات صف (RLS) + دوال خادمية (RPC) + دوال حافة (edge functions). **جميع القرارات الأمنية خادمية** (لا يُوثَق بأي قرار من العميل): التحقق من الحضور، منح ثقة الأجهزة، تقييم المخاطر، الموافقات، تدوير كلمات المرور — كلها في الخادم عبر RPCs (SECURITY DEFINER) + RLS + edge functions.

**المستخدمون والأدوار:**
- **admin** (`*`) — صلاحية كاملة، الدور الوحيد المعامَل كـ full-access.
- **executive** (تنفيذي) — لوحات، تقارير، خريطة حضور حية، طلب موقع حي، موافقات حساسة، KPI تنفيذي/اعتماد نهائي. **ليس** full-access. يعمل كـ "المدير التنفيذي" لتصعيد إجازات `executive_unpaid`.
- **executive-secretary** (سكرتير تنفيذي) — تقارير تنفيذية، mobile ops، طلب إجراءات حساسة، KPI:manage.
- **hr-manager** (HR) — إدارة موظفين/مستخدمين، حضور، موافقات طلبات، KPI فريق/HR، تدقيق. **مستثنى صراحةً** من صلاحية الأدمن الكاملة في edge functions حتى لو حمل `*` (منع الاستيلاء على الحسابات)؛ يدير فقط الحسابات غير المحمية.
- **manager / direct-manager** (مدير مباشر، operations-manager-1/2) — يعتمد طلبات مرؤوسيه المباشرين، KPI:team، عرض الفريق.
- **employee** (موظف) — نطاق ذاتي فقط: حضور ذاتي، KPI ذاتي، موقع ذاتي، الرد على طلب الموقع الحي.

نموذج الصلاحيات = مصفوفة scopes نصية (`roles.permissions[]`) تُقيَّم بدوال `has_permission` / `has_any_permission`؛ `*` = wildcard. الأدوار المحمية (لا يعدّلها غير الأدمن): `admin, super-admin, executive, executive-director, executive-secretary, hr-manager, technical-lead`.

---

## 1) البوابات الأربع (Portals)

كل بوابة تطبيق منفصل (SPA)، تُكتشف الهوية عبر body class ثم مسار URL. عزل أصلي عبر Android product flavors + iOS bundle IDs منفصلة.

| البوابة | المسار | appId الأصلي | الجمهور |
|--------|--------|--------------|---------|
| **الدخول الجذري** | `/` (index) | — | صفحة دخول موحّدة + توجيه للبوابة حسب الدور |
| **الموظف** | `/employee` | `org.ahlashabab.employee` | الموظف النهائي (موبايل/PWA) |
| **التنفيذي** | `/executive` | `org.ahlashabab.executive` | التنفيذيون (غرفة عمليات، خرائط، تقارير) |
| **HR/Admin** | `/admin` + `admin-login` | `org.ahlashabab.hr` | لوحة التحكم المركزية (HR والإدارة) |

**متطلبات عامة لكل بوابة:**
- SPA بموجّه hash-router (المسار الافتراضي `dashboard`/`home`)، جلسة Supabase-style مع snapshot هوية دائم في تخزين آمن (لا PII خام في localStorage).
- **إقلاع صامد (resilient boot):** استدعِ `me()` حتى 3 مرات مع backoff (1s, 2s)؛ عند الفشل المؤقت مع وجود token → استخدم الـsnapshot المخزّن أو اعرض skeleton واستعادة بعد 4s؛ بدون token والمسار ليس login/register/recovery → اعرض تسجيل الدخول.
- **قفل الدخول (lockout):** بعد 5 محاولات فاشلة → قفل 5 دقائق؛ تدقيق الفشل بمُعرِّف مُجزَّأ (hashed).
- **بوابة عمليات ثانية (ops gateway) اختيارية** للأدمن/التنفيذي: كود ثانٍ يُقارَن constant-time مع `SHA256` في متغير بيئة، مع allow-lists اختيارية (emails/phones).
- Service worker لكل بوابة (كاش `hr-<portal>-<VERSION>`)، صفحة offline، توافق إصدار، تعطيل SW داخل Capacitor.
- توطين عربي RTL كامل، ثيم فاتح/داكن تلقائي، تصميم tokens موحّد.

### 1.أ) بوابة الدخول الجذري
تسجيل دخول موحّد (مُعرِّف = بريد/اسم/هاتف + كلمة مرور)، حل المُعرِّف عبر edge function خصوصية-محمية (`resolve-login-identifier`)، توجيه للبوابة حسب الدور، استعادة كلمة المرور، فحص lockout.

### 1.ب) بوابة الموظف (25 ميزة)
Boot/استعادة جلسة صامدة · تسجيل دخول (هاتف+كلمة مرور) · استعادة كلمة المرور · **الرئيسية (dashboard)** · **مركز الإجراءات/الإشعارات** · **البصمة/الحضور (Punch)** · **مشاركة الموقع الحي** + تنبيه موقع حي عاجل + polling · تذكير الحضور · **الشكاوى/النزاعات** · سجل الحضور · مستنداتي · **تقييم KPI ذاتي** · **الطلبات: إجازة/مهمة/قافلة** · **إذنات الحضور (permits)** · الفريق/الهيكل · **Manager Hub** (للمدير) · **Manager KPI review** · **Committee Hub** (للجان) · الملف الشخصي/الحساب · درج "المزيد" (bottom sheet) · Web push + native FCM · **طابور offline + مزامنة** · تبديل الثيم · حارس المسار/التحكم بالوصول.

### 1.ج) بوابة التنفيذي
غرفة عمليات تنفيذية: قائمة كل الموظفين بحالة اليوم + توفّر GPS، بحث، **طلب موقع حي** لكل موظف، تفاصيل الموظف، **خريطة الحضور الحية** (PRESENT/LATE/ABSENT/no-GPS/out-of-range مع دبابيس ملوّنة تربط بـGoogleMaps)، تقارير PDF تنفيذية، KPI تنفيذي.

### 1.د) بوابة HR/Admin (≈59 ميزة — لوحة التحكم المركزية)
> **كل هذه المميزات إلزامية.** كل واحدة route مستقل داخل SPA.

**الحضور:** لوحة معلومات (4 مقاييس أساسية) · إدارة الموظفين (شبكة مقسّمة 40/صفحة + فلاتر) · ملف الموظف (خريطة آخر موقع، بيانات، تبويبات) · أرشيف الموظف الموحّد · المستخدمون/حسابات الدخول (ربط تلقائي user↔employee بالبريد) · **بصمة الموظف الذاتية (Passkey+GPS)** · **عمليات الحضور** (سجل مُفلتَر، شريط عمليات) · **مراجعة الحضور** (البصمات المرفوضة: اعتماد يدوي/رفض نهائي) · تقويم الحضور (31 يوم) · **كشف الحضور الشهري** · ملخص حضور الفريق (نسبة حضور، late، absent، ساعات) · ساعات العمل الشهرية · التقرير الشهري (PDF مطبوع) · **قواعد الحضور الذكية** (shiftStart/absentAfter/earlyExit/duplicateWindow/endOfDayReport/notifyManager).

**الطلبات والموافقات:** **مركز الطلبات** (موافقات موحّدة: إجازات+مهام+قوافل+إذنات+استثناءات+طلبات موقع) · المهام (Missions) · **الإجازات** (اعتيادية/مرضية/طارئة؛ المرضية تتطلب رفع تقرير طبي) · أرصدة الإجازات وإعداد HR (تعيين المدير التنفيذي + حد الإذنات الشهري) · **الاعتمادات الحساسة** (حذف/تعطيل يتحوّل لطلب موافقة).

**KPI:** **سير عمل تقييم KPI** (self→manager→hr→secretary→executive) · مركز شهر KPI (مراقبة كل مرحلة) · تقرير KPI تنفيذي · **قفل دورة KPI** (بعد يوم 25، قائمة المتأخرين، قفل، تذكيرات) · التقييمات الشهرية (حضور/كفاءة/سلوك، تحرير inline).

**التقارير:** Reports hub + مركز التقارير · **باني تقارير متقدّم** (اختيار حقول، جدول تباين actual vs planned) · تقارير PDF تنفيذية + PDF شهري تلقائي.

**المراقبة والذكاء:** مراقب الإشعارات · مراقب المواقع (جودة GPS: GOOD/LOW_ACCURACY/STALE) · **غرفة عمليات الموبايل التنفيذية** · **خريطة الحضور الحية** · **مركز مخاطر الحضور** (risk score/level + flags) · **مركز الأجهزة الموثوقة** (PUSH_ACTIVE/PASSKEY_ONLY/PENDING_APPROVAL/NO_DEVICE) · **غرفة التحكم/التنبيهات الذكية** (smart audit) · مركز الجودة (readiness score، جودة بيانات الموظف).

**الحوكمة:** **النزاعات** + سير عمل النزاع (لجان) · **القرارات الإدارية** (نشر رسمي، إقرار) · الأدوار + **مصفوفة الصلاحيات** · **تشخيص الوصول للمسارات** (self-service: لماذا مسموح/ممنوع) · **خزنة كلمات المرور** (تقني/تنفيذي فقط: كلمات مؤقتة، إصدار مؤقت جديد) · الهيكل الإداري + المخطط التنظيمي (إعادة تعيين مدير مباشر) · لوحات الفريق/المدير · **مركز عمليات HR**.

**السجلات والبيانات:** المستندات (ID/عقد/طبي/أخرى + تتبّع انتهاء) · المهام الداخلية · السياسات (نسخ، توقيع/إقرار) · مراجعة التقارير اليومية · الإعدادات (شخصي/معقّد) · **إعدادات المُجمّع** (geofence واحد: lat/lon/radius/maxAccuracy) · تشخيص النظام + Health · النسخ الاحتياطي/الاستيراد + مركز البيانات + النسخ التلقائي · **سجل التدقيق + سجل الأمان** (فشل دخول، تدوير كلمات مرور) · Realtime/AI analytics/integrations · إعداد Supabase/تحديثات DB · أتمتة سير العمل/محاذاة الموبايل.

> ملاحظة: **بصمة QR مُلغاة نهائياً** — الحضور يعتمد فقط على Passkey + GPS + المراجعة.

---

## 2) قائمة المميزات والخدمات المشتركة (Cross-cutting modules)

يجب توفير هذه كخدمات/موديولات مشتركة عبر كل البوابات:

1. **هوية الحضور (Attendance Identity)** — بوابة مقاومة انتحال: Passkey (WebAuthn) + سيلفي + بيومتري + GPS + تقييم مخاطر. **القرار خادمي**؛ العميل يجمع الأدلة فقط.
2. **طابور offline + مزامنة** — تخزين الإجراءات محلياً عند انقطاع الاتصال، dedupe، مزامنة عند العودة، دون تسريب PII.
3. **صلاحيات ومصفوفة أدوار (client mirror)** — نسخة عرض فقط لمصفوفة الخادم؛ لا تُتَّخذ قرارات أمنية فعلية على العميل.
4. **منطق تقييم KPI** — مراحل، حسابات، حالات، انتقالات.
5. **تخزين آمن (browser + native)** — تخزين مشفّر؛ لا مُعرِّف دخول خام دائم.
6. **إشعارات push (web + native FCM)** — اشتراكات، إرسال مُخوّل بالصلاحيات.
7. **جسر Capacitor الأصلي** — كاميرا، موقع، haptics، شبكة، إشعارات، بيومتري، خدمة أمامية Android.
8. **Service workers** — كاش PWA، fallback offline، توافق إصدار، تعطيل داخل Capacitor.
9. **طبقة API** — REST/RPC facade فوق Supabase + تنسيق الميزات.
10. **قاعدة بيانات بذرة محلية / نموذج offline** — للعمل دون اتصال.
11. **أدوات مشتركة** — format, utils, error handler, auth, telemetry, performance monitor, illustrations, floating-layer, نظام مكوّنات UI + ثيم.

---

## 3) نموذج البيانات الكامل (Postgres + RLS)

> أعد بناءه بدلالات Supabase (Postgres + Auth + Storage + RLS + RPC) أو مكافئ حديث مطابق للدلالات. RLS مفعّل على **كل** جدول عام؛ الوصول يُحسَب عبر دوال SECURITY DEFINER لا عبر ثقة بالـrole slug.

### 3.أ) الجداول الأساسية (بعض الأعمدة تمثيلية — راجع القواعد)
- **permissions** (`id`, `scope` unique, `name`, `description`) — كتالوج ~35 scope.
- **roles** (`id`, `slug` unique, `name`, `permissions text[]`, `role_code`) — `permissions[]` مصفوفة نصية (ليست FK).
- **profiles** — حساب الدخول: `id (=auth.uid)`, `employee_id FK`, `role_id FK`, `status`, `temporary_password`, org fields. أعمدة حساسة (`role_id/employee_id/status/org`) محمية بـtrigger.
- **employees** — السجل الوظيفي: `id`, `user_id FK`, `full_name`, `phone unique(active)`, `job_title`, `manager_employee_id FK`, `is_active`, `is_deleted`, `photo_url`, org fields.
- **lookups:** `governorates, complexes, branches, departments, shifts, integration_settings` — قراءة لأي authenticated، كتابة full-access فقط.
- **attendance_events** — أحداث البصمة (server_verified). لا إدراج مباشر من الموظف.
- **attendance_daily** — تجميع يومي للحضور (late/status/work_minutes).
- **attendance_identity_checks** — نتيجة تقييم هوية خادمية (risk_score/level/flags/requires_review) — تُؤلَّف server-side (trigger).
- **attendance_risk_events**, **attendance_exceptions**, **attendance_permits** (إذنات: وصول/انصراف مع دقائق سماح).
- **passkey_credentials** — `credential_id`, `user_id`, `public_key`, `status (DISABLED/REVOKED/BLOCKED/PENDING_REVIEW/DEVICE_TRUSTED)`, `trusted`, `last_used`. trigger يفرض `trusted=false/PENDING_REVIEW` إلا عبر service_role.
- **webauthn_challenges** — `user_id`, `challenge`, `type (register|auth)`, `expires_at`, `used_at` (single-use, 5-min).
- **leave_requests**, **missions**, **convoy_requests** — طلبات بسير عمل موحّد (`status`, `workflow_status`, `manager_employee_id`, `escalation_deadline`, `decision_due_at`, `escalated_at`).
- **kpi_evaluations** + **kpi_cycles** — تقييمات بمراحل، أقفال دورة.
- **dispute_cases** — نزاعات/لجان (`status`, `severity`, `actor`, directory scoping).
- **notifications** — إشعارات المستخدم (owner-scoped).
- **push_subscriptions**, **notification_delivery_log**.
- **audit_logs / audit_events** — تدقيق (لا إدراج مباشر؛ عبر trigger/RPC فقط — tamper-resistant).
- **login_identifier_attempts**, **credential_vault / password vault** (service_role فقط)، **password_reset_requests** (token hash).
- **hr_config** (المدير التنفيذي المعتمد، `permit_monthly_limit`)، **settings/system_settings**، **system_backups**، **app_error_events / client_error_logs**، **employee_locations / location_requests / live_location_***، **employee documents / attachments / access_control_events / tasks / policies / daily_reports / sensitive_approvals**، **working_hours_monthly** (view security_invoker).

### 3.ب) دوال RPC الرئيسية (SECURITY DEFINER — راجع الأمان)
- **record_attendance_punch**(type, lat, lon, accuracy, passkey_credential_id, biometric_method, selfie_url, notes) — **البصمة الموثوقة الوحيدة للموظف.** يتحقق خادمياً من: المصادقة، موظف نشط، ملكية الـpasskey (`assert_attendance_passkey_credential`)، geofence الفرع (distance ≤ radius)، دقة GPS، قواعد التكرار/الترتيب؛ يحسب late/status؛ يُدرج حدثاً server_verified + daily + location؛ يختم last_used. **تُستدعى فقط عبر `verify-attendance-punch` بعد التحقق من assertion الـWebAuthn.**
- **assert_attendance_passkey_credential**(emp, cred) — يؤكد ملكية الـcredential وعدم تعطيله/انتهائه.
- **write_server_identity_check** (trigger AFTER INSERT) — يؤلّف صف `attendance_identity_checks` من حكم الخادم.
- **passkey_credentials_force_untrusted** (trigger) — يفرض عدم الثقة إلا عبر service_role/full-access.
- **record_attendance_manual_correction / submit_rejected_attendance_review** — تصحيح يدوي/مراجعة (بصلاحيات + الخادم يختم الحقول الحساسة).
- **approve/reject_{leave|mission|convoy|permit}_request**(id, reason) — موافقات مُقسّاة: `FOR UPDATE` lock، حظر الموافقة الذاتية (`SELF_APPROVAL_FORBIDDEN`)، تتطلب صلاحية أو أن يكون المدير المعيَّن، + كتابة تدقيق.
- **cancel_my_request**(table, id) — إلغاء طلب PENDING مملوك.
- **hr_normalize_and_validate_* / enforce_no_overlapping_leave** (triggers) — حل الموظف/المدير، فرض السقوف (إجازات لكل نوع، حد الإذنات الشهري)، توجيه `executive_unpaid` للمدير التنفيذي، تعيين workflow_status، إخطار المدير، رفض تداخل الإجازات.
- **صلاحيات:** `current_is_full_access` (`*` أو slug admin/super-admin فقط — التنفيذي/HR ليسا full-access)، `has_permission(scope)`, `has_any_permission(scopes[])`, `can_access_employee(emp)` (ذات/مدير مباشر/full)، `current_hr_employee_id`.
- **geo_distance_meters** (Haversine)، **calculate_late_minutes**، **upsert_attendance_daily_from_event**.
- **handle_new_auth_user** (trigger) — ربط profile بالبريد، تعيين role/org، وسم كلمة مرور مؤقتة.
- **set_updated_at / audit_row_change** — triggers عامة (تدقيق ~17 جدول).
- كتّاب مُتحكَّم بهم: `write_audit_event, log_client_error*, safe_create_notification, mark_notification_read, resolve_login_identifier, register/approve/reject/block_trusted_device`, تنظيف/صيانة (`cleanup_*`, `system_health_snapshot`, `calculate_hours_monthly`).

### 3.ج) دوال الحافة (Edge Functions) وعقودها
- **webauthn-challenge** (JWT) → `{challenge,expiresAt,type}`؛ single-use 5-min، rate-limit 20/دقيقة/مستخدم؛ يرفض بدون service key.
- **passkey-register** (verify_jwt=false، يتحقق من الـtoken بنفسه) → يسجّل credential؛ يتحقق من `clientDataJSON type=webauthn.create` + origin مسموح + تحدي `register` طازج (استهلاك atomic)؛ مفاتيح المتصفح تُخزَّن `trusted=false/PENDING_REVIEW`؛ البيومتري الأصلي موثوق فقط عند تفعيل `NATIVE_BIOMETRIC_TRUST_ENABLED`.
- **verify-attendance-punch** (JWT) → مسار البصمة الموثوق: يتحقق من JWT + الـcredential + assertion (تحدي طازج مُستهلَك atomically، `type=webauthn.get`، origin مسموح، توقيع ES256/P-256 على `authData||SHA256(clientData)`)؛ الأصلي يُقبل فقط عند `DEVICE_TRUSTED`؛ ثم يستدعي `record_attendance_punch`.
- **process-attendance-punch** (JWT) → مسار معالجة بصمة (legacy).
- **admin-create-user / admin-update-user** (verify_jwt=false) → إنشاء/تحديث حساب+profile+ربط موظف؛ يتطلب `users:manage`؛ يمنع غير الأدمن من تعيين أدوار محمية؛ **HR ليس أدمن** حتى بـ`*`؛ يمنع HR من لمس حسابات محمية/تدوير كلمة مرور غير حسابه (إصلاح استيلاء).
- **resolve-login-identifier** (verify_jwt=false) → حل الهاتف لـlogin-alias مع rate-limit مُجزَّأ (IP+identifier)؛ لا يكشف وجود حساب؛ يتطلب `LOGIN_RATE_LIMIT_SALT ≥ 24 حرف`.
- **verify-ops-gateway** (JWT) → عامل ثانٍ للأدمن/التنفيذي: مقارنة constant-time لـ`SHA256(code)` مع env، + allow-lists.
- **process-request-sla** (cron، `x-cron-secret`) → تصعيد الطلبات المتأخرة، تصعيد النزاعات >24h، حذف فيديوهات الموقع الحي >24h.
- **send-push-notifications / send-attendance-reminders** → إرسال push مُخوّل بالصلاحيات + تسجيل التسليم.
- **scheduled-backup** (cron، service role) → نسخ احتياطي مجدول.
- جميعها تشترك في **CORS helper** يقفل الأصل على النطاقات المسموحة (لا wildcard)، مع بوابة تطوير للـlocalhost.

### 3.د) حاويات التخزين (Storage Buckets)
- **avatars** — عام (لاحقاً مُقيَّد لقراءة authenticated)، 2MB، صور.
- **punch-selfies** — خاص، 3MB، قراءة للمالك أو full-access فقط.
- **employee-attachments** — خاص، 8MB، pdf/office/صور، بادئة مجلد لكل مستخدم + trigger تحقّق.
- **live-location-videos** — خاص، 15MB، فيديو؛ رفع/قراءة للمالك؛ **تُحذف بعد 24h** عبر cron.

---

## 4) نموذج الصلاحيات و RLS (بلغة واضحة)

- **قاعدة ذهبية:** كل قرار وصول يُحسَب بدالة SECURITY DEFINER (`current_is_full_access`, `has_permission`, `can_access_employee`, `current_hr_employee_id`) — **لا ثقة بالـrole slug من العميل.**
- **employees:** SELECT عبر `can_access_employee` (ذات/مدير/full)؛ كتابة full-access (+`employees:write`).
- **profiles:** SELECT ذات/full/مرؤوس؛ UPDATE ذات أو `users:manage/settings:manage`؛ الأعمدة الحساسة محجوبة بـtrigger على كل تحديث.
- **attendance_events:** **الموظف لا يُدرج مباشرة** — البصمة فقط عبر RPC/edge؛ UPDATE بـ`attendance:manage/review`.
- **الطلبات (leave/convoy/permit/mission):** SELECT ذات/مدير/full/صلاحية موافقة؛ INSERT ذات فقط بحالة PENDING؛ UPDATE للمشغّل/المدير/full (لا موافقة ذاتية؛ الإلغاء عبر `cancel_my_request`).
- **audit_logs:** SELECT full-access أو `audit:view`؛ **لا INSERT مباشر** (trigger/RPC فقط).
- **passkey_credentials:** الثقة تُمنَح فقط عبر service role (`passkey-register`)؛ trigger يفرض عدم الثقة.
- **notifications:** owner-scoped. **push_subscriptions:** owner أو full-access.
- **credential_vault / login_identifier_attempts:** service_role فقط (الخزنة تُقرأ بـ`current_can_view_password_vault`).
- **Realtime publication:** `attendance_events, employee_locations, leave_requests, missions, kpi_evaluations`.

---

## 5) المسارات الحسّاسة (خطوة بخطوة)

**أ) البصمة (Attendance Punch):**
1. العميل يجمع: Passkey + سيلفي + GPS (+ بيومتري إن وُجد).
2. `webauthn-challenge` يُصدر تحدي `auth` طازج (single-use، 5 دقائق).
3. المتصفح يُنشئ assertion عبر `navigator.credentials.get()`.
4. `verify-attendance-punch` يتحقق: JWT، ملكية الـcredential، `type=webauthn.get`، origin مسموح، استهلاك التحدي atomically، توقيع ES256/P-256 على `authData||SHA256(clientData)`.
5. عند النجاح → `record_attendance_punch` (الحكم الموثوق): geofence، دقة، تكرار، late/status → يُدرج حدثاً server_verified.
6. trigger `write_server_identity_check` يؤلّف صف تقييم الهوية (risk/flags/requires_review).

**ب) تسجيل البصمة (Passkey Register):** `webauthn-challenge (register)` → `passkey-register` (تحقق تحدي/attestation، يمنح الثقة عبر service role فقط، افتراضياً PENDING_REVIEW).

**ج) الموافقات:** إنشاء طلب → triggers تطبيع/سقوف/توجيه تنفيذي → `approve/reject_*` (lock + منع موافقة ذاتية + صلاحية + تدقيق) → تصعيد SLA عبر cron عند التأخر.

**د) KPI:** self → manager → hr → secretary → executive؛ قفل الدورة بعد يوم 25 مع قائمة متأخرين وتذكيرات.

**هـ) إدارة المستخدمين:** `admin-create-user/admin-update-user` (تحقق دور المستدعي خادمياً، حماية الأدوار الحساسة، منع HR من الاستيلاء، تدقيق).

**و) الإشعارات:** إرسال مُخوّل بالصلاحيات، تسجيل تسليم، دعم web push + native FCM.

**ز) العمل offline:** طابور محلي بلا PII، dedupe، مزامنة عند العودة، تخزين آمن مشفّر.

---

## 6) المتطلبات غير الوظيفية

- **الأمان:** كل قرار أمني خادمي (RLS + SECURITY DEFINER + edge). لا ثقة بالعميل. أدوار محمية. constant-time لمقارنات الأسرار. rate limiting مُجزَّأ. تدقيق tamper-resistant.
- **الخصوصية/PII:** لا مُعرِّف دخول خام دائم في localStorage. buckets خاصة افتراضياً. حذف فيديوهات الموقع بعد 24h. سجلات دخول/فشل مُجزَّأة.
- **العمل بدون اتصال:** طابور + مزامنة + snapshot هوية + كاش SW + صفحة offline.
- **التطبيق الأصلي (Capacitor 8):** Android (compileSdk/targetSdk 36، minSdk 24) + iOS، product flavors/bundle IDs منفصلة لكل بوابة، تحقق أصول البوابة، FCM، بيومتري أصلي، خدمة أمامية.
- **التوطين:** عربي RTL كامل، `lang=ar`، مصطلحات إنجليزية عند اللزوم.
- **الأداء:** تقسيم chunks، minify، مراقبة أداء، idle callbacks، لوحات مبنية بتقسيم صفحات.

---

## 7) معايير القبول (Acceptance Criteria)

- ✅ **الأمان:** لا يمكن لموظف إدراج `attendance_events` مباشرة؛ البصمة تفشل إن كان التحدي مُستهلَكاً/منتهياً أو التوقيع/الأصل غير صحيح؛ HR لا يستطيع تدوير كلمة مرور حساب محمي؛ لا موافقة ذاتية على الطلبات.
- ✅ **الوظائف:** كل الـ59 route في بوابة الأدمن + 25 ميزة الموظف تعمل؛ سير عمل الطلبات والـKPI بمراحله كامل؛ قفل دورة KPI بعد يوم 25.
- ✅ **البيانات:** كل الجداول/الـRPCs/الـbuckets/سياسات RLS المذكورة موجودة وتُطبَّق؛ التدقيق tamper-resistant.
- ✅ **الحضور:** geofence لموقع واحد يعمل؛ تقييم المخاطر server-authored؛ الثقة تُمنَح عبر service role فقط.
- ✅ **الموبايل:** بناء Android/iOS لكل بوابة بعزل، FCM، بيومتري، offline.
- ✅ **الخصوصية:** لا PII خام مخزّن؛ buckets خاصة؛ حذف فيديوهات 24h.
- ✅ **التوطين:** RTL عربي كامل عبر كل الشاشات.

---

## 8) ملاحظات إعادة البناء (تحديث الستاك)

- **مسموح ستاك حديث** مع الحفاظ على كل ما سبق. مقترح: Frontend حديث (مثلاً React/Next أو SvelteKit) بدل Vanilla JS، مع الحفاظ على فصل البوابات الأربع. Backend: أبقِ Postgres + RLS + Auth + Storage + Edge (Supabase أو مكافئ)، لأن نموذج الأمان مبني عليها.
- **تجنّب مشاكل النسخة الحالية:** ازدواج سياسات RLS خارج الـmigrations (كان هناك `RUN_IN_SUPABASE_SQL_EDITOR.sql` / `FINAL_ALL_MISSING_PATCHES.sql` يعرّفان سياسات خارج السلسلة — اجعل كل شيء داخل migrations مُرتَّبة)؛ تضخّم طبقة الفحص (~145 سكربت check-vNNN) — استبدلها بـCI/tests نظيفة؛ وجود مسارين للأدوار (role_id/slug + role_code من حقبة v140) — وحّدهما في نموذج واحد.
- ابنِ **مصفوفة صلاحيات واحدة** مصدرها الخادم، والعميل mirror للعرض فقط.

---

## 9) تطويرات وإضافات قوية — نحو نظام HR مؤسسي كامل يغطي دورة حياة الموظف

> **الرؤية:** ترقية النظام من "نظام حضور + طلبات + تقييم شهري" إلى **HRIS/HCM مؤسسي متكامل** يغطي **دورة حياة الموظف كاملة**:
> **التوظيف → الإلحاق → الأداء → التطوير → التعويض → المشاركة والاحتفاظ → الخروج.**
> كل الوحدات التالية تُبنى فوق **نفس أسس الأمان الحالية** (RLS + دوال SECURITY DEFINER + edge functions + سجل تدقيق + الأدوار)، وتعيد استخدام المكوّنات الموجودة (محرك الموافقات، المهام، الإشعارات/push، السياسات بإقرار، المستندات، التقارير PDF، KPI). أضف دورًا جديدًا **`payroll_officer`** (وأدوار فرعية: `recruiter`, `finance`) إلى مصفوفة الصلاحيات.

### 9.1 التوظيف والتعيين والإلحاق (Recruitment, ATS & Onboarding)

1. **الوظائف الشاغرة وطلبات التوظيف (Requisitions & Job Postings)** — [must-have] — تحويل حاجة القسم إلى شاغر معتمد قبل النشر: طلب توظيف (مسمى/قسم/عدد/ميزانية/سبب) يمرّ بسلسلة موافقات (مدير→HR→تنفيذي) ثم يتحوّل لإعلان بـslug عام. لوحة شواغر مفتوحة/مجمّدة/مغلقة مع `time-to-fill`. **جداول:** `job_requisitions`, `job_requisition_approvals`, `job_postings`, `job_description_templates`. **يعيد استخدام:** محرك الموافقات + الهيكل التنظيمي.
2. **قاعدة المرشحين واستقبال الطلبات (Candidate Database & Talent Pool)** — [must-have] — سجل مركزي لكل المتقدّمين (نموذج عام/رفع يدوي/ترشيح موظف)، منع تكرار بالبريد/الهاتف، بحث وفلترة، إعادة ترشيح مرشح سابق، موافقة على معالجة البيانات. **جداول:** `candidates`, `candidate_documents`, `applications`, `candidate_notes` + bucket خاص للسير الذاتية.
3. **خط أنبوب التوظيف (ATS Pipeline)** — [must-have] — لوحة كانبان بمراحل قابلة للتخصيص (تقديم→فرز→اختبار→مقابلات→عرض→تعيين/رفض) مع سبب رفض إلزامي، أتمتة إشعار/مهمة عند كل مرحلة، ومؤشرات اختناق. **جداول:** `pipeline_stages`, `application_stage_history`, `application_current_state`, `rejection_reasons`.
4. **جدولة المقابلات وبطاقات التقييم (Interview Scorecards)** — [must-have] — مقابلات (حضوري/عن بعد)، بطاقة تقييم موزونة بمعايير مرتبطة بالوظيفة، **إخفاء تقييمات اللجنة حتى يسجّل العضو تقييمه** (منع التحيّز)، تجميع تلقائي، تذكيرات push. **جداول:** `interviews`, `interview_panel`, `interview_scorecards`, `scorecard_criteria_scores`, `scorecard_templates`.
5. **عروض العمل والاعتماد المالي (Job Offers)** — [high] — توليد عرض من قالب، **تحقق آلي أن قيمته ضمن ميزانية الـrequisition**، موافقة مالية/تنفيذية، بوابة قبول/رفض/تفاوض للمرشح مع تتبّع الإصدارات. **جداول:** `job_offers`, `offer_approvals`, `offer_negotiations`.
6. **التوقيع الإلكتروني للعقود (E-Signature & Contract Vault)** — [high] — عقد من قالب، توقيع إلكتروني للمرشح بإثبات هوية (OTP/passkey) + طابع زمني، توقيع مضاد للمؤسسة، خزنة عقود PDF غير قابلة للتعديل. **جداول:** `employment_contracts`, `contract_signatures`, `contract_templates`. **يعيد استخدام:** WebAuthn/OTP + bucket خاص.
7. **قائمة الإلحاق والرحلات (Onboarding Journeys)** — [must-have] — رحلة منظّمة من قبول العرض لنهاية التجربة: مهام بمواعيد نسبية (قبل المباشرة/اليوم الأول/الأسبوع/الشهر) موزّعة على HR/IT/المدير/الموظف، دمج توقيع السياسات، شاشة إلحاق للموظف الجديد بنسبة إنجاز، متابعة نهاية التجربة. **جداول:** `onboarding_journeys`, `onboarding_tasks`, `onboarding_templates`. **يعيد استخدام:** المهام + السياسات بإقرار.
8. **توفير الحسابات والأصول (Provisioning & Asset Handover)** — [high] — إنشاء حساب الموظف من ملف المرشح عبر `admin-create-user`، تسجيل passkey في اليوم الأول، سجل عُهدة أصول (تسليم/استرجاع بتوقيع)، ومسار offboarding عكسي لإلغاء الوصول. **جداول:** `provisioning_requests`, `asset_inventory`, `asset_assignments`, `provisioning_audit`.

### 9.2 الرواتب والتعويضات والمزايا (Payroll, Compensation & Benefits)

1. **هيكل الرواتب والدرجات (Salary Structure & Grades)** — [must-have] — درجات/رتب بنطاق (min/mid/max)، مكوّنات راتب قياسية، ربط كل موظف بدرجته مع **سجل زمني لا يُحذف** لكل تغيير، وتنبيه `compa-ratio` عند الخروج عن النطاق. **جداول:** `salary_grades`, `salary_components`, `employee_compensation`, `grade_component_defaults`.
2. **محرك مسيّر الرواتب الشهري (Payroll Run Engine)** — [must-have] — دورة بحالات (مسودة→محسوبة→مراجعة→معتمدة→مصروفة→مقفلة)، تجميع تلقائي لكل المدخلات، **اشتقاق خصومات الغياب/التأخير من وحدة الحضور**، مقارنة variance بالشهر السابق، قفل بعد الصرف + تسوية موثّقة. **جداول:** `payroll_runs`, توسيع `payslips`, `payslip_lines`, `payroll_adjustments`.
3. **البدلات والخصومات (Recurring & Ad-hoc Pay Elements)** — [high] — بنود استحقاق/اقتطاع متكررة ولمرة واحدة بنافذة سريان وموافقة، إسناد جماعي لقسم/فريق، ربط خصم تأديبي بوحدة النزاعات. **جداول:** `employee_pay_elements`, `pay_element_batches`.
4. **السلف والقروض (Loans & Advances)** — [high] — طلب سلفة/قرض بحاسبة أقساط، سير موافقة، **جدول سداد يُخصم تلقائيًا في مسيّر الرواتب**، سداد مبكر/تأجيل، وتسوية الرصيد عند نهاية الخدمة، وحماية من تجاوز نسبة اقتطاع آمنة. **جداول:** `loans`, `loan_installments`, `loan_events`.
5. **المكافآت والحوافز المرتبطة بالأداء (KPI-linked Incentives)** — [high] — قاعدة تحوّل درجة KPI إلى نسبة مكافأة تلقائيًا عند إغلاق الدورة، مكافآت موسمية/تقديرية، سقف ميزانية حوافز، ضخّ المكافأة في payslip. **جداول:** `bonuses`, `incentive_rules`, `bonus_budgets`. **يربط:** دورة KPI الحالية.
6. **التأمينات والضرائب والحماية الأجرية (Statutory & WPS)** — [must-have] — قواعد تأمين/ضريبة (نِسب/حدود)، احتساب تلقائي في payslip، **تخزين مشفّر لأرقام الهوية/التأمين مع RLS يقصر الاطلاع على finance/payroll**، توليد ملف حماية الأجور (WPS) للبنك، وتقارير الاشتراكات. **جداول:** `statutory_configs`, `employee_statutory_profile`, `statutory_contributions`, `wps_exports`.
7. **نهاية الخدمة والتسوية النهائية (End-of-Service & Final Settlement)** — [must-have] — حاسبة مكافأة نهاية خدمة حسب المدة والسبب، تسوية شاملة (مكافأة + راتب متبقٍّ + صرف رصيد الإجازات نقدًا − أرصدة القروض − العُهد)، اعتماد + PDF، واحتساب التزام شهري (accrual). **جداول:** `eos_settlements`, `eos_rules`, `eos_accruals`.
8. **كشف الراتب الرقمي والخدمة الذاتية (Digital Payslip ESS)** — [high] — كشوف رواتب مفصّلة في تطبيق الموظف، تنزيل PDF عربي معتمد، طلب شهادة راتب ذاتيًا، لوحة مالية مصغّرة، إشعار push + إقرار استلام، والاعتراض على بند عبر وحدة النزاعات. **جداول:** `payslip_acknowledgements`, `salary_certificate_requests`.
9. **إدارة المزايا غير النقدية (Benefits Administration)** — [nice-to-have] — كتالوج مزايا (تأمين طبي/تعليم/سفر) بأهلية حسب الدرجة، إدارة المعالين، بيان التعويض الكلي (Total Rewards) السنوي، تتبّع تكلفة المزايا. **جداول:** `benefit_plans`, `employee_benefits`, `benefit_dependents`.

### 9.3 إدارة الأداء والأهداف والكفاءات (Performance, OKR, Competency, 360)

1. **إدارة الأهداف والنتائج الرئيسية (OKR / Goals Cascade)** — [must-have] — شجرة أهداف متتالية من المؤسسة→الإدارة→الفريق→الفرد، Key Results قابلة للقياس بنسبة تقدم، check-ins بحالة (on-track/at-risk/off-track)، محاذاة، وتحديث KR تلقائيًا من بيانات النظام (قوافل/مهام/حضور). **جداول:** `goal_objectives`, `goal_key_results`, `goal_checkins`, `goal_alignment_links`.
2. **التقييم متعدد الجهات 360° (360 Feedback)** — [must-have] — جولات تقييم (ذات/مدير/أقران/مرؤوسين)، ترشيح مُقيّمين واعتماد، استبيان قائم على الكفاءات، **سرية بكشف مُجمّع فقط عند حد أدنى من الردود**، تقرير مرئي (self vs others + heatmap). **جداول:** `feedback_rounds`, `feedback_raters`, `feedback_questionnaires`, `feedback_responses`, `feedback_reports`.
3. **إطار الكفاءات والتقييم السلوكي (Competency Framework)** — [high] — مكتبة كفاءات (قيادية/فنية/سلوكية/قيمية) بمستويات إتقان موصوفة سلوكيًا، نموذج متوقع لكل دور، تقييم مقابلها، وخريطة فجوات تغذّي التدريب. **جداول:** `competencies`, `competency_levels`, `role_competency_profiles`, `employee_competency_assessments`.
4. **جلسات المعايرة والتوزيع العادل (Calibration)** — [high] — جلسة يراجع فيها المديرون وHR الدرجات معًا لضبط تفاوت الصرامة، شبكة 9-Box، رصد الانحراف، تعديل بسبب موثّق، ومحضر PDF — كبوابة قبل الاعتماد النهائي. **جداول:** `calibration_sessions`, `calibration_participants`, `calibration_minutes`.
5. **محرك دورات المراجعة القابلة للتهيئة (Review Cycle Engine)** — [must-have] — دورات متعددة (نصف سنوية/سنوية/تجربة/مشروع) تجمّع الدرجة من (أهداف + كفاءات + 360 + التزام) بأوزان قابلة للضبط ومراحل workflow مُهيّأة، تبني فوق `kpi_cycles`. **جداول:** `review_cycle_templates`, `review_cycle_instances`, `review_participations`, `review_stage_transitions`.
6. **خطط تحسين الأداء والتطوير (PIP & IDP)** — [must-have] — خطة تحسين رسمية بأهداف SMART ومعالم ودعم وإقرار موظف وتصعيد عند التجاوز (حماية قانونية)، وخطة تطوير فردية (IDP) من فجوات الكفاءات. **جداول:** `improvement_plans`, `plan_goals`, `plan_checkins`, `plan_acknowledgements`, `plan_outcomes`.
7. **المتابعة المستمرة واجتماعات 1:1 (Continuous Check-ins)** — [high] — اجتماعات دورية بأجندة مشتركة وبنود متابعة، وتغذية راجعة فورية مرتبطة بالكفاءات، تتراكم كأدلة للمراجعة الدورية. **جداول:** `one_on_ones`, `checkin_action_items`, `instant_feedback`.
8. **ربط الأداء بالمكافأة والتقدير (Pay-for-Performance)** — [nice-to-have] — جسر بين درجة المراجعة النهائية ووحدة المكافآت (9.2.5) لتفعيل الاستحقاق تلقائيًا.

### 9.4 التعلّم والتطوير والمسار الوظيفي (Learning, Development, Career & Succession)

1. **كتالوج التعلّم ونظام إدارة الدورات (LMS Core)** — [must-have] — كتالوج دورات (داخلية/خارجية/إلزامية)، تسجيل وتتبّع إكمال، اختبارات، ومسارات تعلّم إلزامية (سلامة/امتثال) مرتبطة بالإلحاق. **جداول:** `courses`, `course_enrollments`, `learning_paths`, `course_completions`.
2. **مصفوفة المهارات والكفاءات (Skills Matrix)** — [must-have] — سجل مهارات لكل موظف بمستوى، خريطة مهارات الفريق، وكشف فجوات المهارات الحرجة. **جداول:** `skills`, `employee_skills`, `skill_requirements`.
3. **الشهادات والاعتمادات وتتبّع الصلاحية (Certifications Lifecycle)** — [high] — تسجيل شهادات مهنية/تراخيص بتواريخ انتهاء وتنبيهات تجديد استباقية (يعيد استخدام تتبّع انتهاء المستندات الحالي). **جداول:** `certifications`, `employee_certifications`.
4. **خطط التطوير الفردية (IDP)** — [high] — تتكامل مع 9.3.6 وفجوات الكفاءات لتوليد إجراءات تطوير موجّهة.
5. **تخطيط التعاقب (Succession Planning)** — [high] — تحديد الأدوار الحرجة، ورثة محتملون بمستوى جاهزية (جاهز الآن/1-2 سنة)، وخطط طوارئ. **جداول:** `critical_roles`, `succession_candidates`, `readiness_assessments`.
6. **مسارات الترقّي والإطار الوظيفي (Career Paths)** — [high] — مسارات وظيفية معلنة بمتطلبات كل مستوى، يرى الموظف الفجوة بينه وبين الترقية القادمة. **جداول:** `career_paths`, `path_steps`, `path_requirements`.
7. **محرّك التوصيات والتحليلات الذكية للتعلّم** — [nice-to-have] — توصية دورات بناءً على فجوات المهارات ومسار الترقّي.

### 9.5 الوقت والجدولة والورديات (Advanced Time, Shifts, Overtime)

1. **مصمّم أنماط الورديات (Shift Pattern Designer)** — [must-have] — تعريف ورديات ونماذج دوران (صباحي/مسائي/ليلي/متناوب) وقواعد راحة. **جداول:** `shift_patterns`, `shift_definitions`, `rotation_rules`.
2. **لوحة الجدول والروستر المنشور (Published Roster)** — [must-have] — بناء ونشر جدول عمل الفريق، رؤية الموظف لورديّاته، وربطه باحتساب الحضور والتأخير. **جداول:** `rosters`, `roster_assignments`.
3. **سوق تبديل الورديات (Shift Swap Marketplace)** — [high] — طلب تبديل/تغطية بموافقة المدير، يعيد استخدام محرك الموافقات. **جداول:** `shift_swap_requests`.
4. **محرك العمل الإضافي (Overtime Engine)** — [must-have] — احتساب ساعات إضافية من فرق الحضور مقابل الوردية، اعتماد، وضخّها في مسيّر الرواتب كبند. **جداول:** `overtime_records`, `overtime_rules`.
5. **تقويم العطلات الرسمية (Public Holiday Calendar)** — [must-have] — إدارة الإجازات الرسمية وأيام العمل الاستثنائية، تؤثّر على الحضور والرواتب والإجازات. **جداول:** `public_holidays`, `working_calendars`.
6. **أنماط العمل المرن والعن-بُعد (Flexible & Remote)** — [high] — ساعات نواة (core hours)، عمل مرن، وتسجيل أيام العمل عن بُعد.
7. **إطار البصمة متعددة المواقع (Multi-Site Geofence)** — [nice-to-have] — توسعة الـgeofence الحالي (موقع واحد) لمواقع/فروع متعددة استعدادًا للتوسّع.
8. **محرك سياسات التأخير والامتثال الزمني (Tardiness Engine)** — [high] — قواعد قابلة للتهيئة للتأخير المتكرر/الغياب وتصعيدها تلقائيًا (إنذار→خصم→قرار)، تربط الحضور بالتأديب والرواتب.

### 9.6 تجربة الموظف والمشاركة والرفاهية (Engagement, Recognition & Wellbeing)

1. **استبيانات النبض والمشاركة و eNPS (Pulse Surveys)** — [must-have] — استبيانات دورية قصيرة مجهولة الهوية، مؤشر eNPS، وتحليل اتجاه المعنويات بمرور الوقت. **جداول:** `surveys`, `survey_questions`, `survey_responses` (مجهولة).
2. **صندوق الأفكار والاقتراحات (Suggestion Box)** — [must-have] — تقديم أفكار (باسم/مجهول)، تصويت، ومتابعة حالة التنفيذ. **جداول:** `suggestions`, `suggestion_votes`.
3. **تقدير الأقران والشكر (Kudos & Recognition)** — [high] — إرسال شكر عام مرتبط بقيمة/كفاءة، جدار تقدير، ونقاط تقدير. **جداول:** `recognitions`, `recognition_values`.
4. **بوابة التواصل الداخلي والإعلانات (Internal Comms Hub)** — [must-have] — إعلانات مؤسسية موجّهة بالإقرار (يوسّع القرارات الإدارية الحالية)، أخبار، وتقويم فعاليات. **جداول:** `announcements`, `announcement_acknowledgements`.
5. **الرفاهية والدعم النفسي السري (Confidential Wellbeing)** — [high] — قناة سرية لطلب دعم/إبلاغ، بخصوصية قصوى (RLS يقصر الاطلاع على مختص محدد). **جداول:** `wellbeing_requests` (سرية).
6. **اللقاءات الفردية والتغذية الراجعة (1:1s)** — [high] — تتكامل مع 9.3.7.
7. **لوحة صحة المشاركة والإنذار المبكر بالدوران** — [nice-to-have] — دمج مؤشرات (استبيانات + تقدير + دوران) للإنذار المبكر باستنزاف الفرق.

### 9.7 الخدمة الذاتية ودورة الحياة والامتثال (ESS/MSS, Lifecycle, Compliance)

1. **مركز الخطابات والشهادات الذاتي (Letters & Certificates Self-Service)** — [must-have] — طلب شهادة راتب/تعريف/خبرة ذاتيًا، إصدار PDF معتمد بعد موافقة سريعة. **جداول:** `document_requests`, `document_templates`.
2. **تحديث البيانات الذاتي بموافقة (Data Change Requests)** — [must-have] — الموظف يطلب تعديل بياناته (هاتف/عنوان/حالة اجتماعية/حساب بنكي) فيمرّ بموافقة HR قبل التطبيق، مع أثر تدقيق. **جداول:** `data_change_requests`.
3. **محرك أحداث دورة الحياة (Lifecycle Events Engine)** — [must-have] — نمذجة أحداث (تعيين/ترقية/نقل/تغيير راتب/إجازة طويلة/تعليق/إنهاء) كسلسلة موثّقة تربط كل الوحدات وتحرّك الأتمتة. **جداول:** `lifecycle_events`, `event_effects`.
4. **الإنهاء والإخلاء ومقابلة الخروج (Offboarding & Exit)** — [must-have] — قائمة إخلاء طرف (استرجاع أصول + إلغاء وصول عبر عكس التوفير)، مقابلة خروج منظّمة، وربط بتسوية نهاية الخدمة (9.2.7). **جداول:** `offboarding_cases`, `clearance_items`, `exit_interviews`.
5. **التوقيع الإلكتروني ودفتر المستندات الموقّعة (Signed Documents Ledger)** — [high] — بنية توقيع إلكتروني عامة (تعيد استخدام 9.1.6) لأي مستند HR (سياسات/إقرارات/خطابات) بسجل غير قابل للتعديل. **جداول:** `signature_requests`, `signed_documents`.
6. **سجل الامتثال والوثائق القانونية (Compliance Register)** — [high] — تتبّع تراخيص/تصاريح/وثائق قانونية للمؤسسة والموظف بتواريخ انتهاء وتنبيهات (يوسّع تتبّع المستندات الحالي). **جداول:** `compliance_documents`, `compliance_alerts`.
7. **حوكمة الخصوصية وحق النسيان (Data Privacy & DSAR)** — [nice-to-have] — طلبات صاحب البيانات (اطلاع/تصحيح/حذف) وإخفاء هوية بيانات الموظفين المغادرين بعد مدة الاحتفاظ. **جداول:** `dsar_requests`, `retention_policies`.

### 9.8 التحليلات والذكاء والمنصة والتكاملات (People Analytics, AI, Platform)

1. **مستودع تحليلات القوى العاملة (People Analytics Warehouse)** — [must-have] — لوحات مؤشرات مؤسسية (عدد/تنوّع القوى العاملة، معدل الدوران، متوسط الحضور، توزيع الأداء، الكتلة الرواتبية، time-to-fill) عبر views/materialized views مجمّعة. **جداول/views:** `analytics_facts`, dashboards معرّفة.
2. **التنبؤ باستنزاف الموظفين (Attrition Prediction)** — [high] — نموذج مخاطر يجمع إشارات (انخفاض أداء/مشاركة، تأخر ترقية، تأخير متكرر) لتوليد قائمة موظفين معرّضين للمغادرة مع أسباب. **جداول:** `attrition_scores`, `risk_signals`.
3. **مساعد الموارد البشرية بالذكاء الاصطناعي (AI HR Assistant / RAG)** — [high] — مساعد محادثة يجيب على أسئلة السياسات والرصيد والإجراءات من بيانات النظام (RAG على السياسات + بيانات الموظف بصلاحياته)، ومسودّات خطابات/تقييمات. **يحترم RLS بالكامل.**
4. **محرّك سير العمل القابل للتهيئة (Configurable Workflow Engine)** — [must-have] — تعميم محرك الموافقات الحالي إلى محرك عام مُهيّأ (تعريف مراحل/موافقين/SLA/تصعيد لأي نوع طلب دون كود)، يوحّد كل مسارات الموافقة في النظام. **جداول:** `workflow_definitions`, `workflow_instances`, `workflow_steps`.
5. **مركز التكاملات والموصّلات (Integration Hub)** — [high] — SSO (OIDC/SAML)، بريد/تقويم، ERP/محاسبة (تصدير قيود الرواتب)، بنوك (WPS)، وواتساب/SMS للإشعارات. **جداول:** `integrations`, `integration_logs`.
6. **منصة تعدّد الفروع والكيانات (Multi-Site / Multi-Org)** — [nice-to-have] — بنية `org_id`/tenant على كل جدول مع RLS معزول، استعدادًا لخدمة أكثر من جمعية/فرع.
7. **منصة تعدّد اللغات (i18n Platform)** — [nice-to-have] — طبقة ترجمة كاملة (عربي/إنجليزي) مع الحفاظ على RTL كافتراضي.
8. **واجهة برمجية عامة وويبهوكس (Public API & Webhooks)** — [nice-to-have] — API موثّق + webhooks للأحداث للتكامل الخارجي.
9. **مكتب خدمة وتذاكر الموارد البشرية (HR Helpdesk & Ticketing)** — [high] — نظام تذاكر لاستفسارات الموظفين لـHR (فئات/SLA/قاعدة معرفة)، يقلّل الاستفسارات المتكررة ويقيس جودة خدمة HR. **جداول:** `hr_tickets`, `ticket_messages`, `knowledge_base`.

### 9.9 خارطة الطريق حسب الأولوية (Roadmap)

| المرحلة | التركيز | أبرز الوحدات (must-have) |
|--------|---------|--------------------------|
| **المرحلة 1 — الأساس المؤسسي** | إغلاق دورة الحياة الأساسية والامتثال المالي | التوظيف (requisitions/ATS/مقابلات/إلحاق)، هيكل الرواتب + مسيّر الرواتب + التأمينات/WPS + نهاية الخدمة، OKR + محرك دورات المراجعة + 360 + PIP، LMS + مصفوفة المهارات، الورديات + الروستر + العمل الإضافي + تقويم العطلات، الاستبيانات + الإعلانات، الخدمة الذاتية (خطابات/تغيير بيانات) + أحداث دورة الحياة + الإنهاء، مستودع التحليلات + محرك سير العمل |
| **المرحلة 2 — الإثراء** | تعميق التجربة والحوكمة | العروض + التوقيع الإلكتروني + التوفير، البدلات + السلف + المكافآت + الـpayslip الذاتي، الكفاءات + المعايرة + 1:1، الشهادات + IDP + التعاقب + المسارات الوظيفية، تبديل الورديات + العمل المرن + محرك التأخير، التقدير + الرفاهية، التوقيع العام + سجل الامتثال، التنبؤ بالاستنزاف + مساعد AI + التكاملات + Helpdesk |
| **المرحلة 3 — التوسّع** | القابلية للتوسّع والذكاء | المزايا غير النقدية، ربط الأداء بالمكافأة، توصيات التعلّم، البصمة متعددة المواقع، صحة المشاركة، حوكمة الخصوصية/DSAR، تعدّد الفروع + i18n + API عام |

### 9.10 تكامل مع النموذج الأمني الحالي (إلزامي لكل إضافة)

- **RLS على كل جدول جديد** بنفس نمط الدوال الحالية (`current_is_full_access`, `has_permission`, `can_access_employee`, `current_hr_employee_id`).
- **كل الإجراءات الحسّاسة عبر RPCs (SECURITY DEFINER)** لا عبر إدراج مباشر من العميل: تشغيل الرواتب، اعتماد العروض، توليد نهاية الخدمة، انتقالات المراحل، الموافقات — كلها خادمية مع فحص صلاحية + منع الفعل الذاتي حيث يلزم.
- **البيانات الحسّاسة مشفّرة** (أرقام الهوية/التأمين/الحساب البنكي) مع RLS يقصر الاطلاع على `finance`/`payroll_officer` فقط، وbuckets خاصة للمستندات (سير ذاتية/عقود/payslips).
- **سجل تدقيق tamper-resistant** لكل إجراء مالي أو تعاقدي (عبر triggers/RPCs، لا INSERT مباشر).
- **إعادة استخدام** محرك الموافقات، المهام، الإشعارات/push، السياسات بإقرار، المستندات، التقارير PDF، دورة KPI — بدل التكرار.
- **توسعة مصفوفة الصلاحيات** بأدوار/scopes جديدة (`payroll:run`, `payroll:approve`, `recruitment:manage`, `performance:calibrate`, `learning:manage`...) مع بقاء `admin` هو full-access الوحيد و`HR` غير مُعامَل كأدمن كامل.

### 9.11 معايير قبول عامة للإضافات

- ✅ كل وحدة جديدة تفشل بأمان (fail-closed) عند غياب الصلاحية، ولا تتّخذ أي قرار مالي/تعاقدي على العميل.
- ✅ مسيّر الرواتب يعيد نفس النتيجة عند إعادة التشغيل لنفس الشهر قبل القفل (idempotent)، ويرفض التعديل بعد القفل إلا عبر تسوية موثّقة.
- ✅ لا يمكن لموظف الموافقة على طلبه (توظيف/عرض/سلفة/إجازة) أو تعديل بياناته الحسّاسة دون موافقة.
- ✅ البيانات الحسّاسة (هوية/بنك/تأمين/راتب) غير مرئية إلا لأصحاب الصلاحية المالية، ومشفّرة في التخزين.
- ✅ كل انتقال مرحلة (ATS/مراجعة/سير عمل) وكل إجراء مالي مسجّل في التدقيق بمن ومتى ولماذا.
- ✅ الإضافات تحافظ على التوطين العربي RTL الكامل والعمل offline حيثما ينطبق.

# نهاية نطاق V1–V7 الموروث داخل Master Prompt V8


# ملحق V7 — بوابات أمان قاعدة البيانات قبل التنفيذ

ملفات SQL المرفقة `0001` إلى `0011` تعد Foundation Draft وليست جاهزة للإنتاج حتى نجاح البوابات التالية:

1. ترتيب إنشاء `profiles` قبل أي دالة تعتمد عليه.
2. تطبيق Scopes وABAC فعليًا داخل دوال الوصول وسياسات RLS، وعدم الاكتفاء بـ`has_permission(code)`.
3. منع تنفيذ RPC تسجيل الحضور مباشرة من `authenticated`، وجعل Edge Function التي تتحقق من تحدي Passkey/البيومتري هي المسار الوحيد.
4. استخدام وقت الخادم للحضور، ومنع العميل من تقرير `server_verified`, `risk_score`, `trusted`, أو `event_at` الموثوق.
5. إصلاح Trigger منح ثقة Passkey وعدم الاعتماد على `current_user` داخل `SECURITY DEFINER` لتحديد Service Role.
6. إكمال Workflow Engine بحيث لا تنهي أول موافقة كل المراحل، مع دعم الخطوة النشطة والتسلسل والتوازي والتفويض والتصعيد والإعادة.
7. ربط نقاط الموقع والفيديو بجلسة نشطة وNonce ومدة وصلاحية، والتحقق من Freshness وRetention وسجل المشاهدة.
8. نقل أسرار المنصة إلى Secret Manager/Vault؛ لا توجد خزنة تعرض كلمات مرور المستخدمين الحالية.
9. إضافة migrations الناقصة، Storage policies، Edge Functions contracts، pgTAP/RLS tests، seed آمن، وPost-deploy verification.
10. فشل أي اختبار P0/P1 يمنع بناء الواجهات فوق المسار المتأثر أو النشر إلى Production.

# ترتيب الأولوية النهائي

عند أي تعارض، استخدم الترتيب التالي:

1. ملحق V7 الخاص بتطبيق Flutter واحد ولوحة React واحدة.
2. قواعد الأمان وRLS والـSQL gates.
3. متطلبات V6 الوظيفية غير المتعارضة.
4. الملفات القديمة كمراجع فقط.

---

# ملحق V8 الملزم — Enterprise Governance, Automation & Process Intelligence

> هذا الملحق جزء أصيل من Master Prompt V8، وليس قائمة أفكار اختيارية منفصلة. عند وجود تعارض، تُطبّق أولويات V8 مع الحفاظ على قرار V7 المعماري: **تطبيق Flutter واحد** لجميع أدوار الموبايل، و**React Web واحدة** بـHR Workspace وMain Admin Workspace، وBackend واحد.

## 10. السلطة والأولوية ونطاق الإصدار

1. لا يُلغى أي مطلب أمني أو وظيفي صحيح من V7.
2. V8 تضيف طبقات الحوكمة والأتمتة وذكاء العمليات، ولا تعيد إنشاء Chat داخلي؛ تبقى قناة الأخبار والقرارات الرسمية أحادية الاتجاه في الإصدار الأساسي.
3. لا تُبنى كل وحدات V8 دفعة واحدة. تُنفذ حسب خارطة الطريق والـRelease Gates.
4. كل وحدة قابلة للتفعيل عبر Feature Flag، ولها Data Owner وProduct Owner وSecurity Classification.
5. لا تُبنى وحدة جديدة قبل اكتمال Foundation وSQL P0 Remediation واختبارات RLS لمسارها.
6. أي AI أو توقعات أو Matching تقدم توصيات تفسيرية فقط، ولا تنفذ فصلًا أو جزاءً أو ترقية أو راتبًا أو رفض شكوى تلقائيًا.

## 11. تثبيت المعمارية التشغيلية

### 11.1 تطبيق Flutter الواحد

يوفر Workspaces ديناميكية حسب صلاحيات الخادم:

- **Employee Workspace:** يومي، الحضور، الطلبات، المهام، KPI، الأخبار والقرارات، السياسات، المستندات، الملف.
- **Manager Workspace:** كل وظائف الموظف + فريقه، الموافقات، التقييمات، الحضور، التغطية، 1:1، التقارير.
- **Executive Workspace:** Executive Inbox، Briefing، الاعتمادات، التقارير، القرارات، المخاطر، اللجان، المواقع، التتبع، الاجتماعات التنفيذية.
- **Committee Workspace:** يظهر فقط لعضو لجنة في القضايا المسندة.
- **Field Operations Workspace:** يظهر لأدوار التشغيل الميداني حسب الحاجة.

لا يُنشأ APK منفصل وظيفيًا. Flavors للبيئات فقط: `dev`, `staging`, `prod`.

### 11.2 React Web الواحدة

- **HR Workspace:** الأشخاص، الحضور، الطلبات، الأداء، التوظيف، Onboarding، التعلم، المستندات، Helpdesk، تقارير HR.
- **Main Admin Workspace:** السكرتارية التنفيذية، Executive Dispatch، القرارات، اللجان، الصلاحيات، السياسات، Workflows، البيانات، الأمان، التكاملات، الإدارة التقنية.
- **Product & Operations Workspace** داخل Main Admin عند الصلاحية: المشروعات، المخاطر، العمليات، الجودة، التدقيق، الأتمتة.

## 12. Universal Action Center — مركز الإجراءات الموحد

أنشئ مركزًا واحدًا لكل مستخدم يعرض كل عنصر يحتاج إجراءً:

- طلب موافقة.
- تقييم KPI.
- قرار يحتاج اطلاعًا أو اعتمادًا.
- تصويت.
- محضر يحتاج توقيعًا.
- مهمة أو إجراء تصحيحي.
- سياسة تحتاج إقرارًا.
- تقرير يحتاج مراجعة.
- طلب موقع أو استجابة ميدانية.
- مستند قريب من الانتهاء.
- تذكرة أو قضية تحتاج ردًا.

### قواعد المركز

- ترتيب حسب `risk`, `urgency`, `due_at`, `business_impact`.
- فلاتر: اليوم، متأخر، عاجل، نوع العملية، الإدارة، الفريق.
- لا يعتمد المستخدم عنصرًا لا يملكه في Workflow الحالي.
- Batch Actions فقط للعناصر منخفضة المخاطر والمتجانسة.
- لا Batch Approval للجزاءات، الفصل، الرواتب، القضايا، التقييم النهائي، تغيير الصلاحيات الحساسة.
- كل بطاقة تعرض المطلوب، السبب، الموعد، المُعدّ، مصدر البيانات، آخر تحديث، وماذا يحدث بعد الإجراء.
- دعم Deep Links وPush دون كشف بيانات حساسة على شاشة القفل.

### Executive Enterprise Inbox

تصنيفات ثابتة للمدير التنفيذي:

- `critical_now`
- `decision_today`
- `review_required`
- `information_only`
- `scheduled_reports`
- `risk_alerts`
- `location_requests`
- `returned_for_clarification`

يدعم Snooze منظمًا، Delegation موثقة، Annotation، Voice Note to Draft، وStep-up Authentication.

## 13. Command Palette والبحث المؤسسي

أنشئ Command Palette على Web وFlutter تسمح بتنفيذ الأوامر المصرح بها:

- فتح موظف أو تقرير.
- إنشاء طلب أو موظف.
- إرسال قرار.
- عرض المتأخرين.
- فتح دورة KPI.
- إنشاء لجنة أو مشروع.
- طلب موقع ضمن الصلاحية.

### ضوابط

- الأوامر والنتائج تأتي من الخادم حسب الصلاحيات.
- لا تكشف نتيجة غير مصرح بها حتى في Autocomplete.
- كل أمر حساس يطلب Confirmation وMFA/Reason حسب Catalog.
- دعم بحث Full-text عربي مع Normalization، ومرشحات وRecent Items آمنة.

## 14. Position, Headcount & Capacity Management

### 14.1 نموذج المناصب

افصل بين:

- Person/Employee.
- Job Title.
- Job Family.
- Position.
- Job Grade.
- Organizational Unit.
- Acting Assignment.

المنصب يمكن أن يكون معتمدًا، شاغرًا، مجمدًا، مشغولًا، أو مشغولًا بالإنابة.

### 14.2 Headcount Planning

- العدد الحالي والمعتمد والمطلوب.
- الشواغر والفجوات.
- خطة شهرية وسنوية.
- ميزانية المنصب ومركز التكلفة.
- تأثير التعيين والنقل والاستقالات.
- سيناريوهات Baseline/Growth/Constraint.
- Workflow اعتماد الخطة والتعديلات.

### 14.3 Capacity Planning

- الساعات المتاحة مقابل الطلب.
- أثر الورديات والإجازات والمشروعات.
- حمل كل فريق وموظف.
- Over-allocation وUnder-utilization.
- Single Points of Failure.
- توصيات نقل مؤقت بشرية الاعتماد.

### 14.4 التغطية والبدلاء

- بديل أساسي وثانوي لكل منصب حرج.
- جاهزية البديل.
- صلاحيات مؤقتة محددة.
- Handover Checklist.
- السحب التلقائي بعد عودة صاحب الدور.

## 15. Process Intelligence & Process Mining

أنشئ Event Log موحدًا غير قابل للتلاعب لكل عملية:

- `case_id`
- `process_definition_id/version`
- `activity_code`
- `actor_id/role/scope`
- `occurred_at`
- `previous_state/new_state`
- `duration_since_previous`
- `source`
- `correlation_id`
- `metadata_redacted`

### إمكانات Process Mining

- اكتشاف المسار الفعلي.
- مقارنة Conformance بالـSOP المعتمد.
- الاختناقات وأوقات الانتظار.
- إعادة العمل والعودة بين المراحل.
- SLA violations.
- Variants حسب إدارة/نوع طلب.
- فرص الأتمتة.
- Root Cause exploration.

لا تُستخدم النتائج لعقاب موظف تلقائيًا؛ هي أداة لتحسين العملية والمراجعة البشرية.

## 16. Organizational Digital Twin & Scenario Lab

أنشئ نموذجًا رقميًا يربط:

- الموظفين والمناصب والهيكل.
- المهارات والشهادات.
- الورديات والمواقع.
- المشروعات والأهداف.
- الصلاحيات والتفويضات.
- التكلفة والرواتب المجمعة عند الصلاحية.
- المخاطر والبدلاء.

### Scenario Lab

يسمح بإنشاء نسخة افتراضية غير إنتاجية لتجربة:

- نقل موظفين.
- تغيير مدير.
- فتح فرع أو فريق.
- تعديل ورديات.
- تغيير سياسة حضور أو إجازة.
- غياب منصب حرج.
- خفض/زيادة Headcount.

يعرض الأثر على التغطية والتكلفة والأهداف والمخاطر والصلاحيات. لا يطبق السيناريو إلا عبر Change Plan وWorkflow اعتماد.

## 17. Automation Studio & Event-Driven Platform

### 17.1 Event Catalog

أمثلة:

- `employee.created`
- `employee.manager_changed`
- `employee.terminated`
- `attendance.punch.accepted`
- `attendance.risk.flagged`
- `request.submitted`
- `request.approved`
- `kpi.finalized`
- `decision.published`
- `contract.expiring`
- `location.session.expired`

### 17.2 Transactional Outbox

أي حدث مهم يكتب داخل نفس Transaction إلى `outbox_events`، ثم Worker موثوق ينشره مع:

- Idempotency.
- Retry/backoff.
- Dead-letter queue.
- Correlation/causation IDs.
- Delivery logs.

### 17.3 No-Code Automation Rules

صيغة:

`WHEN event IF conditions THEN actions`

Actions:

- إنشاء مهمة.
- إرسال Notification.
- فتح Workflow.
- إنشاء تقرير.
- تحديث حقل مصرح.
- استدعاء Connector.
- تصعيد أو Reminder.

### ضوابط الأتمتة

- Draft → Test → Review → Approved → Active → Paused → Retired.
- Dry Run على بيانات تاريخية.
- Preview Impact.
- Loop Detection.
- Rate Limits.
- Sensitive actions تحتاج Human Approval.
- Kill Switch.
- Versioning وRollback.
- لا تسمح الأتمتة بتجاوز RLS أو SoD.

## 18. Service Catalog & Case Orchestration

### 18.1 Service Catalog

فئات:

- HR.
- IT.
- Operations.
- Administration.
- Finance عند التفعيل.

كل خدمة تحتوي:

- Owner.
- Eligibility.
- Form schema.
- Required documents.
- SLA.
- Workflow.
- Fulfillment tasks.
- Knowledge articles.
- Satisfaction survey.

### 18.2 Case Orchestration

للحالات المعقدة: نزاع، تحقيق، حادث، إنهاء خدمة، مشكلة متعددة الإدارات.

القضية تجمع:

- الأطراف والأدوار.
- Sub-workflows.
- الجلسات.
- الأدلة.
- المهام والمواعيد.
- القرارات والتوقيعات.
- السرية والـLegal Hold.
- Timeline غير قابل للتلاعب.

## 19. Immutable Evidence Vault & Digital Trust

### 19.1 Evidence Vault

للفيديو والمستندات والعقود والمحاضر والأدلة:

- Hash قوي.
- MIME/type validation.
- Malware scanning عند توفر خدمة.
- Uploader ووقت خادمي.
- Chain of Custody.
- Access log.
- Watermark عند العرض حسب السياسة.
- Signed URLs قصيرة.
- Retention وLegal Hold.
- لا استبدال للأصل؛ إصدار جديد فقط.

### 19.2 Multi-party Signatures

- Passkey أو OTP أو توقيع إلكتروني معتمد حسب نوع المستند.
- تسلسل أو توازي.
- توقيع الموظف والمدير وHR والسكرتير والتنفيذي واللجنة.
- Timestamp، نسخة المستند، Hash، سبب الرفض.
- Revocation/Amendment عبر إجراء موثق.

### 19.3 Document Generation

Templates Versioned لإنشاء القرارات والمحاضر والعقود والخطابات والشهادات والتقارير، مع QR verification وReference Number وأرشفة تلقائية.

## 20. Digital SOP Runner & Enterprise Process Library

كل SOP تُعرّف كعملية قابلة للتنفيذ:

- الهدف والمالك.
- النسخة وتاريخ السريان.
- الخطوات والأدوار.
- المدخلات والمخرجات.
- الأدلة المطلوبة.
- SLA وControls.
- الاستثناءات.
- KPI للعملية.

Digital SOP Runner ينشئ Instance ويتابع إكمال كل خطوة، ولا يسمح بتجاوز خطوة إلزامية بلا Exception معتمد.

## 21. Quality Management, CAPA & Internal Audit

### 21.1 Quality/CAPA

- Observation/Non-conformity.
- Severity.
- Root Cause.
- Corrective Action.
- Preventive Action.
- Owner/Due Date.
- Evidence.
- Effectiveness Review.
- Closure approval.

### 21.2 Internal Audit

- خطة سنوية.
- Audit Universe.
- Scope وChecklist.
- Samples وEvidence.
- Findings وتصنيفها.
- Recommendations.
- Management Response.
- CAPA follow-up.
- PDF report.

### 21.3 Compliance Calendar

يجمع العقود والشهادات والصلاحيات والنسخ الاحتياطية واختبارات الاستعادة وKPI والتدقيق والمخاطر والتدريب.

## 22. Executive Meeting, Briefing & Calendar Intelligence

### 22.1 Briefing Room

يجهز السكرتير حزمة مشفرة قصيرة العمر تحتوي تقارير وقرارات ومخاطر ومحاضر. تعمل Offline للقراءة والملاحظات فقط؛ الاعتماد الحساس يتطلب اتصالًا ومصادقة.

### 22.2 Meeting Mode

- Agenda.
- أوراق العمل.
- Previous actions.
- عرض Chart/Report.
- تسجيل قرار وتصويت.
- إنشاء Action Items.
- مسودة محضر.
- unresolved items.

### 22.3 Executive Calendar

- الاجتماعات والاعتمادات والتقارير والمراجعات.
- تنبيهات ضغط الجدول والتعارض.
- تجميع الاعتمادات منخفضة المخاطر.
- موعد مراجعة أثر القرار.

## 23. Decision Impact & Benefits Realization

لكل قرار أو مشروع:

- Baseline.
- Expected outcome.
- Target KPI.
- Cost/effort.
- Review date.
- Actual result.
- Variance.
- Lessons learned.

الحالات:

`draft -> approved -> in_execution -> impact_review_due -> effective | needs_amendment | ineffective | retired`

## 24. Notification Intelligence & Attention Budget

- Priority routing.
- Deduplication.
- Bundling.
- Quiet hours.
- Digest daily/weekly.
- Escalation only when needed.
- Delivery fallback.
- Read/Action analytics.
- Sensitive Push redaction.

تصنف الأحداث إلى:

- Immediate critical.
- Today action.
- Daily digest.
- Weekly insight.
- Silent in-app.

يستطيع الأدمن تعريف Budget للتنبيهات غير العاجلة لكل Persona، دون كتم عناصر قانونية أو أمنية إلزامية.

## 25. Data Governance & Knowledge Graph

### 25.1 Data Catalog

لكل Data Element:

- Owner/Steward.
- Source of truth.
- Classification.
- Retention.
- Allowed purposes.
- Consumers.
- Quality rules.
- Lineage.

### 25.2 Data Contracts

نسخ مثل `employee_profile.v1`, `attendance_daily.v1`, `kpi_result.v1` مع Compatibility Tests.

### 25.3 Data Quality Rules Builder

- Validation.
- Severity.
- Auto-fix/Manual review.
- Waiver مع انتهاء.
- Quality score.

### 25.4 Knowledge Graph

علاقات الموظف والمنصب والمهارات والمشروعات والقرارات والقضايا والسياسات، مع Query APIs تحترم RLS.

### 25.5 Organizational Memory

Offboarding knowledge transfer، ملفات الإجراءات، Lessons Learned، ومسؤولية تحديث المعرفة.

## 26. AI Governance & Human Decision Ledger

### 26.1 AI Use Case Registry

لكل استخدام:

- Purpose.
- Data categories.
- Risk tier.
- Model/provider/version.
- Prompt/version.
- Evaluation metrics.
- Human oversight.
- Prohibited uses.
- Rollback/Kill switch.

### 26.2 Model Registry

يشمل النماذج الإحصائية والقواعد الذكية وRisk Scores.

### 26.3 Human Decision Ledger

يسجل اقتراح AI، تفسيره، البيانات المستخدمة، قرار الإنسان، السبب، والنتيجة اللاحقة.

### 26.4 AI Safety Rules

- RLS/Field permissions قبل الاسترجاع.
- Redaction قبل مزود خارجي.
- لا تدريب على بيانات المؤسسة دون اتفاق صريح.
- Citations داخل المساعد إلى السياسة أو التقرير المصدر.
- لا قرارات HR عالية الأثر تلقائية.
- اختبار Hallucination, privacy leakage, bias, prompt injection.

## 27. Product Adoption, Training & Feedback

### 27.1 Sandbox Training Mode

بيانات وهمية منفصلة وWatermark واضح، ولا اتصال بProduction.

### 27.2 Guided Tours

حسب الدور والWorkspace مع Checklist onboarding.

### 27.3 Feature Adoption Analytics

- استخدام الميزة.
- Drop-off.
- Time to complete.
- Errors.
- Performance.
- دون تسجيل محتوى حساس أو keystrokes.

### 27.4 Product Feedback

اقتراح/خطأ/UX مع Screenshot اختياري بعد الموافقة، وتحويل إلى Backlog دون كشف PII.

## 28. Release, Resilience & Technical Operations

### 28.1 Release Readiness Dashboard

- Unit/Integration/E2E/RLS.
- Security scan.
- Accessibility.
- Performance budgets.
- Migration dry run.
- Backup وRestore evidence.
- Rollback.
- Signed builds.
- Open P0/P1.

### 28.2 Post-release Control Room

- Crash/error rate.
- Login/punch failures.
- Push delivery.
- Edge/DB latency.
- Queue/dead letters.
- Sync failures.
- Adoption and regressions.

### 28.3 Contract Testing

بين Flutter/React/Edge/RPC/Reports/Webhooks.

### 28.4 Chaos & Resilience Tests

انقطاع الشبكة، بطء DB، فشل Push/Storage/Cron، Token expiry، duplicated events، disk pressure، GPS unavailable.

### 28.5 Mobile Device Health

إصدار التطبيق، الصلاحيات، Push، GPS، biometrics، last sync، trusted device. لا تستخدم Root/Jailbreak signal وحده لاتخاذ جزاء.

## 29. Permissions الجديدة

أضف Catalog تفصيليًا على الأقل:

- `actions.center.read`, `actions.batch.execute`
- `positions.manage`, `headcount.plan`, `capacity.read`, `capacity.manage`
- `process_mining.read`, `process_definition.manage`
- `digital_twin.read`, `scenario.create`, `scenario.approve_apply`
- `automation.rule.manage`, `automation.rule.approve`, `automation.run.read`
- `service_catalog.manage`, `case.orchestrate`
- `evidence.read`, `evidence.export`, `evidence.legal_hold`
- `signature.request`, `signature.verify`, `documents.template.manage`
- `quality.finding.manage`, `capa.approve`, `audit.plan.manage`
- `meeting.manage`, `executive.briefing.prepare`
- `decision.impact.review`
- `data.catalog.manage`, `data.quality.manage`, `data.lineage.read`
- `ai.registry.manage`, `ai.audit.read`, `ai.kill_switch`
- `release.readiness.read`, `release.approve`

كل صلاحية مرتبطة بـScope وRisk وMFA وReason وSoD.

## 30. الجداول الجديدة المطلوبة

على الأقل:

- `action_items`, `action_item_assignments`, `action_item_events`
- `positions`, `position_assignments`, `headcount_plans`, `capacity_snapshots`, `coverage_plans`
- `process_definitions`, `process_event_logs`, `process_variants`, `process_conformance_results`
- `digital_twin_scenarios`, `scenario_changes`, `scenario_impacts`, `change_plans`
- `event_catalog`, `outbox_events`, `event_deliveries`, `dead_letter_events`
- `automation_rules`, `automation_versions`, `automation_runs`, `automation_action_results`
- `service_definitions`, `service_requests`, `case_files`, `case_participants`, `case_timelines`
- `evidence_objects`, `evidence_hashes`, `evidence_access_logs`, `legal_holds`
- `signature_requests`, `signature_parties`, `signature_events`, `signed_documents`
- `sop_definitions`, `sop_versions`, `sop_instances`, `sop_step_runs`
- `quality_findings`, `root_cause_analyses`, `capa_actions`, `effectiveness_reviews`
- `audit_plans`, `audit_engagements`, `audit_findings`, `audit_responses`
- `meeting_agendas`, `meeting_items`, `meeting_decisions`, `meeting_action_items`
- `decision_impact_reviews`, `benefit_realization_records`
- `data_catalog_entries`, `data_contracts`, `data_quality_rules`, `data_quality_results`, `data_lineage_edges`
- `knowledge_nodes`, `knowledge_edges`, `lessons_learned`
- `ai_use_cases`, `ai_models`, `ai_prompt_versions`, `ai_evaluations`, `human_decision_ledger`
- `feature_adoption_events`, `product_feedback`
- `release_readiness_runs`, `resilience_test_runs`

## 31. عقود Backend وEdge/RPC

أنشئ Contracts موثقة للعمليات الحساسة، منها:

- `resolve_user_workspaces`
- `get_universal_action_center`
- `execute_action_item`
- `simulate_org_scenario`
- `approve_scenario_change_plan`
- `publish_outbox_events`
- `execute_automation_rule`
- `create_evidence_upload_session`
- `verify_evidence_integrity`
- `request_multi_party_signature`
- `start_sop_instance`
- `record_process_event`
- `run_data_quality_checks`
- `generate_executive_briefing`
- `record_human_ai_decision`

كل Contract يحدد Auth, permission, scope, input schema, output schema, idempotency, audit, rate limit, errors.

## 32. شاشات V8

### Flutter

- Universal Actions.
- Executive Enterprise Inbox.
- Briefing Room.
- Meeting Mode.
- Position/Career view المصرح.
- Skills Passport.
- Digital Employee ID.
- Service Catalog.
- Case Timeline.
- Notifications Digest.

### React

- Position & Headcount Studio.
- Capacity Dashboard.
- Process Explorer.
- Digital Twin Scenario Lab.
- Automation Studio.
- Service Catalog Builder.
- Evidence Vault.
- Document/Signature Studio.
- SOP Library & Runner.
- Quality/CAPA.
- Internal Audit.
- Data Governance Center.
- AI Governance Center.
- Release Readiness & Control Room.

## 33. الرسوم والتحليلات

أضف:

- Process Map وVariant Explorer.
- Capacity vs Demand.
- Span of Control.
- Position Vacancy Funnel.
- Skills Heatmap.
- Risk Heatmap.
- Decision Impact Before/After.
- Automation Success/Failure.
- Data Quality Trend.
- Audit Findings Aging.
- Notification Attention Load.
- Scenario Comparison.

كل Chart له تعريف ومعادلة ومصدر وLast Updated وبديل جدولي.

## 34. خارطة التنفيذ الملزمة

### Phase 0 — Security & Truth

تدوير الأسرار، SQL P0 remediation، توحيد المصادر، RLS tests.

### Phase 1 — Unified Foundation

Flutter واحد، React واحدة، Workspace Resolver، Identity, RBAC+ABAC, Design System, Audit, Outbox foundation.

### Phase 2 — Core HR Vertical Slices

Employees, Attendance, Requests, KPI, Official Feed, Reports, Executive Workspace.

### Phase 3 — Operational Management

Tasks, Projects, Meetings, Decisions, Risks, Service Catalog, Cases.

### Phase 4 — Governance & Automation

Universal Action Center, Position/Headcount, SOP, CAPA, Internal Audit, Automation Studio.

### Phase 5 — Process & Data Intelligence

Process Mining, Digital Twin, Scenario Lab, Data Governance, Knowledge Graph.

### Phase 6 — Advanced HR Lifecycle

ATS, Onboarding, Learning, Skills, Succession, Payroll gated, Offboarding.

### Phase 7 — Responsible AI & Enterprise Resilience

AI Governance, assistants, forecasts, Release Control, Chaos/DR.

## 35. Definition of Done V8

لا تعتبر وحدة مكتملة دون:

1. Approved requirements and workflow.
2. Schema/migration/idempotent seed.
3. RLS/ABAC/field security tests.
4. RPC/Edge contract and audit.
5. Flutter/React UI حسب الحاجة.
6. Loading/empty/error/offline/accessibility.
7. Unit/Integration/E2E/contract tests.
8. Observability and runbook.
9. Retention/privacy classification.
10. Acceptance scenarios passed.
11. Documentation and data lineage.
12. No open P0/P1.

## 36. Non-goals للإصدار الأول

لا تنفذ في Release 1:

- Chat داخلي كامل.
- Payroll Production قبل مراجعة قانونية ومالية.
- AI عالي الأثر لاتخاذ قرارات موظفين.
- Multi-tenant تجاري كامل.
- تتبع موقع سري أو غير محدد المدة.
- كل وحدات V8 في Big Bang.

# نهاية Master Prompt V8

