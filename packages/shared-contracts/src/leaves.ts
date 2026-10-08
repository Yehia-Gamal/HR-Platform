import { z } from 'zod';
import { leaveTypeCodeSchema } from './operations.js';
export type { LeaveTypeCode } from './operations.js';
export { leaveTypeCodeSchema };

export const leaveStatusSchema = z.enum([
  'draft', 'pending', 'approved', 'rejected', 'returned',
  'cancelled', 'withdrawn', 'expired', 'escalated',
]);
export type LeaveStatus = z.infer<typeof leaveStatusSchema>;

export const leaveAdminRowSchema = z.object({
  requestId:     z.string().uuid(),
  requestNumber: z.number(),
  status:        leaveStatusSchema,
  createdAt:     z.string(),
  employeeId:    z.string().uuid(),
  employeeCode:  z.string().nullable(),
  employeeName:  z.string(),
  leaveTypeId:   z.string().uuid(),
  leaveTypeCode: leaveTypeCodeSchema,
  leaveTypeName: z.string(),
  isPaid:        z.boolean(),
  startDate:     z.string(),
  endDate:       z.string(),
  daysCount:     z.number(),
  hoursCount:    z.number().nullable(),
  durationUnit:  z.enum(['day', 'hour']).default('day'),
  isHalfDay:     z.boolean().default(false),
  reason:        z.string().nullable(),
  handoverNotes: z.string().nullable(),
  attachmentUrl: z.string().nullable(),
});
export type LeaveAdminRow = z.infer<typeof leaveAdminRowSchema>;

export const leaveAdminResponseSchema = z.object({
  total: z.number(),
  rows:  leaveAdminRowSchema.array(),
});
export type LeaveAdminResponse = z.infer<typeof leaveAdminResponseSchema>;

export const LEAVE_TYPE_LABELS: Record<string, string> = {
  annual:           'إجازة سنوية',
  casual:           'إجازة عارضة',
  sick:             'إجازة مرضية',
  unpaid:           'إجازة بدون أجر',
  weekly_rest_comp: 'بدل راحة أسبوعية',
};

export const LEAVE_TYPE_COLORS: Record<string, string> = {
  annual:           'bg-blue-500/15 text-blue-700 dark:text-blue-300 border border-blue-500/30',
  casual:           'bg-purple-500/15 text-purple-700 dark:text-purple-300 border border-purple-500/30',
  sick:             'bg-amber-500/15 text-amber-700 dark:text-amber-300 border border-amber-500/30',
  unpaid:           'bg-gray-500/15 text-gray-700 dark:text-gray-300 border border-gray-500/30',
  weekly_rest_comp: 'bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 border border-emerald-500/30',
};
