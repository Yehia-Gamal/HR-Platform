import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
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
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: () => _showEngagement(context, ref),
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: const Text('من شاهد ومن تفاعل؟'),
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

  void _showEngagement(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AnnouncementEngagementSheet(announcementId: item.id),
    );
  }
}

/// لوحة "من شاهد ومن تفاعل؟" للإعلان — قوائم كاملة (0425).
class _AnnouncementEngagementSheet extends ConsumerWidget {
  const _AnnouncementEngagementSheet({required this.announcementId});

  final String announcementId;

  static const _reactionEmoji = {
    'like': '👍',
    'celebrate': '🎉',
    'support': '🤝',
    'insightful': '💡',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engagement =
        ref.watch(announcementEngagementProvider(announcementId));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: engagement.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref
                    .invalidate(announcementEngagementProvider(announcementId)),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
          data: (data) {
            final viewers = _listOf(data['viewers']);
            final reactions = _listOf(data['reactions']);
            final acknowledgements = _listOf(data['acknowledgements']);
            final viewerCount = data['viewerCount'] as int? ?? 0;
            final reactionCount = data['reactionCount'] as int? ?? 0;
            final acknowledgedCount = data['acknowledgedCount'] as int? ?? 0;

            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  _sectionHeader(
                    context,
                    icon: Icons.visibility_outlined,
                    title: 'من شاهد الإعلان؟',
                    count: viewerCount,
                  ),
                  if (viewers.isEmpty)
                    _emptyNote(context, 'لم يشاهده أحد بعد.')
                  else
                    ...viewers.map(
                      (v) => _PersonRow(
                        name: v['name'] as String? ?? 'موظف',
                        photoUrl: v['photoUrl'] as String?,
                        detail: (v['viewCount'] as int? ?? 1) > 1
                            ? '${v['viewCount']} مشاهدة'
                            : _timeLabel(v['at']),
                      ),
                    ),
                  const SizedBox(height: 18),
                  _sectionHeader(
                    context,
                    icon: Icons.favorite_outline,
                    title: 'من تفاعل معه؟',
                    count: reactionCount,
                  ),
                  if (reactions.isEmpty)
                    _emptyNote(context, 'لا تفاعلات بعد.')
                  else
                    ...reactions.map(
                      (r) => _PersonRow(
                        name: r['name'] as String? ?? 'موظف',
                        photoUrl: r['photoUrl'] as String?,
                        detail:
                            '${_reactionEmoji[r['reactionType']] ?? '👍'} ${_timeLabel(r['at'])}',
                      ),
                    ),
                  if (acknowledgedCount > 0) ...[
                    const SizedBox(height: 18),
                    _sectionHeader(
                      context,
                      icon: Icons.verified_outlined,
                      title: 'أقروا بالاطلاع',
                      count: acknowledgedCount,
                    ),
                    ...acknowledgements.map(
                      (a) => _PersonRow(
                        name: a['name'] as String? ?? 'موظف',
                        photoUrl: a['photoUrl'] as String?,
                        detail: _timeLabel(a['at']),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static List<Map<String, dynamic>> _listOf(Object? value) =>
      (value as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map<dynamic, dynamic>))
          .toList();

  Widget _sectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required int count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Spacer(),
        if (count > 0)
          Text(
            '$count',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _emptyNote(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );

  String _timeLabel(Object? value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value as String);
      return DateFormat('d MMM، h:mm a', 'ar').format(dt);
    } catch (_) {
      return '';
    }
  }
}

/// صف شخص واحد ضمن قوائم "من شاهد / من تفاعل".
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.photoUrl,
    required this.detail,
  });

  final String name;
  final String? photoUrl;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          AppAvatar(name: name, photoUrl: photoUrl, radius: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
