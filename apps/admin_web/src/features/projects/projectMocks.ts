import type { AssociationProjectDetail, AssociationProjectListItem, AssociationProjectsCatalog } from '@ahla/shared-contracts';

// بيانات المعاينة المحلية (VITE_ENABLE_DEV_MOCKS) — تغطي كل حالات اللمبة.
const DEPT_IT = '00000000-0000-4000-8000-0000000000d1';
const DEPT_HR = '00000000-0000-4000-8000-0000000000d2';
const DEPT_MEDIA = '00000000-0000-4000-8000-0000000000d3';
const DEPT_LOG = '00000000-0000-4000-8000-0000000000d4';

const daysAgo = (d: number) => new Date(Date.now() - d * 86_400_000).toISOString();
const dateIn = (d: number) => new Date(Date.now() + d * 86_400_000).toISOString().slice(0, 10);
const id = (n: number) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

function project(n: number, p: Partial<AssociationProjectListItem>): AssociationProjectListItem {
  return {
    id: id(n),
    code: `PRJ-2026-${String(n).padStart(3, '0')}`,
    name: '',
    description: null,
    departmentId: DEPT_IT,
    departmentName: 'تقنية المعلومات',
    ownerId: id(900 + n),
    ownerName: 'أحمد محمد',
    status: 'active',
    approvalStatus: 'approved',
    priority: 'medium',
    progress: 0,
    startDate: dateIn(-60),
    targetEndDate: dateIn(60),
    lastUpdateAt: null,
    lastUpdateNote: null,
    lastActivityAt: null,
    daysSinceActivity: null,
    approvedBy: null,
    approvedAt: daysAgo(60),
    rejectionReason: null,
    totalSteps: 0,
    completedSteps: 0,
    inProgressSteps: 0,
    remainingSteps: 0,
    blockedSteps: 0,
    overdueSteps: 0,
    currentStepTitle: null,
    isOverdue: false,
    canManage: true,
    ledStatus: 'active',
    ...p,
  };
}

function withActivity(days: number): Pick<AssociationProjectListItem, 'lastActivityAt' | 'daysSinceActivity' | 'lastUpdateAt'> {
  return { lastActivityAt: daysAgo(days), daysSinceActivity: days, lastUpdateAt: daysAgo(days) };
}

export const MOCK_PROJECTS: AssociationProjectListItem[] = [
  project(1, {
    name: 'تطبيق إدارة الحضور',
    description: 'تطبيق موبايل لتسجيل حضور الموظفين بالبصمة والموقع.',
    priority: 'critical',
    progress: 75,
    totalSteps: 8,
    completedSteps: 6,
    inProgressSteps: 1,
    remainingSteps: 2,
    currentStepTitle: 'اختبار النسخة التجريبية مع الإدارات',
    lastUpdateNote: 'تم تسليم النسخة التجريبية',
    ...withActivity(1),
  }),
  project(2, {
    name: 'حملة كفالة الأيتام — رمضان',
    departmentId: DEPT_MEDIA,
    departmentName: 'الإعلام والتسويق',
    ownerName: 'سارة علي',
    priority: 'high',
    progress: 40,
    totalSteps: 5,
    completedSteps: 2,
    remainingSteps: 3,
    currentStepTitle: 'تصوير الفيديوهات الترويجية',
    ...withActivity(9),
    ledStatus: 'halted',
  }),
  project(3, {
    name: 'تجهيز مخزن المساعدات الجديد',
    departmentId: DEPT_LOG,
    departmentName: 'الخدمات اللوجستية',
    ownerName: 'محمد حسن',
    priority: 'high',
    progress: 20,
    totalSteps: 6,
    completedSteps: 1,
    blockedSteps: 1,
    remainingSteps: 5,
    overdueSteps: 2,
    currentStepTitle: 'التعاقد مع مورد الأرفف',
    isOverdue: true,
    targetEndDate: dateIn(-5),
    ...withActivity(23),
    ledStatus: 'critical',
  }),
  project(4, {
    name: 'نظام تقييم الأداء الشهري',
    departmentId: DEPT_HR,
    departmentName: 'الموارد البشرية',
    ownerName: 'منى إبراهيم',
    status: 'on_hold',
    progress: 55,
    totalSteps: 4,
    completedSteps: 2,
    remainingSteps: 2,
    currentStepTitle: 'اعتماد معايير التقييم',
    ...withActivity(3),
    ledStatus: 'halted',
  }),
  project(5, {
    name: 'قافلة طبية — قرى الصعيد',
    departmentId: DEPT_LOG,
    departmentName: 'الخدمات اللوجستية',
    ownerName: 'محمد حسن',
    status: 'completed',
    progress: 100,
    totalSteps: 5,
    completedSteps: 5,
    ...withActivity(40),
    ledStatus: 'completed',
  }),
  project(6, {
    name: 'منصة التطوع الإلكترونية',
    ownerName: 'أحمد محمد',
    status: 'planned',
    approvalStatus: 'pending_approval',
    approvedAt: null,
    priority: 'medium',
    ledStatus: 'pending',
  }),
  project(7, {
    name: 'برنامج تدريب المتطوعين الجدد',
    departmentId: DEPT_HR,
    departmentName: 'الموارد البشرية',
    ownerName: 'منى إبراهيم',
    status: 'planned',
    approvalStatus: 'draft',
    approvedAt: null,
    priority: 'low',
    ledStatus: 'draft',
  }),
  project(8, {
    name: 'تطبيق التواصل الداخلي',
    status: 'planned',
    approvalStatus: 'rejected',
    approvedAt: null,
    rejectionReason: 'يجب دراسة البدائل المتوفرة في السوق أولاً',
    ledStatus: 'rejected',
  }),
];

