import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { EmployeePasswordsPage, generateSecurePassword } from '../EmployeePasswordsPage';
import { ToastProvider } from '../../../ui/Toast';

const mockMutateSetPassword = vi.fn().mockResolvedValue(undefined);
const mockMutateResendInvite = vi.fn().mockResolvedValue('تم إرسال الرابط بنجاح');

const mockEmployees = [
  {
    id: '00000000-0000-0000-0000-000000000010',
    employeeCode: 'EMP-101',
    fullNameAr: 'أحمد محمد',
    fullNameEn: 'Ahmed Mohamed',
    phoneE164: '+201234567890',
    status: 'active' as const,
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    department: 'تقنية المعلومات',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'مطور برمجيات',
    createdAt: '2026-01-15T10:00:00Z',
  },
  {
    id: '00000000-0000-0000-0000-000000000020',
    employeeCode: 'EMP-102',
    fullNameAr: 'سارة خالد',
    fullNameEn: 'Sara Khaled',
    phoneE164: '+201122334455',
    status: 'invited' as const,
    isActive: true,
    photoUrl: null,
    departmentId: null,
    teamId: null,
    branchId: null,
    department: 'الموارد البشرية',
    team: null,
    branch: 'المقر الرئيسي',
    jobTitle: 'أخصائي توظيف',
    createdAt: '2026-02-01T10:00:00Z',
  },
];

let employeesQueryOverride: Record<string, unknown>;

vi.mock('../useEmployees', () => ({
  useEmployees: () => employeesQueryOverride,
  useSetEmployeePassword: () => ({
    isPending: false,
    mutateAsync: mockMutateSetPassword,
  }),
  useResendInvite: () => ({
    isPending: false,
    mutateAsync: mockMutateResendInvite,
  }),
}));

const renderPage = () =>
  render(
    <MemoryRouter>
      <ToastProvider>
        <EmployeePasswordsPage />
      </ToastProvider>
    </MemoryRouter>
  );

describe('EmployeePasswordsPage', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    employeesQueryOverride = {
      data: mockEmployees,
      isLoading: false,
      isError: false,
      error: null,
      refetch: vi.fn(),
    };
  });

  it('renders page header, metric cards, and employee table', () => {
    renderPage();

    expect(screen.getByText('إدارة كلمات المرور وحسابات الموظفين')).toBeInTheDocument();
    expect(screen.getByText('إجمالي الموظفين')).toBeInTheDocument();
    expect(screen.getByText('حسابات مفعلة')).toBeInTheDocument();
    expect(screen.getByText('بانتظار تفعيل كلمة المرور')).toBeInTheDocument();

    expect(screen.getByText('أحمد محمد')).toBeInTheDocument();
    expect(screen.getByText('EMP-101')).toBeInTheDocument();
    expect(screen.getByText('سارة خالد')).toBeInTheDocument();
    expect(screen.getByText('EMP-102')).toBeInTheDocument();
  });

  it('filters employees by search term', () => {
    renderPage();

    const searchInput = screen.getByLabelText('البحث عن موظف');
    fireEvent.change(searchInput, { target: { value: 'سارة' } });

    expect(screen.getByText('سارة خالد')).toBeInTheDocument();
    expect(screen.queryByText('أحمد محمد')).not.toBeInTheDocument();
  });

  it('opens reset password dialog and triggers set password mutation', async () => {
    renderPage();

    const changePwdButtons = screen.getAllByText('تغيير كلمة المرور');
    await act(async () => {
      fireEvent.click(changePwdButtons[0]);
    });

    expect(screen.getByText('إعادة تعيين كلمة مرور الموظف')).toBeInTheDocument();

    const generateButton = screen.getByText('توليد كلمة مرور قوية');
    await act(async () => {
      fireEvent.click(generateButton);
    });

    const submitBtn = screen.getByText('حفظ وتعيين كلمة المرور');
    await act(async () => {
      fireEvent.click(submitBtn);
    });

    expect(mockMutateSetPassword).toHaveBeenCalledWith(
      expect.objectContaining({ employeeId: '00000000-0000-0000-0000-000000000010' })
    );
  });

  it('triggers send reset link mutation on click', async () => {
    renderPage();

    const sendLinkButtons = screen.getAllByText('إرسال الرابط');
    await act(async () => {
      fireEvent.click(sendLinkButtons[1]);
    });

    expect(mockMutateResendInvite).toHaveBeenCalledWith('00000000-0000-0000-0000-000000000020');
  });

  it('generates secure passwords that meet all security requirements (>= 12 chars, upper, lower, digit, symbol)', () => {
    for (let i = 0; i < 50; i++) {
      const pwd = generateSecurePassword();
      expect(pwd.length).toBeGreaterThanOrEqual(12);
      expect(pwd.length).toBe(14);
      expect(/[A-Z]/.test(pwd)).toBe(true);
      expect(/[a-z]/.test(pwd)).toBe(true);
      expect(/[0-9]/.test(pwd)).toBe(true);
      expect(/[!@#$%&*]/.test(pwd)).toBe(true);
      // Ensure no 5 consecutive identical characters
      expect(/(.)\1{4,}/.test(pwd)).toBe(false);
    }
  });

  it('allows toggling mustChangePassword in reset password dialog', async () => {
    renderPage();

    const changePwdButtons = screen.getAllByText('تغيير كلمة المرور');
    await act(async () => {
      fireEvent.click(changePwdButtons[0]);
    });

    const checkbox = screen.getByRole('checkbox', {
      name: /إلزام الموظف بتغيير كلمة المرور عند أول تسجيل دخول/i,
    });
    expect(checkbox).toBeChecked();

    // Toggle off
    await act(async () => {
      fireEvent.click(checkbox);
    });
    expect(checkbox).not.toBeChecked();

    const generateButton = screen.getByText('توليد كلمة مرور قوية');
    await act(async () => {
      fireEvent.click(generateButton);
    });

    const submitBtn = screen.getByText('حفظ وتعيين كلمة المرور');
    await act(async () => {
      fireEvent.click(submitBtn);
    });

    expect(mockMutateSetPassword).toHaveBeenCalledWith(
      expect.objectContaining({
        employeeId: '00000000-0000-0000-0000-000000000010',
        mustChangePassword: false,
      })
    );
  });
});
