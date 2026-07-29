import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_announcement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_decisions_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileOfficialFeedPage extends ConsumerWidget {
  const MobileOfficialFeedPage({
    this.focusItemId,
    this.focusKind = 'decision',
    this.canPublish = false,
    super.key,
  });

  final String? focusItemId;
  final String focusKind;

  /// هل المستخدم لديه صلاحية إنشاء قرارات وإعلانات (مدير تنفيذي / أدمن).
  final bool canPublish;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (focusItemId != null) {
      return MobileFeedDetailPage(kind: focusKind, itemId: focusItemId!);
    }

    final feed = ref.watch(mobileFeedProvider);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('القرارات والتعاميم')),
      floatingActionButton: canPublish
          ? FloatingActionButton.extended(
              heroTag: 'fab_new_post',
              onPressed: () => _showCreateOptions(context),
              icon: const Icon(Icons.add),
              label: const Text('نشر جديد'),
            )
          : null,
      body: RefreshIndicator(
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
                      padding: const EdgeInsets.only(top: 80),
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
                            if (canPublish) ...[
                              const SizedBox(height: 24),
                              FilledButton.tonalIcon(
                                onPressed: () => _showCreateOptions(context),
                                icon: const Icon(Icons.add),
                                label: const Text('أنشئ أول قرار أو إعلان'),
                              ),
                            ],
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
                  itemBuilder: (context, index) =>
                      _FeedCard(item: items[index]),
                ),
        ),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إنشاء منشور جديد',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'اختر نوع المنشور الذي تريد إصداره',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              _CreateOptionTile(
                icon: Icons.campaign_rounded,
                iconColor: scheme.primary,
                title: 'إعلان أو تعميم',
                subtitle: 'يُنشر فوراً ويصل كإشعار لجميع الموظفين',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveAnnouncementPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _CreateOptionTile(
                icon: Icons.gavel_rounded,
                iconColor: scheme.tertiary,
                title: 'قرار إداري',
                subtitle: 'يُحفظ كمسودة ويمر بمراحل الاعتماد والنشر',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveDecisionsPage(),
                    ),
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

class _CreateOptionTile extends StatelessWidget {
  const _CreateOptionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: iconColor.withValues(alpha: 0.15),
                  radius: 24,
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
}

class _FeedCard extends StatelessWidget {
  const _FeedCard({required this.item});

  final MobileFeedItem item;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MobileFeedDetailPage(kind: item.kind, itemId: item.id),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                Image.network(
                  item.imageUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        MobileStatusPill(item.kind),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            item.postTypeLabel,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
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
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.body,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style:
                          Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.7,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (item.authorName != null &&
                        item.authorName!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundImage: item.authorPhotoUrl != null &&
                                    item.authorPhotoUrl!.isNotEmpty
                                ? NetworkImage(item.authorPhotoUrl!)
                                : null,
                            child: item.authorPhotoUrl == null ||
                                    item.authorPhotoUrl!.isEmpty
                                ? Text(
                                    item.authorName!.characters.first,
                                    style: const TextStyle(fontSize: 11),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              item.authorName!,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
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
            ],
          ),
        ),
      );
}
