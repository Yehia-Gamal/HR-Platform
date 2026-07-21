import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attendance history parses server verification fields', () {
    final event = AttendanceHistoryItem.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'eventType': 'CHECK_IN',
      'eventAt': '2026-07-13T06:30:00Z',
      'status': 'accepted',
      'verificationStatus': 'passkey_verified',
      'lateMinutes': 4,
      'requiresReview': false,
      'accuracyMeters': 8.5,
      'distanceMeters': 20.0,
      'source': 'mobile',
    });

    expect(event.eventType, 'CHECK_IN');
    expect(event.verificationStatus, 'passkey_verified');
    expect(event.lateMinutes, 4);
    expect(event.accuracyMeters, 8.5);
  });

  test('passkey device parses revocation and backup metadata', () {
    final device = PasskeyDevice.fromJson({
      'id': '22222222-2222-4222-8222-222222222222',
      'deviceLabel': 'هاتف العمل',
      'status': 'revoked',
      'trusted': false,
      'deviceType': 'multiDevice',
      'backedUp': true,
      'createdAt': '2026-07-13T06:30:00Z',
    });

    expect(device.status, 'revoked');
    expect(device.backedUp, isTrue);
    expect(device.trusted, isFalse);
  });
}
