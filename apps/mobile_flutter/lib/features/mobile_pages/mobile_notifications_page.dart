import 'dart:async';

import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_project_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
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
  final Set<String> _localReadIds = {};

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
          localRead: _localReadIds.contains(item.id),
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
    final items = notifications.value ?? const <MobileNotificationItem>[];
    final unread = items
        .where((x) => !x.isRead && !_localReadIds.contains(x.id))
        .toList();
    final visible = _filter == _NotifFilter.unread ? unread : items;
    final allVisibleSelected =
        visible.isNotEmpty && visible.every((x) => _selectedIds.contains(x.id));
    final hasItems = items.isNotEmpty;
    final isInitialLoading = notifications.isLoading && !hasItems;
    final isHardError = notifications.hasError && !hasItems;

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
                setState(() {
                  _localReadIds.addAll(items.map((x) => x.id));
                });
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
          child: isInitialLoading
              ? ListView(
                  children: const [
                    SizedBox(height: 260),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : isHardError
                  ? ListView(
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
                    )
                  : Column(
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
      'association_project' => item.entityId != null
          ? AssociationProjectDetailPage(projectId: item.entityId!)
          : null,
      _ => null,
    };
  }

  Future<void> _open(MobileNotificationItem item) async {
    // 1. تعليم كمقروء محلياً فوراً + خلفياً بدون تعطيل التنقل أو تجميد الشاشة
    if (!item.isRead && !_localReadIds.contains(item.id)) {
      setState(() => _localReadIds.add(item.id));
      unawaited(
        ref
            .read(mobileCommandsProvider)
            .markNotificationsRead([item.id])
            .catchError((_) {}),
      );
    }
    if (!mounted) return;

    // 2. إذا كان للإشعار رابط عميق صريح (deepLink أو actionUrl)
    final rawLink = item.meta('deepLink') ?? item.actionUrl;
    if (rawLink != null && rawLink.trim().isNotEmpty) {
      final route = resolveRouteFromDeepLink(rawLink);
      final uri = Uri.tryParse(route);
      if (uri != null &&
          uri.pathSegments.length >= 3 &&
          uri.pathSegments[0] == 'action') {
        final direct = getDirectActionPage(
          kind: uri.pathSegments[1],
          actionId: uri.pathSegments[2],
          action: uri.queryParameters['action'],
        );
        if (direct != null) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => direct),
          );
          return;
        }
      }
    }

    // 3. حضور الموظف نفسه (بصمة/تذكير): سجلّه الشخصي على يوم الحدث
    final workDate = item.meta('workDate');
    final rawType = (item.entityType ?? '').toLowerCase();
    final isSelf = item.metadata['self'] == true;
    if (isSelf &&
        workDate != null &&
        (rawType == 'attendance_daily' || rawType == 'punch_reminder')) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AttendanceHistoryPage(highlightDate: workDate),
        ),
      );
      return;
    }

    // 4. مسار مباشر وفوري لجميع أنواع الإشعارات المعروفة في التطبيق
    final directPage = getDirectActionPage(
      kind: item.canonicalType ?? item.entityType ?? '',
      actionId: item.entityId ?? '',
    );
    if (directPage != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => directPage),
      );
      return;
    }

    // 5. أنواع لها صفحة محلية مباشرة
    final localPage = _localPageFor(item);
    if (localPage != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => localPage),
      );
      return;
    }

    // 6. كل الإشعارات الأخرى (تنبيهات إدارية، وصول موظف، إيقاف، غرامة تابعة، إشعار نظام):
    // فتح ورقة التفاصيل الذكية التفاعلية مباشرة فوراً دون أي انتظار
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationDetailSheet(item: item),
    );
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
    this.localRead = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  final MobileNotificationItem item;
  final VoidCallback onTap;
  final bool selecting;
  final bool selected;
  final bool localRead;
  final VoidCallback? onToggleSelect;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    final unread = !item.isRead && !localRead;
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
                      _notificationIcon(item.category),
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
                            _notificationRelativeTime(item.createdAt.toLocal()),
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
                            text: _notificationCategoryLabel(item.category),
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

                // السهم الأيسر لكل الإشعارات القابلة للنقر
                if (!selecting) ...[
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
}

