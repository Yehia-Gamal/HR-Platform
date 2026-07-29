import { z } from 'zod';
import { kpiEvaluationSummarySchema, type KpiEvaluationSummary } from './kpi.js';

// إعادة تصدير مخطط ملخص تقييم KPI الرسمي من kpi.ts (المصدر الوحيد للحقيقة — V17 §10).
export { kpiEvaluationSummarySchema, type KpiEvaluationSummary };

export const actionPrioritySchema = z.enum(['low', 'normal', 'high', 'urgent']);
export const actionCenterItemSchema = z.object({
  id: z.string(),
  kind: z.enum(['request', 'kpi', 'decision', 'report', 'case', 'task', 'policy']),
  title: z.string(),
  subtitle: z.string().nullable(),
  priority: actionPrioritySchema,
  status: z.string(),
  dueAt: z.string().nullable(),
  actionUrl: z.string(),
  sourceUpdatedAt: z.string().nullable(),
});
export type ActionCenterItem = z.infer<typeof actionCenterItemSchema>;

export const requestSummarySchema = z.object({
  id: z.string().uuid(),
  requestNumber: z.number(),
  requestType: z.enum(['leave', 'mission', 'convoy', 'late_permit', 'early_permit', 'attendance_correction']),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  title: z.string().nullable(),
  reason: z.string().nullable(),
  status: z.enum(['draft', 'pending', 'approved', 'rejected', 'returned', 'cancelled', 'withdrawn', 'expired', 'escalated']),
  workflowStatus: z.string(),
  currentStepOrder: z.number(),
  activeStepName: z.string().nullable(),
  decisionDueAt: z.string().nullable(),
  createdAt: z.string(),
});
export type RequestSummary = z.infer<typeof requestSummarySchema>;

export const kpiStageScoreSchema = z.object({ score: z.number().nullable(), note: z.string().nullable() });
export const kpiCriterionFormSchema = z.object({
  id: z.string().uuid(), code: z.string(), name: z.string(), description: z.string().nullable(), sectionCode: z.string(),
  weight: z.number(), maxScore: z.number(), sortOrder: z.number(), sourceType: z.string(), evaluatorStage: z.string(),
  // ملاحظة: PostgreSQL تُرجع NULL عند مقارنة NULL=string وليس false — نحول null إلى false هنا.
  calculationMethod: z.string(), editable: z.union([z.boolean(), z.null()]).transform((v) => v ?? false), effectiveScore: z.number().nullable(),
  stageScores: z.record(z.string(), kpiStageScoreSchema),
});
export const kpiGoalSchema = z.object({
  id: z.string().uuid(), title: z.string(), description: z.string().nullable(), targetValue: z.number(), achievedValue: z.number(),
  unit: z.string(), weight: z.number(), dueDate: z.string().nullable(), evidenceSource: z.string().nullable(),
  employeeNote: z.string().nullable(), managerNote: z.string().nullable(), status: z.string(), calculatedScore: z.number(),
});
export const kpiReviewSessionSchema = z.object({
  id: z.string().uuid(), scheduledAt: z.string().nullable(), heldAt: z.string().nullable(), mode: z.string().nullable(),
  discussionSummary: z.string().nullable(), strengths: z.string().nullable(), improvementPoints: z.string().nullable(),
  nextMonthGoals: z.string().nullable(), employeeNotes: z.string().nullable(), managerNotes: z.string().nullable(),
  employeeAttended: z.boolean(), managerAttended: z.boolean(), employeeConfirmedAt: z.string().nullable(),
}).nullable();
export const kpiEvaluationFormSchema = z.object({
  id: z.string().uuid(), employeeId: z.string().uuid(), employeeName: z.string(), employeeCode: z.string().nullable(),
  periodMonth: z.string(), currentStage: kpiEvaluationSummarySchema.shape.currentStage, workflowStatus: z.string(),
  editableStage: z.string().nullable(), locked: z.boolean(), finalScore: z.number().nullable(), finalRating: z.string().nullable(),
  criteria: z.array(kpiCriterionFormSchema), goals: z.array(kpiGoalSchema), session: kpiReviewSessionSchema,
  compliance: z.array(z.object({ metric: z.enum(['PRAYER', 'HALAQA']), requiredCount: z.number(), actualCount: z.number(), exemptCount: z.number(), cancelledCount: z.number(), score: z.number(), note: z.string().nullable() })),
  attendance: z.object({ periodStart: z.string(), periodEnd: z.string(), lateCount: z.number(), earlyLeaveCount: z.number(), unexcusedAbsenceCount: z.number(), shortagePenalty: z.number(), missingPunchCount: z.number(), score: z.number(), hasPendingItems: z.boolean(), calculatedAt: z.string() }).nullable(),
  evidence: z.array(z.object({ id: z.string().uuid(), criterionId: z.string().uuid().nullable(), type: z.string(), title: z.string(), description: z.string().nullable(), storagePath: z.string().nullable(), externalUrl: z.string().nullable(), submittedStage: z.string(), createdAt: z.string() })).default([]),
  cycle: z.object({ id: z.string().uuid(), status: z.string(), scheduledOpenAt: z.string().nullable(), deadlineAt: z.string().nullable(), extendedUntil: z.string().nullable(), effectiveDeadline: z.string().nullable() }),
  validationErrors: z.array(z.string()), lastUpdatedAt: z.string(),
  // V23: حقول المسار المتوازي
  hrCompleted: z.boolean().optional(),
  managerCompleted: z.boolean().optional(),
  parallelFlow: z.boolean().optional(),
  version: z.number().optional(),
});
export type KpiEvaluationForm = z.infer<typeof kpiEvaluationFormSchema>;

