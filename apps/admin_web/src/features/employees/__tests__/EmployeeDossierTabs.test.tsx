import { render, screen, renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { EmployeeKpiTab } from '../EmployeeKpiTab';
import { EmployeeLeaveTab } from '../EmployeeLeaveTab';
import { EmployeeLocationTab } from '../EmployeeLocationTab';
import { EmployeeReportsTab } from '../EmployeeReportsTab';
import { EmployeeTasksTab } from '../EmployeeTasksTab';
import {
  useEmployeeDailyReports,
  useEmployeeKpiEvaluations,
  useEmployeeLocationRequests,
  useEmployeePublishedDecisions,
  useEmployeeTasks,
} from '../useEmployeeDossier';
import { rpc } from '../../../core/rpc';

const EMPLOYEE_ID = '00000000-0000-4000-8000-000000000000';

const mockAccess = {
  userId: '00000000-0000-4000-8000-000000000001',
  employeeId: '00000000-0000-4000-8000-000000000002',
  displayName: 'مختبر',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: {
    attendanceRequired: false,
    selfPunchEnabled: false,
    liveLocationResponseEnabled: false,
  },
};

let isMockValue = true;
vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'authenticated',
    session: null,
    access: mockAccess,
    error: null,
    isMock: isMockValue,
  }),
}));

vi.mock('../../../core/rpc', () => ({
  rpc: vi.fn(),
}));

vi.mock('../../leaves/useLeaves', () => ({
  useAdminLeaves: () => ({
    data: { rows: [], total: 0 },
    isLoading: false,
    isError: false,
    error: null,
    refetch: vi.fn(),
  }),
}));

vi.mock('../../management/useEnterpriseOperations', () => ({
  useReportSchedulerCatalog: () => ({
    data: { schedules: [] },
    isLoading: false,
    isError: false,
    error: null,
    refetch: vi.fn(),
  }),
}));

const locationRow = {
  id: '11111111-1111-4111-8111-111111111111',
  requestedByName: 'سارة',
  reason: 'مهمة ميدانية',
  status: 'approved',
  purpose: 'verification',
  requestedAt: '2026-08-01T10:00:00Z',
  respondedAt: null,
  startsAt: null,
  expiresAt: null,
  durationMinutes: 120,
};

const taskRow = {
  id: '22222222-2222-4222-8222-222222222222',
  title: 'مراجعة التقارير',
  description: 'مراجعة كشف الحضور',
  priority: 'high',
  status: 'in_progress',
  dueDate: '2026-08-15',
  createdAt: '2026-08-01T09:00:00Z',
  createdByName: 'خالد',
};

const kpiRow = {
  id: '33333333-3333-4333-8333-333333333333',
  periodMonth: '2026-07',
  currentStage: 'finalized',
  workflowStatus: 'approved',
  cycleStatus: 'active',
  finalScore: 92.5,
  finalRating: 'ممتاز',
  managerComment: null,
  hrComment: null,
  locked: true,
  updatedAt: '2026-08-05T10:00:00Z',
};

const decisionRow = {
  id: '44444444-4444-4444-8444-444444444444',
  decisionNumber: 'ق-2026-01',
  title: 'قرار منح بدل انتقال',
  category: 'financial',
  effectiveDate: '2026-08-01',
  expiryDate: null,
  publishedAt: '2026-07-20T08:00:00Z',
  isRead: true,
  acknowledged: true,
};

const dailyReportRow = {
  id: '55555555-5555-4555-8555-555555555555',
  employeeId: '00000000-0000-4000-8000-000000000000',
  employeeName: null,
  reportDate: '2026-08-01',
  achievements: 'أنهيت مهام الأسبوع',
  blockers: null,
  tomorrowPlan: null,
  managerComment: null,
  reviewerName: null,
  reviewedAt: null,
  createdAt: '2026-08-01T15:00:00Z',
};

function makeQueryClient() {
  return new QueryClient({ defaultOptions: { queries: { retry: false } } });
}

function renderTab(ui: ReactNode) {
  const client = makeQueryClient();
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
}

const rpcMock = vi.mocked(rpc);

beforeEach(() => {
  isMockValue = true;
  rpcMock.mockReset();
  rpcMock.mockImplementation(async (name: string) => {
    if (name === 'get_employee_location_requests') return [locationRow];
    if (name === 'get_employee_tasks_admin') return [taskRow];
    if (name === 'get_employee_kpi_evaluations_admin') return [kpiRow];
    if (name === 'get_mobile_daily_reports') return [dailyReportRow];
    if (name === 'get_employee_published_decisions_admin') return [decisionRow];
    return [];
  });
});

