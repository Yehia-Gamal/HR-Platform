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
  annual:  'إجازة سنوية',
  casual:  'إجازة عارضة',
  sick:    'إجازة مرضية',
  unpaid:  'إجازة بدون أجر',
};

export const LEAVE_TYPE_COLORS: Record<string, string> = {
  annual:  'bg-blue-100 text-blue-800 dark:bg-blue-900/40 dark:text-blue-300',
  casual:  'bg-purple-100 text-purple-800 dark:bg-purple-900/40 dark:text-purple-300',
  sick:    'bg-orange-100 text-orange-800 dark:bg-orange-900/40 dark:text-orange-300',
  unpaid:  'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-300',
};
