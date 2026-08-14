import {
  addEmployeePenaltySchema,
  auditTrailPageSchema,
  employeePenaltySchema,
  generateInstapayBatchSchema,
  instapayBatchSchema,
  systemSettingSchema,
  type AddEmployeePenaltyResult,
  type AuditTrailPage,
  type AuditTrailItem,
  type EmployeePenalty,
  type GenerateInstapayBatchResult,
  type InstapayBatch,
  type SystemSetting,
} from '@ahla/shared-contracts';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { rpc } from '../../core/rpc';
import { useAuth } from '../auth/AuthProvider';

export type { AuditTrailItem, EmployeePenalty, InstapayBatch, SystemSetting };

const PENALTIES_KEY = 'employee-penalties';
const INSTAPAY_KEY = 'instapay-batches';
const AUDIT_KEY = 'audit-trail';
const SETTINGS_KEY = 'system-settings';

export interface PenaltiesFilter {
  employeeId?: string;
  status?: string;
}

export function useEmployeePenalties(filter: PenaltiesFilter = {}) {
  const auth = useAuth();
  const { employeeId, status } = filter;
  return useQuery({
    queryKey: [PENALTIES_KEY, auth.isMock, employeeId, status],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<EmployeePenalty[]> => {
      if (auth.isMock) return [];
      return employeePenaltySchema.array().parse(
        await rpc('get_employee_penalties', {
          p_employee_id: employeeId ?? null,
          p_status: status ?? null,
        }),
      );
    },
  });
}

export function useAddEmployeePenalty() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: {
      employeeId: string;
      penaltyType: string;
      amount: number;
      reason: string;
      evidenceRef?: string;
    }): Promise<AddEmployeePenaltyResult> => {
      return addEmployeePenaltySchema.parse(
        await rpc('add_employee_penalty', {
          p_employee_id: args.employeeId,
          p_penalty_type: args.penaltyType,
          p_amount: args.amount,
          p_reason: args.reason,
          p_evidence_ref: args.evidenceRef ?? null,
        }),
      );
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [PENALTIES_KEY] });
    },
  });
}

export function useWaiveEmployeePenalty() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (args: { penaltyId: string; reason: string }) => {
      return rpc('waive_employee_penalty', {
        p_penalty_id: args.penaltyId,
        p_reason: args.reason,
      });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [PENALTIES_KEY] });
    },
  });
}

export function useInstapayBatches(payrollRunId?: string) {
  const auth = useAuth();
  return useQuery({
    queryKey: [INSTAPAY_KEY, auth.isMock, payrollRunId],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<InstapayBatch[]> => {
      if (auth.isMock) return [];
      return instapayBatchSchema.array().parse(
        await rpc('list_instapay_batches', {
          p_payroll_run_id: payrollRunId ?? null,
        }),
      );
    },
  });
}

export function useGenerateInstapayBatch() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (payrollRunId: string): Promise<GenerateInstapayBatchResult> => {
      return generateInstapayBatchSchema.parse(await rpc('generate_instapay_batch', { p_payroll_run_id: payrollRunId }));
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [INSTAPAY_KEY] });
    },
  });
}

export interface AuditTrailFilter {
  category?: string;
  eventType?: string;
  severity?: string;
  limit?: number;
}

export function useAuditTrail(filter: AuditTrailFilter = {}) {
  const auth = useAuth();
  const { category, eventType, severity, limit = 100 } = filter;
  return useQuery({
    queryKey: [AUDIT_KEY, auth.isMock, category, eventType, severity, limit],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<AuditTrailPage> => {
      if (auth.isMock) {
        return { total: 0, items: [] };
      }
      return auditTrailPageSchema.parse(
        await rpc('get_audit_trail_page', {
          p_category: category ?? null,
          p_event_type: eventType ?? null,
          p_severity: severity ?? null,
          p_limit: limit,
        }),
      );
    },
  });
}

export function useEditableSystemSettings() {
  const auth = useAuth();
  return useQuery({
    queryKey: [SETTINGS_KEY, auth.isMock],
    enabled: auth.status === 'authenticated',
    queryFn: async (): Promise<SystemSetting[]> => {
      if (auth.isMock) return [];
      return systemSettingSchema.array().parse(await rpc('get_editable_system_settings'));
    },
  });
}

export function useUpdateSystemSettings() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (updates: Record<string, unknown>) => {
      return rpc('update_system_settings', { p_updates: updates });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: [SETTINGS_KEY] });
    },
  });
}

export const PENALTY_TYPE_LABELS: Record<string, string> = {
  attendance: 'حضور وانصراف',
  late: 'تأخير',
  absence: 'غياب',
  misconduct: 'سوء سلوك',
  policy: 'مخالفة سياسة',
  damage: 'إتلاف عهدة',
  client_complaint: 'شكوى عميل',
  other: 'أخرى',
};

export const PENALTY_STATUS_LABELS: Record<string, string> = {
  issued: 'صادرة',
  deducted: 'مخصومة',
  waived: 'مسقطة',
  cancelled: 'ملغاة',
};

export const INSTAPAY_STATUS_LABELS: Record<string, string> = {
  generated: 'مولدة',
  sent: 'مرسلة',
  partially_paid: 'مدفوعة جزئياً',
  paid: 'مدفوعة',
  failed: 'فاشلة',
};

export const AUDIT_SEVERITY_LABELS: Record<string, string> = {
  info: 'معلومة',
  warning: 'تحذير',
  error: 'خطأ',
  critical: 'حرج',
};

export const AUDIT_CATEGORY_LABELS: Record<string, string> = {
  system: 'النظام',
  security: 'أمن',
  financial: 'مالية',
  hr: 'موارد بشرية',
  data: 'بيانات',
};
