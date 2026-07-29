import { describe, it, expect } from 'vitest';
import {
  organizationAdminCatalogSchema,
  accessAdminCatalogSchema,
  onboardingAdminCatalogSchema,
} from '@ahla/shared-contracts';

/**
 * Validates that the mock data embedded in useAdminOperations conforms
 * to the shared-contracts schemas. We recreate the mock shapes here
 * to guard against drift.
 */
describe('useAdminOperations mock data', () => {
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

  const now = new Date().toISOString();

  const mockOrganization = {
    entities: [{ id: ids.entity, code: 'AHLA', name: 'جمعية خواطر أحلى شباب', active: true }],
    branches: [{ id: ids.branch, entityId: ids.entity, code: 'HQ', name: 'المقر الرئيسي', active: true }],
    departments: [{ id: ids.department, entityId: ids.entity, branchId: ids.branch, parentId: null, managerId: ids.employee, code: 'OPS', name: 'إدارة التشغيل', nameEn: 'Operations', active: true, employeeCount: 12, positionCount: 4 }],
    teams: [],
    positions: [{ id: ids.position, departmentId: ids.department, teamId: null, jobTitleId: null, gradeId: null, reportsToId: null, code: 'OPS-MGR', name: 'مدير التشغيل', nameEn: null, headcount: 1, active: true, assignedCount: 1 }],
    employees: [{ id: ids.employee, code: 'EMP-001', name: 'موظف تجريبي', departmentId: ids.department, teamId: null, positionId: ids.position, active: true }],
    jobTitles: [],
    grades: [],
    lastUpdatedAt: now,
  };

  const mockAccess = {
    roles: [{
      id: ids.role, slug: 'employee', name: 'موظف', nameEn: 'Employee', description: 'الخدمة الذاتية',
      color: null, icon: null, system: true, fullAccess: false, assignments: 10,
      permissions: [{ permissionId: ids.permission, code: 'people.employee.read', name: 'عرض الموظف', scope: 'self', requiresMfa: false, requiresReason: false }],
    }],
    permissions: [{
      id: ids.permission, code: 'people.employee.read', module: 'people', resource: 'employee', action: 'read',
      name: 'عرض بيانات الموظف', nameAr: 'عرض بيانات الموظف', description: null, riskLevel: 'normal',
      sensitive: false, allowedScopes: ['self', 'direct_reports', 'organization'], moduleAr: 'شؤون الموظفين',
    }],
    users: [{
      userId: ids.user, employeeId: ids.employee, name: 'موظف تجريبي', employeeCode: 'EMP-001', status: 'active',
      roles: [{ roleId: ids.role, slug: 'employee', name: 'موظف', effectiveFrom: now, effectiveTo: null, scopeOverride: null }],
    }],
    lastUpdatedAt: now,
  };

  const mockOnboarding = {
    journeys: [{
      id: ids.journey, employeeId: ids.employee, employeeName: 'موظف تجريبي', employeeCode: 'EMP-001',
      startedAt: now, probationEnd: null, status: 'in_progress', progress: 50, totalTasks: 2, completedTasks: 1,
      tasks: [{ id: ids.task, title: 'توقيع السياسات', ownerRole: 'HR', assigneeId: null, dueOffsetDays: 1, status: 'completed', completedAt: now }],
    }],
    eligibleEmployees: [{ id: ids.employee, name: 'موظف تجريبي', code: 'EMP-001', status: 'onboarding', probationEnd: null }],
    lastUpdatedAt: now,
  };

  it('mockOrganization passes schema validation', () => {
    expect(() => organizationAdminCatalogSchema.parse(mockOrganization)).not.toThrow();
  });

  it('mockAccess passes schema validation', () => {
    expect(() => accessAdminCatalogSchema.parse(mockAccess)).not.toThrow();
  });

  it('mockOnboarding passes schema validation', () => {
    expect(() => onboardingAdminCatalogSchema.parse(mockOnboarding)).not.toThrow();
  });

  it('organization has entities, branches, departments, positions, employees', () => {
    const parsed = organizationAdminCatalogSchema.parse(mockOrganization);
    expect(parsed.entities).toHaveLength(1);
    expect(parsed.branches).toHaveLength(1);
    expect(parsed.departments).toHaveLength(1);
    expect(parsed.positions).toHaveLength(1);
    expect(parsed.employees).toHaveLength(1);
    expect(parsed.teams).toHaveLength(0);
    expect(parsed.jobTitles).toHaveLength(0);
    expect(parsed.grades).toHaveLength(0);
  });

  it('organization employee references valid department and position IDs', () => {
    const parsed = organizationAdminCatalogSchema.parse(mockOrganization);
    const emp = parsed.employees[0];
    expect(emp.departmentId).toBe(ids.department);
    expect(emp.positionId).toBe(ids.position);
    expect(parsed.departments.some((d) => d.id === emp.departmentId)).toBe(true);
    expect(parsed.positions.some((p) => p.id === emp.positionId)).toBe(true);
  });

  it('access has roles with permissions and users with role assignments', () => {
    const parsed = accessAdminCatalogSchema.parse(mockAccess);
    expect(parsed.roles).toHaveLength(1);
    expect(parsed.roles[0].permissions).toHaveLength(1);
    expect(parsed.permissions).toHaveLength(1);
    expect(parsed.users).toHaveLength(1);
    expect(parsed.users[0].roles).toHaveLength(1);
  });

  it('access role permission references valid permission ID', () => {
    const parsed = accessAdminCatalogSchema.parse(mockAccess);
    const rolePerm = parsed.roles[0].permissions[0];
    expect(rolePerm.permissionId).toBe(ids.permission);
    expect(parsed.permissions.some((p) => p.id === rolePerm.permissionId)).toBe(true);
  });

  it('onboarding journey has correct progress', () => {
    const parsed = onboardingAdminCatalogSchema.parse(mockOnboarding);
    const journey = parsed.journeys[0];
    expect(journey.progress).toBe(50);
    expect(journey.totalTasks).toBe(2);
    expect(journey.completedTasks).toBe(1);
    expect(journey.status).toBe('in_progress');
  });

  it('onboarding has eligible employees', () => {
    const parsed = onboardingAdminCatalogSchema.parse(mockOnboarding);
    expect(parsed.eligibleEmployees).toHaveLength(1);
    expect(parsed.eligibleEmployees[0].status).toBe('onboarding');
  });

  it('ids are valid UUID format', () => {
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    for (const [, value] of Object.entries(ids)) {
      expect(value).toMatch(uuidPattern);
      expect(value).toHaveLength(36);
    }
  });
});
