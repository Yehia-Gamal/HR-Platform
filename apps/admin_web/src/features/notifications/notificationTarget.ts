import type { NotificationItem } from '@ahla/shared-contracts';

export type NotificationWorkspace = 'admin' | 'hr' | 'committee';

/** يستخرج المساحة الحالية من مسار الصفحة — يُستدعى داخل WorkspaceShell. */
export function notificationWorkspaceFromPath(pathname: string): NotificationWorkspace {
  if (pathname.startsWith('/admin')) return 'admin';
  if (pathname.startsWith('/committee')) return 'committee';
  return 'hr';
}

/**
 * هل الرابط مسار داخلي صالح؟ المسارات التي تبدأ بـ / بدون scheme تُمرَّر كما هي
 * (مثل /admin/disputes?case=…). روابط deep link الكاملة (تلك التي تحوي ://)
 * تُرفض هنا لأن متصفح الويب لا يملك صفحة /action/{kind}/{id} —
 * فيُركب الوجهة من entityType بدلاً منها.
 */
export function isInternalAppPath(url: string | null | undefined): url is string {
  if (!url) return false;
  return url.startsWith('/') && !url.startsWith('//') && !url.includes('://');
}

/** خريطة نوع الكيان → مسار إداري لكل مساحة عمل. */
const ENTITY_TYPE_PATHS: Record<NotificationWorkspace, Partial<Record<string, string>>> = {
  admin: {
    request: '/admin/hr/requests',
    request_decision: '/admin/hr/requests',
    work_assignments: '/admin/hr/requests',
    kpi: '/admin/performance/cycles',
    kpi_evaluation: '/admin/performance/cycles',
    attendance: '/admin/hr/attendance',
    attendance_alert: '/admin/hr/attendance',
    dispute: '/admin/disputes?case=',
    decision: '/admin/official-feed',
    announcement: '/admin/official-feed',
    recognition: '/admin/official-feed',
    daily_report: '/admin/daily-reports',
    daily_report_like: '/admin/daily-reports',
    daily_report_comment: '/admin/daily-reports',
  },
  hr: {
    request: '/hr/requests',
    request_decision: '/hr/requests',
    work_assignments: '/hr/requests',
    kpi: '/hr/performance',
    kpi_evaluation: '/hr/performance',
    attendance: '/hr/attendance',
    attendance_alert: '/hr/attendance',
    decision: '/hr/official-feed',
    announcement: '/hr/official-feed',
    recognition: '/hr/official-feed',
    daily_report: '/hr/daily-reports',
    daily_report_like: '/hr/daily-reports',
    daily_report_comment: '/hr/daily-reports',
  },
  committee: {
    dispute: '/committee/disputes?case=',
  },
};

/**
 * يقرر الوجهة الفعلية لإشعار في لوحة الإدارة:
 * 1) actionUrl داخلي صالح → يُستخدم كما هو.
 * 2) غير ذلك → يُركب الوجهة من entityType (+ entityId عند الحاجة).
 * 3) لا وجهة (إشعار معلوماتي) → null، ولا يُعرض زر فتح.
 */
export function notificationTargetPath(item: NotificationItem, workspace: NotificationWorkspace): string | null {
  if (isInternalAppPath(item.actionUrl)) return item.actionUrl;
  if (!item.entityType) return null;
  const base = ENTITY_TYPE_PATHS[workspace][item.entityType];
  if (!base) return null;
  if (base.endsWith('?case=') && item.entityId) return `${base}${item.entityId}`;
  return base;
}
