import 'package:ahla_shabab_management_os/features/mobile_data/push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PushService Lifecycle & Singleton Reference', () {
    test('PushService registers instance on construction', () {
      final service = PushService((token, platform) async {});
      expect(PushService.instance, isNotNull);
      expect(identical(PushService.instance, service), isTrue);
    });

    test('PushService urgent channel constants are defined', () {
      expect(PushService.urgentChannelId, isNotEmpty);
      expect(PushService.urgentChannelName, contains('الموقع'));
    });
  });
}
