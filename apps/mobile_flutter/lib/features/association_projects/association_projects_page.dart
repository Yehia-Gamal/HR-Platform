import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_project_detail_page.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_models.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// لون لمبة الحالة — مطابق للويب.
Color projectLedColor(ProjectLed led) => switch (led) {
      ProjectLed.active => const Color(0xFF10B981),
      ProjectLed.halted || ProjectLed.critical => const Color(0xFFEF4444),
      ProjectLed.completed => const Color(0xFF3B82F6),
      ProjectLed.pending => const Color(0xFFF59E0B),
      ProjectLed.rejected => const Color(0xFFE11D48),
      ProjectLed.draft => const Color(0xFF94A3B8),
      ProjectLed.stale => const Color(0xFF9CA3AF),
    };

/// لمبة الحالة: أخضر يعمل، أحمر ثابت متوقف، أحمر يومض يحتاج تدخل.
class ProjectLedLamp extends StatefulWidget {
  const ProjectLedLamp(this.led, {super.key, this.size = 16});

  final ProjectLed led;
  final double size;

  @override
  State<ProjectLedLamp> createState() => _ProjectLedLampState();
}

class _ProjectLedLampState extends State<ProjectLedLamp> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProjectLedLamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.led == ProjectLed.critical) {
      // الوميض هو الإشارة نفسها؛ مع تقليل الحركة يُبطَّأ ولا يُلغى.
      _blink.duration = Duration(milliseconds: MediaQuery.of(context).disableAnimations ? 2400 : 1000);
      if (!_blink.isAnimating) _blink.repeat();
    } else {
      _blink
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = projectLedColor(widget.led);
    final glows = widget.led == ProjectLed.active || widget.led == ProjectLed.halted || widget.led == ProjectLed.critical;
    return Semantics(
      label: 'حالة المشروع: ${widget.led.label}',
      child: AnimatedBuilder(
        animation: _blink,
        builder: (context, _) {
          // موجة مربعة: نصف الدورة مضاء ونصفها شبه مطفأ.
          final on = widget.led != ProjectLed.critical || _blink.value < 0.5;
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: on ? color : color.withValues(alpha: 0.18),
              boxShadow: glows && on
                  ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: widget.size * 0.8, spreadRadius: 1)]
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class AssociationProjectsPage extends ConsumerStatefulWidget {
  const AssociationProjectsPage({super.key});

  @override
  ConsumerState<AssociationProjectsPage> createState() => _AssociationProjectsPageState();
}

class _AssociationProjectsPageState extends ConsumerState<AssociationProjectsPage> {
  ProjectLed? _filter;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(associationProjectsProvider);
    final catalog = async.value;
    final requestsCount = catalog == null
        ? 0
        : (catalog.isFullAccess
            ? catalog.requests.where((p) => p.approvalStatus == 'pending_approval').length
            : catalog.requests.length);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مشاريع الجمعية'),
          bottom: TabBar(
            tabs: [
              const Tab(text: 'لوحة المشاريع'),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(catalog?.isFullAccess == true ? 'طلبات الاعتماد' : 'قيد الإعداد'),
                    if (requestsCount > 0) ...[
                      const SizedBox(width: 6),
                      Badge(label: Text('$requestsCount'), backgroundColor: AppColors.statusWarning),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: catalog != null && catalog.canCreate
            ? FloatingActionButton.extended(
                onPressed: () => _openCreate(context, catalog),
                icon: const Icon(Icons.add),
                label: const Text('مشروع جديد'),
              )
            : null,
        body: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorView(
            message: humanizeError(error),
            onRetry: () => ref.invalidate(associationProjectsProvider),
          ),
          data: (c) => TabBarView(
            children: [
              _BoardTab(
                catalog: c,
                filter: _filter,
                onFilter: (f) => setState(() => _filter = f),
              ),
              _RequestsTab(catalog: c),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCreate(BuildContext context, AssociationProjectsCatalog catalog) async {
    final departmentId = catalog.myDepartmentId;
    if (departmentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حسابك غير مرتبط بإدارة — لا يمكن إنشاء مشروع من التطبيق.')),
      );
      return;
    }
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateProjectSheet(departmentId: departmentId, isFullAccess: catalog.isFullAccess),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(catalog.isFullAccess ? 'تم إنشاء المشروع واعتماده' : 'تم إرسال المشروع للمدير التنفيذي لاعتماده'),
        ),
      );
    }
  }
}

class _BoardTab extends ConsumerWidget {
  const _BoardTab({required this.catalog, required this.filter, required this.onFilter});

  final AssociationProjectsCatalog catalog;
  final ProjectLed? filter;
  final ValueChanged<ProjectLed?> onFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = catalog.board;
    final visible = filter == null ? board : board.where((p) => p.led == filter).toList();
    int count(ProjectLed l) => board.where((p) => p.led == l).length;
    final critical = count(ProjectLed.critical);

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(associationProjectsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (critical > 0 && filter != ProjectLed.critical)
            Card(
              color: AppColors.statusDanger.withValues(alpha: 0.1),
              child: ListTile(
                leading: const ProjectLedLamp(ProjectLed.critical, size: 18),
                title: Text(
                  '${critical == 1 ? 'مشروع واحد' : '$critical مشاريع'} بلا تحديث منذ ${catalog.criticalDays} يوماً أو أكثر',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.statusDanger),
                ),
                subtitle: Text(catalog.isFullAccess ? 'تحتاج تدخلك — اضغط للعرض' : 'اضغط للعرض'),
                onTap: () => onFilter(ProjectLed.critical),
              ),
            ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'الكل', count: board.length, selected: filter == null, onTap: () => onFilter(null)),
                for (final l in const [ProjectLed.active, ProjectLed.halted, ProjectLed.critical, ProjectLed.completed])
                  _FilterChip(
                    led: l,
                    label: l.label,
                    count: count(l),
                    selected: filter == l,
                    onTap: () => onFilter(filter == l ? null : l),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            _EmptyView(
              icon: Icons.folder_open_outlined,
              title: board.isEmpty ? 'لا توجد مشاريع معتمدة بعد' : 'لا توجد مشاريع بهذه الحالة',
              subtitle: board.isEmpty
                  ? 'عندما ترسل إدارتك مشروعاً ويعتمده المدير التنفيذي يظهر هنا بلمبة حالته.'
                  : 'اختر فلتراً آخر.',
            )
          else
            for (final p in visible) _ProjectTile(project: p),
        ],
      ),
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab({required this.catalog});

  final AssociationProjectsCatalog catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = catalog.requests;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(associationProjectsProvider),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (requests.isEmpty)
            _EmptyView(
              icon: Icons.inbox_outlined,
              title: catalog.isFullAccess ? 'لا توجد طلبات اعتماد' : 'لا توجد مشاريع قيد الإعداد',
              subtitle: catalog.isFullAccess
                  ? 'عندما ترسل إدارة مشروعاً جديداً يظهر هنا لتعتمده.'
                  : 'اضغط «مشروع جديد» لإنشاء مشروع لإدارتك وإرساله للاعتماد.',
            )
          else
            for (final p in requests) _ProjectTile(project: p),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap, this.led});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final ProjectLed? led;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        avatar: led == null ? null : ProjectLedLamp(led!, size: 11),
        label: Text('$label ($count)'),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final AssociationProject project;

  @override
  Widget build(BuildContext context) {
    final p = project;
    final scheme = Theme.of(context).colorScheme;
    final color = projectLedColor(p.led);
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.led == ProjectLed.critical ? color.withValues(alpha: 0.6) : scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AssociationProjectDetailPage(projectId: p.id, title: p.name)),
        ),
        child: Container(
          decoration: BoxDecoration(border: BorderDirectional(top: BorderSide(color: color, width: 4))),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProjectLedLamp(p.led),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.led.label, style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                  ),
                  if (p.isApproved)
                    Text(daysAgoLabel(p.activityDays), style: muted)
                  else
                    Text(approvalLabels[p.approvalStatus] ?? p.approvalStatus, style: muted),
                ],
              ),
              const SizedBox(height: 8),
              Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text('${p.departmentName} • ${p.ownerName}', style: muted),
              if (p.isApproved) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (p.progress / 100).clamp(0, 1).toDouble(),
                          minHeight: 8,
                          color: color,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('${p.progress.round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  p.status == 'completed'
                      ? 'اكتمل التنفيذ'
                      : p.currentStepTitle != null
                          ? 'المرحلة الحالية: ${p.currentStepTitle}'
                          : 'لم تُحدَّد خطوات التنفيذ بعد',
                  style: muted,
                ),
                if (p.totalSteps > 0) Text('تم ${p.completedSteps} من ${p.totalSteps} خطوات', style: muted),
              ],
              if (p.rejectionReason != null && p.approvalStatus == 'rejected') ...[
                const SizedBox(height: 6),
                Text(
                  'ملاحظة المدير التنفيذي: ${p.rejectionReason}',
                  style: const TextStyle(color: AppColors.statusDanger, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
              if (p.blockedSteps > 0 || p.overdueSteps > 0 || p.isOverdue) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (p.blockedSteps > 0) _Tag('${p.blockedSteps} متعثرة', AppColors.statusDanger),
                    if (p.overdueSteps > 0) _Tag('${p.overdueSteps} متأخرة', AppColors.statusWarning),
                    if (p.isOverdue) const _Tag('تجاوز الموعد', AppColors.statusDanger),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Column(
        children: [
          Icon(icon, size: 54, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

/// إنشاء مشروع لإدارة المستخدم — يُرسل للاعتماد مباشرة.
class _CreateProjectSheet extends ConsumerStatefulWidget {
  const _CreateProjectSheet({required this.departmentId, required this.isFullAccess});

  final String departmentId;
  final bool isFullAccess;

  @override
  ConsumerState<_CreateProjectSheet> createState() => _CreateProjectSheetState();
}

class _CreateProjectSheetState extends ConsumerState<_CreateProjectSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _priority = 'medium';
  DateTime? _targetEnd;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم المشروع');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(associationProjectCommandsProvider).create(
            name: _name.text.trim(),
            description: _description.text.trim(),
            departmentId: widget.departmentId,
            priority: _priority,
            targetEndDate: _targetEnd,
            submit: !widget.isFullAccess,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, st) {
      setState(() {
        _saving = false;
        _error = humanizeError(e, st);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('مشروع جديد لإدارتك', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              widget.isFullAccess
                  ? 'المشاريع التي ينشئها المدير التنفيذي تُعتمد مباشرة.'
                  : 'سيُرسل للمدير التنفيذي لاعتماده، ثم يظهر على لوحة المشاريع.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'اسم المشروع *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'الهدف والوصف المختصر', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'الأولوية', border: OutlineInputBorder()),
              items: [
                for (final e in projectPriorityLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _priority = v ?? 'medium'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _targetEnd == null
                    ? 'الموعد المستهدف للانتهاء (اختياري)'
                    : 'الموعد المستهدف: ${_targetEnd!.day}/${_targetEnd!.month}/${_targetEnd!.year}',
              ),
              onPressed: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _targetEnd ?? now.add(const Duration(days: 30)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) setState(() => _targetEnd = picked);
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(widget.isFullAccess ? 'إنشاء المشروع' : 'إنشاء وإرسال للاعتماد'),
            ),
          ],
        ),
      ),
    );
  }
}
