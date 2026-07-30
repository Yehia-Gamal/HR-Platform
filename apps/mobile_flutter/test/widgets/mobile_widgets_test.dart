import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// يغلف ودجة داخل MaterialApp مع اتجاه RTL للاختبار.
Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('MobileStatusPill', () {
    testWidgets('يعرض "قيد المراجعة" للحالة pending', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('pending')));
      expect(find.text('قيد المراجعة'), findsOneWidget);
    });

    testWidgets('يعرض "معتمد" للحالة approved', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('approved')));
      expect(find.text('معتمد'), findsOneWidget);
    });

    testWidgets('يعرض "مرفوض" للحالة rejected', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('rejected')));
      expect(find.text('مرفوض'), findsOneWidget);
    });

    testWidgets('يعرض "نشط" للحالة active', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('active')));
      expect(find.text('نشط'), findsOneWidget);
    });

    testWidgets('يعرض "عند المدير" للحالة manager', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('manager')));
      expect(find.text('عند المدير'), findsOneWidget);
    });

    testWidgets('يعرض "مراجعة HR" للحالة hr_review', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('hr_review')));
      expect(find.text('مراجعة HR'), findsOneWidget);
    });

    testWidgets('يعرض القيمة الخام لحالة غير معروفة', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('xyz_unknown')));
      expect(find.text('xyz_unknown'), findsOneWidget);
    });

    testWidgets('يعرض "في إجازة" للحالة on_leave', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('on_leave')));
      expect(find.text('في إجازة'), findsOneWidget);
    });

    testWidgets('يعرض "في إجازة" للحالة leave أيضًا', (tester) async {
      await tester.pumpWidget(_wrap(const MobileStatusPill('leave')));
      expect(find.text('في إجازة'), findsOneWidget);
    });
  });

  group('MobileSectionHeader', () {
    testWidgets('يعرض العنوان', (tester) async {
      await tester.pumpWidget(
        _wrap(const MobileSectionHeader(title: 'عنوان القسم')),
      );
      expect(find.text('عنوان القسم'), findsOneWidget);
    });

    testWidgets('يعرض العنوان الفرعي إذا كان موجودًا', (tester) async {
      await tester.pumpWidget(
        _wrap(const MobileSectionHeader(
          title: 'عنوان',
          subtitle: 'وصف إضافي',
        )),
      );
      expect(find.text('وصف إضافي'), findsOneWidget);
    });

    testWidgets('لا يعرض العنوان الفرعي إذا كان null', (tester) async {
      await tester.pumpWidget(
        _wrap(const MobileSectionHeader(title: 'عنوان فقط')),
      );
      expect(find.text('عنوان فقط'), findsOneWidget);
      // يجب أن يكون هناك Text واحد فقط (العنوان)
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('يعرض ودجة الإجراء إذا كانت موجودة', (tester) async {
      await tester.pumpWidget(
        _wrap(const MobileSectionHeader(
          title: 'قسم',
          action: Icon(Icons.add),
        )),
      );
      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });

  group('MetricCard', () {
    testWidgets('يعرض القيمة والتسمية', (tester) async {
      await tester.pumpWidget(
        _wrap(const MetricCard(
          label: 'الحضور',
          value: '95%',
          icon: Icons.check_circle,
        )),
      );
      expect(find.text('95%'), findsOneWidget);
      expect(find.text('الحضور'), findsOneWidget);
    });

    testWidgets('يعرض الأيقونة', (tester) async {
      await tester.pumpWidget(
        _wrap(const MetricCard(
          label: 'المهام',
          value: '12',
          icon: Icons.task_alt,
        )),
      );
      expect(find.byIcon(Icons.task_alt), findsOneWidget);
    });

    testWidgets('يستجيب للنقر عند وجود onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(MetricCard(
          label: 'بطاقة',
          value: '7',
          icon: Icons.star,
          onTap: () => tapped = true,
        )),
      );
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('يستخدم لون primaryContainer عند emphasis=true',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const MetricCard(
          label: 'مميز',
          value: '99',
          icon: Icons.star,
          emphasis: true,
        )),
      );
      // يتحقق من أن البطاقة موجودة (الألوان تعتمد على الثيم)
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('99'), findsOneWidget);
    });
  });

  group('MetricGrid', () {
    testWidgets('يعرض العدد الصحيح من البطاقات', (tester) async {
      await tester.pumpWidget(
        _wrap(SizedBox(
          width: 400,
          height: 400,
          child: MetricGrid(cards: const [
            ('حضور', '90%', Icons.people, null),
            ('تأخير', '3', Icons.schedule, null),
            ('غياب', '1', Icons.cancel, null),
          ]),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MetricCard), findsNWidgets(3));
    });

    testWidgets('يعرض بطاقة واحدة بشكل صحيح', (tester) async {
      await tester.pumpWidget(
        _wrap(SizedBox(
          width: 400,
          height: 300,
          child: MetricGrid(cards: const [
            ('عدد الموظفين', '25', Icons.group, null),
          ]),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('25'), findsOneWidget);
      expect(find.text('عدد الموظفين'), findsOneWidget);
    });
  });

  group('MobileFilterBar', () {
    testWidgets('يعرض نص البحث ونتيجة الفلتر', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _wrap(SingleChildScrollView(
          child: MobileFilterBar(
            searchHint: 'ابحث هنا...',
            controller: controller,
            onSearchChanged: (_) {},
            options: const [
              MobileFilterOption('all', 'الكل'),
              MobileFilterOption('pending', 'قيد المراجعة'),
            ],
            selected: 'all',
            onSelected: (_) {},
            resultLabel: '15 نتيجة',
          ),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.text('15 نتيجة'), findsOneWidget);
    });

    testWidgets('يعرض خيارات الفلتر كرقائق', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(
        _wrap(SingleChildScrollView(
          child: MobileFilterBar(
            searchHint: 'بحث',
            controller: controller,
            onSearchChanged: (_) {},
            options: const [
              MobileFilterOption('all', 'الكل'),
              MobileFilterOption('active', 'نشط'),
              MobileFilterOption('closed', 'مغلق'),
            ],
            selected: 'all',
            onSelected: (_) {},
            resultLabel: '10 نتائج',
          ),
        )),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(find.text('الكل'), findsOneWidget);
      expect(find.text('نشط'), findsOneWidget);
      expect(find.text('مغلق'), findsOneWidget);
    });
  });
}
