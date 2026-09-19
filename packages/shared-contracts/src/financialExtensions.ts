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

// ─── غرامات فورية للتأخير ─────────────────────────────────────────────

/** غرامة فورية للتأخير */
export const instantPenaltySchema = z
  .object({
    id: uuid,
    employeeId: uuid,
    employeeName: z.string().nullable(),
    employeeCode: z.string().nullable(),
    departmentName: z.string().nullable(),
    workDate: z.string(),
    lateMinutes: z.number().int(),
    originalAmount: z.number(),
    currentAmount: z.number(),
    currency: z.string(),
    status: z.enum(['pending_payment', 'paid', 'doubled', 'suspended', 'cancelled']),
    escalationLevel: z.enum(['initial', 'doubled', 'suspended']),
    paidAt: isoDate,
    confirmedBy: uuid.nullable(),
    suspendedAt: isoDate,
    suspensionLiftedAt: isoDate,
    notes: z.string().nullable(),
    createdAt: isoDate,
  })
  .strict();
export type InstantPenalty = z.infer<typeof instantPenaltySchema>;

/** موظف مطالب بدفع غرامة فورية */
export const pendingPenaltyEmployeeSchema = z
  .object({
    employeeId: uuid,
    employeeName: z.string().nullable(),
    employeeCode: z.string().nullable(),
    departmentName: z.string().nullable(),
    pendingCount: z.number().int(),
    totalAmount: z.number(),
    isSuspended: z.boolean(),
    latestDate: z.string(),
  })
  .strict();
export type PendingPenaltyEmployee = z.infer<typeof pendingPenaltyEmployeeSchema>;

/** نتيجة إنشاء غرامة فورية */
export const generateInstantPenaltyResultSchema = z.object({
  id: uuid.nullable().optional(),
  alreadyExists: z.boolean().optional(),
  isGracePeriod: z.boolean().optional(),
  amount: z.number().optional(),
  message: z.string().optional(),
  employeeId: uuid.optional(),
  workDate: z.string().optional(),
  lateMinutes: z.number().int().optional(),
  originalAmount: z.number().optional(),
  currentAmount: z.number().optional(),
  status: z.string().optional(),
});
export type GenerateInstantPenaltyResult = z.infer<typeof generateInstantPenaltyResultSchema>;

/** نتيجة تأكيد الدفع */
export const confirmInstantPenaltyPaymentResultSchema = z.object({
  id: uuid,
  status: z.string(),
  paidAt: isoDate,
  currentAmount: z.number(),
  wasSuspended: z.boolean(),
});
export type ConfirmInstantPenaltyPaymentResult = z.infer<typeof confirmInstantPenaltyPaymentResultSchema>;

/** نتيجة إلغاء غرامة */
export const cancelInstantPenaltyResultSchema = z.object({
  id: uuid,
  status: z.string(),
  currentAmount: z.number(),
  wasSuspended: z.boolean(),
});
export type CancelInstantPenaltyResult = z.infer<typeof cancelInstantPenaltyResultSchema>;

/** تفنيط مبالغ صندوق الزمالة حسب الفئة */
export const fellowshipFundCategoryBreakdownSchema = z.object({
  category: z.string(),
  type: z.enum(['inflow', 'outflow']),
  totalAmount: z.number(),
  count: z.number().int(),
});
export type FellowshipFundCategoryBreakdown = z.infer<typeof fellowshipFundCategoryBreakdownSchema>;

/** حركة داخل صندوق الزمالة والتكافل */
export const fellowshipFundTransactionSchema = z.object({
  id: uuid,
  transactionType: z.enum(['inflow', 'outflow']),
  amount: z.number(),
  sourceType: z.string(),
  instantPenaltyId: uuid.nullable().optional(),
  employeeId: uuid.nullable().optional(),
  employeeName: z.string(),
  performedBy: uuid.nullable().optional(),
  performerName: z.string().nullable().optional(),
  category: z.string(),
  reason: z.string(),
  balanceAfter: z.number(),
  notes: z.string().nullable().optional(),
  createdAt: z.string(),
});
export type FellowshipFundTransaction = z.infer<typeof fellowshipFundTransactionSchema>;

/** ملخص صندوق الزمالة والتكافل */
export const fellowshipFundSummarySchema = z.object({
  currentBalance: z.number(),
  totalInflows: z.number(),
  totalOutflows: z.number(),
  inflowsCount: z.number().int(),
  outflowsCount: z.number().int(),
  monthlyInflows: z.number(),
  monthlyOutflows: z.number(),
  categoryBreakdown: z.array(fellowshipFundCategoryBreakdownSchema),
  recentTransactions: z.array(fellowshipFundTransactionSchema),
});
export type FellowshipFundSummary = z.infer<typeof fellowshipFundSummarySchema>;

/** مدخلات سحب مبلغ من صندوق الزمالة */
export const withdrawFellowshipFundInputSchema = z.object({
  amount: z.number().positive('مبلغ السحب يجب أن يكون أكبر من صفر'),
  category: z.string().min(1, 'يرجى اختيار تصنيف السحب'),
  reason: z.string().min(3, 'يرجى توضيح سبب السحب بالتفصيل'),
  beneficiaryEmployeeId: uuid.nullable().optional(),
  notes: z.string().nullable().optional(),
});
export type WithdrawFellowshipFundInput = z.infer<typeof withdrawFellowshipFundInputSchema>;

/** نتيجة سحب مبلغ من صندوق الزمالة */
export const withdrawFellowshipFundResultSchema = z.object({
  success: z.boolean(),
  transactionId: uuid,
  amount: z.number(),
  category: z.string(),
  reason: z.string(),
  balanceAfter: z.number(),
  message: z.string(),
});
export type WithdrawFellowshipFundResult = z.infer<typeof withdrawFellowshipFundResultSchema>;

/** نتيجة تأكيد سداد غرامة وإيداعها في الصندوق */
export const confirmPenaltyToFundResultSchema = z.object({
  success: z.boolean(),
  penaltyId: uuid,
  employeeId: uuid,
  employeeName: z.string().nullable().optional(),
  amount: z.number(),
  fundBalanceAfter: z.number(),
  wasSuspended: z.boolean(),
  transactionId: uuid.optional(),
  message: z.string(),
});
export type ConfirmPenaltyToFundResult = z.infer<typeof confirmPenaltyToFundResultSchema>;
