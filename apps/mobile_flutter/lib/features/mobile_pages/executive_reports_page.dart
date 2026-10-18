import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/theme/brand_gradients.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
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
    final filtered = (filter == 'all'
        ? data.reports.toList()
        : data.reports.where((item) => item.status == filter).toList())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      children: [
        // ── بطاقة الواجهة الترحيبية الرشيقة ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: BrandGradients.hero,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'صندوق التقارير التنفيذي',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'التقارير الدورية وجدولة التسليم الآلي والمؤشرات الشاملة.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .78),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${data.reports.length} تقارير',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── بطاقات الإحصاء التفاعلية الرشيقة (شبكة مضغوطة قابلة للفلترة الفورية) ──
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.3,
          children: [
            _ExecutiveReportStatCard(
              title: 'مكتملة',
              count: completed,
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.statusSuccess,
              isSelected: section == 0 && filter == 'completed',
              onTap: () => setState(() {
                section = 0;
                filter = (filter == 'completed') ? 'all' : 'completed';
              }),
            ),
            _ExecutiveReportStatCard(
              title: 'قيد التجهيز',
              count: active,
              icon: Icons.sync_rounded,
              color: AppColors.statusInfo,
              isSelected: section == 0 && filter == 'running',
              onTap: () => setState(() {
                section = 0;
                filter = (filter == 'running') ? 'all' : 'running';
              }),
            ),
            _ExecutiveReportStatCard(
              title: 'متعذرة',
              count: failed,
              icon: Icons.error_outline_rounded,
              color: AppColors.statusDanger,
              isSelected: section == 0 && filter == 'failed',
              onTap: () => setState(() {
                section = 0;
                filter = (filter == 'failed') ? 'all' : 'failed';
              }),
            ),
            _ExecutiveReportStatCard(
              title: 'جداول نشطة',
              count: data.reportSchedules.where((item) => item.active).length,
              icon: Icons.calendar_month_outlined,
              color: AppColors.statusViolet,
              isSelected: section == 1,
              onTap: () => setState(() => section = 1),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── مبدل الأقسام (التقارير / الجدولة) ──
        SegmentedButton<int>(
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
          ),
          segments: [
            ButtonSegment(
              value: 0,
              icon: const Icon(Icons.description_outlined, size: 16),
              label: Text('التقارير (${data.reports.length})'),
            ),
            ButtonSegment(
              value: 1,
              icon: const Icon(Icons.event_repeat_rounded, size: 16),
              label: Text('الجدولة والتسليم (${data.reportSchedules.length})'),
            ),
          ],
          selected: {section},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() => section = value.first),
        ),
        const SizedBox(height: 14),

        // ── المحتوى حسب القسم المختار ──
        if (section == 0) ...[
          // شريط التصفية والنتائج السريعة
          Row(
            children: [
              Text(
                filter == 'all'
                    ? 'أحدث التقارير (${filtered.length})'
                    : 'تصفية: ${_filterLabel(filter)} (${filtered.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              if (filter != 'all')
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => setState(() => filter = 'all'),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('عرض الكل'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // رقائق التصنيفات السريعة
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('all', 'الكل (${data.reports.length})'),
                _filterChip('completed', 'مكتمل ($completed)'),
                _filterChip('running', 'قيد التجهيز ($active)'),
                _filterChip('failed', 'متعذر ($failed)'),
              ],
            ),
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
                  onDownload: () => _downloadReport(context, report),
                ),
              ),
            ),
        ] else ...[
          const MobileSectionHeader(
            title: 'جدولة التسليم',
            subtitle: 'المواعيد القادمة للتقارير الآلية الدورية.',
          ),
          const SizedBox(height: 10),
          if (data.reportSchedules.isEmpty)
            const _ReportsEmpty(message: 'لا توجد تقارير مجدولة حاليًا.')
          else
            ...data.reportSchedules.map(
              (schedule) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: scheme.outlineVariant.withValues(alpha: .4),
                      width: 1.0,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: schedule.active
                            ? AppColors.statusSuccess.withValues(alpha: .12)
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        schedule.active
                            ? Icons.event_repeat_rounded
                            : Icons.pause_circle_outline_rounded,
                        color: schedule.active
                            ? AppColors.statusSuccess
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      schedule.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        schedule.nextRunAt == null
                            ? '${_scheduleKind(schedule.scheduleKind)} · بلا موعد قادم'
                            : '${_scheduleKind(schedule.scheduleKind)} · القادم: ${DateFormat('d MMMM y، h:mm a', 'ar').format(schedule.nextRunAt!.toLocal())}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
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
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: ChoiceChip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11.5,
        fontWeight: filter == value ? FontWeight.w800 : FontWeight.w600,
      ),
      selected: filter == value,
      onSelected: (_) => setState(() => filter = value),
    ),
  );

  static String _filterLabel(String filter) => switch (filter) {
    'completed' => 'مكتملة',
    'running' => 'قيد التجهيز',
    'queued' => 'بالانتظار',
    'failed' => 'متعذرة',
    _ => 'الكل',
  };

  void _showReport(ExecutiveReportRun report) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      report.name,
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 8),
                  MobileStatusPill(report.status),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: Theme.of(sheetContext)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: .4),
                  ),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('الفترة المشمولة'),
                      subtitle: Text(_period(report)),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('تاريخ ووقت الإنشاء'),
                      subtitle: Text(
                        DateFormat(
                          'd MMMM y، h:mm a',
                          'ar',
                        ).format(report.createdAt.toLocal()),
                      ),
                    ),
                    if (report.errorDetail != null) ...[
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.statusDanger,
                        ),
                        title: const Text(
                          'سبب التعذر',
                          style: TextStyle(color: AppColors.statusDanger),
                        ),
                        subtitle: Text(report.errorDetail!),
                      ),
                    ],
                  ],
                ),
              ),
              if (report.summary.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'الملخص التنفيذي',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (sheetContext) {
                    final rows = _flattenSummary(report.summary);
                    return Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: Theme.of(sheetContext)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: .4),
                        ),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                              ),
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
                                            color: Theme.of(sheetContext)
                                                .colorScheme
                                                .onSurfaceVariant,
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
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
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
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _downloadReport(context, report),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('فتح ملف التقرير'),
                ),
              ],
            ],
          ),
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

  static const Map<String, String> _summaryValueLabels = {
    'executive_daily': 'تنفيذي يومي',
    'daily': 'يومي',
    'weekly': 'أسبوعي',
    'monthly': 'شهري',
  };

  static List<(String, String)> _flattenSummary(Map summary) {
    final rows = <(String, String)>[];
    void addRow(String key, Object? value) {
      rows.add((_summaryKeyLabels[key] ?? key, _scalar(value)));
    }

    for (final entry in summary.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
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

  static String _scheduleKind(String value) => switch (value) {
    'daily' => 'يومي',
    'weekly' => 'أسبوعي',
    'monthly' => 'شهري',
    'manual' => 'عند الطلب',
    _ => value,
  };
}

String _period(ExecutiveReportRun report) {
  if (report.periodStart == null && report.periodEnd == null) {
    return 'فترة دورية';
  }
  final formatter = DateFormat('d MMM y', 'ar');
  if (report.periodStart != null &&
      report.periodEnd != null &&
      report.periodStart!.year == report.periodEnd!.year &&
      report.periodStart!.month == report.periodEnd!.month &&
      report.periodStart!.day == report.periodEnd!.day) {
    return formatter.format(report.periodStart!);
  }
  return [
    report.periodStart,
    report.periodEnd,
  ].whereType<DateTime>().map(formatter.format).join(' – ');
}

/// بطاقة إحصائية مدمجة ورشيقة للتقارير
class _ExecutiveReportStatCard extends StatelessWidget {
  const _ExecutiveReportStatCard({
    required this.title,
    required this.count,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final int count;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? color
              : scheme.outlineVariant.withValues(alpha: .4),
          width: isSelected ? 1.6 : 1.0,
        ),
      ),
      color: isSelected
          ? color.withValues(alpha: .12)
          : scheme.surfaceContainerHighest.withValues(alpha: .35),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: isSelected ? color : null,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة عرض التقرير المنفذ
class _ReportRunCard extends StatelessWidget {
  const _ReportRunCard({
    required this.item,
    required this.onTap,
    required this.onDownload,
  });

  final ExecutiveReportRun item;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (statusLabel, statusColor) = _statusMeta(item.status);
    final hasFile = item.storagePath != null;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: .4),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _icon(item.reportType),
                  size: 22,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _period(item),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '·',
                          style: TextStyle(color: scheme.outlineVariant),
                        ),
                        Text(
                          DateFormat(
                            'd MMM، h:mm a',
                            'ar',
                          ).format(item.createdAt.toLocal()),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: .75,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2.5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (hasFile)
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.primaryContainer.withValues(
                      alpha: .6,
                    ),
                    foregroundColor: scheme.primary,
                  ),
                  icon: const Icon(Icons.download_rounded, size: 20),
                  tooltip: 'فتح التقرير',
                  onPressed: onDownload,
                )
              else
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.onSurfaceVariant.withValues(alpha: .5),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static (String, Color) _statusMeta(String status) => switch (status) {
    'completed' => ('مكتمل', AppColors.statusSuccess),
    'running' => ('جارٍ التجهيز', AppColors.statusInfo),
    'queued' => ('بالانتظار', AppColors.statusWarning),
    'failed' => ('متعذر', AppColors.statusDanger),
    'cancelled' => ('ملغي', Colors.grey),
    _ => (status, AppColors.brandPrimary),
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
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: Theme.of(context).colorScheme.outlineVariant.withValues(
          alpha: .4,
        ),
      ),
    ),
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
