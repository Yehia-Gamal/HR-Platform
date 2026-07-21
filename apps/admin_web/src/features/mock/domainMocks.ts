import type {
  ActionCenterItem,
  AttendanceDashboard,
  KpiEvaluationSummary,
  LeaveBalance,
  OfficialFeedItem,
  RequestSummary,
} from '@ahla/shared-contracts';
import type {
  AuditSecurityData,
  IntegrationCenterData,
  LocationDirectoryItem,
  OperationsCenterData,
} from '../management/controlCenterTypes';

const now = new Date();
const iso = (offsetHours = 0) => new Date(now.getTime() + offsetHours * 3_600_000).toISOString();

export const mockAttendanceDashboard: AttendanceDashboard = {
  scheduled: 54,
  present: 45,
  late: 5,
  absent: 4,
  incomplete: 3,
  pendingReview: 2,
  lastUpdatedAt: iso(),
};

export const mockRequests: RequestSummary[] = [
  {
    id: '41000000-0000-4000-8000-000000000001',
    requestNumber: 1042,
    requestType: 'leave',
    employeeId: '30000000-0000-4000-8000-000000000001',
    employeeName: 'أحمد محمود',
    employeeCode: 'EMP-104',
    title: 'إجازة اعتيادية',
    reason: 'ظرف عائلي',
    status: 'pending',
    workflowStatus: 'in_review',
    currentStepOrder: 2,
    activeStepName: 'مراجعة HR',
    decisionDueAt: iso(8),
    createdAt: iso(-20),
  },
  {
    id: '41000000-0000-4000-8000-000000000002',
    requestNumber: 1041,
    requestType: 'mission',
    employeeId: '30000000-0000-4000-8000-000000000002',
    employeeName: 'محمود علي',
    employeeCode: 'EMP-087',
    title: 'مأمورية ميدانية',
    reason: 'متابعة حالة وتوثيق الزيارة',
    status: 'approved',
    workflowStatus: 'completed',
    currentStepOrder: 3,
    activeStepName: null,
    decisionDueAt: null,
    createdAt: iso(-32),
  },
  {
    id: '41000000-0000-4000-8000-000000000003',
    requestNumber: 1039,
    requestType: 'attendance_permit',
    employeeId: '30000000-0000-4000-8000-000000000003',
    employeeName: 'سارة حسن',
    employeeCode: 'EMP-132',
    title: 'إذن تأخير',
    reason: 'موعد طبي',
    status: 'pending',
    workflowStatus: 'awaiting_manager',
    currentStepOrder: 1,
    activeStepName: 'اعتماد المدير المباشر',
    decisionDueAt: iso(2),
    createdAt: iso(-3),
  },
];

export const mockKpiEvaluations: KpiEvaluationSummary[] = [
  {
    id: '42000000-0000-4000-8000-000000000001',
    employeeId: '30000000-0000-4000-8000-000000000001',
    employeeName: 'أحمد محمود',
    employeeCode: 'EMP-104',
    cycleId: '43000000-0000-4000-8000-000000000001',
    periodMonth: '2026-07-01',
    currentStage: 'manager',
    finalScore: null,
    finalRating: null,
    locked: false,
    updatedAt: iso(-5),
  },
  {
    id: '42000000-0000-4000-8000-000000000002',
    employeeId: '30000000-0000-4000-8000-000000000002',
    employeeName: 'محمود علي',
    employeeCode: 'EMP-087',
    cycleId: '43000000-0000-4000-8000-000000000001',
    periodMonth: '2026-07-01',
    currentStage: 'secretary',
    finalScore: null,
    finalRating: null,
    locked: false,
    updatedAt: iso(-12),
  },
  {
    id: '42000000-0000-4000-8000-000000000003',
    employeeId: '30000000-0000-4000-8000-000000000003',
    employeeName: 'سارة حسن',
    employeeCode: 'EMP-132',
    cycleId: '43000000-0000-4000-8000-000000000001',
    periodMonth: '2026-07-01',
    currentStage: 'executive',
    finalScore: 88,
    finalRating: 'ممتاز',
    locked: false,
    updatedAt: iso(-2),
  },
];

