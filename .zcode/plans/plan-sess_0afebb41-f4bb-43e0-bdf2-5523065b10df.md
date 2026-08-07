# خطة: صفحة الهيكل التنظيمي الإداري (Org Chart)

## الهدف
صفحة ويب جديدة تعرض **شجرة هرمية حقيقية للموظفين** (مدير → مرؤوسون مباشرون بشكل متكرر) ببطاقات متفرعة مع خطوط ربط بصرية. احترافية وعصرية.

---

## الجزء 1: Backend — RPC جديد `get_admin_org_chart`

### ملف جديد: `supabase/migrations/0313_admin_org_chart_rpc.sql`

يُنشئ دالة `get_admin_org_chart()` تُرجع JSONB يحتوي على:

```
{
  "employees": [
    {
      "id", "fullNameAr", "fullNameEn", "photoUrl",
      "jobTitle", "departmentName", "employeeCode",
      "managerEmployeeId",   // المدير المباشر (null للمدير الأعلى)
      "directReportsCount",   // عدد المرؤوسين المباشرين
      "depth",                // عمق في الشجرة (0 للجذر)
      "path",                 // مسار هرمي للترتيب
      "departmentId", "status"
    }
  ]
}
```

**الاستعلام SQL:**
- `WITH RECURSIVE` CTE يمشي على `manager_relations` (حيث `relation_type='primary'` AND `effective_to IS NULL`)
- الجذر: موظفون ليس لديهم مدير رئيسي نشط
- التكرار: `JOIN manager_relations mr ON mr.manager_employee_id = emp.id`
- انضمام لـ `employees` + `job_titles` + `departments` للاسم/الصورة/المسمى/القسم
- فلترة: `is_active=true AND is_deleted=false AND status IN ('active','onboarding','probation_failed')`
- `SECURITY DEFINER`, guard بصلاحية `organization.org_chart.read`
- `GRANT EXECUTE TO authenticated`

---

## الجزء 2: عقد مشترك (Shared Contract)

### ملف جديد: `packages/shared-contracts/src/orgChart.ts`

```ts
export interface OrgChartEmployee {
  id: string;
  fullNameAr: string;
  fullNameEn: string | null;
  photoUrl: string | null;
  jobTitle: string;
  departmentName: string;
  employeeCode: string;
  managerEmployeeId: string | null;
  directReportsCount: number;
  depth: number;
  path: string[];
  departmentId: string | null;
  status: string;
}
export const orgChartEmployeeSchema: z.ZodType<OrgChartEmployee>;
export const orgChartResponseSchema: z.ZodType<{ employees: OrgChartEmployee[] }>;
```

---

## الجزء 3: Hook للجلب

### ملف جديد: `apps/admin_web/src/features/management/useOrgChart.ts`

```ts
export function useOrgChart(search?: string) {
  // useQuery → rpc('get_admin_org_chart')
  // فلترة بحث محلية (client-side) على الاسم/المسمى/الكود
  // إرجاع: { tree, flatList, stats }
}
```

- `tree`: مصفوفة هرمية `{ employee, children: TreeNode[] }` مبنية عبر Map (مثل `buildTree` الموجود في OrganizationPage.tsx:481)
- `stats`: `{ totalEmployees, managersCount, maxDepth, avgDirectReports }`

---

## الجزء 4: صفحة الويب

### ملف جديد: `apps/admin_web/src/features/management/OrgChartPage.tsx`

**هيكل الصفحة:**

1. **PageHeader** — "الهيكل التنظيمي الإداري" + وصف + زر تحديث
2. **MetricCards** (4 بطاقات):
   - إجمالي الموظفين
   - عدد المديرين
   - أقصى عمق هرمي
   - متوسط المرؤوسين
3. **FilterBar** — بحث نصي (اسم/كود/مسمى) + زر "توسيع الكل"/"طي الكل"
4. **شجرة البطاقات المتفرعة** — المكون الرئيسي:

