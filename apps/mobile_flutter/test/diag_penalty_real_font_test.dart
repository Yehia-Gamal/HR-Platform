import 'dart:io';

import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

MobileInstantPenalty _p({
  required String id,
  required String status,
  int lateMinutes = 10,
  double original = 20,
  double current = 20,
  String? notes,
  String excuseStatus = 'none',
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
  createdAt: DateTime(2026, 10, 4, 9, 30),
  excuseStatus: excuseStatus,
  excuseText: excuseStatus == 'submitted' ? 'ظرف طارئ وتأخير' : null,
  receiptReferenceNumber: receiptRef,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar_EG');
    DateFormat.useNativeDigitsByDefaultFor('ar', false);
    DateFormat.useNativeDigitsByDefaultFor('ar_EG', false);
    final cairo = await File('assets/fonts/Cairo.ttf').readAsBytes();
    final loader = FontLoader('RealArabic')
      ..addFont(Future.value(ByteData.view(cairo.buffer)));
    await loader.load();
  });

  testWidgets('قياس بخط عربي حقيقي', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myInstantPenaltiesProvider.overrideWith(
            (ref) async => [
              _p(
                id: 'p1',
                status: 'pending_payment',
                notes: 'تأخير 15 دقيقة عن موعد العمل 10:00 - تم تسجيل البطاقة',
              ),
              _p(
                id: 'p2',
                status: 'doubled',
                original: 20,
                current: 500,
                lateMinutes: 95,
                notes: 'تأخير 95 دقيقة (وصل 11:35 موعد العمل 10:00)',
              ),
              _p(
                id: 'p4',
                status: 'cancelled',
                notes: 'إلغاء بأثر رجعي - مأمورية بإذن المدير التنفيذي',
              ),
              _p(id: 'p5', status: 'suspended', current: 500, notes: 'تعليق'),
            ],
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ar', 'EG'),
          supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(fontFamily: 'RealArabic'),
          home: const MyInstantPenaltiesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final buf = StringBuffer();
    buf.writeln('EXCEPTION: ${tester.takeException()}');
    buf.writeln('--- Text rects (width, height) ---');
    for (final e in tester.allElements) {
      final w = e.widget;
      if (w is! Text) continue;
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.hasSize) continue;
      final o = ro.localToGlobal(Offset.zero);
      final r = o & ro.size;
      final data = (w.data ?? '').replaceAll('\n', ' / ');
      final flag = r.width < 60 && r.height > 60 ? '  <<< NARROW/TALL' : '';
      buf.writeln(
        '  ${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)} '
        '${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)} "$data"$flag',
      );
    }
    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}
