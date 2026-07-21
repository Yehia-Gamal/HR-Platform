import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
import { useAuth } from '../auth/AuthProvider';

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
const mock: OrganizationLookups = {
  roles: [{ id: 'role-employee', slug: 'employee', label: 'موظف' }, { id: 'role-manager', slug: 'direct-manager', label: 'مدير مباشر' }, { id: 'role-hr', slug: 'hr-specialist', label: 'HR Specialist' }],
  managers: [{ id: '30000000-0000-4000-8000-000000000002', label: 'مدير مباشر تجريبي · EMP-002' }],
  branches: [], workSites: [], departments: [], teams: [], jobTitles: [], positions: [], grades: [], employmentTypes: [],
};
const option = (row: Record<string, unknown>, parentKey?: string): Option => ({ id: String(row.id), label: String(row.name ?? row.full_name_ar ?? row.code ?? '—'), parentId: parentKey ? (row[parentKey] as string | null | undefined) : undefined });
export function useOrganizationLookups() {
  const auth = useAuth();
  return useQuery({ queryKey: ['organization-lookups', auth.isMock], enabled: auth.status === 'authenticated', staleTime: 5 * 60_000, queryFn: async (): Promise<OrganizationLookups> => {
    if (auth.isMock) return mock;
    const supabase = await getSupabase();
    const [roles, employees, branches, sites, departments, teams, titles, positions, grades, employmentTypes] = await Promise.all([
      supabase.from('roles').select('id,slug,name_ar,is_full_access').order('name_ar'),
      supabase.from('employees').select('id,full_name_ar,employee_code').eq('is_active', true).eq('is_deleted', false).order('full_name_ar'),
      supabase.from('branches').select('id,name').eq('is_active', true).order('name'),
      supabase.from('work_sites').select('id,name,branch_id').eq('is_active', true).order('name'),
      supabase.from('departments').select('id,name,branch_id').eq('is_active', true).order('name'),
      supabase.from('teams').select('id,name,department_id').eq('is_active', true).order('name'),
      supabase.from('job_titles').select('id,name').eq('is_active', true).order('name'),
      supabase.from('positions').select('id,name,department_id').eq('is_active', true).order('name'),
      supabase.from('job_grades').select('id,name').eq('is_active', true).order('level'),
      supabase.from('employment_types').select('id,name').eq('is_active', true).order('name'),
    ]);
    const firstError = [roles, employees, branches, sites, departments, teams, titles, positions, grades, employmentTypes].find((result) => result.error)?.error;
    if (firstError) throw firstError;
    return {
      // Full-access roles (admin / executive secretary) are intentionally
      // excluded here: provision_employee_record bypasses rpc_assign_role's
      // full-access guard, so those roles must be assigned only via /admin/access.
      roles: (roles.data ?? []).filter((r) => !r.is_full_access).map((r) => ({ id: r.id, slug: r.slug, label: r.name_ar })),
      managers: (employees.data ?? []).map((r) => ({ id: r.id, label: `${r.full_name_ar} · ${r.employee_code}` })),
      branches: (branches.data ?? []).map((r) => option(r)),
      workSites: (sites.data ?? []).map((r) => option(r, 'branch_id')),
      departments: (departments.data ?? []).map((r) => option(r, 'branch_id')),
      teams: (teams.data ?? []).map((r) => option(r, 'department_id')),
      jobTitles: (titles.data ?? []).map((r) => option(r)),
      positions: (positions.data ?? []).map((r) => option(r, 'department_id')),
      grades: (grades.data ?? []).map((r) => option(r)),
      employmentTypes: (employmentTypes.data ?? []).map((r) => option(r)),
    };
  }});
}
