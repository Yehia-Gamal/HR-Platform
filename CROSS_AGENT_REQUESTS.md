# Cross-Agent Requests — أحلى شباب HR V23

> يُسجَّل هنا كل طلب تعديل ملف مملوك لوكيل آخر.
> لا يُنفَّذ الطلب دون موافقة صاحب الملف + Integration Lead (وكيل 14).

## القالب

```markdown
### REQ-XXXX: [وصف مختصر]
- **من:** وكيل [رقم] — [اسم]
- **إلى:** وكيل [رقم] — [اسم]
- **الملف المطلوب تعديله:** [المسار]
- **التعديل المطلوب:** [وصف دقيق]
- **السبب:** [لماذا لا يمكن حله داخل نطاقك]
- **الأولوية:** P0 / P1 / P2
- **الحالة:** 🟡 مقدم | 🟢 معتمد | 🔴 مرفوض | ✅ منفذ
- **تاريخ التقديم:** YYYY-MM-DD
- **تاريخ القرار:** —
- **ملاحظات:** —
```

---

## الطلبات النشطة

### REQ-0001: عقد بيانات الحضور الشهري — مزامنة attendance_daily.status
- **من:** وكيل 04 — Attendance, Geofence & Shifts
- **إلى:** وكيل 12 — Reports & Monthly Statement
- **الملف المطلوب تعديله:** لا يوجد تعديل ملف — طلب مزامنة عقد بيانات فقط
- **التعديل المطلوب:**
  - `attendance_daily.status` أُضيفت قيمة جديدة `'missing_checkout'` (هجرة 0160).
  - يجب أن يعالج كشف الحضور الشهري هذه الحالة (عرضها كـ "بصمة خروج مفقودة" أو ما يناسب).
  - العقد المشترك في `packages/shared-contracts/src/attendanceConfig.ts` يصدِّر `attendanceDailyStatus` enum يحتوي جميع القيم.
  - العقد المشترك في `packages/shared-contracts/src/operations.ts` يحتوي `attendanceStatementDaySchema` بحقل `missingCheckOut: z.boolean()` — لا تغيير مطلوب.
  - الجدول الجديد `attendance_settings` (singleton) يحتوي `timezone` و`missing_checkout_grace_minutes` — متاحان للقراءة.
  - الدالة `finalize_missing_checkouts()` تُنشئ `attendance_exception` من نوع `'missing_check_out'` — يمكن استخدامها في التقارير.
- **السبب:** الحالة الجديدة تؤثر على إحصائيات الكشف الشهري (missingCheckOutCount) وعلى حساب أيام الحضور الفعلي.
- **الأولوية:** P1
- **الحالة:** 🟡 مقدم
- **تاريخ التقديم:** 2026-07-27
- **تاريخ القرار:** —
- **ملاحظات:** لا يتطلب تعديل ملف — إبلاغ فقط لضمان توافق عقد البيانات.

### REQ-0002: سدّ فجوات الترقيم بعد حذف ملفات مكررة (0313، 0322)
- **من:** وكيل — صيانة عقد بيانات الموظف (360)
- **إلى:** وكيل 02 — Database & Migrations
- **الملف المطلوب تعديله:** `supabase/migrations/*.sql` (ما بعد 0320) + `MIGRATION_REGISTRY.md`
- **التعديل المطلوب:**
  - حذفُك لـ `0313_admin_org_chart_rpc.sql` و`0322_observability_permissions_seed.sql` (محتواهما مكرر عند `0321` و`0327`) ترك فجوتين في المتسلسلة.
  - `node scripts/check-migrations-integrity.mjs` يفشل الآن: `✗ [GAP] لا يوجد migration 0313` و`✗ لا يوجد migration 0322`.
  - المطلوب أحد الخيارين:
    1. إعادة ترقيم المتسلسلة لسدّ الفجوتين بلا فجوات + تحديث `MIGRATION_REGISTRY.md`، أو
    2. توثيق الفجوتين كفجوات مقصودة في `ACCEPTABLE_GAPS` في السكربتين (`scripts/check-migrations-integrity.mjs` و`scripts/validate-foundation.mjs`) + إضافة سطر في `MIGRATION_REGISTRY.md`.
- **السبب:** أرقام migrations مملوكة لوكيل 02. أي ملف أُنشئه الآن لسدّ الفجوات قد يتصادم مع إعادة الترقيم الجارية (خطر التكرار بين المحادثات المتوازية).
- **الأولوية:** P0 — يحجب `npm run check:all`
- **الحالة:** ✅ منفذ
- **تاريخ التقديم:** 2026-08-08
- **تاريخ القرار:** 2026-08-08
- **ملاحظات:** سدّ وكيل 02 الفجوتين بإعادة الترقيم — الفحص الآن: «336 ملف، أرقام 0001–0338، بلا تكرار أو فجوات». `scripts/validate-foundation.mjs` عُدّل من طرفي ليستوعب ملفًا حقيقيًا برقم 0279 — لا حاجة لتغيير إضافي عليه بخصوص 0279.

---

## الطلبات المنجزة

### REQ-C001: إصلاح اختبارات KPI V23 — تحديث CONDUCT evaluator
- **من:** وكيل 14 — Integration, Merge, Traceability
- **إلى:** وكيل 08 — KPI Workflow
- **الملف المطلوب تعديله:** `packages/shared-contracts/src/kpi.test.ts`
- **التعديل المطلوب:**
  - تغيير اختبار evaluator ownership (سطر 64-72) من V17 إلى V23
  - V17: `CONDUCT = 'hr'` → V23: `CONDUCT = 'manager'`
  - تحديث وصف الاختبار: "V23 §8: HR owns attendance + prayer + halaqa (30); manager owns target + efficiency + conduct + initiatives (70)"
  - إضافة تغطية شاملة لجميع المعايير السبعة بدلاً من الجزئية
- **السبب:** `kpi.ts` حُدِّث لـ V23 (commit 4380612) لكن الاختبار بقي يتوقع V17. تسبب في فشل 6 اختبارات.
- **الأولوية:** P0
- **الحالة:** ✅ منفذ
- **تاريخ التقديم:** 2026-07-27
- **تاريخ القرار:** 2026-07-27
- **ملاحظات:** نُفِّذ مباشرة بصفتي Integration Lead (صلاحية P0 عاجل). جميع 180 اختبار تنجح بعد الإصلاح.
