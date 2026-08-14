import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ReportsPage } from '../ReportsPage';

/* ─── mock بيانات ملخص التقارير ───────────────────────────────── */
const mockReportsData = {
  attendance: { totalEvents: 100, checkIns: 50, checkOuts: 45, pendingReview: 5, thisMonth: 200 },
  leaves: { totalRequests: 30, approved: 20, pending: 5, rejected: 5, activeNow: 3 },
  assignments: { total: 10, active: 3, completed: 6, pending: 1 },
  kpi: { activeCycles: 2, totalEvaluations: 50, pendingEvaluations: 10, completedEvaluations: 40 },
  disputes: { total: 5, open: 2, resolved: 3, escalated: 1 },
  location: { totalRequests: 8, pending: 2, responded: 6 },
  generatedAt: new Date().toISOString(),
};

/* ─── factory function لحالات الـ hook ──────────────────────── */
let hrReportsOverride: () => Record<string, unknown>;

vi.mock('../useHrReportsSummary', () => ({
  useHrReportsSummary: () => hrReportsOverride(),
}));

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockReportsData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const errorQuery = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: vi.fn() };

describe('ReportsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    hrReportsOverride = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    hrReportsOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('التقارير التشغيلية')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    hrReportsOverride = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ', () => {
    hrReportsOverride = () => errorQuery;
    render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تعذر تحميل التقارير')).toBeDefined();
  });

  it('يعرض أقسام التقارير الرئيسية', () => {
    hrReportsOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الحضور')).toBeDefined();
    expect(screen.getByText('الإجازات')).toBeDefined();
    expect(screen.getByText('التكليفات')).toBeDefined();
    expect(screen.getByText('الأداء (KPI)')).toBeDefined();
    expect(screen.getByText('النزاعات')).toBeDefined();
    expect(screen.getByText('طلبات الموقع')).toBeDefined();
  });

  it('يعرض بطاقات مؤشرات الحضور', () => {
    hrReportsOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('إجمالي الأحداث')).toBeDefined();
    expect(screen.getByText('تسجيل دخول اليوم')).toBeDefined();
    expect(screen.getByText('تسجيل خروج اليوم')).toBeDefined();
  });

  it('يعرض زر تصدير CSV', () => {
    hrReportsOverride = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportsPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تصدير CSV')).toBeDefined();
  });
});
