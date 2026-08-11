import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { EmployeePenaltiesPage } from '../EmployeePenaltiesPage';

let penaltiesFn: () => Record<string, unknown>;
vi.mock('../useFinancialExtensions', () => ({
  PENALTY_STATUS_LABELS: { issued: 'صادرة', deducted: 'مخصومة', waived: 'مُسقطة' },
  PENALTY_TYPE_LABELS: { attendance: 'غياب/تأخير', policy: 'مخالفة لائحة', conduct: 'سلوك' },
  useEmployeePenalties: () => penaltiesFn(),
  useAddEmployeePenalty: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
  useWaiveEmployeePenalty: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
}));

let employeesFn: () => Record<string, unknown>;
vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => employeesFn(),
}));

const emptyPenalties = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingPenalties = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyEmployees = { data: [], isLoading: false, isError: false, error: null };

function renderPage() {
  return render(
    <MemoryRouter>
      <EmployeePenaltiesPage />
    </MemoryRouter>,
  );
}

describe('EmployeePenaltiesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    penaltiesFn = () => emptyPenalties;
    employeesFn = () => emptyEmployees;
    const { container } = renderPage();
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    penaltiesFn = () => emptyPenalties;
    employeesFn = () => emptyEmployees;
    renderPage();
    expect(screen.getByText('المخالفات المالية')).toBeDefined();
  });

  it('يعرض زر إصدار مخالفة', () => {
    penaltiesFn = () => emptyPenalties;
    employeesFn = () => emptyEmployees;
    renderPage();
    expect(screen.getByText('إصدار مخالفة')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    penaltiesFn = () => loadingPenalties;
    employeesFn = () => emptyEmployees;
    const { container } = renderPage();
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود مخالفات', () => {
    penaltiesFn = () => emptyPenalties;
    employeesFn = () => emptyEmployees;
    renderPage();
    expect(screen.getByText('لا توجد مخالفات')).toBeDefined();
  });

  it('يعرض شريط البحث والتصفية', () => {
    penaltiesFn = () => emptyPenalties;
    employeesFn = () => emptyEmployees;
    renderPage();
    expect(screen.getByPlaceholderText('ابحث بالموظف أو السبب…')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب الحالة')).toBeDefined();
  });
});
