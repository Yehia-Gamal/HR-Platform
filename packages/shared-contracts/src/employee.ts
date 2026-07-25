import { z } from 'zod';

export const employeeStatusSchema = z.enum([
  'draft',
  'invited',
  'onboarding',
  'active',
  'suspended',
  'notice_period',
  'terminated',
  'archived',
  'probation_failed',
]);

const optionalUuid = z.string().uuid().nullable().optional();

export const employeeSummarySchema = z.object({
  id: z.string().uuid(),
  employeeCode: z.string(),
  fullNameAr: z.string(),
  fullNameEn: z.string().nullable(),
  phoneE164: z.string().nullable(),
  status: employeeStatusSchema,
  isActive: z.boolean(),
  photoUrl: z.string().nullable(),
  departmentId: z.string().uuid().nullable(),
  teamId: z.string().uuid().nullable(),
  branchId: z.string().uuid().nullable(),
  // أسماء مُثراة من get_employees_enriched (اختياري للتوافق مع الاستعلام القديم)
  department: z.string().nullable().optional(),
  team: z.string().nullable().optional(),
  branch: z.string().nullable().optional(),
  jobTitle: z.string().nullable().optional(),
  createdAt: z.string(),
});

export type EmployeeSummary = z.infer<typeof employeeSummarySchema>;

export const createEmployeeInputSchema = z.object({
  fullNameAr: z.string().trim().min(3).max(160),
  fullNameEn: z.string().trim().max(160).optional(),
  employeeCode: z.string().trim().min(2).max(50).optional(),
  email: z.string().email(),
  // رقم هاتف مصري محلي بصيغة عادية مثل 01154869616 (11 رقماً يبدأ بـ 01)،
  // أو صيغة دولية E.164 (‎+20…) للتوافق مع البيانات القديمة.
  phoneE164: z
    .string()
    .trim()
    .regex(/^(01\d{9}|\+[1-9]\d{7,14})$/, 'رقم هاتف غير صالح'),
  roleSlug: z.string().trim().min(2),
  jobTitleName: z.string().trim().max(160).optional(),
  photoUrl: z.string().url().max(1000).optional(),
  managerEmployeeId: optionalUuid,
  departmentId: optionalUuid,
  teamId: optionalUuid,
  branchId: optionalUuid,
  workSiteId: optionalUuid,
  jobTitleId: optionalUuid,
  positionId: optionalUuid,
  gradeId: optionalUuid,
  employmentTypeId: optionalUuid,
  hireDate: z.string().date().optional(),
  sendInvite: z.boolean().default(true),
});

export type CreateEmployeeInput = z.infer<typeof createEmployeeInputSchema>;

export const createEmployeeResultSchema = z.object({
  employeeId: z.string().uuid(),
  userId: z.string().uuid(),
  invitationSent: z.boolean(),
});

export type CreateEmployeeResult = z.infer<typeof createEmployeeResultSchema>;

export const employee360Schema = z.object({
  id: z.string().uuid(),
  employeeCode: z.string(),
  fullNameAr: z.string(),
  fullNameEn: z.string().nullable(),
  phoneE164: z.string().nullable(),
  photoUrl: z.string().nullable(),
  status: employeeStatusSchema,
  isActive: z.boolean(),
  hireDate: z.string().nullable(),
  contractEnd: z.string().nullable(),
  probationEnd: z.string().nullable(),
  jobTitle: z.string().nullable(),
  position: z.string().nullable(),
  grade: z.string().nullable(),
  department: z.string().nullable(),
  team: z.string().nullable(),
  branch: z.string().nullable(),
  workSite: z.string().nullable(),
  managerName: z.string().nullable(),
  accountStatus: z.string().nullable(),
  // معرّفات FK خام — للاستخدام في نموذج التعديل (0129)
  departmentId: z.string().uuid().nullable().optional(),
  teamId: z.string().uuid().nullable().optional(),
  branchId: z.string().uuid().nullable().optional(),
  workSiteId: z.string().uuid().nullable().optional(),
  jobTitleId: z.string().uuid().nullable().optional(),
  positionId: z.string().uuid().nullable().optional(),
  gradeId: z.string().uuid().nullable().optional(),
  employmentTypeId: z.string().uuid().nullable().optional(),
  managerId: z.string().uuid().nullable().optional(),
  roles: z.array(z.object({ slug: z.string(), name: z.string() })),
  directReports: z.number(),
  attendance30: z.object({
    present: z.number(),
    lateDays: z.number(),
    absent: z.number(),
    workMinutes: z.number(),
  }),
  requestCounts: z.object({ pending: z.number(), approved: z.number(), rejected: z.number() }),
  latestKpi: z.object({
    id: z.string().uuid(),
    periodMonth: z.string(),
    currentStage: z.string(),
    finalScore: z.number().nullable(),
    finalRating: z.string().nullable(),
  }).nullable(),
  documents: z.array(z.object({
    id: z.string().uuid(), type: z.string(), title: z.string(), expiryDate: z.string().nullable(), status: z.string(),
  })),
  assets: z.array(z.object({
    id: z.string().uuid(), assetName: z.string(), assetType: z.string(), serial: z.string().nullable(), handedOverAt: z.string().nullable(), returnedAt: z.string().nullable(),
  })),
  recentRequests: z.array(z.object({
    id: z.string().uuid(), requestNumber: z.number(), requestType: z.string(), title: z.string().nullable(), status: z.string(), createdAt: z.string(),
  })),
  recentTasks: z.array(z.object({
    id: z.string().uuid(), title: z.string(), status: z.string(), priority: z.string(), dueDate: z.string().nullable(),
  })),
  lastUpdatedAt: z.string(),
});

export type Employee360 = z.infer<typeof employee360Schema>;
