import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { ExecutiveMonitoringPage } from '../ExecutiveMonitoringPage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مختبر',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['executive'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

// Leaflet لا يعمل في JSDOM — mock الخريطة
vi.mock('../LiveLocationMap', () => ({
  LiveLocationMap: () => <div data-testid="live-location-map" />,
}));

vi.mock('../LiveLocationResultCard', () => ({
  LiveLocationResultCard: () => <div data-testid="live-location-result-card" />,
}));

const mutationMock = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

let overviewOverrideFn: () => Record<string, unknown>;
vi.mock('../useControlCenters', () => ({
  useExecutiveAttendanceOverview: () => overviewOverrideFn(),
  useLiveLocationCommands: () => ({ request: mutationMock }),
}));

const mockSummary = {
  total: 10,
  present: 5,
  late: 2,
  notYet: 1,
  onLeave: 1,
  onMission: 0,
  onConvoy: 0,
  onFundraising: 0,
  checkedOut: 1,
  absent: 0,
  activeLocationRequests: 1,
};

const mockEmployees = [
  {
    id: 'emp-001',
    name: 'أحمد محمد',
    employeeCode: 'EMP-100',
    department: 'تقنية المعلومات',
    jobTitle: 'مطور',
    status: 'present',
    managerName: 'محمد',
    activeRequestStatus: null,
    activeRequestId: null,
    lateMinutes: null,
    avatarUrl: null,
    assignmentType: null,
    lastLatitude: null,
    lastLongitude: null,
    lastAccuracy: null,
    lastAddressAr: null,
    lastLocationAt: null,
    checkInAt: '2026-08-11T08:00:00Z',
    checkOutAt: null,
  },
];

const dataQuery = {
  data: { summary: mockSummary, employees: mockEmployees },
  isLoading: false,
  isError: false,
  error: null,
  isFetching: false,
  refetch: vi.fn(),
};
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل التحميل'), isFetching: false, refetch: vi.fn() };

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

describe('ExecutiveMonitoringPage', () => {
  it('يُعرض بدون أخطاء', () => {
    overviewOverrideFn = () => dataQuery;
    const { container } = render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    overviewOverrideFn = () => dataQuery;
    render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(screen.getByText('متابعة الموظفين اليومية')).toBeDefined();
  });

  it('يعرض بطاقات الإحصائيات', () => {
    overviewOverrideFn = () => dataQuery;
    render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(screen.getByText('إجمالي الموظفين')).toBeDefined();
    // "حاضر" appears in both the MetricCard and the filter buttons
    expect(screen.getAllByText('حاضر').length).toBeGreaterThan(0);
    expect(screen.getByText('طلبات موقع نشطة')).toBeDefined();
  });

  it('يعرض فلاتر الحالة', () => {
    overviewOverrideFn = () => dataQuery;
    render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(screen.getByRole('group', { name: 'تصفية الحالة' })).toBeDefined();
  });

  it('يعرض حقل البحث', () => {
    overviewOverrideFn = () => dataQuery;
    render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(screen.getByLabelText('بحث')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    overviewOverrideFn = () => loadingQuery;
    const { container } = render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ', () => {
    overviewOverrideFn = () => errorQuery;
    render(<ExecutiveMonitoringPage />, { wrapper: Wrapper });
    // ErrorState بدون title يستخدم الافتراضي
    expect(screen.getByText('تعذّر تحميل البيانات')).toBeDefined();
  });
});
