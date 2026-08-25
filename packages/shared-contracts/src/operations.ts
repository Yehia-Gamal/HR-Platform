import { z } from 'zod';
import { kpiEvaluationSummarySchema, type KpiEvaluationSummary } from './kpi.js';
import { missionExecutionSchema, type MissionExecution } from './requests.js';

// إعادة تصدير مخطط ملخص تقييم KPI الرسمي من kpi.ts (المصدر الوحيد للحقيقة — V17 §10).
export { kpiEvaluationSummarySchema, type KpiEvaluationSummary };

// عقود طلبات تنفيذ المأمورية (0318).
export { missionExecutionSchema, type MissionExecution };

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
  requestType: z.enum(['leave', 'mission', 'convoy', 'fundraising', 'late_permit', 'early_permit', 'attendance_correction']),
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
  // 0318: بيانات الطلب التفصيلية + سجل تنفيذ المأمورية.
  payload: z.record(z.string(), z.unknown()).optional(),
  missionExecution: missionExecutionSchema.optional(),
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
  // 0470: HR يدخل الاستثناءات في أي مرحلة قبل القفل
  complianceEditable: z.boolean().optional(),
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
  postType: z.string().optional(),
  requiresAcknowledgement: z.boolean(),
  publishedAt: z.string().nullable(),
  expiresAt: z.string().nullable(),
  imageUrl: z.string().nullable().optional(),
  authorName: z.string().optional(),
  authorPhotoUrl: z.string().nullable().optional(),
  acknowledgedCount: z.number(),
  viewCount: z.number().nonnegative().default(0),
  reactionCount: z.number().nonnegative().default(0),
  reactionSummary: z.record(z.string(), z.number().nonnegative()).default({}),
  targetCount: z.number().nullable(),
  myAcknowledged: z.boolean().optional(),
  myReaction: z.enum(['like', 'celebrate', 'support', 'insightful']).nullable().optional(),
  createdAt: z.string().optional(),
});
export type OfficialFeedItem = z.infer<typeof officialFeedItemSchema>;

export const announcementEngagementPersonSchema = z.object({
  employeeId: z.string().uuid(),
  name: z.string(),
  photoUrl: z.string().nullable(),
  at: z.string(),
  viewCount: z.number().positive().optional(),
  reactionType: z.enum(['like', 'celebrate', 'support', 'insightful']).optional(),
});
export type AnnouncementEngagementPerson = z.infer<typeof announcementEngagementPersonSchema>;

export const announcementEngagementDetailSchema = z.object({
  announcementId: z.string().uuid(),
  targetCount: z.number().nonnegative(),
  viewerCount: z.number().nonnegative(),
  reactionCount: z.number().nonnegative(),
  acknowledgedCount: z.number().nonnegative(),
  viewers: announcementEngagementPersonSchema.array(),
  reactions: announcementEngagementPersonSchema.array(),
  acknowledgements: announcementEngagementPersonSchema.array(),
});
export type AnnouncementEngagementDetail = z.infer<typeof announcementEngagementDetailSchema>;

export const attendanceDashboardSchema = z.object({
  scheduled: z.number(),
  present: z.number(),
  late: z.number(),
  absent: z.number(),
  unexcusedAbsent: z.number().optional(),
  /** إجازات معتمدة تغطي اليوم (0355) */
  onLeave: z.number().optional(),
  /** مأموريات/تكليفات نشطة بلا سجل حضور (0355) */
  onMission: z.number().optional(),
  /** بصمة دخول بلا انصراف (0355) */
  missingCheckout: z.number().optional(),
  /** بصمات غير مكتملة — اختياري لتوافق DB القديم */
  incomplete: z.number().optional(),
  /** قيد المراجعة — اختياري لتوافق DB القديم */
  pendingReview: z.number().optional(),
  locationRequestsToday: z.number().optional(),
  /** اسم الحقل الفعلي من DB (0444) — يُعاد تسميته من locationRespondedToday */
  locationRequestsResponded: z.number().optional(),
  /** اسم قديم — يُقبل للتوافق */
  locationRespondedToday: z.number().optional(),
  /** تاريخ اللوحة — اختياري */
  date: z.string().optional(),
  /** آخر تحديث — اختياري لتوافق DB القديم */
  lastUpdatedAt: z.string().optional(),
});
export type AttendanceDashboard = z.infer<typeof attendanceDashboardSchema>;

