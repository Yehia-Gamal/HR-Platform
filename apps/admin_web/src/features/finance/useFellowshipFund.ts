import {
  fellowshipFundSummarySchema,
  fellowshipFundTransactionSchema,
  withdrawFellowshipFundResultSchema,
  type FellowshipFundSummary,
  type FellowshipFundTransaction,
  type WithdrawFellowshipFundInput,
  type WithdrawFellowshipFundResult,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export type { FellowshipFundSummary, FellowshipFundTransaction, WithdrawFellowshipFundInput };

export const FELLOWSHIP_FUND_SUMMARY_KEY = 'fellowship-fund-summary';
export const FELLOWSHIP_FUND_TX_KEY = 'fellowship-fund-transactions';

export const FELLOWSHIP_CATEGORIES = ['غرامة تأخير حضور', 'مساعدة زميل', 'مناسبة اجتماعية', 'علاج وطوارئ', 'تكريم وتميز', 'مساهمة تطوعية', 'أخرى'] as const;

export interface FellowshipFundTransactionsFilter {
  type?: 'all' | 'inflow' | 'outflow';
  search?: string;
  limit?: number;
  offset?: number;
}

// ─── استعلام ملخص ورصيد صندوق الزمالة ────────────────────────────────
export function useFellowshipFundSummary() {
  const auth = useAuth();
  return useQuery({
    queryKey: [FELLOWSHIP_FUND_SUMMARY_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    refetchInterval: 30_000,
    queryFn: async (): Promise<FellowshipFundSummary> => {
      if (auth.isMock) {
        return {
          currentBalance: 0,
          totalInflows: 0,
          totalOutflows: 0,
          inflowsCount: 0,
          outflowsCount: 0,
          monthlyInflows: 0,
          monthlyOutflows: 0,
          categoryBreakdown: [],
          recentTransactions: [],
        };
      }
      return fellowshipFundSummarySchema.parse(await rpc('get_fellowship_fund_summary'));
    },
  });
}

// ─── استعلام سجل الحركات الشفاف ──────────────────────────────────────
export function useFellowshipFundTransactions(filter: FellowshipFundTransactionsFilter = {}) {
  const auth = useAuth();
  const { type, search, limit = 50, offset = 0 } = filter;
  return useQuery({
    queryKey: [FELLOWSHIP_FUND_TX_KEY, auth.isMock, type, search, limit, offset],
    enabled: auth.status === 'authenticated',
    refetchInterval: 30_000,
    queryFn: async (): Promise<FellowshipFundTransaction[]> => {
      if (auth.isMock) return [];
      return fellowshipFundTransactionSchema.array().parse(
        await rpc('get_fellowship_fund_transactions', {
          p_limit: limit,
          p_offset: offset,
          p_type: type && type !== 'all' ? type : null,
          p_search: search?.trim() || null,
        }),
      );
    },
  });
}

// ─── سحب مبلغ من صندوق الزمالة (أدمن فقط) ─────────────────────────────
export function useWithdrawFromFellowshipFund() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (input: WithdrawFellowshipFundInput): Promise<WithdrawFellowshipFundResult> => {
      return withdrawFellowshipFundResultSchema.parse(
        await rpc('withdraw_from_fellowship_fund', {
          p_amount: input.amount,
          p_category: input.category,
          p_reason: input.reason,
          p_beneficiary_employee_id: input.beneficiaryEmployeeId ?? null,
          p_notes: input.notes ?? null,
        }),
      );
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: [FELLOWSHIP_FUND_SUMMARY_KEY] });
      queryClient.invalidateQueries({ queryKey: [FELLOWSHIP_FUND_TX_KEY] });
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
    },
  });
}
