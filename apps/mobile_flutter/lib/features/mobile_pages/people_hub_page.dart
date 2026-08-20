import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/org_chart_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// صفحة موحدة تجمع ثلاث صفحات منفصلة في مكان واحد:
/// ١. دليل الموظفين (بحث حي)
/// ٢. سجل الموظفين (قائمة كاملة مع فلتر الحالة)
/// ٣. الهيكل التنظيمي (شجرة تفاعلية)
class PeopleHubPage extends ConsumerStatefulWidget {
  const PeopleHubPage({super.key, this.initialTab = 0});

  /// التبويب الأولي عند فتح الصفحة
  final int initialTab;

  @override
  ConsumerState<PeopleHubPage> createState() => _PeopleHubPageState();
}

class _PeopleHubPageState extends ConsumerState<PeopleHubPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab,
    );
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفون والهيكل التنظيمي'),
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          indicator: BoxDecoration(
            color: scheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          tabs: const [
            Tab(icon: Icon(Icons.manage_search_rounded, size: 20), text: 'الدليل'),
            Tab(icon: Icon(Icons.badge_outlined, size: 20), text: 'السجل'),
            Tab(icon: Icon(Icons.account_tree_rounded, size: 20), text: 'الهيكل'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _DirectoryTab(),
          _EmployeeRegistryTab(),
          _OrgChartTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// التبويب ١ — دليل الموظفين (بحث حي)
// ════════════════════════════════════════════════════════

class _DirectoryTab extends ConsumerStatefulWidget {
  const _DirectoryTab();

  @override
  ConsumerState<_DirectoryTab> createState() => _DirectoryTabState();
}

class _DirectoryTabState extends ConsumerState<_DirectoryTab> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final results = ref.watch(employeeDirectoryProvider(_query));

    return Column(
      children: [
        // ── شريط البحث ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو الكود أو الإدارة…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        // ── المحتوى ──
        Expanded(
          child: results.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorRetry(
              message: humanizeError(e),
              onRetry: () => ref.invalidate(employeeDirectoryProvider(_query)),
            ),
            data: (items) {
              if (_query.isEmpty) {
                return _DirectoryEmptyPrompt(scheme: scheme);
              }
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_search_outlined,
                          size: 56,
                          color: scheme.onSurfaceVariant.withValues(alpha: .4)),
                      const SizedBox(height: 12),
                      Text(
                        'لا توجد نتائج مطابقة لـ "$_query"',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _DirectoryTile(employee: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DirectoryEmptyPrompt extends StatelessWidget {
  const _DirectoryEmptyPrompt({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_3_outlined,
              size: 72,
              color: scheme.primary.withValues(alpha: .25),
            ),
            const SizedBox(height: 16),
            Text(
              'ابحث عن أي موظف في المنظومة',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'بالاسم أو الكود أو الإدارة أو المسمى الوظيفي',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({required this.employee});
  final DirectoryEmployee employee;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [employee.jobTitle, employee.department]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');
    final isPresent = employee.statusToday == 'present';
    final isOnLeave = employee.statusToday == 'on_leave';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppAvatar(
          name: employee.name, photoUrl: employee.photoUrl, radius: 22),
      title: Text(employee.name,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: sub.isNotEmpty ? Text(sub) : null,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isPresent || isOnLeave)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isPresent
                        ? const Color(0xFF0F9F6E)
                        : scheme.primary)
                    .withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isPresent ? 'حاضر' : 'في إجازة',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isPresent
                      ? const Color(0xFF0F9F6E)
                      : scheme.primary,
                ),
              ),
            ),
          if (employee.employeeCode != null)
            Text(employee.employeeCode!,
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// التبويب ٢ — سجل الموظفين (قائمة كاملة مع فلتر الحالة)
// ════════════════════════════════════════════════════════

class _EmployeeRegistryTab extends ConsumerStatefulWidget {
  const _EmployeeRegistryTab();

  @override
  ConsumerState<_EmployeeRegistryTab> createState() =>
      _EmployeeRegistryTabState();
}

class _EmployeeRegistryTabState extends ConsumerState<_EmployeeRegistryTab> {
  final _search = TextEditingController();
  String _query = '';
  String _status = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employees =
        ref.watch(mobileEmployeesProvider((_query.trim(), _status)));

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(mobileEmployeesProvider((_query.trim(), _status))),
      child: employees.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            _ErrorRetry(
              message: humanizeError(e),
              onRetry: () => ref.invalidate(
                  mobileEmployeesProvider((_query.trim(), _status))),
            ),
          ],
        ),
        data: (data) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            MobileFilterBar(
              searchHint: 'بحث بالاسم أو كود الموظف',
              controller: _search,
              onSearchChanged: (v) => setState(() => _query = v),
              options: const [
                MobileFilterOption('all', 'الكل'),
                MobileFilterOption('active', 'نشط'),
                MobileFilterOption('onboarding', 'قيد التهيئة'),
                MobileFilterOption('invited', 'تمت الدعوة'),
                MobileFilterOption('notice_period', 'فترة إخطار'),
                MobileFilterOption('suspended', 'موقوف'),
                MobileFilterOption('terminated', 'منتهي'),
                MobileFilterOption('archived', 'مؤرشف'),
              ],
              selected: _status,
              onSelected: (v) => setState(() => _status = v),
              resultLabel:
                  data.isEmpty ? 'لا نتائج' : '${data.length} موظف',
            ),
            const SizedBox(height: 10),
            if (data.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child:
                    Center(child: Text('لا يوجد موظفون مطابقون')),
              )
            else
              ...data.map(
                (emp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _RegistryCard(
                    employee: emp,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EmployeeProfilePage(
                          employeeId: emp.id,
                          employeeName: emp.fullNameAr,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RegistryCard extends StatelessWidget {
  const _RegistryCard({required this.employee, required this.onTap});
  final MobileEmployeeSummary employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orgInfo = [
      if (employee.jobTitle?.isNotEmpty ?? false) employee.jobTitle!,
      if (employee.department?.isNotEmpty ?? false) employee.department!,
      if (employee.team?.isNotEmpty ?? false) employee.team!,
    ].join(' — ');

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              AppAvatar(
                  name: employee.fullNameAr,
                  photoUrl: employee.photoUrl,
                  radius: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.fullNameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (orgInfo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        orgInfo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (employee.employeeCode != null) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _chip(context,
                              icon: Icons.badge_outlined,
                              text: employee.employeeCode!),
                          if (employee.branch?.isNotEmpty ?? false)
                            _chip(context,
                                icon: Icons.location_on_outlined,
                                text: employee.branch!),
                          MobileStatusPill(employee.status),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required IconData icon, required String text}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 3),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════
// التبويب ٣ — الهيكل التنظيمي
// ════════════════════════════════════════════════════════

final _peopleHubOrgProvider =
    FutureProvider.autoDispose<OrgChartData>((ref) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_admin_org_chart')
      .timeout(const Duration(seconds: 20));
  final json = Map<String, dynamic>.from(data as Map);
  final employees = (json['employees'] as List<dynamic>? ?? [])
      .map((e) => OrgEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(growable: false);
  final tree = _buildPeopleHubTree(employees);
  final stats = _computePeopleHubStats(employees);
  return OrgChartData(employees: employees, tree: tree, stats: stats);
});

List<OrgTreeNode> _buildPeopleHubTree(List<OrgEmployee> employees) {
  final map = <String, OrgTreeNode>{};
  for (final emp in employees) {
    map[emp.id] = OrgTreeNode(employee: emp, children: []);
  }
  final roots = <OrgTreeNode>[];
  for (final node in map.values) {
    final mgrId = node.employee.managerEmployeeId;
    if (mgrId != null && map.containsKey(mgrId)) {
      map[mgrId]!.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

OrgStats _computePeopleHubStats(List<OrgEmployee> employees) {
  if (employees.isEmpty) {
    return const OrgStats(
        totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0);
  }
  final managers = employees.where((e) => e.directReportsCount > 0).length;
  final maxDepth =
      employees.fold<int>(0, (m, e) => e.depth > m ? e.depth : m);
  final totalReports =
      employees.fold<int>(0, (s, e) => s + e.directReportsCount);
  final avg = managers > 0 ? (totalReports / managers).roundToDouble() : 0.0;
  return OrgStats(
    totalEmployees: employees.length,
    managersCount: managers,
    maxDepth: maxDepth,
    avgDirectReports: avg,
  );
}

class _OrgChartTab extends ConsumerWidget {
  const _OrgChartTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_peopleHubOrgProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_peopleHubOrgProvider),
      child: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 80),
            _ErrorRetry(
              message: humanizeError(e),
              onRetry: () => ref.invalidate(_peopleHubOrgProvider),
            ),
          ],
        ),
        data: (chart) => _OrgChartBody(chart: chart),
      ),
    );
  }
}

class _OrgChartBody extends StatefulWidget {
  const _OrgChartBody({required this.chart});
  final OrgChartData chart;

  @override
  State<_OrgChartBody> createState() => _OrgChartBodyState();
}

class _OrgChartBodyState extends State<_OrgChartBody> {
  String _search = '';
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _expandDefaults(widget.chart.tree, 0);
  }

  void _expandDefaults(List<OrgTreeNode> nodes, int depth) {
    if (depth >= 2) return;
    for (final n in nodes) {
      if (n.children.isNotEmpty) {
        _expanded.add(n.employee.id);
        _expandDefaults(n.children, depth + 1);
      }
    }
  }

  void _expandAll(List<OrgTreeNode> nodes) {
    for (final n in nodes) {
      if (n.children.isNotEmpty) {
        _expanded.add(n.employee.id);
        _expandAll(n.children);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final filtered = _search.isEmpty
        ? <OrgEmployee>[]
        : widget.chart.employees.where((e) {
            final hay =
                '${e.fullNameAr} ${e.fullNameEn ?? ''} ${e.employeeCode} ${e.jobTitle} ${e.departmentName}'
                    .toLowerCase();
            return hay.contains(_search.toLowerCase());
          }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      children: [
        // ── إحصائيات ──
        Row(
          children: [
            _OrgStatChip(
              icon: Icons.groups_rounded,
              label: 'الموظفون',
              value: '${widget.chart.stats.totalEmployees}',
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            _OrgStatChip(
              icon: Icons.account_tree_rounded,
              label: 'المديرون',
              value: '${widget.chart.stats.managersCount}',
              color: scheme.tertiary,
            ),
            const SizedBox(width: 8),
            _OrgStatChip(
              icon: Icons.layers_rounded,
              label: 'مستويات',
              value: '${widget.chart.stats.maxDepth}',
              color: scheme.secondary,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // ── بحث ──
        TextField(
          decoration: InputDecoration(
            hintText: 'ابحث في الهيكل التنظيمي…',
            prefixIcon: const Icon(Icons.search),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 6),

        // ── أزرار توسيع/طي ──
        if (_search.isEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  _expanded.clear();
                  _expandAll(widget.chart.tree);
                }),
                icon: const Icon(Icons.unfold_more_rounded, size: 18),
                label: const Text('توسيع الكل'),
              ),
              TextButton.icon(
                onPressed: () => setState(_expanded.clear),
                icon: const Icon(Icons.unfold_less_rounded, size: 18),
                label: const Text('طي الكل'),
              ),
            ],
          ),

        // ── المحتوى ──
        if (_search.isNotEmpty)
          ...filtered.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.search_off_rounded,
                            size: 48,
                            color: scheme.onSurfaceVariant),
                        const SizedBox(height: 8),
                        const Text('لا توجد نتائج',
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                ]
              : filtered
                  .map((e) => _OrgCard(
                        employee: e,
                        indent: 0,
                        isManager: e.directReportsCount > 0,
                        isExpanded: false,
                        onToggle: () {},
                      ))
                  .toList()
        else
          ...widget.chart.tree.expand((node) => _buildNode(node, 0)),
      ],
    );
  }

  List<Widget> _buildNode(OrgTreeNode node, int depth) {
    final emp = node.employee;
    final isExpanded = _expanded.contains(emp.id);
    final hasChildren = node.children.isNotEmpty;
    return [
      _OrgCard(
        employee: emp,
        indent: depth,
        isManager: hasChildren,
        isExpanded: isExpanded,
        onToggle: hasChildren
            ? () => setState(() {
                  if (isExpanded) {
                    _expanded.remove(emp.id);
                  } else {
                    _expanded.add(emp.id);
                  }
                })
            : () {},
      ),
      if (hasChildren && isExpanded)
        ...node.children.expand((c) => _buildNode(c, depth + 1)),
    ];
  }
}

class _OrgStatChip extends StatelessWidget {
  const _OrgStatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: color)),
                      Text(label,
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _OrgCard extends StatelessWidget {
  const _OrgCard({
    required this.employee,
    required this.indent,
    required this.isManager,
    required this.isExpanded,
    required this.onToggle,
  });
  final OrgEmployee employee;
  final int indent;
  final bool isManager;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRoot = indent == 0;
    final depthColor = switch (indent % 3) {
      0 => scheme.primary,
      1 => scheme.tertiary,
      _ => scheme.secondary,
    };

    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent * 16.0),
      child: Card(
        color: isRoot ? scheme.primaryContainer.withValues(alpha: .35) : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmployeeProfilePage(
                employeeId: employee.id,
                employeeName: employee.fullNameAr,
              ),
            ),
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  decoration: BoxDecoration(
                    color: depthColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                AppAvatar(
                  name: employee.fullNameAr,
                  photoUrl: employee.photoUrl,
                  radius: isRoot ? 24 : 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              employee.fullNameAr,
                              style: TextStyle(
                                fontWeight: isRoot
                                    ? FontWeight.w900
                                    : FontWeight.w800,
                                fontSize: isRoot ? 15 : 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isManager && employee.directReportsCount > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${employee.directReportsCount} مرؤوس',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        employee.jobTitle.isNotEmpty
                            ? employee.jobTitle
                            : 'غير محدد',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (employee.departmentName.isNotEmpty)
                        Text(
                          employee.departmentName,
                          style: TextStyle(
                            fontSize: 11,
                            color:
                                scheme.onSurfaceVariant.withValues(alpha: .7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isManager)
                  IconButton(
                    onPressed: onToggle,
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_left_rounded,
                      color: scheme.primary,
                      size: 22,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// مساعد: رسالة الخطأ مع زر إعادة المحاولة
// ════════════════════════════════════════════════════════

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      );
}
