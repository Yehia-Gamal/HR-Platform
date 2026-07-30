import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';

/// يلف استدعاء Supabase RPC بمنطق offline-first:
/// - عند النجاح: يحفظ النتيجة في الكاش ويُرجع البيانات الجديدة.
/// - عند الفشل (انقطاع اتصال): يُرجع البيانات المخزنة إن وُجدت، وإلا يُعيد طرح الخطأ.
///
/// مثال:
/// ```dart
/// final data = await offlineAwareRpc<EmployeeHomeSummary>(
///   rpcCall: client.rpc('get_employee_home'),
///   cacheKey: OfflineCache.employeeHome,
///   parser: (d) => EmployeeHomeSummary.fromJson(Map<String, dynamic>.from(d)),
/// );
/// ```
Future<T> offlineAwareRpc<T>({
  required Future<dynamic> rpcCall,
  required String cacheKey,
  required T Function(dynamic) parser,
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final data = await rpcCall.timeout(timeout);
    // حفظ في الكاش للاستخدام عند انقطاع الاتصال.
    OfflineCache.instance.put(cacheKey, data);
    return parser(data);
  } catch (e) {
    // إذا كان الخطأ متعلقاً بالشبكة، نحاول الكاش.
    if (_isNetworkError(e)) {
      final cached = await OfflineCache.instance.get(cacheKey);
      if (cached != null) return parser(cached);
    }
    rethrow;
  }
}

/// يلف استدعاء Supabase RPC لقائمة مع offline-first caching.
///
/// مثال:
/// ```dart
/// final items = await offlineAwareRpcList<MobileRequest>(
///   rpcCall: client.rpc('get_request_inbox', params: {'p_limit': 100}),
///   cacheKey: OfflineCache.myRequests,
///   parser: (e) => MobileRequest.fromJson(Map<String, dynamic>.from(e)),
/// );
/// ```
Future<List<T>> offlineAwareRpcList<T>({
  required Future<dynamic> rpcCall,
  required String cacheKey,
  required T Function(Map<String, dynamic>) parser,
  Duration timeout = const Duration(seconds: 20),
}) async {
  try {
    final data = await rpcCall.timeout(timeout);
    final list = (data as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
        .toList(growable: false);
    // حفظ القائمة الخام في الكاش.
    OfflineCache.instance.put(cacheKey, list);
    return list.map(parser).toList(growable: false);
  } catch (e) {
    if (_isNetworkError(e)) {
      final cached = await OfflineCache.instance.get(cacheKey);
      if (cached != null) {
        return (cached as List<dynamic>)
            .map((e) => parser(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false);
      }
    }
    rethrow;
  }
}

bool _isNetworkError(Object error) {
  if (error is SocketException) return true;
  if (error is TimeoutException) return true;
  final msg = error.toString();
  return msg.contains('AuthRetryableFetchException') ||
      msg.contains('ClientException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('SocketException');
}
