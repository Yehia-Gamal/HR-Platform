import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileTasksPage extends ConsumerWidget {
  const MobileTasksPage({this.highlightId, super.key});
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(mobileTasksProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileTasksProvider),
      child: tasks.when(
        loading: () => ListView(
          children: [
            const SizedBox(height: 220),
            const Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
          ],
        ),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 140),
            Icon(
              Icons.error_outline,
              size: 54,
              color: Theme.of(context).colorScheme.error,
              semanticLabel: 'خطأ',
            ),
            const SizedBox(height: 12),
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton(
                onPressed: () => ref.invalidate(mobileTasksProvider),
                child: const Text('إعادة المحاولة'),
              ),
            ),
          ],
        ),
        data: (items) => items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 180),
                  Center(
                    child: Icon(
                      Icons.task_alt,
                      size: 54,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      semanticLabel: 'لا توجد مهام',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      'لا توجد مهام مسندة إليك حاليًا',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _TaskCard(
                  item: items[index],
                  isHighlighted: items[index].id == highlightId,
                ),
              ),
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.item, this.isHighlighted = false});
  final MobileTask item;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: isHighlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      color: isHighlighted ? scheme.primaryContainer.withValues(alpha: .15) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _PriorityPill(priority: item.priority),
                if (item.sourceType == 'onboarding') ...[
                  const SizedBox(width: 8),
                  const _SourcePill(),
                ],
                const Spacer(),
                if (item.isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'متأخرة',
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            if (item.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(item.description!),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (item.dueDate != null)
                  _Meta(
                    icon: Icons.event_outlined,
                    text:
                        'الاستحقاق ${DateFormat('d MMM y', 'ar').format(item.dueDate!)}',
                  ),
                if (item.createdByName != null)
                  _Meta(
                    icon: Icons.person_outline,
                    text: 'بواسطة ${item.createdByName}',
                  ),
              ],
            ),
            const Divider(height: 26),
            if (item.status == 'cancelled')
              Row(
                children: [
                  const MobileStatusPill('cancelled'),
                  const SizedBox(width: 8),
                  Text(
                    'لا يمكن تغيير حالة مهمة ملغاة',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            else
              Semantics(
                label: 'حالة المهمة',
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'pending',
                      label: Text('لم تبدأ'),
                      icon: Icon(Icons.schedule),
                    ),
                    ButtonSegment(
                      value: 'in_progress',
                      label: Text('جارية'),
                      icon: Icon(Icons.play_arrow),
                    ),
                    ButtonSegment(
                      value: 'done',
                      label: Text('مكتملة'),
                      icon: Icon(Icons.check),
                    ),
                  ],
                  selected: {item.status},
                  onSelectionChanged: (selection) =>
                      _transition(context, ref, selection.first),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _transition(
    BuildContext context,
    WidgetRef ref,
    String status,
  ) async {
    if (status == item.status) return;
    try {
      await ref.read(mobileCommandsProvider).transitionTask(item.id, status);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تحديث حالة المهمة.')));
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

class _SourcePill extends StatelessWidget {
  const _SourcePill();
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        'Onboarding',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});
  final String priority;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (priority) {
      'urgent' => ('عاجلة', const Color(0xFFDC3D4B)),
      'high' => ('مرتفعة', const Color(0xFFD98508)),
      'low' => ('منخفضة', scheme.onSurfaceVariant),
      _ => ('متوسطة', const Color(0xFFD98508)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}
