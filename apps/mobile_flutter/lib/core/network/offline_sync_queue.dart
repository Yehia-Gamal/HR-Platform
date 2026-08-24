import 'dart:convert';

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
    'request_correction' => 'طلب تصحيح حضور',
    'save_daily_report' => 'حفظ تقرير يومي',
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

/// طابور مزامنة يخزن العمليات الفاشلة/غير المتصلة في FlutterSecureStorage
/// ويعيد تنفيذها عند عودة الاتصال.
///
/// نمط Singleton مطابق لـ [OfflineCache].
class OfflineSyncQueue {
  OfflineSyncQueue._();
  static final OfflineSyncQueue instance = OfflineSyncQueue._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _storageKey = 'offline_sync_queue_v1';
  static const _lastSyncKey = 'offline_sync_last_ts';
  static const _maxRetries = 5;
  static const _maxCriticalRetries = 25;
  static const _uuid = Uuid();

  /// يُخطر المستمعين عند تغيّر الطابور (إضافة/حذف/معالجة).
  final ValueNotifier<int> countNotifier = ValueNotifier<int>(0);

  /// يُخطر المستمعين عند إسقاط عنصر تجاوز الحد الأقصى للمحاولات.
  /// حتى لا تُفقد البصمات/العمليات الحساسة بصمت.
  final ValueNotifier<SyncQueueItem?> droppedNotifier =
      ValueNotifier<SyncQueueItem?>(null);

  /// أضف عملية جديدة إلى الطابور.
  Future<void> enqueue(String action, Map<String, dynamic> payload) async {
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
    countNotifier.value = items.length;
  }

  /// أزل عنصراً من الطابور بعد نجاح المزامنة.
  Future<void> dequeue(String id) async {
    final items = await _load();
    items.removeWhere((item) => item.id == id);
    await _save(items);
    countNotifier.value = items.length;
  }

  /// جميع العناصر المعلقة.
  Future<List<SyncQueueItem>> getAll() => _load();

  /// عدد العناصر المعلقة.
  Future<int> get count async => (await _load()).length;

  /// آخر وقت مزامنة ناجحة.
  Future<DateTime?> get lastSyncTime async {
    try {
      final ts = await _storage.read(key: _lastSyncKey);
      if (ts == null) return null;
      return DateTime.parse(ts);
    } catch (_) {
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
    } catch (_) {
      // Best-effort.
    }
  }

  /// حاول تنفيذ جميع العمليات المعلقة.
  /// يحذف الناجحة، ويزيد عداد المحاولات للفاشلة (حد أقصى [_maxRetries]).
  /// يُرجع عدد العمليات التي نجحت.
  Future<int> processQueue(SupabaseClient client) async {
    final items = await _load();
    if (items.isEmpty) return 0;

    int successCount = 0;
    final toRemove = <String>[];

    for (final item in items) {
      try {
        await _executeAction(client, item);
        toRemove.add(item.id);
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
          toRemove.add(item.id);
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
    }

    // حدّث القائمة: أزل الناجحة والمنتهية الصلاحية.
    final remaining = items
        .where((item) => !toRemove.contains(item.id))
        .toList(growable: false);
    await _save(remaining);
    countNotifier.value = remaining.length;

    if (successCount > 0) {
      await _updateLastSync();
    }

    return successCount;
  }

  /// تنفيذ عملية واحدة حسب نوعها.
  Future<void> _executeAction(SupabaseClient client, SyncQueueItem item) async {
    switch (item.action) {
      case 'punch_attendance':
        await client
            .rpc<dynamic>(
              'punch_attendance_local_biometric_v1',
              params: item.payload,
            )
            .timeout(const Duration(seconds: 20));
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
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => SyncQueueItem.fromJson(
              Map<String, dynamic>.from(e as Map<dynamic, dynamic>),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<SyncQueueItem> items) async {
    try {
      final json = jsonEncode(items.map((e) => e.toJson()).toList());
      await _storage.write(key: _storageKey, value: json);
    } catch (_) {
      // Best-effort.
    }
  }

  /// مسح الطابور بالكامل (للاختبارات أو تسجيل الخروج).
  Future<void> clear() async {
    try {
      await _storage.delete(key: _storageKey);
      countNotifier.value = 0;
    } catch (_) {
      // Best-effort.
    }
  }

  /// تحميل العدد الأولي في countNotifier.
  Future<void> initialize() async {
    countNotifier.value = await count;
  }
}

/// Provider يكشف عدد العمليات المعلقة كـ stream.
final syncQueueCountProvider = StreamProvider<int>((ref) async* {
  final queue = OfflineSyncQueue.instance;
  // القيمة الأولية.
  yield await queue.count;
  // استمع للتغييرات عبر ValueNotifier.
  final notifier = queue.countNotifier;
  var lastValue = notifier.value;
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (notifier.value != lastValue) {
      lastValue = notifier.value;
      yield lastValue;
    }
  }
});
