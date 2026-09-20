import {
  cancelInstantPenaltyResultSchema,
  confirmInstantPenaltyPaymentResultSchema,
  executiveDailyDigestSchema,
  generateInstantPenaltyResultSchema,
  instantPenaltySchema,
  pendingPenaltyEmployeeSchema,
  punctualityChampionsResultSchema,
  reviewInstantPenaltyExcuseResultSchema,
  submitInstantPenaltyExcuseResultSchema,
  submitInstantPenaltyReceiptResultSchema,
  triggerCheckResultSchema,
  type CancelInstantPenaltyResult,
  type ConfirmInstantPenaltyPaymentResult,
  type ExecutiveDailyDigest,
  type GenerateInstantPenaltyResult,
  type InstantPenalty,
  type PendingPenaltyEmployee,
  type PunctualityChampionsResult,
  type ReviewInstantPenaltyExcuseResult,
  type SubmitInstantPenaltyExcuseResult,
  type SubmitInstantPenaltyReceiptResult,
  type TriggerCheckResult,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export type {
  InstantPenalty,
  PendingPenaltyEmployee,
  ExecutiveDailyDigest,
  PunctualityChampionsResult,
  SubmitInstantPenaltyExcuseResult,
  ReviewInstantPenaltyExcuseResult,
  SubmitInstantPenaltyReceiptResult,
};

const INSTANT_PENALTIES_KEY = 'instant-penalties';
const PENDING_EMPLOYEES_KEY = 'instant-penalties-pending-employees';

// ─── أسماء الحالات بالعربية ──────────────────────────────────────────

export const INSTANT_PENALTY_STATUS_LABELS: Record<string, string> = {
  pending_payment: 'بانتظار الدفع',
  paid: 'مدفوعة',
  doubled: 'مضاعفة (500 ج.م)',
  suspended: 'معلّق عن العمل',
  cancelled: 'ملغاة',
};

export const INSTANT_PENALTY_ESCALATION_LABELS: Record<string, string> = {
  initial: 'أولية',
  doubled: 'مضاعفة',
  suspended: 'تعليق',
};

export const EXCUSE_STATUS_LABELS: Record<string, string> = {
  none: 'بدون عذر',
  submitted: 'عذر قيد المراجعة',
  approved: 'عذر مقبول (ملغاة)',
  rejected: 'عذر مرفوض',
};

export const PAYMENT_METHOD_LABELS: Record<string, string> = {
  cash: 'نقدي',
  instapay: 'إنستاباي (InstaPay)',
  vodafone_cash: 'فودافون كاش',
  bank_transfer: 'تحويل بنكي',
  wallet: 'محفظة إلكترونية',
};

// ─── فلاتر ────────────────────────────────────────────────────────────

export interface InstantPenaltiesFilter {
  employeeId?: string;
  status?: string;
  dateFrom?: string;
  dateTo?: string;
}

// ─── استعلام الغرامات ─────────────────────────────────────────────────

export function useInstantPenalties(filter: InstantPenaltiesFilter = {}) {
  const auth = useAuth();
  const { employeeId, status, dateFrom, dateTo } = filter;
  return useQuery({
    queryKey: [INSTANT_PENALTIES_KEY, auth.isMock, employeeId, status, dateFrom, dateTo],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<InstantPenalty[]> => {
      if (auth.isMock) return [];
      return instantPenaltySchema.array().parse(
        await rpc('get_instant_penalties', {
          p_employee_id: employeeId ?? null,
          p_status: status ?? null,
          p_date_from: dateFrom ?? null,
          p_date_to: dateTo ?? null,
        }),
      );
    },
  });
}

// ─── الموظفين المطالبين بالدفع ────────────────────────────────────────

export function usePendingPenaltyEmployees() {
  const auth = useAuth();
  return useQuery({
    queryKey: [PENDING_EMPLOYEES_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    refetchInterval: 60_000, // تحديث كل دقيقة
    queryFn: async (): Promise<PendingPenaltyEmployee[]> => {
      if (auth.isMock) return [];
      return pendingPenaltyEmployeeSchema.array().parse(await rpc('get_employees_with_pending_instant_penalties'));
    },
  });
}

// ─── إنشاء غرامة يدوياً ──────────────────────────────────────────────

export function useGenerateInstantPenalty() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { employeeId: string; workDate: string; lateMinutes: number }): Promise<GenerateInstantPenaltyResult> => {
      return generateInstantPenaltyResultSchema.parse(
        await rpc('generate_instant_penalty', {
          p_employee_id: args.employeeId,
          p_work_date: args.workDate,
          p_late_minutes: args.lateMinutes,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
    },
  });
}

// ─── تأكيد الدفع ─────────────────────────────────────────────────────

export function useConfirmInstantPenaltyPayment() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; notes?: string }): Promise<ConfirmInstantPenaltyPaymentResult> => {
      return confirmInstantPenaltyPaymentResultSchema.parse(
        await rpc('confirm_instant_penalty_payment', {
          p_penalty_id: args.penaltyId,
          p_notes: args.notes ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
      void queryClient.invalidateQueries({ queryKey: ['fellowship-fund-summary'] });
      void queryClient.invalidateQueries({ queryKey: ['fellowship-fund-transactions'] });
      void queryClient.invalidateQueries({ queryKey: ['fellowship-fund-breakdown'] });
      void queryClient.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}

// ─── إلغاء غرامة ────────────────────────────────────────────────────

export function useCancelInstantPenalty() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; reason: string }): Promise<CancelInstantPenaltyResult> => {
      return cancelInstantPenaltyResultSchema.parse(
        await rpc('cancel_instant_penalty', {
          p_penalty_id: args.penaltyId,
          p_reason: args.reason,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
      void queryClient.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}

// ─── رفع التعليق بدون دفع (full-access فقط) ─────────────────────────

export function useLiftInstantPenaltySuspension() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; notes?: string }) => {
      return confirmInstantPenaltyPaymentResultSchema.parse(
        await rpc('lift_instant_penalty_suspension', {
          p_penalty_id: args.penaltyId,
          p_notes: args.notes ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
      void queryClient.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}

// ─── فحص وتطبيق الخصومات التلقائية الآن ─────────────────────────────

export function useTriggerCheckPenaltiesNow() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (): Promise<TriggerCheckResult> => {
      return triggerCheckResultSchema.parse(await rpc('trigger_check_instant_penalties_now'));
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
      void queryClient.invalidateQueries({ queryKey: ['fellowship-fund-summary'] });
      void queryClient.invalidateQueries({ queryKey: ['fellowship-fund-transactions'] });
    },
  });
}

// ─── تقديم عذر على الغرامة ──────────────────────────────────────────

export function useSubmitInstantPenaltyExcuse() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; reason: string; attachmentUrl?: string }): Promise<SubmitInstantPenaltyExcuseResult> => {
      return submitInstantPenaltyExcuseResultSchema.parse(
        await rpc('submit_instant_penalty_excuse', {
          p_penalty_id: args.penaltyId,
          p_reason: args.reason,
          p_attachment_url: args.attachmentUrl ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
    },
  });
}

