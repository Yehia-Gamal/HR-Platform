import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { InstantPenaltiesPage } from '../InstantPenaltiesPage';

let penaltiesData: Record<string, unknown>;
let pendingData: Record<string, unknown>;
let employeesData: Record<string, unknown>;

vi.mock('../useInstantPenalties', () => ({
  INSTANT_PENALTY_STATUS_LABELS: {
    pending_payment: 'بانتظار الدفع',
    paid: 'مدفوعة',
    doubled: 'مضاعفة (500 ج.م)',
    suspended: 'معلّق عن العمل',
    cancelled: 'ملغاة',
  },
  INSTANT_PENALTY_ESCALATION_LABELS: {
    initial: 'أولية',
    doubled: 'مضاعفة',
    suspended: 'تعليق',
  },
  useInstantPenalties: () => penaltiesData,
  usePendingPenaltyEmployees: () => pendingData,
  useGenerateInstantPenalty: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
  useConfirmInstantPenaltyPayment: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
  useCancelInstantPenalty: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
  useLiftInstantPenaltySuspension: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
}));

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => employeesData,
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
const emptyPending = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyEmployees = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
};

const samplePenalties = {
  data: [
    {
      id: '11111111-1111-4111-8111-111111111111',
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'أحمد محمد',
      employeeCode: 'E-001',
      departmentName: 'الإدارة العامة',
      workDate: '2026-09-19',
      lateMinutes: 25,
      originalAmount: 20,
      currentAmount: 20,
      currency: 'EGP',
      status: 'pending_payment',
      escalationLevel: 'initial',
      paidAt: null,
      confirmedBy: null,
      suspendedAt: null,
      suspensionLiftedAt: null,
      notes: null,
      createdAt: '2026-09-19T10:30:00.000Z',
    },
  ],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

const suspendedEmployees = {
  data: [
    {
      employeeId: '22222222-2222-4222-8222-222222222222',
      employeeName: 'أحمد محمد',
      employeeCode: 'E-001',
      departmentName: 'الإدارة العامة',
      pendingCount: 2,
      totalAmount: 500,
      isSuspended: true,
      latestDate: '2026-09-18',
    },
  ],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

function renderPage() {
  return render(
    <MemoryRouter>
      <InstantPenaltiesPage />
    </MemoryRouter>,
  );
}

describe('InstantPenaltiesPage', () => {
  it('يُعرض بدون أخطاء', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    const { container } = renderPage();
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('الغرامات الفورية للتأخير')).toBeDefined();
  });

  it('يعرض زر إنشاء غرامة يدوية', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('إنشاء غرامة يدوياً')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    penaltiesData = loadingPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    const { container } = renderPage();
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود غرامات', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('لا توجد غرامات فورية')).toBeDefined();
  });

  it('يعرض شريط البحث والتصفية', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByPlaceholderText('ابحث بالموظف أو الإدارة…')).toBeDefined();
    expect(screen.getByLabelText('تصفية حسب الحالة')).toBeDefined();
  });

  it('يعرض بيانات الغرامة في الجدول', () => {
    penaltiesData = samplePenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('أحمد محمد')).toBeDefined();
    expect(screen.getByText('الإدارة العامة')).toBeDefined();
    expect(screen.getByText(/25/)).toBeDefined();
  });

  it('يعرض أزرار تأكيد الدفع والإلغاء للغرامة غير المدفوعة', () => {
    penaltiesData = samplePenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('تأكيد الدفع')).toBeDefined();
    expect(screen.getByText('إلغاء')).toBeDefined();
  });

  it('يعرض حالة المدفوعة بدون أزرار', () => {
    penaltiesData = {
      ...samplePenalties,
      data: [{ ...samplePenalties.data[0], status: 'paid' }],
    };
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('✓ مدفوعة ومُزيلَة')).toBeDefined();
  });

  it('يعرض حالة الملغاة بدون أزرار', () => {
    penaltiesData = {
      ...samplePenalties,
      data: [{ ...samplePenalties.data[0], status: 'cancelled' }],
    };
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    const matches = screen.getAllByText('ملغاة');
    expect(matches.length).toBeGreaterThanOrEqual(2);
  });

  it('يعرض زر فتح السيستم للغرامة المعلّقة', () => {
    penaltiesData = {
      ...samplePenalties,
      data: [{ ...samplePenalties.data[0], status: 'suspended' }],
    };
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText(/استلام 500 ج وفتح السيستم/)).toBeDefined();
    expect(screen.getByText('رفع التعليق')).toBeDefined();
  });

  it('يعرض الموظفين المعلقين عند وجودهم', () => {
    penaltiesData = emptyPenalties;
    pendingData = suspendedEmployees;
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText(/موظفون موقوفون عن العمل/)).toBeDefined();
    expect(screen.getByText('أحمد محمد')).toBeDefined();
  });

  it('يعرض إحصائيات عند وجود بيانات', () => {
    penaltiesData = emptyPenalties;
    pendingData = {
      data: [
        {
          employeeId: '22222222-2222-4222-8222-222222222222',
          employeeName: 'أحمد',
          employeeCode: 'E-001',
          departmentName: 'إدارة',
          pendingCount: 1,
          totalAmount: 200,
          isSuspended: false,
          latestDate: '2026-09-19',
        },
      ],
      isLoading: false,
      isError: false,
      error: null,
      refetch: vi.fn(),
    };
    employeesData = emptyEmployees;
    renderPage();
    expect(screen.getByText('1')).toBeDefined();
    expect(screen.getByText('موظف مطالب بالدفع')).toBeDefined();
  });

  it('يعرض الفلاتر مع الحالة الملغاة', () => {
    penaltiesData = emptyPenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();
    const select = screen.getByLabelText('تصفية حسب الحالة');
    expect(select).toBeDefined();
    expect(screen.getByText('ملغاة')).toBeDefined();
  });
});