export function mockCatalog(): AssociationProjectsCatalog {
  return {
    projects: MOCK_PROJECTS,
    recentUpdates: MOCK_PROJECTS.filter((p) => p.lastUpdateAt).map((p, i) => ({
      id: id(500 + i),
      projectId: p.id,
      projectName: p.name,
      projectCode: p.code,
      note: p.lastUpdateNote ?? 'تحديث دوري على سير العمل',
      progress: p.progress,
      statusChange: null,
      authorName: p.ownerName,
      createdAt: p.lastUpdateAt ?? p.approvedAt ?? new Date().toISOString(),
    })),
    lastUpdatedAt: new Date().toISOString(),
    isFullAccess: true,
    canCreate: true,
    myDepartmentId: DEPT_IT,
    settings: { warningDays: 7, criticalDays: 14 },
  };
}

const STEP_TITLES = [
  'دراسة الاحتياج وتحديد النطاق',
  'اعتماد الميزانية',
  'التعاقد مع الموردين',
  'التنفيذ — المرحلة الأولى',
  'التنفيذ — المرحلة الثانية',
  'اختبار النسخة التجريبية مع الإدارات',
  'التدريب والتسليم',
  'التقييم النهائي',
];

export function mockDetail(projectId: string): AssociationProjectDetail {
  const p = MOCK_PROJECTS.find((x) => x.id === projectId) ?? (MOCK_PROJECTS[0] as AssociationProjectListItem);
  const steps = STEP_TITLES.slice(0, p.totalSteps).map((title, i) => {
    const status =
      i < p.completedSteps ? 'done' : i === p.completedSteps && p.blockedSteps > 0 ? 'blocked' : i === p.completedSteps ? 'in_progress' : 'pending';
    return {
      id: id(700 + i),
      title,
      description: null,
      sortOrder: i + 1,
      status: status as 'done' | 'blocked' | 'in_progress' | 'pending',
      dueDate: dateIn(i * 7 - 21),
      assigneeId: null,
      assigneeName: i % 2 ? p.ownerName : 'خالد عمر',
      completedAt: status === 'done' ? daysAgo(30 - i * 3) : null,
      updatedAt: daysAgo(5),
    };
  });
  const approved = p.approvalStatus === 'approved';
  const editable = p.approvalStatus === 'draft' || p.approvalStatus === 'rejected';
  return {
    project: p,
    steps,
    updates: p.lastUpdateAt
      ? [
          { id: id(801), note: p.lastUpdateNote ?? 'تحديث دوري', progress: p.progress, statusChange: null, authorName: p.ownerName, createdAt: p.lastUpdateAt },
          { id: id(802), note: 'بدء التنفيذ بعد الاعتماد', progress: 10, statusChange: 'active', authorName: p.ownerName, createdAt: daysAgo(50) },
        ]
      : [],
    permissions: {
      canManage: true,
      canApprove: p.approvalStatus === 'pending_approval',
      canEdit: true,
      canSubmit: editable,
      canUpdate: approved,
      canDelete: true,
    },
  };
}
