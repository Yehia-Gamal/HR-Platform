import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Model ──

class _OrgDepartment {
  const _OrgDepartment({
    required this.id,
    required this.name,
    this.parentId,
    this.managerId,
    required this.depth,
  });
  factory _OrgDepartment.fromJson(Map<String, dynamic> json) => _OrgDepartment(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        parentId: json['parentId'] as String?,
        managerId: json['managerId'] as String?,
        depth: (json['depth'] as num?)?.toInt() ?? 0,
      );
  final String id;
  final String name;
  final String? parentId;
  final String? managerId;
  final int depth;
}

class _OrgEmployee {
  const _OrgEmployee({
    required this.id,
    required this.fullNameAr,
    required this.employeeCode,
    required this.jobTitle,
    this.photoUrl,
    this.departmentId,
    required this.departmentName,
    required this.isDeptManager,
  });
  factory _OrgEmployee.fromJson(Map<String, dynamic> json) => _OrgEmployee(
        id: json['id'] as String,
        fullNameAr: json['fullNameAr'] as String? ?? '',
        employeeCode: json['employeeCode'] as String? ?? '',
        jobTitle: json['jobTitle'] as String? ?? '',
        photoUrl: json['photoUrl'] as String?,
        departmentId: json['departmentId'] as String?,
        departmentName: json['departmentName'] as String? ?? '',
        isDeptManager: json['isDeptManager'] as bool? ?? false,
      );
  final String id;
  final String fullNameAr;
  final String employeeCode;
  final String jobTitle;
  final String? photoUrl;
  final String? departmentId;
  final String departmentName;
  final bool isDeptManager;
}

class _OrgChartData {
  const _OrgChartData({required this.departments, required this.employees});
  factory _OrgChartData.fromJson(Map<String, dynamic> json) => _OrgChartData(
        departments: (json['departments'] as List<dynamic>? ?? [])
            .map((e) => _OrgDepartment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false),
        employees: (json['employees'] as List<dynamic>? ?? [])
            .map((e) => _OrgEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false),
      );
  final List<_OrgDepartment> departments;
  final List<_OrgEmployee> employees;
}

// ── Provider ──

final _orgChartProvider = FutureProvider.autoDispose<_OrgChartData>((ref) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_mobile_org_chart')
      .timeout(const Duration(seconds: 20));
  return _OrgChartData.fromJson(Map<String, dynamic>.from(data as Map));
});

// ── Page ──

class OrgChartPage extends ConsumerWidget {
  const OrgChartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_orgChartProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('الهيكل الوظيفي'),
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

class _OrgTreeView extends StatefulWidget {
  const _OrgTreeView({required this.chart});
  final _OrgChartData chart;
  @override
  State<_OrgTreeView> createState() => _OrgTreeViewState();
}

class _OrgTreeViewState extends State<_OrgTreeView> {
  String _search = '';
  final _expanded = <String>{};

