import type { NotificationItem } from '@ahla/shared-contracts';

export type NotificationWorkspace = 'admin' | 'hr' | 'committee';

/** يستخرج المساحة الحالية من مسار الصفحة — يُستدعى داخل WorkspaceShell. */
export function notificationWorkspaceFromPath(pathname: string): NotificationWorkspace {
  if (pathname.startsWith('/admin')) return 'admin';
  if (pathname.startsWith('/committee')) return 'committee';
  return 'hr';
}

/**
 * هل الرابط مسار داخلي صالح داخل مساحة عمل الويب؟
 *
 * لا يكفي أن يبدأ بـ «/»: الخلفية تخزّن مسارات موبايل محضة مثل `/attendance`
 * و`/reports/attendance` لا وجود لها في راوتر الويب — كانت تُمرَّر كما هي
 * فيبتلعها catch-all ويُعاد المستخدم للوحة التحكم، فيبدو وكأن «النقر لا يفعل
 * شيئاً». لذا نقبل فقط ما يبدأ ببادئة مساحة عمل حقيقية.
 */
const WORKSPACE_PREFIXES = ['/admin/', '/hr/', '/committee/', '/me/'] as const;

export function isInternalAppPath(url: string | null | undefined): url is string {
  if (!url) return false;
  if (!url.startsWith('/') || url.startsWith('//') || url.includes('://')) return false;
  return WORKSPACE_PREFIXES.some((prefix) => url.startsWith(prefix));
}

/**
 * يستخرج (kind, id) من رابط `/action/{kind}/{id}` بأي صيغة —
 * كاملة (https://host/action/…) أو مخصصة (ahlashabab://action/…) أو نسبية.
 * الويب لا يملك صفحة لهذه المسارات؛ نحوّلها لنوع كيان ونبني الوجهة منه.
 */
export function parseActionDeepLink(url: string | null | undefined): { kind: string; id: string | null } | null {
  if (!url) return null;
  const withoutScheme = url.replace(/^[a-z][a-z0-9+.-]*:\/\//i, '');
  const path = withoutScheme.split('?')[0] ?? '';
  const segments = path.split('/').filter(Boolean);
  const index = segments.indexOf('action');
  if (index < 0 || segments.length < index + 2) return null;
  return { kind: segments[index + 1] ?? '', id: segments[index + 2] ?? null };
}

/**
 * يوحّد صيغ entity_type المتعددة التي تكتبها دوال الإشعارات في قاعدة البيانات
 * إلى اسم واحد — نفس تطبيع الموبايل في notification_handler.dart.
 */
export function canonicalEntityType(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const type = raw.toLowerCase().trim();
  if (type.startsWith('instant_penalty')) return 'instant_penalty';
  switch (type) {
    case 'requests':
    case 'request_decision':
      return 'request';
    // كيانات تُعرض داخل صفحة الطلبات لكن معرّفاتها من جداول أخرى — تفتح
    // الصفحة بلا ?request= حتى لا نمرّر معرّفاً لا يطابق أي طلب.
    case 'work_assignments':
    case 'service_requests':
    case 'document_signature_requests':
      return 'requests_page';
    case 'kpi_evaluation':
    case 'kpi_evaluations':
      return 'kpi';
    // التظلم كيان مستقل عن التقييم — يفتح صفحة الأداء بلا إبراز خاطئ.
    case 'kpi_appeals':
      return 'performance_page';
    case 'dispute_case':
    case 'dispute_cases':
      return 'dispute';
    case 'announcements':
      return 'announcement';
    case 'decisions':
      return 'decision';
    case 'daily_report':
    case 'daily_report_like':
    case 'daily_report_comment':
      return 'daily_reports';
    case 'attendance':
    case 'attendance_alert':
    case 'attendance_event':
      return 'attendance_daily';
    case 'live_location_requests':
    case 'location_request':
    case 'live_location':
    case 'location':
      return 'live_location_request';
    case 'employee_device':
    case 'employee_devices':
    case 'devices':
      return 'device';
    default:
      return type;
  }
}

/** قراءة آمنة لحقل نصي من metadata الإشعار. */
function meta(item: NotificationItem, key: string): string | null {
  const bag = item.metadata as Record<string, unknown> | null | undefined;
  const value = bag?.[key];
  return typeof value === 'string' && value.trim() !== '' ? value : null;
}

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

/** يبني مساراً مع معاملات استعلام، متجاهلاً القيم الفارغة. */
function withParams(path: string, params: Record<string, string | null | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value != null && value !== '') search.set(key, value);
  }
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

/**
 * جذور صفحات كل مساحة عمل. `null` = المساحة لا تملك هذه الصفحة
 * (مثل النزاعات في HR، أو كل شيء عدا النزاعات في لجنة التظلمات).
 */
type PageKey =
  | 'requests'
  | 'attendanceDashboard'
  | 'attendanceDrilldown'
  | 'performance'
  | 'disputes'
  | 'officialFeed'
  | 'dailyReports'
  | 'finance'
  | 'devices'
  | 'liveLocation'
  | 'employees'
  | 'documents'
  | 'access'
  | 'settings';

const PAGES: Record<NotificationWorkspace, Partial<Record<PageKey, string>>> = {
  admin: {
    requests: '/admin/hr/requests',
    attendanceDashboard: '/admin/hr/attendance',
    attendanceDrilldown: '/admin/hr/attendance/details',
    performance: '/admin/performance/cycles',
    disputes: '/admin/disputes',
    officialFeed: '/admin/official-feed',
    dailyReports: '/admin/daily-reports',
    finance: '/admin/finance',
    devices: '/admin/hr/devices',
    liveLocation: '/admin/live-location',
    employees: '/admin/hr/employees',
    documents: '/admin/hr/documents',
    access: '/admin/access',
    settings: '/admin/settings',
  },
  hr: {
    requests: '/hr/requests',
    attendanceDashboard: '/hr/attendance',
    attendanceDrilldown: '/hr/attendance/details',
    performance: '/hr/performance',
    officialFeed: '/hr/official-feed',
    dailyReports: '/hr/daily-reports',
    devices: '/hr/devices',
    employees: '/hr/employees',
    documents: '/hr/documents',
  },
  committee: {
    disputes: '/committee/disputes',
  },
};

