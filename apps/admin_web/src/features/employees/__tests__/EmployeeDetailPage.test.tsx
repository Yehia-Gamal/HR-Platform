import { fireEvent, render, screen, within } from '@testing-library/react';
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

vi.mock('../EmployeeOrgChartTab', () => ({
  EmployeeOrgChartTab: () => <div>الهيكل والتسلسل الإداري للموظف</div>,
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
  useGrantWeeklyRestCredit: () => ({ isPending: false, mutateAsync: vi.fn() }),
  useEmployeeAuditTrail: () => ({ data: [], isLoading: false, isError: false }),
  useSyncEmployeeDepartments: () => ({ isPending: false, mutateAsync: vi.fn() }),
}));

const departmentCreateMock = vi.hoisted(() => vi.fn(async () => '00000000-0000-4000-8000-0000000000d9'));
vi.mock('../../management/useAdminOperations', () => ({
  useOrganizationAdminCatalog: () => ({
    data: {
      entities: [{ id: '00000000-0000-4000-8000-0000000000e1', code: 'ENT-1', name: 'كيان تجريبي', active: true }],
      branches: [],
      departments: [],
      teams: [],
      positions: [],
      employees: [],
      jobTitles: [],
      grades: [],
      lastUpdatedAt: '2026-01-01T00:00:00Z',
    },
    isLoading: false,
    isError: false,
    error: null,
  }),
  useOrganizationCommands: () => ({
    department: { isPending: false, mutateAsync: departmentCreateMock },
    position: { isPending: false, mutateAsync: vi.fn() },
  }),
  useAccessAdminCatalog: () => ({ data: undefined, isLoading: false }),
  useAccessCommands: () => ({ role: { isPending: false, mutateAsync: vi.fn() }, permission: { isPending: false, mutateAsync: vi.fn() } }),
  useOnboardingAdminCatalog: () => ({ data: undefined, isLoading: false }),
  useOnboardingCommands: () => ({ step: { isPending: false, mutateAsync: vi.fn() } }),
  useRecruitmentCommands: () => ({ posting: { isPending: false, mutateAsync: vi.fn() } }),
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

  it('يسمح بكتابة مسمى وظيفي جديد في حوار التعديل (إدخال حر لا قائمة مغلقة)', () => {
    employee360Fn = () => dataQuery;
    renderPage();
    fireEvent.click(screen.getByRole('button', { name: /تعديل البيانات/ }));

    const input = screen.getByLabelText('المسمى الوظيفي') as HTMLInputElement;
    expect(input.tagName).toBe('INPUT');
    expect(input.value).toBe('مطور برمجيات');
    expect(input.getAttribute('list')).toBe('edit-job-titles-list');

    fireEvent.change(input, { target: { value: 'مدير مشروع أول' } });
    expect(input.value).toBe('مدير مشروع أول');
  });

  it('يسمح بكتابة إدارة جديدة في حوار التعديل وإسنادها للموظف', async () => {
    employee360Fn = () => dataQuery;
    departmentCreateMock.mockClear();
    renderPage();
    fireEvent.click(screen.getByRole('button', { name: /تعديل البيانات/ }));

    const dialog = within(screen.getByRole('dialog'));
    const input = dialog.getByLabelText('اسم إدارة جديدة') as HTMLInputElement;
    const createBtn = dialog.getByRole('button', { name: 'إضافة إدارة' }) as HTMLButtonElement;
    expect(createBtn.disabled).toBe(true);

    fireEvent.change(input, { target: { value: 'الإدارة التجريبية' } });
    expect(createBtn.disabled).toBe(false);

    fireEvent.click(createBtn);
    await dialog.findByText('الإدارة التجريبية');
    expect(departmentCreateMock).toHaveBeenCalledTimes(1);
    expect(departmentCreateMock).toHaveBeenCalledWith(expect.objectContaining({ entityId: '00000000-0000-4000-8000-0000000000e1', name: 'الإدارة التجريبية' }));
    expect(input.value).toBe('');
    expect(dialog.getByText('الإدارات التابع لها الموظف (1)')).toBeDefined();
  });

  it('يعرض زر الهيكل والتسلسل الإداري ويسمح بفتح التبويب', () => {
    employee360Fn = () => dataQuery;
    renderPage();
    const orgTabBtn = screen.getByRole('tab', { name: /الهيكل والتسلسل الإداري/ });
    expect(orgTabBtn).toBeDefined();
    fireEvent.click(orgTabBtn);
    expect(screen.getByText('الهيكل والتسلسل الإداري للموظف')).toBeDefined();
  });
});
