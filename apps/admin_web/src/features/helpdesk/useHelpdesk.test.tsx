import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const mockTickets = [
  { id: 't1', subject: 'مشكلة دخول', category: 'auth', priority: 'high', status: 'open', created_at: '2026-01-01', updated_at: '2026-01-02' },
];

vi.mock('../../core/supabase', () => ({
  getSupabase: vi.fn().mockResolvedValue({
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        order: vi.fn().mockReturnValue({
          limit: vi.fn().mockReturnValue({
            range: vi.fn().mockResolvedValue({ data: mockTickets, error: null, count: 1 }),
          }),
        }),
      }),
    }),
  }),
}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: false, access: { permissions: new Set() } }),
}));

import { useHelpdeskTickets } from './useHelpdesk';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useHelpdeskTickets', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches tickets list', async () => {
    const { result } = renderHook(() => useHelpdeskTickets(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true), { timeout: 3000 });
    expect(result.current.data).toBeDefined();
  });
});
