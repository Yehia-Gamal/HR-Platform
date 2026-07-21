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

  testWidgets('mobile login exposes password recovery', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginPage())),
    );

    expect(find.text('نسيت كلمة المرور؟'), findsOneWidget);
    await tester.tap(find.text('نسيت كلمة المرور؟'));
    await tester.pumpAndSettle();

    expect(
      find.text('أدخل بريدك المسجل وسنرسل رابط الاسترداد إليه.'),
      findsOneWidget,
    );
    expect(find.text('إرسال الرابط'), findsOneWidget);
  });
}
