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

  group('فريق المشروع (0645)', () {
    test('مشروع فريق بلا إدارة: القائد والأعضاء والصفة', () {
      final p = AssociationProject.fromJson({
        ..._project('t', 'active'),
        'departmentId': null,
        'departmentName': null,
        'departments': [],
        'leaderId': 'e1',
        'leaderName': 'أحمد',
        'members': [
          {'employeeId': 'e1', 'name': 'أحمد', 'isLeader': true},
          {'employeeId': 'e2', 'name': 'بسمة', 'jobTitle': 'منسقة', 'departmentName': 'الإعلام', 'isLeader': false},
        ],
        'myRole': 'member',
        'canEdit': false,
      });
      expect(p.departmentId, isNull);
      expect(p.leaderName, 'أحمد');
      expect(p.team.where((m) => m.isLeader).length, 1);
      expect(p.scopeLabel, 'فريق من 2');
      expect(p.isMine, isTrue);
      expect(p.team[1].subtitle, 'منسقة • الإعلام');
    });

    test('استجابة ما قبل 0645: الفريق = القائد وحده والإدارة كما هي', () {
      final p = AssociationProject.fromJson(_project('old', 'active'));
      expect(p.team, hasLength(1));
      expect(p.team.single.isLeader, isTrue);
      expect(p.scopeLabel, 'إدارة');
      expect(p.myRole, isNull);
    });

    test('صلاحيات تعديل الفريق تُشتق من canEdit عند غيابها', () {
      final d = AssociationProjectDetail.fromJson({
        'project': _project('a', 'active'),
        'steps': [],
        'updates': [],
        'permissions': {'canManage': true, 'canApprove': false, 'canEdit': true, 'canSubmit': false, 'canUpdate': true, 'canDelete': false},
      }, isFullAccess: false);
      expect(d.permissions.canEditTeam, isTrue);
      expect(d.permissions.canEditCore, isTrue);
    });

    test('قائمة الاختيار والبحث العربي', () {
      final pickers = ProjectPickers.fromJson({
        'employees': [
          {'id': 'e1', 'name': 'أحمد علي', 'jobTitle': null, 'departmentId': 'd1', 'departmentName': 'الإعلام'},
        ],
        'departments': [
          {'id': 'd1', 'name': 'الإعلام'},
        ],
      });
      expect(pickers.byId('e1')?.subtitle, 'الإعلام');
      expect(normalizeArabic('أحمد علي').contains(normalizeArabic('احمد')), isTrue);
      expect(normalizeArabic('فاطمة'), 'فاطمه');
    });

    test('الكتالوج يحمل معرّف الموظف الحالي', () {
      final c = AssociationProjectsCatalog.fromJson({'projects': [], 'myEmployeeId': 'e9'});
      expect(c.myEmployeeId, 'e9');
    });
  });

  test('مهامي (0647): المتأخرة والقريبة تحتاج انتباهاً', () {
    final tasks = MyProjectTask.listFrom([
      {'stepId': 's1', 'title': 'تجهيز', 'status': 'in_progress', 'dueDate': '2026-10-01', 'isOverdue': true,
       'projectId': 'p1', 'projectName': 'مشروع', 'leaderName': 'أحمد'},
      {'stepId': 's2', 'title': 'تسليم', 'status': 'pending', 'dueDate': null, 'projectId': 'p1', 'projectName': 'مشروع'},
    ]);
    expect(tasks, hasLength(2));
    expect(tasks.first.needsAttention, isTrue);
    expect(tasks.last.needsAttention, isFalse);
    expect(tasks.last.leaderName, isNull);
    expect(MyProjectTask.listFrom(null), isEmpty);
  });

  test('رسالة الخادم العربية تظهر كما هي حتى مع رمز 42501', () {
    final msg = humanizeError(
      PostgrestException(message: 'لا يمكنك إنشاء مشروع إلا لإدارتك', code: '42501'),
    );
    expect(msg, 'لا يمكنك إنشاء مشروع إلا لإدارتك');
  });
}
