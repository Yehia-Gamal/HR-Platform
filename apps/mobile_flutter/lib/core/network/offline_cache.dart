import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple JSON cache backed by FlutterSecureStorage.
/// Stores last-fetched data keyed by [cacheKey] so offline views can display
/// stale data instead of error states.
///
/// مفاتيح الكاش مُقيَّدة بمعرّف المستخدم الحالي لمنع تسرّب البيانات
/// بين مستخدمين مختلفين على نفس الجهاز.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _prefix = 'offline_cache_';
  static const _tsPrefix = 'offline_ts_';

  String? _currentUserId;

  void setCurrentUser(String? userId) {
    _currentUserId = userId;
  }

  String _dataKey(String cacheKey) =>
      '$_prefix${_currentUserId != null ? "${_currentUserId}_" : ""}$cacheKey';

  String _tsKey(String cacheKey) =>
      '$_tsPrefix${_currentUserId != null ? "${_currentUserId}_" : ""}$cacheKey';

  Future<void> put(String cacheKey, dynamic data) async {
    try {
      final json = jsonEncode(data);
      await _storage.write(key: _dataKey(cacheKey), value: json);
      await _storage.write(
        key: _tsKey(cacheKey),
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  Future<dynamic> get(String cacheKey) async {
    try {
      final json = await _storage.read(key: _dataKey(cacheKey));
      if (json == null) return null;
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  Future<DateTime?> getTimestamp(String cacheKey) async {
    try {
      final ts = await _storage.read(key: _tsKey(cacheKey));
      if (ts == null) return null;
      return DateTime.parse(ts);
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String cacheKey) async {
    try {
      await _storage.delete(key: _dataKey(cacheKey));
      await _storage.delete(key: _tsKey(cacheKey));
    } catch (_) {}
  }

  Future<void> clearAll() async {
    for (final key in [
      attendanceState,
      employeeHome,
      managerDashboard,
      kpiList,
      myRequests,
    ]) {
      await remove(key);
    }
  }

  Future<void> clearAllForUser(String? userId) async {
    final saved = _currentUserId;
    _currentUserId = userId;
    await clearAll();
    _currentUserId = saved;
  }

  static const attendanceState = 'attendance_state';
  static const employeeHome = 'employee_home';
  static const managerDashboard = 'manager_dashboard';
  static const kpiList = 'kpi_list';
  static const myRequests = 'my_requests';
}
