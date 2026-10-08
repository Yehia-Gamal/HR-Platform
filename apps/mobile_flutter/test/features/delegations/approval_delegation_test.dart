import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApprovalDelegation Model Tests', () {
    test('parses json correctly for active delegation', () {
      final json = {
        'id': 'del-123',
        'manager_employee_id': 'mgr-001',
        'manager_name': 'أحمد علي',
        'manager_code': 'M01',
        'delegate_employee_id': 'del-002',
        'delegate_name': 'محمد حسن',
        'delegate_code': 'E02',
        'starts_at': '2026-10-08',
        'ends_at': '2026-10-15',
        'reason': 'إجازة سنوية',
        'cancelled_at': null,
        'created_at': '2026-10-08T10:00:00Z',
        'is_mine': true,
        'is_active': true,
        'status': 'active',
      };

      final d = ApprovalDelegation.fromJson(json);

      expect(d.id, 'del-123');
      expect(d.managerEmployeeId, 'mgr-001');
      expect(d.managerName, 'أحمد علي');
      expect(d.delegateEmployeeId, 'del-002');
      expect(d.delegateName, 'محمد حسن');
      expect(d.startsAt, '2026-10-08');
      expect(d.endsAt, '2026-10-15');
      expect(d.reason, 'إجازة سنوية');
      expect(d.isMine, true);
      expect(d.isActive, true);
      expect(d.status, 'active');
      expect(d.cancelledAt, isNull);
    });

    test('handles cancelled delegation with timestamp', () {
      final json = {
        'id': 'del-456',
        'manager_employee_id': 'mgr-001',
        'manager_name': 'أحمد علي',
        'manager_code': 'M01',
        'delegate_employee_id': 'del-002',
        'delegate_name': 'محمد حسن',
        'delegate_code': 'E02',
        'starts_at': '2026-10-01',
        'ends_at': '2026-10-10',
        'cancelled_at': '2026-10-05T12:00:00Z',
        'created_at': '2026-10-01T08:00:00Z',
        'is_mine': false,
        'is_active': false,
        'status': 'cancelled',
      };

      final d = ApprovalDelegation.fromJson(json);

      expect(d.id, 'del-456');
      expect(d.isMine, false);
      expect(d.isActive, false);
      expect(d.status, 'cancelled');
      expect(d.cancelledAt, isNotNull);
      expect(d.cancelledAt?.day, 5);
    });
  });
}
