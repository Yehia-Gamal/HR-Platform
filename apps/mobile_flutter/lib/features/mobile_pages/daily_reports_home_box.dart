import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class DailyReportsHomeBox extends ConsumerWidget {
  const DailyReportsHomeBox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(accessContextProvider).value?.isClinicStaff == true) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final feed = ref.watch(dailyReportsFeedProvider(null));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Semantics(
                  container: true,
                  header: true,
                  label: 'التقارير اليومية',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.newspaper_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'التقارير اليومية',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DailyReportsFeedPage(),
                    ),
                  ),
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            feed.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (_, _) => Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text('تعذر تحميل التقارير.'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(dailyReportsFeedProvider(null)),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
              data: (items) {
                final latest = items.take(3).toList(growable: false);
                if (latest.isEmpty) {
                  return const Text('لا توجد تقارير حتى الآن.');
                }
                return Column(
                  children: [
                    for (var i = 0; i < latest.length; i++) ...[
                      if (i > 0) const Divider(height: 12),
                      _ReportRow(item: latest[i]),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = item['employeeName'] as String? ?? 'موظف';
    final photoUrl = item['photoUrl'] as String?;
    final reportDate = item['reportDate'] as String? ?? '';
    final parsedDate = DateTime.tryParse(reportDate);
    final date = parsedDate == null
        ? reportDate
        : DateFormat('d MMM', 'ar').format(parsedDate);
    final views = item['viewersCount'] as int? ?? 0;
    final likes = item['likesCount'] as int? ?? 0;

    return Semantics(
      container: true,
      label: '$name، $date، المشاهدات $views، الإعجابات $likes',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            AppAvatar(name: name, photoUrl: photoUrl, radius: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: theme.textTheme.labelLarge),
                  if (date.isNotEmpty)
                    Text(
                      date,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .55),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 14),
                  const SizedBox(width: 3),
                  Text('$views', style: theme.textTheme.labelSmall),
                  const SizedBox(width: 8),
                  const Icon(Icons.favorite_border, size: 14),
                  const SizedBox(width: 3),
                  Text('$likes', style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
