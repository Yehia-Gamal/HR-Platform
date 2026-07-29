import { describe, it, expect } from 'vitest';
import { requestSummarySchema, leaveBalanceSchema } from '@ahla/shared-contracts';
import { mockRequests, mockLeaveBalances } from '../mock/domainMocks';

describe('useRequests — mock data schema validation', () => {
  describe('mockRequests', () => {
    it('parses all mock requests against requestSummarySchema', () => {
      const parsed = requestSummarySchema.array().parse(mockRequests);
      expect(parsed).toHaveLength(mockRequests.length);
    });

    it('contains exactly 3 requests', () => {
      expect(mockRequests).toHaveLength(3);
    });

    it('all IDs are valid UUIDs', () => {
      const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      for (const req of mockRequests) {
        expect(req.id).toMatch(uuidRe);
        expect(req.employeeId).toMatch(uuidRe);
      }
    });

    it('requestType is a valid enum value', () => {
      const validTypes = ['leave', 'mission', 'convoy', 'late_permit', 'early_permit', 'attendance_correction'];
      const parsed = requestSummarySchema.array().parse(mockRequests);
      for (const req of parsed) {
        expect(validTypes).toContain(req.requestType);
      }
    });

    it('status is a valid enum value', () => {
      const validStatuses = ['draft', 'pending', 'approved', 'rejected', 'returned', 'cancelled', 'withdrawn', 'expired', 'escalated'];
      const parsed = requestSummarySchema.array().parse(mockRequests);
      for (const req of parsed) {
        expect(validStatuses).toContain(req.status);
      }
    });

    it('has correct request types across mock data', () => {
      const parsed = requestSummarySchema.array().parse(mockRequests);
      expect(parsed[0].requestType).toBe('leave');
      expect(parsed[1].requestType).toBe('mission');
      expect(parsed[2].requestType).toBe('late_permit');
    });

    it('requestNumber is a positive number', () => {
      const parsed = requestSummarySchema.array().parse(mockRequests);
      for (const req of parsed) {
        expect(req.requestNumber).toBeGreaterThan(0);
      }
    });

    it('currentStepOrder is a positive number', () => {
      const parsed = requestSummarySchema.array().parse(mockRequests);
      for (const req of parsed) {
        expect(req.currentStepOrder).toBeGreaterThanOrEqual(1);
      }
    });
  });

  describe('mockLeaveBalances', () => {
    it('parses all mock leave balances against leaveBalanceSchema', () => {
      const parsed = leaveBalanceSchema.array().parse(mockLeaveBalances);
      expect(parsed).toHaveLength(mockLeaveBalances.length);
    });

    it('contains exactly 2 leave balances', () => {
      expect(mockLeaveBalances).toHaveLength(2);
    });

    it('all leaveTypeIds are valid UUIDs', () => {
      const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
      for (const bal of mockLeaveBalances) {
        expect(bal.leaveTypeId).toMatch(uuidRe);
      }
    });

    it('units are non-negative', () => {
      const parsed = leaveBalanceSchema.array().parse(mockLeaveBalances);
      for (const bal of parsed) {
        expect(bal.availableUnits).toBeGreaterThanOrEqual(0);
        expect(bal.reservedUnits).toBeGreaterThanOrEqual(0);
        expect(bal.consumedUnits).toBeGreaterThanOrEqual(0);
      }
    });

    it('has expected leave type codes', () => {
      const parsed = leaveBalanceSchema.array().parse(mockLeaveBalances);
      expect(parsed[0].code).toBe('annual');
      expect(parsed[1].code).toBe('emergency');
    });

    it('nameAr is a non-empty Arabic string', () => {
      const parsed = leaveBalanceSchema.array().parse(mockLeaveBalances);
      for (const bal of parsed) {
        expect(bal.nameAr.length).toBeGreaterThan(0);
      }
    });
  });
});
