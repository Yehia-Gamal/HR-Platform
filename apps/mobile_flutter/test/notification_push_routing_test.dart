import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// أشكال حمولة FCM الفعلية المرسلة من الإنتاج (آخر 7 أيام، 2026-09-26):
/// (entity_type, kind = metadata.kind ?? entity_type, deepLink).
/// كان النقر على بعضها يعلق على «جاري فتح الإشعار...» أو لا يفتح شيئاً.
const _id = '11111111-2222-4333-8444-555555555555';
const _payloads = [
  ['attendance_daily', 'attendance_daily', ''],
  ['instant_penalty', 'instant_penalty', ''],
  ['instant_penalty', 'instant_penalty', 'ahlashabab://action/finance?tab=instant-penalties'],
  ['instant_penalty_suspended', 'instant_penalty_suspended', ''],
  ['request', 'request', '/requests/$_id'],
  ['instant_penalty_doubled', 'instant_penalty_doubled', 'ahlashabab://action/finance?tab=instant-penalties'],
  ['punch_reminder', 'before_in', '/attendance'],
  ['fellowship_fund', 'fellowship_fund', 'ahlashabab://action/fellowship-fund'],
  ['punch_reminder', 'late_in', '/attendance'],
  ['broadcast_alert', 'broadcast_alert', ''],
  ['punch_reminder', 'before_out', '/attendance'],
  ['attendance_corrections', 'attendance_corrections', ''],
  ['weekly_executive_summary', 'weekly_executive_summary', 'ahlashabab://action/reports/attendance?start=2026-09-13&end=2026-09-19'],
  ['request', 'casual_leave_auto_approved', ''],
  ['instant_penalty_excuse_approved', 'instant_penalty_excuse_approved', ''],
  ['device', 'device_pending_approval', ''],
  ['association_project', 'project_submitted', ''],
];

/// نفس ترتيب القرار في PushNotificationService._routeFromMessage.
String _routeFor(Map<String, dynamic> data) {
  final deepLink = data['deepLink'] as String;
  if (deepLink.isNotEmpty) {
    final r = resolveRouteFromDeepLink(deepLink);
    if (r != '/') return r;
  }
  final r = resolveNotificationRouteFromData(data);
  return r == '/' ? '/action/notification/${data['notificationId']}' : r;
}

String _screenFor(String route) {
  final uri = Uri.parse(route);
  expect(uri.pathSegments.first, 'action', reason: route);
  final page = getDirectActionPage(
    kind: canonicalNotificationEntityType(uri.pathSegments[1]) ?? '',
    actionId: uri.pathSegments[2],
  );
  // null = مسار الـ RPC عبر شاشة «جاري فتح الإشعار...» — ممنوع لأي نوع فعلي.
  expect(page, isNotNull, reason: 'route $route would fall to the loader');
  return page.runtimeType.toString();
}

void main() {
  for (final withEntityType in [false, true]) {
    final label = withEntityType ? 'dispatcher يرسل entityType' : 'dispatcher قديم (kind فقط)';
    test('كل حمولة إنتاج تفتح شاشة فعلية — $label', () {
      for (final p in _payloads) {
        final data = <String, dynamic>{
          'kind': p[1],
          'entityId': _id,
          'requestId': _id,
          'deepLink': p[2],
          'notificationId': 'n-${p[0]}',
          if (withEntityType) 'entityType': p[0],
        };
        _screenFor(_routeFor(data));
      }
    });
  }

  test('الأنواع الفرعية في kind تُطبَّع إلى نوع كيان ذي صفحة', () {
    expect(canonicalNotificationEntityType('late_in'), 'attendance');
    expect(canonicalNotificationEntityType('before_out'), 'attendance');
    expect(canonicalNotificationEntityType('casual_leave_auto_approved'), 'request');
    expect(canonicalNotificationEntityType('instant_penalty_excuse_approved'), 'instant_penalty');
    expect(canonicalNotificationEntityType('device_pending_approval'), 'device');
  });

  test('الإشعار الذي يحمل entityType يفتح صفحة كيانه لا القائمة العامة', () {
    final route = _routeFor({
      'kind': 'casual_leave_auto_approved',
      'entityType': 'request',
      'entityId': _id,
      'deepLink': '',
      'notificationId': 'n1',
    });
    expect(route, '/action/request/$_id');
    expect(_screenFor(route), 'MobileRequestDetailPage');
  });

  test('MobileActionItem مفتاح مستقر لمزوّد family (لا تعليق في التحميل)', () {
    MobileActionItem make() => const MobileActionItem(
      id: _id, kind: 'recognition', title: '', subtitle: null,
      priority: 'normal', status: '', dueAt: null,
    );
    expect(make(), equals(make()));
    expect(make().hashCode, make().hashCode);
  });
}
