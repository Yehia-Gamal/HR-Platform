import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ReportSchedulerPage } from '../ReportSchedulerPage';

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let catalogOverrideFn: () => Record<string, unknown>;

vi.mock('../useEnterpriseOperations', () => ({
  useReportSchedulerCatalog: () => catalogOverrideFn(),
  useReportSchedulerCommands: () => ({ upsert: noopMutation }),
}));

const mockData = {
  schedules: [
    {
      id: 's1',
      code: 'RPT-001',
      name: 'التقرير التنفيذي اليومي',
      reportType: 'executive_daily',
      audienceScope: 'organization',
      scheduleKind: 'daily',
      runHour: 8,
      nextRunAt: '2026-08-12T08:00:00Z',
      active: true,
    },
  ],
  runs: [
    {
      id: 'r1',
      reportType: 'executive_daily',
      createdAt: '2026-08-11T08:00:00Z',
      attempts: 1,
      status: 'success',
    },
  ],
  notificationQueue: { queued: 3, failed: 0 },
};

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const emptyQuery = {
  data: { schedules: [], runs: [], notificationQueue: { queued: 0, failed: 0 } },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('ReportSchedulerPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('التقارير المجدولة والتسليم')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    // "الجداول" appears in both the MetricCard and the section heading
    expect(screen.getAllByText('الجداول').length).toBeGreaterThan(0);
    expect(screen.getByText('عمليات التشغيل')).toBeDefined();
    expect(screen.getByText('إشعارات منتظرة')).toBeDefined();
    expect(screen.getByText('فشل التسليم')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض اسم الجدول عند وجود بيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('التقرير التنفيذي اليومي')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود تقارير مجدولة', () => {
    catalogOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <ReportSchedulerPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد تقارير مجدولة')).toBeDefined();
  });
});
