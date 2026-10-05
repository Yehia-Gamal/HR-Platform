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

/** عضو في فريق المشروع (0645) — واحد فقط isLeader. */
export const associationProjectMemberSchema = z.object({
  employeeId: uuid,
  name: z.string(),
  jobTitle: z.string().nullable().default(null),
  departmentName: z.string().nullable().default(null),
  isLeader: z.boolean(),
});
export type AssociationProjectMember = z.infer<typeof associationProjectMemberSchema>;

/**
 * صفة المستخدم الحالي في المشروع (0645): القائد، عضو الفريق، مدير/موظف
 * إدارة مرتبطة، المنشئ، أو المدير التنفيذي (admin).
 */
export const projectRoleSchema = z.enum(['leader', 'member', 'dept_manager', 'dept_staff', 'creator', 'admin']);
export type ProjectRole = z.infer<typeof projectRoleSchema>;

// الحقول المضافة في 0553/0645 لها قيم افتراضية حتى يبقى العقد متوافقاً مع
// استجابة ما قبل الـ migration (نشر الويب قد يسبق نشر قاعدة البيانات).
export const associationProjectListItemSchema = z.object({
  id: uuid,
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  /** 0645: الإدارة اختيارية — أول إدارة مرتبطة أو null. */
  departmentId: uuid.nullable(),
  /** أسماء كل الإدارات المرتبطة مفصولة بـ«، » — نص فارغ لمشروع أفراد. */
  departmentName: z
    .string()
    .nullable()
    .transform((v) => v ?? ''),
  departments: z.array(z.object({ id: uuid, name: z.string() })).default([]),
  /** القائد — ownerId/ownerName مرادفان له للتوافق. */
  ownerId: uuid,
  ownerName: z
    .string()
    .nullable()
    .transform((v) => v ?? ''),
  leaderId: uuid.nullable().default(null),
  leaderName: z.string().nullable().default(null),
  members: z.array(associationProjectMemberSchema).default([]),
  myRole: projectRoleSchema.nullable().default(null),
  canEdit: z.boolean().default(false),
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
  /** 0645: الاسم والوصف — يُقفلان بعد الإرسال للاعتماد لغير المدير التنفيذي. */
  canEditCore: z.boolean().optional(),
  /** 0645: القائد والأعضاء والإدارات والأولوية والمواعيد. */
  canEditTeam: z.boolean().optional(),
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
  myEmployeeId: uuid.nullable().default(null),
  settings: associationProjectSettingsSchema.default({ warningDays: 7, criticalDays: 14 }),
});
export type AssociationProjectsCatalog = z.infer<typeof associationProjectsCatalogSchema>;

/** قائمة اختيار فريق المشروع وإداراته (0645 — get_association_project_pickers). */
export const associationProjectPickersSchema = z.object({
  employees: z
    .array(
      z.object({
        id: uuid,
        name: z.string(),
        jobTitle: z.string().nullable().default(null),
        departmentId: uuid.nullable().default(null),
        departmentName: z.string().nullable().default(null),
      }),
    )
    .default([]),
  departments: z.array(z.object({ id: uuid, name: z.string() })).default([]),
});
export type AssociationProjectPickers = z.infer<typeof associationProjectPickersSchema>;
export type AssociationProjectPickerEmployee = AssociationProjectPickers['employees'][number];

/** مهمة مكلَّف بها المستخدم في أحد المشاريع (0647 — get_my_project_tasks). */
export const myProjectTaskSchema = z.object({
  stepId: uuid,
  title: z.string(),
  description: z.string().nullable().default(null),
  status: z.enum(['pending', 'in_progress', 'done', 'blocked']),
  dueDate: z.string().nullable(),
  isOverdue: z.boolean().default(false),
  isDueSoon: z.boolean().default(false),
  projectId: uuid,
  projectName: z.string(),
  projectStatus: z.string(),
  approvalStatus: z.string(),
  leaderName: z.string().nullable().default(null),
});
export type MyProjectTask = z.infer<typeof myProjectTaskSchema>;
export const myProjectTasksSchema = z.array(myProjectTaskSchema);
