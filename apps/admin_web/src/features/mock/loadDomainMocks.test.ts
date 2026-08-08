import { describe, it, expect } from 'vitest';
import { loadDomainMocks } from './loadDomainMocks';

describe('loadDomainMocks', () => {
  it('returns a module with expected mock exports in dev mode', async () => {
    const mocks = await loadDomainMocks();
    expect(mocks).toBeDefined();
    expect(mocks.mockRequests).toBeDefined();
    expect(mocks.mockKpiEvaluations).toBeDefined();
    expect(mocks.mockOfficialFeed).toBeDefined();
    expect(mocks.mockActionCenter).toBeDefined();
    expect(mocks.mockDashboardOverview).toBeDefined();
    expect(mocks.mockLeaveBalances).toBeDefined();
    expect(mocks.mockLocations).toBeDefined();
    expect(mocks.mockOperations).toBeDefined();
    expect(mocks.mockAudit).toBeDefined();
    expect(mocks.mockIntegrations).toBeDefined();
    expect(mocks.mockAttendanceDashboard).toBeDefined();
    expect(mocks.mockNotifications).toBeDefined();
    expect(mocks.mockDailyReportFeed).toBeDefined();
  });

  it('mockRequests returns an array', async () => {
    const { mockRequests } = await loadDomainMocks();
    expect(Array.isArray(mockRequests)).toBe(true);
    expect(mockRequests.length).toBeGreaterThan(0);
  });

  it('mockDashboardOverview has numeric employee count', async () => {
    const { mockDashboardOverview } = await loadDomainMocks();
    expect(typeof mockDashboardOverview.employees).toBe('number');
    expect(mockDashboardOverview.employees).toBeGreaterThan(0);
  });
});
