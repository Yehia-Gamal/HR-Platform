# خطة: تحسين وتطوير صفحة الهيكل التنظيمي (ويب + موبايل)

## المشاكل الحالية

### ويب (OrgChartPage.tsx + styles.css):
1. التخطيط الأفقي مع zoom/pan غير مناسب للموبايل — يصبح canvas صغيرًا يصعب تصفحه
2. `@media (max-width: 768px)` يصغّر البطاقات فقط لكن يُبقي التخطيط الأفقي
3. لا يدعم touch events (فقط mouse events للـ pan)
4. أزرار zoom/pan تشغل مساحة على شاشة صغيرة بلا داعٍ

### موبايل Flutter (org_chart_page.dart):
1. يستخدم `get_mobile_org_chart` (شجرة أقسام) بدل `get_admin_org_chart` (شجرة هرمية للموظفين)
2. يعرض شجرة أقسام وليس مدير → مرؤوسين
3. البطاقات غير قابلة للنقر (لا تنقل لصفحة الموظف)
4. لا توجد بطاقات إحصائيات (فقط نص مضمن)
5. لا يوجد "غير محدد" للحقول الفارغة

---

## الجزء 1: تحسين الويب — CSS متجاوب ذكي

### تعديل: `apps/admin_web/src/styles.css`

**إضافة `@media (max-width: 768px)` شامل:**
- إخفاء شريط أدوات zoom/pan (`.org-controls-toolbar`)
- إخفاء الـ viewport القابل للتكبير (`.org-tree-viewport`)
- عرض الشجرة كقائمة عمودية مسطحة (vertical indented list) بدل التخطيط الأفقي
- تبديل `.org-children-row` من `flex-wrap` أفقي إلى `flex-direction: column` عمودي
- تحويل خطوط الربط من أفقية إلى عمودية جانبية (مثل مستكشف الملفات)
- البطاقات بعرض كامل (`width: 100%`, `min-width: unset`)
- تقليل المسافات والـ padding
- البطاقة تكدّ الصورة فوق النص بدل جنب بعض

**إضافة `@media (max-width: 480px)`:**
- تقليل حجم الصورة (avatar sm بدل md)
- تقليل الخطوط أكثر
- إخفاء حقل الكود (`employeeCode`) لتوفير المساحة

### تعديل: `apps/admin_web/src/features/management/OrgChartPage.tsx`

- إضافة كشف الشاشة (`useIsMobile` hook بسيط: `window.innerWidth < 768`)
- على الموبايل: إخفاء شريط zoom/pan + عرض الشجرة مباشرة بدون viewport
- على الموبايل: تعطيل mouse pan handlers
- تحسين `EmployeeCardNode`: على الموبايل، عرض البطاقة بشكل مضغوط (avatar + name + title فقط)

---

## الجزء 2: تحسين الموبايل Flutter — شجرة هرمية حقيقية

### إعادة كتابة: `apps/mobile_flutter/lib/features/mobile_pages/org_chart_page.dart`

**التغييرات الجوهرية:**

1. **تبديل RPC**: من `get_mobile_org_chart` إلى `get_admin_org_chart` — شجرة هرمية للموظفين (مدير → مرؤوسين)

2. **نموذج بيانات جديد**: استبدال `_OrgDepartment`/`_OrgEmployee`/`_OrgChartData` بـ:
   - `OrgEmployee`: id, fullNameAr, fullNameEn, photoUrl, jobTitle, departmentName, employeeCode, managerEmployeeId, directReportsCount, depth, path, status
   - `OrgChartData`: `{ employees: List<OrgEmployee> }`

3. **بناء شجرة هرمية client-side**: دالة `buildOrgTree(employees)` تبني `List<TreeNode>` حيث كل عقدة `{ employee, children }` — نفس منطق الويب

4. **بطاقات إحصائيات**: شبكة 2×2 في الأعلى:
   - إجمالي الموظفين
   - عدد المديرين
   - أقصى عمق هرمي
   - متوسط المرؤوسين

5. **بطاقة موظف قابلة للنقر**: `EmployeeCard` مع:
   - `AppAvatar` (radius 22)
   - اسم + مسمى وظيفي + قسم + كود
   - badge عدد المرؤوسين (إن وجد)
   - النقر ينتقل لصفحة تفاصيل الموظف (إن وُجدت صفحة mobile) أو يعرض bottom sheet بالتفاصيل
   - "غير محدد" للحقول الفارغة

6. **شجرة مطوية قابلة للتوسيع**:
   - كل مدير له زر توسيع/طي
   - العمق الافتراضي الموسّع: 2 مستويات
   - أزرار "توسيع الكل / طي الكل"
   - مسارين بدل بادئة بسيطة: خط عمودي ملوّن حسب العمق (مثل الويب)

7. **بحث محسّن**: عند البحث، عرض نتائج مسطحة مع إظهار سياق المدير

8. **تصميم محسّن**:
   - بطاقة المدير الأعلى: تدرّج لوني مميز
   - شريط لوني جانبي حسب العمق (أزرق/بنفسجي/أخضر)
   - بطاقات ذات ظل خفيف وزوايا مدوّرة
   - badge عدد المرؤوسين بشكل دائري ملوّن

---

## الجزء 3: تحسينات إضافية

### ويب:
- إضافة touch event support للـ pan على الأجهزة اللوحية
- تحسين `fitToScreen` ليعمل بشكل أفضل مع RTL
- إضافة keyboard shortcut: `+`/`-` للتكبير، `0` لإعادة التعيين

### Flutter:
- إضافة `RefreshIndicator` pull-to-refresh
- إضافة animation عند التوسيع/الطي (AnimatedSize)
- إضافة `hero` transition للصورة عند النقر

---

## ملفات التعديل

| الملف | النوع | التغيير |
|------|------|--------|
| `apps/admin_web/src/styles.css` | تعديل | إضافة `@media` شامل للموبايل + تبديل تخطيط عمودي |
| `apps/admin_web/src/features/management/OrgChartPage.tsx` | تعديل | كشف الموبايل + إخفاء zoom/pan + تخطيط محمول |
| `apps/mobile_flutter/lib/features/mobile_pages/org_chart_page.dart` | إعادة كتابة | RPC جديد + شجرة هرمية + بطاقات + إحصائيات |

## الاختبارات
- `npx vitest run` — للتأكد من عدم كسر اختبارات الويب
- `npx tsc --noEmit` — للتأكد من الأنواع
- `flutter analyze` — للتأكد من عدم أخطاء Dart
- `flutter analyze` للملف المُعاد كتابته فقط للتأكد من سلامته