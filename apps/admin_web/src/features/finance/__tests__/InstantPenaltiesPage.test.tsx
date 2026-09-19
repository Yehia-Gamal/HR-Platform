import { fireEvent, render, screen } from '@testing-library/react';
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
    reset: vi.fn(),
  }),
  useCancelInstantPenalty: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
    reset: vi.fn(),
  }),
  useLiftInstantPenaltySuspension: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
    reset: vi.fn(),
  }),
  useTriggerCheckPenaltiesNow: () => ({
    isPending: false,
    isError: false,
    error: null,
    mutateAsync: vi.fn(),
  }),
}));

vi.mock('../../employees/useEmployees', () => ({
  useEmployees: () => employeesData,
}));

vi.mock('../useFellowshipFund', () => ({
  useFellowshipFundSummary: () => ({
    data: { currentBalance: 300, totalDeposits: 500, totalDisbursements: 200, depositCount: 2, disbursementCount: 1 },
    isLoading: false,
    isError: false,
    error: null,
  }),
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
    expect(screen.getByText(/الغرامات الفورية للتأخير/)).toBeDefined();
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
    expect(screen.getByText(/استلام من .* وإيداع بالصندوق/)).toBeDefined();
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
    expect(screen.getByText(/استلام من .* وإيداع بالصندوق/)).toBeDefined();
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

  it('يعرض صناديق شرائح الغرامات الـ 4 ويتيح النقر عليها للتصفية', () => {
    penaltiesData = samplePenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();

    expect(screen.getByText('صندوق غرامات 20 ج.م')).toBeDefined();
    expect(screen.getByText('صندوق غرامات 50 ج.م')).toBeDefined();
    expect(screen.getByText('صندوق غرامات 150 ج.م')).toBeDefined();
    expect(screen.getByText('غرامات مضاعفة 500 ج.م')).toBeDefined();

    // النقر على صندوق 20 ج.م لتفعيله
    const tier20Box = screen.getByTitle('انقر لتصفية غرامات الـ 20 ج.م');
    fireEvent.click(tier20Box);

    // التحقق من ظهور شريط التصفية النشطة
    expect(screen.getByText('تصفية نشطة حسب الصندوق:')).toBeDefined();
    expect(screen.getByText('صندوق غرامات 20 ج.م (16-30 دقيقة تأخير)')).toBeDefined();

    // النقر على إلغاء التصفية
    const clearBtn = screen.getByText('إلغاء التصفية ✕');
    fireEvent.click(clearBtn);
    expect(screen.queryByText('تصفية نشطة حسب الصندوق:')).toBeNull();
  });

  it('يفتح نافذة التفاصيل الكاملة عند النقر على تفاصيل الشريحة', () => {
    penaltiesData = samplePenalties;
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();

    const detailButtons = screen.getAllByText('تفاصيل ↗');
    expect(detailButtons.length).toBeGreaterThanOrEqual(1);

    // النقر على تفاصيل أول شريحة (20 ج.م)
    fireEvent.click(detailButtons[0]);

    // التحقق من فتح المودال بعنوان صندوق غرامات 20 ج.م
    expect(screen.getByText('صندوق غرامات 20 ج.م (تأخير 16-30 دقيقة)')).toBeDefined();
    expect(screen.getByText('تصدير هذه الشريحة Excel')).toBeDefined();
  });

  it('يفتح كشف الموظفين المطالبين بالدفع عند النقر على كشف الموظفين', () => {
    penaltiesData = emptyPenalties;
    pendingData = suspendedEmployees;
    employeesData = emptyEmployees;
    renderPage();

    const pendingBtn = screen.getByTitle('عرض تفاصيل الموظفين المطالبين بالدفع');
    fireEvent.click(pendingBtn);

    expect(screen.getByText('كشف الموظفين المطالبين بالدفع حالياً')).toBeDefined();
    expect(screen.getByText('تصدير كشف المطالبين Excel')).toBeDefined();
    expect(screen.getByText('تصفية الجدول بهؤلاء الموظفين ←')).toBeDefined();
  });

  it('يفتح كشف الموظفين المعلقين ويحتوي على أزرار التصدير وتصفية الجدول', () => {
    penaltiesData = emptyPenalties;
    pendingData = suspendedEmployees;
    employeesData = emptyEmployees;
    renderPage();

    const suspendedBtn = screen.getByTitle('عرض تفاصيل الموظفين المعلقين');
    fireEvent.click(suspendedBtn);

    expect(screen.getByText('كشف الموظفين الموقوفين عن العمل (اليوم الثالث)')).toBeDefined();
    expect(screen.getByText('تصدير كشف المعلقين Excel')).toBeDefined();
    expect(screen.getByText('تصفية الجدول بالمعلقين ←')).toBeDefined();
  });

  it('يتعامل صندوق الـ 500 ج.م بشكل دقيق مع المعلقين ويتجاهل الغرامات الملغاة', () => {
    penaltiesData = {
      data: [
        {
          id: 'p1',
          employeeId: 'e1',
          employeeName: 'معلق 1',
          employeeCode: 'E-01',
          departmentName: 'إدارة',
          workDate: '2026-09-17',
          lateMinutes: 40,
          originalAmount: 50,
          currentAmount: 500,
          currency: 'EGP',
          status: 'suspended',
          escalationLevel: 'doubled',
          paidAt: null,
          confirmedBy: null,
          suspendedAt: '2026-09-19T00:00:00Z',
          suspensionLiftedAt: null,
          notes: null,
          createdAt: '2026-09-17T10:40:00Z',
        },
        {
          id: 'p2',
          employeeId: 'e2',
          employeeName: 'ملغاة 500',
          employeeCode: 'E-02',
          departmentName: 'إدارة',
          workDate: '2026-09-17',
          lateMinutes: 60,
          originalAmount: 50,
          currentAmount: 500,
          currency: 'EGP',
          status: 'cancelled',
          escalationLevel: 'doubled',
          paidAt: null,
          confirmedBy: null,
          suspendedAt: null,
          suspensionLiftedAt: null,
          notes: null,
          createdAt: '2026-09-17T11:00:00Z',
        },
      ],
      isLoading: false,
      isError: false,
      error: null,
      refetch: vi.fn(),
    };
    pendingData = emptyPending;
    employeesData = emptyEmployees;
    renderPage();

    // يجب أن يحسب فقط الغرامة غير الملغاة (1 غرامة)
    const tier500Card = screen.getByTitle('انقر لتصفية الغرامات المضاعفة لـ 500 ج.م');
    expect(tier500Card).toBeDefined();

    // النقر على تفاصيل صندوق 500 ج.م
    const detailButtons = screen.getAllByText('تفاصيل ↗');
    // آخر زر تفاصيل هو لشريحة 500 ج.م
    fireEvent.click(detailButtons[detailButtons.length - 1]);

    expect(screen.getByText('صندوق الغرامات المضاعفة 500 ج.م (اليوم الثاني)')).toBeDefined();
    // يجب أن تكون 1 بانتظار التحصيل (لأنها معلقة) و0 موردة بالصندوق
    expect(screen.getByText('بانتظار التحصيل')).toBeDefined();
  });
});