// فئات لوحة الحضور التفصيلية — تُستخدم لفتح قائمة الموظفين لكل بطاقة.
export const attendanceRosterCategorySchema = z.enum([
  'scheduled',
  'present',
  'late',
  'absent',
  'unexcused_absent',
  'incomplete',
  'pending_review',
  'location_requests',
  'location_responded',
  'on_leave',
  'on_mission',
  'missing_checkout',
]);
export type AttendanceRosterCategory = z.infer<typeof attendanceRosterCategorySchema>;

// صف قائمة الحضور التفصيلية — يعكس أعمدة public.get_attendance_day_roster
// (النسخة الموسّعة في الترحيل 0294). الحقول الجديدة اختيارية للتوافق الخلفي
// مع النتيجة القديمة (date, text) التي تُرجع مصفوفة مباشرة.
export const attendanceRosterItemSchema = z.object({
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  photoUrl: z.string().nullable().optional(),
  departmentId: z.string().uuid().nullable().optional(),
  departmentName: z.string().nullable(),
  branchId: z.string().uuid().nullable().optional(),
  branchName: z.string().nullable().optional(),
  jobTitle: z.string().nullable().optional(),
  managerId: z.string().uuid().nullable().optional(),
  managerName: z.string().nullable().optional(),
  status: z.string().nullable(),
  lateMinutes: z.number().nullable(),
  firstCheckIn: z.string().nullable(),
  lastCheckOut: z.string().nullable(),
  shiftName: z.string().nullable().optional(),
  shiftStartAt: z.string().nullable().optional(),
  shiftEndAt: z.string().nullable().optional(),
  requiresReview: z.boolean().optional(),
  reviewReason: z.string().nullable().optional(),
  hasApprovedLeave: z.boolean().optional(),
  leaveCode: z.string().nullable().optional(),
  leaveIsPaid: z.boolean().nullable().optional(),
  hasMission: z.boolean().optional(),
  locationRequestStatus: z.string().nullable(),
  locationRequestedAt: z.string().nullable().optional(),
  locationRespondedAt: z.string().nullable().optional(),
});
export type AttendanceRosterItem = z.infer<typeof attendanceRosterItemSchema>;

// نتيجة الترحيم (pagination) من get_attendance_day_roster الموسّع.
// يضمن التطابق بين «الرقم في البطاقة» و«عدد نتائج القائمة»:
// total محسوب من نفس استعلام items (بعد الفلاتر وقبل limit/offset).
export const attendanceRosterPageSchema = z.object({
  items: attendanceRosterItemSchema.array(),
  total: z.number(),
  limit: z.number(),
  offset: z.number(),
});
export type AttendanceRosterPage = z.infer<typeof attendanceRosterPageSchema>;

// خيارات ترتيب قائمة الحضور — تعكس معاملات p_sort/p_direction في RPC.
export const attendanceRosterSortSchema = z.enum(['name', 'check_in', 'late', 'status']);
export type AttendanceRosterSort = z.infer<typeof attendanceRosterSortSchema>;

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
export const leaveTypeCodeSchema = z.enum(['annual', 'casual', 'sick', 'unpaid']);
export type LeaveTypeCode = z.infer<typeof leaveTypeCodeSchema>;

// تكليفات العمل: مأمورية / قافلة / فاندي (وحدة work_assignments — الترحيل 0063).
export const workAssignmentTypeSchema = z.enum(['MISSION', 'CONVOY', 'FUNDRAISING']);
export type WorkAssignmentType = z.infer<typeof workAssignmentTypeSchema>;

export const workAssignmentStatusSchema = z.enum([
  'DRAFT', 'SUBMITTED', 'PENDING_APPROVAL', 'APPROVED', 'REJECTED',
  'IN_PROGRESS', 'COMPLETED', 'REPORT_PENDING', 'REPORT_SUBMITTED', 'CANCELLED',
]);
export type WorkAssignmentStatus = z.infer<typeof workAssignmentStatusSchema>;

