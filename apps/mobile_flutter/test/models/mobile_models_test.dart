import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileRequest.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = {
        'id': 'req-001',
        'requestNumber': 42,
        'requestType': 'leave',
        'employeeName': 'أحمد محمد',
        'employeePhotoUrl': 'https://example.com/photo.jpg',
        'title': 'إجازة سنوية',
        'reason': 'ظروف عائلية',
        'status': 'approved',
        'workflowStatus': 'completed',
        'activeStepName': 'المدير',
        'createdAt': '2026-07-15T10:30:00Z',
      };
      final req = MobileRequest.fromJson(json);
      expect(req.id, 'req-001');
      expect(req.number, 42);
      expect(req.type, 'leave');
      expect(req.employeeName, 'أحمد محمد');
      expect(req.employeePhotoUrl, 'https://example.com/photo.jpg');
      expect(req.title, 'إجازة سنوية');
      expect(req.reason, 'ظروف عائلية');
      expect(req.status, 'approved');
      expect(req.workflowStatus, 'completed');
      expect(req.activeStepName, 'المدير');
      expect(req.createdAt.year, 2026);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final json = <String, dynamic>{
        'id': 'req-002',
        'requestType': 'permit',
      };
      final req = MobileRequest.fromJson(json);
      expect(req.employeeName, 'موظف');
      expect(req.status, 'pending');
      expect(req.workflowStatus, 'submitted');
      expect(req.number, 0);
      expect(req.employeePhotoUrl, isNull);
      expect(req.title, isNull);
      expect(req.reason, isNull);
      expect(req.activeStepName, isNull);
    });

    test('يرجع DateTime(0) عند createdAt فارغ', () {
      final json = <String, dynamic>{
        'id': 'req-003',
        'requestType': 'leave',
        'createdAt': null,
      };
      final req = MobileRequest.fromJson(json);
      expect(req.createdAt, DateTime(0));
    });
  });

  group('ManagerDashboardSummary.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'teamMembers': 15,
        'pendingRequests': 3,
        'pendingKpi': 7,
        'lateToday': 2,
      };
      final summary = ManagerDashboardSummary.fromJson(json);
      expect(summary.teamMembers, 15);
      expect(summary.pendingRequests, 3);
      expect(summary.pendingKpi, 7);
      expect(summary.lateToday, 2);
    });

    test('يستخدم صفر كقيمة افتراضية لكل الحقول', () {
      final summary =
          ManagerDashboardSummary.fromJson(const <String, dynamic>{});
      expect(summary.teamMembers, 0);
      expect(summary.pendingRequests, 0);
      expect(summary.pendingKpi, 0);
      expect(summary.lateToday, 0);
    });
  });

  group('ExecutiveDashboardSummary.fromJson', () {
    test('يحلل الحقول المتداخلة من dailyReport', () {
      final json = <String, dynamic>{
        'urgentActions': 2,
        'pendingApprovals': 5,
        'pendingFinalKpi': 3,
        'publishedDecisions': 10,
        'openCases': 1,
        'activeLocationRequests': 4,
        'dailyReport': {
          'attendance': {'present': 75},
          'employees': {'requiredToday': 100},
        },
      };
      final summary = ExecutiveDashboardSummary.fromJson(json);
      expect(summary.urgentActions, 2);
      expect(summary.pendingApprovals, 5);
      expect(summary.pendingFinalKpi, 3);
      expect(summary.publishedDecisions, 10);
      expect(summary.openCases, 1);
      expect(summary.activeLocationRequests, 4);
      expect(summary.attendancePresent, 75);
      expect(summary.attendanceRequired, 100);
    });

    test('يحسب نسبة الحضور بشكل صحيح', () {
      final json = <String, dynamic>{
        'dailyReport': {
          'attendance': {'present': 75},
          'employees': {'requiredToday': 100},
        },
      };
      final summary = ExecutiveDashboardSummary.fromJson(json);
      expect(summary.attendanceRate, 75);
    });

    test('نسبة الحضور صفر عندما العدد المطلوب صفر', () {
      final json = <String, dynamic>{
        'dailyReport': {
          'attendance': {'present': 0},
          'employees': {'requiredToday': 0},
        },
      };
      final summary = ExecutiveDashboardSummary.fromJson(json);
      expect(summary.attendanceRate, 0);
    });

    test('نسبة الحضور مع أعداد غير متساوية', () {
      final json = <String, dynamic>{
        'dailyReport': {
          'attendance': {'present': 33},
          'employees': {'requiredToday': 50},
        },
      };
      final summary = ExecutiveDashboardSummary.fromJson(json);
      // 33 * 100 ~/ 50 = 66
      expect(summary.attendanceRate, 66);
    });

    test('يستخدم القيم الافتراضية بدون dailyReport', () {
      final summary =
          ExecutiveDashboardSummary.fromJson(const <String, dynamic>{});
      expect(summary.attendancePresent, 0);
      expect(summary.attendanceRequired, 0);
      expect(summary.attendanceRate, 0);
      expect(summary.urgentActions, 0);
    });
  });

  group('EmployeeHomeSummary.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'pendingRequests': 2,
        'activeTasks': 5,
        'kpiStage': 'self',
        'unreadNotifications': 3,
        'unreadOfficial': 1,
        'pendingLocationRequests': 0,
      };
      final summary = EmployeeHomeSummary.fromJson(json);
      expect(summary.pendingRequests, 2);
      expect(summary.activeTasks, 5);
      expect(summary.kpiStage, 'self');
      expect(summary.unreadNotifications, 3);
      expect(summary.unreadOfficial, 1);
      expect(summary.pendingLocationRequests, 0);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final summary =
          EmployeeHomeSummary.fromJson(const <String, dynamic>{});
      expect(summary.pendingRequests, 0);
      expect(summary.activeTasks, 0);
      expect(summary.kpiStage, isNull);
      expect(summary.unreadNotifications, 0);
      expect(summary.unreadOfficial, 0);
      expect(summary.pendingLocationRequests, 0);
    });
  });

  group('MobileRequestStep.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'id': 'step-001',
        'order': 1,
        'name': 'مراجعة المدير',
        'status': 'approved',
        'decision': 'approve',
        'comment': 'موافق',
        'decidedAt': '2026-07-10T14:00:00Z',
        'dueAt': '2026-07-12T23:59:59Z',
        'actorName': 'أحمد',
      };
      final step = MobileRequestStep.fromJson(json);
      expect(step.id, 'step-001');
      expect(step.order, 1);
      expect(step.name, 'مراجعة المدير');
      expect(step.status, 'approved');
      expect(step.decision, 'approve');
      expect(step.comment, 'موافق');
      expect(step.decidedAt, isNotNull);
      expect(step.decidedAt!.year, 2026);
      expect(step.dueAt, isNotNull);
      expect(step.actorName, 'أحمد');
    });

    test('decidedAt و dueAt يكونان null عند عدم وجودهما', () {
      final json = <String, dynamic>{
        'id': 'step-002',
        'order': 2,
        'name': 'مرحلة HR',
        'status': 'pending',
      };
      final step = MobileRequestStep.fromJson(json);
      expect(step.decidedAt, isNull);
      expect(step.dueAt, isNull);
      expect(step.decision, isNull);
      expect(step.comment, isNull);
      expect(step.actorName, isNull);
    });

    test('يستخدم القيم الافتراضية للاسم والحالة', () {
      final step = MobileRequestStep.fromJson(
          const <String, dynamic>{'id': 'step-003'});
      expect(step.name, 'مرحلة اعتماد');
      expect(step.status, 'pending');
      expect(step.order, 0);
    });
  });

  group('MobileRequestAttachment.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'path': 'attachments/doc.pdf',
        'mimeType': 'application/pdf',
        'sizeBytes': 1024,
      };
      final att = MobileRequestAttachment.fromJson(json);
      expect(att.path, 'attachments/doc.pdf');
      expect(att.mimeType, 'application/pdf');
      expect(att.sizeBytes, 1024);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final att = MobileRequestAttachment.fromJson(
          const <String, dynamic>{'path': 'file.bin'});
      expect(att.mimeType, 'application/octet-stream');
      expect(att.sizeBytes, 0);
    });
  });

  group('AttendanceState.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'attendanceRequired': true,
        'selfPunchEnabled': true,
        'activeLocalDevices': 2,
        'hasActiveLocalDevice': true,
        'canPunch': true,
        'suggestedAction': 'CHECK_OUT',
        'lastEventType': 'CHECK_IN',
        'lastEventAt': '2026-07-15T08:00:00Z',
        'lastEventStatus': 'present',
        'todayStatus': 'present',
        'localDeviceStatus': 'active',
      };
      final state = AttendanceState.fromJson(json);
      expect(state.attendanceRequired, isTrue);
      expect(state.selfPunchEnabled, isTrue);
      expect(state.activeLocalDevices, 2);
      expect(state.hasActiveLocalDevice, isTrue);
      expect(state.canPunch, isTrue);
      expect(state.suggestedAction, 'CHECK_OUT');
      expect(state.lastEventType, 'CHECK_IN');
      expect(state.lastEventAt!.year, 2026);
      expect(state.lastEventStatus, 'present');
      expect(state.todayStatus, 'present');
      expect(state.localDeviceStatus, 'active');
    });

    test('يدعم أسماء الحقول القديمة (activePasskeys)', () {
      final json = <String, dynamic>{
        'activePasskeys': 3,
        'hasActivePasskey': true,
      };
      final state = AttendanceState.fromJson(json);
      expect(state.activeLocalDevices, 3);
      expect(state.hasActiveLocalDevice, isTrue);
    });

    test('الحقول الجديدة لها أولوية على القديمة', () {
      final json = <String, dynamic>{
        'activeLocalDevices': 5,
        'activePasskeys': 3,
        'hasActiveLocalDevice': true,
        'hasActivePasskey': false,
      };
      final state = AttendanceState.fromJson(json);
      expect(state.activeLocalDevices, 5);
      expect(state.hasActiveLocalDevice, isTrue);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final state = AttendanceState.fromJson(const <String, dynamic>{});
      expect(state.attendanceRequired, isFalse);
      expect(state.selfPunchEnabled, isFalse);
      expect(state.activeLocalDevices, 0);
      expect(state.hasActiveLocalDevice, isFalse);
      expect(state.canPunch, isFalse);
      expect(state.suggestedAction, 'CHECK_IN');
      expect(state.lastEventType, isNull);
      expect(state.lastEventAt, isNull);
      expect(state.todayStatus, isNull);
      expect(state.localDeviceStatus, isNull);
    });
  });

  group('MobileFeedItem.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'id': 'feed-001',
        'kind': 'announcement',
        'title': 'إعلان مهم',
        'body': 'محتوى الإعلان',
        'priority': 'urgent',
        'requiresAcknowledgement': true,
        'myAcknowledged': false,
        'publishedAt': '2026-07-20T12:00:00Z',
        'imageUrl': 'https://example.com/img.jpg',
        'postType': 'decision',
        'authorName': 'المدير',
        'authorPhotoUrl': 'https://example.com/photo.jpg',
      };
      final item = MobileFeedItem.fromJson(json);
      expect(item.id, 'feed-001');
      expect(item.kind, 'announcement');
      expect(item.title, 'إعلان مهم');
      expect(item.body, 'محتوى الإعلان');
      expect(item.priority, 'urgent');
      expect(item.requiresAcknowledgement, isTrue);
      expect(item.myAcknowledged, isFalse);
      expect(item.publishedAt!.year, 2026);
      expect(item.postType, 'decision');
      expect(item.authorName, 'المدير');
    });

    test('postTypeLabel يرجع "إعلان" للنوع announcement', () {
      final item = MobileFeedItem.fromJson(const <String, dynamic>{
        'id': 'f1',
        'postType': 'announcement',
      });
      expect(item.postTypeLabel, 'إعلان');
    });

    test('postTypeLabel يرجع "قرار إداري" للنوع decision', () {
      final item = MobileFeedItem.fromJson(const <String, dynamic>{
        'id': 'f2',
        'postType': 'decision',
      });
      expect(item.postTypeLabel, 'قرار إداري');
    });

    test('postTypeLabel يرجع "تنبيه" للنوع alert', () {
      final item = MobileFeedItem.fromJson(const <String, dynamic>{
        'id': 'f3',
        'postType': 'alert',
      });
      expect(item.postTypeLabel, 'تنبيه');
    });

    test('postTypeLabel يرجع kind لنوع غير معروف', () {
      final item = MobileFeedItem.fromJson(const <String, dynamic>{
        'id': 'f4',
        'kind': 'custom_type',
        'postType': 'unknown_type',
      });
      expect(item.postTypeLabel, 'custom_type');
    });

    test('postTypeLabel يستخدم kind عندما postType فارغ', () {
      final item = MobileFeedItem.fromJson(const <String, dynamic>{
        'id': 'f5',
        'kind': 'announcement',
      });
      // postType هو null، فيستخدم kind = 'announcement' → 'إعلان'
      expect(item.postTypeLabel, 'إعلان');
    });
  });

  group('MobileNotificationItem.fromJson', () {
    test('يحلل كل الحقول بشكل صحيح', () {
      final json = <String, dynamic>{
        'id': 'notif-001',
        'title': 'طلب جديد',
        'body': 'تم تقديم طلب إجازة',
        'category': 'requests',
        'priority': 'high',
        'actionUrl': '/requests/req-001',
        'entityType': 'request',
        'entityId': 'req-001',
        'isRead': false,
        'createdAt': '2026-07-25T09:00:00Z',
      };
      final notif = MobileNotificationItem.fromJson(json);
      expect(notif.id, 'notif-001');
      expect(notif.title, 'طلب جديد');
      expect(notif.body, 'تم تقديم طلب إجازة');
      expect(notif.category, 'requests');
      expect(notif.priority, 'high');
      expect(notif.entityType, 'request');
      expect(notif.entityId, 'req-001');
      expect(notif.isRead, isFalse);
    });

    test('hasSupportedAction يرجع true لنوع مدعوم مع entityId', () {
      final notif = MobileNotificationItem.fromJson(const <String, dynamic>{
        'id': 'n1',
        'entityType': 'request',
        'entityId': 'req-123',
      });
      expect(notif.hasSupportedAction, isTrue);
    });

    test('hasSupportedAction يرجع true لنوع kpi', () {
      final notif = MobileNotificationItem.fromJson(const <String, dynamic>{
        'id': 'n2',
        'entityType': 'kpi',
        'entityId': 'kpi-123',
      });
      expect(notif.hasSupportedAction, isTrue);
    });

    test('hasSupportedAction يرجع false بدون entityId', () {
      final notif = MobileNotificationItem.fromJson(const <String, dynamic>{
        'id': 'n3',
        'entityType': 'request',
      });
      expect(notif.hasSupportedAction, isFalse);
    });

    test('hasSupportedAction يرجع false لنوع غير مدعوم', () {
      final notif = MobileNotificationItem.fromJson(const <String, dynamic>{
        'id': 'n4',
        'entityType': 'unknown_entity',
        'entityId': 'x-123',
      });
      expect(notif.hasSupportedAction, isFalse);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final notif = MobileNotificationItem.fromJson(
          const <String, dynamic>{'id': 'n5'});
      expect(notif.title, '');
      expect(notif.body, isNull);
      expect(notif.category, 'general');
      expect(notif.priority, 'normal');
      expect(notif.isRead, isFalse);
      expect(notif.createdAt, DateTime(0));
    });
  });

  group('MobileLeaveBalance.fromJson', () {
    test('يحلل حقول snake_case بشكل صحيح', () {
      final json = <String, dynamic>{
        'leave_type_id': 'lt-001',
        'code': 'ANNUAL',
        'name_ar': 'إجازة سنوية',
        'available_units': 21.0,
        'reserved_units': 3.0,
        'consumed_units': 5.0,
        'expires_at': '2026-12-31T23:59:59Z',
      };
      final balance = MobileLeaveBalance.fromJson(json);
      expect(balance.leaveTypeId, 'lt-001');
      expect(balance.code, 'ANNUAL');
      expect(balance.name, 'إجازة سنوية');
      expect(balance.availableUnits, 21.0);
      expect(balance.reservedUnits, 3.0);
      expect(balance.consumedUnits, 5.0);
      expect(balance.expiresAt, isNotNull);
      expect(balance.expiresAt!.year, 2026);
    });

    test('يستخدم القيم الافتراضية للحقول الناقصة', () {
      final balance = MobileLeaveBalance.fromJson(
          const <String, dynamic>{'leave_type_id': 'lt-002'});
      expect(balance.code, '');
      expect(balance.name, 'إجازة');
      expect(balance.availableUnits, 0.0);
      expect(balance.reservedUnits, 0.0);
      expect(balance.consumedUnits, 0.0);
      expect(balance.expiresAt, isNull);
    });
  });
}
