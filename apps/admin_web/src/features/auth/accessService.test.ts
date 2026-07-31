import { describe, it, expect } from 'vitest';
import { accessContextSchema, canUseWorkspace, isWebWorkspace, workspaceIdSchema } from '@ahla/shared-contracts';
import { ZodError } from 'zod';

describe('accessService — schema & pure function validation', () => {
  const validFixture = {
    userId: '10000000-0000-4000-8000-000000000001',
    employeeId: '20000000-0000-4000-8000-000000000001',
    displayName: 'أحمد محمد',
    employeeCode: 'EMP-001',
    photoUrl: null,
    roles: ['employee', 'direct-manager'],
    permissions: ['attendance:view', 'requests:manage'],
    workspaces: ['employee', 'manager'] as const,
    defaultWorkspace: 'employee' as const,
    attendancePolicy: {
      attendanceRequired: true,
      selfPunchEnabled: true,
      liveLocationResponseEnabled: false,
    },
  };

  it('accessContextSchema parses a valid access context', () => {
    const parsed = accessContextSchema.parse(validFixture);
    expect(parsed.roles).toHaveLength(2);
    expect(parsed.permissions).toHaveLength(2);
    expect(parsed.workspaces).toHaveLength(2);
    expect(parsed.displayName).toBe('أحمد محمد');
  });

  it('accessContextSchema allows null employeeId', () => {
    const input = { ...validFixture, employeeId: null };
    const parsed = accessContextSchema.parse(input);
    expect(parsed.employeeId).toBeNull();
  });

  it('accessContextSchema rejects invalid workspace', () => {
    const input = { ...validFixture, workspaces: ['invalid_workspace'] };
    expect(() => accessContextSchema.parse(input)).toThrow(ZodError);
  });

  it('workspaceIdSchema validates all valid workspace IDs', () => {
    const validIds = ['employee', 'manager', 'executive', 'hr', 'main_admin', 'committee', 'field_operations'];
    for (const id of validIds) {
      expect(workspaceIdSchema.parse(id)).toBe(id);
    }
  });

  it('canUseWorkspace returns true when workspace is in context', () => {
    const ctx = accessContextSchema.parse({
      ...validFixture,
      workspaces: ['employee', 'hr'],
    });
    expect(canUseWorkspace(ctx, 'hr')).toBe(true);
  });

  it('canUseWorkspace returns false when workspace is not in context', () => {
    const ctx = accessContextSchema.parse({
      ...validFixture,
      workspaces: ['employee', 'hr'],
    });
    expect(canUseWorkspace(ctx, 'main_admin')).toBe(false);
  });

  it('isWebWorkspace returns true for hr, main_admin, committee', () => {
    expect(isWebWorkspace('hr')).toBe(true);
    expect(isWebWorkspace('main_admin')).toBe(true);
    expect(isWebWorkspace('committee')).toBe(true);
  });

  it('isWebWorkspace returns false for employee, manager, executive, field_operations', () => {
    expect(isWebWorkspace('employee')).toBe(false);
    expect(isWebWorkspace('manager')).toBe(false);
    expect(isWebWorkspace('executive')).toBe(false);
    expect(isWebWorkspace('field_operations')).toBe(false);
  });

  it('photoUrl defaults to null when omitted', () => {
    const withoutPhoto = Object.fromEntries(Object.entries(validFixture).filter(([key]) => key !== 'photoUrl'));
    const parsed = accessContextSchema.parse(withoutPhoto);
    expect(parsed.photoUrl).toBeNull();
  });

  it('roles and permissions are string arrays', () => {
    const parsed = accessContextSchema.parse(validFixture);
    expect(Array.isArray(parsed.roles)).toBe(true);
    expect(Array.isArray(parsed.permissions)).toBe(true);
    for (const role of parsed.roles) {
      expect(typeof role).toBe('string');
    }
    for (const perm of parsed.permissions) {
      expect(typeof perm).toBe('string');
    }
  });
});
