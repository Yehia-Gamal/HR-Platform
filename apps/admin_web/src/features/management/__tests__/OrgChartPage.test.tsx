import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { beforeAll, describe, expect, it, vi } from 'vitest';
import { OrgChartPage } from '../OrgChartPage';

/* ─── jsdom لا يوفّر window.matchMedia — mock قياسي ─────────────── */
beforeAll(() => {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: vi.fn(),
      removeListener: vi.fn(),
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
});

/* ─── mock بيانات موظف ─────────────────────────────────────────── */
const mockEmployee = {
  id: '00000000-0000-0000-0000-000000000001',
  fullNameAr: 'أحمد محمد',
  fullNameEn: null,
  photoUrl: null,
  jobTitle: 'مدير عام',
  departmentName: 'الإدارة العليا',
  employeeCode: 'EMP001',
  departmentId: null,
  status: 'active',
  managerEmployeeId: null,
  directReportsCount: 1,
  depth: 0,
  path: [],
};

const mockStats = { totalEmployees: 5, managersCount: 2, maxDepth: 3, avgDirectReports: 2.5 };

const mockData = {
  employees: [mockEmployee],
  tree: [{ employee: mockEmployee, children: [] }],
  stats: mockStats,
};

/* ─── factory يتيح تغيير حالة الـ hook لكل اختبار ────────────── */
let hookOverride: () => Record<string, unknown>;

vi.mock('../useOrgChart', () => ({
  useOrgChart: () => hookOverride(),
}));

const loadingResult = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const errorResult = { data: undefined, isLoading: false, isError: true, error: new Error('فشل'), refetch: vi.fn() };
const emptyResult = { data: { employees: [], tree: [], stats: { totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0 } }, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const dataResult = { data: mockData, isLoading: false, isError: false, error: null, refetch: vi.fn() };

describe('OrgChartPage', () => {
  it('يُعرض بدون أخطاء', () => {
    hookOverride = () => dataResult;
    const { container } = render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    hookOverride = () => dataResult;
    render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(screen.getByText('الهيكل التنظيمي الإداري')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    hookOverride = () => loadingResult;
    const { container } = render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    // LoadingScreen يستخدم animate-spin وليس animate-pulse
    expect(container.querySelector('.animate-spin')).toBeTruthy();
    expect(screen.getByText('جارٍ تحميل الهيكل التنظيمي…')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    hookOverride = () => errorResult;
    render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(screen.getByText('تعذر تحميل الهيكل')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات عند توفر البيانات', () => {
    hookOverride = () => dataResult;
    render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(screen.getByText('إجمالي الموظفين')).toBeDefined();
    expect(screen.getByText('عدد المديرين')).toBeDefined();
    expect(screen.getByText('أقصى عمق هرمي')).toBeDefined();
    expect(screen.getByText('متوسط المرؤوسين')).toBeDefined();
  });

  it('يعرض شجرة الهيكل التنظيمي بعقد الموظفين', () => {
    hookOverride = () => dataResult;
    render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(screen.getByText('أحمد محمد')).toBeDefined();
    expect(screen.getByText('مدير عام')).toBeDefined();
  });

  it('يعرض حالة فارغة عند غياب الموظفين', () => {
    hookOverride = () => emptyResult;
    render(<MemoryRouter><OrgChartPage /></MemoryRouter>);
    expect(screen.getByText('لا توجد بيانات')).toBeDefined();
  });
});
