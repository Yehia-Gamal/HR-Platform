import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_router.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileActionInboxPage extends ConsumerWidget {
  const MobileActionInboxPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(mobileActionCenterProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileActionCenterProvider),
      child: actions.when(
        loading: () => ListView(
          children: [
            const SizedBox(height: 240),
            const Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(mobileActionCenterProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: (items) => items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 180),
                  Center(
                    child: Icon(
                      Icons.inbox_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      semanticLabel: 'لا توجد إجراءات',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Center(child: Text('لا توجد إجراءات معلقة')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _ActionCard(
                  item: items[index],
                  onOpen: () => _open(context, ref, items[index]),
                ),
              ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    MobileActionItem item,
  ) async {
    try {
      final target = await ref.read(mobileCommandsProvider).resolveAction(item);
      if (!context.mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => mobilePageForActionTarget(target)),
      );
      ref.invalidate(mobileActionCenterProvider);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.item, required this.onOpen});

  final MobileActionItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOverdue =
        item.dueAt != null && item.dueAt!.isBefore(DateTime.now());
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Semantics(
          label: item.kind,
          child: CircleAvatar(child: Icon(_icon(item.kind))),
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.subtitle != null) Text(item.subtitle!),
            const SizedBox(height: 6),
            Row(
              children: [
                MobileStatusPill(item.priority),
                if (item.dueAt != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'المهلة ${DateFormat('d MMM - h:mm a', 'ar').format(item.dueAt!.toLocal())}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isOverdue ? scheme.error : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Tooltip(
          message: 'فتح الإجراء',
          child: const Icon(Icons.chevron_left),
        ),
        onTap: onOpen,
      ),
    );
  }

  static IconData _icon(String kind) => switch (kind) {
    'request' => Icons.approval_outlined,
    'kpi' => Icons.speed,
    'decision' => Icons.gavel_outlined,
    'case' => Icons.balance_outlined,
    _ => Icons.task_alt,
  };
}
