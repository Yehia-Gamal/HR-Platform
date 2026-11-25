import 'dart:async';
import 'dart:convert';

import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// عنصر واحد في طابور المزامنة — يمثل عملية فشلت أو نُفذت أثناء انقطاع الاتصال.
class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.retryCount = 0,
  });

  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
    id: json['id'] as String,
    action: json['action'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    createdAt: json['createdAt'] as String,
    retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String action;
  final Map<String, dynamic> payload;
  final String createdAt;
  int retryCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'action': action,
    'payload': payload,
    'createdAt': createdAt,
    'retryCount': retryCount,
  };

  /// وصف عربي مقروء لنوع العملية.
  String get actionLabel => switch (action) {
    'punch_attendance' => 'تسجيل حضور/انصراف',
    'submit_request' => 'إرسال طلب',
    'decide_request' => 'قرار على طلب',
    'delegate_request_to_abu_ammar' => 'تفويض طلب لمدير التشغيل',
    'request_correction' => 'طلب تصحيح حضور',
    'save_daily_report' => 'حفظ تقرير يومي',
    'service_request' => 'فتح تذكرة خدمة',
    _ => action,
  };
}

/// استثناء يُرمى عندما تُدرج العملية في طابور المزامنة بدل تنفيذها —
/// الرسالة تخبر المستخدم أن الإرسال سيحدث تلقائياً عند عودة الاتصال.
class OfflineQueuedException implements Exception {
  OfflineQueuedException(this.action);
  final String action;

  @override
  String toString() =>
      'لا يوجد اتصال الآن — العملية أُضيفت لطابور المزامنة '
      'وستُرسل تلقائياً عند عودة الاتصال.';
}

/// استثناء يُرمى عند محاولة تسجيل بصمة حضور/انصراف بدون اتصال مباشر بالخادم.
/// البصمات لا تُخزّن offline حتى لا تُحتسب بوقت المزامنة المتأخر كـ تأخير/غرامة.
class AttendanceOfflineException implements Exception {
  const AttendanceOfflineException();

  @override
  String toString() =>
      'لا يوجد اتصال، حاول لاحقاً — يلزم اتصال مباشر بالإنترنت لتسجيل البصمة بوقت الخادم.';
}

/// طابور مزامنة يخزن العمليات الفاشلة/غير المتصلة في FlutterSecureStorage
/// ويعيد تنفيذها عند عودة الاتصال.
///
/// نمط Singleton مطابق لـ [OfflineCache].
class OfflineSyncQueue {
  OfflineSyncQueue._(this._userId);
  static final _queues = <String, OfflineSyncQueue>{};
  static OfflineSyncQueue forUser(String userId) =>
      _queues.putIfAbsent(userId, () => OfflineSyncQueue._(userId));

  final String _userId;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  // The legacy queue had no owner and cannot be replayed under a new account.
  String get _storageKey => 'offline_sync_queue_v2_$_userId';
  String get _lastSyncKey => 'offline_sync_last_ts_$_userId';
  Future<void> _pending = Future<void>.value();
  int _generation = 0;
  static const _maxRetries = 5;
  static const _maxCriticalRetries = 25;
  static const _uuid = Uuid();

  /// يُخطر المستمعين عند تغيّر الطابور (إضافة/حذف/معالجة).
  final ValueNotifier<int> countNotifier = ValueNotifier<int>(0);

  /// يُخطر المستمعين عند إسقاط عنصر تجاوز الحد الأقصى للمحاولات.
  /// حتى لا تُفقد البصمات/العمليات الحساسة بصمت.
  final ValueNotifier<SyncQueueItem?> droppedNotifier =
      ValueNotifier<SyncQueueItem?>(null);

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// أضف عملية جديدة إلى الطابور.
  /// يُرفض تسجيل البصمات (`punch_attendance`) هنا لحماية الموظف من احتسابها بوقت المزامنة.
  Future<void> enqueue(String action, Map<String, dynamic> payload) {
    if (action == 'punch_attendance') {
      throw UnsupportedError(
        'لا يمكن تخزين بصمة الحضور بدون اتصال — يلزم اتصال مباشر بالخادم.',
      );
    }
    final generation = _generation;
    return _serialize(() async {
      if (generation != _generation) throw StateError('The queue was cleared.');
      final items = await _load();
      items.add(
        SyncQueueItem(
          id: _uuid.v4(),
          action: action,
          payload: payload,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      await _save(items);
    });
  }

  /// جميع العناصر المعلقة.
  Future<List<SyncQueueItem>> getAll() async {
    try {
      return await _load();
    } catch (error, stackTrace) {
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'offline_sync_queue_get_all',
        ),
      );
      return [];
    }
  }

  /// عدد العناصر المعلقة.
  Future<int> get count async => (await getAll()).length;

