import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileKpiPage extends ConsumerStatefulWidget {
  const MobileKpiPage({required this.access, super.key});

  final AccessContext access;

  @override
  ConsumerState<MobileKpiPage> createState() => _MobileKpiPageState();
}

class _MobileKpiPageState extends ConsumerState<MobileKpiPage> {
  final _searchController = TextEditingController();
  String _search = '';
  String _stage = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final evaluations = ref.watch(mobileKpiProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileKpiProvider),
      child: evaluations.when(
        loading: () => ListView(
          children: [
            const SizedBox(height: 250),
            const Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.error,
              semanticLabel: 'خطأ',
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                humanizeError(error),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () => ref.invalidate(mobileKpiProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ),
          ],
        ),
        data: (items) {
          final visible = items.where(_matches).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              MobileFilterBar(
                searchHint: 'بحث باسم الموظف أو الكود',
                controller: _searchController,
                onSearchChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                /// V17 §10: flow order is self → hr_review → manager_review → finalized.
                /// manager_final removed from active flow (kept in DB for history).
                options: const [
                  MobileFilterOption('all', 'كل المراحل'),
                  MobileFilterOption('self', 'الموظف'),
                  MobileFilterOption('hr_review', 'مراجعة HR'),
                  MobileFilterOption('manager_review', 'مراجعة المدير'),
                  MobileFilterOption('finalized', 'في التقرير'),
                  MobileFilterOption('closed', 'مغلق'),
                  MobileFilterOption('archived', 'مؤرشف'),
                ],
                selected: _stage,
                onSelected: (value) => setState(() => _stage = value),
                resultLabel: '${visible.length} من ${items.length} تقييم',
                onClear: _search.isEmpty && _stage == 'all'
                    ? null
                    : () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _stage = 'all';
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty) ...[
                const SizedBox(height: 100),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 48,
                      semanticLabel: 'لا توجد نتائج',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'لا توجد تقييمات مطابقة للفلاتر',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ] else
                ...visible.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _KpiCard(item: item, access: widget.access),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  bool _matches(MobileKpiEvaluation item) {
    final haystack = '${item.employeeName} ${item.employeeCode ?? ''}'
        .toLowerCase();
    return (_search.isEmpty || haystack.contains(_search)) &&
        (_stage == 'all' || item.currentStage == _stage);
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.item, required this.access});

  final MobileKpiEvaluation item;
  final AccessContext access;

  @override
  Widget build(BuildContext context) {
    final action = _allowedAction();
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MobileStatusPill(item.currentStage),
                  const Spacer(),
                  Text(DateFormat('MMMM y', 'ar').format(item.periodMonth)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  AppAvatar(
                    name: item.employeeName,
                    photoUrl: item.employeePhotoUrl,
                    radius: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.employeeName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          item.employeeCode ?? 'بدون كود',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                kpiWorkflowLabel(item.workflowStatus),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Info(
                      label: 'النتيجة',
                      value: item.finalScore?.toStringAsFixed(1) ?? '—',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _Info(
                      label: 'التقدير',
                      value: item.finalRating ?? '—',
                    ),
                  ),
                ],
              ),
              if (action != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    action == 'self'
                        ? 'بدء التقييم الذاتي'
                        : action == 'hr_review'
                            ? 'مراجعة HR'
                            : 'فتح نموذج المراجعة',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KpiEvaluationDetailPage(evaluationId: item.id),
      ),
    );
  }

  String? _allowedAction() {
    if (item.currentStage == 'self' &&
        access.hasPermission('performance.kpi.self_assess')) {
      return 'self';
    }
    if (item.currentStage == 'hr_review' &&
        access.hasPermission('performance.kpi.hr_assess')) {
      return 'hr_review';
    }
    if (item.currentStage == 'manager_review' &&
        access.hasPermission('performance.kpi.manager_assess')) {
      return 'manager_review';
    }
    return null;
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}
