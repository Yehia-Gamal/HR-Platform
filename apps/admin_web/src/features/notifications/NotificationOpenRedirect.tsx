import { useEffect, useRef } from 'react';
import { Navigate, useParams } from 'react-router';
import { useAuth } from '../auth/AuthProvider';
import { firstWebWorkspace } from '../workspaces/access';
import { LoadingScreen } from '../../ui/LoadingScreen';
import { notificationTargetPath, type NotificationWorkspace } from './notificationTarget';
import { useMarkNotificationsRead, useNotifications } from './useNotifications';

/**
 * وجهة النقر على إشعار المتصفح (Web Push): `/notification/{id}`.
 *
 * كان Service Worker يفتح `data.actionUrl` الخام من قاعدة البيانات — فارغ في
 * إشعارات الطلبات، أو مسار موبايل (`/attendance`)، أو `ahlashabab://` —
 * فيهبط المستخدم على الرئيسية لا على الحدث. هنا نبحث عن الإشعار في قائمة
 * المستخدم نفسه (RLS) ونوجّه بنفس منطق صفحة الإشعارات داخل التطبيق.
 * الرابط لا يحمل إلا معرّف الإشعار — لا محتواه.
 */
const WORKSPACE_TO_NOTIFICATION: Record<string, NotificationWorkspace> = {
  main_admin: 'admin',
  hr: 'hr',
  committee: 'committee',
};
const WORKSPACE_ROOT: Record<NotificationWorkspace, string> = { admin: '/admin', hr: '/hr', committee: '/committee' };

export function NotificationOpenRedirect() {
  const { notificationId = '' } = useParams();
  const auth = useAuth();
  const query = useNotifications();
  const mark = useMarkNotificationsRead();
  const markedRef = useRef(false);

  const webWorkspace = auth.access ? firstWebWorkspace(auth.access) : null;
  const workspace: NotificationWorkspace = WORKSPACE_TO_NOTIFICATION[webWorkspace ?? ''] ?? 'hr';
  const item = query.data?.find((n) => n.id === notificationId);

  useEffect(() => {
    if (item && !item.isRead && !markedRef.current) {
      markedRef.current = true;
      mark.mutate([item.id]);
    }
  }, [item, mark]);

  if (query.isLoading) return <LoadingScreen />;
  const fallback = `${WORKSPACE_ROOT[workspace]}/notifications`;
  if (!item) return <Navigate to={fallback} replace />;
  return <Navigate to={notificationTargetPath(item, workspace) ?? fallback} replace />;
}
