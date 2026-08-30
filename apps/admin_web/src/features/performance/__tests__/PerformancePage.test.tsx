import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { PerformancePage } from '../PerformancePage';

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

let performanceOverrideFn: () => Record<string, unknown>;
let hasSubordinatesOverrideFn: () => boolean;
vi.mock('../usePerformance', () => ({
  usePerformance: () => performanceOverrideFn(),
}));
vi.mock('../../employees/useHasSubordinates', () => ({
  useHasSubordinates: () => ({ data: hasSubordinatesOverrideFn() }),
}));

vi.mock('../KpiEvaluationEditor', () => ({
  KpiEvaluationEditor: () => null,
}));

const mockEvaluations = [
  {
    id: 'eval-1',
    employeeId: 'emp-1',
    employeeName: 'أحمد محمد',
    employeeCode: 'EMP-101',
    photoUrl: null,
    currentStage: 'self' as const,
    selfScore: null,
    managerScore: null,
    finalScore: null,
    periodMonth: '2026-01-01',
    relation: 'self' as const,
    workflowStatus: 'PENDING',
    canEdit: true,
  },
  {
    id: 'eval-2',
    employeeId: 'emp-2',
    employeeName: 'فاطمة علي',
    employeeCode: 'EMP-102',
    photoUrl: null,
    currentStage: 'hr_review' as const,
    selfScore: 80,
    managerScore: null,
    finalScore: null,
    periodMonth: '2026-01-01',
    relation: 'team' as const,
    workflowStatus: 'PENDING',
    canEdit: false,
  },
  {
    id: 'eval-3',
    employeeId: 'emp-3',
    employeeName: 'عمر خالد',
    employeeCode: 'EMP-103',
    photoUrl: null,
    currentStage: 'manager_review' as const,
    selfScore: 75,
    managerScore: null,
    finalScore: null,
    periodMonth: '2026-01-01',
    relation: 'review' as const,
    workflowStatus: 'PENDING',
    canEdit: false,
  },
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockEvaluations, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

function renderWithProviders(ui: React.ReactElement) {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false, gcTime: 0 } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>{ui}</MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('PerformancePage', () => {
  beforeEach(() => {
    hasSubordinatesOverrideFn = () => true;
  });

  it('يُعرض بدون أخطاء', () => {
    performanceOverrideFn = () => dataQuery;
    const { container } = renderWithProviders(<PerformancePage />);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    performanceOverrideFn = () => dataQuery;
    renderWithProviders(<PerformancePage />);
    expect(screen.getByText('KPI والأداء')).toBeDefined();
  });

  it('يعرض تبويبات العرض', () => {
    performanceOverrideFn = () => dataQuery;
    renderWithProviders(<PerformancePage />);
    expect(screen.getByText('تقييمي')).toBeDefined();
    expect(screen.getByText('فريقي')).toBeDefined();
    expect(screen.getByText('المهام')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    performanceOverrideFn = () => dataQuery;
    renderWithProviders(<PerformancePage />);
    expect(screen.getByText('إجمالي التقييمات')).toBeDefined();
    expect(screen.getByText('المكتملة')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    performanceOverrideFn = () => loadingQuery;
    const { container } = renderWithProviders(<PerformancePage />);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود تقييمات', () => {
    performanceOverrideFn = () => emptyQuery;
    renderWithProviders(<PerformancePage />);
    expect(screen.getByText('لا توجد تقييمات')).toBeDefined();
  });
});
