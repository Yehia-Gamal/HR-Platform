import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { AnalyticsDashboardPage } from '../AnalyticsDashboardPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockData = {
  monthlyRequests: [
    { month: 'يناير', monthKey: '2026-01', approved: 12, rejected: 3, pending: 5, cancelled: 1 },
    { month: 'فبراير', monthKey: '2026-02', approved: 18, rejected: 2, pending: 4, cancelled: 0 },
  ],
  attendanceTrend: [
    { date: '2026-08-01', label: 'السبت', present: 40, late: 5, absent: 3 },
    { date: '2026-08-04', label: 'الثلاثاء', present: 42, late: 3, absent: 2 },
  ],
  departmentDistribution: [
    { name: 'التشغيل', value: 22 },
    { name: 'المالية', value: 8 },
  ],
  kpiScores: [
    { subject: 'الالتزام', actual: 85, target: 90 },
    { subject: 'الحضور', actual: 92, target: 95 },
  ],
};

let dashboardOverrideFn: () => Record<string, unknown>;

vi.mock('../useAnalyticsDashboard', () => ({
  useAnalyticsDashboard: () => dashboardOverrideFn(),
}));

const dataQuery = { data: mockData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل الاتصال'), refetch: vi.fn() };

describe('AnalyticsDashboardPage', () => {
  it('يُعرض بدون أخطاء', () => {
    dashboardOverrideFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    dashboardOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(screen.getByText('لوحة التحليلات')).toBeInTheDocument();
  });

  it('يعرض هيكل التحميل عند الانتظار', () => {
    dashboardOverrideFn = () => loadingQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    // MetricSkeletonRow يُعرض عند التحميل — لا توجد البطاقات الفعلية
    expect(screen.queryByText('حركة الطلبات الشهرية')).not.toBeInTheDocument();
  });

  it('يعرض رسالة الخطأ عند فشل التحميل', () => {
    dashboardOverrideFn = () => errorQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل التحليلات')).toBeInTheDocument();
  });

  it('يعرض عناوين البطاقات الأربع عند توفر البيانات', () => {
    dashboardOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(screen.getByText('حركة الطلبات الشهرية')).toBeInTheDocument();
    expect(screen.getByText('توزيع الأقسام')).toBeInTheDocument();
    expect(screen.getByText('اتجاه الحضور الأسبوعي')).toBeInTheDocument();
    expect(screen.getByText('مؤشرات الأداء')).toBeInTheDocument();
  });

  it('يعرض الـ eyebrow "التقارير"', () => {
    dashboardOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(screen.getByText('التقارير')).toBeInTheDocument();
  });

  it('يعرض زر إعادة المحاولة عند الخطأ', () => {
    dashboardOverrideFn = () => errorQuery;
    render(
      <Wrapper>
        <AnalyticsDashboardPage />
      </Wrapper>,
    );
    expect(screen.getByRole('button', { name: /إعادة المحاولة/i })).toBeInTheDocument();
  });
});
