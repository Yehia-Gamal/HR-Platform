import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { EmployeesPage } from '../EmployeesPage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مستخدم اختبار',
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

let employeesOverrideFn: () => Record<string, unknown>;
vi.mock('../useEmployees', () => ({
  useEmployees: () => employeesOverrideFn(),
}));

const mockEmployees = [
  {
    id: '00000000-0000-0000-0000-000000000010',
    employeeCode: 'EMP-101',
    fullNameAr: 'أحمد محمد',
    fullNameEn: null,
    phoneE164: '+201234567890',
    status: 'active',
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    department: 'تقنية المعلومات',
    team: null,
    branch: null,
    jobTitle: 'مطور برمجيات',
    createdAt: '2026-01-15T10:00:00Z',
  },
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockEmployees, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('EmployeesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    employeesOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    employeesOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    // العنوان في h1 — التبويب يعرض نفس النص لذا نستعلم بالدور.
    expect(screen.getByRole('heading', { name: 'دليل الموظفين' })).toBeDefined();
  });

  it('يعرض التبويبين: الدليل والهيكل التنظيمي', () => {
    employeesOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    expect(screen.getByRole('tab', { name: /دليل الموظفين/ })).toBeDefined();
    expect(screen.getByRole('tab', { name: 'الهيكل التنظيمي' })).toBeDefined();
  });

  it('يعرض شريط البحث والتصفية', () => {
    employeesOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    expect(screen.getByPlaceholderText('بحث بالاسم أو الكود أو الهاتف')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب الحالة')).toBeDefined();
    expect(screen.getByLabelText('ترتيب الموظفين')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود بيانات', () => {
    employeesOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا يوجد موظفون بعد')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    employeesOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    // ListSkeleton يستخدم aria-label للنص و animate-pulse للهيكل
    const skeleton = container.querySelector('[aria-label="جارٍ تحميل الموظفين…"]');
    expect(skeleton).toBeTruthy();
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    employeesOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <EmployeesPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('إجمالي الملفات')).toBeDefined();
    expect(screen.getByText('موظفون نشطون')).toBeDefined();
  });
});
