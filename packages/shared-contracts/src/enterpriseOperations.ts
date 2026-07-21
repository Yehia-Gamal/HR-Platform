import { z } from 'zod';

const uuid = z.string().uuid();
const nullableUuid = uuid.nullable();

export const recruitmentWorkbenchSchema = z.object({
  requisitions: z.array(z.object({ id: uuid, title: z.string(), departmentId: uuid, departmentName: z.string(), headcount: z.number(), status: z.string(), createdAt: z.string() })),
  postings: z.array(z.object({ id: uuid, requisitionId: uuid, title: z.string(), slug: z.string(), visibility: z.string(), status: z.string(), publishedAt: z.string().nullable(), closesAt: z.string().nullable() })),
  applications: z.array(z.object({ id: uuid, candidateId: uuid, candidateName: z.string(), postingId: uuid, jobTitle: z.string(), status: z.string(), stageId: nullableUuid, stageName: z.string().nullable(), appliedAt: z.string(), assigneeId: nullableUuid })),
  candidates: z.array(z.object({ id: uuid, name: z.string(), email: z.string().nullable(), phone: z.string().nullable(), source: z.string().nullable(), tags: z.array(z.string()), createdAt: z.string() })),
  stages: z.array(z.object({ id: uuid, postingId: uuid, name: z.string(), orderIndex: z.number(), slaDays: z.number().nullable() })),
  interviews: z.array(z.object({ id: uuid, applicationId: uuid, candidateName: z.string(), mode: z.string(), scheduledAt: z.string().nullable(), status: z.string(), locationOrLink: z.string().nullable() })),
  offers: z.array(z.object({ id: uuid, applicationId: uuid, candidateName: z.string(), title: z.string().nullable(), status: z.string(), startDate: z.string().nullable(), expiresAt: z.string().nullable(), version: z.number() })),
  lastUpdatedAt: z.string(),
});
export type RecruitmentWorkbench = z.infer<typeof recruitmentWorkbenchSchema>;

export const learningAdminCatalogSchema = z.object({
  courses: z.array(z.object({ id: uuid, code: z.string(), title: z.string(), category: z.string(), deliveryMode: z.string(), durationMinutes: z.number(), mandatory: z.boolean(), active: z.boolean(), enrollments: z.number(), completed: z.number() })),
  enrollments: z.array(z.object({ id: uuid, employeeId: uuid, employeeName: z.string(), employeeCode: z.string(), courseId: uuid, courseTitle: z.string(), status: z.string(), progress: z.number(), score: z.number().nullable(), enrolledAt: z.string(), completedAt: z.string().nullable(), expiresAt: z.string().nullable() })),
  employees: z.array(z.object({ id: uuid, name: z.string(), code: z.string() })),
  lastUpdatedAt: z.string(),
});
export type LearningAdminCatalog = z.infer<typeof learningAdminCatalogSchema>;

export const documentStudioCatalogSchema = z.object({
  templates: z.array(z.object({ id: uuid, code: z.string(), name: z.string(), documentType: z.string(), version: z.number(), active: z.boolean(), requiresEmployeeSignature: z.boolean(), requiresManagerSignature: z.boolean(), requiresHrSignature: z.boolean(), requiresExecutiveSignature: z.boolean() })),
  documents: z.array(z.object({ id: uuid, referenceNumber: z.string(), title: z.string(), documentType: z.string(), employeeId: nullableUuid, employeeName: z.string().nullable(), status: z.string(), createdAt: z.string(), issuedAt: z.string().nullable(), pendingSignatures: z.number() })),
  lastUpdatedAt: z.string(),
});
export type DocumentStudioCatalog = z.infer<typeof documentStudioCatalogSchema>;

export const reportSchedulerCatalogSchema = z.object({
  schedules: z.array(z.object({ id: uuid, code: z.string(), name: z.string(), reportType: z.string(), audienceScope: z.string(), scheduleKind: z.string(), timezone: z.string(), runHour: z.number(), runWeekday: z.number().nullable(), runMonthday: z.number().nullable(), deliveryChannels: z.array(z.string()), active: z.boolean(), nextRunAt: z.string().nullable(), lastRunAt: z.string().nullable() })),
  runs: z.array(z.object({ id: uuid, reportType: z.string(), status: z.string(), periodStart: z.string().nullable(), periodEnd: z.string().nullable(), attempts: z.number(), createdAt: z.string(), completedAt: z.string().nullable(), errorDetail: z.string().nullable() })),
  notificationQueue: z.object({ queued: z.number(), failed: z.number() }),
  lastUpdatedAt: z.string(),
});
export type ReportSchedulerCatalog = z.infer<typeof reportSchedulerCatalogSchema>;
