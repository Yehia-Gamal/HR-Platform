import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// بوكس التقارير اليومية في الواجهة الأولى — يظهر لكل المستخدمين.
/// يعرض أحدث 3 تقارير (الاسم، الصورة، التاريخ، المشاهدات والإعجابات)
/// والنقر عليه يفتح صفحة التقارير اليومية الكاملة.
class DailyReportsHomeBox extends ConsumerWidget {
  const DailyReportsHomeBox({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final feed = ref.watch(dailyReportsFeedProvider(null));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DailyReportsFeedPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.newspaper_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'التقارير اليومية',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  Text(
                    'عرض الكل',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Icon(Icons.chevron_left_rounded, size: 18, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              feed.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'تعذر تحميل التقارير.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'لا توجد تقارير بعد — كن أول من يرفع تقرير اليوم.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    );
                  }
                  final visible = items.take(3).toList();
                  return Column(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const Divider(height: 14),
                        _ReportRow(item: visible[i]),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// صف تقرير واحد داخل البوكس.
class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = item['employeeName'] as String? ?? 'موظف';
    final photoUrl = item['photoUrl'] as String?;
    final reportDate = item['reportDate'] as String?;
    final viewersCount = item['viewersCount'] as int? ?? 0;
    final likesCount = item['likesCount'] as int? ?? 0;

    String dateLabel = '';
    if (reportDate != null) {
      try {
        dateLabel = DateFormat('d MMM', 'ar')
            .format(DateTime.parse('${reportDate}T00:00:00'));
      } catch (_) {}
    }

    return Row(
      children: [
        AppAvatar(name: name, photoUrl: photoUrl, radius: 17),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (dateLabel.isNotEmpty)
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        Icon(Icons.visibility_outlined,
            size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '$viewersCount',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.favorite_border, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          '$likesCount',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}