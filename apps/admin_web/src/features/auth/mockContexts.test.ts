import { describe, it, expect } from 'vitest';
import { accessContextSchema } from '@ahla/shared-contracts';
import { mockContexts } from './mockContexts';
import type { MockPersona } from './mockContexts';

const personas: MockPersona[] = ['hr', 'admin'];

describe('mockContexts', () => {
  it('exports both hr and admin personas', () => {
    expect(mockContexts).toHaveProperty('hr');
    expect(mockContexts).toHaveProperty('admin');
  });

  describe.each(personas)('%s persona — schema validation', (persona) => {
    it('passes accessContextSchema.parse() without throwing', () => {
      const result = accessContextSchema.parse(mockContexts[persona]);
      expect(result).toBeDefined();
    });
  });

  describe.each(personas)('%s persona — structural checks', (persona) => {
    const ctx = mockContexts[persona];

    it('has a non-empty displayName', () => {
      expect(ctx.displayName.length).toBeGreaterThan(0);
    });

    it('has at least one role', () => {
      expect(ctx.roles.length).toBeGreaterThan(0);
    });

    it('has at least one permission', () => {
      expect(ctx.permissions.length).toBeGreaterThan(0);
    });

    it('has at least one workspace', () => {
      expect(ctx.workspaces.length).toBeGreaterThan(0);
    });

    it('defaultWorkspace is included in the workspaces array', () => {
      expect(ctx.workspaces).toContain(ctx.defaultWorkspace);
    });

    it('has a valid attendancePolicy', () => {
      expect(ctx.attendancePolicy).toEqual({
        attendanceRequired: expect.any(Boolean),
        selfPunchEnabled: expect.any(Boolean),
        liveLocationResponseEnabled: expect.any(Boolean),
      });
    });
  });

  describe('hr context', () => {
    const ctx = mockContexts.hr;

    it('displayName contains الموارد البشرية', () => {
      expect(ctx.displayName).toContain('الموارد البشرية');
    });

    it('has roles [hr-manager]', () => {
      expect(ctx.roles).toEqual(['hr-manager']);
    });

    it('has the expected permissions', () => {
      expect(ctx.permissions).toEqual([
        'people.employee.read',
        'people.employee.create',
        'attendance.record.read',
        'requests.request.read',
        'performance.kpi.read',
        'reports.people.read',
      ]);
    });

    it('does not have wildcard permissions', () => {
      expect(ctx.permissions).not.toContain('*');
    });

    it('all permissions follow dotted triple format', () => {
      for (const perm of ctx.permissions) {
        expect(perm).toMatch(/^[a-z]+\.[a-z]+\.[a-z]+$/);
      }
    });

    it('has workspaces [employee, hr]', () => {
      expect(ctx.workspaces).toEqual(['employee', 'hr']);
    });

    it('defaultWorkspace is hr', () => {
      expect(ctx.defaultWorkspace).toBe('hr');
    });
  });

  describe('admin context', () => {
    const ctx = mockContexts.admin;

    it('displayName contains الأدمن', () => {
      expect(ctx.displayName).toContain('الأدمن');
    });

    it('has roles [admin, executive-secretary]', () => {
      expect(ctx.roles).toEqual(['admin', 'executive-secretary']);
    });

    it('has wildcard permissions', () => {
      expect(ctx.permissions).toEqual(['*']);
    });

    it('has workspaces [employee, manager, hr, main_admin]', () => {
      expect(ctx.workspaces).toEqual(['employee', 'manager', 'hr', 'main_admin']);
    });

    it('defaultWorkspace is main_admin', () => {
      expect(ctx.defaultWorkspace).toBe('main_admin');
    });
  });

  describe('shared base fields', () => {
    it('both personas share the same userId', () => {
      expect(mockContexts.hr.userId).toBe(mockContexts.admin.userId);
    });

    it('both personas share the same employeeId', () => {
      expect(mockContexts.hr.employeeId).toBe(mockContexts.admin.employeeId);
    });

    it('both personas have employeeCode DEV-001', () => {
      expect(mockContexts.hr.employeeCode).toBe('DEV-001');
      expect(mockContexts.admin.employeeCode).toBe('DEV-001');
    });

    it('both personas have null photoUrl', () => {
      expect(mockContexts.hr.photoUrl).toBeNull();
      expect(mockContexts.admin.photoUrl).toBeNull();
    });

    it('both personas share the same attendancePolicy', () => {
      expect(mockContexts.hr.attendancePolicy).toEqual(mockContexts.admin.attendancePolicy);
    });
  });
});
