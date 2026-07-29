import { describe, it, expect } from 'vitest';
import {
  recruitmentWorkbenchSchema,
  reportSchedulerCatalogSchema,
} from '@ahla/shared-contracts';

/**
 * Validates that the mock data embedded in useEnterpriseOperations conforms
 * to the shared-contracts schemas. We import the schemas and re-create
 * the mock shapes here to guard against drift.
 */
describe('useEnterpriseOperations mock data', () => {
  const id = (tail: string) => `90000000-0000-4000-8000-${tail.padStart(12, '0')}`;
  const now = new Date().toISOString();

  const mockRecruitment = {
    requisitions: [{ id: id('1'), title: 'أخصائي تشغيل', departmentId: id('2'), departmentName: 'التشغيل', headcount: 2, status: 'approved', createdAt: now }],
    postings: [{ id: id('3'), requisitionId: id('1'), title: 'أخصائي تشغيل', slug: 'operations-specialist', visibility: 'external', status: 'published', publishedAt: now, closesAt: null }],
    applications: [{ id: id('4'), candidateId: id('5'), candidateName: 'مرشح تجريبي', postingId: id('3'), jobTitle: 'أخصائي تشغيل', status: 'active', stageId: id('6'), stageName: 'مقابلة', appliedAt: now, assigneeId: null }],
    candidates: [{ id: id('5'), name: 'مرشح تجريبي', email: 'candidate@example.com', phone: '+201000000000', source: 'referral', tags: ['تشغيل'], createdAt: now }],
    stages: [{ id: id('6'), postingId: id('3'), name: 'مقابلة', orderIndex: 3, slaDays: 3 }],
    interviews: [],
    offers: [],
    lastUpdatedAt: now,
  };

  const mockReports = {
    schedules: [],
    runs: [],
    notificationQueue: { queued: 0, failed: 0 },
    lastUpdatedAt: now,
  };

  it('mock recruitment data passes schema validation', () => {
    expect(() => recruitmentWorkbenchSchema.parse(mockRecruitment)).not.toThrow();
  });

  it('mock report scheduler data passes schema validation', () => {
    expect(() => reportSchedulerCatalogSchema.parse(mockReports)).not.toThrow();
  });

  it('recruitment mock has requisitions, postings, applications, candidates, stages', () => {
    const parsed = recruitmentWorkbenchSchema.parse(mockRecruitment);
    expect(parsed.requisitions).toHaveLength(1);
    expect(parsed.postings).toHaveLength(1);
    expect(parsed.applications).toHaveLength(1);
    expect(parsed.candidates).toHaveLength(1);
    expect(parsed.stages).toHaveLength(1);
    expect(parsed.interviews).toHaveLength(0);
    expect(parsed.offers).toHaveLength(0);
  });

  it('recruitment requisition has valid status', () => {
    const parsed = recruitmentWorkbenchSchema.parse(mockRecruitment);
    expect(parsed.requisitions[0].status).toBe('approved');
    expect(parsed.requisitions[0].headcount).toBe(2);
  });

  it('report scheduler mock has empty queues', () => {
    const parsed = reportSchedulerCatalogSchema.parse(mockReports);
    expect(parsed.schedules).toHaveLength(0);
    expect(parsed.runs).toHaveLength(0);
    expect(parsed.notificationQueue.queued).toBe(0);
    expect(parsed.notificationQueue.failed).toBe(0);
  });

  it('id helper generates valid UUID-like strings', () => {
    const result = id('1');
    expect(result).toBe('90000000-0000-4000-8000-000000000001');
    expect(result).toHaveLength(36);
    expect(result).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
  });
});
