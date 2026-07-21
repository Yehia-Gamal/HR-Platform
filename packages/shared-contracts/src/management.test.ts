import { describe, expect, it } from 'vitest';
import { dashboardOverviewSchema, notificationItemSchema } from './management.js';

describe('management contracts', () => {
  it('parses dashboard overview', () => {
    expect(dashboardOverviewSchema.parse({
      employees: 10, activeEmployees: 9, pendingRequests: 2, attendancePendingReview: 1,
      pendingKpi: 3, openRequisitions: 1, urgentActions: 1, publishedDecisions: 4,
      unresolvedErrors: 0, lastUpdatedAt: new Date().toISOString(),
    }).activeEmployees).toBe(9);
  });
  it('rejects invalid notification priority', () => {
    expect(() => notificationItemSchema.parse({ id: crypto.randomUUID(), title: 'x', body: null, category: 'general', priority: 'critical', actionUrl: null, isRead: false, createdAt: new Date().toISOString() })).toThrow();
  });
});