  /// آخر وقت مزامنة ناجحة.
  Future<DateTime?> get lastSyncTime async {
    try {
      final ts = await _storage.read(key: _lastSyncKey);
      if (ts == null) return null;
      return DateTime.parse(ts);
    } catch (error, stackTrace) {
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'offline_sync_queue_last_sync_read',
        ),
      );
      return null;
    }
  }

  /// تحديث زمن آخر مزامنة ناجحة.
  Future<void> _updateLastSync() async {
    try {
      await _storage.write(
        key: _lastSyncKey,
        value: DateTime.now().toUtc().toIso8601String(),
      );
    } catch (error, stackTrace) {
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'offline_sync_queue_last_sync_write',
        ),
      );
    }
  }

  /// حاول تنفيذ جميع العمليات المعلقة.
  /// يحذف الناجحة، ويزيد عداد المحاولات للفاشلة (حد أقصى [_maxRetries]).
  /// يُرجع عدد العمليات التي نجحت.
  Future<int> processQueue(SupabaseClient client) {
    final generation = _generation;
    return _serialize(() => _processQueue(client, generation));
  }

  Future<int> _processQueue(SupabaseClient client, int generation) async {
    final items = await _load();
    int successCount = 0;

    for (final item in List.of(items)) {
      if (generation != _generation || client.auth.currentUser?.id != _userId) {
        break;
      }
      // حماية للعناصر المخزنة من إصدارات أقدم: لا نعيد إرسال بصمة متأخرة بوقت المزامنة.
      if (item.action == 'punch_attendance') {
        items.remove(item);
        droppedNotifier.value = item;
        await _save(items);
        continue;
      }
      try {
        await _executeAction(client, item);
        items.remove(item);
        successCount++;
      } catch (e) {
        item.retryCount++;
        // البصمات (حضور/انصراف) عمليات حرجة — تمنح حصة محاولات أوسع.
        final maxRetries = item.action == 'punch_attendance'
            ? _maxCriticalRetries
            : _maxRetries;
        if (item.retryCount >= maxRetries) {
          // تجاوز الحد الأقصى — نحذف العنصر لمنع التراكم،
          // لكن مع إشعار صريح للمستخدم بدل الإسقاط الصامت.
          items.remove(item);
          droppedNotifier.value = item;
          if (kDebugMode) {
            debugPrint(
              '[OfflineSyncQueue] تجاوز الحد الأقصى للمحاولات: '
              '${item.action} (${item.id})',
            );
          }
        } else if (kDebugMode) {
          debugPrint(
            '[OfflineSyncQueue] فشل ${item.action}: $e '
            '(محاولة ${item.retryCount}/$maxRetries)',
          );
        }
      }
      await _save(items);
    }

    if (successCount > 0) {
      await _updateLastSync();
    }

    return successCount;
  }

  /// تنفيذ عملية واحدة حسب نوعها.
  Future<void> _executeAction(SupabaseClient client, SyncQueueItem item) async {
    switch (item.action) {
      case 'punch_attendance':
        throw StateError('تم إيقاف مزامنة البصمة غير المتصلة لحماية دقة وقت الخادم.');
      default:
        // أنواع أخرى مستقبلية — ننفذها كـ RPC عام.
        final rpcName = item.payload['rpc_name'] as String?;
        final rpcParams = item.payload['rpc_params'] as Map<String, dynamic>?;
        if (rpcName != null) {
          await client
              .rpc<dynamic>(rpcName, params: rpcParams ?? {})
              .timeout(const Duration(seconds: 20));
        } else {
          throw StateError('نوع العملية غير معروف: ${item.action}');
        }
    }
  }

  // ── تخزين داخلي ──────────────────────────────────────────

  Future<List<SyncQueueItem>> _load() async {
    final raw = await _storage.read(key: _storageKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => SyncQueueItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _save(List<SyncQueueItem> items) async {
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    await _storage.write(key: _storageKey, value: json);
    countNotifier.value = items.length;
  }

  /// مسح الطابور بالكامل (للاختبارات أو تسجيل الخروج).
  Future<void> clear() {
    _generation++;
    return _serialize(() async {
      await _storage.delete(key: _storageKey);
      await _storage.delete(key: _lastSyncKey);
      countNotifier.value = 0;
      droppedNotifier.value = null;
    });
  }
}

final offlineSyncQueueProvider = Provider<OfflineSyncQueue?>((ref) {
  final userId = ref.watch(authUserIdProvider);
  return userId == null ? null : OfflineSyncQueue.forUser(userId);
});

/// Provider يكشف عدد العمليات المعلقة كـ stream.
final syncQueueCountProvider = StreamProvider<int>((ref) {
  final queue = ref.watch(offlineSyncQueueProvider);
  if (queue == null) return Stream.value(0);
  final controller = StreamController<int>();
  final notifier = queue.countNotifier;
  var changed = false;
  void onCountChanged() {
    changed = true;
    controller.add(notifier.value);
  }

  notifier.addListener(onCountChanged);
  unawaited(
    queue.count.then((value) {
      if (!changed && !controller.isClosed) controller.add(value);
    }),
  );
  ref.onDispose(() {
    notifier.removeListener(onCountChanged);
    unawaited(controller.close());
  });
  return controller.stream;
});
