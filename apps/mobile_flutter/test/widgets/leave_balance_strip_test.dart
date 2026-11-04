import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_list_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('LeaveBalanceStrip يعرض جميع أرصدة الإجازات وبطاقة أذونات الشهر الـ 4', (tester) async {
    bool leaveTapped = false;
    bool permitTapped = false;

    final balances = [
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-annual',
        'code': 'annual',
        'name_ar': 'سنوية',
        'available_units': 14,
        'consumed_units': 2,
        'reserved_units': 0,
      }),
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-casual',
        'code': 'casual',
        'name_ar': 'عارضة',
        'available_units': 5,
        'consumed_units': 1,
        'reserved_units': 0,
      }),
      MobileLeaveBalance.fromJson({
        'leave_type_id': 'lt-rest',
        'code': 'rest_day',
        'name_ar': 'بدل راحة أسبوعية',
        'available_units': 1,
        'consumed_units': 4,
        'reserved_units': 0,
      }),
    ];

    final permitBalance = MobilePermitBalance.fromJson({
      'month': '2026-11',
      'max_permits': 4,
      'max_hours': 8,
      'used_approved': 0,
      'used_pending': 0,
      'total_used': 0,
      'remaining_permits': 4,
      'remaining_hours': 8,
      'minutes_per_permit': 120,
      'has_remaining': true,
      'items': [],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myPermitBalanceProvider.overrideWith((ref) async => permitBalance),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SingleChildScrollView(
                child: LeaveBalanceStrip(
                  balances: balances,
                  onTap: () => leaveTapped = true,
                  onPermitTap: () => permitTapped = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // التحقق من ظهور بطاقة أذونات الشهر
    expect(find.text('أذونات الشهر'), findsOneWidget);
    expect(find.text('من 4 أذونات'), findsOneWidget);
    expect(find.text('(8 س)'), findsOneWidget);

    // التحقق من ظهور بطاقات الإجازات
    expect(find.text('سنوية'), findsOneWidget);
    expect(find.text('عارضة'), findsOneWidget);
    expect(find.text('بدل راحة أسبوعية'), findsOneWidget);

    // النقر على بطاقة الأذونات
    await tester.tap(find.text('أذونات الشهر'));
    expect(permitTapped, isTrue);

    // النقر على بطاقة الإجازة
    await tester.tap(find.text('سنوية'));
    expect(leaveTapped, isTrue);

    // التبديل بين العرض الشبكي والشريط
    expect(find.text('عرض شريط'), findsOneWidget);
    await tester.tap(find.text('عرض شريط'));
    await tester.pumpAndSettle();
    expect(find.text('عرض شبكي'), findsOneWidget);
  });
}

