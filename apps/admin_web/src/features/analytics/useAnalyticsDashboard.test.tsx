import { describe, it, expect } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useAnalyticsDashboard } from './useAnalyticsDashboard';

function wrapper({ children }: { children: React.ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useAnalyticsDashboard', () => {
  it('returns hardcoded dashboard data', async () => {
    const { result } = renderHook(() => useAnalyticsDashboard(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(result.current.data?.monthlyRequests).toHaveLength(6);
    expect(result.current.data?.attendanceTrend).toHaveLength(5);
    expect(result.current.data?.departmentDistribution).toBeDefined();
  });
});
