import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/core/notifications/notification_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('كتم الإشعارات', () {
    test('المشاريع قناة مستقلة قابلة للكتم بنفس النوع الموحّد للإشعار', () {
      expect(NotificationPreferences.mutableChannels['association_project'], 'المشاريع');
      // نوع الكيان الذي يرسله notification-dispatcher يُوحَّد إلى نفس مفتاح القناة
      expect(canonicalNotificationEntityType('association_project'), 'association_project');
      expect(canonicalNotificationEntityType('project_approved'), 'association_project');

      const prefs = NotificationPreferences(mutedKinds: {'association_project'});
      expect(prefs.shouldSuppress('association_project', subKind: 'project_submitted'), isTrue);
    });

    test('تعثّر المشروع وتأخر خطوته لا يُكتمان بكتم القناة', () {
      const prefs = NotificationPreferences(mutedKinds: {'association_project'});
      expect(prefs.shouldSuppress('association_project', subKind: 'project_stalled'), isFalse);
      expect(prefs.shouldSuppress('association_project', subKind: 'project_step_overdue'), isFalse);
    });

    test('ساعات الهدوء تسري على التنبيهات الإلزامية، لا على طلبات الموقع', () {
      // نافذة هدوء تغطي اليوم كله
      const quiet = NotificationPreferences(
        quietHoursEnabled: true,
        quietStartMinutes: 0,
        quietEndMinutes: 24 * 60,
      );
      expect(quiet.shouldSuppress('association_project', subKind: 'project_stalled'), isTrue);
      expect(quiet.shouldSuppress('live_location_request'), isFalse);
    });
  });
}
