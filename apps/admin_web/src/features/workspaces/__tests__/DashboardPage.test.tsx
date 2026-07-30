import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { DashboardPage } from '../DashboardPage';

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

let dashboardOverrideFn: () => Record<string, unknown>;
vi.mock('../../management/useManagementOverviews', () => ({
  useDashboardOverview: () => dashboardOverrideFn(),
}));

let attendanceOverrideFn: () => Record<string, unknown>;
vi.mock('../useAttendanceTodayOverview', () => ({
  useAttendanceTodayOverview: () => attendanceOverrideFn(),
}));

const mockDashboardData = {
  employees: 42,
  activeEmployees: 38,
  pendingRequests: 5,
  attendancePendingReview: 3,
  pendingKpi: 2,
  openRequisitions: 1,
  urgentActions: 0,
  publishedDecisions: 0,
  unresolvedErrors: 0,
  lastUpdatedAt: new Date().toISOString(),
};

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockDashboardData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const attendanceEmpty = { data: undefined, isLoading: false, isError: false, error: null };

describe('DashboardPage', () => {
  it('يُعرض بدون أخطاء', () => {
    dashboardOverrideFn = () => dataQuery;
    attendanceOverrideFn = () => attendanceEmpty;
    const { container } = render(
      <MemoryRouter>
        <DashboardPage type="hr" />
      </MemoryRouter>,
    );
    expect(container.querySelector('.dashboard-hero')).toBeTruthy();
  });

  it('يعرض حالة التحميل عند جلب البيانات', () => {
    dashboardOverrideFn = () => loadingQuery;
    attendanceOverrideFn = () => attendanceEmpty;
    const { container } = render(
      <MemoryRouter>
        <DashboardPage type="hr" />
      </MemoryRouter>,
    );
    // MetricSkeletonRow يعرض عناصر skeleton أثناء التحميل
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض بطاقات المؤشرات عند تحميل البيانات', () => {
    dashboardOverrideFn = () => dataQuery;
    attendanceOverrideFn = () => attendanceEmpty;
    render(
      <MemoryRouter>
        <DashboardPage type="hr" />
      </MemoryRouter>,
    );
    expect(screen.getByText('إجمالي الموظفين')).toBeDefined();
    expect(screen.getByText('42')).toBeDefined();
    expect(screen.getByText('طلبات معلقة')).toBeDefined();
  });

  it('يعرض قسم نبض التشغيل عند توفر البيانات', () => {
    dashboardOverrideFn = () => dataQuery;
    attendanceOverrideFn = () => attendanceEmpty;
    render(
      <MemoryRouter>
        <DashboardPage type="hr" />
      </MemoryRouter>,
    );
    expect(screen.getByText('نبض التشغيل')).toBeDefined();
    expect(screen.getByText('أولويات اليوم')).toBeDefined();
  });

  it('يعرض الإجراءات السريعة حسب نوع اللوحة', () => {
    dashboardOverrideFn = () => dataQuery;
    attendanceOverrideFn = () => attendanceEmpty;
    render(
      <MemoryRouter>
        <DashboardPage type="hr" />
      </MemoryRouter>,
    );
    expect(screen.getByText('إضافة موظف')).toBeDefined();
    expect(screen.getByText('مراجعة الطلبات')).toBeDefined();
  });
});
