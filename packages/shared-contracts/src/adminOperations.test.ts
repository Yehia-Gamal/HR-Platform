import { describe, expect, it } from 'vitest';
import { accessAdminCatalogSchema, onboardingAdminCatalogSchema, organizationAdminCatalogSchema } from './adminOperations';

const id = (tail: string) => `10000000-0000-4000-8000-${tail.padStart(12, '0')}`;

describe('admin operation contracts', () => {
  it('parses organization structure with headcount', () => {
    const parsed = organizationAdminCatalogSchema.parse({
      entities: [{ id: id('1'), code: 'ORG', name: 'المؤسسة', active: true }],
      branches: [],
      departments: [{ id: id('2'), entityId: id('1'), branchId: null, parentId: null, managerId: null, code: 'HR', name: 'الموارد البشرية', nameEn: null, active: true, employeeCount: 3, positionCount: 2 }],
      teams: [], positions: [], employees: [], jobTitles: [], grades: [], lastUpdatedAt: new Date().toISOString(),
    });
    expect(parsed.departments[0]!.employeeCount).toBe(3);
  });

  it('parses scoped role permissions', () => {
    const parsed = accessAdminCatalogSchema.parse({
      roles: [{ id: id('1'), slug: 'manager', name: 'مدير', nameEn: null, description: null, color: null, icon: null, system: false, fullAccess: false, assignments: 1, permissions: [{ permissionId: id('2'), code: 'people.employee.read', name: 'people.employee.read', scope: 'direct_reports', requiresMfa: false, requiresReason: false }] }],
      permissions: [{ id: id('2'), code: 'people.employee.read', module: 'people', resource: 'employee', action: 'read', name: 'people.employee.read', description: null, riskLevel: 'normal', sensitive: false, allowedScopes: ['self', 'direct_reports'] }],
      users: [], lastUpdatedAt: new Date().toISOString(),
    });
    expect(parsed.roles[0]!.permissions[0]!.scope).toBe('direct_reports');
  });

  it('parses onboarding progress and tasks', () => {
    const parsed = onboardingAdminCatalogSchema.parse({
      journeys: [{ id: id('1'), employeeId: id('2'), employeeName: 'موظف', employeeCode: 'EMP-1', startedAt: new Date().toISOString(), probationEnd: null, status: 'in_progress', progress: 50, totalTasks: 2, completedTasks: 1, tasks: [] }],
      eligibleEmployees: [], lastUpdatedAt: new Date().toISOString(),
    });
    expect(parsed.journeys[0]!.progress).toBe(50);
  });
});