  @override
  void initState() {
    super.initState();
    // Expand root departments by default
    for (final dept in widget.chart.departments) {
      if (dept.depth == 0) _expanded.add(dept.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rootDepts = widget.chart.departments
        .where((d) => d.parentId == null)
        .toList(growable: false);

    // Filter employees by search
    final allEmployees = _search.isEmpty
        ? widget.chart.employees
        : widget.chart.employees.where((e) {
            final haystack =
                '${e.fullNameAr} ${e.employeeCode} ${e.jobTitle} ${e.departmentName}'
                    .toLowerCase();
            return haystack.contains(_search.toLowerCase());
          }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'ابحث عن موظف أو إدارة...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withValues(alpha: .5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
        ),

        // Stats bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.groups_rounded, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '${allEmployees.length} موظف نشط',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.account_tree_rounded, size: 18, color: scheme.tertiary),
              const SizedBox(width: 6),
              Text(
                '${widget.chart.departments.length} إدارة',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (_search.isEmpty) ...[
                TextButton.icon(
                  onPressed: () => setState(
                    () => _expanded
                      ..clear()
                      ..addAll(widget.chart.departments.map((d) => d.id)),
                  ),
                  icon: const Icon(Icons.unfold_more_rounded, size: 18),
                  label: const Text('توسيع الكل'),
                ),
                TextButton.icon(
                  onPressed: () => setState(_expanded.clear),
                  icon: const Icon(Icons.unfold_less_rounded, size: 18),
                  label: const Text('طي الكل'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // If searching, show flat list
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
            ...allEmployees.map((e) => _EmployeeCard(employee: e)),
        ] else ...[
          // Tree view by department
          ...rootDepts.expand((dept) => _buildDeptTree(dept, 0)),

          // Employees without department
          ..._employeesInDept(null).map((e) => _EmployeeCard(employee: e)),
        ],
      ],
    );
  }

  List<Widget> _buildDeptTree(_OrgDepartment dept, int indent) {
    final isExpanded = _expanded.contains(dept.id);
    final children = widget.chart.departments
        .where((d) => d.parentId == dept.id)
        .toList(growable: false);
    final employees = _employeesInDept(dept.id);
    final hasContent = children.isNotEmpty || employees.isNotEmpty;
    // ابحث عن مدير القسم (رابط managerId لقسم أو موظف علم كـ isDeptManager).
    final manager = dept.managerId != null
        ? widget.chart.employees
            .where((e) => e.id == dept.managerId)
            .firstOrNull
        : employees.where((e) => e.isDeptManager).firstOrNull;

    return [
      _DeptHeader(
        dept: dept,
        indent: indent,
        isExpanded: isExpanded,
        employeeCount: employees.length,
        hasChildren: hasContent,
        managerName: manager?.fullNameAr,
        onTap: () => setState(() {
          if (isExpanded) {
            _expanded.remove(dept.id);
          } else {
            _expanded.add(dept.id);
          }
        }),
      ),
      if (isExpanded) ...[
        // Manager first
        ...employees.where((e) => e.isDeptManager).map(
              (e) => _EmployeeCard(employee: e, indent: indent + 1, isManager: true),
            ),
        // Then regular employees
        ...employees.where((e) => !e.isDeptManager).map(
              (e) => _EmployeeCard(employee: e, indent: indent + 1),
            ),
        // Sub-departments
        ...children.expand((child) => _buildDeptTree(child, indent + 1)),
      ],
    ];
  }

  List<_OrgEmployee> _employeesInDept(String? deptId) {
    return widget.chart.employees
        .where((e) => e.departmentId == deptId)
        .toList(growable: false);
  }
}

class _DeptHeader extends StatelessWidget {
  const _DeptHeader({
    required this.dept,
    required this.indent,
    required this.isExpanded,
    required this.employeeCount,
    required this.hasChildren,
    required this.managerName,
    required this.onTap,
  });
  final _OrgDepartment dept;
  final int indent;
  final bool isExpanded;
  final int employeeCount;
  final bool hasChildren;
  final String? managerName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // شريط لوني رأسي يدل على مستوى القسم في الهيكل لتحسين القراءة البصرية.
    final depthColor = switch (indent % 3) {
      0 => scheme.primary,
      1 => scheme.tertiary,
      _ => scheme.secondary,
    };
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent * 16.0),
      child: Card(
        color: scheme.primaryContainer.withValues(alpha: .4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasChildren ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 34,
                  margin: const EdgeInsetsDirectional.only(end: 10),
                  decoration: BoxDecoration(
                    color: depthColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.folder_open_rounded
                      : Icons.folder_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dept.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        managerName != null && managerName!.isNotEmpty
                            ? 'المدير: $managerName · $employeeCount موظف'
                            : '$employeeCount موظف',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onPrimaryContainer.withValues(alpha: .7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasChildren)
                  Icon(
                    isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({
    required this.employee,
    this.indent = 0,
    this.isManager = false,
  });
  final _OrgEmployee employee;
  final int indent;
  final bool isManager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent * 16.0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Avatar
              AppAvatar(
                name: employee.fullNameAr,
                photoUrl: employee.photoUrl,
                radius: 22,
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            employee.fullNameAr,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isManager) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'مدير',
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
                    if (employee.jobTitle.isNotEmpty)
                      Text(
                        employee.jobTitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      employee.employeeCode,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
              ),
              // Department badge (only in search mode / flat list)
              if (indent == 0 && employee.departmentName.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxWidth: 80),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    employee.departmentName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSecondaryContainer,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
