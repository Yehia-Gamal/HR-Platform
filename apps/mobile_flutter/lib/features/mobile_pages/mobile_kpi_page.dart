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
  const MobileKpiPage({required this.access, this.employeeOnly = false, super.key});

  final AccessContext access;

  /// عند true يعرض فقط تقييم الموظف الحالي (مساحة الموظف).
  final bool employeeOnly;

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
          // في مساحة الموظف: تصفية للتقييم الذاتي فقط.
          // حماية: إذا لم يكن للمستخدم employeeId مربوط، نعرض رسالة واضحة.
          if (widget.employeeOnly && widget.access.employeeId == null) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                const SizedBox(height: 100),
                Column(
                  children: [
                    Icon(
                      Icons.link_off_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'حسابك غير مربوط بملف موظف.\nتواصل مع الموارد البشرية لربط حسابك.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            );
          }
          final scoped = widget.employeeOnly
              ? items.where((e) => e.employeeId == widget.access.employeeId).toList(growable: false)
              : items;
          final visible = scoped.where(_matches).toList(growable: false);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
            children: [
              if (!widget.employeeOnly)
                MobileFilterBar(
                  searchHint: 'بحث باسم الموظف أو الكود',
                  controller: _searchController,
                  onSearchChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                  // V23: أضفنا مراحل المسار المتوازي (parallel_review, secretary_review, executive_review).
                  options: const [
                    MobileFilterOption('all', 'كل المراحل'),
                    MobileFilterOption('self', 'الموظف'),
                    MobileFilterOption('parallel_review', 'مراجعة متوازية'),
                    MobileFilterOption('hr_review', 'مراجعة HR'),
                    MobileFilterOption('manager_review', 'مراجعة المدير'),
                    MobileFilterOption('secretary_review', 'السكرتير'),
                    MobileFilterOption('executive_review', 'المدير التنفيذي'),
                    MobileFilterOption('finalized', 'في التقرير'),
                    MobileFilterOption('closed', 'مغلق'),
                    MobileFilterOption('archived', 'مؤرشف'),
                  ],
                  selected: _stage,
                  onSelected: (value) => setState(() => _stage = value),
                  resultLabel: '${visible.length} من ${scoped.length} تقييم',
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
              if (widget.employeeOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'تقييماتي',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (visible.isEmpty) ...[
                const SizedBox(height: 100),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      widget.employeeOnly
                          ? Icons.hourglass_empty_rounded
                          : Icons.search_off_rounded,
                      size: 48,
                      semanticLabel: 'لا توجد نتائج',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.employeeOnly
                          ? 'لا يوجد تقييم حالي لك'
                          : 'لا توجد تقييمات مطابقة للفلاتر',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ] else
                ...visible.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _KpiCard(
                      item: item,
                      access: widget.access,
                      employeeOnly: widget.employeeOnly,
                    ),
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
  const _KpiCard({
    required this.item,
    required this.access,
    this.employeeOnly = false,
  });

  final MobileKpiEvaluation item;
  final AccessContext access;
  final bool employeeOnly;

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
              // عرض الموعد النهائي إن وُجد.
              if (item.deadlineAt != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      item.deadlineAt!.isBefore(DateTime.now())
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      size: 14,
                      color: item.deadlineAt!.isBefore(DateTime.now())
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'الموعد النهائي: ${DateFormat.yMd('ar').format(item.deadlineAt!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: item.deadlineAt!.isBefore(DateTime.now())
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              // في مساحة الموظف لا داعي لعرض اسم الموظف — هو نفسه.
              if (!employeeOnly) ...[
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
                const SizedBox(height: 8),
              ],
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
              // في مساحة الموظف: رسالة توضيحية بعد إرسال التقييم الذاتي.
              if (employeeOnly && item.currentStage != 'self' && action == null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'تم تقديم تقييمك — ${kpiWorkflowLabel(item.workflowStatus)}',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _open(context),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_actionLabel(action)),
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

  // V23: تسميات أزرار الإجراء حسب المرحلة.
  String _actionLabel(String action) => switch (action) {
    'self' => 'بدء التقييم الذاتي',
    'hr_review' => 'مراجعة HR',
    'manager_review' => 'مراجعة المدير المباشر',
    'parallel_review' => 'مراجعة متوازية',
    'secretary_review' => 'مراجعة السكرتير',
    'executive_review' => 'إقرار المدير التنفيذي',
    _ => 'فتح نموذج المراجعة',
  };

  String? _allowedAction() {
    // التقييم الذاتي: يتطلب الصلاحية دائمًا + ملكية التقييم في مساحة الموظف.
    if (item.currentStage == 'self' &&
        access.hasPermission('performance.kpi.self_assess') &&
        (!employeeOnly || item.employeeId == access.employeeId)) {
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
    // V23: المراجعة المتوازية — HR أو المدير حسب الصلاحية.
    if (item.currentStage == 'parallel_review') {
      if (access.hasPermission('performance.kpi.hr_assess') ||
          access.hasPermission('performance.kpi.manager_assess')) {
        return 'parallel_review';
      }
    }
    // V23: مراحل السكرتير والمدير التنفيذي.
    if (item.currentStage == 'secretary_review' &&
        access.hasPermission('performance.kpi.secretary_review')) {
      return 'secretary_review';
    }
    if (item.currentStage == 'executive_review' &&
        access.hasPermission('performance.kpi.executive_review')) {
      return 'executive_review';
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
