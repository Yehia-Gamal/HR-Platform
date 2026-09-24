import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _project(String id, String led, {String approval = 'approved', int? days}) => {
      'id': id,
      'code': 'PRJ-$id',
      'name': 'مشروع $id',
      'description': null,
      'departmentId': 'd1',
      'departmentName': 'إدارة',
      'ownerName': 'موظف',
      'status': 'active',
      'approvalStatus': approval,
      'priority': 'high',
      'progress': 40,
      'totalSteps': 2,
      'completedSteps': 1,
      'blockedSteps': 0,
      'ledStatus': led,
      'daysSinceActivity': ?days,
    };

void main() {
  group('مشاريع الجمعية — النماذج (0553)', () {
    test('يقرأ الكتالوج ويفصل اللوحة عن الطلبات ويرتّب الأحوج أولاً', () {
      final c = AssociationProjectsCatalog.fromJson({
        'projects': [
          _project('a', 'active', days: 1),
          _project('b', 'critical', days: 20),
          _project('c', 'halted', days: 9),
          _project('d', 'pending', approval: 'pending_approval'),
        ],
        'isFullAccess': true,
        'myDepartmentId': 'd1',
        'settings': {'warningDays': 5, 'criticalDays': 10},
      });
      expect(c.board.map((p) => p.id), ['b', 'c', 'a']);
      expect(c.requests.map((p) => p.id), ['d']);
      expect(c.warningDays, 5);
      expect(c.criticalDays, 10);
    });

    test('استجابة ما قبل 0553 تعمل بقيم افتراضية', () {
      final c = AssociationProjectsCatalog.fromJson({
        'projects': [_project('a', 'stale')],
      });
      expect(c.criticalDays, 14);
      expect(c.canCreate, isTrue);
      expect(c.projects.single.canManage, isFalse);
      expect(c.projects.single.led, ProjectLed.stale);
    });

    test('حالة لمبة مجهولة لا تكسر التطبيق', () {
      expect(ProjectLed.parse('blinking'), ProjectLed.stale);
      expect(ProjectLed.parse('critical'), ProjectLed.critical);
    });

    test('الصلاحيات تُشتق عند غيابها من الخادم', () {
      final d = AssociationProjectDetail.fromJson({
        'project': _project('a', 'pending', approval: 'pending_approval'),
        'steps': [
          {'id': 's1', 'title': 'دراسة', 'sortOrder': 1, 'status': 'done'},
          {'id': 's2', 'title': 'تنفيذ', 'sortOrder': 2, 'status': 'pending'},
        ],
        'updates': [],
      }, isFullAccess: true);
      expect(d.permissions.canApprove, isTrue);
      expect(d.permissions.canUpdate, isFalse);
      expect(d.currentStep?.title, 'تنفيذ');
    });

    test('daysAgoLabel', () {
      expect(daysAgoLabel(null), 'لا يوجد نشاط بعد');
      expect(daysAgoLabel(0), 'اليوم');
      expect(daysAgoLabel(3), 'منذ 3 أيام');
      expect(daysAgoLabel(20), 'منذ 20 يوماً');
    });
  });

  test('رسالة الخادم العربية تظهر كما هي حتى مع رمز 42501', () {
    final msg = humanizeError(
      PostgrestException(message: 'لا يمكنك إنشاء مشروع إلا لإدارتك', code: '42501'),
    );
    expect(msg, 'لا يمكنك إنشاء مشروع إلا لإدارتك');
  });
}
