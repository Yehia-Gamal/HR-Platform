import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useAnalyticsDashboard } from './useAnalyticsDashboard';

vi.mock('../../features/auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: true }),
}));

function wrapper({ children }: { children: React.ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={qc}>{children}</QueryClientProvider>;
}

describe('useAnalyticsDashboard', () => {
  beforeEach(() => { vi.clearAllMocks(); });

  it('يُرجع بيانات اللوحة في وضع mock', async () => {
    const { result } = renderHook(() => useAnalyticsDashboard(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const data = result.current.data;
    expect(data).toBeDefined();
    expect(data?.monthlyRequests.length).toBeGreaterThan(0);
    expect(data?.attendanceTrend.length).toBeGreaterThan(0);
    expect(data?.departmentDistribution.length).toBeGreaterThan(0);
    expect(data?.kpiScores.length).toBeGreaterThan(0);
  });

  it('كل عنصر طلبات شهرية يحتوي الحقول المطلوبة', async () => {
    const { result } = renderHook(() => useAnalyticsDashboard(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const req = result.current.data?.monthlyRequests[0];
    expect(req).toBeDefined();
    expect(req).toHaveProperty('month');
    expect(req).toHaveProperty('monthKey');
    expect(typeof req?.approved).toBe('number');
    expect(typeof req?.rejected).toBe('number');
    expect(typeof req?.pending).toBe('number');
    expect(typeof req?.cancelled).toBe('number');
  });

  it('كل عنصر حضور يحتوي حاضر/متأخر/غائب', async () => {
    const { result } = renderHook(() => useAnalyticsDashboard(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const day = result.current.data?.attendanceTrend[0];
    expect(day).toBeDefined();
    expect(typeof day?.present).toBe('number');
    expect(typeof day?.late).toBe('number');
    expect(typeof day?.absent).toBe('number');
  });

  it('كل مؤشر KPI يحتوي subject + actual + target', async () => {
    const { result } = renderHook(() => useAnalyticsDashboard(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const kpi = result.current.data?.kpiScores[0];
    expect(kpi).toBeDefined();
    expect(typeof kpi?.subject).toBe('string');
    expect(typeof kpi?.actual).toBe('number');
    expect(typeof kpi?.target).toBe('number');
  });
});
