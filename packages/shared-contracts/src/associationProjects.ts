import { z } from 'zod';

const uuid = z.string().uuid();

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
  approvedBy: uuid.nullable(),
  approvedAt: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  totalSteps: z.number(),
  completedSteps: z.number(),
  remainingSteps: z.number(),
  blockedSteps: z.number(),
  ledStatus: z.enum(['active', 'halted', 'stale', 'pending', 'rejected', 'draft']),
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

export const associationProjectDetailSchema = z.object({
  project: associationProjectListItemSchema,
  steps: z.array(associationProjectStepSchema),
  updates: z.array(associationProjectUpdateSchema),
});
export type AssociationProjectDetail = z.infer<typeof associationProjectDetailSchema>;

export const associationProjectsCatalogSchema = z.object({
  projects: z.array(associationProjectListItemSchema),
  lastUpdatedAt: z.string(),
  isFullAccess: z.boolean().optional(),
});
export type AssociationProjectsCatalog = z.infer<typeof associationProjectsCatalogSchema>;
