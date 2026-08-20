import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:ahla_shabab_management_os/shared/permission_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PermissionGate renders child when permission is granted',
      (tester) async {
    final mockAccess = AccessContext(
      userId: 'test-user',
      employeeId: 'emp-123',
      displayName: 'Test User',
      employeeCode: '12345',
      roles: ['employee'],
      permissions: ['requests.request.decide'],
      workspaces: [WorkspaceId.employee],
      defaultWorkspace: WorkspaceId.employee,
      attendancePolicy: AttendancePolicy(
        attendanceRequired: true,
        selfPunchEnabled: true,
        liveLocationResponseEnabled: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith((ref) => Future.value(mockAccess)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PermissionGate(
              permission: 'requests.request.decide',
              child: Text('Authorized Content'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Authorized Content'), findsOneWidget);
  });

  testWidgets('PermissionGate hides child when permission is denied',
      (tester) async {
    final mockAccess = AccessContext(
      userId: 'test-user',
      employeeId: 'emp-123',
      displayName: 'Test User',
      employeeCode: '12345',
      roles: ['employee'],
      permissions: ['requests.request.read'],
      workspaces: [WorkspaceId.employee],
      defaultWorkspace: WorkspaceId.employee,
      attendancePolicy: AttendancePolicy(
        attendanceRequired: true,
        selfPunchEnabled: true,
        liveLocationResponseEnabled: false,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accessContextProvider.overrideWith((ref) => Future.value(mockAccess)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PermissionGate(
              permission: 'requests.request.decide',
              child: Text('Authorized Content'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Authorized Content'), findsNothing);
    expect(find.text('غير مصرّح لك بالوصول إلى هذه الخاصية'), findsOneWidget);
  });
}
