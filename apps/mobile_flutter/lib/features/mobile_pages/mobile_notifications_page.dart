import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/notification_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// مجموعة إشعارات مجمّعة — نفس النوع/العنوان مع عدة كيانات.
class _GroupedNotifications {
  const _GroupedNotifications({
    required this.representative,
    required this.items,
    required this.label,
  });

  final MobileNotificationItem representative;
  final List<MobileNotificationItem> items;
  final String label;

  bool get isGrouped => items.length > 1;
  int get unreadCount => items.where((x) => !x.isRead).length;
}

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

  /// تجميع الإشعارات حسب النوع + العنوان — الإشعارات المتشابهة
  /// تُعرض كبطاقة واحدة بعدد، والنقر يفتح كرت التفاصيل.
  List<_GroupedNotifications> _groupNotifications(
    List<MobileNotificationItem> items,
  ) {
    final map = <String, List<MobileNotificationItem>>{};
    for (final item in items) {
      final key = '${item.canonicalType ?? item.category}::${item.title}';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map.entries.map((e) {
      final list = e.value;
      final rep = list.first;
      final count = list.length;
      return _GroupedNotifications(
        representative: rep,
        items: list,
        label: count > 1 ? '($count)' : '',
      );
    }).toList();
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

  /// بناء القائمة المجمّعة مع دعم السحب للحذف.
  Widget _buildGroupedList(List<MobileNotificationItem> visible) {
    final groups = _groupNotifications(visible);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final item = group.representative;
        final card = _NotificationCard(
          item: item,
          groupLabel: group.label,
          unreadCount: group.unreadCount,
          selecting: _selecting,
          selected: _selectedIds.contains(item.id),
          onToggleSelect: () => _toggleSelect(item.id),
          onTap: () => _openGroup(group),
          onLongPress: () {
            if (!_selecting) _enterSelection();
            _toggleSelect(item.id);
          },
        );

        if (_selecting) return card;

        return Dismissible(
          key: ValueKey(item.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) async {
            final messenger = ScaffoldMessenger.of(context);
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('حذف الإشعار'),
                content: Text(
                  group.isGrouped
                      ? 'سيتم حذف ${group.items.length} إشعار مرتبط.'
                      : 'سيتم حذف هذا الإشعار نهائيًا.',
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
            if (confirmed != true || !mounted) return false;
            try {
              final ids = group.items.map((x) => x.id).toList();
              await ref
                  .read(mobileCommandsProvider)
                  .deleteNotifications(ids);
              if (!mounted) return false;
              messenger.showSnackBar(
                const SnackBar(content: Text('تم حذف الإشعار')),
              );
              return true;
            } catch (_) {
              if (!mounted) return false;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('تعذر حذف الإشعار. أعد المحاولة.'),
                ),
              );
              return false;
            }
          },
          background: Container(
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: 24),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
          child: card,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(myNotificationsProvider);
    final items =
        notifications.asData?.value ?? const <MobileNotificationItem>[];
    final unread = items.where((x) => !x.isRead).toList();
    final visible = _filter == _NotifFilter.unread ? unread : items;
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((x) => _selectedIds.contains(x.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (_selecting)
            TextButton(onPressed: _exitSelection, child: const Text('إلغاء'))
          else ...[
            IconButton(
              tooltip: 'تفضيلات الإشعارات',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsPage(),
                ),
              ),
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: 'تحديد متعدد',
              onPressed: _enterSelection,
              icon: const Icon(Icons.checklist_rounded),
            ),
            IconButton(
              tooltip: 'تعليم الكل كمقروء',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(mobileCommandsProvider).markNotificationsRead();
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('تم تعليم كل الإشعارات كمقروءة'),
                  ),
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
                          child: Text(
                            'تعذر تحميل الإشعارات. اسحب لأسفل لإعادة المحاولة.',
                          ),
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
                          onTap: () =>
                              setState(() => _filter = _NotifFilter.all),
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
                        : _buildGroupedList(visible),
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
                          allVisibleSelected
                              ? 'إلغاء تحديد الكل'
                              : 'تحديد الكل',
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

  /// الصفحة المحلية المقابلة لنوع الإشعار — `null` إن لم يكن له صفحة مباشرة.
  Widget? _localPageFor(MobileNotificationItem item) {
    if (!item.hasLocalRoute) return null;
    return switch (item.canonicalType) {
      'instant_penalty' => MyInstantPenaltiesPage(highlightId: item.entityId),
      'daily_report' => const MobileDailyReportsPage(),
      'device' => const PasskeyDevicesPage(),
      _ => null,
    };
  }

  /// فتح مجموعة إشعارات: إذا كان لها صفحة نفتح أول عنصر، وإلا نعلّم الكل مقروءة.
  Future<void> _openGroup(_GroupedNotifications group) async {
    if (group.isGrouped) {
      // تعليم الكل كمقروء في المجموعة.
      final unreadIds = group.items
          .where((x) => !x.isRead)
          .map((x) => x.id)
          .toList();
      if (unreadIds.isNotEmpty) {
        try {
          await ref
              .read(mobileCommandsProvider)
              .markNotificationsRead(unreadIds);
        } catch (_) {
          // فشل صامت.
        }
      }
      if (!mounted) return;
      // فتح أول عنصر له صفحة.
      final withAction = group.items.firstWhere(
        (x) => x.hasSupportedAction,
        orElse: () => group.items.first,
      );
      await _open(withAction);
      return;
    }
    await _open(group.representative);
  }

  Future<void> _open(MobileNotificationItem item) async {
    // التعليم كمقروء فوراً عند النقر — حتى للإشعارات المعلوماتية التي لا
    // تملك صفحة موبايل (كان النقر عليها لا يفعل شيئاً إطلاقاً).
    if (!item.isRead) {
      try {
        await ref.read(mobileCommandsProvider).markNotificationsRead([item.id]);
      } catch (_) {
        // فشل التعليم لا يمنع فتح الإشعار.
      }
    }
    if (!mounted) return;
    if (!item.hasSupportedAction) {
      // معلوماتي: نُصرّح بذلك بدل صمت يبدو للمستخدم وكأن النقر لا يفعل شيئاً.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('إشعار للعلم فقط — لا توجد صفحة مرتبطة به.')),
      );
      return;
    }

    try {
      if (item.canonicalType == 'announcement') {
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

      // أنواع لها صفحة موبايل مباشرة — لا يعرفها resolve_mobile_action_target
      // فكان النقر عليها بلا أثر رغم وجود الصفحة في التطبيق.
      final localPage = _localPageFor(item);
      if (localPage != null) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => localPage));
        return;
      }

      // حضور الموظف نفسه (بصمة/تذكير): سجلّه الشخصي على يوم الحدث —
      // أدق من صفحة خدمات الحضور العامة التي يعيدها الـ RPC.
      final workDate = item.meta('workDate');
      final rawType = (item.entityType ?? '').toLowerCase();
      if (workDate != null && (rawType == 'attendance_daily' || rawType == 'punch_reminder')) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AttendanceHistoryPage(highlightDate: workDate),
          ),
        );
        return;
      }

      final action = MobileActionItem(
        id: '${item.canonicalType}-${item.entityId}',
        kind: item.canonicalType!,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر فتح الإشعار بأمان. أعد المحاولة.'),
          ),
        );
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
    this.groupLabel = '',
    this.unreadCount = 0,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  final MobileNotificationItem item;
  final VoidCallback onTap;
  final String groupLabel;
  final int unreadCount;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    final unread = !item.isRead;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: unread
            ? BorderSide(
                color: scheme.primary.withValues(alpha: 0.5),
                width: 1.5,
              )
            : BorderSide.none,
      ),
      child: Semantics(
        label: unread ? 'إشعار غير مقروء' : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          leading: selecting
              ? Checkbox(
                  value: selected,
                  onChanged: (_) => onToggleSelect?.call(),
                  activeColor: scheme.error,
                )
              : CircleAvatar(
                  backgroundColor: urgent
                      ? scheme.errorContainer
                      : unread
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                  child: Icon(
                    _icon(item.category),
                    size: 20,
                    color: urgent
                        ? scheme.onErrorContainer
                        : unread
                            ? scheme.onPrimaryContainer
                            : scheme.onSurfaceVariant,
                  ),
                ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (groupLabel.isNotEmpty)
                Container(
                  margin: const EdgeInsetsDirectional.only(start: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    groupLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  _CategoryChip(category: item.category),
                  if (item.priority != 'normal') ...[
                    const SizedBox(width: 6),
                    _PriorityBadge(priority: item.priority),
                  ],
                  if (unread) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'جديد',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (item.body != null && item.body!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.body!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unread ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                _relativeTime(item.createdAt.toLocal()),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          trailing: selecting
              ? null
              : item.hasSupportedAction
                  ? Icon(
                      Icons.chevron_left_rounded,
                      color: unread
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    )
                  : null,
          onTap: selecting ? onToggleSelect : onTap,
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

/// شريحة فئة الإشعار — تصغير معلومات الفئة في سطر واحد.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label(category),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String _label(String category) => switch (category) {
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
}

/// شارة الأولوية — أوضح من MobileStatusPill مع ألوان مميزة لكل مستوى.
class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (priority) {
      'urgent' => (
        Theme.of(context).colorScheme.error,
        'عاجل',
      ),
      'high' => (
        const Color(0xFFF57C00),
        'مهم',
      ),
      _ => (
        Theme.of(context).colorScheme.onSurfaceVariant,
        priority,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}
