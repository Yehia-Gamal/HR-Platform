import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileFeedDetailPage extends ConsumerStatefulWidget {
  const MobileFeedDetailPage({
    required this.kind,
    required this.itemId,
    super.key,
  });

  final String kind;
  final String itemId;

  @override
  ConsumerState<MobileFeedDetailPage> createState() =>
      _MobileFeedDetailPageState();
}

class _MobileFeedDetailPageState
    extends ConsumerState<MobileFeedDetailPage> {
  bool _viewRecorded = false;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final itemId = widget.itemId;
    final key = (kind: kind, id: itemId);
    final item = ref.watch(mobileFeedDetailProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (kind) {
          'decision' => 'القرار الإداري',
          'recognition' => 'التقدير',
          _ => 'الخبر الرسمي',
        }),
      ),
      body: SafeArea(
        child: item.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    humanizeError(error),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () =>
                        ref.invalidate(mobileFeedDetailProvider(key)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (value) {
            if (kind == 'announcement' && !_viewRecorded) {
              _viewRecorded = true;
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  await ref
                      .read(mobileCommandsProvider)
                      .recordAnnouncementView(itemId);
                  if (mounted) {
                    ref.invalidate(mobileFeedDetailProvider(key));
                  }
                } catch (_) {
                  // المشاهدة تحليلية؛ فشلها لا يمنع المستخدم من قراءة الإعلان.
                }
              });
            }
            return _FeedDetailContent(item: value);
          },
        ),
      ),
    );
  }
}

class _FeedDetailContent extends ConsumerWidget {
  const _FeedDetailContent({required this.item});

  final MobileFeedItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                Image.network(
                  item.imageUrl!,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, st) => const SizedBox.shrink(),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MobileStatusPill(item.kind),
                        MobileStatusPill(item.priority),
                        if (item.publishedAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              DateFormat(
                                'd MMMM y',
                                'ar',
                              ).format(item.publishedAt!.toLocal()),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      item.title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      item.body,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (item.requiresAcknowledgement) ...[
          const SizedBox(height: 12),
          if (item.myAcknowledged)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Semantics(
                      label: 'مُقَرّ',
                      child: const Icon(
                        Icons.verified,
                        color: Color(0xFF0F9F6E),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('تم تسجيل اطلاعك وإقرارك على هذا الإصدار.'),
                    ),
                  ],
                ),
              ),
            )
          else
            FilledButton.icon(
              onPressed: () => _acknowledge(context, ref),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('تم الاطلاع والإقرار'),
            ),
        ],
        if (item.kind == 'announcement') ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.visibility_outlined, size: 20),
                      const SizedBox(width: 6),
                      Text('${item.viewCount} مشاهدة'),
                      const SizedBox(width: 16),
                      const Icon(Icons.favorite_outline, size: 20),
                      const SizedBox(width: 6),
                      Text('${item.reactionCount} تفاعل'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      ('like', '👍', 'أعجبني'),
                      ('celebrate', '🎉', 'احتفال'),
                      ('support', '🤝', 'دعم'),
                      ('insightful', '💡', 'مفيد'),
                    ].map((reaction) {
                      final selected = item.myReaction == reaction.$1;
                      final count = item.reactionSummary[reaction.$1] ?? 0;
                      return FilterChip(
                        selected: selected,
                        avatar: Text(reaction.$2),
                        label: Text('${reaction.$3}${count > 0 ? ' $count' : ''}'),
                        onSelected: (_) => _react(context, ref, reaction.$1),
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _acknowledge(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(mobileCommandsProvider).acknowledge(item);
      ref.invalidate(mobileFeedDetailProvider((kind: item.kind, id: item.id)));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تسجيل الإقرار.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Future<void> _react(
    BuildContext context,
    WidgetRef ref,
    String reactionType,
  ) async {
    try {
      await ref
          .read(mobileCommandsProvider)
          .toggleAnnouncementReaction(item.id, reactionType);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }
}
