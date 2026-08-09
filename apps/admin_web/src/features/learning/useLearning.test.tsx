import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';

vi.mock('../../core/rpc', () => ({
  rpc: vi.fn().mockResolvedValue({
    courses: [
      { id: '00000000-0000-0000-0000-000000000001', code: 'C001', title: 'دورة أمن المعلومات', category: 'تقنية', deliveryMode: 'online', durationMinutes: 120, mandatory: true, active: true, enrollments: 5, completed: 2 },
    ],
    enrollments: [],
    employees: [],
  }),
}));

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: false, access: { permissions: new Set() } }),
}));

import { useLearningCatalog } from './useLearning';

function wrapper({ children }: { children: ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useLearningCatalog', () => {
  beforeEach(() => vi.clearAllMocks());

  it('fetches catalog with courses', async () => {
    const { result } = renderHook(() => useLearningCatalog(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.courses).toHaveLength(1);
    expect(result.current.data?.courses[0].title).toBe('دورة أمن المعلومات');
    expect(result.current.data?.enrollments).toHaveLength(0);
  });
});
