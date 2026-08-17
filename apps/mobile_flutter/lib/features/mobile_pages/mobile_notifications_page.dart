import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum _NotifFilter { all, unread }

class MobileNotificationsPage extends ConsumerStatefulWidget {
  const MobileNotificationsPage({super.key});

  @override
  ConsumerState<MobileNotificationsPage> createState() =>
      _MobileNotificationsPageState();
}

class _MobileNotificationsPageState
    extends ConsumerState<MobileNotificationsPage> {
  _NotifFilter _filter = _NotifFilter.all;
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _enterSelection() => setState(() => _selecting = true);

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(Iterable<MobileNotificationItem> visible) {
    setState(() => _selectedIds.addAll(visible.map((x) => x.id)));
  }

  void _deselectAll(Iterable<MobileNotificationItem> visible) {
    setState(() {
      for (final item in visible) {
        _selectedIds.remove(item.id);
      }
    });
  }

  Future<void> _confirmDeleteSelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الإشعارات المحددة'),
        content: Text(
          'سيتم حذف $count إشعار نهائيًا من حسابك. لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(mobileCommandsProvider)
          .deleteNotifications(_selectedIds.toList(growable: false));
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selectedIds.clear();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('تم حذف الإشعارات المحددة')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر حذف الإشعارات. أعد المحاولة.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(myNotificationsProvider);
    final items = notifications.asData?.value ?? const <MobileNotificationItem>[];
    final unread = items.where((x) => !x.isRead).toList();
    final visible = _filter == _NotifFilter.unread ? unread : items;
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((x) => _selectedIds.contains(x.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (_selecting)
            TextButton(
              onPressed: _exitSelection,
              child: const Text('إلغاء'),
            )
          else ...[
            IconButton(
              tooltip: 'تحديد الإشعارات',
              onPressed: _enterSelection,
              icon: const Icon(Icons.checklist_rounded),
            ),
            IconButton(
              tooltip: 'تعليم الكل كمقروء',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref
                    .read(mobileCommandsProvider)
                    .markNotificationsRead();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('تم تعليم كل الإشعارات كمقروءة')),
                );
              },
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myNotificationsProvider),
          child: notifications.when(
            loading: () => ListView(
              children: [
                const SizedBox(height: 260),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('تعذر تحميل الإشعارات. اسحب لأسفل لإعادة المحاولة.'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            data: (_) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'الكل (${items.length})',
                          selected: _filter == _NotifFilter.all,
                          onTap: () => setState(() => _filter = _NotifFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'غير المقروء (${unread.length})',
                          selected: _filter == _NotifFilter.unread,
                          onTap: () =>
                              setState(() => _filter = _NotifFilter.unread),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    children: [
                                      Icon(
                                        Icons.notifications_none,
                                        size: 48,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _filter == _NotifFilter.unread
                                            ? 'لا توجد إشعارات غير مقروءة'
                                            : 'لا توجد إشعارات حاليًا',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return _NotificationCard(
                                item: item,
                                selecting: _selecting,
                                selected: _selectedIds.contains(item.id),
                                onToggleSelect: () => _toggleSelect(item.id),
                                onTap: () => _open(item),
                                onLongPress: () {
                                  if (!_selecting) _enterSelection();
                                  _toggleSelect(item.id);
                                },
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              top: false,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: allVisibleSelected
                            ? () => _deselectAll(visible)
                            : () => _selectAll(visible),
                        child: Text(
                          allVisibleSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل',
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _confirmDeleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text('مسح المحدد (${_selectedIds.length})'),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _open(MobileNotificationItem item) async {
    if (item.hasSupportedAction) {
      try {
        if (!item.isRead) {
          await ref
              .read(mobileCommandsProvider)
              .markNotificationsRead([item.id]);
        }
        if (!mounted) return;
        if (item.entityType == 'announcement') {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MobileFeedDetailPage(
                kind: 'announcement',
                itemId: item.entityId!,
              ),
            ),
          );
          return;
        }

        final action = MobileActionItem(
          id: '${item.entityType}-${item.entityId}',
          kind: item.entityType!,
          title: item.title,
          subtitle: item.body,
          priority: item.priority,
          status: '',
          dueAt: null,
        );
        final target = await ref
            .read(mobileCommandsProvider)
            .resolveAction(action);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => mobilePageForActionTarget(target)),
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            const SnackBar(
              content: Text('تعذر فتح الإشعار بأمان. أعد المحاولة.'),
            ),
          );
        }
      }
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.item,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  final MobileNotificationItem item;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    return Card(
      child: Semantics(
        label: item.isRead ? null : 'إشعار غير مقروء',
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: selecting
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelect?.call(),
                  activeColor: Theme.of(context).colorScheme.error,
                )
              : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      backgroundColor: urgent
                          ? Theme.of(context).colorScheme.errorContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Icon(
                        _icon(item.category),
                        color: urgent
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (!item.isRead)
                      PositionedDirectional(
                        start: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
          title: Text(
            item.title,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    _categoryLabel(item.category),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (item.priority != 'normal') MobileStatusPill(item.priority),
                ],
              ),
              if (item.body != null && item.body!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(item.body!, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 7),
              Text(
                _relativeTime(item.createdAt.toLocal()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          trailing: selecting
              ? null
              : item.hasSupportedAction
                  ? const Icon(Icons.chevron_left_rounded)
                  : null,
          onTap: selecting ? onToggleSelect : (item.hasSupportedAction ? onTap : null),
          onLongPress: selecting ? null : onLongPress,
        ),
      ),
    );
  }

  IconData _icon(String category) => switch (category) {
    'request' => Icons.approval_outlined,
    'decision' => Icons.gavel_outlined,
    'announcement' => Icons.campaign_outlined,
    'survey' => Icons.how_to_vote_outlined,
    'dispute' => Icons.balance_outlined,
    'system' => Icons.settings_suggest_outlined,
    'recognition' => Icons.workspace_premium_outlined,
    'kpi' => Icons.assessment_outlined,
    'device' => Icons.fingerprint_outlined,
    'attendance' => Icons.schedule_outlined,
    'location' => Icons.location_on_outlined,
    'security' => Icons.shield_outlined,
    'privacy' => Icons.visibility_off_outlined,
    'documents' => Icons.description_outlined,
    'service' => Icons.support_agent_outlined,
    'wellbeing' => Icons.favorite_outline_rounded,
    'offboarding' => Icons.person_off_outlined,
    'daily_report' => Icons.article_outlined,
    'daily_report_like' => Icons.favorite_outline_rounded,
    'daily_report_comment' => Icons.chat_bubble_outline_rounded,
    'attendance_manager_notify' => Icons.schedule_outlined,
    _ => Icons.notifications_outlined,
  };

  String _categoryLabel(String category) => switch (category) {
    'request' => 'طلب',
    'decision' => 'قرار رسمي',
    'announcement' => 'إعلان',
    'survey' => 'استبيان',
    'dispute' => 'قضية',
    'system' => 'نظام',
    'recognition' => 'تقدير',
    'kpi' => 'الأداء',
    'device' => 'جهاز بصمة',
    'attendance' => 'حضور',
    'location' => 'موقع',
    'security' => 'أمان',
    'privacy' => 'خصوصية',
    'documents' => 'مستندات',
    'service' => 'خدمة',
    'wellbeing' => 'رفاهية',
    'offboarding' => 'إنهاء خدمة',
    'daily_report' => 'تقرير يومي',
    'daily_report_like' => 'إعجاب بتقرير',
    'daily_report_comment' => 'تعليق على تقرير',
    'attendance_manager_notify' => 'حضور',
    _ => 'عام',
  };

  /// وقت نسبي عربي: "الآن"، "قبل 5 د"، "قبل 3 س"، "قبل يومين".
  String _relativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';
    return DateFormat('d MMM y', 'ar').format(time);
  }
}