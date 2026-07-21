import {
  accessAdminCatalogSchema,
  onboardingAdminCatalogSchema,
  organizationAdminCatalogSchema,
  type AccessAdminCatalog,
  type OnboardingAdminCatalog,
  type OrganizationAdminCatalog,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

const ids = {
  entity: '10000000-0000-4000-8000-000000000001',
  branch: '10000000-0000-4000-8000-000000000002',
  department: '10000000-0000-4000-8000-000000000003',
  position: '10000000-0000-4000-8000-000000000004',
  employee: '30000000-0000-4000-8000-000000000001',
  role: '20000000-0000-4000-8000-000000000001',
  permission: '20000000-0000-4000-8000-000000000002',
  user: '40000000-0000-4000-8000-000000000001',
  journey: '50000000-0000-4000-8000-000000000001',
  task: '50000000-0000-4000-8000-000000000002',
};

const mockOrganization: OrganizationAdminCatalog = {
  entities: [{ id: ids.entity, code: 'AHLA', name: 'جمعية خواطر أحلى شباب', active: true }],
  branches: [{ id: ids.branch, entityId: ids.entity, code: 'HQ', name: 'المقر الرئيسي', active: true }],
  departments: [{ id: ids.department, entityId: ids.entity, branchId: ids.branch, parentId: null, managerId: ids.employee, code: 'OPS', name: 'إدارة التشغيل', nameEn: 'Operations', active: true, employeeCount: 12, positionCount: 4 }],
  teams: [],
  positions: [{ id: ids.position, departmentId: ids.department, teamId: null, jobTitleId: null, gradeId: null, reportsToId: null, code: 'OPS-MGR', name: 'مدير التشغيل', nameEn: null, headcount: 1, active: true, assignedCount: 1 }],
  employees: [{ id: ids.employee, code: 'EMP-001', name: 'موظف تجريبي', departmentId: ids.department, teamId: null, positionId: ids.position, active: true }],
  jobTitles: [], grades: [], lastUpdatedAt: new Date().toISOString(),
};

const mockAccess: AccessAdminCatalog = {
  roles: [{ id: ids.role, slug: 'employee', name: 'موظف', nameEn: 'Employee', description: 'الخدمة الذاتية', color: null, icon: null, system: true, fullAccess: false, assignments: 10, permissions: [{ permissionId: ids.permission, code: 'people.employee.read', name: 'عرض الموظف', scope: 'self', requiresMfa: false, requiresReason: false }] }],
  permissions: [{ id: ids.permission, code: 'people.employee.read', module: 'people', resource: 'employee', action: 'read', name: 'عرض الموظف', description: null, riskLevel: 'normal', sensitive: false, allowedScopes: ['self', 'direct_reports', 'organization'] }],
  users: [{ userId: ids.user, employeeId: ids.employee, name: 'موظف تجريبي', employeeCode: 'EMP-001', status: 'active', roles: [{ roleId: ids.role, slug: 'employee', name: 'موظف', effectiveFrom: new Date().toISOString(), effectiveTo: null, scopeOverride: null }] }],
  lastUpdatedAt: new Date().toISOString(),
};

const mockOnboarding: OnboardingAdminCatalog = {
  journeys: [{ id: ids.journey, employeeId: ids.employee, employeeName: 'موظف تجريبي', employeeCode: 'EMP-001', startedAt: new Date().toISOString(), probationEnd: null, status: 'in_progress', progress: 50, totalTasks: 2, completedTasks: 1, tasks: [{ id: ids.task, title: 'توقيع السياسات', ownerRole: 'HR', assigneeId: null, dueOffsetDays: 1, status: 'completed', completedAt: new Date().toISOString() }] }],
  eligibleEmployees: [{ id: ids.employee, name: 'موظف تجريبي', code: 'EMP-001', status: 'onboarding', probationEnd: null }],
  lastUpdatedAt: new Date().toISOString(),
};

export function useOrganizationAdminCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['organization-admin-catalog', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => auth.isMock ? mockOrganization : organizationAdminCatalogSchema.parse(await rpc('get_organization_admin_catalog')),
  });
}

export function useOrganizationCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      client.invalidateQueries({ queryKey: ['organization-admin-catalog'] }),
      client.invalidateQueries({ queryKey: ['organization-overview'] }),
      client.invalidateQueries({ queryKey: ['organization-lookups'] }),
    ]);
  };
  const department = useMutation({
    mutationFn: async (input: { id?: string | null; entityId: string; branchId?: string | null; parentId?: string | null; managerId?: string | null; code: string; name: string; nameEn?: string | null; active: boolean }) => {
      if (auth.isMock) return ids.department;
      return rpc('upsert_department_admin', {
        p_id: input.id ?? null,
        p_legal_entity_id: input.entityId,
        p_branch_id: input.branchId ?? null,
        p_parent_id: input.parentId ?? null,
        p_manager_id: input.managerId ?? null,
        p_code: input.code,
        p_name: input.name,
        p_name_en: input.nameEn ?? null,
        p_is_active: input.active,
      });
    },
    onSuccess: refresh,
  });
  const position = useMutation({
    mutationFn: async (input: { id?: string | null; departmentId: string; teamId?: string | null; jobTitleId?: string | null; gradeId?: string | null; reportsToId?: string | null; code: string; name: string; nameEn?: string | null; headcount: number; active: boolean }) => {
      if (auth.isMock) return ids.position;
      return rpc('upsert_position_admin', {
        p_id: input.id ?? null,
        p_department_id: input.departmentId,
        p_team_id: input.teamId ?? null,
        p_job_title_id: input.jobTitleId ?? null,
        p_grade_id: input.gradeId ?? null,
        p_reports_to_id: input.reportsToId ?? null,
        p_code: input.code,
        p_name: input.name,
        p_name_en: input.nameEn ?? null,
        p_headcount: input.headcount,
        p_is_active: input.active,
      });
    },
    onSuccess: refresh,
  });
  return { department, position };
}