describe('تبويبات ملف الموظف الشامل', () => {
  it('تعرض حالة فارغة لكل تبويب عندما لا توجد بيانات', async () => {
    isMockValue = true;
    renderTab(<EmployeeLocationTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('لا توجد طلبات مواقع')).toBeDefined();
  });

  it('تعرض صفوف طلبات المواقع عبر RPC', async () => {
    isMockValue = false;
    renderTab(<EmployeeLocationTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('مهمة ميدانية')).toBeDefined();
    expect(rpcMock).toHaveBeenCalledWith('get_employee_location_requests', { p_employee_id: EMPLOYEE_ID });
  });

  it('تعرض صفوف المهام عبر RPC', async () => {
    isMockValue = false;
    renderTab(<EmployeeTasksTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('مراجعة التقارير')).toBeDefined();
    expect(rpcMock).toHaveBeenCalledWith('get_employee_tasks_admin', { p_employee_id: EMPLOYEE_ID });
  });

  it('تعرض صفوف تقييمات الأداء عبر RPC', async () => {
    isMockValue = false;
    renderTab(<EmployeeKpiTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('ممتاز')).toBeDefined();
    expect(rpcMock).toHaveBeenCalledWith('get_employee_kpi_evaluations_admin', { p_employee_id: EMPLOYEE_ID });
  });

  it('تعرض التقارير اليومية والقرارات في تبويب التقارير', async () => {
    isMockValue = false;
    renderTab(<EmployeeReportsTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('أنهيت مهام الأسبوع')).toBeDefined();
    expect(await screen.findByText('قرار منح بدل انتقال')).toBeDefined();
  });

  it('تعرض حالة الخطأ لكل تبويب عند فشل RPC', async () => {
    isMockValue = false;
    rpcMock.mockRejectedValueOnce(new Error('network error'));
    renderTab(<EmployeeLocationTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('تعذر تحميل طلبات المواقع')).toBeDefined();
  });

  it('تبويب الإجازات يعرض الحالة الفارغة عبر hook الإجازات', async () => {
    renderTab(<EmployeeLeaveTab employeeId={EMPLOYEE_ID} />);
    expect(await screen.findByText('لا توجد إجازات')).toBeDefined();
  });
});

describe('hooks ملف الموظف الشامل', () => {
  it('تعيد مصفوفة فارغة في وضع المعاينة دون استدعاء RPC', async () => {
    isMockValue = true;
    const client = makeQueryClient();
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    );

    const { result } = renderHook(() => useEmployeeLocationRequests(EMPLOYEE_ID), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toEqual([]);
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('تستدعي RPC الصحيح لكل دالة عند الخروج من وضع المعاينة', async () => {
    isMockValue = false;
    const client = makeQueryClient();
    const wrapper = ({ children }: { children: ReactNode }) => (
      <QueryClientProvider client={client}>{children}</QueryClientProvider>
    );

    rpcMock.mockResolvedValueOnce([]);
    const { result: tasks } = renderHook(() => useEmployeeTasks(EMPLOYEE_ID), { wrapper });
    await waitFor(() => expect(tasks.current.isSuccess).toBe(true));
    expect(rpcMock).toHaveBeenCalledWith('get_employee_tasks_admin', { p_employee_id: EMPLOYEE_ID });

    rpcMock.mockResolvedValueOnce([]);
    const { result: kpi } = renderHook(() => useEmployeeKpiEvaluations(EMPLOYEE_ID), { wrapper });
    await waitFor(() => expect(kpi.current.isSuccess).toBe(true));
    expect(rpcMock).toHaveBeenCalledWith('get_employee_kpi_evaluations_admin', { p_employee_id: EMPLOYEE_ID });

    rpcMock.mockResolvedValueOnce([]);
    const { result: decisions } = renderHook(() => useEmployeePublishedDecisions(EMPLOYEE_ID), { wrapper });
    await waitFor(() => expect(decisions.current.isSuccess).toBe(true));
    expect(rpcMock).toHaveBeenCalledWith('get_employee_published_decisions_admin', { p_employee_id: EMPLOYEE_ID });

    rpcMock.mockResolvedValueOnce([]);
    const { result: reports } = renderHook(() => useEmployeeDailyReports(EMPLOYEE_ID), { wrapper });
    await waitFor(() => expect(reports.current.isSuccess).toBe(true));
    expect(rpcMock).toHaveBeenCalledWith('get_mobile_daily_reports', { p_employee_id: EMPLOYEE_ID, p_limit: 50 });
  });
});
