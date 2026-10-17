import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:ahla_shabab_management_os/shared/hierarchy_sort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('الهيكل الإداري وترتيب الموظفين', () {
    test('الرتب الدقيقة لجميع فئات الموظفين', () {
      // 1. الشيخ محمد يوسف
      expect(
        getHierarchyRank(
          name: 'الشيخ محمد يوسف',
          jobTitle: 'المدير التنفيذي لجمعية خواطر أحلى شباب',
        ),
        equals(1),
      );
      expect(
        getHierarchyRank(
          name: 'ألشيخ محمد يوسف',
          jobTitle: 'المدير التنفيذي',
        ),
        equals(1),
      );

      // 2. يحيى السبع
      expect(
        getHierarchyRank(
          name: 'يحيى جمال السبع',
          jobTitle: 'السكرتير التنفيذي',
        ),
        equals(2),
      );
      expect(
        getHierarchyRank(
          name: 'يحيى السبع',
          jobTitle: 'سكرتير تنفيذي',
        ),
        equals(2),
      );

      // 3. أبو عمار
      expect(
        getHierarchyRank(
          name: 'محمد عبدالباسط ( ابو عمار )',
          jobTitle: 'مدير تشغيل (أوبريشن)',
        ),
        equals(3),
      );

      // 4. ياسر
      expect(
        getHierarchyRank(
          name: 'ياسر فتحي نور الدين',
          jobTitle: 'مدير تشغيل (أوبريشن)',
        ),
        equals(4),
      );

      // 5. باقي المديرين
      expect(
        getHierarchyRank(
          name: 'بلال محمد ابراهيم الشاكر',
          jobTitle: 'مدير الميديا - شؤون القرآن',
        ),
        equals(5),
      );
      expect(
        getHierarchyRank(
          name: 'عبدالعزيز طارق محمود الباسل',
          jobTitle: 'مدير ادارة المتطوعين',
        ),
        equals(5),
      );
      expect(
        getHierarchyRank(
          name: 'محمد عبده رجب مزار',
          jobTitle: 'مدير مطابخ أحلى شباب',
        ),
        equals(5),
      );
      expect(
        getHierarchyRank(
          name: 'مصطفي محمد فايد',
          jobTitle: 'مدير الحسابات',
        ),
        equals(5),
      );
      expect(
        getHierarchyRank(
          name: 'مصطفي أحمد كمال الدين',
          jobTitle: 'إدارة العيادات الطبية بمجمعات أحلى شباب',
          department: 'إدارة العيادات الطبية',
        ),
        equals(5),
      );
      expect(
        getHierarchyRank(
          name: 'يوسف رسمي شعبان',
          jobTitle: 'مدير مجمع وعيادات منيل شيحة',
          department: 'إدارة العيادات الطبية',
        ),
        equals(5),
      );

      // 6. باقي الموظفين
      expect(
        getHierarchyRank(
          name: 'طارق سيد إبراهيم',
          jobTitle: 'سائق',
          department: 'إدارة الحركة',
        ),
        equals(6),
      );
      expect(
        getHierarchyRank(
          name: 'عمار محمد عبد الباسط',
          jobTitle: 'مسؤول الاعلام / جرافيك ديزاين',
          department: 'إدارة الميديا',
        ),
        equals(6),
      );
      expect(
        getHierarchyRank(
          name: 'حامد محمود العمدة',
          jobTitle: 'مسؤول الأسر',
          department: 'لجنة الأسر',
        ),
        equals(6),
      );

      // 7. تيم البنات بتوع الطاقم الطبي (آخر شيء خالص)
      expect(
        getHierarchyRank(
          name: 'رحاب مجدي يوسف سيد',
          jobTitle: 'دكتورة المعمل',
          department: 'إدارة العيادات الطبية',
        ),
        equals(7),
      );
      expect(
        getHierarchyRank(
          name: 'ساميه أشرف قرني عبد المجيد',
          jobTitle: 'تمريض',
          department: 'إدارة العيادات الطبية',
        ),
        equals(7),
      );
      expect(
        getHierarchyRank(
          name: 'سمر احمد سمير ربيع',
          jobTitle: 'تمريض',
          department: 'إدارة العيادات الطبية',
        ),
        equals(7),
      );
      expect(
        getHierarchyRank(
          name: 'سميرة سعيد محمود عبد رب النبي',
          jobTitle: 'موظف استقبال',
          department: 'إدارة العيادات الطبية',
        ),
        equals(7),
      );
      expect(
        getHierarchyRank(
          name: 'شروق عبد العليم صلاح عبد...',
          jobTitle: 'تمريض',
          department: 'إدارة العيادات الطبية',
        ),
        equals(7),
      );
    });

    test('ترتيب مصفوفة موظفين يعكس الترتيب المطلوب تماما', () {
      final employees = [
        {'name': 'سمر احمد سمير ربيع', 'title': 'تمريض', 'dept': 'إدارة العيادات الطبية'},
        {'name': 'ياسر فتحي نور الدين', 'title': 'مدير تشغيل (أوبريشن)', 'dept': 'العمليات'},
        {'name': 'طارق سيد إبراهيم', 'title': 'سائق', 'dept': 'إدارة الحركة'},
        {'name': 'يحيى جمال السبع', 'title': 'السكرتير التنفيذي', 'dept': 'المكتب التنفيذي'},
        {'name': 'بلال محمد ابراهيم الشاكر', 'title': 'مدير الميديا', 'dept': 'الميديا'},
        {'name': 'محمد عبدالباسط ( ابو عمار )', 'title': 'مدير تشغيل (أوبريشن)', 'dept': 'العمليات'},
        {'name': 'الشيخ محمد يوسف', 'title': 'المدير التنفيذي', 'dept': 'الإدارة العليا'},
        {'name': 'مصطفي أحمد كمال الدين', 'title': 'مدير إدارة العيادات الطبية', 'dept': 'العيادات'},
      ];

      final sorted = sortByHierarchy<Map<String, String>>(
        employees,
        (e) => e['title']!,
        (e) => e['name']!,
        getDepartment: (e) => e['dept']!,
      );

      final names = sorted.map((e) => e['name']).toList();
      expect(
        names,
        equals([
          'الشيخ محمد يوسف',              // 1
          'يحيى جمال السبع',              // 2
          'محمد عبدالباسط ( ابو عمار )',   // 3
          'ياسر فتحي نور الدين',          // 4
          'بلال محمد ابراهيم الشاكر',      // 5 (مدير)
          'مصطفي أحمد كمال الدين',         // 5 (مدير العيادات)
          'طارق سيد إبراهيم',             // 6 (موظف)
          'سمر احمد سمير ربيع',           // 7 (تيم البنات بتوع الطاقم الطبي آخر شيء)
        ]),
      );
    });

    test('صلاحية رؤية تيم بنات الطاقم الطبي', () {
      // 1. الشيخ محمد يوسف -> مسموح
      final sheikh = AccessContext(
        userId: 'u1',
        employeeId: '7b0740fa-66ba-4616-8674-3dbd8e14109e',
        displayName: 'الشيخ محمد يوسف',
        employeeCode: 'EXEC01',
        roles: const ['executive-director'],
        permissions: const [],
        workspaces: const [WorkspaceId.executive],
        defaultWorkspace: WorkspaceId.executive,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: false,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: false,
        ),
      );
      expect(canViewClinicGirls(sheikh), isTrue);

      // 2. يحيى السبع -> مسموح
      final yehia = AccessContext(
        userId: 'u2',
        employeeId: 'e2',
        displayName: 'يحيى جمال السبع',
        employeeCode: 'SEC01',
        roles: const ['executive-secretary'],
        permissions: const [],
        workspaces: const [WorkspaceId.executive],
        defaultWorkspace: WorkspaceId.executive,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: false,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: false,
        ),
      );
      expect(canViewClinicGirls(yehia), isTrue);

      // 3. مصطفى أحمد -> مسموح
      final mostafa = AccessContext(
        userId: 'u3',
        employeeId: '4120ce3a-8999-453e-8d9d-acd8f3b5f04c',
        displayName: 'مصطفي أحمد كمال الدين',
        employeeCode: 'MED01',
        roles: const ['clinics-manager'],
        permissions: const [],
        workspaces: const [WorkspaceId.manager],
        defaultWorkspace: WorkspaceId.manager,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: true,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: false,
        ),
      );
      expect(canViewClinicGirls(mostafa), isTrue);

      // 4. يوسف رسمي -> مسموح
      final youssef = AccessContext(
        userId: 'u4',
        employeeId: 'a3b0a2ca-6cbd-49f6-87ed-2f63fa1055c6',
        displayName: 'يوسف رسمي شعبان',
        employeeCode: 'MED02',
        roles: const ['manager'],
        permissions: const [],
        workspaces: const [WorkspaceId.manager],
        defaultWorkspace: WorkspaceId.manager,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: true,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: false,
        ),
      );
      expect(canViewClinicGirls(youssef), isTrue);

      // 5. موظف عادي (سائق أو ميديا أو موظف آخر) -> غير مسموح ومحجوبين عنه
      final regularEmp = AccessContext(
        userId: 'u5',
        employeeId: 'e5',
        displayName: 'طارق سيد إبراهيم',
        employeeCode: 'DRV01',
        roles: const ['employee'],
        permissions: const [],
        workspaces: const [WorkspaceId.employee],
        defaultWorkspace: WorkspaceId.employee,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: true,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: true,
        ),
      );
      expect(canViewClinicGirls(regularEmp), isFalse);

      // 6. مدير آخر (مثل مدير الميديا) -> غير مسموح ومحجوبين عنه
      final otherManager = AccessContext(
        userId: 'u6',
        employeeId: 'e6',
        displayName: 'بلال محمد ابراهيم الشاكر',
        employeeCode: 'MED01',
        roles: const ['manager'],
        permissions: const [],
        workspaces: const [WorkspaceId.manager],
        defaultWorkspace: WorkspaceId.manager,
        attendancePolicy: const AttendancePolicy(
          attendanceRequired: true,
          selfPunchEnabled: true,
          liveLocationResponseEnabled: false,
        ),
      );
      expect(canViewClinicGirls(otherManager), isFalse);
    });
  });
}
