import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
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

    // إزالة تكرار العنوان داخل المتن في حال كان الكاتب بدأ المتن بالعنوان نصياً
    final trimmedTitle = item.title.trim();
    String cleanBody = item.body.trim();
    if (cleanBody == trimmedTitle) {
      cleanBody = '';
    } else if (cleanBody.startsWith(trimmedTitle)) {
      cleanBody = cleanBody.substring(trimmedTitle.length).trim();
      cleanBody = cleanBody.replaceFirst(RegExp(r'^[-:،\.\n\r\s]+'), '').trim();
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. بطاقة الخبر / الإعلان الرئيسية
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
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
                    // شارات الحالة والأولوية والتاريخ
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        MobileStatusPill(item.kind),
                        MobileStatusPill(item.priority),
                        if (item.publishedAt != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.4,
                      ),
                    ),
                    if (cleanBody.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      SelectableText(
                        cleanBody,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.8,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. قسم الإقرار بالاطلاع والعلم (إذا كان الإعلان يتطلب إقراراً)
        if (item.requiresAcknowledgement) ...[
          const SizedBox(height: 12),
          if (item.myAcknowledged)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
              ),
              color: const Color(0xFF10B981).withValues(alpha: .08),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF10B981),
                      size: 26,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تم تسجيل إقرارك بالاطلاع والعلم ✓',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF10B981),
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'تم توثيق إقرارك الرسمي على هذا الإعلان بنجاح.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: .4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.assignment_late_outlined,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'مطلوب إقرار إداري إلزامي',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'يرجى تأكيد اطلاعك وقراءتك لمحتوى هذا الإعلان الرسمي للإدارة.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _acknowledge(context, ref),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text(
                        'أقر بالاطلاع والعلم بهذا الإعلان',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],

        // 3. قسم التفاعلات والمشاهدات (للإعلانات)
        if (item.kind == 'announcement') ...[
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // شريط العدادات وزر من شاهد ومن تفاعل
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.visibility_outlined,
                        label: '${item.viewCount} مشاهدة',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.favorite_outline,
                        label: '${item.reactionCount} تفاعل',
                        isHighlighted: item.reactionCount > 0,
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _showEngagement(context, ref),
                        icon: const Icon(Icons.people_alt_outlined, size: 16),
                        label: const Text('من شاهد وتفاعل؟'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // أزرار التفاعل الـ 4 في صف واحد متناسق (Row of 4 Expanded)
                  Row(
                    children: const [
                      ('like', '👍', 'أعجبني'),
                      ('celebrate', '🎉', 'احتفال'),
                      ('support', '🤝', 'دعم'),
                      ('insightful', '💡', 'مفيد'),
                    ].map((reaction) {
                      final selected = item.myReaction == reaction.$1;
                      final count = item.reactionSummary[reaction.$1] ?? 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Material(
                            color: selected
                                ? colorScheme.primaryContainer
                                : colorScheme.surfaceContainerHighest
                                    .withValues(alpha: .5),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () =>
                                  _react(context, ref, reaction.$1),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant
                                            .withValues(alpha: .4),
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      reaction.$2,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          reaction.$3,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            fontSize: 10,
                                            fontWeight: selected
                                                ? FontWeight.bold
                                                : FontWeight.w600,
                                            color: selected
                                                ? colorScheme
                                                    .onPrimaryContainer
                                                : colorScheme
                                                    .onSurfaceVariant,
                                          ),
                                        ),
                                        if (count > 0) ...[
                                          const SizedBox(width: 3),
                                          Text(
                                            '$count',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: selected
                                                  ? colorScheme.primary
                                                  : colorScheme
                                                      .onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
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
      ref.invalidate(
        mobileFeedDetailProvider((kind: item.kind, id: item.id)),
      );
      ref.invalidate(announcementEngagementProvider(item.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل إقرارك بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
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
      ref.invalidate(
        mobileFeedDetailProvider((kind: item.kind, id: item.id)),
      );
      ref.invalidate(announcementEngagementProvider(item.id));
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

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String label;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlighted
            ? colorScheme.primaryContainer.withValues(alpha: .5)
            : colorScheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: isHighlighted
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isHighlighted
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// تبويبات لوحة تفاعل الإعلان
enum _EngagementSheetTab { viewers, reactions, acknowledgements }

/// لوحة "من شاهد ومن تفاعل؟" للإعلان — مطوّرة بتبويبات وتنسيق مريح
class _AnnouncementEngagementSheet extends ConsumerStatefulWidget {
  const _AnnouncementEngagementSheet({required this.announcementId});

  final String announcementId;

  @override
  ConsumerState<_AnnouncementEngagementSheet> createState() =>
      _AnnouncementEngagementSheetState();
}

class _AnnouncementEngagementSheetState
    extends ConsumerState<_AnnouncementEngagementSheet> {
  _EngagementSheetTab _activeTab = _EngagementSheetTab.viewers;

  static const _reactionEmoji = {
    'like': '👍',
    'celebrate': '🎉',
    'support': '🤝',
    'insightful': '💡',
  };

  static const _reactionNames = {
    'like': 'أعجبني',
    'celebrate': 'احتفال',
    'support': 'دعم',
    'insightful': 'مفيد',
  };

  @override
  Widget build(BuildContext context) {
    final engagement =
        ref.watch(announcementEngagementProvider(widget.announcementId));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: engagement.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(40),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('جاري تحميل بيانات التفاعل...'),
                ],
              ),
            ),
          ),
          error: (error, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              TextButton(
                onPressed: () => ref.invalidate(
                  announcementEngagementProvider(widget.announcementId),
                ),
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
                maxHeight: MediaQuery.sizeOf(context).height * .78,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // شريط العنوان وزر الإغلاق
                  Row(
                    children: [
                      Icon(
                        Icons.groups_rounded,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'تفاعل ومشاهدات الإعلان',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // أزرار التبويبات الثلاثية
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(
                            Icons.visibility_outlined,
                            size: 16,
                          ),
                          label: Text(
                            'المشاهدات ($viewerCount)',
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _activeTab == _EngagementSheetTab.viewers,
                          onSelected: (_) => setState(
                            () => _activeTab = _EngagementSheetTab.viewers,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(
                            Icons.favorite_outline,
                            size: 16,
                          ),
                          label: Text(
                            'التفاعلات ($reactionCount)',
                            overflow: TextOverflow.ellipsis,
                          ),
                          selected: _activeTab == _EngagementSheetTab.reactions,
                          onSelected: (_) => setState(
                            () => _activeTab = _EngagementSheetTab.reactions,
                          ),
                        ),
                      ),
                      if (acknowledgedCount > 0) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: ChoiceChip(
                            avatar: const Icon(
                              Icons.verified_outlined,
                              size: 16,
                            ),
                            label: Text(
                              'الإقرارات ($acknowledgedCount)',
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: _activeTab ==
                                _EngagementSheetTab.acknowledgements,
                            onSelected: (_) => setState(
                              () => _activeTab =
                                  _EngagementSheetTab.acknowledgements,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Divider(height: 20),

                  // محتوى التبويب النشط
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (_activeTab == _EngagementSheetTab.viewers) ...[
                          if (viewers.isEmpty)
                            _emptyBox(
                              context,
                              icon: Icons.visibility_off_outlined,
                              title: 'لا توجد مشاهدات مسجلة بعد',
                            )
                          else
                            ...viewers.map(
                              (v) => _PersonRow(
                                name: v['name'] as String? ?? 'موظف',
                                photoUrl: v['photoUrl'] as String?,
                                subtitle: (v['viewCount'] as int? ?? 1) > 1
                                    ? '${v['viewCount']} مشاهدات · آخرها ${_timeLabel(v['at'])}'
                                    : 'شاهد في ${_timeLabel(v['at'])}',
                              ),
                            ),
                        ],
                        if (_activeTab == _EngagementSheetTab.reactions) ...[
                          if (reactions.isEmpty)
                            _emptyBox(
                              context,
                              icon: Icons.favorite_border_rounded,
                              title: 'لا توجد تفاعلات بعد',
                              subtitle:
                                  'كن أول من يترك تفاعلاً على هذا الإعلان ✨',
                            )
                          else
                            ...reactions.map(
                              (r) {
                                final rType = r['reactionType'] as String?;
                                final emoji = _reactionEmoji[rType] ?? '👍';
                                final label = _reactionNames[rType] ?? 'تفاعل';
                                return _PersonRow(
                                  name: r['name'] as String? ?? 'موظف',
                                  photoUrl: r['photoUrl'] as String?,
                                  subtitle: '$label · ${_timeLabel(r['at'])}',
                                  badgeEmoji: emoji,
                                );
                              },
                            ),
                        ],
                        if (_activeTab ==
                            _EngagementSheetTab.acknowledgements) ...[
                          if (acknowledgements.isEmpty)
                            _emptyBox(
                              context,
                              icon: Icons.assignment_late_outlined,
                              title: 'لم يقم أحد بالإقرار بعد',
                            )
                          else
                            ...acknowledgements.map(
                              (a) => _PersonRow(
                                name: a['name'] as String? ?? 'موظف',
                                photoUrl: a['photoUrl'] as String?,
                                subtitle:
                                    'أقر بالعلم في ${_timeLabel(a['at'])}',
                                trailingBadge: const Icon(
                                  Icons.verified_rounded,
                                  color: Color(0xFF10B981),
                                  size: 18,
                                ),
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
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

  Widget _emptyBox(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.onSurfaceVariant.withValues(alpha: .5)),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant.withValues(alpha: .8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _timeLabel(Object? value) {
    if (value == null) return '';
    try {
      final dt = DateTime.parse(value as String).toLocal();
      return DateFormat('d MMM، h:mm a', 'ar').format(dt);
    } catch (_) {
      return '';
    }
  }
}

/// صف شخص واحد ضمن قوائم "من شاهد / من تفاعل / من أقر".
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.photoUrl,
    required this.subtitle,
    this.badgeEmoji,
    this.trailingBadge,
  });

  final String name;
  final String? photoUrl;
  final String subtitle;
  final String? badgeEmoji;
  final Widget? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AppAvatar(name: name, photoUrl: photoUrl, radius: 20),
              if (badgeEmoji != null)
                Positioned(
                  bottom: -2,
                  left: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      badgeEmoji!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
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
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (trailingBadge != null) trailingBadge!,
        ],
      ),
    );
  }
}
