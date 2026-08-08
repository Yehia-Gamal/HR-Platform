# خطة: تحسين لوحة الحضور بصرياً ووظيفياً (Web + Mobile)

انتهيت من الاستكشاف الكامل للجانبين. هذه النتائج المؤكدة والخطة المُقسّمة لمراحل — يمكنك اعتماد الكل أو اختيار مرحلة/مراحل بعينها.

## ما وُجد خلال الاستكشاف

**الجوال (`mobile_attendance_page.dart`):** ثلاث خرقات لاتساق نظام التصميم:
- `_WarningBanner` يستخدم `Colors.orange` الخام بدلاً من `AppColors.statusWarning` (`#D98508`).
- `_TodayStatusCard` يستخدم `Color(0xFF0F9F6E)` الخام — وهذا مطابق حرفياً لـ `AppColors.statusSuccess`.
- `_QuickLink` يستخدم `BorderRadius.circular(12)` بينما نظام البطاقات يستخدم **22** (`app_theme.dart:79`).

**الويب (`AttendanceDrilldownPage.tsx`):** خلل بصري حقيقي — الباجات/الجدار تستخدم أصناف CSS غير موجودة:
- `badge`, `badge-success`, `badge-warning`, `badge-danger`, `badge-neutral` (الأسطر 334، 359، 365) — لا توجد. النظام يستخدم `status-pill`/`status-pill--ok|warn|danger|neutral`.
- `btn-sm`, `btn-xs` (الأسطر 164، 176، 252، 374) — لا توجد كأصناف حجم.
- `table` (السطر 281) و`table-container` (السطر 280) — لا توجد؛ يجب استخدام `data-table`.
- `statusBadgeClass()` (الأسطر 82-87) تُرجِع `badge-success`… إلخ.

**الويب (`AttendancePage.tsx`):** ثغرات وظيفية في اللوحة الرئيسية:
- **لا مرشّح تاريخ** — مُثبّت على اليوم (`cairoTodayIso()`).
- **لا مرشّح قسم/فرع** — الأرقام على مستوى المنشأة (التصفية موجودة فقط في صفحة التفاصيل).
- لا تصدير من اللوحة. اللوحة للقراءة فقط.

---

## المرحلة 1 — اتساق بصري للجوال (منخفض المخاطر، ملف واحد)
الملف: `apps/mobile_flutter/lib/features/mobile_pages/mobile_attendance_page.dart`

1. `_WarningBanner`: استبدال `Colors.orange` (و`.shade50`/`.shade900`) بـ `AppColors.statusWarning` للأيقونة/الحدّ، وخلفية ناعمة عبر `AppColors.statusWarning.withValues(alpha: 0.12)`. استيراد `app_colors.dart` إن لزم.
2. `_TodayStatusCard`: استبدال `Color(0xFF0F9F6E)` الخام بـ `AppColors.statusSuccess` (مطابق تماماً).
3. `_QuickLink`: استبدال `BorderRadius.circular(12)` بـ `BorderRadius.circular(22)` ليتوافق مع `cardTheme`.

**النتيجة:** ألوان ونصف قطر متّسقة مع نظام التصميم، دون تغيير سلوك.

## المرحلة 2 — إصلاح الخلل البصري في تفاصيل الحضور بالويب
الملفات: `apps/admin_web/src/features/attendance/AttendanceDrilldownPage.tsx` + `apps/admin_web/src/styles.css`

1. تحديث `statusBadgeClass()` لتُرجِع: `status-pill status-pill--ok` (present) / `--warn` (late) / `--danger` (absent) / `--neutral` (other).
2. تحديث JSX: السطر 334 `badge text-xs` → `status-pill`؛ السطر 359 `badge badge-success` → `status-pill status-pill--ok`؛ السطر 365 `badge badge-neutral` → `status-pill status-pill--neutral`.
3. السطر 281: `<table className="table w-full">` → `<table className="data-table w-full">`.
4. السطر 280: حذف صنف `table-container` (أدوات Tailwind `-m-4 max-h-[65vh] overflow-auto` تتكفّل بالتمرير)، أو الإبقاء بصنف فارغ — يُحسم أثناء التنفيذ.
5. في `styles.css`: **إضافة** أصناف الحجم `.btn-sm` و`.btn-xs` (padding/font أصغر) كأدوات قابلة لإعادة الاستخدام — هذا فجوة حقيقية في النظام تبرر الإضافة بدل حذفها.

## المرحلة 3 — تحسين وظيفي للوحة الحضور بالويب (الأكبر)
الملفات: `AttendancePage.tsx` + `useAttendanceDashboard.ts` + migration (RPC) + `app/App.tsx` للمسار.

1. **مرشّح التاريخ:** إضافة منتقي تاريخ أعلى البطاقات، تمريره كـ `p_date` إلى الـ hook. الـ hook يدعم أصلاً `p_date` (يحتاج التحقق من قبول RPC للتاريخ الماضي).
2. **مرشّح القسم/الفرع:** تحديد ما إذا كان `get_attendance_dashboard` يدعم تصفية حسب القسم/الفرع. إن لم يدعم (المرجّح)، يتطلب هذا **migration** يضيف بارامتر `p_department_id`/`p_branch_id` إلى الـ RPC ويُرشّح السجلات. *سأتحقق من تعريف الـ RPC أولاً ثم أعلمك إن كان يتطلب migration فعلية.*
3. **حالة العطلة/الفراغ:** عرض بطاقة بديلة لطيفة عند `scheduled===0` بدل إخفاء شريط التقدّم فقط.

> ملاحظة المخاطر: المرحلة 3 قد تتطلّب تعديل backend (RPC/migration) لتصفية القسم — وهو ما أتجنّبه إن أمكن. سأقف عند نقطة التحقق وأبلغك.

---

## الإعدادات الموصى بها للاعتماد
- **النطاق الافتراضي المُقترح:** المرحلتان 1 + 2 (إصلاحات بصرية ملموسة ومنخفضة المخاطر، ملفان فقط تقريباً + CSS).
- **إن رغبت بالشق الوظيفي:** أضف المرحلة 3 (مع تنبيه الـ backend).
- **خارج النطاق حالياً (أذكُرها فقط):** توحيد رموز نصف القطر `--radius-*` على الويب (مرّحل واسع لكل المكونات).

## بعد التنفيذ
- تشغيل فحص الأنواع/التحليل: Dart (`flutter analyze` على الحزمة) وTS (`tsc --noEmit` أو أمر lint المعتمد).
- التأكد نظيف ثم إبلاغك بالملخص.

أيّ مرحلة تريد اعتمادها؟ (1+2 موصى به، أو 1+2+3)