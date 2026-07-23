import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_probe.dart';

enum ConnectivityState { online, offline, reconnecting, serverUnavailable }

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, ConnectivityState>(
      ConnectivityNotifier.new,
    );

class ConnectivityNotifier extends Notifier<ConnectivityState> {
  Timer? _timer;
  bool _wasOffline = false;

  @override
  ConnectivityState build() {
    _start();
    ref.onDispose(() {
      _timer?.cancel();
    });
    return ConnectivityState.online;
  }

  void _start() {
    unawaited(_check());
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _check());
  }

  Future<void> _check() async {
    try {
      final connected = await hasNetworkConnection().timeout(
        const Duration(seconds: 5),
      );
      if (connected) {
        if (_wasOffline) {
          state = ConnectivityState.reconnecting;
          _wasOffline = false;
          Future<void>.delayed(const Duration(seconds: 2), () {
            if (ref.mounted) state = ConnectivityState.online;
          });
        } else if (state != ConnectivityState.reconnecting) {
          state = ConnectivityState.online;
        }
      } else {
        _wasOffline = true;
        state = ConnectivityState.offline;
      }
    } on SocketException {
      _wasOffline = true;
      state = ConnectivityState.offline;
    } on TimeoutException {
      _wasOffline = true;
      state = ConnectivityState.offline;
    } catch (_) {
      _wasOffline = true;
      state = ConnectivityState.offline;
    }
  }

  Future<void> recheck() => _check();
}

String humanizeError(Object error, [StackTrace? stack]) {
  if (kDebugMode) {
    debugPrint('[ErrorHumanizer] $error\n${stack ?? ''}');
  }

  final msg = error.toString();

  if (error is SocketException || msg.contains('Failed host lookup')) {
    return 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وأعد المحاولة.';
  }
  if (msg.contains('AuthRetryableFetchException') ||
      msg.contains('ClientException')) {
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وأعد المحاولة.';
  }
  if (msg.contains('AuthApiException') && msg.contains('refresh_token')) {
    return 'انتهت صلاحية الجلسة. سجّل الدخول من جديد.';
  }
  if (error is TimeoutException || msg.contains('TimeoutException')) {
    return 'استغرق الطلب وقتًا طويلًا. تحقق من الاتصال وأعد المحاولة.';
  }

  if (error is PostgrestException) {
    return _humanizePostgrest(error);
  }
  if (msg.contains('PGRST')) {
    return 'تعذر حفظ العملية حاليًا. أعد المحاولة بعد لحظات.';
  }

  if (msg.contains('device_not_active') ||
      msg.contains('credential_not_found')) {
    return 'هذا الجهاز غير معتمد للحضور. حدّث حالة الأجهزة أو تواصل مع المسؤول.';
  }
  if (msg.contains('video_required')) {
    return 'يجب تسجيل فيديو التحقق قبل إكمال هذا الطلب.';
  }
  if (msg.contains('duplicate_attendance_event')) {
    return 'تم تسجيل هذه العملية بالفعل.';
  }

  if (error is FunctionException) {
    return _humanizeFunctionError(error);
  }

  if (msg.contains('CameraException') || msg.contains('SecurityException')) {
    return 'تعذر تشغيل الكاميرا. تحقق من صلاحية الكاميرا في إعدادات التطبيق.';
  }

  if (msg.contains('خدمة الموقع غير مفعلة')) {
    return 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
  }
  if (msg.contains('صلاحية الموقع مرفوضة')) {
    return 'صلاحية الموقع مرفوضة. افتح إعدادات التطبيق لتفعيلها.';
  }
  if (msg.contains('دقة الموقع')) {
    return msg;
  }

  if (error is StateError) {
    final stateMsg = error.message;
    if (_isArabic(stateMsg)) return stateMsg;
    return 'تعذر إكمال العملية. أعد المحاولة.';
  }

  if (_isArabic(msg)) {
    return msg
        .replaceFirst(
          RegExp(r'^(StateError|Exception|FormatException):\s*'),
          '',
        )
        .trim();
  }

  return 'حدث خطأ غير متوقع. أعد المحاولة أو تواصل مع المسؤول.';
}

String _humanizePostgrest(PostgrestException error) {
  final code = error.code;
  switch (code) {
    case '42703':
      return 'تعذر تحميل البيانات. تواصل مع مسؤول النظام.';
    case '42501':
      return 'ليس لديك صلاحية لهذه العملية.';
    case '23505':
      return 'هذا العنصر موجود بالفعل. لا يمكن تكراره.';
    case '23503':
      return 'لا يمكن حذف هذا العنصر لأن بيانات أخرى تعتمد عليه.';
    case 'PGRST204':
    case 'PGRST116':
      return 'العنصر المطلوب غير موجود.';
    case 'PGRST203':
      return 'تعذر حفظ العملية حاليًا. أعد المحاولة.';
    default:
      if (_isArabic(error.message)) {
        return error.message;
      }
      return 'تعذر إتمام العملية. أعد المحاولة بعد لحظات.';
  }
}

String _humanizeFunctionError(FunctionException error) {
  final status = error.status;
  if (status == 401 || status == 403) {
    return 'انتهت صلاحية الجلسة أو ليس لديك صلاحية. سجّل الدخول من جديد.';
  }
  if (status == 429) {
    return 'عدد المحاولات كثير. انتظر قليلاً ثم أعد المحاولة.';
  }
  if (status >= 500) {
    return 'خطأ في الخادم. أعد المحاولة بعد لحظات.';
  }
  return 'تعذر إكمال العملية. أعد المحاولة.';
}

bool _isArabic(String text) {
  return RegExp(r'[؀-ۿ]').hasMatch(text);
}

Future<T> retryWithBackoff<T>(
  Future<T> Function() action, {
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  Duration delay = initialDelay;
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await action();
    } catch (error) {
      final isRetryable =
          error is SocketException ||
          error is TimeoutException ||
          error.toString().contains('AuthRetryableFetchException') ||
          error.toString().contains('ClientException');
      if (!isRetryable || attempt == maxRetries - 1) rethrow;
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }
  throw StateError('Unreachable');
}

/// P0-21: Wraps a Future with a timeout to prevent infinite spinners.
/// Default is 20 seconds, matching the V10 requirement.
Future<T> rpcWithTimeout<T>(
  Future<T> future, [
  Duration timeout = const Duration(seconds: 20),
]) =>
    future.timeout(timeout);
