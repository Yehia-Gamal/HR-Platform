import { z } from 'zod';

// عقود أنواع الطلبات — V17 §8 + 0325 (fundraising).
// 7 أنواع طلبات رسمية بالضبط.

// ─── أنواع الطلبات السبعة ─────────────────────────────────────────────────────

export const requestTypeSchema = z.enum([
  'leave',
  'mission',
  'convoy',
  'fundraising',
  'late_permit',
  'early_permit',
  'attendance_correction',
  'shift_change',
]);
export type RequestType = z.infer<typeof requestTypeSchema>;

/** عدد أنواع الطلبات الرسمية — V17 §8 + 0325 + 0632. */
export const REQUEST_TYPE_COUNT = 8;

/** تسميات الأنواع بالعربية. */
export const REQUEST_TYPE_LABELS: Record<RequestType, string> = {
  leave: 'إجازة',
  mission: 'مأمورية',
  convoy: 'قافلة',
  fundraising: 'فاندي',
  late_permit: 'إذن حضور',
  early_permit: 'إذن انصراف',
  attendance_correction: 'تصحيح حضور',
  shift_change: 'تغيير فترة العمل',
};

// ─── حالات الطلب ─────────────────────────────────────────────────────────────

export const requestStatusSchema = z.enum([
  'draft',
  'sent',
  'pending_direct_manager',
  'needs_completion',
  'escalated',
  'approved',
  'rejected',
  'returned',
  'cancelled',
  'cancelled_by_employee',
  'cancel_requested',
  'cancelled_after_approval',
  'withdrawn',
  'expired',
  'closed',
]);
export type RequestStatus = z.infer<typeof requestStatusSchema>;

/** تسميات حالات الطلب بالعربية — V23 §8. */
export const REQUEST_STATUS_LABELS: Record<RequestStatus, string> = {
  draft: 'مسودة',
  sent: 'مرسل',
  pending_direct_manager: 'بانتظار المدير المباشر',
  needs_completion: 'يحتاج استكمال',
  escalated: 'مصعّد',
  approved: 'معتمد',
  rejected: 'مرفوض',
  returned: 'معاد',
  cancelled: 'ملغى',
  cancelled_by_employee: 'ملغى بواسطة الموظف',
  cancel_requested: 'طلب إلغاء',
  cancelled_after_approval: 'ملغى بعد الاعتماد',
  withdrawn: 'مسحوب',
  expired: 'منتهي',
  closed: 'مغلق',
};

export interface RequestStatusDisplay {
  label: string;
  color: string;
  bgLight: string;
  tone: 'neutral' | 'info' | 'success' | 'warning' | 'danger' | 'violet';
  badgeClass: string;
}

export const REQUEST_STATUS_DISPLAY_MAP: Record<string, RequestStatusDisplay> = {
  approved: {
    label: 'معتمد',
    color: '#0F9F6E',
    bgLight: '#ecfdf5',
    tone: 'success',
    badgeClass: 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20',
  },
  rejected: {
    label: 'مرفوض',
    color: '#DC3D4B',
    bgLight: '#fef2f2',
    tone: 'danger',
    badgeClass: 'bg-red-500/10 text-red-600 dark:text-red-400 border border-red-500/20',
  },
  pending: {
    label: 'قيد المراجعة',
    color: '#008CB3',
    bgLight: '#eff6ff',
    tone: 'info',
    badgeClass: 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20',
  },
  pending_direct_manager: {
    label: 'بانتظار المدير المباشر',
    color: '#008CB3',
    bgLight: '#eff6ff',
    tone: 'info',
    badgeClass: 'bg-blue-500/10 text-blue-600 dark:text-blue-400 border border-blue-500/20',
  },
  escalated: {
    label: 'مصعّد',
    color: '#D98508',
    bgLight: '#fffbeb',
    tone: 'warning',
    badgeClass: 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border border-amber-500/20',
  },
  returned: {
    label: 'معاد للتعديل',
    color: '#C2410C',
    bgLight: '#fff7ed',
    tone: 'warning',
    badgeClass: 'bg-orange-500/10 text-orange-600 dark:text-orange-400 border border-orange-500/20',
  },
  cancelled: {
    label: 'ملغى',
    color: '#64748B',
    bgLight: '#f8fafc',
    tone: 'neutral',
    badgeClass: 'bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20',
  },
  withdrawn: {
    label: 'مسحوب',
    color: '#64748B',
    bgLight: '#f8fafc',
    tone: 'neutral',
    badgeClass: 'bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20',
  },
  expired: {
    label: 'منتهي',
    color: '#64748B',
    bgLight: '#f8fafc',
    tone: 'neutral',
    badgeClass: 'bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20',
  },
  closed: {
    label: 'مغلق',
    color: '#475569',
    bgLight: '#f1f5f9',
    tone: 'neutral',
    badgeClass: 'bg-slate-500/10 text-slate-700 dark:text-slate-300 border border-slate-500/20',
  },
  draft: {
    label: 'مسودة',
    color: '#94A3B8',
    bgLight: '#f8fafc',
    tone: 'neutral',
    badgeClass: 'bg-slate-500/10 text-slate-500 dark:text-slate-400 border border-slate-500/20',
  },
};

export function getRequestStatusDisplay(status: string): RequestStatusDisplay {
  return (
    REQUEST_STATUS_DISPLAY_MAP[status] ?? {
      label: status,
      color: '#64748B',
      bgLight: '#f8fafc',
      tone: 'neutral',
      badgeClass: 'bg-slate-500/10 text-slate-600 dark:text-slate-400 border border-slate-500/20',
    }
  );
}

// ─── مدخلات إنشاء طلب ────────────────────────────────────────────────────────

export const createRequestInputSchema = z.object({
  type: requestTypeSchema,
  /** سبب الطلب (3–300 حرف — V17 §1.3) */
  reason: z.string().min(3).max(300),
  /** تاريخ البداية */
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  /** تاريخ النهاية (اختياري — طلبات اليوم الواحد) */
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  /** وقت بداية المأمورية/التكليف (اختياري — HH:mm بنظام 24 ساعة) */
  startTime: z
    .string()
    .regex(/^([01]\d|2[0-3]):[0-5]\d$/)
    .optional(),
  /** وقت نهاية المأمورية/التكليف (اختياري — HH:mm بنظام 24 ساعة) */
  endTime: z
    .string()
    .regex(/^([01]\d|2[0-3]):[0-5]\d$/)
    .optional(),
  /** معرّفات المرفقات */
  attachmentIds: z.array(z.string().uuid()).default([]),
  /** ملاحظات إضافية */
  notes: z.string().max(500).optional(),
});
export type CreateRequestInput = z.infer<typeof createRequestInputSchema>;

// ─── تنفيذ المأمورية (0318) ─────────────────────────────────────────────────

/** سجل تنفيذ المأمورية/القافلة — يطابق مهمة mission_executions. */
export const missionExecutionSchema = z
  .object({
    id: z.string().uuid(),
    status: z.enum(['not_started', 'in_progress', 'completed']),
    startedAt: z.string().nullable(),
    endedAt: z.string().nullable(),
    actualMinutes: z.number().nullable(),
    report: z.string().nullable(),
    outcome: z.string().nullable(),
  })
  .nullable();
export type MissionExecution = z.infer<typeof missionExecutionSchema>;

/** حالات تنفيذ المأمورية بالعربية. */
export const MISSION_EXECUTION_STATUS_LABELS: Record<string, string> = {
  not_started: 'لم تبدأ',
  in_progress: 'قيد التنفيذ',
  completed: 'منجزة',
};