// ─── مراجعة العذر (قبول / رفض) من قبل HR ──────────────────────────

export function useReviewInstantPenaltyExcuse() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; action: 'approved' | 'rejected'; notes?: string }): Promise<ReviewInstantPenaltyExcuseResult> => {
      return reviewInstantPenaltyExcuseResultSchema.parse(
        await rpc('review_instant_penalty_excuse', {
          p_penalty_id: args.penaltyId,
          p_action: args.action,
          p_notes: args.notes ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
      void queryClient.invalidateQueries({ queryKey: ['employees'] });
    },
  });
}

// ─── تسجيل إيصال دفع إلكتروني (InstaPay / فودافون كاش) ──────────────

export function useSubmitInstantPenaltyReceipt() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: {
      penaltyId: string;
      paymentMethod: 'instapay' | 'vodafone_cash' | 'cash' | 'bank_transfer' | 'wallet';
      receiptUrl?: string;
      referenceNumber?: string;
    }): Promise<SubmitInstantPenaltyReceiptResult> => {
      return submitInstantPenaltyReceiptResultSchema.parse(
        await rpc('submit_instant_penalty_receipt', {
          p_penalty_id: args.penaltyId,
          p_payment_method: args.paymentMethod,
          p_receipt_url: args.receiptUrl ?? null,
          p_reference_number: args.referenceNumber ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTANT_PENALTIES_KEY] });
      void queryClient.invalidateQueries({ queryKey: [PENDING_EMPLOYEES_KEY] });
    },
  });
}

// ─── الموجز اليومي للواتساب للإدارة العليا ───────────────────────────

export function useExecutiveDailyDigest(date?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['executive-daily-digest', auth.isMock, date],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<ExecutiveDailyDigest> => {
      if (auth.isMock) {
        return {
          date: date ?? new Date().toISOString().slice(0, 10),
          totalActive: 0,
          present: 0,
          fieldMissions: 0,
          leaves: 0,
          absent: 0,
          penaltiesIssued: 0,
          penaltiesIssuedAmount: 0,
          penaltiesPaid: 0,
          penaltiesPaidAmount: 0,
          fundBalance: 0,
          digestText: 'موجز تجريبي...',
        };
      }
      return executiveDailyDigestSchema.parse(
        await rpc('generate_executive_daily_digest', {
          p_date: date ?? null,
        }),
      );
    },
  });
}

// ─── لوحة شرف أبطال الانضباط الشهري ─────────────────────────────────

export function usePunctualityChampions(month?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: ['punctuality-champions', auth.isMock, month],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<PunctualityChampionsResult> => {
      if (auth.isMock) {
        return {
          month: month ?? new Date().toISOString().slice(0, 7),
          startDate: '',
          endDate: '',
          champions: [],
        };
      }
      return punctualityChampionsResultSchema.parse(
        await rpc('get_punctuality_champions', {
          p_month: month ?? null,
        }),
      );
    },
  });
}

export function useBulkConfirmPenaltyPayments() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ penaltyIds, notes }: { penaltyIds: string[]; notes?: string }) => {
      return await rpc<number>('bulk_confirm_penalty_payments', {
        p_penalty_ids: penaltyIds,
        p_notes: notes || null,
      });
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['instantPenalties'] });
    },
  });
}

export function useBulkCancelPenalties() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: async ({ penaltyIds, reason }: { penaltyIds: string[]; reason: string }) => {
      return await rpc<number>('bulk_cancel_penalties', {
        p_penalty_ids: penaltyIds,
        p_reason: reason,
      });
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['instantPenalties'] });
    },
  });
}
