import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPill(WidgetTester tester, String status) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: MobileStatusPill(status))),
      ),
    );
  }

  testWidgets('حالات الأجهزة تظهر بسمات عربية بدل raw الإنجليزية', (
    tester,
  ) async {
    // 0096: passkey_devices.status ∈ (pending, active, blocked, revoked, replaced)
    const expectations = {
      'active': 'نشط',
      'blocked': 'محظور',
      'revoked': 'ملغى',
      'replaced': 'مستبدل',
      'auto_revoked': 'إلغاء تلقائي',
    };
    for (final entry in expectations.entries) {
      await pumpPill(tester, entry.key);
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: 'status=${entry.key} يجب أن يُترجم',
      );
    }
  });

  testWidgets('حالة مجهولة تظهر كما هي (fallback)', (tester) async {
    await pumpPill(tester, 'mystery_status');
    expect(find.text('mystery_status'), findsOneWidget);
  });
}
