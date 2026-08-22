import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExecutiveReportsPage extends ConsumerStatefulWidget {
  const ExecutiveReportsPage({super.key});

  @override
  ConsumerState<ExecutiveReportsPage> createState() =>
      _ExecutiveReportsPageState();
}

class _ExecutiveReportsPageState extends ConsumerState<ExecutiveReportsPage> {
  int section = 0;
  String filter = 'all';

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(mobileExecutiveCommandCenterProvider);
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(mobileExecutiveCommandCenterProvider),
      child: data.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 230),
            Center(child: CircularProgressIndicator()),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 90),
            Icon(
              Icons.cloud_off_rounded,
              size: 52,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(humanizeError(error), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.invalidate(mobileExecutiveCommandCenterProvider),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: _content,
      ),
    );
  }

  Widget _content(MobileExecutiveCommandCenter data) {
    final scheme = Theme.of(context).colorScheme;
    final completed = data.reports
        .where((item) => item.status == 'completed')
        .length;
    final active = data.reports
        .where((item) => const {'queued', 'running'}.contains(item.status))
        .length;
    final failed = data.reports.where((item) => item.status == 'failed').length;
    final filtered = filter == 'all'
        ? data.reports
        : data.reports.where((item) => item.status == filter).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        Container(
          padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [scheme.primary, scheme.secondary],
            ),
          ),
          child: Row(
            children: [
              const BrandLogoMark(inverse: true, size: 48),
              const SizedBox(width: 12),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.analytics_outlined,
                  color: scheme.onPrimary,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'صندوق التقارير التنفيذي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'التقارير الدورية وحالة تجهيزها ومواعيد التسليم القادمة.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        height: 1.45,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        MetricGrid(
          cards: [
            // كل بطاقة تفتح قائمتها: الحالة داخل تبويب التقارير أو الجدولة.
            (
              'مكتملة',
              completed.toString(),
              Icons.verified_outlined,
              () => setState(() {
                section = 0;
                filter = 'completed';
              }),
            ),
            (
              'قيد التجهيز',
              active.toString(),
              Icons.sync_rounded,
              () => setState(() {
                section = 0;
                filter = 'running';
              }),
            ),
            (
              'متعذرة',
              failed.toString(),
              Icons.error_outline_rounded,
              () => setState(() {
                section = 0;
                filter = 'failed';
              }),
            ),
            (
              'جداول نشطة',
              data.reportSchedules
                  .where((item) => item.active)
                  .length
                  .toString(),
              Icons.schedule_rounded,
              () => setState(() => section = 1),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.inbox_outlined),
              label: Text('التقارير'),
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.calendar_month_outlined),
              label: Text('الجدولة'),
            ),
          ],
          selected: {section},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => section = value.first),
        ),
        const SizedBox(height: 18),
        if (section == 0) ...[
          const MobileSectionHeader(
            title: 'أحدث التقارير',
            subtitle: 'اختر أي تقرير لعرض الفترة والملخص وحالة الملف.',
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'الكل'),
                _filterChip('completed', 'مكتمل'),
                _filterChip('running', 'جارٍ'),
                _filterChip('queued', 'بالانتظار'),
                _filterChip('failed', 'متعذر'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'عدد التقارير: ${filtered.length}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              if (filter != 'all')
                TextButton.icon(
                  onPressed: () => setState(() => filter = 'all'),
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('مسح التصفية'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const _ReportsEmpty(message: 'لا توجد تقارير مطابقة لهذا التصنيف.')
          else
            ...filtered.map(
              (report) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReportRunCard(
                  item: report,
                  onTap: () => _showReport(report),
                ),
              ),
            ),
        ] else ...[
          const MobileSectionHeader(
            title: 'جدولة التسليم',
            subtitle: 'المواعيد التالية للتقارير اليومية والأسبوعية والشهرية.',
          ),
          const SizedBox(height: 10),
          if (data.reportSchedules.isEmpty)
            const _ReportsEmpty(message: 'لا توجد تقارير مجدولة حاليًا.')
          else
            ...data.reportSchedules.map(
              (schedule) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      child: schedule.active
                          ? const Icon(Icons.event_repeat_rounded)
                          : const SizedBox.shrink(),
                    ),
                    title: Text(
                      schedule.name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      schedule.nextRunAt == null
                          ? '${_scheduleKind(schedule.scheduleKind)} · بلا موعد قادم'
                          : '${_scheduleKind(schedule.scheduleKind)} · ${DateFormat('d MMM، h:mm a', 'ar').format(schedule.nextRunAt!.toLocal())}',
                    ),
                    trailing: MobileStatusPill(
                      schedule.active ? 'active' : 'cancelled',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _filterChip(String value, String label) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 7),
    child: ChoiceChip(
      label: Text(label),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    ),
  );

  void _showReport(ExecutiveReportRun report) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              report.name,
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('الفترة'),
                    subtitle: Text(_period(report)),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('تاريخ الإنشاء'),
                    subtitle: Text(
                      DateFormat(
                        'd MMMM y، h:mm a',
                        'ar',
                      ).format(report.createdAt.toLocal()),
                    ),
                  ),
                  if (report.errorDetail != null) ...[
                    const Divider(indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.error_outline_rounded),
                      title: const Text('سبب التعذر'),
                      subtitle: Text(report.errorDetail!),
                    ),
                  ],
                ],
              ),
            ),
            if (report.summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'الملخص التنفيذي',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              // 0440+: عرض مُقروء للملخص — تسميات عربية، فكّ تعشيش
              // الكائنات، وتنسيق التواريخ — بدل أزواج JSON خام.
              Builder(
                builder: (sheetContext) {
                  final rows = _flattenSummary(report.summary);
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    rows[i].$1,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            sheetContext,
                                          ).colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    rows[i].$2,
                                    textAlign: TextAlign.end,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
            if (report.storagePath != null) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _downloadReport(context, report),
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('فتح ملف التقرير'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Future<void> _downloadReport(
    BuildContext context,
    ExecutiveReportRun report,
  ) async {
    if (report.storagePath == null) return;
    try {
      final url = await ref
          .read(supabaseProvider)
          .storage
          .from('report-files')
          .createSignedUrl(report.storagePath!, 120)
          .timeout(const Duration(seconds: 20));
      if (context.mounted) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    }
  }

  /// تسميات عربية لمفاتيح الملخص المعروفة — والمجهول يُعرض كما هو.
  static const Map<String, String> _summaryKeyLabels = {
    'date': 'التاريخ',
    'headcount': 'عدد الموظفين',
    'attendance': 'الحضور',
    'present': 'حاضر',
    'late': 'متأخر',
    'absent': 'غائب',
    'onLeave': 'في إجازة',
    'total': 'الإجمالي',
    'reportType': 'نوع التقرير',
    'generatedAt': 'وقت الإنشاء',
    'openDisputes': 'قضايا مفتوحة',
    'activeKpiCycles': 'دورات تقييم نشطة',
    'pendingRequests': 'طلبات معلقة',
  };

  /// ترجمة قيم معروفة (أنواع تقارير وأشباهها).
  static const Map<String, String> _summaryValueLabels = {
    'executive_daily': 'تنفيذي يومي',
    'daily': 'يومي',
    'weekly': 'أسبوعي',
    'monthly': 'شهري',
  };

  /// يفكّ ملخص التقرير إلى صفوف «تسمية ← قيمة» قابلة للقراءة:
  /// كائن متشعّب → صفوف فرعية، قائمة → عدد، تاريخ ISO → تنسيق عربي.
  static List<(String, String)> _flattenSummary(Map summary) {
    final rows = <(String, String)>[];
    void addRow(String key, Object? value) {
      rows.add((_summaryKeyLabels[key] ?? key, _scalar(value)));
    }

    for (final entry in summary.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
        // كائن مثل attendance: {late: 0, total: 1, ...} → صف لكل حقل.
        for (final sub in value.entries) {
          addRow(sub.key.toString(), sub.value);
        }
      } else if (value is List) {
        rows.add((
          _summaryKeyLabels[key] ?? key,
          value.isEmpty ? 'لا يوجد' : '${value.length}',
        ));
      } else {
        addRow(key, value);
      }
    }
    return rows;
  }

  static String _scalar(Object? value) {
    if (value == null) return '—';
    if (value is Map) return value.isEmpty ? 'لا يوجد' : '${value.length}';
    if (value is List) return value.isEmpty ? 'لا يوجد' : '${value.length}';
    final text = value.toString();
    if (text.contains('T') && text.length > 10) {
      final date = DateTime.tryParse(text);
      if (date != null) {
        return DateFormat('d MMMM y، h:mm a', 'ar').format(date.toLocal());
      }
    }
    return _summaryValueLabels[text] ?? text;
  }

  static String _period(ExecutiveReportRun report) {
    if (report.periodStart == null && report.periodEnd == null) {
      return 'غير محددة';
    }
    final formatter = DateFormat('d MMM y', 'ar');
    return [
      report.periodStart,
      report.periodEnd,
    ].whereType<DateTime>().map(formatter.format).join(' – ');
  }

  static String _scheduleKind(String value) => switch (value) {
    'daily' => 'يومي',
    'weekly' => 'أسبوعي',
    'monthly' => 'شهري',
    'manual' => 'عند الطلب',
    _ => value,
  };
}

class _ReportRunCard extends StatelessWidget {
  const _ReportRunCard({required this.item, required this.onTap});

  final ExecutiveReportRun item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      leading: CircleAvatar(child: Icon(_icon(item.reportType))),
      title: Text(
        item.name,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        '${DateFormat('d MMM، h:mm a', 'ar').format(item.createdAt.toLocal())} · ${_label(item.status)}',
      ),
      trailing: Semantics(
        label: item.storagePath == null ? 'لا يوجد ملف' : 'الملف جاهز للتنزيل',
        child: item.storagePath == null
            ? const Icon(Icons.chevron_left_rounded)
            : const SizedBox.shrink(),
      ),
      onTap: onTap,
    ),
  );

  static String _label(String value) => switch (value) {
    'queued' => 'بالانتظار',
    'running' => 'جارٍ التجهيز',
    'completed' => 'مكتمل',
    'failed' => 'متعذر',
    'cancelled' => 'ملغي',
    _ => value,
  };

  static IconData _icon(String value) {
    if (value.contains('attendance')) return Icons.event_available_outlined;
    if (value.contains('kpi') || value.contains('performance')) {
      return Icons.speed_outlined;
    }
    if (value.contains('payroll') || value.contains('finance')) {
      return Icons.payments_outlined;
    }
    return Icons.insert_chart_outlined_rounded;
  }
}

class _ReportsEmpty extends StatelessWidget {
  const _ReportsEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 42),
          const SizedBox(height: 9),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
