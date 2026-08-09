/// يسجّل أخطاء تطبيق Flutter في observability_events عبر edge function.
///
/// بديل داخلي لـ Crashlytics/Sentry — يُرسل الأخطاء للـ log-client-error
/// edge function التي تخزّنها في قاعدة البيانات. لا يتطلب أي حساب خارجي.
///
/// الاستخدام:
///   await CrashReporter.instance.captureError(error, stackTrace, context: 'login');
///
/// خصوصية: لا يُرسل أي PII — فقط رسالة الخطأ والـ stack واسم الشاشة.
library;

import 'dart:async';

import 'package:ahla_shabab_management_os/core/config/app_config.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// يسجّل الأخطاء في observability_events عبر edge function.
class CrashReporter {
  CrashReporter._();
  static final CrashReporter instance = CrashReporter._();

  bool _initialized = false;
  SupabaseClient? _client;
  final _queue = <_PendingReport>[];
  static const _maxQueueSize = 20;
  static const _minInterval = Duration(seconds: 2);
  DateTime? _lastSent;

  /// يُستدعى بعد Supabase.initialize — يربط بالعميل ويصرفّ التقارير المعلّقة.
  void initialize(SupabaseClient client) {
    _client = client;
    _initialized = true;
    _flushQueue();
  }

  /// يسجّل خطأ — fire-and-forget، لا يُعطّل التطبيق ولا يرمي استثناء.
  Future<void> captureError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, dynamic>? metadata,
  }) async {
    final report = _PendingReport(
      message: error.toString().substring(0, error.toString().length.clamp(0, 2000)),
      errorName: error.runtimeType.toString(),
      errorStack: stackTrace?.toString().substring(0, stackTrace.toString().length.clamp(0, 5000)),
      source: 'mobile:flutter',
      context: context,
      metadata: metadata,
    );

    if (!_initialized || _client == null) {
      if (_queue.length < _maxQueueSize) _queue.add(report);
      return;
    }

    // منع الإرسال المتكرر جداً (حلقة أخطاء لا نهائية)
    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < _minInterval) {
      if (_queue.length < _maxQueueSize) _queue.add(report);
      return;
    }
    _lastSent = now;

    await _send(report);
  }

  Future<void> _send(_PendingReport report) async {
    if (_client == null) return;
    try {
      final session = _client!.auth.currentSession;
      if (session == null) return; // لا نُرسل بدون جلسة مصادقة

      await _client!.functions.invoke(
        'log-client-error',
        body: {
          'level': 'error',
          'source': report.source,
          'eventType': 'error',
          'message': report.message,
          'errorName': report.errorName,
          'errorStack': report.errorStack,
          'metadata': {
            ...report.metadata ?? {},
            if (report.context != null) 'context': report.context,
            'environment': AppConfig.environment,
          },
        },
      );
    } catch (_) {
      // الرصد فشل صامتاً — لا نريد حلقة أخطاء
    }
  }

  Future<void> _flushQueue() async {
    while (_queue.isNotEmpty) {
      final report = _queue.removeAt(0);
      await _send(report);
    }
  }
}

class _PendingReport {
  final String message;
  final String errorName;
  final String? errorStack;
  final String source;
  final String? context;
  final Map<String, dynamic>? metadata;

  _PendingReport({
    required this.message,
    required this.errorName,
    this.errorStack,
    required this.source,
    this.context,
    this.metadata,
  });
}

/// يربط FlutterError.onError و PlatformDispatcher.instance.onError بـ CrashReporter.
/// يُستدعى في main() قبل runApp.
void setupGlobalErrorHandlers() {
  FlutterError.onError = (details) {
    if (kDebugMode) FlutterError.presentError(details);
    unawaited(
      CrashReporter.instance.captureError(
        details.exception,
        details.stack,
        context: 'flutter_error',
        metadata: {'library': details.library ?? 'unknown'},
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Uncaught application error: $error\n$stackTrace');
    }
    unawaited(
      CrashReporter.instance.captureError(
        error,
        stackTrace,
        context: 'platform_dispatcher',
      ),
    );
    return true;
  };
}
