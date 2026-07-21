import type { AccessContext } from '@ahla/shared-contracts';

export type MockPersona = 'hr' | 'admin';

const base = {
  userId: '11111111-1111-4111-8111-111111111111',
  employeeId: '22222222-2222-4222-8222-222222222222',
  employeeCode: 'DEV-001',
  attendancePolicy: {
    attendanceRequired: true,
    selfPunchEnabled: true,
    liveLocationResponseEnabled: true,
  },
} as const;

export const mockContexts: Record<MockPersona, AccessContext> = {
  hr: {
    ...base,
    displayName: 'مدير الموارد البشرية — وضع التطوير',
    roles: ['hr-manager'],
    permissions: [
      'people.employee.read',
      'people.employee.create',
      'attendance.record.read',
      'requests.request.read',
      'performance.kpi.read',
      'reports.people.read',
    ],
    workspaces: ['employee', 'hr'],
    defaultWorkspace: 'hr',
  },
  admin: {
    ...base,
    displayName: 'الأدمن الرئيسي — وضع التطوير',
    roles: ['admin', 'executive-secretary'],
    permissions: ['*'],
    workspaces: ['employee', 'manager', 'hr', 'main_admin'],
    defaultWorkspace: 'main_admin',
  },
};
