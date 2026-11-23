import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Caches a successful response for the account that issued the request.
/// Falls back to that account's cache on connectivity errors.
Future<T> offlineAwareRpc<T>({
  required SupabaseClient client,
  required Future<dynamic> Function() rpcCall,
  required String cacheKey,
  required T Function(dynamic) parser,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final userId = client.auth.currentUser?.id;
  try {
    final data = await rpcCall().timeout(timeout);
    if (client.auth.currentUser?.id != userId) {
      throw StateError('The active account changed during the request.');
    }
    final result = parser(data);
    if (userId != null) {
      unawaited(OfflineCache.instance.put(userId, cacheKey, data));
    }
    return result;
  } catch (error) {
    if (userId != null &&
        _isNetworkError(error) &&
        client.auth.currentUser?.id == userId) {
      final cached = await OfflineCache.instance.get(userId, cacheKey);
      if (cached != null && client.auth.currentUser?.id == userId) {
        return parser(cached);
      }
    }
    rethrow;
  }
}

bool _isNetworkError(Object error) =>
    error is SocketException ||
    error is TimeoutException ||
    error is http.ClientException ||
    error is AuthRetryableFetchException;
