import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_employee_summary_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/org_chart_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/today_status_style.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:ahla_shabab_management_os/shared/hierarchy_sort.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// الموظفون والهيكل الإداري — صفحة واحدة بدل ثلاث (الدليل/السجل/الهيكل):
/// بحث، ملخص حالة اليوم (يُصفّي بالضغط)، والهيكل الإداري كاملًا شجرةً
/// بحالة كل موظف اليوم. للإدارة وHR: تصفية بحالة التوظيف (السجل سابقًا).
class PeopleHubPage extends ConsumerStatefulWidget {
  const PeopleHubPage({super.key, this.initialTab = 0});

  /// أُبقي للتوافق مع نقاط الدخول القديمة (كانت تفتح تبويبًا بعينه).
  final int initialTab;

  @override
  ConsumerState<PeopleHubPage> createState() => _PeopleHubPageState();
}

/// الهيكل الإداري الكامل (get_admin_org_chart).
final peopleOrgChartProvider = FutureProvider.autoDispose<List<OrgEmployee>>((
  ref,
) async {
  final data = await ref
      .watch(supabaseProvider)
      .rpc<dynamic>('get_admin_org_chart')
      .timeout(const Duration(seconds: 20));
  final json = Map<String, dynamic>.from(data as Map);
  return (json['employees'] as List<dynamic>? ?? const [])
      .map((e) => OrgEmployee.fromJson(Map<String, dynamic>.from(e as Map)))
      .toList(growable: false);
  // رفض الصلاحية لا يتغير بالإعادة؛ التحديث اليدوي يعيد الطلب.
}, retry: (_, _) => null);

