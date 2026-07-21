import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class MobileServicePortalPage extends ConsumerStatefulWidget {
  const MobileServicePortalPage({super.key});

  @override
  ConsumerState<MobileServicePortalPage> createState() =>
      _MobileServicePortalPageState();
}

class _MobileServicePortalPageState
    extends ConsumerState<MobileServicePortalPage> {
  final _searchController = TextEditingController();
  String _search = '';
  String _status = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(MobileServiceRequest item) {
    final matchesSearch =
        _search.isEmpty ||
        item.title.toLowerCase().contains(_search) ||
        item.serviceName.toLowerCase().contains(_search) ||
        '${item.number}'.contains(_search);
    return matchesSearch && (_status == 'all' || item.status == _status);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(myServicePortalProvider);
    final catalog = query.value?.catalog ?? const <MobileServiceCatalogItem>[];

    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8),
          child: BrandLogoMark(size: 32),
        ),
        title: const Text('الخدمات الداخلية'),
      ),
      floatingActionButton: catalog.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openRequestDialog(context, ref, catalog),
              icon: const Icon(Icons.add),
              label: const Text('طلب خدمة'),
            ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myServicePortalProvider),
        child: query.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              Padding(
                padding: EdgeInsets.only(top: 120),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        humanizeError(error),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.invalidate(myServicePortalProvider),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (data) {
            final openCount = data.requests
                .where(
                  (item) => !const [
                    'resolved',
                    'closed',
                    'cancelled',
                  ].contains(item.status),
                )
                .length;

            final filtered = data.requests.where(_matches).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                MetricGrid(
                  cards: [
                    (
                      'الخدمات',
                      '${data.catalog.length}',
                      Icons.support_agent_outlined,
                      null,
                    ),
                    (
                      'طلباتي',
                      '${data.requests.length}',
                      Icons.list_alt_outlined,
                      null,
                    ),
                    ('مفتوحة', '$openCount', Icons.pending_actions_outlined, null),
                  ],
                ),
                const SizedBox(height: 12),
                if (data.requests.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.support_agent_outlined,
                            size: 44,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'لا توجد طلبات خدمة حتى الآن.',
                            textAlign: TextAlign.center,
                          ),
                          if (catalog.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: () =>
                                  _openRequestDialog(context, ref, catalog),
                              icon: const Icon(Icons.add),
                              label: const Text('طلب خدمة'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                else ...[
                  MobileFilterBar(
                    searchHint: 'بحث بالعنوان أو الخدمة أو رقم الطلب',
                    controller: _searchController,
                    onSearchChanged: (value) =>
                        setState(() => _search = value.trim().toLowerCase()),
                    options: const [
                      MobileFilterOption('all', 'الكل'),
                      MobileFilterOption('submitted', 'مقدم'),
                      MobileFilterOption('in_progress', 'قيد التنفيذ'),
                      MobileFilterOption('waiting_requester', 'بانتظارك'),
                      MobileFilterOption('resolved', 'تم الحل'),
                      MobileFilterOption('closed', 'مغلق'),
                    ],
                    selected: _status,
                    onSelected: (value) => setState(() => _status = value),
                    resultLabel:
                        '${filtered.length} من ${data.requests.length} طلب',
                    onClear: _search.isEmpty && _status == 'all'
                        ? null
                        : () {
                            _searchController.clear();
                            setState(() {
                              _search = '';
                              _status = 'all';
                            });
                          },
                  ),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 44,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'لا توجد طلبات مطابقة للبحث.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...filtered.map(
                      (item) => Card(
                        child: ListTile(
                          leading: Semantics(
                            label: 'طلب خدمة',
                            child: const Icon(Icons.support_agent_outlined),
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.serviceName} · #${item.number}',
                          ),
                          trailing: MobileStatusPill(item.status),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  static Future<void> _openRequestDialog(
    BuildContext context,
    WidgetRef ref,
    List<MobileServiceCatalogItem> items,
  ) async {
    var serviceId = items.first.id;
    var title = '';
    var description = '';
    var priority = 'normal';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('طلب خدمة'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: serviceId,
                      items: items
                          .map(
                            (item) => DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() => serviceId = value ?? serviceId);
                      },
                      decoration: const InputDecoration(labelText: 'الخدمة'),
                    ),
                    TextField(
                      onChanged: (value) => title = value,
                      decoration: const InputDecoration(labelText: 'العنوان'),
                    ),
                    TextField(
                      onChanged: (value) => description = value,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'التفاصيل'),
                    ),
                    DropdownButtonFormField<String>(
                      value: priority,
                      items: const [
                        DropdownMenuItem(value: 'normal', child: Text('عادي')),
                        DropdownMenuItem(value: 'high', child: Text('مهم')),
                        DropdownMenuItem(value: 'urgent', child: Text('عاجل')),
                      ],
                      onChanged: (value) {
                        priority = value ?? priority;
                      },
                      decoration: const InputDecoration(labelText: 'الأولوية'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (title.trim().isEmpty) return;
                    await ref
                        .read(mobileCommandsProvider)
                        .submitServiceRequest(
                          catalogItemId: serviceId,
                          title: title,
                          description: description,
                          priority: priority,
                        );
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('إرسال'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
