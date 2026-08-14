import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Model ──

class OrgEmployee {
  const OrgEmployee({
    required this.id,
    required this.fullNameAr,
    this.fullNameEn,
    this.photoUrl,
    required this.jobTitle,
    required this.departmentName,
    required this.employeeCode,
    this.managerEmployeeId,
    required this.directReportsCount,
    required this.depth,
  });

  factory OrgEmployee.fromJson(Map<String, dynamic> json) => OrgEmployee(
        id: json['id'] as String,
        fullNameAr: json['fullNameAr'] as String? ?? '',
        fullNameEn: json['fullNameEn'] as String?,
        photoUrl: json['photoUrl'] as String?,
        jobTitle: json['jobTitle'] as String? ?? '',
        departmentName: json['departmentName'] as String? ?? '',
        employeeCode: json['employeeCode'] as String? ?? '',
        managerEmployeeId: json['managerEmployeeId'] as String?,
        directReportsCount: (json['directReportsCount'] as num?)?.toInt() ?? 0,
        depth: (json['depth'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String fullNameAr;
  final String? fullNameEn;
  final String? photoUrl;
  final String jobTitle;
  final String departmentName;
  final String employeeCode;
  final String? managerEmployeeId;
  final int directReportsCount;
  final int depth;
}

class OrgTreeNode {
  const OrgTreeNode({required this.employee, required this.children});
  final OrgEmployee employee;
  final List<OrgTreeNode> children;
}

class OrgChartData {
  const OrgChartData({required this.employees, required this.tree, required this.stats});
  final List<OrgEmployee> employees;
  final List<OrgTreeNode> tree;
  final OrgStats stats;
}

class OrgStats {
  const OrgStats({
    required this.totalEmployees,
    required this.managersCount,
    required this.maxDepth,
    required this.avgDirectReports,
  });
  final int totalEmployees;
  final int managersCount;
  final int maxDepth;
  final double avgDirectReports;
}

// ── Tree builder ──

List<OrgTreeNode> _buildTree(List<OrgEmployee> employees) {
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

OrgStats _computeStats(List<OrgEmployee> employees) {
  if (employees.isEmpty) {
    return const OrgStats(
        totalEmployees: 0, managersCount: 0, maxDepth: 0, avgDirectReports: 0);
  }
  final managers = employees.where((e) => e.directReportsCount > 0).length;
  final maxDepth = employees.fold<int>(0, (m, e) => e.depth > m ? e.depth : m);
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

// ── Provider ──

final _orgChartProvider =
    FutureProvider.autoDispose<OrgChartData>((ref) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_admin_org_chart')
      .timeout(const Duration(seconds: 20));
  final json = Map<String, dynamic>.from(data as Map);
  final employees = (json['employees'] as List<dynamic>? ?? [])
      .map((e) => OrgEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(growable: false);
  final tree = _buildTree(employees);
  final stats = _computeStats(employees);
  return OrgChartData(employees: employees, tree: tree, stats: stats);
});

// ── Page ──

class OrgChartPage extends ConsumerWidget {
  const OrgChartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_orgChartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الهيكل التنظيمي الإداري'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_orgChartProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_orgChartProvider),
        child: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 120),
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(humanizeError(error), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.icon(
                  onPressed: () => ref.invalidate(_orgChartProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (chart) => _OrgTreeView(chart: chart),
        ),
      ),
    );
  }
}

// ── Tree View ──

class _OrgTreeView extends StatefulWidget {
  const _OrgTreeView({required this.chart});
  final OrgChartData chart;

  @override
  State<_OrgTreeView> createState() => _OrgTreeViewState();
}

class _OrgTreeViewState extends State<_OrgTreeView> {
  String _search = '';
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    _expandDefaults(widget.chart.tree, 0);
  }

  void _expandDefaults(List<OrgTreeNode> nodes, int depth) {
    if (depth >= 2) return;
    for (final node in nodes) {
      if (node.children.isNotEmpty) {
        _expanded.add(node.employee.id);
        _expandDefaults(node.children, depth + 1);
      }
    }
  }

  void _expandAll(List<OrgTreeNode> nodes) {
    for (final node in nodes) {
      if (node.children.isNotEmpty) {
        _expanded.add(node.employee.id);
        _expandAll(node.children);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final allEmployees = _search.isEmpty
        ? <OrgEmployee>[]
        : widget.chart.employees.where((e) {
            final haystack =
                '${e.fullNameAr} ${e.fullNameEn ?? ''} ${e.employeeCode} ${e.jobTitle} ${e.departmentName}'
                    .toLowerCase();
            return haystack.contains(_search.toLowerCase());
          }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      children: [
        // ── بطاقات الإحصائيات ──
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _StatChip(
                icon: Icons.groups_rounded,
                label: 'الموظفون',
                value: '${widget.chart.stats.totalEmployees}',
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.account_tree_rounded,
                label: 'المديرون',
                value: '${widget.chart.stats.managersCount}',
                color: scheme.tertiary,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _StatChip(
                icon: Icons.layers_rounded,
                label: 'أقصى عمق',
                value: '${widget.chart.stats.maxDepth}',
                color: scheme.secondary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.supervisor_account_rounded,
                label: 'متوسط المرؤوسين',
                value: widget.chart.stats.avgDirectReports.toStringAsFixed(1),
                color: scheme.primary,
              ),
            ],
          ),
        ),

        // ── البحث ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث عن موظف…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor:
                  scheme.surfaceContainerHighest.withValues(alpha: .5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),

        // ── أزرار توسيع/طي الكل ──
        if (_search.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
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
          ),

        // ── المحتوى ──
        if (_search.isNotEmpty) ...[
          if (allEmployees.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.search_off_rounded, size: 48,
                      color: scheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  const Text('لا توجد نتائج', textAlign: TextAlign.center),
                ],
              ),
            )
          else
            ...allEmployees.map((e) => _EmployeeCard(
                  employee: e,
                  indent: 0,
                  isManager: e.directReportsCount > 0,
                  isExpanded: false,
                  onToggle: () {},
                )),
        ] else ...[
          ...widget.chart.tree
              .map((node) => _buildTreeNode(node, 0))
              .expand((e) => e),
        ],
      ],
    );
  }