/// حالة اليوم لكل الموظفين في طلب واحد (بدل بحث على الخادم لكل حرف).
final peopleTodayStatusProvider =
    FutureProvider.autoDispose<List<DirectoryEmployee>>((ref) async {
      final data = await ref
          .watch(supabaseProvider)
          .rpc<dynamic>(
            'get_mobile_employee_directory',
            params: {'p_search': null, 'p_limit': 100},
          )
          .timeout(const Duration(seconds: 15));
      return (data as List<dynamic>? ?? const [])
          .map(
            (e) =>
                DirectoryEmployee.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
    });

const _employmentFilters = <(String, String)>[
  ('all', 'كل الحالات'),
  ('active', 'نشط'),
  ('onboarding', 'قيد التهيئة'),
  ('invited', 'تمت الدعوة'),
  ('notice_period', 'فترة إخطار'),
  ('suspended', 'موقوف'),
  ('terminated', 'منتهي'),
  ('archived', 'مؤرشف'),
];

const _registryRoles = {
  'admin',
  'system-admin',
  'executive-secretary',
  'executive',
  'executive-director',
  'hr-manager',
  'hr-specialist',
};

/// شخص في الشاشة: من الهيكل الإداري (أو الدليل إن لم يتح الهيكل) مع حالته اليوم.
class _Person {
  _Person({
    required this.id,
    required this.name,
    this.jobTitle,
    this.department,
    this.photoUrl,
    this.code,
    this.managerId,
  });

  final String id;
  final String name;
  final String? jobTitle;
  final String? department;
  final String? photoUrl;
  final String? code;
  final String? managerId;
  String? status;
  String? statusLabel;
  String? activity;
  final List<_Person> team = [];

  bool get hasStatus => status != null;
  String get label => todayStatusLabel(status, fallback: statusLabel);
  Color get color => todayStatusColor(status);
  String? get destination {
    final a = humanizeIsoDates(activity?.trim() ?? '');
    return isOffsiteStatus(status) && a.isNotEmpty ? a : null;
  }

  late final String searchText =
      '$name ${code ?? ''} ${jobTitle ?? ''} ${department ?? ''}'.toLowerCase();
}

class _PeopleHubPageState extends ConsumerState<PeopleHubPage> {
  final _search = TextEditingController();
  String _query = '';
  TodayStatusGroup? _group;
  String? _employment;
  final _collapsed = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(peopleOrgChartProvider);
    ref.invalidate(peopleTodayStatusProvider);
    if (_employment != null) {
      ref.invalidate(mobileEmployeesProvider(('', _employment!)));
    }
  }

  void _open(String id, String name) {
    final access = ref.read(accessContextProvider).value;
    // 0451: المدير التنفيذي يفتح ملخصه التنفيذي للشخص بدل الملف العام.
    final isExecutive =
        (access?.roles.contains('executive-director') ?? false) ||
        (access?.workspaces.contains(WorkspaceId.executive) ?? false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isExecutive
            ? ExecutiveEmployeeSummaryPage(employeeId: id, employeeName: name)
            : EmployeeProfilePage(employeeId: id, employeeName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(accessContextProvider).value;
    final canFilterEmployment =
        access?.roles.any(_registryRoles.contains) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الموظفون والهيكل الإداري'),
        actions: [
          if (canFilterEmployment)
            PopupMenuButton<String>(
              tooltip: 'حالة التوظيف',
              icon: Icon(
                Icons.filter_list_rounded,
                color: _employment != null
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onSelected: (v) => setState(() {
                _employment = v == '_tree' ? null : v;
                _group = null;
              }),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: '_tree',
                  child: Text('الهيكل الإداري (الافتراضي)'),
                ),
                const PopupMenuDivider(),
                for (final f in _employmentFilters)
                  PopupMenuItem(
                    value: f.$1,
                    child: Text('حالة التوظيف: ${f.$2}'),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: _employment != null ? _registryBody() : _peopleBody(),
      ),
    );
  }

  // ── الحقل والملخص ───────────────────────────────────────────────────────

  Widget _searchField() {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _search,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'ابحث بالاسم أو الكود أو الوظيفة أو الإدارة…',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                tooltip: 'مسح',
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _search.clear();
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
      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
    );
  }

  Widget _summary(List<_Person> people) {
    final counts = <TodayStatusGroup, int>{};
    for (final p in people.where((p) => p.hasStatus)) {
      final g = TodayStatusGroup.of(p.status);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    // كل المجموعات ظاهرة معًا (Wrap) — لا شريط أفقي يخفي بعضها.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: 'الكل',
          count: people.length,
          color: Theme.of(context).colorScheme.primary,
          icon: Icons.groups_rounded,
          selected: _group == null,
          onTap: () => setState(() => _group = null),
        ),
        for (final g in TodayStatusGroup.values)
          if ((counts[g] ?? 0) > 0)
            _SummaryChip(
              label: g.label,
              count: counts[g]!,
              color: g.color,
              icon: g.icon,
              selected: _group == g,
              onTap: () => setState(() => _group = _group == g ? null : g),
            ),
      ],
    );
  }

  // ── الشاشة الرئيسية: الهيكل أو نتائج البحث/التصفية ──────────────────────

  Widget _peopleBody() {
    final org = ref.watch(peopleOrgChartProvider);
    final today = ref.watch(peopleTodayStatusProvider);

    // الخطأ (مثل عدم إتاحة الهيكل لهذا المستخدم) لا يُنتظر: يُعرض الدليل وحده.
    bool waiting(AsyncValue<Object?> v) =>
        v.isLoading && !v.hasValue && !v.hasError;
    if (waiting(org) || waiting(today)) {
      return const Center(child: CircularProgressIndicator());
    }
    final orgList = org.hasError ? null : org.value;
    final todayList = today.value ?? const <DirectoryEmployee>[];
    if (orgList == null && todayList.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          _ErrorRetry(
            message: humanizeError(org.error ?? today.error ?? 'تعذر التحميل'),
            onRetry: _refresh,
          ),
        ],
      );
    }

    // الأشخاص من الهيكل (أو من الدليل إن لم يتح الهيكل لهذا المستخدم)
    final byId = <String, _Person>{};
    if (orgList != null) {
      for (final e in orgList) {
        byId[e.id] = _Person(
          id: e.id,
          name: e.fullNameAr,
          jobTitle: e.jobTitle,
          department: e.departmentName,
          photoUrl: e.photoUrl,
          code: e.employeeCode,
          managerId: e.managerEmployeeId,
        );
      }
    }
    for (final d in todayList) {
      final p = byId.putIfAbsent(
        d.id,
        () => _Person(
          id: d.id,
          name: d.name,
          jobTitle: d.jobTitle,
          department: d.department,
          photoUrl: d.photoUrl,
          code: d.employeeCode,
        ),
      );
      p
        ..status = d.statusToday
        ..statusLabel = d.statusTodayLabel
        ..activity = d.activityTitle;
    }
    final people = byId.values.toList(growable: false);
    for (final p in people) {
      final m = p.managerId == null ? null : byId[p.managerId];
      m?.team.add(p);
    }
    List<_Person> sorted(List<_Person> list) =>
        sortByHierarchy<_Person>(list, (p) => p.jobTitle ?? '', (p) => p.name);
    for (final p in people) {
      final ordered = sorted(p.team);
      p.team
        ..clear()
        ..addAll(ordered);
    }
    final roots = sorted(
      people
          .where((p) => p.managerId == null || !byId.containsKey(p.managerId))
          .toList(),
    );
    final hasTree = orgList != null;
    final filtering = _query.isNotEmpty || _group != null || !hasTree;
    final matches = filtering
        ? sorted(
            people
                .where(
                  (p) =>
                      (_query.isEmpty || p.searchText.contains(_query)) &&
                      (_group == null ||
                          (p.hasStatus &&
                              TodayStatusGroup.of(p.status) == _group)),
                )
                .toList(),
          )
        : const <_Person>[];
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _searchField(),
        const SizedBox(height: 10),
        _summary(people),
        const SizedBox(height: 12),
        if (!filtering) ...[
          Row(
            children: [
              Icon(
                Icons.account_tree_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'الهيكل الإداري',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(_collapsed.clear),
                child: const Text('توسيع الكل'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _collapsed
                    ..clear()
                    ..addAll(
                      people.where((p) => p.team.isNotEmpty).map((p) => p.id),
                    );
                }),
                child: const Text('طي الكل'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final r in roots) _treeNode(r, root: true),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              matches.isEmpty
                  ? 'لا توجد نتائج مطابقة'
                  : _employeesCount(matches.length),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final p in matches)
            _PersonTile(
              person: p,
              managerName: p.managerId == null ? null : byId[p.managerId]?.name,
              onTap: () => _open(p.id, p.name),
            ),
        ],
      ],
    );
  }

  Widget _treeNode(_Person person, {bool root = false}) {
    final expanded = !_collapsed.contains(person.id);
    final card = _NodeCard(
      person: person,
      root: root,
      expanded: expanded,
      onOpen: () => _open(person.id, person.name),
      onToggle: person.team.isEmpty
          ? null
          : () => setState(() {
              if (expanded) {
                _collapsed.add(person.id);
              } else {
                _collapsed.remove(person.id);
              }
            }),
    );
    if (person.team.isEmpty || !expanded) return card;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final lineColor = Theme.of(context).colorScheme.outlineVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        Padding(
          // الخط الرأسي تحت مركز صورة الأب
          padding: EdgeInsetsDirectional.only(
            start: _NodeCard.avatarCenter(root: root) - 1,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < person.team.length; i++)
                CustomPaint(
                  painter: _GuidePainter(
                    color: lineColor,
                    rtl: rtl,
                    last: i == person.team.length - 1,
                    tickY: 6 + _NodeCard.avatarCenter(root: false),
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 16,
                      top: 6,
                    ),
                    child: _treeNode(person.team[i]),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ── حالة التوظيف (السجل سابقًا) — للإدارة وHR ──────────────────────────

  Widget _registryBody() {
    final status = _employment!;
    final list = ref.watch(mobileEmployeesProvider(('', status)));
    final label = _employmentFilters
        .firstWhere((f) => f.$1 == status, orElse: () => (status, status))
        .$2;
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          _ErrorRetry(message: humanizeError(e), onRetry: _refresh),
        ],
      ),
      data: (items) {
        final matches = sortByHierarchy<MobileEmployeeSummary>(
          items
              .where(
                (e) =>
                    _query.isEmpty ||
                    '${e.fullNameAr} ${e.employeeCode ?? ''} ${e.jobTitle ?? ''} ${e.department ?? ''}'
                        .toLowerCase()
                        .contains(_query),
              )
              .toList(),
          (e) => e.jobTitle ?? '',
          (e) => e.fullNameAr,
        );
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _searchField(),
            const SizedBox(height: 10),
            Row(
              children: [
                InputChip(
                  avatar: const Icon(Icons.filter_list_rounded, size: 18),
                  label: Text('حالة التوظيف: $label'),
                  onDeleted: () => setState(() => _employment = null),
                  deleteButtonTooltipMessage: 'العودة إلى الهيكل',
                ),
                const Spacer(),
                Text(
                  _employeesCount(matches.length),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (matches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('لا يوجد موظفون مطابقون')),
              )
            else
              for (final e in matches)
                _PersonTile(
                  person: _Person(
                    id: e.id,
                    name: e.fullNameAr,
                    jobTitle: e.jobTitle,
                    department: e.department,
                    photoUrl: e.photoUrl,
                    code: e.employeeCode,
                  ),
                  employmentStatus: e.status,
                  onTap: () => _open(e.id, e.fullNameAr),
                ),
          ],
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? color.withValues(alpha: .18)
          : color.withValues(alpha: .07),
      shape: StadiumBorder(
        side: BorderSide(
          color: color.withValues(alpha: selected ? .9 : .3),
          width: selected ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '$label $count',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// بطاقة شخص في الشجرة: الصورة بحلقة لون حالته اليوم، الاسم والوظيفة، حالته،
/// وعدد فريقه مع زر الطي/التوسيع.
class _NodeCard extends StatelessWidget {
  const _NodeCard({
    required this.person,
    required this.root,
    required this.expanded,
    required this.onOpen,
    this.onToggle,
  });

  final _Person person;
  final bool root;
  final bool expanded;
  final VoidCallback onOpen;
  final VoidCallback? onToggle;

  static const double _padding = 10;
  static double _radius({required bool root}) => root ? 22 : 18;

  /// مركز الصورة من بداية البطاقة (لخطوط الشجرة): الحشوة + الحلقة + نصف القطر.
  static double avatarCenter({required bool root}) =>
      _padding + 3 + _radius(root: root);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ringColor = person.hasStatus ? person.color : scheme.outlineVariant;
    return Material(
      color: root
          ? scheme.primaryContainer.withValues(alpha: .4)
          : scheme.surfaceContainerHighest.withValues(alpha: .4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: root
              ? scheme.primary.withValues(alpha: .45)
              : scheme.outlineVariant.withValues(alpha: .6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(_padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 1.5),
                ),
                child: AppAvatar(
                  name: person.name,
                  photoUrl: person.photoUrl,
                  radius: _radius(root: root),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: root ? 15 : null,
                      ),
                    ),
                    if (person.jobTitle?.trim().isNotEmpty ?? false)
                      Text(
                        person.jobTitle!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (person.hasStatus) ...[
                      const SizedBox(height: 3),
                      _StatusLine(person: person),
                    ],
                  ],
                ),
              ),
              if (onToggle != null)
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onToggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${person.team.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.person});

  final _Person person;

  @override
  Widget build(BuildContext context) {
    final destination = person.destination;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: person.color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            destination == null
                ? person.label
                : '${person.label} — $destination',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: person.color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// سطر نتيجة بحث/تصفية: الشخص ووظيفته وإدارته وحالته اليوم وفريق من يتبع.
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.onTap,
    this.managerName,
    this.employmentStatus,
  });

  final _Person person;
  final VoidCallback onTap;
  final String? managerName;
  final String? employmentStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sub = [
      if (person.jobTitle?.trim().isNotEmpty ?? false) person.jobTitle!.trim(),
      if (person.department?.trim().isNotEmpty ?? false)
        person.department!.trim(),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: .4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: person.hasStatus
                          ? person.color
                          : scheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                  child: AppAvatar(
                    name: person.name,
                    photoUrl: person.photoUrl,
                    radius: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (person.hasStatus) ...[
                        const SizedBox(height: 3),
                        _StatusLine(person: person),
                      ],
                      if (managerName != null)
                        Text(
                          'مديره المباشر: $managerName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (employmentStatus != null) ...[
                  const SizedBox(width: 6),
                  MobileStatusPill(employmentStatus!),
                ],
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// خط الشجرة لعضو: رأسي من الأب (ينتهي عند آخر عضو) وفرع أفقي إلى بطاقته.
class _GuidePainter extends CustomPainter {
  _GuidePainter({
    required this.color,
    required this.rtl,
    required this.last,
    required this.tickY,
  });

  final Color color;
  final bool rtl;
  final bool last;
  final double tickY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = rtl ? size.width - 1 : 1.0;
    final end = rtl ? size.width - 16 : 16.0;
    final dir = rtl ? -1.0 : 1.0;
    const r = 7.0;
    if (last) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, tickY - r)
        ..quadraticBezierTo(x, tickY, x + dir * r, tickY)
        ..lineTo(end, tickY);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(x, tickY), Offset(end, tickY), paint);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.color != color ||
      old.rtl != rtl ||
      old.last != last ||
      old.tickY != tickY;
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      ],
    ),
  );
}

/// «موظف واحد / موظفان / 5 موظفين / 33 موظفًا».
String _employeesCount(int n) => switch (n) {
  1 => 'موظف واحد',
  2 => 'موظفان',
  >= 3 && <= 10 => '$n موظفين',
  >= 11 && <= 99 => '$n موظفًا',
  _ => '$n موظف',
};
