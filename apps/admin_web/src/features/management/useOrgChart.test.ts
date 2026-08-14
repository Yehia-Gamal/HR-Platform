import { describe, expect, it } from 'vitest';
import type { OrgChartEmployee } from '@ahla/shared-contracts';

// نستورد الدوال المساعدة مباشرة عبر اختبار الوحدة
// (لا يمكن استيراد useOrgChart نفسه لأنه يحتاج React context)
// لذا نختبر منطق بناء الشجرة والإحصائيات بشكل مستقل.

function buildOrgTree(employees: OrgChartEmployee[]): Array<{
  employee: OrgChartEmployee;
  children: ReturnType<typeof buildOrgTree>;
}> {
  const map = new Map<string, { employee: OrgChartEmployee; children: ReturnType<typeof buildOrgTree> }>();
  for (const emp of employees) {
    map.set(emp.id, { employee: emp, children: [] });
  }
  const roots: Array<{ employee: OrgChartEmployee; children: ReturnType<typeof buildOrgTree> }> = [];
  for (const node of map.values()) {
    const mgrId = node.employee.managerEmployeeId;
    if (mgrId && map.has(mgrId)) {
      map.get(mgrId)!.children.push(node);
    } else {
      roots.push(node);
    }
  }
  return roots;
}

function computeStats(employees: OrgChartEmployee[]) {
  if (employees.length === 0) {
    return { totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 };
  }
  const managersCount = employees.filter((e) => e.directReportsCount > 0).length;
  const maxDepth = Math.max(...employees.map((e) => e.depth));
  const totalReports = employees.reduce((sum, e) => sum + e.directReportsCount, 0);
  const avgDirectReports = managersCount > 0 ? +(totalReports / managersCount).toFixed(1) : 0;
  return { totalEmployees: employees.length, managersCount, maxDepth, avgDirectReports };
}

const UUID = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

function makeEmployee(overrides: Partial<OrgChartEmployee> & { id: string }): OrgChartEmployee {
  return {
    fullNameAr: 'موظف',
    fullNameEn: null,
    photoUrl: null,
    jobTitle: '',
    departmentName: '',
    employeeCode: 'EMP-0',
    departmentId: null,
    status: 'active',
    managerEmployeeId: null,
    directReportsCount: 0,
    depth: 0,
    path: [],
    ...overrides,
  };
}

describe('buildOrgTree', () => {
  it('يبني شجرة من عقدة جذر واحدة', () => {
    const root = makeEmployee({ id: UUID(1), fullNameAr: 'المدير العام' });
    const tree = buildOrgTree([root]);
    expect(tree).toHaveLength(1);
    expect(tree[0].employee.id).toBe(UUID(1));
    expect(tree[0].children).toHaveLength(0);
  });

  it('يربط المرؤوسين بمديريهم', () => {
    const root = makeEmployee({ id: UUID(1), directReportsCount: 2 });
    const child1 = makeEmployee({ id: UUID(2), managerEmployeeId: UUID(1) });
    const child2 = makeEmployee({ id: UUID(3), managerEmployeeId: UUID(1) });
    const tree = buildOrgTree([root, child1, child2]);
    expect(tree).toHaveLength(1);
    expect(tree[0].children).toHaveLength(2);
    expect(tree[0].children[0].employee.id).toBe(UUID(2));
    expect(tree[0].children[1].employee.id).toBe(UUID(3));
  });

  it('يدعم هرمية متعددة المستويات', () => {
    const root = makeEmployee({ id: UUID(1), directReportsCount: 1 });
    const mid = makeEmployee({ id: UUID(2), managerEmployeeId: UUID(1), directReportsCount: 1 });
    const leaf = makeEmployee({ id: UUID(3), managerEmployeeId: UUID(2) });
    const tree = buildOrgTree([root, mid, leaf]);
    expect(tree).toHaveLength(1);
    expect(tree[0].children).toHaveLength(1);
    expect(tree[0].children[0].children).toHaveLength(1);
    expect(tree[0].children[0].children[0].employee.id).toBe(UUID(3));
  });

  it('يتعامل مع موظفين بلا مدير كجذور متعددة', () => {
    const r1 = makeEmployee({ id: UUID(1) });
    const r2 = makeEmployee({ id: UUID(2) });
    const tree = buildOrgTree([r1, r2]);
    expect(tree).toHaveLength(2);
  });

  it('يتجاهل مرؤوسًا بمدير غير موجود', () => {
    const root = makeEmployee({ id: UUID(1) });
    const orphan = makeEmployee({ id: UUID(2), managerEmployeeId: UUID(999) });
    const tree = buildOrgTree([root, orphan]);
    expect(tree).toHaveLength(2); // الجذر + اليتيم (كجذر ثانٍ)
  });
});

describe('computeStats', () => {
  it('يرجع أصفار لقائمة فارغة', () => {
    const stats = computeStats([]);
    expect(stats).toEqual({ totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 });
  });

  it('يحسب العدد الإجمالي والمديرين', () => {
    const emps = [
      makeEmployee({ id: UUID(1), directReportsCount: 3 }),
      makeEmployee({ id: UUID(2), directReportsCount: 0 }),
      makeEmployee({ id: UUID(3), directReportsCount: 1 }),
      makeEmployee({ id: UUID(4), directReportsCount: 0 }),
    ];
    const stats = computeStats(emps);
    expect(stats.totalEmployees).toBe(4);
    expect(stats.managersCount).toBe(2);
  });

  it('يحسب أقصى عمق', () => {
    const emps = [
      makeEmployee({ id: UUID(1), depth: 0 }),
      makeEmployee({ id: UUID(2), depth: 1 }),
      makeEmployee({ id: UUID(3), depth: 2 }),
      makeEmployee({ id: UUID(4), depth: 3 }),
    ];
    const stats = computeStats(emps);
    expect(stats.maxDepth).toBe(3);
  });

  it('يحسب متوسط المرؤوسين', () => {
    const emps = [
      makeEmployee({ id: UUID(1), directReportsCount: 4 }),
      makeEmployee({ id: UUID(2), directReportsCount: 2 }),
      makeEmployee({ id: UUID(3), directReportsCount: 0 }),
    ];
    const stats = computeStats(emps);
    expect(stats.avgDirectReports).toBe(3); // (4+2) / 2 managers
  });
});
