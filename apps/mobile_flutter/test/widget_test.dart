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

  // الرابط ظاهر دائماً بنص أوضح — "إعادة تعيين كلمة السر؟" يقود المستخدم
  // للإجراء مباشرة بدل أن ينتظر فشل محاولة دخول أولاً (V12 §17 لم يعد سارياً).
  testWidgets('mobile login shows password reset link permanently',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LoginPage())),
    );

    // الرابط ظاهر منذ فتح الشاشة — قابل للنقر فوراً.
    expect(find.text('إعادة تعيين كلمة السر؟'), findsOneWidget);
  });
}
