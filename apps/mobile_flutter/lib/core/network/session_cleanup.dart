import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';

/// تنظيف الجلسة عند تسجيل الخروج.
///
/// يُمسح الكاش المحلي وطابور المزامنة ويُحذف رمز FCM
/// لمنع استقبال إشعارات بعد الخروج من الحساب.
///
/// جميع العمليات best-effort: لا يُرمى أي استثناء.
Future<void> cleanupOnSignOut() async {
  try {
    await OfflineCache.instance.clearAll();
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
