import 'package:ahla_shabab_management_os/core/theme/theme_mode_controller.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('theme preference serialization is stable', () {
    expect(parseThemeMode('light'), ThemeMode.light);
    expect(parseThemeMode('dark'), ThemeMode.dark);
    expect(parseThemeMode('system'), ThemeMode.system);
    expect(parseThemeMode('unknown'), ThemeMode.system);
    expect(serializeThemeMode(ThemeMode.dark), 'dark');
  });

  testWidgets('avatar safely renders an empty-name fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppAvatar(name: '', radius: 24)),
      ),
    );

    expect(find.text('؟'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
