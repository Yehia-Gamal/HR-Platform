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

/// يطبّع أسماء entity_type المخزّنة في قاعدة البيانات إلى الأسماء الموحّدة
/// التي يفهمها التطبيق والـ RPC resolve_mobile_action_target (0435).
///
/// كانت دوال الإشعارات تخزّن صيغاً مختلفة عن قائمة الموبايل:
/// live_location_requests (الجمع)، kpi_evaluation، attendance_corrections،
/// work_rosters، attendance_daily، attendance_event، requests، dispute_case —
/// فكان النقر على الإشعار لا يستجيب (لا فتح مسار ولا تعليم مقروء).
String? canonicalNotificationEntityType(String? raw) {
  if (raw == null) return null;
  // كل متغيرات الغرامة الفورية (doubled/suspended/excuse_approved/…) صفحتها واحدة.
  if (raw.startsWith('instant_penalty')) return 'instant_penalty';
  // أنواع فرعية تُرسل في حقل kind (من metadata.kind) بدل نوع الكيان — كان
  // النقر عليها في الهاتف لا يفتح شيئاً (لا تطابق أي مسار).
  if (raw.startsWith('device_')) return 'device';
  return _canonicalEntityTypeExact(raw);
}

String? _canonicalEntityTypeExact(String raw) => switch (raw) {
  'before_in' ||
  'late_in' ||
  'before_out' ||
  'late_out' ||
  'missed_in' ||
  'missed_out' ||
  'weekly_executive_summary' ||
  'attendance_manager_notify' => 'attendance',
  'casual_leave_auto_approved' ||
  'request_approval_needed' ||
  'mission' ||
  'missions' ||
  'leave' ||
  'leaves' ||
  'permission' ||
  'permissions' ||
  'team_requests' ||
  'my_requests' ||
  'urgent_exec' => 'request',
  'live_location_requests' => 'live_location_request',
  'kpi_evaluation' => 'kpi',
  'requests' => 'request',
  'request_decision' => 'request',
  'dispute_case' || 'disputes' => 'dispute',
  'attendance_corrections' ||
  'attendance_correction' => 'attendance_correction',
  'attendance_daily' ||
  'attendance_event' ||
  'overtime_records' ||
  'work_rosters' ||
  'attendance_alert' ||
  'punch_reminder' => 'attendance',
  'daily_reports' ||
  'daily_report_like' ||
  'daily_report_comment' => 'daily_report',
  'announcements' => 'announcement',
  'decisions' => 'decision',
  'employee_device' || 'employee_devices' || 'devices' => 'device',
  'fellowship' || 'fellowship_fund' => 'fellowship_fund',
  'association_projects' ||
  'association_project' ||
  'projects' ||
  'project' ||
  'project_submitted' ||
  'project_approved' ||
  'project_rejected' => 'association_project',
  'tasks' => 'task',
  'notifications' => 'notification',
  _ => raw,
};

