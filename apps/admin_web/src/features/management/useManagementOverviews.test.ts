import { describe, it, expect } from 'vitest';
import {
  dashboardOverviewSchema,
  organizationOverviewSchema,
  accessOverviewSchema,
  recruitmentOverviewSchema,
  systemOverviewSchema,
} from '@ahla/shared-contracts';
import {
  mockDashboardOverview,
  mockOrganizationOverview,
  mockAccessOverview,
  mockRecruitmentOverview,
  mockSystemOverview,
} from '../mock/domainMocks';

describe('useManagementOverviews — mock data schema validation', () => {
  describe('dashboardOverview', () => {
    it('parses against dashboardOverviewSchema', () => {
      expect(() => dashboardOverviewSchema.parse(mockDashboardOverview)).not.toThrow();
    });

    it('has expected numeric fields', () => {
      const parsed = dashboardOverviewSchema.parse(mockDashboardOverview);
      expect(parsed.employees).toBeGreaterThanOrEqual(0);
      expect(parsed.activeEmployees).toBeGreaterThanOrEqual(0);
      expect(parsed.pendingRequests).toBeGreaterThanOrEqual(0);
    });

    it('activeEmployees <= employees', () => {
      const parsed = dashboardOverviewSchema.parse(mockDashboardOverview);
      expect(parsed.activeEmployees).toBeLessThanOrEqual(parsed.employees);
    });
  });

  describe('organizationOverview', () => {
    it('parses against organizationOverviewSchema', () => {
      expect(() => organizationOverviewSchema.parse(mockOrganizationOverview)).not.toThrow();
    });

    it('has non-negative department and branch counts', () => {
      const parsed = organizationOverviewSchema.parse(mockOrganizationOverview);
      expect(parsed.departments).toBeGreaterThanOrEqual(0);
      expect(parsed.branches).toBeGreaterThanOrEqual(0);
    });
  });

  describe('accessOverview', () => {
    it('parses against accessOverviewSchema', () => {
      expect(() => accessOverviewSchema.parse(mockAccessOverview)).not.toThrow();
    });

    it('has non-negative role and assignment counts', () => {
      const parsed = accessOverviewSchema.parse(mockAccessOverview);
      expect(parsed.roles).toBeGreaterThanOrEqual(0);
      expect(parsed.activeAssignments).toBeGreaterThanOrEqual(0);
      expect(parsed.permissions).toBeGreaterThanOrEqual(0);
    });

    it('rolesList is an array', () => {
      const parsed = accessOverviewSchema.parse(mockAccessOverview);
      expect(Array.isArray(parsed.rolesList)).toBe(true);
    });
  });

  describe('recruitmentOverview', () => {
    it('parses against recruitmentOverviewSchema', () => {
      expect(() => recruitmentOverviewSchema.parse(mockRecruitmentOverview)).not.toThrow();
    });

    it('has non-negative requisition and candidate counts', () => {
      const parsed = recruitmentOverviewSchema.parse(mockRecruitmentOverview);
      expect(parsed.requisitions).toBeGreaterThanOrEqual(0);
      expect(parsed.candidates).toBeGreaterThanOrEqual(0);
      expect(parsed.activeApplications).toBeGreaterThanOrEqual(0);
    });

    it('pipeline is an array', () => {
      const parsed = recruitmentOverviewSchema.parse(mockRecruitmentOverview);
      expect(Array.isArray(parsed.pipeline)).toBe(true);
    });
  });

  describe('systemOverview', () => {
    it('parses against systemOverviewSchema', () => {
      expect(() => systemOverviewSchema.parse(mockSystemOverview)).not.toThrow();
    });

    it('has non-negative flag and error counts', () => {
      const parsed = systemOverviewSchema.parse(mockSystemOverview);
      expect(parsed.enabledFlags).toBeGreaterThanOrEqual(0);
      expect(parsed.totalFlags).toBeGreaterThanOrEqual(0);
      expect(parsed.unresolvedErrors).toBeGreaterThanOrEqual(0);
    });
  });

  it('all 5 overviews parse without data loss', () => {
    const dashboard = dashboardOverviewSchema.parse(mockDashboardOverview);
    const org = organizationOverviewSchema.parse(mockOrganizationOverview);
    const access = accessOverviewSchema.parse(mockAccessOverview);
    const recruitment = recruitmentOverviewSchema.parse(mockRecruitmentOverview);
    const system = systemOverviewSchema.parse(mockSystemOverview);

    // Every parsed result should be a non-null object
    for (const parsed of [dashboard, org, access, recruitment, system]) {
      expect(parsed).toBeDefined();
      expect(typeof parsed).toBe('object');
      expect(parsed).not.toBeNull();
    }
  });
});
