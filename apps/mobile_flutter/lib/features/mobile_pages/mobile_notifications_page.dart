import 'dart:async';

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/notifications/notification_handler.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_project_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_daily_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/notification_settings_page.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
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

  Future<void> _confirmDeleteAll() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح جميع الإشعارات'),
        content: const Text(
          'سيتم مسح جميع الإشعارات نهائياً من حسابك وتفريغ الصندوق بالكامل. لا يمكن التراجع عن هذا الإجراء.',
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
            child: const Text('مسح الكل'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(mobileCommandsProvider).deleteNotifications();
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selectedIds.clear();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('تم مسح جميع الإشعارات بنجاح')),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر مسح الإشعارات. أعد المحاولة.')),
      );
    }
  }

  /// بناء القائمة الفردية الكاملة — كل إشعار يظهر بشكل مستقل ومضغوط
  Widget _buildNotificationList(
    List<MobileNotificationItem> visible, {
    required bool hasMore,
    required int totalLoaded,
  }) {
    // صفوف القائمة: عنوان اليوم ثم إشعاراته (القائمة مرتبة الأحدث أولًا)
    final rows = <Object>[];
    String? lastDay;
    for (final item in visible) {
      final day = _notificationDayLabel(item.createdAt);
      if (day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      rows.add(item);
    }
    final count = rows.length + (hasMore ? 1 : 0);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index == rows.length && hasMore) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  ref.read(notificationsLimitProvider.notifier).loadMore(300);
                },
                icon: const Icon(Icons.history_rounded, size: 20),
                label: Text(
                  'تحميل المزيد من الإشعارات السابقة ($totalLoaded+)',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          );
        }
        final row = rows[index];
        if (row is String) return _DayHeader(label: row, first: index == 0);
        final item = row as MobileNotificationItem;
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
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(14),
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
    final currentLimit = ref.watch(notificationsLimitProvider);
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
    final hasMore = items.length >= currentLimit;

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
            PopupMenuButton<String>(
              tooltip: 'خيارات إضافية',
              onSelected: (val) {
                if (val == 'clear_all') {
                  _confirmDeleteAll();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'مسح جميع الإشعارات',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                              : _buildNotificationList(
                                  visible,
                                  hasMore: hasMore,
                                  totalLoaded: items.length,
                                ),
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

    // 2. فحص إشعارات الحضور والانصراف بدقة
    final currentEmpId = ref.read(accessContextProvider).value?.employeeId;
    final targetEmpId = item.meta('employeeId') ??
        (item.entityType == 'late_attendance_alert' ? item.entityId : null);
    final empName = item.meta('employeeName') ?? item.meta('employee_name');
    final workDate = item.meta('workDate');
    final rawType = (item.entityType ?? '').toLowerCase();
    final canonical = item.canonicalType ?? rawType;
    final isAttendanceEvent = canonical == 'attendance' ||
        rawType.contains('attendance') ||
        rawType == 'punch_reminder' ||
        rawType == 'late_attendance_alert' ||
        item.category == 'attendance' ||
        item.category == 'attendance_manager_notify';

    // أ) إذا كان الإشعار يخص موظفاً تابعاً (للمدير أو المسؤول) -> افتح بروفايل الموظف مباشرة لرؤية حالته اليوم وتفاصيل دوامه
    if (isAttendanceEvent &&
        targetEmpId != null &&
        targetEmpId.isNotEmpty &&
        targetEmpId != currentEmpId) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmployeeProfilePage(
            employeeId: targetEmpId,
            employeeName: empName,
          ),
        ),
      );
      return;
    }

    // ب) إذا كانت غرامة تخص موظفاً تابعاً للمدير: فتح ورقة التفاصيل الذكية لرؤية تفاصيل الغرامة ومبلغها وزر الانتقال لملف الموظف
    if (canonical == 'instant_penalty' &&
        targetEmpId != null &&
        targetEmpId.isNotEmpty &&
        targetEmpId != currentEmpId) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => NotificationDetailSheet(item: item),
      );
      return;
    }

    // ج) إذا كان للإشعار رابط عميق صريح (deepLink أو actionUrl)
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

    // د) إذا كان الإشعار يخص المستخدم نفسه (تسجيل حضوره أو انصرافه أو تذكير بالبصمة) -> افتح سجله للحضور اليومي
    if (isAttendanceEvent) {
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

/// بطاقة إشعار: أيقونة ملوّنة بالفئة، العنوان والساعة، ثم النص على سطرين —
/// اليوم صار عنوان مجموعة فلا يتكرر «اليوم ·» في كل بطاقة.
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
    final unread = !item.isRead && !localRead;
    final humanizedBody = _humanizeNotificationBody(item.body);
    final color = _notificationColor(item.category, scheme);
    final muted = scheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: unread
            ? scheme.primary.withValues(alpha: 0.06)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? scheme.error.withValues(alpha: .6)
              : unread
              ? scheme.primary.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: selecting ? onToggleSelect : onTap,
          onLongPress: selecting ? null : onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selecting)
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => onToggleSelect?.call(),
                      activeColor: scheme.error,
                    ),
                  )
                else
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: unread ? .16 : .09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _notificationIcon(item.category),
                      size: 20,
                      color: unread ? color : color.withValues(alpha: .75),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: unread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: unread ? scheme.onSurface : muted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_notificationCategoryLabel(item.category)} · '
                            '${_notificationClock(item.createdAt)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: muted.withValues(alpha: .85),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (humanizedBody.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          humanizedBody,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: unread
                                ? scheme.onSurface.withValues(alpha: 0.85)
                                : muted.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// عنوان مجموعة اليوم في قائمة الإشعارات.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, this.first = false});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 4 : 14, 4, 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: .4),
            ),
          ),
        ],
      ),
    );
  }
}

