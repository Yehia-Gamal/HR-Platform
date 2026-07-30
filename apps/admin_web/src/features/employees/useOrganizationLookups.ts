import { useQuery } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';
import { loadDomainMocks } from '../mock/loadDomainMocks';

type Option = { id: string; label: string; parentId?: string | null };
export interface OrganizationLookups {
  roles: Array<{ id: string; slug: string; label: string }>;
  managers: Option[];
  branches: Option[];
  workSites: Option[];
  departments: Option[];
  teams: Option[];
  jobTitles: Option[];
  positions: Option[];
  grades: Option[];
  employmentTypes: Option[];
}
function rows(value: unknown): Array<Record<string, unknown>> { return Array.isArray(value) ? value : []; }
const option = (row: Record<string, unknown>, parentKey?: string): Option => ({ id: String(row.id), label: String(row.name ?? row.full_name_ar ?? row.code ?? '—'), parentId: parentKey ? (row[parentKey] as string | null | undefined) : undefined });
export function useOrganizationLookups() {
  const auth = useAuth();
  return useQuery({ queryKey: ['organization-lookups', auth.isMock], enabled: auth.status === 'authenticated', staleTime: 5 * 60_000, queryFn: async (): Promise<OrganizationLookups> => {
    if (auth.isMock) return (await loadDomainMocks()).mockOrganizationLookups;
    const data = await rpc<Record<string, unknown>>('get_organization_lookups');
    return {
      // Full-access roles (admin / executive secretary) and capability roles
      // (committee-member / committee-chair) are intentionally excluded here:
      // full-access → provision_employee_record bypasses rpc_assign_role guard;
      // capability → contextual roles added via committee management, not employee creation.
      roles: rows(data.roles).filter((r) => !r.is_full_access && !r.is_capability).map((r) => ({ id: String(r.id), slug: String(r.slug), label: String(r.name_ar) })),
      // إخفاء كود الموظف إذا كان رقم هاتف (يبدأ بـ + أو 01) — المشتق تلقائياً من الهاتف
      managers: rows(data.employees).map((r) => ({ id: String(r.id), label: /^\+|^01\d/.test(String(r.employee_code)) ? String(r.full_name_ar) : `${String(r.full_name_ar)} · ${String(r.employee_code)}` })),
      branches: rows(data.branches).map((r) => option(r)),
      workSites: rows(data.work_sites).map((r) => option(r, 'branch_id')),
      departments: rows(data.departments).map((r) => option(r, 'branch_id')),
      teams: rows(data.teams).map((r) => option(r, 'department_id')),
      jobTitles: rows(data.job_titles).map((r) => option(r)),
      positions: rows(data.positions).map((r) => option(r, 'department_id')),
      grades: rows(data.job_grades).map((r) => option(r)),
      employmentTypes: rows(data.employment_types).map((r) => option(r)),
    };
  }});
}
