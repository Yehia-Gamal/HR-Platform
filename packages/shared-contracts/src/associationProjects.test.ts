import { describe, expect, it } from 'vitest';
import { associationProjectDetailSchema, associationProjectsCatalogSchema } from './associationProjects';

const legacyProject = {
  id: '55300000-0000-4000-8000-000000000001',
  code: 'PRJ-001',
  name: 'مشروع',
  description: null,
  departmentId: '55300000-0000-4000-8000-000000000002',
  departmentName: 'إدارة',
  ownerId: '55300000-0000-4000-8000-000000000003',
  ownerName: 'موظف',
  status: 'active',
  approvalStatus: 'approved',
  priority: 'high',
  progress: 40,
  startDate: null,
  targetEndDate: null,
  lastUpdateAt: null,
  lastUpdateNote: null,
  approvedBy: null,
  approvedAt: null,
  rejectionReason: null,
  totalSteps: 2,
  completedSteps: 1,
  remainingSteps: 1,
  blockedSteps: 0,
  ledStatus: 'stale',
};

describe('associationProjects contract (0553)', () => {
  it('يقبل استجابة ما قبل 0553 ويملأ الحقول الجديدة بقيم افتراضية', () => {
    const parsed = associationProjectsCatalogSchema.parse({ projects: [legacyProject], lastUpdatedAt: '2026-09-24T00:00:00Z', isFullAccess: true });
    expect(parsed.recentUpdates).toEqual([]);
    expect(parsed.settings).toEqual({ warningDays: 7, criticalDays: 14 });
    expect(parsed.projects[0]?.canManage).toBe(false);
    expect(parsed.projects[0]?.overdueSteps).toBe(0);
  });

  it('يقبل حالات اللمبة الجديدة critical و completed', () => {
    for (const ledStatus of ['critical', 'completed'] as const) {
      expect(() => associationProjectsCatalogSchema.parse({ projects: [{ ...legacyProject, ledStatus }], lastUpdatedAt: 'x' })).not.toThrow();
    }
  });

  it('يرفض حالة لمبة مجهولة', () => {
    expect(() => associationProjectsCatalogSchema.parse({ projects: [{ ...legacyProject, ledStatus: 'blinking' }], lastUpdatedAt: 'x' })).toThrow();
  });

  it('تفاصيل المشروع تقبل الصلاحيات المحسوبة من الخادم', () => {
    const parsed = associationProjectDetailSchema.parse({
      project: { ...legacyProject, ledStatus: 'critical', daysSinceActivity: 20, canManage: true },
      steps: [],
      updates: [],
      permissions: { canManage: true, canApprove: false, canEdit: false, canSubmit: false, canUpdate: true, canDelete: false },
    });
    expect(parsed.permissions?.canUpdate).toBe(true);
    expect(parsed.project.daysSinceActivity).toBe(20);
  });
});