IconData _notificationIcon(String category) => switch (category) {
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

String _notificationCategoryLabel(String category) => switch (category) {
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

String _notificationRelativeTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'الآن';
  if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
  if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
  if (diff.inDays < 30) return 'قبل ${diff.inDays} ي';
  return DateFormat('d MMM', 'ar').format(time);
}

/// ورقة تفاصيل الإشعار الشاملة — تفتح فوراً عند النقر على أي إشعار للعلم أو إشعار عام
class NotificationDetailSheet extends StatelessWidget {
  const NotificationDetailSheet({required this.item, super.key});

  final MobileNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    final humanBody = _humanizeNotificationBody(item.body);
    final meta = item.metadata;

    final amount = meta['amount'] ?? meta['newAmount'];
    final lateMinutes = meta['lateMinutes'];
    final workDate = item.meta('workDate');
    final time = item.meta('time');
    final employeeName = item.meta('employeeName') ?? item.meta('employee_name');
    final reason = item.meta('reason');
    final requestType = item.meta('requestType');

    final isAttendance = item.canonicalType == 'attendance' ||
        (item.entityType ?? '').contains('attendance');
    final isPenalty = (item.canonicalType ?? '').contains('penalty') ||
        (item.entityType ?? '').contains('penalty');
    final isRequest = item.canonicalType == 'request' ||
        (item.entityType ?? '').contains('request');
    final isTask = item.canonicalType == 'task' ||
        (item.entityType ?? '').contains('task');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.paddingOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // شريط السحب بالأعلى
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // رأس الإشعار: الأيقونة + الفئة + الأولوية + الوقت
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: urgent
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _notificationIcon(item.category),
                    size: 22,
                    color: urgent
                        ? scheme.onErrorContainer
                        : scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _SlimBadge(
                            text: _notificationCategoryLabel(item.category),
                            color: urgent ? scheme.error : scheme.primary,
                          ),
                          if (urgent) ...[
                            const SizedBox(width: 6),
                            _SlimBadge(
                              text: item.priority == 'urgent' ? 'عاجل جداً' : 'أولوية عالية',
                              color: scheme.error,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('d MMMM yyyy — hh:mm a', 'ar')
                            .format(item.createdAt.toLocal()),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // عنوان الإشعار
            Text(
              item.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 12),

            // نص الإشعار
            if (humanBody.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  humanBody,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.6,
                    color: scheme.onSurface,
                  ),
                ),
              ),

            // تفاصيل إضافية إن وُجدت
            if (amount != null ||
                lateMinutes != null ||
                workDate != null ||
                time != null ||
                employeeName != null ||
                reason != null ||
                requestType != null) ...[
              const SizedBox(height: 16),
              Text(
                'بيانات مرتبطة',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (amount != null)
                    _DetailChip(
                      icon: Icons.payments_outlined,
                      label: 'المبلغ: $amount ج.م',
                      color: scheme.error,
                    ),
                  if (lateMinutes != null)
                    _DetailChip(
                      icon: Icons.timer_outlined,
                      label: 'تأخير: $lateMinutes دقيقة',
                      color: Colors.orange.shade800,
                    ),
                  if (workDate != null)
                    _DetailChip(
                      icon: Icons.calendar_today_outlined,
                      label: 'تاريخ الدوام: $workDate',
                      color: scheme.primary,
                    ),
                  if (time != null)
                    _DetailChip(
                      icon: Icons.access_time_rounded,
                      label: 'التوقيت: $time',
                      color: scheme.secondary,
                    ),
                  if (employeeName != null)
                    _DetailChip(
                      icon: Icons.person_outline_rounded,
                      label: 'الموظف: $employeeName',
                      color: scheme.primary,
                    ),
                  if (reason != null && reason.isNotEmpty)
                    _DetailChip(
                      icon: Icons.info_outline,
                      label: 'السبب: $reason',
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // أزرار الإجراء
            Row(
              children: [
                if (isAttendance)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MobileAttendanceServicesPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.co_present_outlined),
                      label: const Text('سجل الحضور'),
                    ),
                  )
                else if (isPenalty)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyInstantPenaltiesPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('سجل الغرامات'),
                    ),
                  )
                else if (isRequest)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MobileRequestsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.assignment_outlined),
                      label: const Text('عرض الطلبات'),
                    ),
                  )
                else if (isTask)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MobileTasksPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.task_alt_outlined),
                      label: const Text('عرض المهام'),
                    ),
                  )
                else
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('حسناً'),
                    ),
                  ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
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