/// لون الفئة — يميّز الحضور عن الطلبات عن القرارات بنظرة.
Color _notificationColor(String category, ColorScheme scheme) =>
    switch (category) {
      'request' => scheme.primary,
      'decision' || 'survey' => AppColors.statusViolet,
      'announcement' => AppColors.accent,
      'dispute' || 'security' => AppColors.statusDanger,
      'recognition' => const Color(0xFFD4A017),
      'kpi' || 'documents' || 'service' || 'device' => AppColors.statusInfo,
      'attendance' ||
      'attendance_manager_notify' => AppColors.statusWarning,
      'location' || 'daily_report' => AppColors.statusSuccess,
      'wellbeing' || 'daily_report_like' => const Color(0xFFE5484D),
      'daily_report_comment' => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };

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

/// الساعة وحدها داخل البطاقة — اليوم في عنوان المجموعة.
String _notificationClock(DateTime time) =>
    DateFormat('h:mm a', 'ar').format(time.toLocal());

/// عنوان مجموعة: اليوم، أمس، اسم اليوم خلال الأسبوع، ثم التاريخ.
String _notificationDayLabel(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(DateTime(local.year, local.month, local.day)).inDays;
  if (diff == 0) return 'اليوم';
  if (diff == 1) return 'أمس';
  if (diff > 1 && diff < 7) return DateFormat('EEEE', 'ar').format(local);
  if (local.year == now.year) {
    return DateFormat('EEEE d MMMM', 'ar').format(local);
  }
  return DateFormat('d MMMM y', 'ar').format(local);
}

/// ورقة تفاصيل الإشعار الشاملة — تفتح فوراً عند النقر على أي إشعار للعلم أو إشعار عام
class NotificationDetailSheet extends ConsumerWidget {
  const NotificationDetailSheet({required this.item, super.key});

  final MobileNotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final urgent = item.priority == 'urgent' || item.priority == 'high';
    final humanBody = _humanizeNotificationBody(item.body);
    final meta = item.metadata;

    final currentEmpId = ref.read(accessContextProvider).value?.employeeId;
    final targetEmpId = item.meta('employeeId');
    final isSubordinate = targetEmpId != null &&
        targetEmpId.isNotEmpty &&
        targetEmpId != currentEmpId;

    final amount = meta['amount'] ?? meta['newAmount'];
    final lateMinutes = meta['lateMinutes'];
    final workDate = item.meta('workDate');
    final time = item.meta('time');
    final employeeName = item.meta('employeeName') ?? item.meta('employee_name');
    final reason = item.meta('reason');
    final requestType = item.meta('requestType');

    final isAttendance = item.canonicalType == 'attendance' ||
        (item.entityType ?? '').contains('attendance') ||
        item.category == 'attendance' ||
        item.category == 'attendance_manager_notify';
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
                            color: scheme.primary,
                          ),
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
                        if (isSubordinate) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmployeeProfilePage(
                                employeeId: targetEmpId,
                                employeeName: employeeName,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AttendanceHistoryPage(
                                highlightDate: workDate,
                              ),
                            ),
                          );
                        }
                      },
                      icon: Icon(isSubordinate
                          ? Icons.person_search_outlined
                          : Icons.co_present_outlined),
                      label: Text(isSubordinate
                          ? 'عرض حالة وملف الموظف'
                          : 'سجل الحضور'),
                    ),
                  )
                else if (isPenalty)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        if (isSubordinate) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmployeeProfilePage(
                                employeeId: targetEmpId,
                                employeeName: employeeName,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MyInstantPenaltiesPage(
                                highlightId: item.entityId,
                              ),
                            ),
                          );
                        }
                      },
                      icon: Icon(isSubordinate
                          ? Icons.person_search_outlined
                          : Icons.account_balance_wallet_outlined),
                      label: Text(isSubordinate
                          ? 'عرض ملف الموظف وحالته'
                          : 'سجل الغرامات'),
                    ),
                  )
                else if (isRequest)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        if (item.entityId != null && item.entityId!.isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MobileRequestDetailPage(
                                requestId: item.entityId!,
                              ),
                            ),
                          );
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MobileRequestsPage(),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.assignment_outlined),
                      label: const Text('عرض الطلب'),
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
