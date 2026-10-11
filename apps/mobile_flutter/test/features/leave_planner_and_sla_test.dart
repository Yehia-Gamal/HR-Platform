import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SLA Tracker and Indicator Calculation Tests', () {
    test('Calculates fast tone for fresh request (< 2h)', () {
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(minutes: 45));

      final sla = calculateRequestSla(
        createdAt: createdAt,
        status: 'pending',
        activeStepName: 'المدير المباشر',
      );

      expect(sla.tone, RequestSlaTone.fast);
      expect(sla.isCompleted, isFalse);
      expect(sla.color, AppColors.statusSuccess);
      expect(sla.label, contains('جديد'));
      expect(sla.detail, contains('المدير المباشر'));
    });

    test('Calculates warning tone for requests pending between 2h and 24h', () {
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(hours: 14));

      final sla = calculateRequestSla(
        createdAt: createdAt,
        status: 'pending',
        activeStepName: 'الموارد البشرية',
      );

      expect(sla.tone, RequestSlaTone.warning);
      expect(sla.isCompleted, isFalse);
      expect(sla.color, const Color(0xFFD97706));
      expect(sla.label, contains('قيد الانتظار'));
      expect(sla.responsibleParty, 'الموارد البشرية');
    });

    test('Calculates breached tone for requests pending > 24h with responsible person', () {
      final now = DateTime.now();
      final createdAt = now.subtract(const Duration(hours: 36));

      final sla = calculateRequestSla(
        createdAt: createdAt,
        status: 'pending',
        activeStepName: 'مدير التشغيل 1',
        activeStepActor: 'أحمد محمود',
      );

      expect(sla.tone, RequestSlaTone.breached);
      expect(sla.isCompleted, isFalse);
      expect(sla.color, AppColors.statusDanger);
      expect(sla.label, contains('معلق أكثر من 24 س'));
      expect(sla.detail, contains('أحمد محمود'));
      expect(sla.responsibleParty, 'أحمد محمود');
    });

    test('Calculates completed fast turnaround (< 2h)', () {
      final createdAt = DateTime(2026, 10, 10, 10, 0);
      final decidedAt = DateTime(2026, 10, 10, 11, 15); // 1h 15m

      final sla = calculateRequestSla(
        createdAt: createdAt,
        status: 'approved',
        decidedAt: decidedAt,
        decidedByName: 'يحيى جمال',
      );

      expect(sla.tone, RequestSlaTone.fast);
      expect(sla.isCompleted, isTrue);
      expect(sla.color, AppColors.statusSuccess);
      expect(sla.label, contains('اعتماد قياسي'));
      expect(sla.responsibleParty, 'يحيى جمال');
    });

    testWidgets('RequestSlaChip renders correctly with color and label', (tester) async {
      final sla = RequestSlaInfo(
        tone: RequestSlaTone.breached,
        label: 'معلق 28 س',
        detail: 'واقف عند: الموارد البشرية',
        color: AppColors.statusDanger,
        icon: Icons.warning_amber_rounded,
        elapsed: const Duration(hours: 28),
        isCompleted: false,
        responsibleParty: 'الموارد البشرية',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RequestSlaChip(sla: sla),
            ),
          ),
        ),
      );

      expect(find.text('معلق 28 س'), findsOneWidget);
      expect(find.text('· الموارد البشرية'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });
}
