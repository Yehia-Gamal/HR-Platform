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
]);
export type RequestType = z.infer<typeof requestTypeSchema>;

/** عدد أنواع الطلبات الرسمية — V17 §8 + 0325. */
export const REQUEST_TYPE_COUNT = 7;

/** تسميات الأنواع بالعربية. */
export const REQUEST_TYPE_LABELS: Record<RequestType, string> = {
  leave: 'إجازة',
  mission: 'مأمورية',
  convoy: 'قافلة',
  fundraising: 'فاندي',
  late_permit: 'إذن حضور',
  early_permit: 'إذن انصراف',
  attendance_correction: 'تصحيح حضور',
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

// ─── مدخلات إنشاء طلب ────────────────────────────────────────────────────────

export const createRequestInputSchema = z.object({
  type: requestTypeSchema,
  /** سبب الطلب (3–300 حرف — V17 §1.3) */
  reason: z.string().min(3).max(300),
  /** تاريخ البداية */
  startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  /** تاريخ النهاية (اختياري — طلبات اليوم الواحد) */
  endDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
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
