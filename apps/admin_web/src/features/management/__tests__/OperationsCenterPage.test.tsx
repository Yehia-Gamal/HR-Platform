import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { OperationsCenterPage } from '../OperationsCenterPage';

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
  useOperationsCenter: () => centerOverrideFn(),
  useOperationsCommands: () => ({
    createTask: mutationMock,
    transitionTask: mutationMock,
  }),
}));

const mockOperationsData = {
  employees: [
    { id: 'emp-001', name: 'أحمد محمد' },
    { id: 'emp-002', name: 'سارة علي' },
  ],
  tasks: [
    {
      id: 'task-001',
      title: 'مراجعة تقرير الحضور',
      description: 'مراجعة تقرير الحضور الشهري',
      assigneeId: 'emp-001',
      assigneeName: 'أحمد محمد',
      priority: 'high',
      dueDate: '2026-08-15',
      status: 'pending',
    },
    {
      id: 'task-002',
      title: 'تحديث بيانات الموظفين',
      description: null,
      assigneeId: 'emp-002',
      assigneeName: 'سارة علي',
      priority: 'medium',
      dueDate: null,
      status: 'in_progress',
    },
  ],
  missions: [
    {
      id: 'mis-001',
      employeeName: 'أحمد محمد',
      destination: 'القاهرة',
      purpose: 'اجتماع مع العملاء',
      startAt: '2026-08-12T09:00:00Z',
      endAt: '2026-08-13T18:00:00Z',
      status: 'approved',
      transportMode: 'company_vehicle',
    },
  ],
  convoys: [
    {
      id: 'conv-001',
      employeeName: 'سارة علي',
      name: 'قافلة الإسكندرية',
      origin: 'القاهرة',
      destination: 'الإسكندرية',
      departureAt: '2026-08-14T07:00:00Z',
      returnAt: '2026-08-14T20:00:00Z',
      passengers: 12,
      vehicles: 2,
      status: 'approved',
    },
  ],
};

const dataQuery = { data: mockOperationsData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل التحميل'), isFetching: false, refetch: vi.fn() };

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

describe('OperationsCenterPage', () => {
  it('يُعرض بدون أخطاء', () => {
    centerOverrideFn = () => dataQuery;
    const { container } = render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    centerOverrideFn = () => dataQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(screen.getByText('مركز العمليات والمهام')).toBeDefined();
  });

  it('يعرض بطاقات الإحصائيات', () => {
    centerOverrideFn = () => dataQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(screen.getByText('مهام مفتوحة')).toBeDefined();
    expect(screen.getByText('أولوية عاجلة')).toBeDefined();
    expect(screen.getByText('مأموريات')).toBeDefined();
    expect(screen.getByText('قوافل مجدولة')).toBeDefined();
  });

  it('يعرض تبويبات المهام والمأموريات والقوافل', () => {
    centerOverrideFn = () => dataQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(screen.getByRole('tablist', { name: 'أقسام مركز العمليات' })).toBeDefined();
  });

  it('يعرض المهام في التبويب الافتراضي', () => {
    centerOverrideFn = () => dataQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    // الصفحة تعرض desktop + mobile في نفس الوقت (hidden بالـ CSS) — نستخدم getAllByText
    expect(screen.getAllByText('مراجعة تقرير الحضور').length).toBeGreaterThan(0);
    expect(screen.getAllByText('تحديث بيانات الموظفين').length).toBeGreaterThan(0);
  });

  it('يعرض زر إنشاء مهمة جديدة عند وجود صلاحيات', () => {
    centerOverrideFn = () => dataQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(screen.getByText('مهمة جديدة')).toBeDefined();
  });

  it('يعرض حالة التحميل (animate-pulse)', () => {
    centerOverrideFn = () => loadingQuery;
    const { container } = render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ', () => {
    centerOverrideFn = () => errorQuery;
    render(<OperationsCenterPage />, { wrapper: Wrapper });
    expect(screen.getByText('تعذر تحميل مركز العمليات')).toBeDefined();
  });
});
