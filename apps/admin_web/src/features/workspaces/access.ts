import type { AccessContext, WorkspaceId } from '@ahla/shared-contracts';

export function hasPermission(context: AccessContext, permission: string): boolean {
  return context.permissions.includes('*') || context.permissions.includes(permission);
}

/** يعيد true إذا يملك المستخدم أي صلاحية من القائمة (OR). */
export function hasAnyPermission(context: AccessContext, permissions: string | string[]): boolean {
  if (typeof permissions === 'string') return hasPermission(context, permissions);
  return permissions.some((p) => hasPermission(context, p));
}

export function firstWebWorkspace(context: AccessContext): WorkspaceId | null {
  if (context.defaultWorkspace === 'hr' || context.defaultWorkspace === 'main_admin' || context.defaultWorkspace === 'committee') {
    return context.defaultWorkspace;
  }
  if (context.workspaces.includes('main_admin')) return 'main_admin';
  if (context.workspaces.includes('hr')) return 'hr';
  if (context.workspaces.includes('committee')) return 'committee';
  return null;
}