export const mockOfficialFeed: OfficialFeedItem[] = [
  {
    id: '44000000-0000-4000-8000-000000000001',
    kind: 'decision',
    title: 'قرار تنظيم تسليم التقارير الأسبوعية',
    body: 'تسلم التقارير الأسبوعية قبل نهاية دوام يوم الخميس، مع بيان الإنجاز والمعوقات وخطة الأسبوع التالي.',
    category: 'executive',
    priority: 'high',
    status: 'published',
    requiresAcknowledgement: true,
    publishedAt: iso(-10),
    expiresAt: null,
    acknowledgedCount: 39,
    targetCount: 54,
  },
  {
    id: '44000000-0000-4000-8000-000000000002',
    kind: 'announcement',
    title: 'موعد اجتماع مناقشة النظام الجديد',
    body: 'يعقد الاجتماع في القاعة الرئيسية لمراجعة استخدام التطبيق ومسارات الموافقات الجديدة.',
    category: 'event',
    priority: 'normal',
    status: 'published',
    requiresAcknowledgement: false,
    publishedAt: iso(-28),
    expiresAt: iso(48),
    acknowledgedCount: 0,
    targetCount: null,
  },
];

export const mockActionCenter: ActionCenterItem[] = [
  {
    id: 'action-request-1',
    kind: 'request',
    title: 'إذن تأخير يحتاج اعتماد المدير',
    subtitle: 'سارة حسن · EMP-132',
    priority: 'urgent',
    status: 'awaiting_manager',
    dueAt: iso(2),
    actionUrl: '/hr/requests',
    sourceUpdatedAt: iso(-1),
  },
  {
    id: 'action-kpi-1',
    kind: 'kpi',
    title: 'تقييم جاهز للمراجعة التنفيذية',
    subtitle: 'سارة حسن · دورة يوليو 2026',
    priority: 'high',
    status: 'executive',
    dueAt: iso(24),
    actionUrl: '/hr/performance',
    sourceUpdatedAt: iso(-2),
  },
  {
    id: 'action-decision-1',
    kind: 'decision',
    title: 'قرار نسبة الاطلاع عليه أقل من المستهدف',
    subtitle: '39 من 54 موظفًا أقروا بالاطلاع',
    priority: 'normal',
    status: 'published',
    dueAt: iso(36),
    actionUrl: '/admin/official-feed',
    sourceUpdatedAt: iso(-10),
  },
];

export const mockDashboardOverview = {
  employees: 54, activeEmployees: 51, pendingRequests: 6, attendancePendingReview: 2,
  pendingKpi: 9, openRequisitions: 3, urgentActions: 2, publishedDecisions: 7,
  unresolvedErrors: 1, lastUpdatedAt: iso(),
};

export const mockOrganizationOverview = {
  legalEntities: 1, branches: 1, workSites: 2, departments: 8, teams: 14, positions: 61,
  vacantPositions: 7, managerRelations: 49,
  recentDepartments: [
    { id: '51000000-0000-4000-8000-000000000001', name: 'إدارة التشغيل', active: true },
    { id: '51000000-0000-4000-8000-000000000002', name: 'الموارد البشرية', active: true },
    { id: '51000000-0000-4000-8000-000000000003', name: 'العلاقات العامة', active: true },
  ],
  recentPositions: [
    { id: '52000000-0000-4000-8000-000000000001', code: 'POS-OPS-01', title: 'مسؤول تشغيل', status: 'active' },
    { id: '52000000-0000-4000-8000-000000000002', code: 'POS-HR-01', title: 'أخصائي موارد بشرية', status: 'active' },
  ], lastUpdatedAt: iso(),
};

export const mockAccessOverview = {
  roles: 12, permissions: 186, activeAssignments: 61, sensitivePermissions: 38, expiringAssignments: 3,
  rolesList: [
    { id: '53000000-0000-4000-8000-000000000001', slug: 'admin', name: 'الأدمن الرئيسي', isFullAccess: true, permissionCount: 186, userCount: 1 },
    { id: '53000000-0000-4000-8000-000000000002', slug: 'hr-manager', name: 'مدير الموارد البشرية', isFullAccess: false, permissionCount: 46, userCount: 2 },
    { id: '53000000-0000-4000-8000-000000000003', slug: 'direct-manager', name: 'مدير مباشر', isFullAccess: false, permissionCount: 19, userCount: 8 },
    { id: '53000000-0000-4000-8000-000000000004', slug: 'employee', name: 'موظف', isFullAccess: false, permissionCount: 12, userCount: 50 },
  ], lastUpdatedAt: iso(),
};

