import { describe, it, expect } from 'vitest';
import {
  attendanceOperationsCatalogSchema,
  kpiAdminCatalogSchema,
  disputeOperationsCatalogSchema,
} from '@ahla/shared-contracts';

/**
 * Validates the empty/default mock data in useAdvancedOperations against
 * shared-contracts schemas. Guards against schema drift.
 */
describe('useAdvancedOperations mock data', () => {
  const now = new Date().toISOString();

  const emptyAttendance = {
    month: now.slice(0, 7) + '-01',
    shifts: [],
    rosters: [],
    corrections: [],
    overtime: [],
    periods: [],
    summary: { scheduled: 0, present: 0, absent: 0, pendingCorrections: 0, pendingOvertime: 0 },
    lastUpdatedAt: now,
  };

  const emptyKpi = {
    month: now.slice(0, 7) + '-01',
    cycles: [],
    templates: [],
    appeals: [],
    stageCounts: {},
    lastUpdatedAt: now,
  };

  const emptyDisputes = {
    cases: [],
    summary: {
      new: 0, overdue: 0, urgent: 0, critical: 0, waitingStatements: 0, escalated: 0,
      pendingExecution: 0, actionProposed: 0, awaitingExecution: 0, executed: 0, closed: 0,
      averageResolutionHours: 0,
    },
    pendingAppeals: 0,
    lastUpdatedAt: now,
  };

  it('emptyAttendance passes schema validation', () => {
    expect(() => attendanceOperationsCatalogSchema.parse(emptyAttendance)).not.toThrow();
  });

  it('emptyKpi passes schema validation', () => {
    expect(() => kpiAdminCatalogSchema.parse(emptyKpi)).not.toThrow();
  });

  it('emptyDisputes passes schema validation', () => {
    expect(() => disputeOperationsCatalogSchema.parse(emptyDisputes)).not.toThrow();
  });

  it('attendance has correct empty arrays and zero summary', () => {
    const parsed = attendanceOperationsCatalogSchema.parse(emptyAttendance);
    expect(parsed.shifts).toHaveLength(0);
    expect(parsed.rosters).toHaveLength(0);
    expect(parsed.corrections).toHaveLength(0);
    expect(parsed.overtime).toHaveLength(0);
    expect(parsed.periods).toHaveLength(0);
    expect(parsed.summary.scheduled).toBe(0);
    expect(parsed.summary.present).toBe(0);
    expect(parsed.summary.absent).toBe(0);
    expect(parsed.summary.pendingCorrections).toBe(0);
    expect(parsed.summary.pendingOvertime).toBe(0);
  });

  it('kpi has correct empty arrays and empty stageCounts', () => {
    const parsed = kpiAdminCatalogSchema.parse(emptyKpi);
    expect(parsed.cycles).toHaveLength(0);
    expect(parsed.templates).toHaveLength(0);
    expect(parsed.appeals).toHaveLength(0);
    expect(Object.keys(parsed.stageCounts)).toHaveLength(0);
  });

  it('disputes has all zero summary fields', () => {
    const parsed = disputeOperationsCatalogSchema.parse(emptyDisputes);
    expect(parsed.cases).toHaveLength(0);
    expect(parsed.pendingAppeals).toBe(0);
    const s = parsed.summary;
    expect(s.new).toBe(0);
    expect(s.overdue).toBe(0);
    expect(s.urgent).toBe(0);
    expect(s.critical).toBe(0);
    expect(s.waitingStatements).toBe(0);
    expect(s.escalated).toBe(0);
    expect(s.pendingExecution).toBe(0);
    expect(s.actionProposed).toBe(0);
    expect(s.awaitingExecution).toBe(0);
    expect(s.executed).toBe(0);
    expect(s.closed).toBe(0);
    expect(s.averageResolutionHours).toBe(0);
  });

  it('month format is valid YYYY-MM-01', () => {
    const parsed = attendanceOperationsCatalogSchema.parse(emptyAttendance);
    expect(parsed.month).toMatch(/^\d{4}-\d{2}-01$/);
  });

  it('lastUpdatedAt is valid ISO string', () => {
    const parsed = attendanceOperationsCatalogSchema.parse(emptyAttendance);
    expect(new Date(parsed.lastUpdatedAt).toISOString()).toBe(parsed.lastUpdatedAt);
  });
});
