import { describe, expect, it } from 'vitest';
import { attendanceOperationsCatalogSchema, kpiAdminCatalogSchema, disputeOperationsCatalogSchema, lifecycleOperationsCatalogSchema } from './advancedOperations.js';

const id = '10000000-0000-4000-8000-000000000001';

describe('advanced operation contracts', () => {
  it('parses attendance operations', () => {
    const value = attendanceOperationsCatalogSchema.parse({ month: '2026-07-01', shifts: [], rosters: [], corrections: [], overtime: [], periods: [], summary: { scheduled: 0, present: 0, absent: 0, pendingCorrections: 0, pendingOvertime: 0 }, lastUpdatedAt: new Date().toISOString() });
    expect(value.summary.present).toBe(0);
  });
  it('parses KPI cycles and appeals', () => {
    const value = kpiAdminCatalogSchema.parse({ month: '2026-07-01', cycles: [], templates: [], appeals: [], stageCounts: { self: 2 }, lastUpdatedAt: new Date().toISOString() });
    expect(value.stageCounts.self).toBe(2);
  });
  it('parses disputes and lifecycle', () => {
    expect(disputeOperationsCatalogSchema.parse({
      cases: [],
      summary: { new: 0, overdue: 0, urgent: 0, critical: 0, waitingStatements: 0, escalated: 0, pendingExecution: 0, closed: 0, averageResolutionHours: 0 },
      pendingAppeals: 0,
      lastUpdatedAt: new Date().toISOString(),
    }).cases).toHaveLength(0);
    expect(lifecycleOperationsCatalogSchema.parse({ documents: [], assets: [], offboarding: [], expiringDocuments: 0, assignedAssets: 0, openOffboarding: 0, lastUpdatedAt: new Date().toISOString() }).openOffboarding).toBe(0);
  });
  it('rejects malformed UUIDs', () => {
    expect(() => disputeOperationsCatalogSchema.parse({ cases: [{ id: 'x', caseNumber: null, title: 'x', caseType: 'grievance', status: 'submitted', severity: 'medium', actorId: null, actorName: null, respondentId: null, respondentName: null, assignedTo: null, assignedName: null, openedAt: new Date().toISOString(), acceptedAt: null, decisionDueAt: null, quorum: 2, members: [], sessions: [], decision: null }], pendingAppeals: 0, lastUpdatedAt: new Date().toISOString() })).toThrow();
    expect(id).toContain('-');
  });
});
