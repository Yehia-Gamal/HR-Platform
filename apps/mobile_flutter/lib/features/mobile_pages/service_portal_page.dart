import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// بوابة الخدمة (0035) — فتح تذاكر دعم ومتابعتها من الهاتف.
/// الفتح يتم عبر طابور المزامنة: انقطاع أثناء الإرسال = إرسال تلقائي لاحق.
class ServicePortalPage extends ConsumerWidget {
  const ServicePortalPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(myServicePortalProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الدعم الفني')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openNewRequestSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('طلب جديد'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myServicePortalProvider),
        child: portal.when(
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
                  onPressed: () => ref.invalidate(myServicePortalProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (data) {
            if (data.requests.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 140),
                  Icon(
                    Icons.support_agent_rounded,
                    size: 54,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'لا توجد تذاكر بعد',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'اضغط «طلب جديد» لفتح تذكرة دعم.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: data.requests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _TicketCard(item: data.requests[index]),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openNewRequestSheet(BuildContext context, WidgetRef ref) async {
    final portal = ref.read(myServicePortalProvider).asData?.value;
    final catalog = portal?.catalog ?? const <MobileServiceCatalogItem>[];
    if (catalog.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أنواع خدمة متاحة حالياً.')),
      );
      return;
    }

    var catalogItemId = catalog.first.id;
    final title = TextEditingController();
    final description = TextEditingController();
    var priority = 'normal';

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تذكرة دعم جديدة',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: catalogItemId,
                decoration: const InputDecoration(labelText: 'نوع الخدمة'),
                items: catalog
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setSheetState(
                  () => catalogItemId = value ?? catalog.first.id,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'الوصف',
                  hintText: 'اشرح المشكلة أو الطلب بوضوح',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final entry in const [
                    ('normal', 'عادية'),
                    ('high', 'عالية'),
                    ('urgent', 'عاجلة'),
                  ])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(entry.$2),
                        selected: priority == entry.$1,
                        onSelected: (_) =>
                            setSheetState(() => priority = entry.$1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().length < 3 ||
                      description.text.trim().length < 5) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'اكتب عنواناً ووصفاً واضحين قبل الإرسال.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, true);
                },
                child: const Text('إرسال التذكرة'),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) {
      title.dispose();
      description.dispose();
      return;
    }

    try {
      await ref
          .read(mobileCommandsProvider)
          .submitServiceRequest(
            catalogItemId: catalogItemId,
            title: title.text.trim(),
            description: description.text.trim(),
            priority: priority,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إرسال التذكرة ✓')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      title.dispose();
      description.dispose();
    }
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.item});
  final MobileServiceRequest item;

  String _statusLabel(String status) => switch (status) {
    'open' => 'مفتوحة',
    'in_progress' => 'قيد التنفيذ',
    'resolved' => 'تم حلها',
    'closed' => 'مغلقة',
    _ => status,
  };

  Color _statusColor(String status) => switch (status) {
    'open' => AppColors.statusWarning,
    'in_progress' => Colors.blue,
    'resolved' || 'closed' => AppColors.statusSuccess,
    _ => Colors.grey,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final due = item.dueAt;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MobileStatusPill(item.status),
                const SizedBox(width: 8),
                if (item.priority == 'urgent' || item.priority == 'high')
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.statusDanger.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      item.priority == 'urgent' ? 'عاجلة' : 'عالية',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.statusDanger,
                      ),
                    ),
                  ),
                const Spacer(),
                Text(
                  '#${item.number}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            if ((item.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                item.description ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    item.serviceName,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  DateFormat('d MMM', 'ar').format(item.createdAt.toLocal()),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (due != null && item.status != 'closed') ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 14,
                    color: due.isBefore(DateTime.now())
                        ? AppColors.statusDanger
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'الاستحقاق: ${DateFormat('d MMM، h:mm a', 'ar').format(due.toLocal())}',
                    style: TextStyle(
                      fontSize: 12,
                      color: due.isBefore(DateTime.now())
                          ? AppColors.statusDanger
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.circle, size: 8, color: _statusColor(item.status)),
                const SizedBox(width: 6),
                Text(
                  _statusLabel(item.status),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _statusColor(item.status),
                  ),
                ),
                const Spacer(),
                if (item.satisfactionScore != null)
                  Row(
                    children: [
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: Colors.amber,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${item.satisfactionScore}/5',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
