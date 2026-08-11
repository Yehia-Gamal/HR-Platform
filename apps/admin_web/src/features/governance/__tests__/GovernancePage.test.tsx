import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { GovernancePage } from '../GovernancePage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
  );
}

const mockAccess = {
  userId: '00000000-0000-0000-0000-000000000001',
  employeeId: '00000000-0000-0000-0000-000000000002',
  displayName: 'مستخدم اختبار',
  employeeCode: 'EMP-001',
  photoUrl: null,
  roles: ['hr'],
  permissions: ['*'],
  workspaces: ['hr'] as const,
  defaultWorkspace: 'hr' as const,
  attendancePolicy: { attendanceRequired: false, selfPunchEnabled: false, liveLocationResponseEnabled: false },
};

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', session: null, access: mockAccess, error: null, isMock: true }),
}));

const noopMutation = { mutateAsync: vi.fn(), mutate: vi.fn(), isPending: false, isError: false, error: null };

let risksOverrideFn: () => Record<string, unknown>;
let incidentsOverrideFn: () => Record<string, unknown>;
vi.mock('../useGovernance', () => ({
  useRisks: () => risksOverrideFn(),
  useIncidents: () => incidentsOverrideFn(),
  useUpsertRisk: () => noopMutation,
  useUpsertIncident: () => noopMutation,
}));

const mockRisks = [
  {
    id: '11111111-1111-4111-8111-111111111111',
    title: 'خطر تأخر الرواتب',
    description: 'احتمال تأخر صرف رواتب الشهر القادم',
    severity: 'high',
    likelihood: 'medium',
    impact: 'high',
    status: 'open',
    owner_name: 'أحمد محمد',
    updated_at: '2026-01-15T10:00:00Z',
    created_at: '2026-01-10T10:00:00Z',
  },
];

const mockIncidents = [
  {
    id: '22222222-2222-4222-8222-222222222222',
    title: 'حادثة وصول غير مصرح',
    description: 'تم رصد محاولة وصول غير مصرح به',
    severity: 'critical',
    status: 'open',
    reporter_name: 'فاطمة علي',
    created_at: '2026-01-12T08:00:00Z',
    updated_at: null,
  },
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const risksDataQuery = { data: mockRisks, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const incidentsDataQuery = { data: mockIncidents, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('GovernancePage', () => {
  it('يُعرض بدون أخطاء', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    const { container } = render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByText('الحوكمة والالتزام')).toBeDefined();
  });

  it('يعرض شريط البحث', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByPlaceholderText('ابحث في المخاطر...')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByText('مخاطر حرجة')).toBeDefined();
    expect(screen.getByText('حوادث مفتوحة')).toBeDefined();
    expect(screen.getByText('إجمالي الحوادث')).toBeDefined();
  });

  it('يعرض تبويبي سجل المخاطر والحوادث', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByText('سجل المخاطر')).toBeDefined();
    expect(screen.getByText('سجل الحوادث')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود مخاطر', () => {
    risksOverrideFn = () => emptyQuery;
    incidentsOverrideFn = () => emptyQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد سجلات')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    risksOverrideFn = () => loadingQuery;
    incidentsOverrideFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض أزرار الإضافة للمستخدم ذي الصلاحيات الكاملة', () => {
    risksOverrideFn = () => risksDataQuery;
    incidentsOverrideFn = () => incidentsDataQuery;
    render(
      <Wrapper>
        <GovernancePage />
      </Wrapper>,
    );
    expect(screen.getByText('مخاطرة جديدة')).toBeDefined();
    expect(screen.getByText('حادث جديد')).toBeDefined();
  });
});
