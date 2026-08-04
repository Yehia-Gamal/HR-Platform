import { accessContextSchema, type AccessContext } from '@ahla/shared-contracts';
import { describe, expect, it } from 'vitest';
import { mockContexts } from '../auth/mockContexts';
import { firstWebWorkspace, hasPermission, hrPathToAdmin, isUnifiedAdminActive } from './access';

function makeContext(overrides: Partial<AccessContext> = {}): AccessContext {
  return {
    userId: '11111111-1111-4111-8111-111111111111',
    employeeId: null,
    displayName: 'Admin',
    employeeCode: null,
    photoUrl: null,
    roles: ['admin'],
    permissions: ['*'],
    workspaces: ['main_admin', 'hr'],
    defaultWorkspace: 'main_admin',
    attendancePolicy: {
      attendanceRequired: false,
      selfPunchEnabled: false,
      liveLocationResponseEnabled: false,
    },
    ...overrides,
  };
}

describe('hasPermission', () => {
  it('honors wildcard permission', () => {
    expect(hasPermission(makeContext(), 'people.employee.create')).toBe(true);
  });

  it('matches an explicitly granted permission', () => {
    const context = makeContext({ permissions: ['people.employee.read'] });
    expect(hasPermission(context, 'people.employee.read')).toBe(true);
  });

  it('denies a permission that is neither wildcard nor listed', () => {
    const context = makeContext({ permissions: ['people.employee.read'] });
    expect(hasPermission(context, 'people.employee.delete')).toBe(false);
  });

  it('denies when the permission list is empty', () => {
    expect(hasPermission(makeContext({ permissions: [] }), 'anything')).toBe(false);
  });
});

describe('firstWebWorkspace', () => {
  it('returns the configured hr default workspace', () => {
    const context = makeContext({ defaultWorkspace: 'hr', workspaces: ['hr'] });
    expect(firstWebWorkspace(context)).toBe('hr');
  });

  it('returns the configured main_admin default workspace', () => {
    expect(firstWebWorkspace(makeContext())).toBe('main_admin');
  });

  it('falls back to main_admin when the default is a non-web workspace', () => {
    const context = makeContext({
      defaultWorkspace: 'employee',
      workspaces: ['employee', 'main_admin', 'hr'],
    });
    expect(firstWebWorkspace(context)).toBe('main_admin');
  });

  it('falls back to hr when only hr is available among web workspaces', () => {
    const context = makeContext({
      defaultWorkspace: 'employee',
      workspaces: ['employee', 'hr'],
    });
    expect(firstWebWorkspace(context)).toBe('hr');
  });

  it('returns null when no web workspace is available', () => {
    const context = makeContext({
      defaultWorkspace: 'employee',
      workspaces: ['employee', 'manager'],
    });
    expect(firstWebWorkspace(context)).toBeNull();
  });
});

describe('mock personas', () => {
  it('every dev persona is a schema-valid AccessContext', () => {
    for (const context of Object.values(mockContexts)) {
      expect(() => accessContextSchema.parse(context)).not.toThrow();
    }
  });

  it('resolves each persona to a web workspace', () => {
    expect(firstWebWorkspace(mockContexts.hr)).toBe('hr');
    expect(firstWebWorkspace(mockContexts.admin)).toBe('main_admin');
  });
});

describe('hrPathToAdmin', () => {
  it('maps the HR dashboard to the unified admin dashboard', () => {
    expect(hrPathToAdmin('/hr')).toBe('/admin/hr');
  });

  it('maps nested HR pages under /admin/hr and preserves ids', () => {
    expect(hrPathToAdmin('/hr/employees')).toBe('/admin/hr/employees');
    expect(hrPathToAdmin('/hr/employees/abc-123')).toBe('/admin/hr/employees/abc-123');
    expect(hrPathToAdmin('/hr/attendance/operations')).toBe('/admin/hr/attendance/operations');
  });

  it('returns null for non-HR paths', () => {
    expect(hrPathToAdmin('/admin/actions')).toBeNull();
    expect(hrPathToAdmin('/committee')).toBeNull();
  });
});

describe('isUnifiedAdminActive', () => {
  it('is active on /admin and any /admin sub-path when the user owns main_admin', () => {
    expect(isUnifiedAdminActive(['main_admin'], '/admin')).toBe(true);
    expect(isUnifiedAdminActive(['main_admin', 'hr'], '/admin/hr/employees')).toBe(true);
    expect(isUnifiedAdminActive(['main_admin'], '/admin/audit-security')).toBe(true);
  });

  it('is inactive outside the admin area or without the main_admin workspace', () => {
    expect(isUnifiedAdminActive(['main_admin'], '/hr')).toBe(false);
    expect(isUnifiedAdminActive(['main_admin'], '/committee/disputes')).toBe(false);
    expect(isUnifiedAdminActive(['hr'], '/admin')).toBe(false);
  });
});
