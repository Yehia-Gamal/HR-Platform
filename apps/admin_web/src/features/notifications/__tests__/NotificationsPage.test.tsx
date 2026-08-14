import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi } from 'vitest';
import { ToastProvider } from '../../../ui/Toast';
import { NotificationsPage } from '../NotificationsPage';

function Wrapper({ children }: { children: React.ReactNode }) {
  return (
    <MemoryRouter>
      <ToastProvider>{children}</ToastProvider>
    </MemoryRouter>
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

vi.mock('../useNotifications', () => ({
  useNotifications: () => notifReturn,
  useMarkNotificationsRead: () => markReturn,
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

describe('NotificationsPage', () => {
  it('يُعرض بدون أخطاء', () => {
    notifReturn = dataQuery;
    markReturn = markMutation;
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
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('طلب إجازة جديد')).toBeDefined();
    expect(screen.getByText('تمت الموافقة على طلبك')).toBeDefined();
  });

  it('يعرض حالة التحميل', () => {
    notifReturn = loadingQuery;
    markReturn = markMutation;
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
    render(
      <Wrapper>
        <NotificationsPage />
      </Wrapper>,
    );
    expect(screen.getByText('تعذر تحميل الإشعارات')).toBeDefined();
  });
});
