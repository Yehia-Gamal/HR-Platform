import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';

/// تنظيف الجلسة عند تسجيل الخروج.
///
/// [userId]: معرّف المستخدم الخارج — يُمرَّر صراحةً لتجنّب سباقات التزامن.
/// جميع العمليات best-effort: لا يُرمى أي استثناء.
Future<void> cleanupOnSignOut({String? userId}) async {
  try {
    await OfflineCache.instance.clearAllForUser(userId);
    OfflineCache.instance.setCurrentUser(null);
  } catch (_) {}
  try {
    await OfflineSyncQueue.instance.clear();
  } catch (_) {}
  try {
    await FirebaseMessaging.instance.deleteToken();
  } catch (_) {}
  if (kDebugMode) {
    debugPrint('[session_cleanup] تم تنظيف الجلسة عند الخروج.');
  }
}
