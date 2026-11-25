import 'dart:async';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// تنظيف الجلسة عند تسجيل الخروج.
///
/// [userId]: معرّف المستخدم الخارج — يُمرَّر صراحةً لتجنّب سباقات التزامن.
/// جميع العمليات best-effort: لا يُرمى أي استثناء.
Future<void> cleanupOnSignOut({String? userId}) async {
  try {
    if (userId != null) await OfflineCache.instance.clearAllForUser(userId);
  } catch (error, stackTrace) {
    unawaited(
      CrashReporter.instance.captureError(
        error,
        stackTrace,
        context: 'session_cleanup_cache',
      ),
    );
  }
  try {
    if (userId != null) await OfflineSyncQueue.forUser(userId).clear();
  } catch (error, stackTrace) {
    unawaited(
      CrashReporter.instance.captureError(
        error,
        stackTrace,
        context: 'session_cleanup_queue',
      ),
    );
  }
  try {
    await FirebaseMessaging.instance.deleteToken();
  } catch (error, stackTrace) {
    unawaited(
      CrashReporter.instance.captureError(
        error,
        stackTrace,
        context: 'session_cleanup_fcm',
      ),
    );
  }
  if (kDebugMode) {
    debugPrint('[session_cleanup] تم تنظيف الجلسة عند الخروج.');
  }
}
