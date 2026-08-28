import { Navigate, useLocation, useParams } from 'react-router';
import { useAuth } from '../auth/AuthProvider';
import { firstWebWorkspace } from '../workspaces/access';

/**
 * وجهة الروابط الموحّدة (بند 10): نفس رابط `/action/{kind}/{id}` الذي
 * يفتح التطبيق على الهاتف (app link مُصرَّح) يُفتح هنا على المتصفح
 * ويُحوَّل لأفضل صفحة ويب مكافئة في مساحة عمل المستخدم.
 *
 * معرّف غير صالح (ليس UUID) → رئيسية مساحة العمل.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** خريطة النوع الموحّد → مسار نسبي داخل مساحة العمل. */
const KIND_TO_SEGMENT: Record<string, string> = {
  request: 'requests',
  request_decision: 'requests',
  kpi: 'performance',
  kpi_evaluation: 'performance',
  dispute: 'disputes',
  location: 'live-location',
  location_request: 'live-location',
  live_location: 'live-location',
  live_location_request: 'live-location',
  attendance: 'attendance',
  attendance_alert: 'attendance',
  punch_reminder: 'attendance',
  attendance_daily: 'attendance',
  task: 'operations',
  decision: 'official-feed',
  announcement: 'official-feed',
  recognition: 'official-feed',
  daily_report: 'daily-reports',
  daily_report_like: 'daily-reports',
  daily_report_comment: 'daily-reports',
};

export function ActionRedirect() {
  const { kind = '', actionId = '' } = useParams();
  const auth = useAuth();
  const { pathname } = useLocation();

  // مساحة العمل: من الرابط إن بدأ بـ /admin، وإلا الافتراضية للمستخدم.
  const workspace = pathname.startsWith('/admin') ? '/admin' : `/${(auth.access && firstWebWorkspace(auth.access)) || 'hr'}`;

  if (!UUID_RE.test(actionId)) {
    return <Navigate to={workspace} replace />;
  }

  const segment = KIND_TO_SEGMENT[kind.toLowerCase()] ?? '';
  // بعض الصفحات تدعم فتح عنصر تفصيلي ب’enriched param:
  //   request → /requests?request={id}  (يفتح حوار الطلب + قراره)
  const enrichedSegments: Record<string, string> = {
    request: 'requests',
  };
  if (!segment) return <Navigate to={workspace} replace />;
  const hasParam = kind.toLowerCase() in enrichedSegments;
  return <Navigate to={hasParam ? `${workspace}/${segment}?request=${actionId}` : `${workspace}/${segment}`} replace />;
}
