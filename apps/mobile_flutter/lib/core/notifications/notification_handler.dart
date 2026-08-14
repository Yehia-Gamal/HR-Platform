/// يربط بيانات الإشعار (payload) بمسار GoRouter للتنقل العميق.
///
/// الأنواع المدعومة (kind في `/action/kind/id`):
/// - request / request_decision           → طلبات الموظف
/// - kpi / kpi_evaluation                 → تقييمات الأداء
/// - attendance / attendance_alert / punch_reminder → الحضور والبصمة
/// - location / location_request / live_location_request → طلبات الموقع
/// - dispute                              → النزاعات
/// - task                                 → المهام
/// - decision                             → القرارات
/// - announcement                         → الإعلانات
/// - recognition                          → التقدير
library;

final RegExp _uuidRegExp = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// محلل موحّد للروابط العميقة: يستخرج مسار GoRouter من رابط عميق
/// (كامل مثل https://host/action/location/{id} أو نسبي مثل /action/request/{id})
/// مع تحقق أمني من أن المعرّف UUID صالح — يمنع حقن مسارات عشوائية.
///
/// يعود `/` للروابط غير الصالحة.
String resolveRouteFromDeepLink(String deepLink) {
  if (deepLink.isEmpty) return '/';
  try {
    final uri = Uri.parse(deepLink);
    final segments = uri.pathSegments;
    final parts = deepLink.contains('://')
        ? [uri.host, ...segments]
        : segments;

    // أولوية 1: مسار /action/{kind}/{id} القياسي.
    final idx = parts.indexOf('action');
    if (idx >= 0 && parts.length >= idx + 3) {
      final kind = parts[idx + 1];
      final id = parts[idx + 2];
      // UUID صالح → اقبل أي kind.
      if (_uuidRegExp.hasMatch(id)) return _withQuery('/action/$kind/$id', uri);
      // معرّف غير UUID (مثل تاريخ attendance) → اقبل فقط للأنواع المعروفة.
      if (id.isNotEmpty && _isKnownActionKind(kind)) {
        return _withQuery('/action/$kind/$id', uri);
      }
    }

    // أولوية 2: مسارات قديمة مثل /requests/{uuid} أو /hr/requests/{uuid}
    // نبحث عن UUID في آخر جزء ونحوّل بادئة المسار إلى kind.
    if (parts.isNotEmpty) {
      final lastPart = parts.last;
      if (_uuidRegExp.hasMatch(lastPart)) {
        final prefix = parts.length > 1
            ? parts.sublist(0, parts.length - 1).join('/')
            : '';
        final legacyKind = _kindFromLegacyPath('/$prefix');
        if (legacyKind != null) {
          return _withQuery('/action/$legacyKind/$lastPart', uri);
        }
      }
    }
  } catch (_) {
    // روابط غير صالحة → الرئيسية.
  }
  return '/';
}

/// V25: يُلحق معاملات الـ query (مثل action=reject و notification_id)
/// بمسار GoRouter — كانت تُفقد في المحلل القديم فكان زر "رفض الطلب"
/// في شاشة Kotlin يفتح Flutter دون أن يصل معامل الرفض.
String _withQuery(String route, Uri uri) {
  final query = uri.query;
  if (query.isEmpty) return route;
  return '$route?$query';
}

/// هل النوع (kind) معروف في خريطة التنقل؟
bool _isKnownActionKind(String kind) {
  return switch (kind) {
    'request' || 'request_decision' || 'kpi' || 'kpi_evaluation' ||
    'attendance' || 'attendance_alert' || 'punch_reminder' ||
    'location' || 'location_request' || 'live_location_request' ||
    'dispute' || 'task' || 'decision' || 'announcement' || 'recognition'
        => true,
    _ => false,
  };
}