  List<Widget> _buildTreeNode(OrgTreeNode node, int depth) {
    final emp = node.employee;
    final isExpanded = _expanded.contains(emp.id);
    final hasChildren = node.children.isNotEmpty;

    return [
      _EmployeeCard(
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
        ...node.children
            .map((child) => _buildTreeNode(child, depth + 1))
            .expand((e) => e),
    ];
  }
}

// ── Stat Chip ──

class _StatChip extends StatelessWidget {
  const _StatChip({
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
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Employee Card ──

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
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
        color: isRoot
            ? scheme.primaryContainer.withValues(alpha: .35)
            : null,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                                fontWeight:
                                    isRoot ? FontWeight.w900 : FontWeight.w800,
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
                        employee.jobTitle.isNotEmpty ? employee.jobTitle : 'غير محدد',
                        style: TextStyle(
                          fontSize: 12,
                          color: employee.jobTitle.isNotEmpty
                              ? scheme.onSurfaceVariant
                              : scheme.onSurfaceVariant.withValues(alpha: .5),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          if (employee.departmentName.isNotEmpty)
                            Flexible(
                              child: Text(
                                employee.departmentName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: .7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          if (employee.departmentName.isNotEmpty &&
                              employee.employeeCode.isNotEmpty)
                            Text(
                              ' · ',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: .5),
                              ),
                            ),
                          if (employee.employeeCode.isNotEmpty)
                            Text(
                              employee.employeeCode,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: .5),
                              ),
                            ),
                        ],
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
                    constraints: const BoxConstraints(
                        minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
