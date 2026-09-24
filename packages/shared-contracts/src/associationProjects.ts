import { z } from 'zod';

const uuid = z.string().uuid();

/**
 * لمبة حالة المشروع (0553):
 *   active    — أخضر: نشاط حديث.
 *   halted    — أحمر ثابت: متوقف صراحةً أو بلا نشاط منذ warningDays.
 *   critical  — أحمر يومض: بلا نشاط منذ criticalDays → يحتاج تدخل المدير التنفيذي.
 *   completed — مكتمل. stale — ملغى/مطفأ.
 *   pending / rejected / draft — قبل الاعتماد (لا يظهر على اللوحة الرئيسية).
 */
export const projectLedStatusSchema = z.enum(['active', 'halted', 'critical', 'completed', 'stale', 'pending', 'rejected', 'draft']);
export type ProjectLedStatus = z.infer<typeof projectLedStatusSchema>;

// الحقول المضافة في 0553 لها قيم افتراضية حتى يبقى العقد متوافقاً مع
// استجابة ما قبل الـ migration (نشر الويب قد يسبق نشر قاعدة البيانات).
export const associationProjectListItemSchema = z.object({
  id: uuid,
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  departmentId: uuid,
  departmentName: z.string(),
  ownerId: uuid,
  ownerName: z.string(),
  status: z.enum(['planned', 'active', 'on_hold', 'completed', 'cancelled']),
  approvalStatus: z.enum(['draft', 'pending_approval', 'approved', 'rejected']),
  priority: z.enum(['low', 'medium', 'high', 'critical']),
  progress: z.number(),
  startDate: z.string().nullable(),
  targetEndDate: z.string().nullable(),
  lastUpdateAt: z.string().nullable(),
  lastUpdateNote: z.string().nullable(),
  lastActivityAt: z.string().nullable().default(null),
  daysSinceActivity: z.number().nullable().default(null),
  approvedBy: uuid.nullable(),
  approvedAt: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  totalSteps: z.number(),
  completedSteps: z.number(),
  inProgressSteps: z.number().default(0),
  remainingSteps: z.number(),
  blockedSteps: z.number(),
  overdueSteps: z.number().default(0),
  currentStepTitle: z.string().nullable().default(null),
  isOverdue: z.boolean().default(false),
  canManage: z.boolean().default(false),
  ledStatus: projectLedStatusSchema,
});
export type AssociationProjectListItem = z.infer<typeof associationProjectListItemSchema>;

export const associationProjectStepSchema = z.object({
  id: uuid,
  title: z.string(),
  description: z.string().nullable(),
  sortOrder: z.number(),
  status: z.enum(['pending', 'in_progress', 'done', 'blocked']),
  dueDate: z.string().nullable(),
  assigneeId: uuid.nullable(),
  assigneeName: z.string().nullable(),
  completedAt: z.string().nullable().default(null),
  updatedAt: z.string().nullable().default(null),
});
export type AssociationProjectStep = z.infer<typeof associationProjectStepSchema>;

export const associationProjectUpdateSchema = z.object({
  id: uuid,
  note: z.string(),
  progress: z.number().nullable(),
  statusChange: z.string().nullable(),
  authorName: z.string(),
  createdAt: z.string(),
});
export type AssociationProjectUpdate = z.infer<typeof associationProjectUpdateSchema>;

/** صلاحيات المستخدم الحالي على مشروع بعينه — يحسبها الخادم. */
export const associationProjectPermissionsSchema = z.object({
  canManage: z.boolean(),
  canApprove: z.boolean(),
  canEdit: z.boolean(),
  canSubmit: z.boolean(),
  canUpdate: z.boolean(),
  canDelete: z.boolean(),
});
export type AssociationProjectPermissions = z.infer<typeof associationProjectPermissionsSchema>;

export const associationProjectDetailSchema = z.object({
  project: associationProjectListItemSchema,
  steps: z.array(associationProjectStepSchema),
  updates: z.array(associationProjectUpdateSchema),
  permissions: associationProjectPermissionsSchema.optional(),
});
export type AssociationProjectDetail = z.infer<typeof associationProjectDetailSchema>;

export const associationProjectActivitySchema = associationProjectUpdateSchema.extend({
  projectId: uuid,
  projectName: z.string(),
  projectCode: z.string(),
});
export type AssociationProjectActivity = z.infer<typeof associationProjectActivitySchema>;

export const associationProjectSettingsSchema = z.object({
  warningDays: z.number().int(),
  criticalDays: z.number().int(),
});
export type AssociationProjectSettings = z.infer<typeof associationProjectSettingsSchema>;

export const associationProjectsCatalogSchema = z.object({
  projects: z.array(associationProjectListItemSchema),
  recentUpdates: z.array(associationProjectActivitySchema).default([]),
  lastUpdatedAt: z.string(),
  isFullAccess: z.boolean().optional(),
  canCreate: z.boolean().default(true),
  myDepartmentId: uuid.nullable().default(null),
  settings: associationProjectSettingsSchema.default({ warningDays: 7, criticalDays: 14 }),
});
export type AssociationProjectsCatalog = z.infer<typeof associationProjectsCatalogSchema>;