export function useAccessAdminCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['access-admin-catalog', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => auth.isMock ? mockAccess : accessAdminCatalogSchema.parse(await rpc('get_access_admin_catalog')),
  });
}

export function useAccessCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      client.invalidateQueries({ queryKey: ['access-admin-catalog'] }),
      client.invalidateQueries({ queryKey: ['access-overview'] }),
    ]);
  };
  const upsertRole = useMutation({
    mutationFn: async (input: { id?: string | null; slug: string; name: string; nameEn?: string | null; description?: string | null; color?: string | null; icon?: string | null; fullAccess?: boolean }) => {
      if (auth.isMock) return { id: input.id ?? ids.role };
      return rpc('rpc_upsert_role', {
        p_id: input.id ?? null,
        p_slug: input.slug,
        p_name_ar: input.name,
        p_name_en: input.nameEn ?? null,
        p_description: input.description ?? null,
        p_color: input.color ?? null,
        p_icon: input.icon ?? null,
        p_is_full_access: input.fullAccess ?? false,
      });
    },
    onSuccess: refresh,
  });
  const setPermissions = useMutation({
    mutationFn: async (input: { roleId: string; items: Array<{ permission_id: string; scope: string; requires_mfa: boolean; requires_reason: boolean }> }) => {
      if (auth.isMock) return input.items.length;
      return rpc('rpc_set_role_permissions', { p_role_id: input.roleId, p_items: input.items });
    },
    onSuccess: refresh,
  });
  const assignRole = useMutation({
    mutationFn: async (input: { userId: string; roleId: string; effectiveTo?: string | null }) => {
      if (auth.isMock) return { userId: input.userId, roleId: input.roleId };
      return rpc('rpc_assign_role', {
        p_user_id: input.userId,
        p_role_id: input.roleId,
        p_scope_override: null,
        p_effective_from: new Date().toISOString(),
        p_effective_to: input.effectiveTo ?? null,
      });
    },
    onSuccess: refresh,
  });
  const revokeRole = useMutation({
    mutationFn: async (input: { userId: string; roleId: string }) => {
      if (auth.isMock) return null;
      return rpc('rpc_revoke_role', { p_user_id: input.userId, p_role_id: input.roleId });
    },
    onSuccess: refresh,
  });
  return { upsertRole, setPermissions, assignRole, revokeRole };
}

export function useOnboardingAdminCatalog() {
  const auth = useAuth();
  return useQuery({
    queryKey: ['onboarding-admin-catalog', auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async () => auth.isMock ? mockOnboarding : onboardingAdminCatalogSchema.parse(await rpc('get_onboarding_admin_catalog', { p_limit: 150 })),
  });
}

export function useOnboardingCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const refresh = async () => {
    await Promise.all([
      client.invalidateQueries({ queryKey: ['onboarding-admin-catalog'] }),
      client.invalidateQueries({ queryKey: ['employees'] }),
    ]);
  };
  const createJourney = useMutation({
    mutationFn: async (input: { employeeId: string; probationEnd?: string | null; tasks: Array<{ title: string; ownerRole?: string | null; dueOffsetDays?: number }> }) => {
      if (auth.isMock) return ids.journey;
      return rpc('create_onboarding_journey_admin', {
        p_employee_id: input.employeeId,
        p_started_at: new Date().toISOString(),
        p_probation_end: input.probationEnd ?? null,
        p_tasks: input.tasks.map((task) => ({ title: task.title, ownerRole: task.ownerRole ?? null, dueOffsetDays: task.dueOffsetDays ?? 0 })),
      });
    },
    onSuccess: refresh,
  });
  const transitionTask = useMutation({
    mutationFn: async (input: { taskId: string; status: string }) => {
      if (auth.isMock) return { completed: input.status === 'completed' };
      return rpc('transition_onboarding_task_admin', { p_task_id: input.taskId, p_status: input.status });
    },
    onSuccess: refresh,
  });
  return { createJourney, transitionTask };
}

export function useRecruitmentCommands() {
  const auth = useAuth();
  const client = useQueryClient();
  const createRequisition = useMutation({
    mutationFn: async (input: { departmentId: string; title: string; headcount: number; reason?: string | null; budgetRange?: string | null; submit: boolean }) => {
      if (auth.isMock) return '60000000-0000-4000-8000-000000000001';
      return rpc('create_job_requisition_admin', {
        p_department_id: input.departmentId,
        p_title: input.title,
        p_headcount: input.headcount,
        p_reason: input.reason ?? null,
        p_budget_range: input.budgetRange ?? null,
        p_submit: input.submit,
      });
    },
    onSuccess: async () => {
      await client.invalidateQueries({ queryKey: ['recruitment-overview'] });
    },
  });
  return { createRequisition };
}