export const mockRecruitmentOverview = {
  requisitions: 8, pendingRequisitions: 2, openPostings: 3, candidates: 47, activeApplications: 21, hiredApplications: 6,
  pipeline: [{ stage: 'active', count: 21 }, { stage: 'hired', count: 6 }, { stage: 'rejected', count: 14 }, { stage: 'withdrawn', count: 2 }],
  recentRequisitions: [
    { id: '54000000-0000-4000-8000-000000000001', title: 'مسؤول تشغيل ميداني', department: 'إدارة التشغيل', headcount: 3, status: 'posted', createdAt: iso(-72) },
    { id: '54000000-0000-4000-8000-000000000002', title: 'أخصائي موارد بشرية', department: 'الموارد البشرية', headcount: 1, status: 'pending', createdAt: iso(-96) },
  ], lastUpdatedAt: iso(),
};

export const mockSystemOverview = {
  enabledFlags: 5, totalFlags: 8, unresolvedErrors: 1, fatalErrors: 0,
  latestBackupStatus: 'completed', latestBackupAt: iso(-12), settingsCount: 24,
  recentErrors: [{ id: '55000000-0000-4000-8000-000000000001', level: 'warning', source: 'edge', message: 'تأخر مؤقت في تسليم إشعار Push', occurredAt: iso(-2) }],
  flags: [
    { id: '56000000-0000-4000-8000-000000000001', key: 'official_feed', name: 'القناة الرسمية', enabled: true, rolloutPercent: 100, environment: 'all' },
    { id: '56000000-0000-4000-8000-000000000002', key: 'executive_workspace', name: 'مساحة المدير التنفيذي', enabled: true, rolloutPercent: 100, environment: 'all' },
    { id: '56000000-0000-4000-8000-000000000003', key: 'live_location_video', name: 'فيديو التحقق الحي', enabled: false, rolloutPercent: 0, environment: 'staging' },
  ], lastUpdatedAt: iso(),
};

export const mockNotifications = [
  { id: '57000000-0000-4000-8000-000000000001', title: 'طلب جديد يحتاج المراجعة', body: 'تم تقديم طلب إجازة جديد من أحمد محمود.', category: 'request', priority: 'high' as const, actionUrl: '/hr/requests', isRead: false, createdAt: iso(-1) },
  { id: '57000000-0000-4000-8000-000000000002', title: 'قرار إداري جديد', body: 'تم نشر قرار تنظيم التقارير الأسبوعية.', category: 'decision', priority: 'normal' as const, actionUrl: '/admin/official-feed', isRead: false, createdAt: iso(-6) },
  { id: '57000000-0000-4000-8000-000000000003', title: 'اكتمل النسخ الاحتياطي', body: 'اكتملت آخر عملية نسخ احتياطي بنجاح.', category: 'system', priority: 'low' as const, actionUrl: '/admin/settings', isRead: true, createdAt: iso(-12) },
];

export const mockLeaveBalances: LeaveBalance[] = [
  { leaveTypeId: '11111111-1111-4111-8111-111111111111', code: 'annual', nameAr: 'اعتيادية', availableUnits: 18, reservedUnits: 2, consumedUnits: 5, expiresAt: null },
  { leaveTypeId: '22222222-2222-4222-8222-222222222222', code: 'emergency', nameAr: 'عارضة', availableUnits: 4, reservedUnits: 0, consumedUnits: 2, expiresAt: null },
];

const controlIds = {
  employee1: '10000000-0000-4000-8000-000000000001',
  employee2: '10000000-0000-4000-8000-000000000002',
  employee3: '10000000-0000-4000-8000-000000000003',
  employee4: '10000000-0000-4000-8000-000000000004',
};

