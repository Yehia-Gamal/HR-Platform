import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { createElement, type ReactNode } from 'react';
import { describe, expect, it, vi, beforeEach } from 'vitest';
import { usePenaltyDisputes, useSubmitPenaltyDispute, useReviewPenaltyDispute } from '../usePenaltyDisputes';

const mockRpc = vi.fn();

vi.mock('../../../core/rpc', () => ({
  rpc: (...args: unknown[]) => mockRpc(...args),
}));

function createWrapper() {
  const qc = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return function Wrapper({ children }: { children: ReactNode }) {
    return createElement(QueryClientProvider, { client: qc }, children);
  };
}

beforeEach(() => {
  vi.clearAllMocks();
});

const sampleDisputes = [
  {
    id: 'd1',
    penalty_id: 'p1',
    employee_id: 'e1',
    employee_name: 'أحمد محمد',
    department: 'الإدارة العامة',
    penalty_date: '2026-09-19',
    penalty_amount: 20,
    reason: 'تأخير غير مبرر',
    status: 'pending' as const,
    reviewed_by: null,
    reviewer_name: null,
    review_note: null,
    reviewed_at: null,
    created_at: '2026-09-19T10:00:00Z',
  },
];

describe('usePenaltyDisputes', () => {
  it('يُرجع بيانات الاستفسارات عند النجاح', async () => {
    mockRpc.mockResolvedValueOnce(sampleDisputes);

    const { result } = renderHook(() => usePenaltyDisputes(), {
      wrapper: createWrapper(),
    });

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual(sampleDisputes);
    expect(mockRpc).toHaveBeenCalledWith('get_penalty_disputes', { p_status: null });
  });

  it('يمرّر فلتر الحالة عند وجوده', async () => {
    mockRpc.mockResolvedValueOnce([sampleDisputes[0]]);

    const { result } = renderHook(() => usePenaltyDisputes('approved'), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(mockRpc).toHaveBeenCalledWith('get_penalty_disputes', { p_status: 'approved' });
  });

  it('يُرجع مصفوفة فارغة عند عودة null', async () => {
    mockRpc.mockResolvedValueOnce(null);

    const { result } = renderHook(() => usePenaltyDisputes(), {
      wrapper: createWrapper(),
    });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual([]);
  });
});

describe('useSubmitPenaltyDispute', () => {
  it('يستدعي rpc ويعيد المعرف عند النجاح', async () => {
    mockRpc.mockResolvedValueOnce('dispute-id-123');

    const { result } = renderHook(() => useSubmitPenaltyDispute(), {
      wrapper: createWrapper(),
    });

    const response = await result.current.mutateAsync({
      penaltyId: 'p1',
      reason: 'الغرامة غير صحيحة',
    });

    expect(response).toBe('dispute-id-123');
    expect(mockRpc).toHaveBeenCalledWith('submit_penalty_dispute', {
      p_penalty_id: 'p1',
      p_reason: 'الغرامة غير صحيحة',
    });
  });

  it('يرمي خطأ عند فشل RPC', async () => {
    mockRpc.mockRejectedValueOnce(new Error('RPC failed'));

    const { result } = renderHook(() => useSubmitPenaltyDispute(), {
      wrapper: createWrapper(),
    });

    try {
      await result.current.mutateAsync({ penaltyId: 'p1', reason: 'سبب' });
      expect.fail('يجب أن يرمي خطأ');
    } catch (e: unknown) {
      expect(e).toBeInstanceOf(Error);
      expect((e as Error).message).toBe('RPC failed');
    }
  });
});

describe('useReviewPenaltyDispute', () => {
  it('يستدعي rpc بالمعاملات الصحيحة عند الموافقة', async () => {
    mockRpc.mockResolvedValueOnce(undefined);

    const { result } = renderHook(() => useReviewPenaltyDispute(), {
      wrapper: createWrapper(),
    });

    await result.current.mutateAsync({
      disputeId: 'd1',
      status: 'approved',
      note: 'تمت المراجعة',
    });

    expect(mockRpc).toHaveBeenCalledWith('review_penalty_dispute', {
      p_dispute_id: 'd1',
      p_status: 'approved',
      p_review_note: 'تمت المراجعة',
    });
  });

  it('يرسل null كملاحظة عند عدم تقديمها', async () => {
    mockRpc.mockResolvedValueOnce(undefined);

    const { result } = renderHook(() => useReviewPenaltyDispute(), {
      wrapper: createWrapper(),
    });

    await result.current.mutateAsync({
      disputeId: 'd1',
      status: 'rejected',
    });

    expect(mockRpc).toHaveBeenCalledWith('review_penalty_dispute', {
      p_dispute_id: 'd1',
      p_status: 'rejected',
      p_review_note: null,
    });
  });

  it('يرمي خطأ عند فشل RPC', async () => {
    mockRpc.mockRejectedValueOnce(new Error('Review failed'));

    const { result } = renderHook(() => useReviewPenaltyDispute(), {
      wrapper: createWrapper(),
    });

    try {
      await result.current.mutateAsync({ disputeId: 'd1', status: 'approved' });
      expect.fail('يجب أن يرمي خطأ');
    } catch (e: unknown) {
      expect(e).toBeInstanceOf(Error);
      expect((e as Error).message).toBe('Review failed');
    }
  });
});
