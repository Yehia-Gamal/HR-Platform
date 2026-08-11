import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { PerformancePage } from '../PerformancePage';

let performanceOverrideFn: () => Record<string, unknown>;
vi.mock('../usePerformance', () => ({
  usePerformance: () => performanceOverrideFn(),
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
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockEvaluations, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('PerformancePage', () => {
  it('يُعرض بدون أخطاء', () => {
    performanceOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    performanceOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('KPI والأداء')).toBeDefined();
  });

  it('يعرض تبويبات العرض', () => {
    performanceOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تقييمي')).toBeDefined();
    expect(screen.getByText('فريقي')).toBeDefined();
    expect(screen.getByText('المهام')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    performanceOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('إجمالي التقييمات')).toBeDefined();
    expect(screen.getByText('المكتملة')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    performanceOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود تقييمات', () => {
    performanceOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <PerformancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد تقييمات')).toBeDefined();
  });
});
