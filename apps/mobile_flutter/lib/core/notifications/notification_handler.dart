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
    final idx = parts.indexOf('action');
    if (idx >= 0 && parts.length >= idx + 3) {
      final kind = parts[idx + 1];
      final id = parts[idx + 2];
      if (!_uuidRegExp.hasMatch(id)) return '/';
      return '/action/$kind/$id';
    }
  } catch (_) {
    // روابط غير صالحة → الرئيسية.
  }
  return '/';
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
    _                                => '/',
  };
}

/// يستخرج مسار التنقل من بيانات الإشعار (data map) مباشرة.
///
/// يدعم حقلي `deepLink` (رابط كامل) و `entityType`/`entityId` (حقول منفصلة).
/// الأولوية لـ `deepLink` إن وُجد — يُمرَّر عبر المحلل الموحّد
/// [resolveRouteFromDeepLink] للتحقق الأمني من UUID.
String resolveNotificationRouteFromData(Map<String, dynamic> data) {
  // أولوية 1: رابط عميق صريح (يتضمن التحقق الأمني للمعرّف).
  final deepLink = data['deepLink'] as String?;
  if (deepLink != null && deepLink.isNotEmpty) {
    final route = resolveRouteFromDeepLink(deepLink);
    if (route != '/') return route;
  }

  // أولوية 2: حقول entityType + entityId.
  final entityType = data['entityType'] as String? ?? data['kind'] as String?;
  final entityId = data['entityId'] as String? ?? data['requestId'] as String?;
  return resolveNotificationRoute(type: entityType, entityId: entityId);
}
