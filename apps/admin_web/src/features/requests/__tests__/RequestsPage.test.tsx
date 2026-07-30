import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { RequestsPage } from '../RequestsPage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مستخدم اختبار',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr', 'main_admin'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

let requestsOverrideFn: () => Record<string, unknown>;
vi.mock('../useRequests', () => ({
  useRequests: () => requestsOverrideFn(),
  useRequestDecision: () => ({ mutateAsync: vi.fn(), isError: false, error: null, isPending: false }),
  useMyLeaveBalances: () => ({ data: [], isLoading: false, isError: false, error: null }),
  useWorkAssignments: () => ({ data: [], isLoading: false, isError: false, error: null }),
}));

vi.mock('../../advanced/useAdvancedOperations', () => ({
  useAttendanceOperations: () => ({ data: { corrections: [] }, isLoading: false, isError: false, error: null, refetch: vi.fn() }),
  useAttendanceOperationsCommands: () => ({ decideCorrection: { mutate: vi.fn(), isError: false, error: null } }),
}));

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };

const mockRequests = [
  {
    id: '00000000-0000-0000-0000-000000000020',
    requestNumber: 1001,
    requestType: 'leave' as const,
    title: 'إجازة سنوية',
    status: 'pending',
    employeeName: 'أحمد محمد',
    employeeCode: 'EMP-101',
    reason: 'إجازة عائلية',
    activeStepName: 'مراجعة المدير',
    createdAt: '2026-01-20T08:00:00Z',
  },
];
const dataQuery = { data: mockRequests, isLoading: false, isError: false, error: null, refetch: vi.fn() };

describe('RequestsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    requestsOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    requestsOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('طلب اجازة')).toBeDefined();
  });

  it('يعرض تبويبات تصنيف الطلبات', () => {
    requestsOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الكل')).toBeDefined();
    expect(screen.getByText('الإجازات')).toBeDefined();
    expect(screen.getByText('المأموريات')).toBeDefined();
    expect(screen.getByText('القوافل')).toBeDefined();
    expect(screen.getByText('أذونات الحضور')).toBeDefined();
    expect(screen.getByText('تصحيحات الحضور')).toBeDefined();
  });

  it('يعرض قسم التنقل بين التصنيفات مع aria-label', () => {
    requestsOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    const nav = container.querySelector('nav[aria-label="تصنيف الطلبات"]');
    expect(nav).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود طلبات', () => {
    requestsOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد طلبات')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب الطلبات', () => {
    requestsOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <RequestsPage />
      </MemoryRouter>,
    );
    // ListSkeleton يعرض عناصر skeleton أثناء التحميل
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });
});