const ago = (minutes: number) => new Date(now.getTime() - minutes * 60_000).toISOString();
const later = (hours: number) => new Date(now.getTime() + hours * 3_600_000).toISOString();

export const mockLocations: LocationDirectoryItem[] = [
  { id: controlIds.employee1, name: 'أحمد محمود', employeeCode: 'EMP-1042', jobTitle: 'مشرف تشغيل', department: 'العمليات', lastLatitude: 30.0444, lastLongitude: 31.2357, lastAccuracy: 8, lastRecordedAt: ago(3), activeRequestId: null, activeRequestStatus: null },
  { id: controlIds.employee2, name: 'سارة عادل', employeeCode: 'EMP-1088', jobTitle: 'أخصائي موارد بشرية', department: 'الموارد البشرية', lastLatitude: 30.0512, lastLongitude: 31.2241, lastAccuracy: 18, lastRecordedAt: ago(14), activeRequestId: '20000000-0000-4000-8000-000000000001', activeRequestStatus: 'accepted' },
  { id: controlIds.employee3, name: 'محمود فؤاد', employeeCode: 'EMP-1127', jobTitle: 'مسؤول ميداني', department: 'الخدمات الميدانية', lastLatitude: 30.0301, lastLongitude: 31.246, lastAccuracy: 74, lastRecordedAt: ago(92), activeRequestId: null, activeRequestStatus: null },
  { id: controlIds.employee4, name: 'منى حسن', employeeCode: 'EMP-1164', jobTitle: 'محاسب', department: 'المالية', lastLatitude: null, lastLongitude: null, lastAccuracy: null, lastRecordedAt: null, activeRequestId: '20000000-0000-4000-8000-000000000002', activeRequestStatus: 'pending' },
];

export const mockOperations: OperationsCenterData = {
  employees: mockLocations.map((item) => ({ id: item.id, name: item.name })),
  tasks: [
    { id: '30000000-0000-4000-8000-000000000001', title: 'مراجعة خطة تشغيل الفرع', description: 'اعتماد توزيع الورديات قبل بداية الأسبوع.', assigneeId: controlIds.employee1, assigneeName: 'أحمد محمود', priority: 'urgent', dueDate: later(6).slice(0, 10), status: 'in_progress' },
    { id: '30000000-0000-4000-8000-000000000002', title: 'تسوية عهدة الجهاز', description: null, assigneeId: controlIds.employee3, assigneeName: 'محمود فؤاد', priority: 'high', dueDate: later(28).slice(0, 10), status: 'pending' },
    { id: '30000000-0000-4000-8000-000000000003', title: 'تحديث كشف الموردين', description: null, assigneeId: controlIds.employee4, assigneeName: 'منى حسن', priority: 'medium', dueDate: later(72).slice(0, 10), status: 'done' },
  ],
  missions: [
    { id: '40000000-0000-4000-8000-000000000001', employeeName: 'محمود فؤاد', destination: 'فرع الجيزة', purpose: 'تسليم وتجهيز أجهزة التشغيل', startAt: later(4), endAt: later(10), status: 'approved', transportMode: 'company_vehicle' },
    { id: '40000000-0000-4000-8000-000000000002', employeeName: 'أحمد محمود', destination: 'المخزن الرئيسي', purpose: 'جرد تشغيلي مفاجئ', startAt: later(25), endAt: later(32), status: 'pending', transportMode: 'company_vehicle' },
  ],
  convoys: [
    { id: '50000000-0000-4000-8000-000000000001', employeeName: 'أحمد محمود', name: 'قافلة خدمة فرع أكتوبر', origin: 'المقر الرئيسي', destination: 'فرع أكتوبر', departureAt: later(48), returnAt: later(58), passengers: 12, vehicles: 2, status: 'approved' },
  ],
};

