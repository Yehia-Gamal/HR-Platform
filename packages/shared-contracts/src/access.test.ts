import { describe, expect, it } from 'vitest';
import { accessContextSchema, canUseWorkspace } from './access.js';

describe('access context', () => {
  it('accepts a valid HR context and resolves workspaces', () => {
    const context = accessContextSchema.parse({
      userId: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      displayName: 'مسؤول الموارد البشرية',
      employeeCode: 'EMP-001',
      roles: ['hr-manager'],
      permissions: ['people.employee.read'],
      workspaces: ['employee', 'hr'],
      defaultWorkspace: 'hr',
      attendancePolicy: {
        attendanceRequired: true,
        selfPunchEnabled: true,
        liveLocationResponseEnabled: true,
      },
    });

    expect(canUseWorkspace(context, 'hr')).toBe(true);
    expect(canUseWorkspace(context, 'main_admin')).toBe(false);
  });
});
