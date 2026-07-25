import { z } from 'zod';

// عقود أنواع الطلبات — V17 §8.
// 6 أنواع طلبات رسمية بالضبط. لا أنواع إضافية.

// ─── أنواع الطلبات الستة ──────────────────────────────────────────────────────

export const requestTypeSchema = z.enum([
  'leave',
  'mission',
  'convoy',
  'late_permit',
  'early_permit',
  'attendance_correction',
]);
export type RequestType = z.infer<typeof requestTypeSchema>;

/** عدد أنواع الطلبات الرسمية — V17 §8. */
export const REQUEST_TYPE_COUNT = 6;

/** تسميات الأنواع بالعربية. */
export const REQUEST_TYPE_LABELS: Record<RequestType, string> = {
  leave: 'إجازة',
  mission: 'مأمورية',
  convoy: 'قافلة / فاندي',
  late_permit: 'إذن تأخير',
  early_permit: 'إذن انصراف مبكر',
  attendance_correction: 'تصحيح حضور',
};

// ─── حالات الطلب ─────────────────────────────────────────────────────────────

export const requestStatusSchema = z.enum([
  'draft',
  'pending',
  'approved',
  'rejected',
  'returned',
  'cancelled',
  'withdrawn',
  'expired',
  'escalated',
]);
export type RequestStatus = z.infer<typeof requestStatusSchema>;

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
