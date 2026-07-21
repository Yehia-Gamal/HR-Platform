import { describe, expect, it } from 'vitest';
import { documentStudioCatalogSchema, learningAdminCatalogSchema, recruitmentWorkbenchSchema, reportSchedulerCatalogSchema } from './enterpriseOperations.js';

const now = new Date().toISOString();
describe('enterprise operations contracts', () => {
  it('parses ATS workbench', () => expect(recruitmentWorkbenchSchema.parse({ requisitions: [], postings: [], applications: [], candidates: [], stages: [], interviews: [], offers: [], lastUpdatedAt: now }).applications).toHaveLength(0));
  it('parses ATS interviews and offers rows', () => {
    const parsed = recruitmentWorkbenchSchema.parse({
      requisitions: [], postings: [], applications: [], candidates: [], stages: [],
      interviews: [{ id: '11111111-1111-4111-8111-111111111111', applicationId: '22222222-2222-4222-8222-222222222222', candidateName: 'مرشح', mode: 'onsite', scheduledAt: now, status: 'scheduled', locationOrLink: null }],
      offers: [{ id: '33333333-3333-4333-8333-333333333333', applicationId: '22222222-2222-4222-8222-222222222222', candidateName: 'مرشح', title: 'أخصائي', status: 'sent', startDate: null, expiresAt: null, version: 1 }],
      lastUpdatedAt: now,
    });
    expect(parsed.interviews[0]?.status).toBe('scheduled');
    expect(parsed.offers[0]?.version).toBe(1);
  });
  it('parses learning catalog', () => expect(learningAdminCatalogSchema.parse({ courses: [], enrollments: [], employees: [], lastUpdatedAt: now }).courses).toHaveLength(0));
  it('parses document studio', () => expect(documentStudioCatalogSchema.parse({ templates: [], documents: [], lastUpdatedAt: now }).templates).toHaveLength(0));
  it('parses scheduler', () => expect(reportSchedulerCatalogSchema.parse({ schedules: [], runs: [], notificationQueue: { queued: 0, failed: 0 }, lastUpdatedAt: now }).notificationQueue.failed).toBe(0));
});
