import { z } from 'zod';

// عقود KPI الرسمية — V17 §10 + V23 المسار المتوازي.
// V17: موظف → HR → مدير مباشر → اعتماد نهائي → مكتمل.
// V23: موظف → HR + المدير بالتوازي → حاجز → السكرتير → المدير التنفيذي → مكتمل.
// المعايير السبعة بأوزانها الرسمية (المجموع 100).

// ─── مراحل التقييم ───────────────────────────────────────────────────────────

export const kpiStageSchema = z.enum([
  'self',
  'parallel_review',
  'hr_review',
  'manager_review',
  'manager_final',
  'secretary_review',
  'executive_review',
  'finalized',
  'closed',
  'archived',
]);
export type KpiStage = z.infer<typeof kpiStageSchema>;

/** الترتيب الرسمي للمراحل — الفهرس يحدد التقدم مقابل الإرجاع. */
export const KPI_STAGE_ORDER: readonly KpiStage[] = [
  'self',
  'parallel_review',
  'hr_review',
  'manager_review',
  'manager_final',
  'secretary_review',
  'executive_review',
  'finalized',
  'closed',
  'archived',
] as const;

// ─── حالات سير العمل ─────────────────────────────────────────────────────────

export const kpiWorkflowStatusSchema = z.enum([
  'DRAFT',
  'SUBMITTED_TO_HR',
  'HR_REVIEW',
  'SUBMITTED_TO_DIRECT_MANAGER',
  'MANAGER_REVIEW',
  'RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL',
  'MANAGER_APPROVED',
  'INCLUDED_IN_MONTHLY_REPORT',
  'RETURNED_FOR_REVISION',
  'REJECTED',
  'CLOSED',
  'ARCHIVED',
  // V23: حالات المسار المتوازي
  'PARALLEL_REVIEW_IN_PROGRESS',
  'HR_COMPLETED',
  'MANAGER_COMPLETED',
  'SECRETARY_REVIEW',
  'EXECUTIVE_REVIEW',
  'EXECUTIVE_ACKNOWLEDGED',
  'RETURNED_BY_EXECUTIVE',
]);
export type KpiWorkflowStatus = z.infer<typeof kpiWorkflowStatusSchema>;

// ─── أكواد المعايير السبعة ────────────────────────────────────────────────────

export const kpiCriterionCodeSchema = z.enum([
  'TARGET',
  'EFFICIENCY',
  'ATTENDANCE',
  'CONDUCT',
  'PRAYER',
  'HALAQA',
  'INITIATIVES',
]);
export type KpiCriterionCode = z.infer<typeof kpiCriterionCodeSchema>;

/** مسؤول التقييم لكل معيار — V23: السلوك انتقل للمدير. HR: حضور+صلاة+حلقة (30). المدير: أهداف+كفاءة+سلوك+مبادرات (70). */
export const KPI_CRITERION_EVALUATOR: Record<KpiCriterionCode, 'hr' | 'manager'> = {
  TARGET: 'manager',
  EFFICIENCY: 'manager',
  ATTENDANCE: 'hr',
  CONDUCT: 'manager',
  PRAYER: 'hr',
  HALAQA: 'hr',
  INITIATIVES: 'manager',
};

/** الأوزان الرسمية — المجموع 100 نقطة. */
export const KPI_CRITERIA_WEIGHTS: Record<KpiCriterionCode, number> = {
  TARGET: 40,
  EFFICIENCY: 20,
  ATTENDANCE: 20,
  CONDUCT: 5,
  PRAYER: 5,
  HALAQA: 5,
  INITIATIVES: 5,
};

// ─── مخطط المعيار الكامل ──────────────────────────────────────────────────────

export const kpiCriterionSchema = z.object({
  id: z.string().uuid(),
  code: kpiCriterionCodeSchema,
  nameAr: z.string(),
  description: z.string().nullable(),
  maxScore: z.number().min(0).max(100),
  evaluatorStage: z.enum(['hr', 'manager']),
  sourceType: z.enum(['manual', 'automatic', 'compliance']),
  calculationMethod: z.string().nullable(),
  requiresEvidence: z.boolean(),
});
export type KpiCriterion = z.infer<typeof kpiCriterionSchema>;

// ─── درجة واحدة ───────────────────────────────────────────────────────────────

export const kpiScoreInputSchema = z.object({
  criterion_id: z.string().uuid(),
  score: z.number().min(0),
  note: z.string().max(5000).optional(),
});
export type KpiScoreInput = z.infer<typeof kpiScoreInputSchema>;

// ─── سجل الامتثال (صلاة / حلقة) ─────────────────────────────────────────────

export const kpiComplianceMetricSchema = z.enum(['PRAYER', 'HALAQA']);
export type KpiComplianceMetric = z.infer<typeof kpiComplianceMetricSchema>;

export const kpiComplianceInputSchema = z.object({
  evaluationId: z.string().uuid(),
  metric: kpiComplianceMetricSchema,
  totalDays: z.number().int().min(0),
  attendedDays: z.number().int().min(0),
  excusedDays: z.number().int().min(0).default(0),
  violationDays: z.number().int().min(0).default(0),
  note: z.string().max(500).optional(),
});
export type KpiComplianceInput = z.infer<typeof kpiComplianceInputSchema>;

// ─── تقدير الأداء ─────────────────────────────────────────────────────────────

export const kpiRatingBandSchema = z.object({
  min: z.number().min(0),
  max: z.number().max(100),
  label: z.string(),
});
export type KpiRatingBand = z.infer<typeof kpiRatingBandSchema>;

// ─── ملخص التقييم (نتيجة get_kpi_inbox) ──────────────────────────────────────

export const kpiEvaluationSummarySchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  cycleId: z.string().uuid(),
  periodMonth: z.string(),
  currentStage: kpiStageSchema,
  workflowStatus: kpiWorkflowStatusSchema,
  locked: z.boolean(),
  editable: kpiStageSchema.nullable(),
  finalScore: z.number().nullable(),
  finalRating: z.string().nullable(),
  finalBreakdown: z.record(kpiCriterionCodeSchema, z.number()).nullable(),
  managerComment: z.string().nullable(),
  hrComment: z.string().nullable(),
  criteria: z.array(kpiCriterionSchema),
  scores: z.record(z.string(), z.object({
    self: z.number().nullable(),
    manager: z.number().nullable(),
    secretary: z.number().nullable(),
    effective: z.number().nullable(),
  })),
  // V23: حقول المسار المتوازي
  hrCompleted: z.boolean().optional(),
  managerCompleted: z.boolean().optional(),
  parallelFlow: z.boolean().optional(),
  version: z.number().optional(),
});
export type KpiEvaluationSummary = z.infer<typeof kpiEvaluationSummarySchema>;