export const workAssignmentSchema = z.object({
  id: z.string().uuid(),
  assignmentNumber: z.number(),
  assignmentType: workAssignmentTypeSchema,
  title: z.string(),
  description: z.string().nullable(),
  status: workAssignmentStatusSchema,
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
  /** يوم عمل قادم؛ لا يُعد غيابًا ولا يدخل في النسب الحالية. */
  isFuture: z.boolean().catch(false),
  /** يوم عمل مستحق حتى وقت إنشاء التقرير. */
  isDue: z.boolean().catch(false),
  /** تم تسجيل الحضور وما زالت الوردية مفتوحة. */
  isOpenShift: z.boolean().catch(false),
  /** حضور مكتمل ببصمتي دخول وخروج. */
  isCompleted: z.boolean().catch(false),
  /** تعديل إداري فعّال مع بقاء البصمات الخام محفوظة. */
  adminOverride: z
    .object({
      id: z.string().uuid(),
      dayType: z.enum(['work', 'leave', 'mission', 'convoy', 'fundraising', 'holiday', 'rest', 'absent']),
      leaveType: z.string().nullable().optional(),
      reason: z.string(),
      notes: z.string().nullable(),
      updatedAt: z.string(),
    })
    .nullable()
    .optional(),
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
  capabilities: z
    .object({
      canEditDays: z.boolean().default(false),
    })
    .default({ canEditDays: false }),
  summary: z.object({
    totalDays: z.number(),
    scheduledDays: z.number(),
    /** كامل أيام العمل في الشهر بعد استبعاد الجمعة والعطلات الرسمية. */
    dueScheduledDays: z.number().nonnegative().default(0),
    /** أيام العمل القادمة المتبقية في الشهر. */
    upcomingDays: z.number().nonnegative().default(0),
    presentDays: z.number(),
    absentDays: z.number(),
    /** ورديات اليوم التي بدأ حضورها ولم يحن/يُسجّل انصرافها بعد. */
    openShiftDays: z.number().nonnegative().default(0),
    /** أيام الحضور المكتملة المستخدمة في متوسط الساعات. */
    completedPresenceDays: z.number().nonnegative().default(0),
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
    /** نسبة الحضور الفعلي من كامل أيام العمل الشهرية. */
    attendanceRate: z.number().min(0).max(100).default(0),
    /** مكونات نسبة الحضور الشهرية الكاملة. */
    attendanceRateBasis: z
      .object({
        presentInDue: z.number().nonnegative(),
        dueDays: z.number().nonnegative(),
        presentDays: z.number().nonnegative(),
        absentDays: z.number().nonnegative(),
        openShiftDays: z.number().nonnegative(),
        upcomingDays: z.number().nonnegative(),
      })
      .optional(),
    /** نسبة تغطية أيام العمل (حضور/إجازة/مأمورية/قافلة/فاندي). */
    coverageRate: z.number().min(0).max(100).default(0),
    coverageDays: z.number().nonnegative().default(0),
    /** نسبة الساعات المنجزة من إجمالي ساعات الشهر. */
    hoursComplianceRate: z.number().min(0).max(100).default(0),
    /** false يعني أن المقام غير متوفر، فتُعرض النسبة «غير متاحة» لا 0%. */
    hoursComplianceAvailable: z.boolean().default(false),
    totalDeficitMinutes: z.number().nonnegative().default(0),
    hoursRateBasis: z
      .object({
        workedMinutes: z.number().nonnegative(),
        requiredMinutes: z.number().nonnegative(),
        scheduledDays: z.number().nonnegative(),
        deficitMinutes: z.number().nonnegative(),
        overtimeMinutes: z.number().nonnegative(),
      })
      .optional(),
  }),
});
export type AttendanceStatement = z.infer<typeof attendanceStatementSchema>;

// عنصر خلاصة التقارير اليومية العامة — يعكس نتيجة public.get_public_daily_reports_feed
// في الترحيل 0324 (jsonb مبني بـ jsonb_build_object في قاعدة البيانات).
export const dailyReportCommentSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  comment: z.string(),
  createdAt: z.string(),
});
export type DailyReportComment = z.infer<typeof dailyReportCommentSchema>;

export const dailyReportFeedItemSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  employeeCode: z.string().nullable(),
  photoUrl: z.string().nullable(),
  jobTitle: z.string().nullable(),
  department: z.string().nullable(),
  managerName: z.string().nullable(),
  reportDate: z.string(),
  achievements: z.string(),
  blockers: z.string().nullable(),
  tomorrowPlan: z.string().nullable(),
  managerComment: z.string().nullable(),
  reviewedByName: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  createdAt: z.string(),
  likesCount: z.number(),
  isLikedByMe: z.boolean(),
  comments: z.array(dailyReportCommentSchema),
});
export type DailyReportFeedItem = z.infer<typeof dailyReportFeedItemSchema>;

export const toggleLikeResultSchema = z.object({
  liked: z.boolean(),
  count: z.number(),
});
export type ToggleLikeResult = z.infer<typeof toggleLikeResultSchema>;
