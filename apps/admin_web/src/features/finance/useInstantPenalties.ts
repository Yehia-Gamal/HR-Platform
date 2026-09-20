import {
  cancelInstantPenaltyResultSchema,
  confirmInstantPenaltyPaymentResultSchema,
  generateInstantPenaltyResultSchema,
  instantPenaltySchema,
  pendingPenaltyEmployeeSchema,
  triggerCheckResultSchema,
  type CancelInstantPenaltyResult,
  type ConfirmInstantPenaltyPaymentResult,
  type GenerateInstantPenaltyResult,
  type InstantPenalty,
  type PendingPenaltyEmployee,
  type TriggerCheckResult,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export type { InstantPenalty, PendingPenaltyEmployee };

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
