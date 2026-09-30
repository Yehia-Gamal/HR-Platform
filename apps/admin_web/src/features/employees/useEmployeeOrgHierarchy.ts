import { useMemo } from 'react';
import type { OrgChartEmployee, OrgChartTreeNode } from '@ahla/shared-contracts';
import { useOrgChart } from '../management/useOrgChart';

export interface EmployeeOrgHierarchyStats {
  directReportsCount: number;
  totalSubordinatesCount: number;
  managersUnderCount: number;
  maxSubtreeDepth: number;
}

export interface EmployeeOrgHierarchyData {
  employee: OrgChartEmployee;
  ancestors: OrgChartEmployee[]; // سلسلة القيادة من القمة إلى المدير المباشر
  directReports: OrgChartEmployee[]; // المرؤوسون المباشرون
  allSubordinates: OrgChartEmployee[]; // جميع المرؤوسين المباشرين وغير المباشرين
  subTree: OrgChartTreeNode; // الشجرة الهرمية التابعة لجذر الموظف
  stats: EmployeeOrgHierarchyStats;
  isTopLevel: boolean;
  hasSubordinates: boolean;
}

export interface FallbackEmployeeInfo {
  fullNameAr?: string;
  fullNameEn?: string | null;
  photoUrl?: string | null;
  jobTitle?: string | null;
  department?: string | null;
  employeeCode?: string;
  managerName?: string | null;
  managerId?: string | null;
  directReports?: number;
}

export function useEmployeeOrgHierarchy(
  employeeId: string | undefined,
  fallback?: FallbackEmployeeInfo,
): {
  data: EmployeeOrgHierarchyData | undefined;
  isLoading: boolean;
  isError: boolean;
  error: unknown;
  refetch: () => void;
} {
  const orgChart = useOrgChart('');

  const result = useMemo<EmployeeOrgHierarchyData | undefined>(() => {
    if (!employeeId) return undefined;
    const chartData = orgChart.data;
    if (!chartData) return undefined;

    const allEmps = chartData.employees;
    let target = allEmps.find((e) => e.id === employeeId);

    // بناء موظف احتياطي إذا لم يكن موجوداً في مصفوفة الهيكل
    if (!target) {
      target = {
        id: employeeId,
        fullNameAr: fallback?.fullNameAr ?? 'الموظف الحالي',
        fullNameEn: fallback?.fullNameEn ?? null,
        photoUrl: fallback?.photoUrl ?? null,
        jobTitle: fallback?.jobTitle ?? 'موظف',
        departmentName: fallback?.department ?? 'بدون إدارة',
        employeeCode: fallback?.employeeCode ?? '',
        departmentId: null,
        status: 'active',
        managerEmployeeId: fallback?.managerId ?? null,
        directReportsCount: fallback?.directReports ?? 0,
        depth: fallback?.managerId ? 1 : 0,
        path: fallback?.managerId ? [fallback.managerId, employeeId] : [employeeId],
      };
    }

    // 1. سلسلة القيادة الصاعدة (Ancestors)
    const ancestorIds = target.path.filter((id) => id !== target.id);
    const ancestors: OrgChartEmployee[] = [];
    for (const id of ancestorIds) {
      const ancestor = allEmps.find((e) => e.id === id);
      if (ancestor) {
        ancestors.push(ancestor);
      }
    }

    // إذا لم تُكتشف أي أسلاف ولكن هناك مدير مباشر مسجل في البيانات
    if (ancestors.length === 0 && (target.managerEmployeeId || fallback?.managerName)) {
      const directMgr = target.managerEmployeeId ? allEmps.find((e) => e.id === target.managerEmployeeId) : undefined;
      if (directMgr) {
        ancestors.push(directMgr);
      } else if (fallback?.managerName) {
        ancestors.push({
          id: target.managerEmployeeId || 'fallback-manager-id',
          fullNameAr: fallback.managerName,
          fullNameEn: null,
          photoUrl: null,
          jobTitle: 'المدير المباشر',
          departmentName: target.departmentName,
          employeeCode: '',
          departmentId: null,
          status: 'active',
          managerEmployeeId: null,
          directReportsCount: 1,
          depth: Math.max(0, target.depth - 1),
          path: [],
        });
      }
    }

    // 2. البحث عن عقدة الموظف في الشجرة
    let subTreeNode = findTreeNode(chartData.tree, target.id);
    if (!subTreeNode) {
      // بناء شجرة فرعية من قائمة الموظفين إذا لم تكن في الشجرة الأصلية
      const directChildren = allEmps.filter((e) => e.managerEmployeeId === target.id);
      subTreeNode = {
        employee: target,
        children: directChildren.map((child) => ({
          employee: child,
          children: allEmps.filter((c) => c.managerEmployeeId === child.id).map((c) => ({ employee: c, children: [] })),
        })),
      };
    }

    // 3. تحليل المرؤوسين (مباشرين وغير مباشرين)
    const allSubordinates = collectAllDescendants(subTreeNode);
    const directReports = subTreeNode.children.map((c) => c.employee);
    const managersUnderCount = allSubordinates.filter((e) => e.directReportsCount > 0).length;
    const maxSubtreeDepth = calculateSubtreeDepth(subTreeNode);

    return {
      employee: target,
      ancestors,
      directReports,
      allSubordinates,
      subTree: subTreeNode,
      stats: {
        directReportsCount: directReports.length,
        totalSubordinatesCount: allSubordinates.length,
        managersUnderCount,
        maxSubtreeDepth,
      },
      isTopLevel: ancestors.length === 0 && !target.managerEmployeeId,
      hasSubordinates: directReports.length > 0,
    };
  }, [employeeId, orgChart.data, fallback]);

  return {
    data: result,
    isLoading: orgChart.isLoading,
    isError: Boolean(orgChart.error),
    error: orgChart.error,
    refetch: orgChart.refetch,
  };
}

function findTreeNode(nodes: OrgChartTreeNode[], id: string): OrgChartTreeNode | null {
  for (const node of nodes) {
    if (node.employee.id === id) return node;
    const found = findTreeNode(node.children, id);
    if (found) return found;
  }
  return null;
}

function collectAllDescendants(node: OrgChartTreeNode): OrgChartEmployee[] {
  const result: OrgChartEmployee[] = [];
  for (const child of node.children) {
    result.push(child.employee);
    result.push(...collectAllDescendants(child));
  }
  return result;
}

function calculateSubtreeDepth(node: OrgChartTreeNode, currentDepth = 0): number {
  if (node.children.length === 0) return currentDepth;
  return Math.max(...node.children.map((child) => calculateSubtreeDepth(child, currentDepth + 1)));
}
