import { z } from 'zod';

const uuid = z.string().uuid();
const isoDate = z.string().datetime({ offset: true }).nullable();

/** مسير رواتب دوري */
export const payrollRunSchema = z
  .object({
    id: uuid,
    periodMonth: z.string().regex(/^\d{4}-\d{2}$/, 'صيغة الشهر غير صالحة (YYYY-MM)'),
    legalEntityId: uuid.nullable().optional(),
    status: z.enum(['draft', 'calculating', 'approved', 'paid', 'cancelled']),
    totalGross: z.number().nonnegative(),
    totalNet: z.number().nonnegative(),
    totalDeductions: z.number().nonnegative(),
    employeeCount: z.number().int().nonnegative(),
    approvedBy: uuid.nullable().optional(),
    approvedAt: isoDate.optional(),
    createdAt: z.string().datetime().optional(),
  })
  .strict();
export type PayrollRun = z.infer<typeof payrollRunSchema>;

/** مخالفة مالية على موظف تُخصم من راتبه */
export const employeePenaltySchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    employeeCode: z.string().nullable(),
    employeeName: z.string().nullable(),
    departmentName: z.string().nullable(),
    penaltyType: z.string(),
    amount: z.number(),
    currency: z.string(),
    reason: z.string(),
    evidenceRef: z.string().nullable(),
    status: z.enum(['issued', 'deducted', 'waived', 'cancelled']),
    payrollRunId: uuid.nullable(),
    issuedBy: uuid.nullable(),
    issuedAt: isoDate,
    waivedBy: uuid.nullable(),
    waivedAt: isoDate,
    waiveReason: z.string().nullable(),
  })
  .strict();
export type EmployeePenalty = z.infer<typeof employeePenaltySchema>;

export const addEmployeePenaltySchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    amount: z.number(),
    penaltyType: z.string(),
    status: z.string(),
    issuedAt: isoDate,
  })
  .strict();
export type AddEmployeePenaltyResult = z.infer<typeof addEmployeePenaltySchema>;

/** عنصر داخل دفعة InstaPay */
export const instapayItemSchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    employeeName: z.string().nullable(),
    mobileE164: z.string().nullable(),
    amount: z.number(),
    status: z.enum(['pending', 'paid', 'failed']),
    paidAt: isoDate,
  })
  .strict();

/** دفعة InstaPay لصرف الرواتب */
export const instapayBatchSchema = z
  .object({
    id: uuid,
    payrollRunId: uuid,
    periodMonth: z.string().nullable(),
    batchReference: z.string().nullable(),
    totalAmount: z.number(),
    itemCount: z.number(),
    status: z.enum(['generated', 'sent', 'partially_paid', 'paid', 'failed']),
    sentAt: isoDate,
    completedAt: isoDate,
    createdAt: isoDate,
    items: z.array(instapayItemSchema),
  })
  .strict();
export type InstapayBatch = z.infer<typeof instapayBatchSchema>;

export const generateInstapayBatchSchema = z
  .object({
    id: uuid,
    reference: z.string(),
    totalAmount: z.number(),
    itemCount: z.number(),
    status: z.string(),
  })
  .strict();
export type GenerateInstapayBatchResult = z.infer<typeof generateInstapayBatchSchema>;

/** عنصر سجل تدقيق */
export const auditTrailItemSchema = z
  .object({
    id: uuid,
    eventType: z.string(),
    category: z.string().nullable(),
    severity: z.string().nullable(),
    actorUserId: uuid.nullable(),
    actorEmployeeId: uuid.nullable(),
    actorName: z.string().nullable(),
    targetTable: z.string().nullable(),
    targetId: uuid.nullable(),
    summaryAr: z.string().nullable(),
    metadata: z.record(z.string(), z.unknown()).nullable(),
    occurredAt: isoDate,
  })
  .strict();
export type AuditTrailItem = z.infer<typeof auditTrailItemSchema>;

export const auditTrailPageSchema = z
  .object({
    total: z.number(),
    items: z.array(auditTrailItemSchema),
  })
  .strict();
export type AuditTrailPage = z.infer<typeof auditTrailPageSchema>;

/** إعداد نظام قابل للتعديل */
export const systemSettingSchema = z
  .object({
    key: z.string(),
    value: z.unknown(),
    valueType: z.string(),
    groupName: z.string().nullable(),
    labelAr: z.string().nullable(),
    description: z.string().nullable(),
    isSecret: z.boolean(),
    isEditable: z.boolean(),
  })
  .strict();
export type SystemSetting = z.infer<typeof systemSettingSchema>;
