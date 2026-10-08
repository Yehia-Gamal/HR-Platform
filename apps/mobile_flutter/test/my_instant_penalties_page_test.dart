import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

MobileInstantPenalty _penalty({
  required String id,
  required String status,
  int lateMinutes = 10,
  double original = 20,
  double current = 20,
  String? notes,
  String excuseStatus = 'none',
  DateTime? createdAt,
  String? receiptRef,
}) => MobileInstantPenalty(
  id: id,
  workDate: '2026-10-05',
  lateMinutes: lateMinutes,
  originalAmount: original,
  currentAmount: current,
  currency: 'EGP',
  status: status,
  notes: notes,
  createdAt: createdAt ?? DateTime(2026, 10, 4, 9, 30),
  excuseStatus: excuseStatus,
  excuseText: excuseStatus == 'submitted' ? 'ظرف طارئ وتأخير عن الميعاد' : null,
  receiptReferenceNumber: receiptRef,
);

Future<void> _pump(WidgetTester tester, List<MobileInstantPenalty> items) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myInstantPenaltiesProvider.overrideWith((ref) async => items),
      ],
      child: MaterialApp(
        locale: const Locale('ar', 'EG'),
        supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const MyInstantPenaltiesPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar_EG');
    DateFormat.useNativeDigitsByDefaultFor('ar', false);
    DateFormat.useNativeDigitsByDefaultFor('ar_EG', false);
  });

  testWidgets('يعرض الصفحة كاملة بدون أخطاء تجاوز أو استثناءات', (tester) async {
    await _pump(tester, [
      _penalty(
        id: 'p1',
        status: 'pending_payment',
        notes: 'تأخير 15 دقيقة عن موعد العمل 10:00 - تم تسجيل البطاقة',
      ),
      _penalty(
        id: 'p2',
        status: 'doubled',
        current: 500,
        original: 20,
        lateMinutes: 95,
        excuseStatus: 'submitted',
        notes: 'تأخير 95 دقيقة (وصل 11:35 موعد العمل 10:00) - تم الإرسال فريق تنفيذ الحضور',
      ),
      _penalty(
        id: 'p3',
        status: 'paid',
        receiptRef: '123456',
        notes: 'تم السداد بالكامل وأودع المبلغ في صندوق الزمالة',
      ),
      _penalty(
        id: 'p4',
        status: 'cancelled',
        notes: 'إلغاء بأثر رجعي - مأمورية بإذن المدير التنفيذي',
      ),
      _penalty(id: 'p5', status: 'suspended', current: 500, notes: 'تعليق الحساب'),
    ]);

    expect(find.text('غرامات الحضور وصندوق الزمالة'), findsOneWidget);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/my_instant_penalties_page.png'),
    );

    final err = tester.takeException();
    expect(err, isNull, reason: 'أخطاء تجاوز في التخطيط: $err');
  });

  testWidgets('يعرض الحالة الفارغة بدون أخطاء', (tester) async {
    await _pump(tester, const []);

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/my_instant_penalties_empty.png'),
    );

    final err = tester.takeException();
    expect(find.text('لا توجد غرامات على حسابك'), findsOneWidget);
    expect(err, isNull, reason: 'أخطاء تجاوز في التخطيط: $err');
  });
}