export const mockAudit: AuditSecurityData = {
  securityEvents: [
    { id: '60000000-0000-4000-8000-000000000001', eventType: 'login_failed', severity: 'high', outcome: 'blocked', handled: false, occurredAt: ago(7) },
    { id: '60000000-0000-4000-8000-000000000002', eventType: 'managed_device_registered', severity: 'low', outcome: 'allowed', handled: true, occurredAt: ago(35) },
    { id: '60000000-0000-4000-8000-000000000003', eventType: 'privilege_escalation_requested', severity: 'critical', outcome: 'detected', handled: false, occurredAt: ago(82) },
  ],
  auditEvents: [
    { id: '70000000-0000-4000-8000-000000000001', eventType: 'access.role_assigned', category: 'access', severity: 'notice', summary: 'إسناد دور مدير عمليات', targetTable: 'user_roles', occurredAt: ago(18) },
    { id: '70000000-0000-4000-8000-000000000002', eventType: 'employee.updated', category: 'data', severity: 'info', summary: 'تحديث البيانات الوظيفية', targetTable: 'employees', occurredAt: ago(49) },
    { id: '70000000-0000-4000-8000-000000000003', eventType: 'live_location.requested', category: 'security', severity: 'warning', summary: 'طلب موقع حي بسبب تشغيلي', targetTable: 'live_location_requests', occurredAt: ago(96) },
  ],
  devices: [
    { id: '80000000-0000-4000-8000-000000000001', name: 'Chrome — جهاز العمل', platform: 'web', appVersion: '0.10.0', environment: 'staging', trusted: true, status: 'active', lastSeenAt: ago(2) },
    { id: '80000000-0000-4000-8000-000000000002', name: 'Samsung A54', platform: 'android', appVersion: '0.10.0', environment: 'staging', trusted: true, status: 'active', lastSeenAt: ago(22) },
    { id: '80000000-0000-4000-8000-000000000003', name: 'iPhone 13', platform: 'ios', appVersion: '0.9.0', environment: 'production', trusted: false, status: 'revoked', lastSeenAt: ago(1440) },
  ],
};

export const mockIntegrations: IntegrationCenterData = {
  integrations: [
    { id: '90000000-0000-4000-8000-000000000001', name: 'بوابة البريد المؤسسي', provider: 'sendgrid', category: 'email', status: 'active', enabled: true, lastSyncAt: ago(4), lastError: null },
    { id: '90000000-0000-4000-8000-000000000002', name: 'نظام ERP المالي', provider: 'sap', category: 'erp', status: 'error', enabled: true, lastSyncAt: ago(65), lastError: 'انتهت مهلة الاتصال بعد 30 ثانية' },
    { id: '90000000-0000-4000-8000-000000000003', name: 'Webhook القرارات', provider: 'webhook', category: 'webhook', status: 'inactive', enabled: false, lastSyncAt: null, lastError: null },
  ],
  logs: [
    { id: '91000000-0000-4000-8000-000000000001', integrationId: '90000000-0000-4000-8000-000000000001', operation: 'send_email', direction: 'outbound', status: 'success', httpStatus: 202, durationMs: 184, occurredAt: ago(4), error: null },
    { id: '91000000-0000-4000-8000-000000000002', integrationId: '90000000-0000-4000-8000-000000000002', operation: 'sync_payroll', direction: 'outbound', status: 'failed', httpStatus: 504, durationMs: 30_000, occurredAt: ago(65), error: 'Gateway timeout' },
  ],
  outbox: [
    { id: '92000000-0000-4000-8000-000000000001', eventType: 'employee.updated', status: 'pending', attempts: 0, maxAttempts: 8, nextAttemptAt: later(0.1), createdAt: ago(1), error: null },
    { id: '92000000-0000-4000-8000-000000000002', eventType: 'payroll.closed', status: 'retrying', attempts: 3, maxAttempts: 8, nextAttemptAt: later(0.5), createdAt: ago(38), error: 'ERP endpoint unavailable' },
    { id: '92000000-0000-4000-8000-000000000003', eventType: 'decision.published', status: 'delivered', attempts: 1, maxAttempts: 8, nextAttemptAt: ago(20), createdAt: ago(21), error: null },
  ],
  automationRuns: [
    { id: '93000000-0000-4000-8000-000000000001', status: 'succeeded', attempts: 1, createdAt: ago(12), completedAt: ago(11), error: null },
    { id: '93000000-0000-4000-8000-000000000002', status: 'failed', attempts: 2, createdAt: ago(70), completedAt: ago(66), error: 'تعذر إنشاء الإشعار' },
  ],
};
