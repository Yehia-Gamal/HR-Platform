import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { HelpdeskPage } from '../HelpdeskPage';

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

let ticketsOverrideFn: () => Record<string, unknown>;
vi.mock('../useHelpdesk', () => ({
  useHelpdeskTickets: () => ticketsOverrideFn(),
  useCreateTicket: () => noopMutation,
  useUpdateTicketStatus: () => noopMutation,
  useSendTicketMessage: () => noopMutation,
  useTicketMessages: () => ({ data: [], isLoading: false, isError: false, error: null }),
}));

const mockTickets = [
  {
    id: '11111111-1111-4111-8111-111111111111',
    subject: 'مشكلة في تسجيل الحضور',
    category: 'تقني',
    priority: 'high',
    status: 'open',
    requester_employee_id: '00000000-0000-0000-0000-000000000002',
    assignee_employee_id: null,
    sla_due_at: null,
    created_at: '2026-01-15T10:00:00Z',
    updated_at: null,
    requester_name: 'أحمد محمد',
    assignee_name: null,
  },
];

const emptyQuery = { data: [], isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const loadingQuery = { data: undefined, isLoading: true, isError: false, error: null, isFetching: false, refetch: vi.fn() };
const dataQuery = { data: mockTickets, isLoading: false, isError: false, error: null, isFetching: false, refetch: vi.fn() };

describe('HelpdeskPage', () => {
  it('يُعرض بدون أخطاء', () => {
    ticketsOverrideFn = () => dataQuery;
    const { container } = render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    ticketsOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(screen.getByText('مكتب الخدمات')).toBeDefined();
  });

  it('يعرض شريط البحث', () => {
    ticketsOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(screen.getByPlaceholderText('ابحث في الموضوع أو التصنيف...')).toBeDefined();
  });

  it('يعرض بطاقات المؤشرات', () => {
    ticketsOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(screen.getByText('التذاكر المفتوحة')).toBeDefined();
    expect(screen.getByText('الإجمالي')).toBeDefined();
  });

  it('يعرض تبويبي صندوق الخدمات وتذاكري', () => {
    ticketsOverrideFn = () => dataQuery;
    render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(screen.getByText('صندوق الخدمات')).toBeDefined();
    expect(screen.getByText('تذاكرى')).toBeDefined();
  });

  it('يعرض حالة فارغة عند عدم وجود تذاكر', () => {
    ticketsOverrideFn = () => emptyQuery;
    render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد تذاكر')).toBeDefined();
  });

  it('يعرض حالة التحميل أثناء جلب البيانات', () => {
    ticketsOverrideFn = () => loadingQuery;
    const { container } = render(
      <Wrapper>
        <HelpdeskPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });
});
