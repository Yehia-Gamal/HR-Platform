import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileLearningPage extends ConsumerWidget {
  const MobileLearningPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(myLearningCatalogProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('تدريبي ومهاراتي')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myLearningCatalogProvider),
        child: catalog.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 120),
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(myLearningCatalogProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _Summary(items: data.items),
              const SizedBox(height: 12),
              if (data.items.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.school_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد دورات مسجلة حاليًا.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...data.items.map((item) => _LearningCard(item: item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.items});
  final List<MobileLearningItem> items;
  @override
  Widget build(BuildContext context) {
    final completed = items.where((item) => item.status == 'completed').length;
    final mandatory = items
        .where((item) => item.mandatory && item.status != 'completed')
        .length;
    return MetricGrid(
      cards: [
        ('الدورات', '${items.length}', Icons.school_rounded, null),
        ('مكتملة', '$completed', Icons.verified_rounded, null),
        ('إلزامية متبقية', '$mandatory', Icons.priority_high_rounded, null),
      ],
    );
  }
}

class _LearningCard extends ConsumerWidget {
  const _LearningCard({required this.item});
  final MobileLearningItem item;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (item.mandatory) const Chip(label: Text('إلزامية')),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${item.category} · ${item.durationMinutes} دقيقة · ${_mode(item.deliveryMode)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: item.progress / 100,
            minHeight: 8,
            borderRadius: BorderRadius.circular(99),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: Text('التقدم ${item.progress}%')),
              MobileStatusPill(item.status),
            ],
          ),
          if (item.score != null)
            Text('الدرجة ${item.score!.toStringAsFixed(1)}%'),
          if (item.status != 'completed') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (item.status == 'enrolled')
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => ref
                          .read(mobileCommandsProvider)
                          .transitionLearning(
                            item.id,
                            'in_progress',
                            progress: 10,
                          ),
                      child: const Text('بدء الدورة'),
                    ),
                  ),
                if (item.status == 'in_progress')
                  Expanded(
                    child: FilledButton(
                      onPressed: () => ref
                          .read(mobileCommandsProvider)
                          .transitionLearning(
                            item.id,
                            'completed',
                            progress: 100,
                          ),
                      child: const Text('إكمال الدورة'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
  String _mode(String value) => switch (value) {
    'onsite' => 'حضوري',
    'hybrid' => 'هجين',
    'self_paced' => 'ذاتي',
    _ => 'عن بعد',
  };
}
