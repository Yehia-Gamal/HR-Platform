import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { MemoryRouter } from 'react-router';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import type { AccessContext } from '@ahla/shared-contracts';
import { ToastProvider } from '../../../ui/Toast';
import { BroadcastAlertBanner, BroadcastAlertButton } from '../BroadcastAlert';

let authState: {
  session: unknown;
  access: AccessContext | null;
  isMock: boolean;
};
let sendError: Error | null = null;

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => authState,
}));

vi.mock('../../workspaces/access', () => ({
  hasPermission: (ctx: unknown, permission: string) => ctx != null && permission === 'alerts.broadcast.send',
}));

const sendRpc = vi.fn();
vi.mock('../useBroadcastAlert', async (importOriginal) => {
  // نمط vitest القياسي يتطلب نوع import() هنا — استثناء صريح للقاعدة.
  // eslint-disable-next-line @typescript-eslint/consistent-type-imports
  const original = await importOriginal<typeof import('../useBroadcastAlert')>();
  return {
    ...original,
    useSendBroadcastAlert: () => ({
      mutate: (message: string, options?: { onSuccess?: (id: string) => void; onError?: (e: Error) => void }) => {
        if (sendError) options?.onError?.(sendError);
        else options?.onSuccess?.('alert-1');
      },
      isPending: false,
    }),
    useActiveBroadcastAlert: () => activeQueryReturn,
  };
});

let activeQueryReturn: { data: unknown; isLoading: boolean; refetch: ReturnType<typeof vi.fn> } = {
  data: null,
  isLoading: false,
  refetch: vi.fn(),
};

function Wrapper({ children }: { children: React.ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return (
    <QueryClientProvider client={client}>
      <MemoryRouter>
        <ToastProvider>{children}</ToastProvider>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

beforeEach(() => {
  sendError = null;
  sendRpc.mockClear();
  activeQueryReturn = { data: null, isLoading: false, refetch: vi.fn() };
});

describe('BroadcastAlertButton', () => {
  it('لا يظهر لمن لا يملك صلاحية التنبيه', () => {
    authState = { session: {}, access: null, isMock: false };
    render(<BroadcastAlertButton />, { wrapper: Wrapper });
    expect(screen.queryByRole('button', { name: /تنبيه شامل/ })).toBeNull();
  });

  it('يظهر للمخوّل ويفتح حوار الإرسال ويرسل الرسالة', async () => {
    authState = { session: {}, access: { permissions: ['alerts.broadcast.send'] } as unknown as AccessContext, isMock: false };
    render(<BroadcastAlertButton />, { wrapper: Wrapper });

    fireEvent.click(screen.getByRole('button', { name: /تنبيه شامل/ }));
    const input = screen.getByLabelText('نص التنبيه');
    fireEvent.change(input, { target: { value: 'اجتماع طارئ فورًا في المقر' } });
    fireEvent.click(screen.getByRole('button', { name: 'إرسال التنبيه الآن' }));

    await waitFor(() => expect(screen.getByText('أُرسل التنبيه الشامل لكل الموظفين')).toBeTruthy());
  });

  it('يعرض رسالة خطأ عند فشل الإرسال', async () => {
    authState = { session: {}, access: { permissions: ['alerts.broadcast.send'] } as unknown as AccessContext, isMock: false };
    sendError = new Error('broadcast alert permission required');
    render(<BroadcastAlertButton />, { wrapper: Wrapper });

    fireEvent.click(screen.getByRole('button', { name: /تنبيه شامل/ }));
    fireEvent.change(screen.getByLabelText('نص التنبيه'), { target: { value: 'تجربة إرسال تنبيه' } });
    fireEvent.click(screen.getByRole('button', { name: 'إرسال التنبيه الآن' }));

    // Toast يُعرض عبر portal بعنصر role="alert".
    await waitFor(() => expect(screen.getAllByRole('alert').length).toBeGreaterThan(0));
  });
});

describe('BroadcastAlertBanner', () => {
  it('لا يعرض شيئًا بدون تنبيه نشط', () => {
    authState = { session: {}, access: null, isMock: false };
    const { container } = render(<BroadcastAlertBanner />, { wrapper: Wrapper });
    expect(container.querySelector('[role="alert"]')).toBeNull();
  });

  it('يعرض رسالة التنبيه النشط وزر الصمت', () => {
    authState = { session: {}, access: null, isMock: false };
    activeQueryReturn = {
      data: {
        id: 'alert-9',
        message: 'إنذار تجربة للجميع',
        createdAt: new Date().toISOString(),
        expiresAt: new Date(Date.now() + 60_000).toISOString(),
      },
      isLoading: false,
      refetch: vi.fn(),
    };
    render(<BroadcastAlertBanner />, { wrapper: Wrapper });
    expect(screen.getByRole('alert')).toBeTruthy();
    expect(screen.getByText('إنذار تجربة للجميع')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: 'حسنًا، تم الاطلاع' }));
    expect(screen.queryByRole('alert')).toBeNull();
  });
});
