import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

const mockRisks = [
  { id: 'r1', title: 'خطر أمني', description: 'وصف', likelihood: 'high', impact: 'high', severity: 'critical', status: 'open', created_at: '2026-01-01', updated_at: '2026-01-02' },
];

vi.mock('../../core/supabase', () => ({
  getSupabase: vi.fn().mockResolvedValue({
    from: vi.fn().mockReturnValue({
      select: vi.fn().mockReturnValue({
        order: vi.fn().mockReturnValue({
          limit: vi.fn().mockResolvedValue({ data: mockRisks, error: null }),
        }),
      }),
    }),
  }),
}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: false, access: { permissions: new Set() } }),
}));

import { useRisks } from './useGovernance';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useRisks', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches risks list', async () => {
    const { result } = renderHook(() => useRisks(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toBeDefined();
  });
});