// PostType مُصدَّر من postPublishing.ts — لا تكرره هنا.
import { postTypeSchema } from './postPublishing.js';

export const officialFeedItemSchema = z.object({
  id: z.string().uuid(),
  kind: z.enum(['announcement', 'decision']),
  title: z.string(),
  body: z.string(),
  category: z.string(),
  priority: actionPrioritySchema,
  status: z.string(),
  postType: postTypeSchema.optional(),
  requiresAcknowledgement: z.boolean(),
  publishedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
  imageUrl: z.string().nullable().optional(),
  authorName: z.string().optional(),
  authorPhotoUrl: z.string().nullable().optional(),
  acknowledgedCount: z.number(),
  targetCount: z.number().nullable(),
  myAcknowledged: z.boolean().optional(),
  createdAt: z.string().optional(),
});
export type OfficialFeedItem = z.infer<typeof officialFeedItemSchema>;

export const attendanceDashboardSchema = z.object({
  scheduled: z.number(),
  present: z.number(),
  late: z.number(),
  absent: z.number(),
  incomplete: z.number(),
  pendingReview: z.number(),
  lastUpdatedAt: z.string(),
});
export type AttendanceDashboard = z.infer<typeof attendanceDashboardSchema>;

export const leaveBalanceSchema = z.object({
  leaveTypeId: z.string().uuid(),
  code: z.string(),
  nameAr: z.string(),
  availableUnits: z.number(),
  reservedUnits: z.number(),
  consumedUnits: z.number(),
  expiresAt: z.string().nullable(),
});
export type LeaveBalance = z.infer<typeof leaveBalanceSchema>;

// أنواع الإجازات القانونية (تُطابق أكواد leave_types في الترحيل 0060).
// ملاحظة: 'emergency' القديم يُخرَّط إلى 'casual' في الباك إند للتوافق الخلفي.
export const leaveTypeCode = z.enum(['annual', 'casual', 'sick', 'unpaid']);
export type LeaveTypeCode = z.infer<typeof leaveTypeCode>;

// تكليفات العمل: مأمورية / قافلة / فاندي (وحدة work_assignments — الترحيل 0063).
export const workAssignmentType = z.enum(['MISSION', 'CONVOY', 'FUNDRAISING']);
export type WorkAssignmentType = z.infer<typeof workAssignmentType>;

export const workAssignmentStatus = z.enum([
  'DRAFT', 'SUBMITTED', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED',
  'IN_PROGRESS', 'COMPLETED', 'REPORT_PENDING', 'REPORT_SUBMITTED', 'CANCELLED',
]);
export type WorkAssignmentStatus = z.infer<typeof workAssignmentStatus>;

