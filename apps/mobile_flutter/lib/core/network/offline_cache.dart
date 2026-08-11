import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Simple JSON cache backed by FlutterSecureStorage.
/// Stores last-fetched data keyed by [cacheKey] so offline views can display
/// stale data instead of error states.
///
/// مفاتيح الكاش مُقيَّدة بمعرّف المستخدم الحالي لمنع تسرّب البيانات
/// بين مستخدمين مختلفين على نفس الجهاز.
///
/// TTL: العناصر الأقدم من [_maxAge] تُعتبر منتهية الصلاحية ويُرجع لها null.
class OfflineCache {
  OfflineCache._();
  static final OfflineCache instance = OfflineCache._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _prefix = 'offline_cache_';
  static const _tsPrefix = 'offline_ts_';

  /// أقصى عمر لعنصر الكاش قبل اعتباره منتهي الصلاحية (24 ساعة).
  static const _maxAge = Duration(hours: 24);

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

  /// يُرجع البيانات المخزّنة إن لم تنتهِ صلاحيتها (خلال [_maxAge]).
  /// إن انتهت، يُحذف العنصر ويُرجع null.
  Future<dynamic> get(String cacheKey) async {
    try {
      // تحقق من TTL قبل الإرجاع
      final ts = await getTimestamp(cacheKey);
      if (ts == null) return null;
      final age = DateTime.now().difference(ts);
      if (age > _maxAge) {
        await remove(cacheKey);
        return null;
      }
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

  /// يُحدّث كل عناصر الكاش للمستخدم الحالي عبر iterate جميع المفاتيح
  /// التي تبدأ بالـ prefix الخاص بالمستخدم.
  Future<void> clearAll() async {
    try {
      final allKeys = await _storage.readAll();
      final dataPrefix = '$_prefix${_currentUserId != null ? "${_currentUserId}_" : ""}';
      final tsPrefix = '$_tsPrefix${_currentUserId != null ? "${_currentUserId}_" : ""}';
      for (final key in allKeys.keys) {
        if (key.startsWith(dataPrefix) || key.startsWith(tsPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {}
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
