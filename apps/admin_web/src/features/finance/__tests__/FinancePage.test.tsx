import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { FinancePage } from '../FinancePage';

let catalogOverrideFn: () => Record<string, unknown>;
vi.mock('../usePeopleFinance', () => ({
  usePeopleFinanceCatalog: () => catalogOverrideFn(),
  PAYROLL_RUN_STATUS_LABELS: {},
  SALARY_STRUCTURE_STATUS_LABELS: {},
  LOAN_STATUS_LABELS: {},
  WORKFORCE_PLAN_STATUS_LABELS: {},
  CAMPAIGN_STATUS_LABELS: {},
}));

const mockCatalogData = {
  payrollRuns: [
    {
      id: 'pr-1',
      periodMonth: '2026-01',
      status: 'draft',
      totalGross: 50000,
      totalNet: 45000,
      employeeCount: 10,
      createdAt: '2026-01-01T00:00:00Z',
      approvedAt: null,
      approvedByName: null,
    },
  ],
  salaryStructures: [
    { id: 'ss-1', name: 'هيكل أساسي', code: 'BASIC', active: true, baseSalary: 5000, currency: 'EGP', effectiveFrom: '2026-01-01', effectiveTo: null },
  ],
  loans: [
    {
      id: 'ln-1',
      employeeId: 'emp-1',
      employeeName: 'أحمد محمد',
      loanType: 'personal',
      principalAmount: 10000,
      remainingBalance: 8000,
      status: 'active',
      requestedAt: '2026-01-05T00:00:00Z',
      approvedAt: null,
    },
  ],
  workforcePlans: [{ id: 'wp-1', departmentName: 'تقنية المعلومات', year: 2026, headcount: 15, status: 'approved', budgetEgp: 1000000, notes: null }],
  campaigns: [
    {
      id: 'ca-1',
      title: 'استبيان الرضا الوظيفي',
      campaignType: 'survey',
      status: 'active',
      targetAudience: null,
      startDate: '2026-01-01',
      endDate: null,
      createdByName: null,
    },
  ],
};

const emptyData = { payrollRuns: [], salaryStructures: [], loans: [], workforcePlans: [], campaigns: [] };

const emptyQuery = { data: emptyData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockCatalogData, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('FinancePage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الرواتب والمالية')).toBeDefined();
  });

  it('يعرض تبويبات القسم الرئيسية', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('دورات الرواتب')).toBeDefined();
    expect(screen.getByText('هياكل الرواتب')).toBeDefined();
    expect(screen.getByText('السلف والقروض')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات عند توفر البيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('دورات رواتب')).toBeDefined();
    expect(screen.getByText('هياكل رواتب نشطة')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود بيانات في التبويب', () => {
    catalogOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <FinancePage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد بيانات')).toBeDefined();
  });
});
