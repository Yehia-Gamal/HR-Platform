import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { DailyReportsFeedPage } from '../DailyReportsFeedPage';

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

const mockReport = {
  id: 'report-1',
  employeeId: '00000000-0000-0000-0000-000000000003',
  employeeName: 'سارة علي',
  photoUrl: null,
  jobTitle: 'مسؤولة برامج',
  department: 'قسم البرامج',
  reportDate: '2026-08-01',
  achievements: 'أنجزت تقرير الأنشطة الشهري',
  blockers: null,
  tomorrowPlan: 'مراجعة خطة الأسبوع',
  likesCount: 3,
  isLikedByMe: false,
  managerComment: null,
  reviewedByName: null,
  comments: [],
};

let feedReturn: Record<string, unknown> = {};
const mutationStub = {
  mutate: vi.fn(),
  mutateAsync: vi.fn(),
  isPending: false,
  isError: false,
  error: null,
};

vi.mock('../useDailyReportsFeed', () => ({
  useDailyReportsFeed: () => feedReturn,
  useToggleDailyReportLike: () => mutationStub,
  useAddDailyReportComment: () => mutationStub,
  useDeleteDailyReportComment: () => mutationStub,
  useSubmitDailyReport: () => mutationStub,
}));

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const dataQuery = {
  data: [mockReport],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const loadingQuery = {
  data: undefined,
  isLoading: true,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyQuery = {
  data: [],
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorQuery = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};

describe('DailyReportsFeedPage', () => {
  it('يُعرض بدون أخطاء', () => {
    feedReturn = dataQuery;
    const { container } = render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    feedReturn = dataQuery;
    render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(screen.getByText('التقارير اليومية')).toBeDefined();
  });

  it('يعرض زر تقرير جديد', () => {
    feedReturn = dataQuery;
    render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(screen.getByText('تقرير جديد')).toBeDefined();
  });

  it('يعرض بيانات التقارير', () => {
    feedReturn = dataQuery;
    render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(screen.getByText('سارة علي')).toBeDefined();
    expect(screen.getByText('أنجزت تقرير الأنشطة الشهري')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    feedReturn = loadingQuery;
    const { container } = render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود تقارير', () => {
    feedReturn = emptyQuery;
    render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(screen.getByText('لا توجد تقارير بعد')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    feedReturn = errorQuery;
    render(<Wrapper><DailyReportsFeedPage /></Wrapper>);
    expect(screen.getByText('تعذر تحميل التقارير')).toBeDefined();
  });
});
