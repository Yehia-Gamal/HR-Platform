import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple JSON cache backed by FlutterSecureStorage.
/// Stores last-fetched data keyed by [cacheKey] so offline views can display
/// stale data instead of error states.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _prefix = 'offline_cache_';
  static const _tsPrefix = 'offline_ts_';

  /// Save [data] (typically a Map or List) under [cacheKey].
  Future<void> put(String cacheKey, dynamic data) async {
    try {
      final json = jsonEncode(data);
      await _storage.write(key: '$_prefix$cacheKey', value: json);
      await _storage.write(
        key: '$_tsPrefix$cacheKey',
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Cache writes are best-effort.
    }
  }

  /// Retrieve cached data for [cacheKey]. Returns `null` if not found.
  Future<dynamic> get(String cacheKey) async {
    try {
      final json = await _storage.read(key: '$_prefix$cacheKey');
      if (json == null) return null;
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  /// Get the timestamp of the last cache write for [cacheKey].
  Future<DateTime?> getTimestamp(String cacheKey) async {
    try {
      final ts = await _storage.read(key: '$_tsPrefix$cacheKey');
      if (ts == null) return null;
      return DateTime.parse(ts);
    } catch (_) {
      return null;
    }
  }

  /// Remove cached data for [cacheKey].
  Future<void> remove(String cacheKey) async {
    try {
      await _storage.delete(key: '$_prefix$cacheKey');
      await _storage.delete(key: '$_tsPrefix$cacheKey');
    } catch (_) {
      // Best-effort.
    }
  }

  /// مسح جميع البيانات المؤقتة (عند تسجيل الخروج).
  Future<void> clearAll() async {
    const keys = [attendanceState, employeeHome, managerDashboard, kpiList, myRequests];
    for (final key in keys) {
      await remove(key);
    }
  }

  /// Common cache keys used across the app.
  static const attendanceState = 'attendance_state';
  static const employeeHome = 'employee_home';
  static const managerDashboard = 'manager_dashboard';
  static const kpiList = 'kpi_list';
  static const myRequests = 'my_requests';
}
