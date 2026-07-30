/// يربط بيانات الإشعار (payload) بمسار GoRouter للتنقل العميق.
///
/// الأنواع المدعومة:
/// - request_decision → /action/request/{id}
/// - kpi_evaluation   → /action/kpi/{id}
/// - attendance_alert → /action/attendance/{id}
/// - location_request → /action/location/{id}
/// - dispute          → /action/dispute/{id}
/// - task             → /action/task/{id}
/// - announcement     → /action/announcement/{id}
/// - general          → / (الرئيسية)
library;

/// يحوّل نوع الإشعار ومعرّف الكيان إلى مسار GoRouter.
///
/// يُستخدم من [NotificationService] ومن صفحة الإشعارات
/// لتحويل الضغط على الإشعار إلى تنقل داخل التطبيق.
///
/// إذا كان النوع غير معروف أو المعرّف فارغ يعود إلى `/` (الرئيسية).
String resolveNotificationRoute({
  required String? type,
  required String? entityId,
}) {
  if (entityId == null || entityId.isEmpty) return '/';

  return switch (type) {
    'request' || 'request_decision' => '/action/request/$entityId',
    'kpi' || 'kpi_evaluation'       => '/action/kpi/$entityId',
    'attendance' || 'attendance_alert' => '/action/attendance/$entityId',
    'location' || 'location_request' => '/action/location/$entityId',
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
/// الأولوية لـ `deepLink` إن وُجد.
String resolveNotificationRouteFromData(Map<String, dynamic> data) {
  // أولوية 1: رابط عميق صريح.
  final deepLink = data['deepLink'] as String?;
  if (deepLink != null && deepLink.isNotEmpty) {
    // إذا كان رابطاً كاملاً (يحتوي ://) نستخرج المسار فقط.
    if (deepLink.contains('://')) {
      try {
        final uri = Uri.parse(deepLink);
        final segments = uri.pathSegments;
        final parts = [uri.host, ...segments];
        final idx = parts.indexOf('action');
        if (idx >= 0 && parts.length >= idx + 3) {
          return '/action/${parts[idx + 1]}/${parts[idx + 2]}';
        }
      } catch (_) {
        // تجاهل الروابط غير الصالحة.
      }
    }
    // إذا كان مساراً نسبياً (يبدأ بـ /).
    if (deepLink.startsWith('/')) return deepLink;
  }

  // أولوية 2: حقول entityType + entityId.
  final entityType = data['entityType'] as String? ?? data['kind'] as String?;
  final entityId = data['entityId'] as String? ?? data['requestId'] as String?;
  return resolveNotificationRoute(type: entityType, entityId: entityId);
}
