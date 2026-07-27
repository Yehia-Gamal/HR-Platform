import { z } from 'zod';

// عقود إجراءات لجنة المنازعات — V17 §14.
// الإجراء الإداري: اقتراح → قرار تنفيذي → تنفيذ → توثيق.

// ─── حالات القضية ─────────────────────────────────────────────────────────────

export const disputeCaseStatusSchema = z.enum([
  'open',
  'investigation',
  'hearing',
  'deliberation',
  'decision_pending',
  'decided',
  'appealed',
  'appeal_decided',
  'executed',
  'resolved_friendly',
  'closed',
  'archived',
]);
export type DisputeCaseStatus = z.infer<typeof disputeCaseStatusSchema>;

// ─── أنواع الإجراءات الإدارية ─────────────────────────────────────────────────

export const adminActionTypeSchema = z.enum([
  'verbal_warning',
  'written_warning',
  'final_warning',
  'salary_deduction',
  'suspension',
  'demotion',
  'termination',
  'transfer',
  'training_requirement',
  'no_action',
]);
export type AdminActionType = z.infer<typeof adminActionTypeSchema>;

// ─── قرار المدير التنفيذي ─────────────────────────────────────────────────────

export const executiveDecisionSchema = z.enum([
  'approved',
  'modified',
  'rejected',
  'deferred',
]);
export type ExecutiveDecision = z.infer<typeof executiveDecisionSchema>;

// ─── مخطط الإجراء الإداري الكامل ──────────────────────────────────────────────

export const disputeAdminActionSchema = z.object({
  /** الإجراء الإداري المقترح من لجنة المنازعات */
  proposedAction: adminActionTypeSchema,
  proposedActionDetail: z.string().min(3).max(2000).nullable(),
  proposedAt: z.string().datetime().nullable(),
  proposedBy: z.string().uuid().nullable(),

  /** قرار المدير التنفيذي */
  executiveDecision: executiveDecisionSchema.nullable(),
  executiveDecisionReason: z.string().min(3).max(2000).nullable(),
  executiveDecisionAt: z.string().datetime().nullable(),
  executiveDecisionBy: z.string().uuid().nullable(),

  /** الإجراء المعتمد (قد يختلف عن المقترح إذا عدّله التنفيذي) */
  approvedAction: adminActionTypeSchema.nullable(),
  approvedActionDetail: z.string().max(2000).nullable(),

  /** التنفيذ */
  executedAt: z.string().datetime().nullable(),
  executedBy: z.string().uuid().nullable(),
  executionNotes: z.string().max(2000).nullable(),
});
export type DisputeAdminAction = z.infer<typeof disputeAdminActionSchema>;

// ─── مدخلات اقتراح الإجراء ───────────────────────────────────────────────────

export const proposeAdminActionInputSchema = z.object({
  caseId: z.string().uuid(),
  proposedAction: adminActionTypeSchema,
  detail: z.string().min(3).max(2000),
});
export type ProposeAdminActionInput = z.infer<typeof proposeAdminActionInputSchema>;

// ─── مدخلات قرار المدير التنفيذي ──────────────────────────────────────────────

export const executiveDecisionInputSchema = z.object({
  caseId: z.string().uuid(),
  decision: executiveDecisionSchema,
  reason: z.string().min(3).max(2000),
  /** إجراء معدّل (مطلوب إذا كان القرار 'modified') */
  modifiedAction: adminActionTypeSchema.optional(),
  modifiedActionDetail: z.string().max(2000).optional(),
});
export type ExecutiveDecisionInput = z.infer<typeof executiveDecisionInputSchema>;

// ─── مدخلات تأكيد التنفيذ ─────────────────────────────────────────────────────

export const executeActionInputSchema = z.object({
  caseId: z.string().uuid(),
  notes: z.string().min(3).max(2000),
});
export type ExecuteActionInput = z.infer<typeof executeActionInputSchema>;

// ─── مدخلات تقديم مشكلة (V23 §16) ────────────────────────────────────────────
// تطابق submit_my_dispute_v23 RPC — 7 معلمات مبسطة.

export const createDisputeInputSchema = z.object({
  /** عنوان المشكلة (3–300 حرف) */
  title: z.string().min(3).max(300),
  /** وصف المشكلة (10–5000 حرف) */
  description: z.string().min(10).max(5000),
  /** نوع القضية */
  caseType: z.string().min(2).max(100),
  /** معرّفات الأطراف المعنيين */
  parties: z.array(z.string().uuid()).default([]),
  /** معرّفات الشهود */
  witnesses: z.array(z.string().uuid()).default([]),
  /** إقرار بصحة المعلومات */
  truthConfirmed: z.boolean(),
  /** الموافقة على السرية */
  confidentialityAccepted: z.boolean(),
});
export type CreateDisputeInput = z.infer<typeof createDisputeInputSchema>;

// ─── مدخلات تقديم شكوى — V23 §16 ────────────────────────────────────────────
// يُطابق RPC submit_my_dispute_v23 (7 معاملات).

export const createDisputeInputSchema = z.object({
  /** عنوان الشكوى (3–300 حرف) */
  title: z.string().min(3).max(300),
  /** تفاصيل الشكوى (10–5000 حرف) */
  description: z.string().min(10).max(5000),
  /** نوع القضية (سلوكي، إداري، مالي...) */
  caseType: z.string().min(2).max(100),
  /** معرّفات الأطراف (المشتكى عليهم) */
  parties: z.array(z.string().uuid()).default([]),
  /** معرّفات الشهود */
  witnesses: z.array(z.string().uuid()).default([]),
  /** إقرار بصدق المعلومات */
  truthConfirmed: z.boolean(),
  /** قبول سياسة السرية */
  confidentialityAccepted: z.boolean(),
});
export type CreateDisputeInput = z.infer<typeof createDisputeInputSchema>;
