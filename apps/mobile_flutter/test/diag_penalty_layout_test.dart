import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
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
  excuseText: excuseStatus == 'submitted' ? 'ظرف طارئ' : null,
  receiptReferenceNumber: receiptRef,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ar_EG');
    DateFormat.useNativeDigitsByDefaultFor('ar', false);
    DateFormat.useNativeDigitsByDefaultFor('ar_EG', false);
  });

  testWidgets('تشخيص مواقع العناصر', (tester) async {
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
                notes: 'تأخير 15 دقيقة عن موعد العمل',
              ),
              _p(
                id: 'p4',
                status: 'cancelled',
                notes: 'إلغاء بأثر رجعي - مأمورية',
              ),
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
          home: const MyInstantPenaltiesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final buf = StringBuffer();
    final err = tester.takeException();
    buf.writeln('EXCEPTION: $err');

    void dump(String label, Finder f) {
      if (f.evaluate().isEmpty) {
        buf.writeln('$label -> NOT FOUND');
        return;
      }
      for (final e in f.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        buf.writeln(
          '$label -> ${e.widget.runtimeType} rect=${r.left.toStringAsFixed(0)},'
          '${r.top.toStringAsFixed(0)} ${r.width.toStringAsFixed(0)}x'
          '${r.height.toStringAsFixed(0)}'
          '${e.widget is Text ? ' "${(e.widget as Text).data}"' : ''}',
        );
      }
    }

    buf.writeln('--- Card ---');
    dump('Card', find.byType(Card));
    buf.writeln('--- Row (first 12) ---');
    final rows = find.byType(Row);
    for (var i = 0; i < rows.evaluate().length && i < 14; i++) {
      dump('Row$i', rows.at(i));
    }
    buf.writeln('--- Text ---');
    dump('Text', find.byType(Text));
    buf.writeln('--- Icon ---');
    dump('Icon', find.byType(Icon));

    buf.writeln('--- hit test probes ---');
    final painted = <(Element, Rect, String)>[];
    for (final e in tester.allElements) {
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final w = e.widget;
      if (w is! Text && w is! Icon && w is! Container && w is! Row && w is! Column) {
        continue;
      }
      final o = ro.localToGlobal(Offset.zero);
      painted.add((e, o & ro.size, w.toString().split('(').first));
    }
    for (final p in const [
      Offset(316, 140),
      Offset(316, 210),
      Offset(272, 470),
      Offset(272, 600),
      Offset(21, 300),
      Offset(340, 300),
    ]) {
      final hits = painted
          .where((t) => t.$2.inflate(1).contains(p))
          .map((t) => '${t.$3}(${t.$2.left.toStringAsFixed(0)},'
              '${t.$2.top.toStringAsFixed(0)} '
              '${t.$2.width.toStringAsFixed(0)}x${t.$2.height.toStringAsFixed(0)})'
              '${t.$1.widget is Text ? ':"${(t.$1.widget as Text).data}"' : ''}')
          .toList();
      buf.writeln('$p -> ${hits.join(' | ')}');
    }

    // ignore: avoid_print
    print(buf.toString());
    expect(true, isTrue);
  });
}
