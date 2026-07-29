import { useQuery } from '@tanstack/react-query';
import { getSupabase } from '../../core/supabase';
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
const option = (row: Record<string, unknown>, parentKey?: string): Option => ({ id: String(row.id), label: String(row.name ?? row.full_name_ar ?? row.code ?? '—'), parentId: parentKey ? (row[parentKey] as string | null | undefined) : undefined });
export function useOrganizationLookups() {
  const auth = useAuth();
  return useQuery({ queryKey: ['organization-lookups', auth.isMock], enabled: auth.status === 'authenticated', staleTime: 5 * 60_000, queryFn: async (): Promise<OrganizationLookups> => {
    if (auth.isMock) return (await loadDomainMocks()).mockOrganizationLookups;
    const supabase = await getSupabase();
    const [roles, employees, branches, sites, departments, teams, titles, positions, grades, employmentTypes] = await Promise.all([
      supabase.from('roles').select('id,slug,name_ar,is_full_access,is_capability').order('name_ar'),
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
      // Full-access roles (admin / executive secretary) and capability roles
      // (committee-member / committee-chair) are intentionally excluded here:
      // full-access → provision_employee_record bypasses rpc_assign_role guard;
      // capability → contextual roles added via committee management, not employee creation.
      roles: (roles.data ?? []).filter((r) => !r.is_full_access && !r.is_capability).map((r) => ({ id: r.id, slug: r.slug, label: r.name_ar })),
      // إخفاء كود الموظف إذا كان رقم هاتف (يبدأ بـ + أو 01) — المشتق تلقائياً من الهاتف
      managers: (employees.data ?? []).map((r) => ({ id: r.id, label: /^\+|^01\d/.test(r.employee_code) ? r.full_name_ar : `${r.full_name_ar} · ${r.employee_code}` })),
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
