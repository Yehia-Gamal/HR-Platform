import 'package:ahla_shabab_management_os/features/mobile_pages/battery_notifications_guide_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detectFromManufacturer maps major Android brands cleanly', () {
    expect(
      DeviceVendorGroup.detectFromManufacturer('Xiaomi'),
      DeviceVendorGroup.xiaomi,
    );
    expect(
      DeviceVendorGroup.detectFromManufacturer('SAMSUNG'),
      DeviceVendorGroup.samsung,
    );
    expect(
      DeviceVendorGroup.detectFromManufacturer('OPPO'),
      DeviceVendorGroup.oppo,
    );
    expect(
      DeviceVendorGroup.detectFromManufacturer('HUAWEI'),
      DeviceVendorGroup.huawei,
    );
    expect(
      DeviceVendorGroup.detectFromManufacturer('Google'),
      DeviceVendorGroup.generic,
    );
  });

  testWidgets(
    'BatteryNotificationsGuidePage switches manufacturer instructions without overflow on large text scale',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: const BatteryNotificationsGuidePage(
              initialVendor: DeviceVendorGroup.xiaomi,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('شاومي / ريدمي / بوكو (MIUI / HyperOS)'),
        200,
        scrollable: scrollable,
      );
      expect(
        find.text('شاومي / ريدمي / بوكو (MIUI / HyperOS)'),
        findsOneWidget,
      );
      final samsungChip = find.text('سامسونج');
      await tester.ensureVisible(samsungChip);
      await tester.tap(samsungChip);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('سامسونج (One UI)'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('سامسونج (One UI)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
