import 'package:ahla_shabab_management_os/features/auth/login_page.dart';
import 'package:ahla_shabab_management_os/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('configuration errors are rendered in Arabic', (tester) async {
    await tester.pumpWidget(
      const ConfigurationErrorApp(message: 'SUPABASE_URL is missing'),
    );

    expect(find.text('إعداد التطبيق غير مكتمل'), findsOneWidget);
    expect(find.text('SUPABASE_URL is missing'), findsOneWidget);
  });

  // V12 §17: «نسيت كلمة المرور» مخفي ابتداءً ويظهر فقط بعد فشل بيانات الاعتماد.
  testWidgets('mobile login hides password recovery until credential failure',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginPage())),
    );

    // الرابط مخفي عند فتح الشاشة (V12 §17.1).
    expect(find.text('نسيت كلمة المرور؟'), findsNothing);
  });
}
