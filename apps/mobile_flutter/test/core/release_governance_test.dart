import 'package:ahla_shabab_management_os/features/mobile_data/release_governance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileReleasePolicy blocking rules', () {
    test('blocks old versions when action is update_required, maintenance, or blocked', () {
      expect(
        MobileReleasePolicy.fromJson({
          'action': 'update_required',
          'currentVersion': '0.13.30',
          'currentBuild': 50,
          'minSupportedVersion': '0.13.35',
          'minSupportedBuild': 55,
        }).blocksApplication,
        isTrue,
      );

      expect(
        MobileReleasePolicy.fromJson({'action': 'maintenance'}).blocksApplication,
        isTrue,
      );

      expect(
        MobileReleasePolicy.fromJson({'action': 'blocked'}).blocksApplication,
        isTrue,
      );
    });

    test('blocks even if action is update_available when forceUpdate, minBuild, or minVersion fails', () {
      expect(
        MobileReleasePolicy.fromJson({
          'action': 'update_available',
          'forceUpdate': true,
        }).blocksApplication,
        isTrue,
      );

      expect(
        MobileReleasePolicy.fromJson({
          'action': 'none',
          'currentBuild': 54,
          'minSupportedBuild': 58,
        }).blocksApplication,
        isTrue,
      );

      expect(
        MobileReleasePolicy.fromJson({
          'action': 'none',
          'currentVersion': '0.13.30',
          'minSupportedVersion': '0.13.37',
        }).blocksApplication,
        isTrue,
      );
    });

    test('allows supported builds and offline continue fallback', () {
      expect(
        MobileReleasePolicy.fromJson({
          'action': 'update_available',
          'currentVersion': '0.13.37',
          'currentBuild': 58,
          'minSupportedVersion': '0.13.35',
          'minSupportedBuild': 55,
          'forceUpdate': false,
        }).blocksApplication,
        isFalse,
      );
      expect(MobileReleasePolicy.continueAction().blocksApplication, isFalse);
    });
  });
}
