import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { IntegrationsJobsPage } from '../IntegrationsJobsPage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مختبر',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

const mutationMock = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

let centerOverrideFn: () => Record<string, unknown>;
vi.mock('../useControlCenters', () => ({
  useIntegrationCenter: () => centerOverrideFn(),
  useIntegrationCommands: () => ({ toggle: mutationMock }),
}));

const mockIntegrationData = {
  integrations: [
    {
      id: 'int-001',
      name: 'نظام الرواتب',
      provider: 'PayrollPro',
      category: 'hr',
      status: 'active',
      enabled: true,
      lastSyncAt: '2026-08-11T10:00:00Z',
      lastError: null,
    },
    {
      id: 'int-002',
      name: 'نظام الحضور',
      provider: 'AttendSystem',
      category: 'attendance',
      status: 'error',
      enabled: false,
      lastSyncAt: null,
      lastError: 'فشل الاتصال',
    },
  ],
  logs: [
    {
      id: 'log-001',
      integrationId: 'int-001',
      operation: 'sync_employees',
      direction: 'outbound',
      status: 'success',
      httpStatus: 200,
      durationMs: 350,
      occurredAt: '2026-08-11T10:00:00Z',
      error: null,
    },
  ],
  outbox: [
    {
      id: 'out-001',
      eventType: 'employee.created',
      status: 'pending',
      attempts: 0,
      maxAttempts: 8,
      nextAttemptAt: '2026-08-11T11:00:00Z',
      createdAt: '2026-08-11T10:30:00Z',
      error: null,
    },
  ],
  automationRuns: [
    {
      id: 'run-001',
      status: 'completed',
      attempts: 1,
      createdAt: '2026-08-11T09:00:00Z',
      completedAt: '2026-08-11T09:01:00Z',
      error: null,
    },
  ],
};

const dataQuery = { data: mockIntegrationData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل الاتصال'), isFetching: false, refetch: vi.fn() };

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

describe('IntegrationsJobsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    centerOverrideFn = () => dataQuery;
    const { container } = render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    centerOverrideFn = () => dataQuery;
    render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(screen.getByText('التكاملات والمهام الخلفية')).toBeDefined();
  });

  it('يعرض بطاقات الإحصائيات', () => {
    centerOverrideFn = () => dataQuery;
    render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(screen.getByText('موصلات نشطة')).toBeDefined();
    expect(screen.getByText('موصلات بها خطأ')).toBeDefined();
    expect(screen.getByText('رسائل في الطابور')).toBeDefined();
    expect(screen.getByText('تشغيلات فاشلة')).toBeDefined();
  });

  it('يعرض حالة التحميل (animate-pulse)', () => {
    centerOverrideFn = () => loadingQuery;
    const { container } = render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض تبويبات الأقسام', () => {
    centerOverrideFn = () => dataQuery;
    render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(screen.getByRole('tablist', { name: 'أقسام التكاملات' })).toBeDefined();
  });

  it('يعرض بطاقات الموصلات في التبويب الافتراضي', () => {
    centerOverrideFn = () => dataQuery;
    render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(screen.getByText('نظام الرواتب')).toBeDefined();
    expect(screen.getByText('نظام الحضور')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    centerOverrideFn = () => errorQuery;
    render(<IntegrationsJobsPage />, { wrapper: Wrapper });
    expect(screen.getByText('تعذر تحميل مركز التكاملات')).toBeDefined();
  });
});
