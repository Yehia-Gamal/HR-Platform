import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// الشهور بالعربية
const _months = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// كشف الحضور والانصراف الشهري — للموظف عن نفسه (V12 §18).
class MonthlyAttendanceStatementPage extends ConsumerStatefulWidget {
  const MonthlyAttendanceStatementPage({super.key});

  @override
  ConsumerState<MonthlyAttendanceStatementPage> createState() =>
      _MonthlyAttendanceStatementPageState();
}

class _MonthlyAttendanceStatementPageState
    extends ConsumerState<MonthlyAttendanceStatementPage> {
  final _now = DateTime.now();
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = _now.year;
    _month = _now.month;
  }

  @override
  Widget build(BuildContext context) {
    final statement = ref.watch(myMonthlyStatementProvider((_year, _month)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الحضور والانصراف'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration:
                        const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(_months[i]))),
                    onChanged: (v) => setState(() => _month = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _year,
                    decoration:
                        const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    items: [_now.year, _now.year - 1, _now.year - 2]
                        .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
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
          onRefresh: () async =>
              ref.invalidate(myMonthlyStatementProvider((_year, _month))),
          child: statement.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 8),
                  Text(humanizeError(error), textAlign: TextAlign.center),
                  TextButton(
                    onPressed: () => ref.invalidate(myMonthlyStatementProvider((_year, _month))),
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

class _StatementBody extends StatelessWidget {
  const _StatementBody({required this.statement});

  final MonthlyAttendanceStatement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // بطاقات الملخص
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 2.4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            _SummaryTile(label: 'أيام الحضور', value: '${s.presentDays} / ${s.scheduledDays}'),
            _SummaryTile(label: 'أيام الغياب', value: '${s.absentDays}'),
            _SummaryTile(label: 'أيام الإجازات', value: '${s.leaveDays}'),
            _SummaryTile(label: 'أيام المأموريات', value: '${s.missionDays}'),
            _SummaryTile(label: 'إجمالي الساعات', value: s.totalWorkHours.toStringAsFixed(1)),
            _SummaryTile(label: 'إجمالي التأخير', value: '${s.totalLateMinutes} د'),
          ],
        ),
        const SizedBox(height: 16),
        Text('الجدول اليومي',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        ...statement.days.map((d) => _DayCard(day: d)),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day});
  final AttendanceStatementDay day;

  static const _warn = {'غائب دون إذن', 'يحتاج مراجعة'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final isWarn = _warn.contains(day.status);
    String fmt(String? t) => (t == null || t.length < 5) ? '—' : t.substring(0, 5);
    return Card(
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text('${day.dayNameAr} ${day.date}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            MobileStatusPill(day.status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('${fmt(day.checkIn)} → ${fmt(day.checkOut)}', style: muted),
                ),
              ),
              if (day.workHours > 0)
                Text('ساعات فعلية: ${day.workHours.toStringAsFixed(1)}', style: muted),
              if (day.lateMinutes > 0)
                Text('تأخير: ${day.lateMinutes} دقيقة',
                    style: muted?.copyWith(color: isWarn ? scheme.error : null)),
              if (day.missingCheckOut)
                Text('لم يسجل انصراف', style: muted?.copyWith(color: scheme.error)),
              if (day.correctionNote != null && day.correctionNote!.isNotEmpty)
                Text('تصحيح: ${day.correctionNote}', style: muted),
            ],
          ),
        ),
      ),
    );
  }
}
