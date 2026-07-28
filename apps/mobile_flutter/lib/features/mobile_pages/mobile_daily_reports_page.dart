import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileDailyReportsPage extends ConsumerWidget {
  const MobileDailyReportsPage({this.employeeId, this.employeeName, super.key});

  final String? employeeId;
  final String? employeeName;

  bool get isSelf => employeeId == null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(mobileDailyReportsProvider(employeeId));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isSelf ? 'تقاريري اليومية' : 'تقارير ${employeeName ?? 'الموظف'}',
        ),
      ),
      floatingActionButton: isSelf
          ? FloatingActionButton.extended(
              onPressed: () => _editReport(context, ref, reports.asData?.value),
              icon: const Icon(Icons.edit_note),
              label: const Text('تقرير اليوم'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mobileDailyReportsProvider(employeeId));
        },
        child: reports.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 140),
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
                semanticLabel: 'خطأ',
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () =>
                      ref.invalidate(mobileDailyReportsProvider(employeeId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 160),
                    Icon(
                      Icons.summarize_outlined,
                      size: 54,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      semanticLabel: 'لا توجد تقارير',
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        'لا توجد تقارير يومية',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'ستظهر التقارير هنا عند إضافتها',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _ReportCard(
                    item: items[index],
                    canReview: !isSelf,
                    onReview: !isSelf
                        ? () => _reviewReport(context, ref, items[index])
                        : null,
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _editReport(
    BuildContext context,
    WidgetRef ref,
    List<MobileDailyReport>? reports,
  ) async {
    final today = DateTime.now();
    MobileDailyReport? existing;
    for (final report in reports ?? const <MobileDailyReport>[]) {
      if (DateUtils.isSameDay(report.reportDate, today)) {
        existing = report;
        break;
      }
    }

    final achievements = TextEditingController(text: existing?.achievements);
    final blockers = TextEditingController(text: existing?.blockers);
    final tomorrow = TextEditingController(text: existing?.tomorrowPlan);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              existing == null ? 'تقرير اليوم' : 'تعديل تقرير اليوم',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: achievements,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'ما تم إنجازه'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: blockers,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'المعوقات'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tomorrow,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'خطة الغد'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (achievements.text.trim().length < 3) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text('اكتب الإنجازات بصورة واضحة أولًا.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(sheetContext, true);
              },
              child: const Text('حفظ التقرير'),
            ),
          ],
        ),
      ),
    );

    final done = achievements.text.trim();
    final blocked = blockers.text.trim();
    final next = tomorrow.text.trim();
    achievements.dispose();
    blockers.dispose();
    tomorrow.dispose();
    if (confirmed != true) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .saveDailyReport(
            reportDate: today,
            achievements: done,
            blockers: blocked,
            tomorrowPlan: next,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ التقرير اليومي.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Future<void> _reviewReport(
    BuildContext context,
    WidgetRef ref,
    MobileDailyReport report,
  ) async {
    final comment = TextEditingController(text: report.managerComment);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مراجعة تقرير ${report.employeeName}',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(DateFormat('EEEE، d MMMM y', 'ar').format(report.reportDate)),
            const SizedBox(height: 14),
            TextField(
              controller: comment,
              autofocus: true,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'تعليق المدير',
                hintText: 'اكتب ملاحظة واضحة أو توجيه المتابعة',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                if (comment.text.trim().length < 3) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(content: Text('تعليق المدير مطلوب.')),
                  );
                  return;
                }
                Navigator.pop(sheetContext, true);
              },
              icon: const Icon(Icons.verified_outlined),
              label: Text(
                report.reviewedAt == null ? 'حفظ المراجعة' : 'تحديث المراجعة',
              ),
            ),
          ],
        ),
      ),
    );

    final value = comment.text.trim();
    comment.dispose();
    if (confirmed != true || employeeId == null) return;

    try {
      await ref
          .read(mobileCommandsProvider)
          .reviewDailyReport(
            reportId: report.id,
            comment: value,
            employeeId: employeeId!,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم حفظ مراجعة التقرير.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.item,
    required this.canReview,
    this.onReview,
  });

  final MobileDailyReport item;
  final bool canReview;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  DateFormat('EEEE، d MMMM y', 'ar').format(item.reportDate),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (item.reviewedAt != null) const MobileStatusPill('approved'),
            ],
          ),
          const SizedBox(height: 12),
          _section('الإنجازات', item.achievements),
          _section('المعوقات', item.blockers),
          _section('خطة الغد', item.tomorrowPlan),
          if (item.managerComment?.trim().isNotEmpty == true) ...[
            const Divider(height: 24),
            Text(
              'تعليق المدير${item.reviewerName == null ? '' : ' — ${item.reviewerName}'}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            Text(item.managerComment!),
            if (item.reviewedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                DateFormat(
                  'd MMM y، h:mm a',
                  'ar',
                ).format(item.reviewedAt!.toLocal()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
          if (canReview) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(
                  item.reviewedAt == null
                      ? 'إضافة مراجعة المدير'
                      : 'تحديث مراجعة المدير',
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _section(String title, String? value) {
    if (value?.trim().isEmpty != false) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(value!),
        ],
      ),
    );
  }
}
