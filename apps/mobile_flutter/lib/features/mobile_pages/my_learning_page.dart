import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة «التعلم والتدريب» — دوراتي المسجَّلة مع التقدم والدرجة (0033).
class MyLearningPage extends ConsumerStatefulWidget {
  const MyLearningPage({super.key});

  @override
  ConsumerState<MyLearningPage> createState() => _MyLearningPageState();
}

class _MyLearningPageState extends ConsumerState<MyLearningPage> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final courses = ref.watch(myLearningCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('التعلم والتدريب')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myLearningCatalogProvider),
        child: courses.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 220),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(myLearningCatalogProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (catalog) {
            final items = catalog.items;
            final filtered = switch (_filter) {
              'active' =>
                items
                    .where(
                      (c) =>
                          c.status == 'enrolled' || c.status == 'in_progress',
                    )
                    .toList(),
              'completed' =>
                items.where((c) => c.status == 'completed').toList(),
              _ => items,
            };
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      for (final entry in const [
                        ('all', 'الكل'),
                        ('active', 'جارية'),
                        ('completed', 'مكتملة'),
                      ])
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ChoiceChip(
                            label: Text(entry.$2),
                            selected: _filter == entry.$1,
                            onSelected: (_) =>
                                setState(() => _filter = entry.$1),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${filtered.length} من ${items.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 140),
                            Icon(
                              Icons.school_outlined,
                              size: 54,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            const Center(
                              child: Text(
                                'لا توجد دورات في هذا التصنيف',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _CourseCard(course: filtered[index]),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({required this.course});
  final MobileLearningItem course;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                MobileStatusPill(course.status),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (course.mandatory)
                  _chip(
                    'إجبارية',
                    AppColors.statusDanger.withValues(alpha: .12),
                    AppColors.statusDanger,
                  ),
                if (course.category.isNotEmpty)
                  _chip(
                    course.category,
                    scheme.surfaceContainerHighest,
                    scheme.onSurface,
                  ),
                if (course.deliveryMode == 'online')
                  _chip(
                    'عن بُعد',
                    scheme.primaryContainer,
                    scheme.onPrimaryContainer,
                  ),
                if (course.durationMinutes > 0)
                  _chip(
                    '${course.durationMinutes} دقيقة',
                    scheme.surfaceContainerHighest,
                    scheme.onSurface,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: course.progress / 100,
                      minHeight: 8,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${course.progress}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (course.score != null) ...[
                  Icon(
                    Icons.grade_outlined,
                    size: 14,
                    color: AppColors.statusSuccess,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'الدرجة: ${course.score!.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (course.completedAt != null)
                  Text(
                    'أُكملت ${DateFormat('d MMM y', 'ar').format(course.completedAt!.toLocal())}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else if (course.expiresAt != null)
                  Text(
                    'تنتهي ${DateFormat('d MMM y', 'ar').format(course.expiresAt!.toLocal())}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}
