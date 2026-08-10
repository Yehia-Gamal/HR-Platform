import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple JSON cache backed by FlutterSecureStorage.
/// Stores last-fetched data keyed by [cacheKey] so offline views can display
/// stale data instead of error states.
///
/// مفاتيح الكاش مُقيَّدة بمعرّف المستخدم الحالي لمنع تسرّب البيانات
/// بين مستخدمين مختلفين على نفس الجهاز (خاصةً في حالة تسجيل الخروج ثم
/// الدخول بحساب آخر). استدعِ [setCurrentUser] عند بدء الجلسة وعند إنهائها.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _prefix = 'offline_cache_';
  static const _tsPrefix = 'offline_ts_';

  String? _currentUserId;

  /// يضبط معرّف المستخدم الحالي لتقييد مفاتيح الكاش.
  /// استدعِه بـ null عند تسجيل الخروج لحذف التقييد قبل [clearAll].
  void setCurrentUser(String? userId) {
    _currentUserId = userId;
  }

  String _dataKey(String cacheKey) =>
      '$_prefix${_currentUserId != null ? "${_currentUserId}_" : ""}$cacheKey';

  String _tsKey(String cacheKey) =>
      '$_tsPrefix${_currentUserId != null ? "${_currentUserId}_" : ""}$cacheKey';

  /// Save [data] (typically a Map or List) under [cacheKey].
  Future<void> put(String cacheKey, dynamic data) async {
    try {
      final json = jsonEncode(data);
      await _storage.write(key: _dataKey(cacheKey), value: json);
      await _storage.write(
        key: _tsKey(cacheKey),
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Cache writes are best-effort.
    }
  }

  /// Retrieve cached data for [cacheKey]. Returns `null` if not found.
  Future<dynamic> get(String cacheKey) async {
    try {
      final json = await _storage.read(key: _dataKey(cacheKey));
      if (json == null) return null;
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  /// Get the timestamp of the last cache write for [cacheKey].
  Future<DateTime?> getTimestamp(String cacheKey) async {
    try {
      final ts = await _storage.read(key: _tsKey(cacheKey));
      if (ts == null) return null;
      return DateTime.parse(ts);
    } catch (_) {
      return null;
    }
  }

  /// Remove cached data for [cacheKey].
  Future<void> remove(String cacheKey) async {
    try {
      await _storage.delete(key: _dataKey(cacheKey));
      await _storage.delete(key: _tsKey(cacheKey));
    } catch (_) {
      // Best-effort.
    }
  }

  /// مسح جميع البيانات المؤقتة للمستخدم الحالي (عند تسجيل الخروج).
  Future<void> clearAll() async {
    const keys = [attendanceState, employeeHome, managerDashboard, kpiList, myRequests];
    for (final key in keys) {
      await remove(key);
    }
  }

  /// مسح جميع البيانات المؤقتة لمستخدم محدد بمعرّفه — آمن من سباقات التزامن
  /// لأنه لا يعتمد على الحقل [_currentUserId] المتغيّر.
  Future<void> clearAllForUser(String? userId) async {
    final savedUserId = _currentUserId;
    _currentUserId = userId;
    await clearAll();
    _currentUserId = savedUserId;
  }

  /// Common cache keys used across the app.
  static const attendanceState = 'attendance_state';
  static const employeeHome = 'employee_home';
  static const managerDashboard = 'manager_dashboard';
  static const kpiList = 'kpi_list';
  static const myRequests = 'my_requests';
}
