import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';

/// تنظيف الجلسة عند تسجيل الخروج.
///
/// يُمسح الكاش المحلي وطابور المزامنة ويُحذف رمز FCM
/// لمنع استقبال إشعارات بعد الخروج من الحساب.
///
/// [userId]: معرّف المستخدم الخارج — يُمرَّر صراحةً لتجنّب أي سباق تزامن
/// بين إعادة ضبط الجلسة وحذف مفاتيح الكاش. مرِّر null إذا لم يكن متاحاً.
///
/// جميع العمليات best-effort: لا يُرمى أي استثناء.
Future<void> cleanupOnSignOut({String? userId}) async {
  try {
    await OfflineCache.instance.clearAllForUser(userId);
    OfflineCache.instance.setCurrentUser(null);
  } catch (_) {
    // Best-effort.
  }
  try {
    await OfflineSyncQueue.instance.clear();
  } catch (_) {
    // Best-effort.
  }
  try {
    await FirebaseMessaging.instance.deleteToken();
  } catch (_) {
    // Firebase قد لا يكون مهيأ (بدون google-services.json).
  }
  if (kDebugMode) {
    debugPrint('[session_cleanup] تم تنظيف الجلسة عند الخروج.');
  }
}
