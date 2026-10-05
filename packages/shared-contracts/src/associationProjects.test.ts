import { describe, expect, it } from 'vitest';
import { associationProjectDetailSchema, associationProjectPickersSchema, associationProjectsCatalogSchema, myProjectTasksSchema } from './associationProjects';

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

  it('0645: مشروع فريق بلا إدارة — القائد والأعضاء والصفة', () => {
    const parsed = associationProjectsCatalogSchema.parse({
      projects: [
        {
          ...legacyProject,
          departmentId: null,
          departmentName: null,
          departments: [],
          leaderId: legacyProject.ownerId,
          leaderName: 'موظف',
          members: [
            { employeeId: legacyProject.ownerId, name: 'موظف', jobTitle: null, departmentName: 'إدارة', isLeader: true },
            { employeeId: '55300000-0000-4000-8000-000000000009', name: 'زميل', jobTitle: 'منسق', departmentName: null, isLeader: false },
          ],
          myRole: 'member',
          canEdit: false,
        },
      ],
      lastUpdatedAt: 'x',
      myEmployeeId: '55300000-0000-4000-8000-000000000009',
    });
    const p = parsed.projects[0]!;
    expect(p.departmentName).toBe('');
    expect(p.members.filter((m) => m.isLeader)).toHaveLength(1);
    expect(p.myRole).toBe('member');
  });

  it('0645: الاستجابة القديمة تُملأ بفريق فارغ', () => {
    const parsed = associationProjectsCatalogSchema.parse({ projects: [legacyProject], lastUpdatedAt: 'x' });
    expect(parsed.projects[0]?.members).toEqual([]);
    expect(parsed.projects[0]?.myRole).toBeNull();
    expect(parsed.myEmployeeId).toBeNull();
  });

  it('0645: قائمة اختيار الفريق', () => {
    const parsed = associationProjectPickersSchema.parse({
      employees: [{ id: '55300000-0000-4000-8000-000000000009', name: 'زميل', jobTitle: null, departmentId: null, departmentName: null }],
      departments: [],
    });
    expect(parsed.employees[0]?.name).toBe('زميل');
  });

  it('0647: مهامي عبر المشاريع', () => {
    const parsed = myProjectTasksSchema.parse([
      {
        stepId: '55300000-0000-4000-8000-000000000011',
        title: 'تجهيز',
        status: 'in_progress',
        dueDate: '2026-10-01',
        isOverdue: true,
        projectId: legacyProject.id,
        projectName: 'مشروع',
        projectStatus: 'active',
        approvalStatus: 'approved',
      },
    ]);
    expect(parsed[0]?.isDueSoon).toBe(false);
    expect(parsed[0]?.leaderName).toBeNull();
  });
});
