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
    expect(context.photoUrl).toBeNull();
    expect(context.isSuspended).toBe(false);
  });

  it('accepts a suspended employee context with fine details', () => {
    const context = accessContextSchema.parse({
      userId: '33333333-3333-4333-8333-333333333333',
      employeeId: '44444444-4444-4444-8444-444444444444',
      displayName: 'موظف موقوف',
      employeeCode: 'EMP-999',
      roles: [],
      permissions: [],
      workspaces: [],
      defaultWorkspace: 'employee',
      isSuspended: true,
      suspensionReason: 'penalty_unpaid',
      suspensionAmount: 500,
      suspensionMessage: 'تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ',
      attendancePolicy: {
        attendanceRequired: false,
        selfPunchEnabled: false,
        liveLocationResponseEnabled: false,
      },
    });

    expect(context.isSuspended).toBe(true);
    expect(context.suspensionAmount).toBe(500);
    expect(context.suspensionMessage).toBe('تم وقفك عن العمل لعدم سداد قيمة الخصم 500جنيه توجه الي قسم ال HR لسداد المبلغ');
    expect(context.workspaces).toHaveLength(0);
    expect(canUseWorkspace(context, 'employee')).toBe(false);
  });
});
