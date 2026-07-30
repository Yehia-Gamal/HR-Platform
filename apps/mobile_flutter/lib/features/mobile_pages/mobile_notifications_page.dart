import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_feed_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileNotificationsPage extends ConsumerStatefulWidget {
  const MobileNotificationsPage({super.key});

  @override
  ConsumerState<MobileNotificationsPage> createState() =>
      _MobileNotificationsPageState();
}

class _MobileNotificationsPageState
    extends ConsumerState<MobileNotificationsPage> {
  @override
  Widget build(BuildContext context) {
    final notifications = ref.watch(myNotificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myNotificationsProvider),
          child: notifications.when(
            loading: () => ListView(
              children: [
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
                          child: Text('تعذر تحميل الإشعارات. اسحب لأسفل لإعادة المحاولة.'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            data: (items) => items.isEmpty
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
                                'لا توجد إشعارات حاليًا',
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _NotificationCard(
                      item: items[index],
                      onTap: () => _open(items[index]),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(MobileNotificationItem item) async {
    if (!item.hasSupportedAction) return;
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

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onTap});

  final MobileNotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('d MMM، h:mm a', 'ar');
    return Card(
      child: Semantics(
        label: item.isRead ? null : 'إشعار غير مقروء',
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(child: Icon(_icon(item.category))),
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
              if (item.priority != 'normal') ...[
                const SizedBox(height: 6),
                MobileStatusPill(item.priority),
              ],
              if (item.body != null && item.body!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(item.body!, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 7),
              Text(
                formatter.format(item.createdAt.toLocal()),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          trailing: item.hasSupportedAction
              ? const Icon(Icons.chevron_left_rounded)
              : null,
          onTap: item.hasSupportedAction ? onTap : null,
        ),
      ),
    );
  }

  IconData _icon(String category) => switch (category) {
    'request' => Icons.approval_outlined,
    'decision' => Icons.gavel_outlined,
    'announcement' => Icons.campaign_outlined,
    'dispute' => Icons.balance_outlined,
    'system' => Icons.settings_suggest_outlined,
    'recognition' => Icons.workspace_premium_outlined,
    _ => Icons.notifications_outlined,
  };
}