export const workAssignmentSchema = z.object({
  id: z.string().uuid(),
  assignmentNumber: z.number(),
  assignmentType: workAssignmentType,
  title: z.string(),
  description: z.string().nullable(),
  status: workAssignmentStatus,
  createdByEmployeeId: z.string().uuid().nullable(),
  responsibleEmployeeId: z.string().uuid().nullable(),
  startAt: z.string(),
  endAt: z.string(),
  isFullDay: z.boolean(),
  location: z.string().nullable(),
  countsAsWorkDay: z.boolean(),
  needsReport: z.boolean(),
  reportDueAt: z.string().nullable(),
  targetAmount: z.number().nullable(),
  achievedAmount: z.number().nullable(),
  createdAt: z.string(),
});
export type WorkAssignment = z.infer<typeof workAssignmentSchema>;

// كشف الحضور والانصراف الشهري (V12 §18 — Migration 0127).
export const attendanceStatementDaySchema = z.object({
  date: z.string(),
  dayNameAr: z.string(),
  checkIn: z.string().nullable(),
  checkOut: z.string().nullable(),
  shiftName: z.string(),
  workHours: z.number(),
  requiredHours: z.number(),
  lateMinutes: z.number(),
  earlyLeaveMinutes: z.number(),
  overtimeMinutes: z.number(),
  status: z.string(),
  /** غائب */
  isAbsent: z.boolean().catch(false),
  /** يوم عطلة رسمية */
  isOfficialHoliday: z.boolean().catch(false),
  hasLeave: z.boolean().catch(false),
  /** إذن حضور — V23 §14 */
  hasLatePermit: z.boolean().catch(false),
  /** إذن انصراف — V23 §14 */
  hasEarlyPermit: z.boolean().catch(false),
  /** توافق خلفي: hasPermit = hasLatePermit || hasEarlyPermit */
  hasPermit: z.boolean().catch(false),
  hasMission: z.boolean().catch(false),
  hasConvoyFundi: z.boolean().catch(false),
  missingCheckIn: z.boolean().catch(false),
  missingCheckOut: z.boolean().catch(false),
  hasCorrection: z.boolean().catch(false),
  correctionNote: z.string().nullable(),
  /** ملاحظات اليوم — V23 §14 */
  notes: z.string().nullable().default(null),
  /** الجزاءات (مثلاً خصم ساعات) — V23 §14 */
  penalties: z.number().catch(0),
});
export type AttendanceStatementDay = z.infer<typeof attendanceStatementDaySchema>;

export const attendanceStatementSchema = z.object({
  employee: z.object({
    id: z.string().uuid(),
    employeeCode: z.string().nullable(),
    fullNameAr: z.string(),
    jobTitle: z.string(),
    department: z.string(),
    manager: z.string(),
    branch: z.string(),
    hireDate: z.string().nullable(),
  }),
  period: z.object({
    year: z.number(),
    month: z.number(),
    startDate: z.string(),
    endDate: z.string(),
    generatedAt: z.string(),
  }),
  days: attendanceStatementDaySchema.array(),
  summary: z.object({
    totalDays: z.number(),
    scheduledDays: z.number(),
    presentDays: z.number(),
    absentDays: z.number(),
    leaveDays: z.number(),
    permitCount: z.number(),
    missionDays: z.number(),
    convoyFundiDays: z.number(),
    holidayDays: z.number(),
    restDays: z.number(),
    totalWorkHours: z.number(),
    /** إجمالي الساعات المطلوبة — V23 §14 */
    totalRequiredHours: z.number().default(0),
    averageWorkHours: z.number(),
    totalLateMinutes: z.number(),
    totalEarlyLeaveMinutes: z.number(),
    totalOvertimeMinutes: z.number(),
    missingCheckInCount: z.number(),
    missingCheckOutCount: z.number(),
    correctionCount: z.number(),
    /** نسبة الحضور — V23 §14 */
    attendanceRate: z.number().min(0).max(100).default(0),
    /** نسبة الالتزام بالساعات — V23 §14 */
    hoursComplianceRate: z.number().min(0).max(100).default(0),
  }),
});
export type AttendanceStatement = z.infer<typeof attendanceStatementSchema>;
