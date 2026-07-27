# قيادة حزمة الوكلاء — أحلى شباب HR V22

هذه الحزمة تقسم الخطة إلى 15 مسار عمل متخصص بالإضافة إلى هذا الملف القيادي.

## قواعد مشتركة ملزمة

- المرجع الوظيفي هو خطة V22 المختصرة والمحصنة، وهذه المهمة جزء منها وليست مشروعًا منفصلًا.
- العمل داخل المستودع الحالي ونفس Flutter/Web/Supabase/Firebase/Package Name/Keystore.
- ابدأ بـDiscovery داخل نطاقك قبل التعديل، ولا تفترض أسماء ملفات أو جداول أو دوال.
- لا تعدّل Migration منشورة، ولا تحذف بيانات Production، ولا تعطّل RLS.
- استخدم Migration جديدة باسم Timestamp UTC كامل بعد حجزها في سجل التنسيق.
- لا تعرض بيانات Demo أو نجاحًا وهميًا.
- لا تكتب «تم» دون Root Cause، Commit، Tests، Runtime Evidence، وRollback.
- لا تعدّل ملفات مملوكة لوكيل آخر دون موافقة Orchestrator وتحديث File Ownership Registry.
- كل واجهة جديدة يجب أن ترتبط بخادم فعلي وصلاحيات واختبارات.
- عند خطر فقد بيانات: أوقف الجزء الخطر فقط، سجله في BLOCKERS، واستمر في المهام المستقلة.
- سلّم تقريرًا ختاميًا يتضمن: قبل/بعد، الملفات، المايجريشن، الاختبارات، الصور، السجلات، القيود، وخطوات الرجوع.

# 1. طريقة الاستخدام

لكل شات/وكيل:

1. أرسل له هذا الملف أو الجزء «قواعد مشتركة».
2. أرسل ملف المهمة المتخصصة فقط.
3. أعطه Branch مستقل:
   `agent/<domain>/<task-id>`
4. امنعه من تعديل ملفات خارج النطاق.
5. عيّن Reviewer مختلفًا.
6. لا تدمج أي Branch قبل Integration Queue.

# 2. الملفات والمسؤوليات

| الملف | المسؤولية |
|---|---|
| 01 | Discovery ومعمارية وجرد شامل |
| 02 | قاعدة البيانات والـMigrations وسلامة البيانات |
| 03 | الأمن وRLS والأدوار والصلاحيات |
| 04 | الموظفون والهيكل والتعيينات المتعددة |
| 05 | لوحة Admin وHR والنوافذ المنبثقة ومساحات العمل |
| 06 | الجهاز والبصمة والحضور وGeofence |
| 07 | الإجازات والأذونات والتكليفات والتصحيحات والعطلات |
| 08 | KPI ومساره المتوازي |
| 09 | لجنة المشكلات والجزاءات |
| 10 | هاتف المدير التنفيذي والقرارات والمنشورات والهيكل |
| 11 | طلب الموقع وFCM وAndroid Notifications |
| 12 | كشف الحضور الشهري والتقارير |
| 13 | UI/UX وRTL وTheme وOffline والأداء |
| 14 | QA والأمن واختبارات الحمل والإطلاق |
| 15 | الدمج والتتبع والقبول النهائي |

# 3. موجات التنفيذ

## Wave 0 — يبدأ أولًا

- 01 Discovery.
- لا تغييرات إنتاجية كبيرة قبل تسليم الجرد.

## Wave 1 — الأساسات

- 02 Database.
- 03 Security/RLS.
- 04 Employee Identity.
- يجب الاتفاق على العقود والـEnums والـViews.

## Wave 2 — الويب والوظائف الأساسية

- 05 Web Admin/HR.
- 06 Attendance.
- 07 Leaves/Assignments.
- 08 KPI.
- 09 Disputes.
- 10 Executive.
- 11 Live Location.
- 12 Monthly Statement.
- 13 UI/Performance.

يمكن العمل بالتوازي بعد تثبيت العقود وFile Ownership.

## Wave 3 — التحقق

- 14 QA/Security/Load/Release.

## Wave 4 — الدمج

- 15 Integration/Merge/Traceability.

# 4. ملكية الملفات

أنشئ داخل المشروع:

- `docs/agent_coordination/AGENT_REGISTRY.md`
- `docs/agent_coordination/FILE_OWNERSHIP_LOCKS.json`
- `docs/agent_coordination/MIGRATION_REGISTRY.md`
- `docs/agent_coordination/INTEGRATION_QUEUE.md`
- `docs/agent_coordination/BLOCKERS.md`
- `docs/agent_coordination/SHARED_CONTRACTS.md`

صيغة القفل:

```json
{
  "path_or_glob": "lib/features/attendance/**",
  "owner": "agent-attendance",
  "task_id": "ATT-001",
  "branch": "agent/attendance/ATT-001",
  "expires_at": "ISO-8601",
  "reviewer": "agent-qa-attendance"
}
```

# 5. حجز الـMigration

- الاسم: `YYYYMMDDHHMMSS_description.sql`
- الحجز يكتب في `MIGRATION_REGISTRY.md` قبل إنشاء الملف.
- يمنع Timestamp مكرر في CI.
- كل Migration تحتوي Verification وRollback notes.
- لا Squash لتاريخ Production.

# 6. سياسة الوكلاء الفرعيين

يجوز لكل Lead Agent إنشاء وكلاء فرعيين عند دعم المنصة:

- 1 Lead.
- 2–6 منفذين في ملفات منفصلة.
- 1 Reviewer.
- 1 Tester عند الحاجة.

ممنوع أن يعدل وكيلان الملف نفسه بالتوازي.

# 7. بوابات الدمج

لا يدخل Branch إلى Merge Queue إلا بعد:

- Lint/Analyze.
- Tests الخاصة بالنطاق.
- مراجعة مستقلة.
- تحديث Traceability.
- عدم وجود Secret.
- Migration checks.
- Runtime evidence.
- Rollback.

# 8. قالب الأمر المختصر لكل وكيل

```text
اقرأ ملف المهمة المرفق كاملًا. أنت Lead Agent لهذا النطاق فقط.
ابدأ بجرد الكود الفعلي، ثم أنشئ خطة مهام ذرية وتبعيات وملكية ملفات.
يمكنك إنشاء وكلاء فرعيين بشرط عدم تعديل الملف نفسه بالتوازي.
نفّذ داخل المشروع الحالي، واختبر End-to-End، ولا تعتبر المهمة مكتملة
دون أدلة Runtime وCommit hashes وRollback. لا تتجاوز نطاق الملف.
```

## صيغة التسليم الإلزامية

1. **ملخص التنفيذ**
2. **الأسباب الجذرية**
3. **الملفات المعدلة**
4. **Migrations/RPC/RLS/Edge Functions**
5. **الاختبارات الناجحة والفاشلة**
6. **أدلة Runtime وصور قبل/بعد**
7. **المخاطر والقيود المتبقية**
8. **Commit hashes**
9. **تعليمات الدمج**
10. **Rollback**