/**
 * يبني وجهة الإشعار لنوع كيان موحّد. يعود `null` إذا كانت المساحة لا تملك
 * الصفحة أو كان النوع معلوماتياً بلا وجهة.
 *
 * كل وجهة تحمل معرّف الحدث نفسه (`focus` أو `request` أو `case`) — الصفحات
 * تقرأ `focus` عبر useEntityFocus فتمرّر إليه وتُبرزه، بدل الاكتفاء بفتح
 * القائمة العامة.
 */
function buildTarget(type: string, item: NotificationItem, workspace: NotificationWorkspace): string | null {
  const pages = PAGES[workspace];
  const id = item.entityId ?? null;

  switch (type) {
    case 'request':
      return pages.requests ? withParams(pages.requests, { request: id }) : null;

    case 'requests_page':
      return pages.requests ?? null;

    case 'performance_page':
      return pages.performance ?? null;

    case 'dispute':
      return pages.disputes ? withParams(pages.disputes, { case: id }) : null;

    case 'announcement':
    case 'decision':
    case 'recognition':
      return pages.officialFeed ? withParams(pages.officialFeed, { focus: id }) : null;

    case 'daily_reports':
      return pages.dailyReports ? withParams(pages.dailyReports, { focus: id }) : null;

    case 'kpi':
      return pages.performance ? withParams(pages.performance, { focus: meta(item, 'evaluationId') ?? id }) : null;

    case 'instant_penalty':
      return pages.finance ? withParams(pages.finance, { tab: 'instant-penalties', focus: id }) : null;

    case 'fellowship_fund':
      return pages.finance ? withParams(pages.finance, { tab: 'fellowship-fund', focus: id }) : null;

    case 'device':
      return pages.devices ? withParams(pages.devices, { focus: meta(item, 'deviceId') ?? id }) : null;

    case 'live_location_request':
      return pages.liveLocation ? withParams(pages.liveLocation, { focus: id }) : null;

    case 'attendance_daily':
    case 'attendance_corrections':
    case 'overtime_records':
    case 'work_rosters':
    case 'punch_reminder': {
      // يوم الحدث نفسه — لا «اليوم» الافتراضي الذي كانت تفتحه الصفحة.
      const workDate = meta(item, 'workDate');
      const employeeId = meta(item, 'employeeId');
      if (pages.attendanceDrilldown && workDate && ISO_DATE.test(workDate)) {
        return withParams(pages.attendanceDrilldown, { category: 'scheduled', date: workDate, focus: employeeId });
      }
      return pages.attendanceDashboard ?? null;
    }

    case 'weekly_executive_summary': {
      // ملخص الأسبوع التنفيذي: يفتح التقرير التنفيذي على آخر يوم في الفترة.
      const endDate = meta(item, 'endDate');
      if (!pages.attendanceDashboard) return null;
      return withParams(pages.attendanceDashboard, { tab: 'executive', date: endDate && ISO_DATE.test(endDate) ? endDate : null });
    }

    case 'offboarding_cases':
      return pages.documents ? withParams(pages.documents, { tab: 'offboarding', focus: id }) : null;

    case 'break_glass_requests':
    case 'access_review_items':
      return pages.access ?? null;

    case 'privacy_requests':
      return pages.settings ?? pages.employees ?? null;

    default:
      return null;
  }
}

/**
 * يقرر الوجهة الفعلية لإشعار في لوحة الإدارة:
 * 1) actionUrl داخلي صالح ضمن مساحة عمل حقيقية → يُستخدم كما هو.
 * 2) رابط `/action/{kind}/{id}` (كامل أو مخصص) → يُحوَّل إلى نوع كيان.
 * 3) غير ذلك → يُركب من entityType + entityId + metadata.
 * 4) لا وجهة (إشعار معلوماتي مثل التنبيه الشامل) → null، ولا يُعرض زر فتح.
 */
export function notificationTargetPath(item: NotificationItem, workspace: NotificationWorkspace): string | null {
  const internalAction = isInternalAppPath(item.actionUrl) ? item.actionUrl : null;

  // actionUrl يحمل معلمة بنفسه (مثل /admin/disputes?case=…) → هو الأدق، يُستخدم كما هو.
  if (internalAction && internalAction.includes('?')) return internalAction;

  const fromEntity = canonicalEntityType(item.entityType);
  if (fromEntity) {
    const target = buildTarget(fromEntity, item, workspace);
    // الوجهة المبنية من الكيان أدق من actionUrl الذي يشير للقائمة العامة فقط.
    if (target) return target;
  }

  // احتياطي: بعض الإشعارات القديمة لا تحمل entity_type مفيداً لكن actionUrl
  // يحوي رابط الإجراء الموحّد — نستخرج النوع منه.
  const action = parseActionDeepLink(item.actionUrl);
  const fromAction = canonicalEntityType(action?.kind);
  if (fromAction && fromAction !== fromEntity) {
    const target = buildTarget(fromAction, { ...item, entityId: item.entityId ?? action?.id ?? null }, workspace);
    if (target) return target;
  }

  // آخر احتياطي: صفحة عامة صالحة داخل مساحة العمل خير من لا شيء.
  return internalAction;
}
