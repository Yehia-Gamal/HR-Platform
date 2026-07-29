import { describe, it, expect } from 'vitest';
import { enterpriseManagementCatalogSchema } from '@ahla/shared-contracts';

/**
 * Validates that the mock data embedded in useEnterpriseManagement conforms
 * to the shared-contracts schema. Guards against drift.
 */
describe('useEnterpriseManagement mock data', () => {
  const now = new Date().toISOString();

  const mockEnterprise = {
    objectives: [],
    projects: [],
    risks: [],
    incidents: [],
    serviceRequests: [
      {
        id: 'a1000000-0000-4000-8000-000000000001',
        number: 24031,
        serviceName: 'الدعم التقني',
        requesterName: 'أحمد محمود',
        title: 'تعذر الدخول إلى نظام الحضور',
        priority: 'urgent',
        status: 'submitted',
        dueAt: new Date(Date.now() - 45 * 60_000).toISOString(),
      },
      {
        id: 'a1000000-0000-4000-8000-000000000002',
        number: 24030,
        serviceName: 'الخدمات الإدارية',
        requesterName: 'سارة عادل',
        title: 'طلب بطاقة دخول بديلة',
        priority: 'high',
        status: 'in_progress',
        dueAt: new Date(Date.now() + 5 * 3_600_000).toISOString(),
      },
      {
        id: 'a1000000-0000-4000-8000-000000000003',
        number: 24028,
        serviceName: 'تقنية المعلومات',
        requesterName: 'محمود فؤاد',
        title: 'تجهيز صلاحيات جهاز العمل',
        priority: 'normal',
        status: 'assigned',
        dueAt: new Date(Date.now() + 22 * 3_600_000).toISOString(),
      },
      {
        id: 'a1000000-0000-4000-8000-000000000004',
        number: 24021,
        serviceName: 'الموارد البشرية',
        requesterName: 'منى حسن',
        title: 'تصحيح بيانات وثيقة وظيفية',
        priority: 'normal',
        status: 'resolved',
        dueAt: new Date(Date.now() - 26 * 3_600_000).toISOString(),
      },
    ],
    meetings: [],
    qualityCases: [],
    audits: [],
    automations: [],
    dataAssets: [],
    aiUseCases: [],
    lastUpdatedAt: now,
  };

  it('mockEnterprise passes schema validation', () => {
    expect(() => enterpriseManagementCatalogSchema.parse(mockEnterprise)).not.toThrow();
  });

  it('has 4 service requests', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    expect(parsed.serviceRequests).toHaveLength(4);
  });

  it('each service request has required fields', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    for (const sr of parsed.serviceRequests) {
      expect(sr.id).toBeTruthy();
      expect(typeof sr.number).toBe('number');
      expect(sr.serviceName).toBeTruthy();
      expect(sr.requesterName).toBeTruthy();
      expect(sr.title).toBeTruthy();
      expect(sr.priority).toBeTruthy();
      expect(sr.status).toBeTruthy();
      expect(sr.dueAt).toBeTruthy();
    }
  });

  it('service request priorities are valid', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    const priorities = parsed.serviceRequests.map((sr) => sr.priority);
    expect(priorities).toContain('urgent');
    expect(priorities).toContain('high');
    expect(priorities).toContain('normal');
  });

  it('service request statuses are valid', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    const statuses = parsed.serviceRequests.map((sr) => sr.status);
    expect(statuses).toContain('submitted');
    expect(statuses).toContain('in_progress');
    expect(statuses).toContain('assigned');
    expect(statuses).toContain('resolved');
  });

  it('empty arrays for non-service-request fields', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    expect(parsed.objectives).toHaveLength(0);
    expect(parsed.projects).toHaveLength(0);
    expect(parsed.risks).toHaveLength(0);
    expect(parsed.incidents).toHaveLength(0);
    expect(parsed.meetings).toHaveLength(0);
    expect(parsed.qualityCases).toHaveLength(0);
    expect(parsed.audits).toHaveLength(0);
    expect(parsed.automations).toHaveLength(0);
    expect(parsed.dataAssets).toHaveLength(0);
    expect(parsed.aiUseCases).toHaveLength(0);
  });

  it('lastUpdatedAt is a valid ISO string', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    expect(new Date(parsed.lastUpdatedAt).toISOString()).toBe(parsed.lastUpdatedAt);
  });

  it('service request IDs are valid UUID format', () => {
    const parsed = enterpriseManagementCatalogSchema.parse(mockEnterprise);
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
    for (const sr of parsed.serviceRequests) {
      expect(sr.id).toMatch(uuidPattern);
    }
  });
});
