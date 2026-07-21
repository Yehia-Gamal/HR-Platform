import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _contextJson({
  List<String> roles = const ['employee'],
  List<String> permissions = const ['reports.people.read'],
  List<String> workspaces = const ['employee'],
  String defaultWorkspace = 'employee',
  Map<String, dynamic>? attendancePolicy,
}) {
  return {
    'userId': '11111111-1111-4111-8111-111111111111',
    'employeeId': '22222222-2222-4222-8222-222222222222',
    'displayName': 'موظف',
    'employeeCode': 'EMP-001',
    'roles': roles,
    'permissions': permissions,
    'workspaces': workspaces,
    'defaultWorkspace': defaultWorkspace,
    'attendancePolicy':
        attendancePolicy ??
        const {
          'attendanceRequired': true,
          'selfPunchEnabled': true,
          'liveLocationResponseEnabled': false,
        },
  };
}

void main() {
  group('AccessContext.fromJson', () {
    test('executive context disables self attendance', () {
      final context = AccessContext.fromJson(
        _contextJson(
          roles: ['executive-director'],
          workspaces: ['executive'],
          defaultWorkspace: 'executive',
          attendancePolicy: const {
            'attendanceRequired': false,
            'selfPunchEnabled': false,
            'liveLocationResponseEnabled': false,
          },
        ),
      );

      expect(context.defaultWorkspace, WorkspaceId.executive);
      expect(context.attendancePolicy.selfPunchEnabled, isFalse);
    });

    test('parses nullable employee identity fields', () {
      final json = _contextJson()
        ..['employeeId'] = null
        ..['employeeCode'] = null;
      final context = AccessContext.fromJson(json);

      expect(context.employeeId, isNull);
      expect(context.employeeCode, isNull);
    });

    test('defaults missing role and permission lists to empty', () {
      final json = _contextJson()
        ..remove('roles')
        ..remove('permissions');
      final context = AccessContext.fromJson(json);

      expect(context.roles, isEmpty);
      expect(context.permissions, isEmpty);
    });
  });

  group('WorkspaceId.fromWire', () {
    test('maps every known wire value including snake_case forms', () {
      expect(WorkspaceId.fromWire('employee'), WorkspaceId.employee);
      expect(WorkspaceId.fromWire('manager'), WorkspaceId.manager);
      expect(WorkspaceId.fromWire('executive'), WorkspaceId.executive);
      expect(WorkspaceId.fromWire('hr'), WorkspaceId.hr);
      expect(WorkspaceId.fromWire('main_admin'), WorkspaceId.mainAdmin);
      expect(WorkspaceId.fromWire('committee'), WorkspaceId.committee);
      expect(
        WorkspaceId.fromWire('field_operations'),
        WorkspaceId.fieldOperations,
      );
    });

    test('throws a FormatException on an unknown workspace', () {
      expect(
        () => WorkspaceId.fromWire('unknown'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('permission checks', () {
    test('wildcard grants any permission', () {
      final context = AccessContext.fromJson(_contextJson(permissions: ['*']));

      expect(context.hasPermission('people.employee.delete'), isTrue);
      expect(context.hasAnyPermission(['anything.at.all']), isTrue);
    });

    test('explicit permission is matched exactly', () {
      final context = AccessContext.fromJson(
        _contextJson(permissions: ['requests.request.read']),
      );

      expect(context.hasPermission('requests.request.read'), isTrue);
      expect(context.hasPermission('requests.request.decide'), isFalse);
    });

    test('hasAnyPermission returns true when at least one code matches', () {
      final context = AccessContext.fromJson(
        _contextJson(permissions: ['performance.kpi.read']),
      );

      expect(
        context.hasAnyPermission([
          'performance.kpi.decide',
          'performance.kpi.read',
        ]),
        isTrue,
      );
      expect(context.hasAnyPermission(['performance.kpi.decide']), isFalse);
    });
  });
}
