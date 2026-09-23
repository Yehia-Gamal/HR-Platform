import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
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

enum _NotifFilter { all, unread }

/// تحويل الأكواد التقنية في نص الإشعار إلى نصوص عربية مفهومة
String _humanizeNotificationBody(String? body) {
  if (body == null || body.trim().isEmpty) return '';
  var text = body;
  text = text.replaceAll('missing_check_in', 'نسيان بصمة دخول');
  text = text.replaceAll('missing_check_out', 'نسيان بصمة خروج');
  text = text.replaceAll('wrong_time', 'تعديل توقيت البصمة');
  text = text.replaceAll('wrong_status', 'تعديل حالة الدوام');
  text = text.replaceAll('full_day_missing', 'غياب يوم كامل');
  text = text.replaceAll('( )', '').replaceAll('()', '');
  return text.trim();
}

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

  /// بناء القائمة الفردية الكاملة — كل إشعار يظهر بشكل مستقل ومضغوط
  Widget _buildNotificationList(List<MobileNotificationItem> visible) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        final card = _NotificationCard(
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
                content: const Text('سيتم حذف هذا الإشعار نهائيًا.'),
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
              await ref
                  .read(mobileCommandsProvider)
                  .deleteNotifications([item.id]);
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
            padding: const EdgeInsetsDirectional.only(end: 20),
            margin: const EdgeInsets.symmetric(vertical: 3.5),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(10),
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
              children: const [
                SizedBox(height: 260),
                Center(child: CircularProgressIndicator()),
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
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
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
                        : _buildNotificationList(visible),
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
      'attendance_correction' => item.entityId != null
          ? AttendanceCorrectionDetailPage(correctionId: item.entityId!)
          : null,
      _ => null,
    };
  }

  Future<void> _open(MobileNotificationItem item) async {
    // التعليم كمقروء فوراً عند النقر
    if (!item.isRead) {
      try {
        await ref.read(mobileCommandsProvider).markNotificationsRead([item.id]);
      } catch (_) {
        // فشل التعليم لا يمنع فتح الإشعار.
      }
    }
    if (!mounted) return;

    // توجيه طلبات تصحيح البصمة فوراً إلى شاشة مراجعة تصحيح البصمة
    if (item.canonicalType == 'attendance_correction' ||
        item.entityType == 'attendance_corrections' ||
        item.entityType == 'attendance_correction' ||
        (item.entityId != null && item.title.contains('تصحيح حضور'))) {
      if (item.entityId != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AttendanceCorrectionDetailPage(
              correctionId: item.entityId!,
            ),
          ),
        );
        return;
      }
    }

    if (!item.hasSupportedAction) {
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

      // أنواع لها صفحة موبايل مباشرة
      final localPage = _localPageFor(item);
      if (localPage != null) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => localPage));
        return;
      }

      // حضور الموظف نفسه (بصمة/تذكير): سجلّه الشخصي على يوم الحدث
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// بطاقة إشعار نحيفة ورشيقة وعصرية
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
    final scheme = Theme.of(context).colorScheme;
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    final unread = !item.isRead;
    final humanizedBody = _humanizeNotificationBody(item.body);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3.5),
      decoration: BoxDecoration(
        color: unread
            ? scheme.primary.withValues(alpha: 0.05)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: unread
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.25),
          width: unread ? 1.0 : 0.6,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: selecting ? onToggleSelect : onTap,
          onLongPress: selecting ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // الصندوق الأيمن: أيقونة أو صندوق تحديد
                if (selecting)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelect?.call(),
                      activeColor: scheme.error,
                    ),
                  )
                else
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: urgent
                          ? scheme.errorContainer
                          : unread
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _icon(item.category),
                      size: 17,
                      color: urgent
                          ? scheme.onErrorContainer
                          : unread
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 10),

                // المحتوى الأوسط: العنوان والوقت في الأعلى، والتفاصيل في الأسفل
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // السطر الأول: العنوان + الوقت النسبي + نقطة غير المقروء
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: unread
                                    ? scheme.onSurface
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _relativeTime(item.createdAt.toLocal()),
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),

                      // السطر الثاني: الفئة + نص الإشعار النظيف
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _SlimBadge(
                            text: _categoryLabel(item.category),
                            color: urgent ? scheme.error : scheme.primary,
                          ),
                          if (urgent) ...[
                            const SizedBox(width: 4),
                            _SlimBadge(
                              text: item.priority == 'urgent' ? 'عاجل' : 'مهم',
                              color: scheme.error,
                            ),
                          ],
                          if (humanizedBody.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                humanizedBody,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: unread
                                      ? scheme.onSurface
                                          .withValues(alpha: 0.85)
                                      : scheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // السهم الأيسر (إن كان مدعوماً)
                if (!selecting && item.hasSupportedAction) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: unread
                        ? scheme.primary
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ],
            ),
          ),
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
    'decision' => 'قرار',
    'announcement' => 'إعلان',
    'survey' => 'استبيان',
    'dispute' => 'قضية',
    'system' => 'نظام',
    'recognition' => 'تقدير',
    'kpi' => 'أداء',
    'device' => 'بصمة',
    'attendance' => 'حضور',
    'location' => 'موقع',
    'security' => 'أمان',
    'privacy' => 'خصوصية',
    'documents' => 'وثائق',
    'service' => 'خدمة',
    'wellbeing' => 'رفاهية',
    'offboarding' => 'إنهاء',
    'daily_report' => 'تقرير',
    'daily_report_like' => 'إعجاب',
    'daily_report_comment' => 'تعليق',
    'attendance_manager_notify' => 'حضور',
    _ => 'عام',
  };

  String _relativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} ي';
    return DateFormat('d MMM', 'ar').format(time);
  }
}

/// شارة صغيرة ونحيفة مناسبة للبطاقات المدمجة
class _SlimBadge extends StatelessWidget {
  const _SlimBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
