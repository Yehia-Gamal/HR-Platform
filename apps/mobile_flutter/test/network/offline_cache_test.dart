import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('leaves another account’s cached data intact during logout', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final cache = OfflineCache.instance;
    await Future.wait([
      cache.put('account-a', OfflineCache.employeeHome, {'name': 'A'}),
      cache.put('account-b', OfflineCache.employeeHome, {'name': 'B'}),
    ]);
    await cache.clearAllForUser('account-a');

    expect(await cache.get('account-a', OfflineCache.employeeHome), isNull);
    expect(await cache.get('account-b', OfflineCache.employeeHome), {
      'name': 'B',
    });
  });

  test('does not return an expired access context', () async {
    FlutterSecureStorage.setMockInitialValues({
      'offline_cache_account-a_access_context': '{"role":"admin"}',
      'offline_ts_account-a_access_context': '2020-01-01T00:00:00.000Z',
    });
    expect(
      await OfflineCache.instance.get('account-a', OfflineCache.accessContext),
      isNull,
    );
  });

  group('OfflineCache — ثوابت مفاتيح التخزين المؤقت', () {
    test('مفتاح حالة الحضور', () {
      expect(OfflineCache.attendanceState, 'attendance_state');
    });

    test('مفتاح الصفحة الرئيسية للموظف', () {
      expect(OfflineCache.employeeHome, 'employee_home');
    });

    test('مفتاح لوحة المدير', () {
      expect(OfflineCache.managerDashboard, 'manager_dashboard');
    });

    test('مفتاح قائمة مؤشرات الأداء', () {
      expect(OfflineCache.kpiList, 'kpi_list');
    });

    test('مفتاح طلباتي', () {
      expect(OfflineCache.myRequests, 'my_requests');
    });

    test('مفتاح سياق الصلاحيات', () {
      expect(OfflineCache.accessContext, 'access_context');
    });
  });

  group('OfflineCache — نمط Singleton', () {
    test('يرجع نفس الكائن عند كل وصول', () {
      final a = OfflineCache.instance;
      final b = OfflineCache.instance;
      expect(identical(a, b), isTrue);
    });

    test('الكائن ليس null', () {
      expect(OfflineCache.instance, isNotNull);
    });
  });

  group('OfflineCache — المفاتيح فريدة ومختلفة', () {
    test('كل مفتاح مختلف عن الآخر', () {
      final keys = [
        OfflineCache.attendanceState,
        OfflineCache.employeeHome,
        OfflineCache.managerDashboard,
        OfflineCache.kpiList,
        OfflineCache.myRequests,
        OfflineCache.accessContext,
      ];
      // تحقق من عدم تكرار المفاتيح
      expect(keys.toSet().length, keys.length);
    });

    test('المفاتيح ليست فارغة', () {
      expect(OfflineCache.attendanceState.isNotEmpty, isTrue);
      expect(OfflineCache.employeeHome.isNotEmpty, isTrue);
      expect(OfflineCache.managerDashboard.isNotEmpty, isTrue);
      expect(OfflineCache.kpiList.isNotEmpty, isTrue);
      expect(OfflineCache.myRequests.isNotEmpty, isTrue);
      expect(OfflineCache.accessContext.isNotEmpty, isTrue);
    });
  });
}
