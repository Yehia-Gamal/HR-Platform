import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { AccessPage } from '../AccessPage';

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

let catalogOverrideFn: () => Record<string, unknown>;
vi.mock('../useAdminOperations', () => ({
  useAccessAdminCatalog: () => catalogOverrideFn(),
  useAccessCommands: () => ({
    upsertRole: mutationMock,
    setPermissions: mutationMock,
    assignRole: mutationMock,
    revokeRole: mutationMock,
  }),
}));

const mockData = {
  roles: [
    {
      id: '10000000-0000-0000-0000-000000000001',
      slug: 'admin',
      name: 'أدمن',
      nameEn: 'Admin',
      description: 'الأدمن الرئيسي',
      fullAccess: true,
      system: true,
      permissions: [],
      assignments: 2,
    },
    {
      id: '10000000-0000-0000-0000-000000000002',
      slug: 'custom-role',
      name: 'دور مخصص',
      nameEn: 'Custom',
      description: null,
      fullAccess: false,
      system: false,
      permissions: [],
      assignments: 0,
    },
  ],
  permissions: [
    {
      id: '20000000-0000-0000-0000-000000000001',
      code: 'access.read',
      name: 'Access Read',
      nameAr: 'قراءة الوصول',
      module: 'access',
      moduleAr: 'إدارة الوصول',
      allowedScopes: ['organization'],
      sensitive: false,
    },
  ],
  users: [
    {
      userId: '30000000-0000-0000-0000-000000000001',
      name: 'أحمد',
      employeeCode: 'EMP-100',
      roles: [{ roleId: '10000000-0000-0000-0000-000000000001', name: 'أدمن', effectiveTo: null }],
    },
  ],
};

const dataQuery = { data: mockData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل التحميل'), isFetching: false, refetch: vi.fn() };

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

describe('AccessPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(<AccessPage />, { wrapper: Wrapper });
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(<AccessPage />, { wrapper: Wrapper });
    expect(screen.getByText('الأدوار والصلاحيات')).toBeDefined();
  });

  it('يعرض حالة التحميل (animate-pulse)', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(<AccessPage />, { wrapper: Wrapper });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض بطاقات الإحصائيات عند توفر البيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(<AccessPage />, { wrapper: Wrapper });
    expect(screen.getByText('الأدوار')).toBeDefined();
    expect(screen.getByText('الصلاحيات')).toBeDefined();
    expect(screen.getByText('المستخدمون')).toBeDefined();
  });

  it('يعرض قوالب الأدوار المعتمدة', () => {
    catalogOverrideFn = () => dataQuery;
    render(<AccessPage />, { wrapper: Wrapper });
    expect(screen.getByText('قوالب الأدوار المعتمدة')).toBeDefined();
  });

  it('يعرض قسم إسناد دور', () => {
    catalogOverrideFn = () => dataQuery;
    render(<AccessPage />, { wrapper: Wrapper });
    expect(screen.getByText('إسناد دور')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    catalogOverrideFn = () => errorQuery;
    render(<AccessPage />, { wrapper: Wrapper });
    expect(screen.getByText('تعذر تحميل الصلاحيات')).toBeDefined();
  });
});