/// يحوّل نوع الإشعار ومعرّف الكيان إلى مسار GoRouter.
///
/// يُستخدم من [NotificationService] ومن صفحة الإشعارات
/// لتحويل الضغط على الإشعار إلى تنقل داخل التطبيق.
///
/// **مهم: يطابق القيم المرسلة من الـ Backend** (entity_type في جدول notifications
/// وkind في FCM payload)، ويطابق أيضاً قائمة resolve_mobile_action_target في
/// migration 0087 (request, kpi, decision, live_location_request) مع fallback
/// للأنواع الأخرى التي تعمل عبر RPC get_mobile_action_target العام.
///
/// إذا كان النوع غير معروف أو المعرّف فارغ أو غير صالح يعود إلى `/`.
String resolveNotificationRoute({
  required String? type,
  required String? entityId,
}) {
  if (entityId == null || entityId.isEmpty) return '/';
  if (!_uuidRegExp.hasMatch(entityId)) return '/';

  return switch (type) {
    'request' || 'request_decision' => '/action/request/$entityId',
    'kpi' || 'kpi_evaluation'       => '/action/kpi/$entityId',
    'attendance' || 'attendance_alert' || 'punch_reminder' => '/action/attendance/$entityId',
    'location' || 'location_request' || 'live_location_request' => '/action/live_location_request/$entityId',
    'dispute'                        => '/action/dispute/$entityId',
    'task'                           => '/action/task/$entityId',
    'decision'                       => '/action/decision/$entityId',
    'announcement'                   => '/action/announcement/$entityId',
    'recognition'                    => '/action/recognition/$entityId',
    // ─── أنواع جديدة من migrations 0316-0328 ───
    // الإشعارات التالية لا تفتح صفحة محددة بل تُظهر المستخدم على القائمة المناسبة:
    // 'daily_report' / 'daily_report_like' / 'daily_report_comment' → تقارير الجميع
    // 'attendance_manager_notify' → لا إجراء مباشر (إشعار معلوماتي)
    // نُرجع '/' لأنها إشعارات معلوماتية بدون deep link محدد.
    'daily_report' || 'daily_report_like' || 'daily_report_comment' || 'attendance_manager_notify' => '/',
    _                                => '/',
  };
}

/// يستخرج مسار التنقل من بيانات الإشعار (data map) مباشرة.
///
/// يدعم حقلي `deepLink` (رابط كامل) و `entityType`/`entityId` (حقول منفصلة).
/// كما يتعامل مع روابط الـ action_url المخزنة قديماً (مثل `/location-requests`)
/// بمحاولة دمجها مع entityId/requestId لبناء `/action/{kind}/{id}` صالح.
///
/// الأولوية لـ `deepLink` إن وُجد — يُمرَّر عبر المحلل الموحّد
/// [resolveRouteFromDeepLink] للتحقق الأمني من UUID.
String resolveNotificationRouteFromData(Map<String, dynamic> data) {
  // أولوية 1: رابط عميق صريح (يتضمن التحقق الأمني للمعرّف).
  final deepLink = data['deepLink'] as String?;
  if (deepLink != null && deepLink.isNotEmpty) {
    final route = resolveRouteFromDeepLink(deepLink);
    if (route != '/') return route;
    // إن كان الرابط موجوداً لكن غير قابل للحل (legacy أو بدون معرّف)،
    // نُكمل ونحاول بناء المسار من الحقول المنفصلة.
  }

  // أولوية 2: action_url قديم من قاعدة البيانات + حقول المعرّف.
  // بعض الإشعارات القديمة تخزن action_url = '/location-requests' بدون معرّف.
  final rawActionUrl = (data['action_url'] ?? data['actionUrl']) as String?;
  final entityId =
      data['entityId'] as String? ??
      data['requestId'] as String? ??
      (data['metadata'] is Map
          ? ((data['metadata'] as Map)['entityId'] ??
                (data['metadata'] as Map)['requestId'])
              as String?
          : null);

  if (rawActionUrl != null && rawActionUrl.isNotEmpty) {
    final legacyKind = _kindFromLegacyPath(rawActionUrl);
    if (legacyKind != null &&
        entityId != null &&
        _uuidRegExp.hasMatch(entityId)) {
      return '/action/$legacyKind/$entityId';
    }
  }

  // أولوية 3: حقول entityType + entityId.
  final entityType = data['entityType'] as String? ?? data['kind'] as String?;
  return resolveNotificationRoute(type: entityType, entityId: entityId);
}

/// يحوّل مسار action_url القديم (web/admin paths) إلى kind في التطبيق.
/// يُستخدم لمعالجة الإشعارات المخزّنة قبل توحيد بروتوكول deep link.
String? _kindFromLegacyPath(String actionUrl) {
  final normalized = actionUrl.toLowerCase().trim();
  return switch (normalized) {
    '/location-requests' => 'live_location_request',
    '/attendance' => 'attendance',
    '/attendance-requests' => 'attendance',
    '/requests' => 'request',
    '/hr/requests' => 'request',
    '/kpi' => 'kpi',
    '/kpi-evaluations' => 'kpi',
    '/disputes' => 'dispute',
    '/tasks' => 'task',
    '/decisions' => 'decision',
    '/announcements' => 'announcement',
    '/recognitions' => 'recognition',
    _ => null,
  };
}
