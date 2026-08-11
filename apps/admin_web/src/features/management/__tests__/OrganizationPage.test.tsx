import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { OrganizationPage } from '../OrganizationPage';

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let catalogOverrideFn: () => Record<string, unknown>;

vi.mock('../useAdminOperations', () => ({
  useOrganizationAdminCatalog: () => catalogOverrideFn(),
  useOrganizationCommands: () => ({ department: noopMutation, position: noopMutation }),
  useOnboardingAdminCatalog: () => ({ data: undefined, isLoading: false, isError: false, error: null, refetch: vi.fn() }),
  useOnboardingCommands: () => ({ createJourney: noopMutation, transitionTask: noopMutation }),
}));

const mockData = {
  entities: [{ id: 'e1', name: 'الجمعية الرئيسية' }],
  branches: [{ id: 'b1', name: 'الفرع الرئيسي', entityId: 'e1' }],
  departments: [
    {
      id: 'd1',
      entityId: 'e1',
      branchId: 'b1',
      parentId: null,
      managerId: null,
      code: 'DEPT-001',
      name: 'الموارد البشرية',
      nameEn: 'HR',
      active: true,
      employeeCount: 5,
      positionCount: 2,
    },
  ],
  positions: [
    {
      id: 'p1',
      departmentId: 'd1',
      teamId: null,
      jobTitleId: null,
      gradeId: null,
      reportsToId: null,
      code: 'POS-001',
      name: 'مدير الموارد البشرية',
      nameEn: null,
      headcount: 2,
      assignedCount: 1,
      active: true,
    },
  ],
  employees: [{ id: 'emp1', name: 'أحمد محمد' }],
  teams: [],
  jobTitles: [],
  grades: [],
};

const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataQuery = { data: mockData, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const emptyDepsQuery = {
  data: { ...mockData, departments: [], positions: [] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('OrganizationPage', () => {
  it('يُعرض بدون أخطاء', () => {
    catalogOverrideFn = () => dataQuery;
    const { container } = render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('الهيكل المؤسسي والمناصب')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    // Some labels also appear in section headings or table headers — use getAllByText
    expect(screen.getByText('الكيانات')).toBeDefined();
    expect(screen.getAllByText('الإدارات').length).toBeGreaterThan(0);
    expect(screen.getAllByText('المناصب').length).toBeGreaterThan(0);
    expect(screen.getByText('الشواغر')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    catalogOverrideFn = () => loadingQuery;
    const { container } = render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    // LoadingScreen uses animate-spin
    expect(container.querySelector('.animate-spin')).toBeTruthy();
  });

  it('يعرض اسم الإدارة في الجدول عند وجود بيانات', () => {
    catalogOverrideFn = () => dataQuery;
    render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    // Department name appears in both the departments table and as the department column in the positions table
    expect(screen.getAllByText('الموارد البشرية').length).toBeGreaterThan(0);
  });

  it('يعرض حالة فارغة عند عدم وجود إدارات', () => {
    catalogOverrideFn = () => emptyDepsQuery;
    render(
      <MemoryRouter>
        <OrganizationPage />
      </MemoryRouter>,
    );
    expect(screen.getByText('لا توجد إدارات')).toBeDefined();
  });
});
