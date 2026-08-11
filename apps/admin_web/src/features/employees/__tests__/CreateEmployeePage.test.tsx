import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { CreateEmployeePage } from '../CreateEmployeePage';

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مختبر',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: {
    attendanceRequired: false,
    selfPunchEnabled: false,
    liveLocationResponseEnabled: false,
  },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'authenticated',
    session: null,
    access: mockAccess,
    error: null,
    isMock: true,
  }),
}));

let lookupsFn: () => Record<string, unknown>;
vi.mock('../useOrganizationLookups', () => ({
  useOrganizationLookups: () => lookupsFn(),
}));

const emptyLookups = {
  data: {
    roles: [],
    branches: [],
    workSites: [],
    managers: [],
    jobTitles: [],
    departments: [],
  },
  isLoading: false,
  isError: false,
  error: null,
};

function renderPage() {
  return render(
    <MemoryRouter>
      <CreateEmployeePage />
    </MemoryRouter>,
  );
}

describe('CreateEmployeePage', () => {
  it('يُعرض بدون أخطاء', () => {
    lookupsFn = () => emptyLookups;
    const { container } = renderPage();
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    lookupsFn = () => emptyLookups;
    renderPage();
    expect(screen.getByText('إنشاء موظف وحساب دخول')).toBeDefined();
  });

  it('يعرض خطوات الرحلة (stepper)', () => {
    lookupsFn = () => emptyLookups;
    renderPage();
    expect(screen.getByText('الهوية والحساب')).toBeDefined();
    expect(screen.getByText('الهيكل والوظيفة')).toBeDefined();
    expect(screen.getByText('المراجعة والإنشاء')).toBeDefined();
  });

  it('يعرض الخطوة الأولى بحقول الهوية والحساب', () => {
    lookupsFn = () => emptyLookups;
    renderPage();
    expect(screen.getByText('الاسم الكامل بالعربية')).toBeDefined();
    expect(screen.getByText('البريد الإلكتروني')).toBeDefined();
  });

  it('يعرض زر "التالي" نشطاً وزر "السابق" معطّلاً في الخطوة الأولى', () => {
    lookupsFn = () => emptyLookups;
    renderPage();
    expect(screen.getByText('التالي')).toBeDefined();
    const prevButton = screen.getByText('السابق').closest('button');
    expect(prevButton).toBeDisabled();
  });

  it('يعرض زر رفع الصورة الشخصية', () => {
    lookupsFn = () => emptyLookups;
    renderPage();
    expect(screen.getByText('رفع صورة')).toBeDefined();
  });
});
