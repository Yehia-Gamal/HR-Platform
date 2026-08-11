import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { EmployeeDetailPage } from '../EmployeeDetailPage';

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
  attendancePolicy: {
    attendanceRequired: false,
    selfPunchEnabled: false,
    liveLocationResponseEnabled: false,
  },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'authenticated',
    session: null,
    access: mockAccess,
    error: null,
    isMock: true,
  }),
}));

vi.mock('react-router', async () => {
  const actual = await vi.importActual('react-router');
  return {
    ...actual,
    useParams: () => ({ employeeId: '00000000-0000-0000-0000-000000000010' }),
  };
});

vi.mock('../../../ui/Toast', () => ({
  useToast: () => ({ toast: vi.fn() }),
  subscribeToastEmitter: vi.fn(),
  ToastProvider: ({ children }: { children: React.ReactNode }) => children,
}));

vi.mock('../useOrganizationLookups', () => ({
  useOrganizationLookups: () => ({
    data: {
      roles: [],
      branches: [],
      workSites: [],
      managers: [],
      jobTitles: [],
      departments: [],
    },
    isLoading: false,
    isError: false,
    error: null,
  }),
}));

vi.mock('../../attendance/MonthlyStatementSection', () => ({
  MonthlyStatementSection: () => null,
}));

vi.mock('../employeeDetailShared', () => ({
  normalizePhoneForSubmit: (v: string) => v,
  EmployeeEditHistory: () => null,
}));

let employee360Fn: () => Record<string, unknown>;
vi.mock('../useEmployees', () => ({
  useEmployee360: () => employee360Fn(),
  useResendInvite: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useEmployees: () => ({ data: [], isLoading: false }),
  useChangeManager: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useArchiveEmployee: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useUpdateEmployee: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useEmployeeDepartments: () => ({ data: [], isLoading: false }),
  useAssignDepartment: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useRemoveDepartment: () => ({ isPending: false, mutate: vi.fn(), isError: false }),
  useDeleteEmployee: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useSetEmployeePassword: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useUpdateEmployeeEmail: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useEmployeeAuditTrail: () => ({ data: [], isLoading: false, isError: false }),
}));

const mockEmployee360 = {
  id: '00000000-0000-0000-0000-000000000010',
  employeeCode: 'EMP-101',
  fullNameAr: 'أحمد محمد',
  fullNameEn: null,
  phoneE164: '+201234567890',
  photoUrl: null,
  status: 'active',
  isActive: true,
  hireDate: '2026-01-01',
  contractEnd: null,
  probationEnd: null,
  jobTitle: 'مطور برمجيات',
  position: null,
  grade: null,
  department: 'تقنية المعلومات',
  team: null,
  branch: null,
  workSite: null,
  managerName: null,
  accountStatus: 'active',
  email: 'ahmed@example.com',
  departmentId: null,
  teamId: null,
  branchId: null,
  workSiteId: null,
  jobTitleId: null,
  positionId: null,
  gradeId: null,
  employmentTypeId: null,
  managerId: null,
  departments: [],
  roles: [{ slug: 'employee', name: 'موظف' }],
  directReports: 0,
  attendance30: { present: 20, lateDays: 2, absent: 1, workMinutes: 9600 },
  requestCounts: { pending: 1, approved: 3, rejected: 0 },
  latestKpi: null,
  documents: [],
  assets: [],
  recentRequests: [],
  recentTasks: [],
  lastUpdatedAt: '2026-08-11T10:00:00Z',
};

const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const dataQuery = {
  data: mockEmployee360,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};

function renderPage() {
  return render(
    <MemoryRouter>
      <EmployeeDetailPage />
    </MemoryRouter>,
  );
}

describe('EmployeeDetailPage', () => {
  it('يُعرض بدون أخطاء', () => {
    employee360Fn = () => dataQuery;
    const { container } = renderPage();
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    employee360Fn = () => dataQuery;
    renderPage();
    expect(screen.getByText('ملف الموظف')).toBeDefined();
  });

  it('يعرض اسم الموظف عند توفر البيانات', () => {
    employee360Fn = () => dataQuery;
    renderPage();
    expect(screen.getByText('أحمد محمد')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    employee360Fn = () => loadingQuery;
    const { container } = renderPage();
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل الجلب', () => {
    employee360Fn = () => errorQuery;
    renderPage();
    expect(screen.getByText('تعذر فتح ملف الموظف')).toBeDefined();
  });

  it('يعرض بطاقات مؤشرات الحضور والطلبات', () => {
    employee360Fn = () => dataQuery;
    renderPage();
    expect(screen.getByText('أيام الحضور — 30 يومًا')).toBeDefined();
    expect(screen.getByText('الطلبات المعلقة')).toBeDefined();
  });
});
