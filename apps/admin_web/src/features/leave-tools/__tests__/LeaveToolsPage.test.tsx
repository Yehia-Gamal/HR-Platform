import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { LeaveToolsPage } from '../LeaveToolsPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockEmployees = [
  {
    id: 'emp-1',
    employeeCode: 'EMP-101',
    fullNameAr: 'أحمد محمد',
    fullNameEn: null,
    phoneE164: null,
    status: 'active' as const,
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    createdAt: '2026-01-01T00:00:00Z',
  },
  {
    id: 'emp-2',
    employeeCode: 'EMP-102',
    fullNameAr: 'سارة علي',
    fullNameEn: null,
    phoneE164: null,
    status: 'active' as const,
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    createdAt: '2026-01-01T00:00:00Z',
  },
];

const mockLeaveTypes = [
  { id: 'lt-annual', code: 'annual', nameAr: 'إجازة سنوية', isPaid: true, requiresAttachment: false, maxDaysPerYear: 24, affectsBalance: true, color: null },
  { id: 'lt-sick', code: 'sick', nameAr: 'إجازة مرضية', isPaid: true, requiresAttachment: false, maxDaysPerYear: null, affectsBalance: false, color: null },
];

let employeesOverride: () => Record<string, unknown>;
let leaveTypesOverride: () => Record<string, unknown>;

const mockMutation = { mutate: vi.fn(), mutateAsync: vi.fn(), isPending: false, isError: false, error: null };

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => employeesOverride(),
}));

vi.mock('../useLeaveTools', () => ({
  useLeaveTypes: () => leaveTypesOverride(),
  useGrantRestCreditBulk: () => mockMutation,
  useAdjustLeaveBalance: () => mockMutation,
  useCreateLeaveForEmployee: () => mockMutation,
  useCreateBulkAssignment: () => mockMutation,
}));

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ access: { permissions: ['*'] } }),
}));

vi.mock('../../workspaces/access', () => ({
  hasAnyPermission: () => true,
}));

const employeesQuery = { data: mockEmployees, isLoading: false, isError: false, error: null };
const leaveTypesQuery = { data: mockLeaveTypes, isLoading: false, isError: false, error: null };

describe('LeaveToolsPage', () => {
  beforeEach(() => {
    employeesOverride = () => employeesQuery;
    leaveTypesOverride = () => leaveTypesQuery;
  });

  it('يُعرض بدون أخطاء', () => {
    const { container } = render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getByText('أدوات الإجازات والتكليفات')).toBeDefined();
  });

  it('يعرض الأقسام الأربعة: منح بدل راحة، ضبط رصيد، إنشاء إجازة بدل الموظف، قافلة/فاندي', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getByText('منح بدل راحة أسبوعي (جماعي)')).toBeDefined();
    expect(screen.getByText('ضبط رصيد إجازة')).toBeDefined();
    expect(screen.getByText('إنشاء إجازة بدل الموظف')).toBeDefined();
    expect(screen.getByText('إضافة قافلة / فاندي')).toBeDefined();
  });

  it('يعرض إشعار أن الإجازة المرضية مفتوحة', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getByText(/الإجازة المرضية/)).toBeDefined();
  });

  it('يعرض أسماء الموظفين في قائمة الاختيار الجماعي', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('أحمد محمد').length).toBeGreaterThan(0);
    expect(screen.getAllByText('سارة علي').length).toBeGreaterThan(0);
  });

  it('يعرض أنواع الإجازات في قسم إنشاء الإجازة', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getAllByText('إجازة سنوية').length).toBeGreaterThan(0);
    expect(screen.getAllByText(/إجازة مرضية/).length).toBeGreaterThan(0);
  });

  it('يعرض خيار جميع الموظفين النشطين في قسم القافلة/الفاندي', () => {
    render(
      <Wrapper>
        <LeaveToolsPage />
      </Wrapper>,
    );
    expect(screen.getByText(/جميع الموظفين النشطين/)).toBeDefined();
  });
});