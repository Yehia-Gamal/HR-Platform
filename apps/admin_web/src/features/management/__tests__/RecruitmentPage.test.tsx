import { render, screen } from '@testing-library/react';
import type { ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { RecruitmentPage } from '../RecruitmentPage';

function Wrapper({ children }: { children: ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockMut = { isPending: false, isError: false, error: null, mutateAsync: vi.fn(), mutate: vi.fn() };

let overviewFn: () => Record<string, unknown>;
let orgFn: () => Record<string, unknown>;
let workbenchFn: () => Record<string, unknown>;

vi.mock('../useAdminOperations', () => ({
  useOrganizationAdminCatalog: () => orgFn(),
  useRecruitmentCommands: () => ({
    createRequisition: { ...mockMut },
  }),
}));

vi.mock('../useEnterpriseOperations', () => ({
  useRecruitmentWorkbench: () => workbenchFn(),
  useRecruitmentWorkbenchCommands: () => ({
    scheduleInterview: { ...mockMut },
    createOffer: { ...mockMut },
    decideInterview: { ...mockMut },
    transitionOffer: { ...mockMut },
    moveStage: { ...mockMut },
    hireApplicant: { ...mockMut },
  }),
}));

vi.mock('../useManagementOverviews', () => ({
  useRecruitmentOverview: () => overviewFn(),
}));

const emptyOrg = {
  data: { departments: [] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const emptyWorkbench = { data: null, isLoading: false, isError: false, error: null, refetch: vi.fn() };
const mockOverviewData = {
  requisitions: 5,
  pendingRequisitions: 2,
  openPostings: 3,
  candidates: 12,
  hiredApplications: 1,
  recentRequisitions: [],
  pipeline: [],
  activeApplications: 0,
};
const loadingOverview = { data: undefined, isLoading: true, isError: false, error: null, refetch: vi.fn() };
const dataOverview = {
  data: mockOverviewData,
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};
const errorOverview = {
  data: undefined,
  isLoading: false,
  isError: true,
  error: new Error('network error'),
  refetch: vi.fn(),
};
const workbenchWithData = {
  data: { applications: [], stages: [], interviews: [], offers: [] },
  isLoading: false,
  isError: false,
  error: null,
  refetch: vi.fn(),
};

describe('RecruitmentPage', () => {
  it('يُعرض بدون أخطاء', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    const { container } = render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('التوظيف وATS')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات الإحصائية', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('طلبات التوظيف')).toBeDefined();
    expect(screen.getByText('تنتظر الاعتماد')).toBeDefined();
    expect(screen.getByText('إعلانات مفتوحة')).toBeDefined();
    expect(screen.getByText('المرشحون')).toBeDefined();
    expect(screen.getByText('تم تعيينهم')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    overviewFn = () => loadingOverview;
    orgFn = () => ({ ...emptyOrg, isLoading: true });
    workbenchFn = () => emptyWorkbench;
    const { container } = render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة الخطأ عند فشل التحميل', () => {
    overviewFn = () => errorOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل التوظيف')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود طلبات توظيف', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد طلبات توظيف')).toBeDefined();
  });

  it('يعرض قسم أحدث طلبات التوظيف', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => emptyWorkbench;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('أحدث طلبات التوظيف')).toBeDefined();
  });

  it('يعرض لوحة المرشحين عند توفر بيانات الـ workbench', () => {
    overviewFn = () => dataOverview;
    orgFn = () => emptyOrg;
    workbenchFn = () => workbenchWithData;
    render(
      <Wrapper>
        <RecruitmentPage />
      </Wrapper>,
    );
    expect(screen.getByText('لوحة المرشحين والمراحل')).toBeDefined();
    expect(screen.getByText('لا توجد طلبات مرشحين')).toBeDefined();
  });
});
