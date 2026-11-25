part of '../my_instant_penalties_page.dart';

enum _TeamFilter {
  all('الكل'),
  unpaid('غير مسددة'),
  excuses('أعذار للمراجعة'),
  paid('مسددة'),
  cancelled('ملغاة ومعفاة');

  const _TeamFilter(this.label);
  final String label;

  bool matches(MobileInstantPenalty p) => switch (this) {
    _TeamFilter.all => true,
    _TeamFilter.unpaid => _isUnpaid(p.status),
    _TeamFilter.excuses => p.excuseStatus == 'submitted' && _isUnpaid(p.status),
    _TeamFilter.paid => p.status == 'paid',
    _TeamFilter.cancelled => p.status == 'cancelled',
  };
}

/// الفترة حسب يوم الغرامة.
enum _Period {
  thisMonth('هذا الشهر'),
  lastMonth('الشهر الماضي'),
  all('كل الفترات');

  const _Period(this.label);
  final String label;

  bool contains(MobileInstantPenalty p) {
    if (this == _Period.all) return true;
    final d = DateTime.tryParse(p.workDate);
    if (d == null) return false;
    final now = DateTime.now();
    final start = this == _Period.thisMonth
        ? DateTime(now.year, now.month)
        : DateTime(now.year, now.month - 1);
    final end = DateTime(start.year, start.month + 1);
    return !d.isBefore(start) && d.isBefore(end);
  }
}

class _TeamPenaltiesTab extends ConsumerStatefulWidget {
  const _TeamPenaltiesTab();

  @override
  ConsumerState<_TeamPenaltiesTab> createState() => _TeamPenaltiesTabState();
}

class _TeamPenaltiesTabState extends ConsumerState<_TeamPenaltiesTab> {
  final _search = TextEditingController();
  String _query = '';
  _TeamFilter _filter = _TeamFilter.unpaid;
  _Period _period = _Period.all;
  final _expanded = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(teamInstantPenaltiesProvider);
    final manage = canManagePenalties(ref);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamInstantPenaltiesProvider),
      child: data.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(teamInstantPenaltiesProvider),
        ),
        data: (everything) {
          // الأرقام والقائمة للفترة المختارة
          final all = everything.where(_period.contains).toList();
          final excusesWaiting = all
              .where(
                (p) => p.excuseStatus == 'submitted' && _isUnpaid(p.status),
              )
              .length;
          final unpaidAll = all.where((p) => _isUnpaid(p.status));
          final dueTotal = unpaidAll.fold<double>(
            0,
            (s, p) => s + p.currentAmount,
          );
          final dueEmployees = {for (final p in unpaidAll) p.employeeId}.length;
          final paidTotal = all
              .where((p) => p.status == 'paid')
              .fold<double>(0, (s, p) => s + p.currentAmount);

          // التجميع بالموظف بعد التصفية
          final groups = <String, List<MobileInstantPenalty>>{};
          for (final p in all.where(_filter.matches)) {
            final hay = '${p.employeeName ?? ''} ${p.departmentName ?? ''}'
                .toLowerCase();
            if (_query.isNotEmpty && !hay.contains(_query)) continue;
            groups
                .putIfAbsent(p.employeeId ?? p.employeeName ?? '-', () => [])
                .add(p);
          }
          double due(List<MobileInstantPenalty> l) => l
              .where((p) => _isUnpaid(p.status))
              .fold<double>(0, (s, p) => s + p.currentAmount);
          final ordered = groups.entries.toList()
            ..sort((a, b) {
              final d = due(b.value).compareTo(due(a.value));
              if (d != 0) return d;
              return (a.value.first.employeeName ?? '').compareTo(
                b.value.first.employeeName ?? '',
              );
            });

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _CountTile(
                        label: 'غير مسدد',
                        count: unpaidAll.length,
                        amount: dueTotal,
                        color: AppColors.statusWarning,
                      ),
                      const SizedBox(width: 8),
                      _CountTile(
                        label: 'موظفون عليهم مستحقات',
                        count: dueEmployees,
                        color: AppColors.statusDanger,
                      ),
                      const SizedBox(width: 8),
                      _CountTile(
                        label: 'مسدد للصندوق',
                        count: all.where((p) => p.status == 'paid').length,
                        amount: paidTotal,
                        color: AppColors.statusSuccess,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Card(
                color: theme.colorScheme.primaryContainer.withValues(alpha: .2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: .25),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_rounded,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'سجل الانضباط الشفاف: جميع غرامات التأخير تُورّد بالكامل لصندوق الزمالة والتكافل لدعم الزملاء.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الموظف أو الإدارة…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: .5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Period>(
                showSelectedIcon: false,
                segments: [
                  for (final per in _Period.values)
                    ButtonSegment(value: per, label: Text(per.label)),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _TeamFilter.values)
                    if (f != _TeamFilter.excuses || excusesWaiting > 0)
                      ChoiceChip(
                        label: Text(
                          f == _TeamFilter.excuses
                              ? '${f.label} ($excusesWaiting)'
                              : f.label,
                        ),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              if (ordered.isEmpty)
                const _EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'لا توجد غرامات مطابقة',
                  subtitle: 'غيّر التصفية أو البحث.',
                )
              else
                for (final g in ordered) ...[
                  _EmployeeGroupCard(
                    penalties: g.value,
                    manage: manage,
                    expanded: _expanded.contains(g.key),
                    onToggle: () => setState(() {
                      if (!_expanded.remove(g.key)) _expanded.add(g.key);
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeGroupCard extends StatelessWidget {
  const _EmployeeGroupCard({
    required this.penalties,
    required this.expanded,
    required this.onToggle,
    this.manage = false,
  });

  final List<MobileInstantPenalty> penalties;
  final bool expanded;
  final VoidCallback onToggle;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = penalties.first;
    final name = first.employeeName ?? 'موظف';
    final unpaid = penalties.where((p) => _isUnpaid(p.status));
    final due = unpaid.fold<double>(0, (s, p) => s + p.currentAmount);
    final paid = penalties.where((p) => p.status == 'paid').length;
    final cancelled = penalties.where((p) => p.status == 'cancelled').length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AppAvatar(name: name, photoUrl: first.photoUrl, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (first.departmentName?.isNotEmpty ?? false)
                          Text(
                            first.departmentName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (penalties.any(
                              (p) =>
                                  p.status == 'suspended' ||
                                  p.escalationLevel == 'suspended',
                            ))
                              const _Pill(
                                text: 'موقوف عن العمل',
                                color: AppColors.statusDanger,
                              )
                            else if (penalties.any(
                              (p) =>
                                  p.currentAmount >= 500 ||
                                  p.escalationLevel == 'doubled',
                            ))
                              const _Pill(
                                text: 'مضاعفة 500 ج.م',
                                color: AppColors.statusWarning,
                              ),
                            if (unpaid.isNotEmpty)
                              _Pill(
                                text: 'مستحق ${_money(due)} (${unpaid.length})',
                                color: AppColors.statusWarning,
                              ),
                            if (paid > 0)
                              _Pill(
                                text: 'مسددة: $paid',
                                color: AppColors.statusSuccess,
                              ),
                            if (cancelled > 0)
                              _Pill(
                                text: 'ملغاة: $cancelled',
                                color: const Color(0xFF64748B),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (final p in penalties) ...[
                    _PenaltyCard(item: p, manage: manage),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// الموظفون الموقوفون عن العمل
// ═══════════════════════════════════════════════════════════════════════════

