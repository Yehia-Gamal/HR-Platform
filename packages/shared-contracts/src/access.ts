import { z } from 'zod';

export const workspaceIdSchema = z.enum([
  'employee',
  'manager',
  'executive',
  'hr',
  'main_admin',
  'committee',
  'field_operations',
]);

export type WorkspaceId = z.infer<typeof workspaceIdSchema>;

export const attendancePolicySchema = z.object({
  attendanceRequired: z.boolean(),
  selfPunchEnabled: z.boolean(),
  liveLocationResponseEnabled: z.boolean(),
});

export const accessContextSchema = z.object({
  userId: z.string().uuid(),
  employeeId: z.string().uuid().nullable(),
  displayName: z.string().min(1),
  employeeCode: z.string().nullable(),
  roles: z.array(z.string()),
  permissions: z.array(z.string()),
  workspaces: z.array(workspaceIdSchema),
  defaultWorkspace: workspaceIdSchema,
  attendancePolicy: attendancePolicySchema,
});

export type AccessContext = z.infer<typeof accessContextSchema>;

export function canUseWorkspace(
  context: AccessContext,
  workspace: WorkspaceId,
): boolean {
  return context.workspaces.includes(workspace);
}

export function isWebWorkspace(workspace: WorkspaceId): boolean {
  return workspace === 'hr' || workspace === 'main_admin' || workspace === 'committee';
}
