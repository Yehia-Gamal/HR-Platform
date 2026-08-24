import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// مزوّد شارة الإشعارات — يتتبع عدد الإشعارات غير المقروءة ويوفر
// واجهة لتحديد الإشعارات كمقروءة.
//
// يُستخدم في شريط التنقل (NavigationBar) وأيقونة الإشعارات في AppBar.
// ---------------------------------------------------------------------------

/// عدد الإشعارات غير المقروءة — مشتق من [myNotificationsProvider].
///
/// يُحدَّث تلقائياً عند تحميل أو إبطال قائمة الإشعارات.
///
/// استخدام:
/// ```dart
/// final count = ref.watch(unreadNotificationCountProvider);
/// count.when(
///   data: (n) => Badge(label: Text('$n'), child: icon),
///   ...
/// );
/// ```
final unreadNotificationCountProvider = Provider<AsyncValue<int>>((ref) {
  final notifications = ref.watch(myNotificationsProvider);
  return notifications.whenData(
    (items) => items.where((item) => !item.isRead).length,
  );
});

/// قائمة الإشعارات غير المقروءة فقط.
final unreadNotificationsProvider =
    Provider<AsyncValue<List<MobileNotificationItem>>>((ref) {
      final notifications = ref.watch(myNotificationsProvider);
      return notifications.whenData(
        (items) => items.where((item) => !item.isRead).toList(growable: false),
      );
    });

/// مزوّد شارة الإشعارات — يجمع العدد والإجراءات في واجهة واحدة.
///
/// يوفر:
/// - عدد الإشعارات غير المقروءة كـ state.
/// - `markAsRead(id)` — تحديد إشعار واحد كمقروء.
/// - `markAllAsRead()` — تحديد جميع الإشعارات كمقروءة.
/// - `refresh()` — إعادة تحميل قائمة الإشعارات.
final notificationBadgeProvider =
    NotifierProvider<NotificationBadgeController, int>(
      NotificationBadgeController.new,
    );

class NotificationBadgeController extends Notifier<int> {
  @override
  int build() {
    // نستمع لقائمة الإشعارات ونحسب غير المقروءة.
    final notifications = ref.watch(myNotificationsProvider);
    return notifications.maybeWhen(
      data: (items) => items.where((item) => !item.isRead).length,
      // أثناء التحميل أو الخطأ نعود بـ 0 (لا يمكن الوصول لـ state في build).
      orElse: () => 0,
    );
  }

  /// تحديد إشعار واحد كمقروء بالمعرّف.
  Future<void> markAsRead(String notificationId) async {
    try {
      await ref.read(mobileCommandsProvider).markNotificationsRead([
        notificationId,
      ]);
      // إبطال القائمة لإعادة الحساب.
      ref.invalidate(myNotificationsProvider);
    } catch (_) {
      // فشل صامت — لا نكسر الواجهة.
    }
  }

  /// تحديد جميع الإشعارات كمقروءة.
  Future<void> markAllAsRead() async {
    try {
      await ref.read(mobileCommandsProvider).markNotificationsRead();
      ref.invalidate(myNotificationsProvider);
      // تحديث فوري للشارة.
      state = 0;
    } catch (_) {
      // فشل صامت.
    }
  }

  /// إعادة تحميل قائمة الإشعارات (مفيد بعد فتح التطبيق من الخلفية).
  void refresh() {
    ref.invalidate(myNotificationsProvider);
  }
}
