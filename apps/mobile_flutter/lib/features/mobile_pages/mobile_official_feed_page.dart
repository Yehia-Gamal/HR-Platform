import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileOfficialFeedPage extends ConsumerWidget {
  const MobileOfficialFeedPage({
    this.focusItemId,
    this.focusKind = 'decision',
    super.key,
  });

  final String? focusItemId;
  final String focusKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (focusItemId != null) {
      return MobileFeedDetailPage(kind: focusKind, itemId: focusItemId!);
    }

    final feed = ref.watch(mobileFeedProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileFeedProvider),
      child: feed.when(
        loading: () => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    'تعذر تحميل الأخبار والقرارات',
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => ref.invalidate(mobileFeedProvider),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ],
        ),
        data: (items) => items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BrandLogoMark(size: 44),
                          const SizedBox(height: 16),
                          Icon(
                            Icons.campaign_outlined,
                            size: 48,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد منشورات رسمية',
                            style: textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _FeedCard(item: items[index]),
              ),
      ),
    );
  }
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item});

  final MobileFeedItem item;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              MobileFeedDetailPage(kind: item.kind, itemId: item.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MobileStatusPill(item.kind),
                const SizedBox(width: 6),
                MobileStatusPill(item.priority),
                const Spacer(),
                if (item.publishedAt != null)
                  Text(
                    DateFormat(
                      'd MMM',
                      'ar',
                    ).format(item.publishedAt!.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (item.requiresAcknowledgement) ...[
              const Divider(height: 28),
              Row(
                children: [
                  Semantics(
                    label: item.myAcknowledged
                        ? 'تم الإقرار بالاطلاع'
                        : 'يتطلب الاطلاع والإقرار',
                    child: Icon(
                      item.myAcknowledged
                          ? Icons.verified
                          : Icons.visibility_outlined,
                      size: 20,
                      color: item.myAcknowledged
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.myAcknowledged
                        ? 'تم الإقرار بالاطلاع'
                        : 'يتطلب الاطلاع والإقرار',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
