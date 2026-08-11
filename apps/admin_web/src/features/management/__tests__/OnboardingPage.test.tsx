import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { OnboardingPage } from '../OnboardingPage';

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let catalogOverrideFn: () => Record<string, unknown>;

vi.mock('../useAdminOperations', () => ({
  useOnboardingAdminCatalog: () => catalogOverrideFn(),
  useOnboardingCommands: () => ({
    createJourney: noopMutation,
    transitionTask: noopMutation,
  }),
  useOrganizationAdminCatalog: () => ({ data: undefined, isLoading: false, isError: false, error: null, refetch: vi.fn() }),
  useOrganizationCommands: () => ({ department: noopMutation, position: noopMutation }),
}));

const mockJourney = {
  id: 'j1',
  employeeName: 'سارة الأحمدي',
  employeeCode: 'EMP-201',
  status: 'in_progress',
  probationEnd: '2026-10-01',
  progress: 60,
  totalTasks: 5,
  completedTasks: 3,
  tasks: [
    { id: 't1', title: 'مراجعة المستندات', ownerRole: 'HR', dueOffsetDays: 0, status: 'completed' },
    { id: 't2', title: 'توقيع السياسات', ownerRole: 'Employee', dueOffsetDays: 1, status: 'pending' },
  ],
};

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = {
  data: { journeys: [mockJourney], eligibleEmployees: [{ id: 'emp1', name: 'سارة الأحمدي', code: 'EMP-201' }] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyQuery = {
  data: { journeys: [], eligibleEmployees: [] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('OnboardingPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('Onboarding وفترة التجربة')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الرحلات النشطة')).toBeDefined();
    expect(screen.getByText('المكتملة')).toBeDefined();
    expect(screen.getByText('مهام معلقة')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض اسم الموظف في رحلة الإلحاق', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('سارة الأحمدي')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود رحلات', () => {
    catalogOverrideFn = () => emptyQuery;
    render(
      <MemoryRouter>
        <OnboardingPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد رحلات Onboarding')).toBeDefined();
  });
});
