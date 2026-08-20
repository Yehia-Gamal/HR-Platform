import { useLocation } from 'react-router';
import type { AccessContext, WorkspaceId } from '@ahla/shared-contracts';

export function hasPermission(context: AccessContext | null, permission: string): boolean {
  if (!context) return false;
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

/**
 * صفحات الموارد البشرية المتاحة أيضًا داخل القائمة الموحّدة للأدمن الرئيسي.
 * تُستخدم لترجمة المسار بين /hr/... و/admin/hr/... عند إعادة التوجيه.
 */
export const HR_PAGE_SEGMENTS = [
  'employees',
  'attendance',
  'attendance/operations',
  'attendance/report',
  'performance',
  'recruitment',
  'onboarding',
  'reports',
  'holidays',
  'requests',
  'leave-tools',
  'devices',
  'organization',
  'official-feed',
  'learning',
  'lifecycle',
  'documents',
  'knowledge',
] as const;

/**
 * يحوّل مسارًا يبدأ بـ /hr إلى ما يقابله داخل /admin/hr، أو يعيد null إذا لم يكن مسار HR.
 */
export function hrPathToAdmin(path: string): string | null {
  if (path === '/hr') return '/admin/hr';
  if (!path.startsWith('/hr/')) return null;
  return `/admin/hr/${path.slice('/hr/'.length)}`;
}

/**
 * يعيد true إذا كانت القائمة الموحّدة للأدمن الرئيسي تغطي المسار الحالي،
 * بما يشمل /admin نفسها والصفحات الـ HR المثبّتة تحت /admin/hr.
 */
export function isUnifiedAdminActive(workspaces: readonly WorkspaceId[], pathname: string): boolean {
  if (!workspaces.includes('main_admin')) return false;
  return pathname === '/admin' || pathname.startsWith('/admin/');
}

/**
 * Hook يُعيد سابقة مسار HR الصحيحة حسب المسار الحالي:
 * '/admin/hr' داخل المساحة الموحّدة للأدمن الرئيسي، أو '/hr' خلاف ذلك.
 * تُستخدم لبناء روابط مطلقة تعمل من أي مسار دون قفزات إعادة توجيه.
 *
 * مثال: useHrPrefix() + `/employees/${id}` يُعطي الرابط الصحيح في كلا الحالتين.
 */
export function useHrPrefix(): string {
  const location = useLocation();
  return location.pathname.startsWith('/admin/hr') ? '/admin/hr' : '/hr';
}
