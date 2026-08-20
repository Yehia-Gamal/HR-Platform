import { z } from 'zod';
import { requestTypeSchema } from './requests.js';

// ─── مسارات سير العمل (Workflow Definitions & Steps) ──────────────────────────

export const workflowStepSchema = z.object({
  id: z.string().uuid(),
  workflowId: z.string().uuid(),
  stepOrder: z.number().int().min(1),
  stepName: z.string().min(1).max(100),
  approverRole: z.string().min(1),
  slaHours: z.number().int().positive().optional().nullable(),
  autoApproveOnSla: z.boolean().default(false),
});
export type WorkflowStep = z.infer<typeof workflowStepSchema>;

export const workflowDefinitionSchema = z.object({
  id: z.string().uuid(),
  requestType: requestTypeSchema,
  name: z.string().min(2).max(150),
  description: z.string().max(500).nullable().optional(),
  isActive: z.boolean().default(true),
  steps: z.array(workflowStepSchema).optional(),
  createdAt: z.string().datetime().optional(),
  updatedAt: z.string().datetime().optional(),
});
export type WorkflowDefinition = z.infer<typeof workflowDefinitionSchema>;

export const createWorkflowDefinitionInputSchema = z.object({
  requestType: requestTypeSchema,
  name: z.string().min(2).max(150),
  description: z.string().max(500).optional(),
  steps: z.array(
    z.object({
      stepOrder: z.number().int().min(1),
      stepName: z.string().min(1).max(100),
      approverRole: z.string().min(1),
      slaHours: z.number().int().positive().optional(),
      autoApproveOnSla: z.boolean().default(false),
    })
  ).min(1, 'يجب تحديد خطوة واحدة على الأقل'),
});
export type CreateWorkflowDefinitionInput = z.infer<typeof createWorkflowDefinitionInputSchema>;
