import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import type { OrgChartEmployee, OrgChartTreeNode } from '@ahla/shared-contracts';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export interface OrgChartStats {
  totalEmployees: number;
  managersCount: number;
  maxDepth: number;
  avgDirectReports: number;
}

export interface OrgChartData {
  employees: OrgChartEmployee[];
  tree: OrgChartTreeNode[];
  stats: OrgChartStats;
}

export function useOrgChart(search: string): {
  data: OrgChartData | undefined;
  isLoading: boolean;
  error: unknown;
  refetch: () => void;
} {
  const auth = useAuth();

  const query = useQuery<OrgChartData>({
    queryKey: ['org-chart', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => {
      const raw = await rpc<{ employees: OrgChartEmployee[] }>('get_admin_org_chart');
      const employees = Array.isArray(raw?.employees) ? raw.employees : [];
      const tree = buildOrgTree(employees);
      const stats = computeStats(employees);
      return { employees, tree, stats };
    },
  });

  const filtered = useMemo(() => {
    const base = query.data;
    if (!base) return undefined;
    const q = search.trim().toLowerCase();
    if (!q) return base;
    const matches = base.employees.filter(
      (e) =>
        e.fullNameAr.toLowerCase().includes(q) ||
        (e.fullNameEn?.toLowerCase().includes(q) ?? false) ||
        e.employeeCode.toLowerCase().includes(q) ||
        e.jobTitle.toLowerCase().includes(q) ||
        e.departmentName.toLowerCase().includes(q),
    );
    const matchSet = new Set(matches.map((m) => m.id));
    // شمل المديرين في المسار حتى الجذر لإظهار السياق الهرمي
    const expanded = new Set<string>();
    for (const m of matches) {
      let cursor: string | null = m.managerEmployeeId;
      while (cursor) {
        expanded.add(cursor);
        const parent = base.employees.find((e) => e.id === cursor);
        cursor = parent?.managerEmployeeId ?? null;
      }
    }
    const visibleIds = new Set<string>([...matchSet, ...expanded]);
    const visibleEmployees = base.employees.filter((e) => visibleIds.has(e.id));
    return {
      employees: visibleEmployees,
      tree: buildOrgTree(visibleEmployees),
      stats: base.stats,
    };
  }, [query.data, search]);

  return {
    data: filtered,
    isLoading: query.isLoading,
    error: query.error,
    refetch: () => query.refetch(),
  };
}

function buildOrgTree(employees: OrgChartEmployee[]): OrgChartTreeNode[] {
  const map = new Map<string, OrgChartTreeNode>();
  for (const emp of employees) {
    map.set(emp.id, { employee: emp, children: [] });
  }
  const roots: OrgChartTreeNode[] = [];
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

function computeStats(employees: OrgChartEmployee[]): OrgChartStats {
  if (employees.length === 0) {
    return { totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 };
  }
  const managersCount = employees.filter((e) => e.directReportsCount > 0).length;
  const maxDepth = Math.max(...employees.map((e) => e.depth));
  const totalReports = employees.reduce((sum, e) => sum + e.directReportsCount, 0);
  const avgDirectReports = managersCount > 0 ? +(totalReports / managersCount).toFixed(1) : 0;
  return { totalEmployees: employees.length, managersCount, maxDepth, avgDirectReports };
}
