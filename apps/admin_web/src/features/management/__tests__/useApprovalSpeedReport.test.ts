import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useApprovalSpeedReport, approvalSpeedReportSchema } from '../useApprovalSpeedReport';

vi.mock('../../auth/AuthProvider', () => ({
  useAuth: () => ({ status: 'authenticated', isMock: true }),
}));

function wrapper({ children }: { children: React.ReactNode }) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return React.createElement(QueryClientProvider, { client: qc }, children);
}

describe('useApprovalSpeedReport', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('يُرجع بيانات تقرير سرعة الاعتمادات في وضع mock', async () => {
    const { result } = renderHook(() => useApprovalSpeedReport(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const data = result.current.data;
    expect(data).toBeDefined();
    expect(data?.summary).toBeDefined();
    expect(data?.summary.total_decisions).toBeGreaterThan(0);
    expect(data?.approvers.length).toBeGreaterThan(0);
    expect(data?.byRequestType.length).toBeGreaterThan(0);
  });

  it('البيانات تتطابق مع zod schema', async () => {
    const { result } = renderHook(() => useApprovalSpeedReport(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const data = result.current.data;
    const parsed = approvalSpeedReportSchema.safeParse(data);
    expect(parsed.success).toBe(true);
  });

  it('كل معتمد يحتوي على مؤشرات القرارات والسرعة والمعلقات', async () => {
    const { result } = renderHook(() => useApprovalSpeedReport(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const first = result.current.data?.approvers[0];
    expect(first).toBeDefined();
    expect(first?.name).toBeDefined();
    expect(typeof first?.total_decisions).toBe('number');
    expect(typeof first?.avg_hours).toBe('number');
    expect(typeof first?.median_hours).toBe('number');
    expect(typeof first?.pending_count).toBe('number');
  });

  it('تفصيل أنواع الطلبات يحتوي على متوسط ووسيط زمن الرد', async () => {
    const { result } = renderHook(() => useApprovalSpeedReport(), { wrapper });
    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    const item = result.current.data?.byRequestType[0];
    expect(item).toBeDefined();
    expect(item?.request_type).toBeDefined();
    expect(typeof item?.decisions_count).toBe('number');
    expect(typeof item?.avg_hours).toBe('number');
    expect(typeof item?.median_hours).toBe('number');
  });
});
