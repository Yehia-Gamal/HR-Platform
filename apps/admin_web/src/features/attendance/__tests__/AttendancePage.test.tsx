import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';

/* ─── mock الحالات المختلفة للـ hook ─────────────────────────────── */
const mockDashboardData = {
  scheduled: 54,
  present: 45,
  late: 5,
  absent: 4,
  incomplete: 3,
  pendingReview: 2,
  lastUpdatedAt: new Date().toISOString(),
};

const mockRefetch = vi.fn();

let hookReturn: Record<string, unknown> = {};

vi.mock('../useAttendanceDashboard', () => ({
  useAttendanceDashboard: () => hookReturn,
}));

vi.mock('../../employees/useOrganizationLookups', () => ({
  useOrganizationLookups: () => ({
    data: { departments: [], branches: [] },
    isLoading: false,
    isError: false,
  }),
}));

import { AttendancePage } from '../AttendancePage';

describe('AttendancePage', () => {
  it('يعرض عنوان الصفحة والوصف', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الحضور والورديات')).toBeDefined();
  });

  it('يعرض زر التحديث', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByLabelText('تحديث')).toBeDefined();
  });

  it('يعرض مقاييس لوحة التحكم عند توفر البيانات', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('المجدولون اليوم')).toBeDefined();
    expect(screen.getByText('حاضرون')).toBeDefined();
    expect(screen.getByText('متأخرون')).toBeDefined();
    expect(screen.getByText('غياب')).toBeDefined();
  });

  it('يعرض القيم العددية الصحيحة للمقاييس', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('54')).toBeDefined();
    expect(screen.getByText('45')).toBeDefined();
    expect(screen.getByText('5')).toBeDefined();
    expect(screen.getByText('4')).toBeDefined();
  });

  it('يعرض بطاقات الحالات تحتاج اهتمام', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('بصمات غير مكتملة')).toBeDefined();
    expect(screen.getByText('تحتاج مراجعة')).toBeDefined();
    expect(screen.getByText('غياب بدون إذن')).toBeDefined();
    expect(screen.getByText('طلبات الموقع')).toBeDefined();
  });

  it('يعرض ملاحظات التشغيل', () => {
    hookReturn = { data: mockDashboardData, isLoading: false, isError: false, isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText(/ضعف GPS يُنشئ تنبيه/)).toBeDefined();
    expect(screen.getByText(/وقت الحضور المعتمد/)).toBeDefined();
  });

  it('يعرض هياكل التحميل أثناء جلب البيانات', () => {
    hookReturn = { data: undefined, isLoading: true, isError: false, isFetching: true, refetch: mockRefetch };
    const { container } = render(<AttendancePage />);
    // MetricSkeletonRow + SkeletonCard يظهران عند التحميل
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
    // لا تظهر المقاييس الفعلية أثناء التحميل
    expect(screen.queryByText('المجدولون اليوم')).toBeNull();
  });

  it('يعرض حالة الخطأ عند فشل الطلب', () => {
    hookReturn = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), isFetching: false, refetch: mockRefetch };
    render(
      <MemoryRouter>
        <AttendancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('تعذر تحميل الحضور')).toBeDefined();
  });
});
