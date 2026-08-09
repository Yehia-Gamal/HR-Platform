import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

vi.mock('../../core/rpc', () => ({
  rpc: vi.fn().mockResolvedValue([
    { id: 'p1', employeeId: 'e1', employeeName: 'أحمد', amount: 500, reason: 'تأخير', status: 'pending', createdAt: '2026-01-01' },
  ]),
}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: false, access: { permissions: new Set() } }),
}));

import { useEmployeePenalties } from './useFinancialExtensions';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useEmployeePenalties', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches penalties list', async () => {
    const { result } = renderHook(() => useEmployeePenalties({}), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data).toHaveLength(1);
    expect(result.current.data?.[0].employeeName).toBe('أحمد');
  });
});
