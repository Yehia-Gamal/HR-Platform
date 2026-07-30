import 'package:ahla_shabab_management_os/core/network/offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    });
  });
}