/// محلل موحّد للروابط العميقة: يستخرج مسار GoRouter من رابط عميق
/// (كامل مثل https://host/action/location/{id} أو نسبي مثل /action/request/{id})
/// مع تحقق أمني من أن المعرّف UUID صالح أو من مسار معروف — يمنع حقن مسارات عشوائية.
///
/// يعود `/` للروابط غير الصالحة.
String resolveRouteFromDeepLink(String deepLink) {
  if (deepLink.isEmpty) return '/';
  try {
    final uri = Uri.parse(deepLink);
    final segments = uri.pathSegments;
    final parts = deepLink.contains('://') ? [uri.host, ...segments] : segments;

    // أولوية 1: مسار /action/{kind}/{id} القياسي.
    final idx = parts.indexOf('action');
    if (idx >= 0 && parts.length >= idx + 3) {
      final kind = parts[idx + 1];
      final id = parts[idx + 2];
      // UUID صالح → اقبل أي kind.
      if (_uuidRegExp.hasMatch(id)) return _withQuery('/action/$kind/$id', uri);
      // معرّف غير UUID (مثل تاريخ attendance أو default) → اقبل فقط للأنواع المعروفة.
      if (id.isNotEmpty && _isKnownActionKind(kind)) {
        return _withQuery('/action/$kind/$id', uri);
      }
    }

    // روابط خاصة دون معرّف صريح (مثل /action/finance أو /action/attendance)
    if (idx >= 0 && parts.length >= idx + 2) {
      final target = parts[idx + 1];
      if (target == 'finance' ||
          target == 'instant-penalties' ||
          target == 'instant_penalty') {
        return _withQuery('/action/instant_penalty/default', uri);
      }
      if (target == 'fellowship-fund' ||
          target == 'fellowship' ||
          target == 'fellowship_fund') {
        return _withQuery('/action/fellowship_fund/default', uri);
      }
      if (target == 'attendance' || target == 'attendance_services') {
        final date = uri.queryParameters['date'];
        final id = (date != null && date.isNotEmpty) ? date : 'default';
        return _withQuery('/action/attendance/$id', uri);
      }
      if (target == 'reports' ||
          target == 'reports/attendance' ||
          target == 'daily_report' ||
          target == 'daily-reports') {
        return _withQuery('/action/daily_report/default', uri);
      }
      if (target == 'requests' || target == 'request') {
        return _withQuery('/action/request/default', uri);
      }
      if (target == 'notifications' || target == 'notification') {
        return _withQuery('/action/notification/default', uri);
      }
      if (target == 'tasks' || target == 'task') {
        return _withQuery('/action/task/default', uri);
      }
      if (target == 'device' || target == 'devices') {
        return _withQuery('/action/device/default', uri);
      }
      if (target == 'association_project' ||
          target == 'association_projects' ||
          target == 'projects' ||
          target == 'project') {
        return _withQuery('/action/association_project/default', uri);
      }
    }

    // أولوية 2: مسارات قديمة مثل /requests/{uuid} أو https://host/requests/{uuid}
    // نبحث عن UUID في آخر جزء ونحوّل بادئة المسار (من segments وليس parts لتجنب الـ host) إلى kind.
    if (segments.isNotEmpty) {
      final lastPart = segments.last;
      if (_uuidRegExp.hasMatch(lastPart)) {
        final prefix = segments.length > 1
            ? segments.sublist(0, segments.length - 1).join('/')
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
    'request' ||
    'request_decision' ||
    'kpi' ||
    'kpi_evaluation' ||
    'attendance' ||
    'attendance_alert' ||
    'attendance_correction' ||
    'attendance_corrections' ||
    'punch_reminder' ||
    'location' ||
    'location_request' ||
    'live_location_request' ||
    'dispute' ||
    'task' ||
    'decision' ||
    'announcement' ||
    'recognition' ||
    'instant_penalty' ||
    'daily_report' ||
    'device' ||
    'association_project' ||
    'notification' ||
    'fellowship_fund' => true,
    _ => false,
  };
}

/// يحوّل نوع الإشعار ومعرّف الكيان إلى مسار GoRouter.
///
/// يُستخدم من [NotificationService] ومن صفحة الإشعارات
/// لتحويل الضغط على الإشعار إلى تنقل داخل التطبيق.
String resolveNotificationRoute({
  required String? type,
  required String? entityId,
}) {
  final cleanId = (entityId == null || entityId.isEmpty) ? 'default' : entityId;
  final isValidId = cleanId == 'default' ||
      _uuidRegExp.hasMatch(cleanId) ||
      cleanId.length >= 8;
  if (!isValidId) return '/action/notification/default';

  // تطبيع اسم النوع أولاً — الخلفية تخزّن صيغاً متعددة لنفس الكيان (0435).
  final canonical = canonicalNotificationEntityType(type);

  return switch (canonical) {
    'request' => '/action/request/$cleanId',
    'kpi' => '/action/kpi/$cleanId',
    'attendance_correction' => '/action/attendance_correction/$cleanId',
    'attendance' => '/action/attendance/$cleanId',
    'location' ||
    'location_request' ||
    'live_location_request' => '/action/live_location_request/$cleanId',
    'dispute' => '/action/dispute/$cleanId',
    'task' => '/action/task/$cleanId',
    'decision' => '/action/decision/$cleanId',
    'announcement' => '/action/announcement/$cleanId',
    'recognition' => '/action/recognition/$cleanId',
    'instant_penalty' => '/action/instant_penalty/$cleanId',
    'daily_report' => '/action/daily_report/$cleanId',
    'device' => '/action/device/$cleanId',
    'fellowship_fund' => '/action/fellowship_fund/$cleanId',
    'association_project' => '/action/association_project/$cleanId',
    'notification' ||
    'daily_report_like' ||
    'daily_report_comment' ||
    'attendance_manager_notify' => '/action/notification/$cleanId',
    _ => '/action/notification/$cleanId',
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
    '/finance' || '/instant-penalties' => 'instant_penalty',
    '/daily-reports' => 'daily_report',
    '/fellowship-fund' => 'fellowship_fund',
    _ => null,
  };
}
