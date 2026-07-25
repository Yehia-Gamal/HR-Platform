import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileFeedDetailPage extends ConsumerWidget {
  const MobileFeedDetailPage({
    required this.kind,
    required this.itemId,
    super.key,
  });

  final String kind;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (kind: kind, id: itemId);
    final item = ref.watch(mobileFeedDetailProvider(key));
    return Scaffold(
      appBar: AppBar(
        title: Text(kind == 'decision' ? 'القرار الإداري' : 'الخبر الرسمي'),
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
          data: (value) => _FeedDetailContent(item: value),
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
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
}
