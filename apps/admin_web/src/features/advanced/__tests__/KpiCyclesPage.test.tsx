import { fireEvent, render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { KpiCyclesPage } from '../KpiCyclesPage';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

vi.mock('../../../core/cairoTime', () => ({
  cairoMonthIso: () => '2026-08',
  cairoTodayIso: () => '2026-08-11',
}));

const mockMut = { isPending: false, isError: false, error: null, mutateAsync: vi.fn(), mutate: vi.fn() };
const mockCommands = {
  createCycle: { ...mockMut },
  manageCycle: { ...mockMut },
  rescheduleCycle: { ...mockMut },
  sendNotifications: { ...mockMut },
  refreshAttendance: { ...mockMut },
  updatePolicy: { ...mockMut },
  getReport: { ...mockMut },
  decideAppeal: { ...mockMut },
};

let kpiAdminFn: () => Record<string, unknown>;

vi.mock('../useAdvancedOperations', () => ({
  useKpiAdmin: () => kpiAdminFn(),
  useKpiAdminCommands: () => mockCommands,
}));

const emptyDataQuery = {
  data: { cycles: [], appeals: [], canManageCycles: false, policy: null, officialTemplateId: null },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};
const mockCycle = {
  id: 'cycle-1',
  periodMonth: '2026-08-01',
  status: 'draft',
  evaluations: 5,
  finalized: 2,
  overdue: 1,
  averageScore: null,
  scheduledOpenAt: null,
  effectiveDeadline: null,
  overrideReason: null,
  employeeEvaluations: [],
};
const dataQuery = {
  data: { cycles: [mockCycle], appeals: [], canManageCycles: false, policy: null, officialTemplateId: null },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('KpiCyclesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    kpiAdminFn = () => emptyDataQuery;
    const { container } = render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    kpiAdminFn = () => emptyDataQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(screen.getByText('دورات KPI الرسمية')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    kpiAdminFn = () => emptyDataQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('الدورات').length).toBeGreaterThan(0);
    expect(screen.getByText('التقييمات')).toBeDefined();
    expect(screen.getByText('المدرجة في التقارير')).toBeDefined();
    expect(screen.getByText('الاعتراضات')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    kpiAdminFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل التحميل', () => {
    kpiAdminFn = () => errorQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل دورات KPI')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود دورات', () => {
    kpiAdminFn = () => emptyDataQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد دورات')).toBeDefined();
  });

  it('يعرض قسم الاعتراضات وبيانات الدورة عند توفرها', () => {
    kpiAdminFn = () => dataQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    expect(screen.getByText('اعتراضات التقييم')).toBeDefined();
    expect(screen.getByText('لا توجد اعتراضات معلقة')).toBeDefined();
  });

  it('يُظهر لوحة التحليلات عند التبديل إليها ويعرض حالة عدم وجود بيانات', () => {
    kpiAdminFn = () => dataQuery;
    render(
      <Wrapper>
        <KpiCyclesPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByRole('tab', { name: /تحليلات/ }));
    expect(screen.getByText('المقارنة التاريخية لنتائج KPI')).toBeDefined();
  });
});
