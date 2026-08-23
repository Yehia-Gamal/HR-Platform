import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { NotificationsPage } from '../NotificationsPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  // 0455: BroadcastAlertButton يستخدم TanStack Query داخليًا — نوفّر عميلًا للاختبار.
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return (
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <ToastProvider>{children}</ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

const mockNotification = {
  id: 'notif-1',
  title: 'طلب إجازة جديد',
  body: 'قدّم أحمد محمد طلب إجازة سنوية',
  priority: 'high',
  category: 'request',
  isRead: false,
  entityType: 'request',
  entityId: 'req-1',
  actionUrl: '/hr/requests',
  createdAt: '2026-08-01T10:00:00Z',
};

const readNotification = {
  ...mockNotification,
  id: 'notif-2',
  isRead: true,
  title: 'تمت الموافقة على طلبك',
};

let notifReturn: Record<string, unknown> = {};
let markReturn: Record<string, unknown> = {};
let deleteReturn: Record<string, unknown> = {};

vi.mock('../useNotifications', () => ({
  useNotifications: () => notifReturn,
  useMarkNotificationsRead: () => markReturn,
  useDeleteNotifications: () => deleteReturn,
}));

// زر التنبيه الشامل يحتاج سياق المصادقة — بلا صلاحيات يختفي من الواجهة.
vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ session: null, access: null, isMock: true }),
}));

const dataQuery = {
  data: [mockNotification, readNotification],
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
const markMutation = {
  mutate: vi.fn(),
  mutateAsync: vi.fn(),
  isPending: false,
  isError: false,
  error: null,
};
const deleteMutation = {
  mutate: vi.fn(),
  mutateAsync: vi.fn(),
  isPending: false,
  isError: false,
  error: null,
};

describe('NotificationsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    const { container } = render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(container.firstChild).toBeTruthy();
  });

  it('يعرض عنوان الصفحة', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('الإشعارات')).toBeDefined();
  });

  it('يعرض زر تعليم الكل كمقروء', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعليم الكل كمقروء')).toBeDefined();
  });

  it('يعرض بيانات الإشعارات', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('طلب إجازة جديد')).toBeDefined();
    expect(screen.getByText('تمت الموافقة على طلبك')).toBeDefined();
  });

  it('يعرض أزرار حذف لكل إشعار', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getAllByLabelText('حذف الإشعار')).toHaveLength(2);
  });

  it('يعرض حالة التحميل', () => {
    notifReturn = loadingQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    const { container } = render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(container.querySelector('.animate-pulse')).toBeTruthy();
  });

  it('يعرض حالة فارغة عند عدم وجود إشعارات', () => {
    notifReturn = emptyQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('لا توجد إشعارات')).toBeDefined();
  });

  it('يعرض حالة الخطأ', () => {
    notifReturn = errorQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل الإشعارات')).toBeDefined();
  });

  it('يدخل وضع التحديد ويعرض مربعات اختيار بدل أزرار الحذف', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByText('تحديد'));
    expect(screen.getAllByLabelText('تحديد الإشعار')).toHaveLength(2);
    expect(screen.queryByLabelText('حذف الإشعار')).toBeNull();
    expect(screen.getByText('إلغاء التحديد')).toBeDefined();
    expect(screen.getByText('تحديد الكل (0/2)')).toBeDefined();
  });

  it('يعرض عدد المحدد في زر المسح ويحدد الكل دفعة واحدة', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = deleteMutation;
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByText('تحديد'));
    fireEvent.click(screen.getAllByLabelText('تحديد الإشعار')[0]);
    expect(screen.getByText('مسح المحدد (1)')).toBeDefined();
    fireEvent.click(screen.getByLabelText('تحديد الكل'));
    expect(screen.getByText('مسح المحدد (2)')).toBeDefined();
    expect(screen.getByText('تحديد الكل (2/2)')).toBeDefined();
  });

  it('يحذف المحدد دفعة واحدة بعد التأكيد', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = { ...deleteMutation, mutate: vi.fn() };
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByText('تحديد'));
    fireEvent.click(screen.getByLabelText('تحديد الكل'));
    fireEvent.click(screen.getByText('مسح المحدد (2)'));
    expect(screen.getByText('حذف الإشعارات المحددة')).toBeDefined();
    fireEvent.click(screen.getByText('حذف'));
    expect(deleteReturn.mutate).toHaveBeenCalledWith(['notif-1', 'notif-2'], expect.anything());
  });

  it('يغلق وضع التحديد بالزر إلغاء التحديد دون مسح', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = { ...deleteMutation, mutate: vi.fn() };
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getByText('تحديد'));
    fireEvent.click(screen.getByLabelText('تحديد الكل'));
    fireEvent.click(screen.getByText('إلغاء التحديد'));
    expect(screen.queryByLabelText('تحديد الإشعار')).toBeNull();
    expect(deleteReturn.mutate).not.toHaveBeenCalled();
  });

  it('يتيح حذف الإشعارات الفردية أثناء عدم وضع التحديد', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
    deleteReturn = { ...deleteMutation, mutate: vi.fn() };
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    fireEvent.click(screen.getAllByLabelText('حذف الإشعار')[0]);
    expect(deleteReturn.mutate).toHaveBeenCalledWith(['notif-1'], expect.anything());
  });
});
