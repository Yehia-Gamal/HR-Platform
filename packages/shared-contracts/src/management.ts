import { z } from 'zod';

export const dashboardOverviewSchema = z.object({
  employees: z.number(),
  activeEmployees: z.number(),
  pendingRequests: z.number(),
  attendancePendingReview: z.number(),
  pendingKpi: z.number(),
  openRequisitions: z.number(),
  urgentActions: z.number(),
  publishedDecisions: z.number(),
  unresolvedErrors: z.number(),
  lastUpdatedAt: z.string(),
});
export type DashboardOverview = z.infer<typeof dashboardOverviewSchema>;

export const organizationOverviewSchema = z.object({
  legalEntities: z.number(),
  branches: z.number(),
  workSites: z.number(),
  departments: z.number(),
  teams: z.number(),
  positions: z.number(),
  vacantPositions: z.number(),
  managerRelations: z.number(),
  recentDepartments: z.array(z.object({ id: z.string().uuid(), name: z.string(), active: z.boolean() })),
  recentPositions: z.array(z.object({ id: z.string().uuid(), code: z.string(), title: z.string(), status: z.string() })),
  lastUpdatedAt: z.string(),
});
export type OrganizationOverview = z.infer<typeof organizationOverviewSchema>;

export const accessOverviewSchema = z.object({
  roles: z.number(),
  permissions: z.number(),
  activeAssignments: z.number(),
  sensitivePermissions: z.number(),
  expiringAssignments: z.number(),
  rolesList: z.array(z.object({
    id: z.string().uuid(),
    slug: z.string(),
    name: z.string(),
    isFullAccess: z.boolean(),
    permissionCount: z.number(),
    userCount: z.number(),
  })),
  lastUpdatedAt: z.string(),
});
export type AccessOverview = z.infer<typeof accessOverviewSchema>;

export const recruitmentOverviewSchema = z.object({
  requisitions: z.number(),
  pendingRequisitions: z.number(),
  openPostings: z.number(),
  candidates: z.number(),
  activeApplications: z.number(),
  hiredApplications: z.number(),
  pipeline: z.array(z.object({ stage: z.string(), count: z.number() })),
  recentRequisitions: z.array(z.object({
    id: z.string().uuid(),
    title: z.string(),
    department: z.string(),
    headcount: z.number(),
    status: z.string(),
    createdAt: z.string(),
  })),
  lastUpdatedAt: z.string(),
});
export type RecruitmentOverview = z.infer<typeof recruitmentOverviewSchema>;

export const systemOverviewSchema = z.object({
  enabledFlags: z.number(),
  totalFlags: z.number(),
  unresolvedErrors: z.number(),
  fatalErrors: z.number(),
  latestBackupStatus: z.string().nullable(),
  latestBackupAt: z.string().nullable(),
  settingsCount: z.number(),
  recentErrors: z.array(z.object({ id: z.string().uuid(), level: z.string(), source: z.string(), message: z.string(), occurredAt: z.string() })),
  flags: z.array(z.object({ id: z.string().uuid(), key: z.string(), name: z.string().nullable(), enabled: z.boolean(), rolloutPercent: z.number(), environment: z.string() })),
  lastUpdatedAt: z.string(),
});
export type SystemOverview = z.infer<typeof systemOverviewSchema>;

export const notificationItemSchema = z.object({
  id: z.string().uuid(),
  title: z.string(),
  body: z.string().nullable(),
  category: z.string(),
  priority: z.enum(['low', 'normal', 'high', 'urgent']),
  actionUrl: z.string().nullable(),
  entityType: z.string().nullable().optional(),
  entityId: z.string().nullable().optional(),
  isRead: z.boolean(),
  createdAt: z.string(),
});
export type NotificationItem = z.infer<typeof notificationItemSchema>;

/**
 * أنواع الإشعارات الخاصة بالموبايل فقط — لا تظهر في لوحة الإدارة.
 * تذكيرات البصمة وطلبات التحقق من الموقع مخصصة لتطبيق الموظف.
 */
export const MOBILE_ONLY_ENTITY_TYPES = ['punch_reminder', 'live_location_request'] as const;
