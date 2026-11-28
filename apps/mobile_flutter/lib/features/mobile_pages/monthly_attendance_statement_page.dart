import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/time/app_time.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/attendance_pdf_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/admin_attendance_day_edit_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'statement/statement_body_and_header.dart';
part 'statement/statement_percentage_card.dart';
part 'statement/statement_metrics_and_insights.dart';
part 'statement/statement_missing_punches.dart';
part 'statement/statement_calendar_grid.dart';
part 'statement/statement_calendar_day_cell.dart';
part 'statement/statement_day_detail_sheet.dart';
part 'statement/statement_day_detail_actions.dart';
part 'statement/statement_retroactive_change_sheet.dart';
part 'statement/statement_quick_leave_permit_sheets.dart';
part 'statement/statement_quick_correction_sheet.dart';

// الشهور بالعربية
const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// كشف المستخدم نفسه؟ الطلبات الذاتية (إجازة/إذن/تصحيح بصمة/تعديل حالة يوم)
/// تُقدَّم باسم من يستخدم التطبيق، فلا تُعرض على كشف موظف آخر.
bool _isOwnStatement(WidgetRef ref, MonthlyAttendanceStatement statement) {
  final me = ref.watch(accessContextProvider).value?.employeeId;
  return statement.employeeId.isEmpty || statement.employeeId == me;
}

/// Opens the same daily statement used by the calendar from a punch in history.
Future<void> showOwnAttendanceDayDetails(BuildContext context, DateTime date) {
  final provider = myMonthlyStatementProvider((date.year, date.month));
  final dateKey =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => Consumer(
      builder: (context, ref, _) => ref
          .watch(provider)
          .when(
            loading: () => const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (statement) {
              final day = statement.days
                  .where((day) => day.date == dateKey)
                  .firstOrNull;
              final now = AppTime.now();
              final today = DateUtils.dateOnly(now);
              return _DayDetailSheet(
                statement: statement,
                day: day,
                dayNum: date.day,
                isFuture: date.isAfter(today),
                isToday: DateUtils.isSameDay(date, today),
                year: date.year,
                month: date.month,
              );
            },
          ),
    ),
  );
}

/// كشف الحضور والانصراف الشهري — للموظف عن نفسه (V12 §18)،
/// وعند تمرير [employeeId] يُعرض كشف موظف محدد (مدير مباشر/HR) (V22).
class MonthlyAttendanceStatementPage extends ConsumerStatefulWidget {
  const MonthlyAttendanceStatementPage({
    this.employeeId,
    this.employeeName,
    this.initialYear,
    this.initialMonth,
    super.key,
  });

  /// عند تمريره يُحمل كشف هذا الموظف بدلًا من كشف المستخدم الحالي.
  final String? employeeId;
  final String? employeeName;

  /// الشهر المعروض أولًا (افتراضيًا الشهر الحالي) — يفتح ملف الموظف كشف
  /// الشهر الذي يعرض ملخصه.
  final int? initialYear;
  final int? initialMonth;

  @override
  ConsumerState<MonthlyAttendanceStatementPage> createState() =>
      _MonthlyAttendanceStatementPageState();
}

class _MonthlyAttendanceStatementPageState
    extends ConsumerState<MonthlyAttendanceStatementPage> {
  final _now = AppTime.now();
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initialYear ?? _now.year;
    _month = widget.initialMonth ?? _now.month;
  }

  AsyncValue<MonthlyAttendanceStatement> _statement(WidgetRef ref) =>
      widget.employeeId == null
      ? ref.watch(myMonthlyStatementProvider((_year, _month)))
      : ref.watch(
          employeeMonthlyStatementProvider((widget.employeeId!, _year, _month)),
        );

  void _reload(WidgetRef ref) => widget.employeeId == null
      ? ref.invalidate(myMonthlyStatementProvider((_year, _month)))
      : ref.invalidate(
          employeeMonthlyStatementProvider((widget.employeeId!, _year, _month)),
        );

  @override
  Widget build(BuildContext context) {
    final statement = _statement(ref);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employeeName ?? 'كشف الحضور والانصراف'),
        actions: [
          if (statement.hasValue)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: 'تصدير PDF',
              onPressed: () async {
                try {
                  await exportAttendancePdf(statement.value!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('تم تصدير كشف الحضور PDF بنجاح'),
                            ),
                          ],
                        ),
                        backgroundColor: Color(0xFF0F9F6E),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(humanizeError(error))),
                    );
                  }
                }
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: List.generate(
                      12,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text(_months[i]),
                      ),
                    ),
                    onChanged: (v) => setState(() => _month = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: [_now.year, _now.year - 1, _now.year - 2]
                        .map(
                          (y) => DropdownMenuItem(value: y, child: Text('$y')),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _year = v!),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(ref),
          child: statement.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => _reload(ref),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (stmt) => _StatementBody(statement: stmt),
          ),
        ),
      ),
    );
  }
}

// ─── الجسم الرئيسي ───────────────────────────────────────────────
