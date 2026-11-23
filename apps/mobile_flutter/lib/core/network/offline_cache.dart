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

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static const _prefix = 'offline_cache_';
  static const _tsPrefix = 'offline_ts_';

  /// أقصى عمر لعنصر الكاش قبل اعتباره منتهي الصلاحية (24 ساعة).
  static const _maxAge = Duration(hours: 24);

  String _dataKey(String userId, String cacheKey) =>
      '$_prefix${userId}_$cacheKey';

  String _tsKey(String userId, String cacheKey) =>
      '$_tsPrefix${userId}_$cacheKey';

  Future<void> put(String userId, String cacheKey, dynamic data) async {
    try {
      final json = jsonEncode(data);
      await _storage.write(key: _dataKey(userId, cacheKey), value: json);
      await _storage.write(
        key: _tsKey(userId, cacheKey),
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  /// يُرجع البيانات المخزّنة إن لم تنتهِ صلاحيتها (خلال [_maxAge]).
  /// إن انتهت، يُحذف العنصر ويُرجع null إلا إذا كان [allowStale] مفعلاً.
  Future<dynamic> get(String userId, String cacheKey) async {
    try {
      // تحقق من TTL قبل الإرجاع
      final rawTimestamp = await _storage.read(key: _tsKey(userId, cacheKey));
      final ts = rawTimestamp == null ? null : DateTime.tryParse(rawTimestamp);
      if (ts == null) return null;
      final age = DateTime.now().difference(ts);
      if (age > _maxAge) {
        await _storage.delete(key: _dataKey(userId, cacheKey));
        await _storage.delete(key: _tsKey(userId, cacheKey));
        return null;
      }
      final json = await _storage.read(key: _dataKey(userId, cacheKey));
      if (json == null) return null;
      return jsonDecode(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAllForUser(String userId) async {
    try {
      final allKeys = await _storage.readAll();
      final dataPrefix = _dataKey(userId, '');
      final tsPrefix = _tsKey(userId, '');
      for (final key in allKeys.keys) {
        if (key.startsWith(dataPrefix) || key.startsWith(tsPrefix)) {
          await _storage.delete(key: key);
        }
      }
    } catch (_) {}
  }

  static const attendanceState = 'attendance_state';
  static const employeeHome = 'employee_home';
  static const managerDashboard = 'manager_dashboard';
  static const kpiList = 'kpi_list';
  static const myRequests = 'my_requests';
  static const accessContext = 'access_context';
}