**عقدة البطاقة (EmployeeCardNode):**
```
┌─────────────────────┐
│  [صورة]  اسم الموظف │  ← UserAvatar (lg) + اسم + مسمى وظيفي
│           المسمى     │
│    [عدد المرؤوسين]  │  ← badge لو لديه مرؤوسون
└──────────┬──────────┘
           │              ← خط ربط عمودي
     ┌─────┴─────┐
     │           │         ← خطوط ربط أفقية متفرعة
  [مرؤوس1]   [مرؤوس2]
```

- كل بطاقة: `UserAvatar` (size lg) + اسم + مسمى وظيفي + قسم + عدد مرؤوسين
- بطاقة المدير الأعلى لها تدرج لوني مميز (primary gradient)
- المديرون الذين لديهم مرؤوسون: زر توسيع/طي (chevron)
- خطوط ربط بصرية عبر CSS `::before`/`::after` pseudo-elements
- عند النقر على بطاقة: انتقال لـ `/admin/hr/employees/:id` (EmployeeDetailPage)
- عند البحث: عرض نتائج مسطحة (Grid) بدل الشجرة
- Lazy mount للعقد العميقة (تجنب أداء بطيء)
- EmptyState لو لا توجد بيانات
- ErrorState + retry لو فشل الجلب

**أنماط CSS** في `styles.css`:
- `.org-tree` — حاوية الشجرة
- `.org-node` — بطاقة الموظف
- `.org-connector` — خطوط الربط
- `.org-children` — حاوية الأبناء
- متغيرات ثيم (light/dark mode support)

---

## الجزء 5: التوجيه (Routing)

### تعديل: `apps/admin_web/src/app/App.tsx`

1. إضافة lazy import:
```ts
const OrgChartPage = lazy(() => import('../features/management/OrgChartPage').then((m) => ({ default: m.OrgChartPage })));
```

2. إضافة route في `HrWorkspaceRoutes()`:
```tsx
<Route path="org-chart" element={
  <RequirePermission perm="organization.org_chart.read"><OrgChartPage /></RequirePermission>
} />
```

---

## الجزء 6: القائمة الجانبية (Sidebar)

### تعديل: `apps/admin_web/src/features/workspaces/WorkspaceShell.tsx`

إضافة في `adminSections` → قسم "الموظفون":
```ts
{ label: 'الهيكل الإداري', to: '/admin/hr/org-chart', icon: GitBranch, permission: 'organization.org_chart.read' },
```
(`GitBranch` من lucide-react — أيقونة شجرة هرمية مناسبة)

---

## الجزء 7: اختبارات

### ملف جديد: `apps/admin_web/src/features/management/OrgChartPage.test.tsx`

- بناء الشجرة من بيانات وهمية
- فلترة البحث
- توسيع/طي العقد
- عرض حالة فارغة
- روابط لصفحة الموظف

---

## ملخص الملفات

| النوع | الملف |
|------|------|
| جديد | `supabase/migrations/0313_admin_org_chart_rpc.sql` |
| جديد | `packages/shared-contracts/src/orgChart.ts` |
| جديد | `apps/admin_web/src/features/management/useOrgChart.ts` |
| جديد | `apps/admin_web/src/features/management/OrgChartPage.tsx` |
| جديد | `apps/admin_web/src/features/management/OrgChartPage.test.tsx` |
| تعديل | `apps/admin_web/src/app/App.tsx` (route + lazy import) |
| تعديل | `apps/admin_web/src/features/workspaces/WorkspaceShell.tsx` (sidebar) |
| تعديل | `apps/admin_web/src/styles.css` (أنماط الشجرة) |
| تعديل | `packages/shared-contracts/src/index.ts` (export) |

## المكونات المُعاد استخدامها
- `UserAvatar` (مع `useResolvedAvatarUrl` الجديد)
- `PageHeader`, `MetricCard`, `FilterBar`, `EmptyState`, `ErrorState`
- `rpc` helper
- `RequirePermission`
- `hasPermission` from `accessService`

## المزايا
- شجرة هرمية حقيقية (مدير → مرؤوسون) وليست شجرة أقسام
- بطاقات مع صور (تحمل من bucket خاص)
- خطوط ربط بصرية احترافية
- بحث فوري + توسيع/طي
- إحصائيات سريعة
- دعم RTL + light/dark mode
- lazy loading للأداء
- اختبارات شاملة