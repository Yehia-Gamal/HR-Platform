import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_operations_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// مركز العمليات (إدارة التشغيل) — المهام المفتوحة، المهمات، والقوافل
/// بنطاق صلاحية المستخدم (mig 0408). كان سابقاً صفحة "ويب فقط".
class MobileOperationsCenterPage extends ConsumerStatefulWidget {
  const MobileOperationsCenterPage({required this.access, super.key});

  final AccessContext access;

  @override
  ConsumerState<MobileOperationsCenterPage> createState() =>
      _MobileOperationsCenterPageState();
}

enum _OpsTab { tasks, missions, convoys }

class _MobileOperationsCenterPageState
    extends ConsumerState<MobileOperationsCenterPage> {
  final _search = TextEditingController();
  _OpsTab _tab = _OpsTab.tasks;
  String _query = '';
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _canManage => widget.access.hasAnyPermission(const [
    'tasks.write',
    'operations.mission.manage',
    'operations.convoy.manage',
  ]);

  Future<void> _transition(MobileOpsTask task, String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await rpcWithTimeout(
        ref.read(supabaseProvider).rpc<dynamic>(
          'admin_transition_task',
          params: {'p_id': task.id, 'p_status': status},
        ),
      );
      ref.invalidate(mobileOperationsCenterProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث حالة المهمة إلى «${_statusLabel(status)}»')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<MobileOpsTask> get _filteredTasks {
    final q = _query.trim().toLowerCase();
    return ref
        .watch(mobileOperationsCenterProvider)
        .asData
        ?.value
        .tasks
        .where(
          (t) =>
              q.isEmpty ||
              t.title.toLowerCase().contains(q) ||
              t.assigneeName.toLowerCase().contains(q) ||
              (t.description?.toLowerCase().contains(q) ?? false),
        )
        .toList(growable: false) ??
        const [];
  }

  List<MobileOpsMission> get _filteredMissions {
    final q = _query.trim().toLowerCase();
    return ref
        .watch(mobileOperationsCenterProvider)
        .asData
        ?.value
        .missions
        .where(
          (m) =>
              q.isEmpty ||
              m.employeeName.toLowerCase().contains(q) ||
              m.destination.toLowerCase().contains(q) ||
              m.purpose.toLowerCase().contains(q),
        )
        .toList(growable: false) ??
        const [];
  }

  List<MobileOpsConvoy> get _filteredConvoys {
    final q = _query.trim().toLowerCase();
    return ref
        .watch(mobileOperationsCenterProvider)
        .asData
        ?.value
        .convoys
        .where(
          (c) =>
              q.isEmpty ||
              c.name.toLowerCase().contains(q) ||
              c.employeeName.toLowerCase().contains(q) ||
              c.origin.toLowerCase().contains(q) ||
              c.destination.toLowerCase().contains(q),
        )
        .toList(growable: false) ??
        const [];
  }

  int get _activeCount => switch (_tab) {
    _OpsTab.tasks => _filteredTasks.length,
    _OpsTab.missions => _filteredMissions.length,
    _OpsTab.convoys => _filteredConvoys.length,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final center = ref.watch(mobileOperationsCenterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة التشغيل')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(mobileOperationsCenterProvider),
          child: center.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      humanizeError(error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(mobileOperationsCenterProvider),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (data) {
              final summary = data.summary;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  MobileSectionHeader(
                    title: 'مركز العمليات',
                    subtitle: 'المهام والمهمات والقوافل حسب صلاحياتك.',
                  ),
                  const SizedBox(height: 10),
                  _MetricsStrip(summary: summary),
                  const SizedBox(height: 12),
                  MobileFilterBar(
                    searchHint: 'بحث في التبويب الحالي…',
                    controller: _search,
                    onSearchChanged: (v) => setState(() => _query = v),
                    options: const [
                      MobileFilterOption('tasks', 'المهام'),
                      MobileFilterOption('missions', 'المهمات'),
                      MobileFilterOption('convoys', 'القوافل'),
                    ],
                    selected: _tab.name,
                    onSelected: (v) => setState(
                      () => _tab = _OpsTab.values.firstWhere(
                        (t) => t.name == v,
                        orElse: () => _OpsTab.tasks,
                      ),
                    ),
                    resultLabel: '$_activeCount عنصر',
                  ),
                  const SizedBox(height: 8),
                  if (_activeCount == 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: Text('لا توجد نتائج مطابقة')),
                    )
                  else ..._cardsFor(_tab),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _cardsFor(_OpsTab tab) => switch (tab) {
    _OpsTab.tasks => _filteredTasks
        .map(
          (task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TaskCard(
              task: task,
              canManage: _canManage && task.isOpen,
              busy: _busy,
              onTransition: (status) => _transition(task, status),
            ),
          ),
        )
        .toList(growable: false),
    _OpsTab.missions => _filteredMissions
        .map(
          (mission) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MissionCard(mission: mission),
          ),
        )
        .toList(growable: false),
    _OpsTab.convoys => _filteredConvoys
        .map(
          (convoy) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ConvoyCard(convoy: convoy),
          ),
        )
        .toList(growable: false),
  };

  String _statusLabel(String status) => switch (status) {
    'pending' => 'قيد الانتظار',
    'in_progress' => 'قيد التنفيذ',
    'done' => 'مكتملة',
    'cancelled' => 'ملغاة',
    'approved' => 'معتمدة',
    'rejected' => 'مرفوضة',
    _ => status,
  };
}

class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({required this.summary});

  final MobileOperationsCenterSummary summary;

  @override
  Widget build(BuildContext context) {
    final cells = [
      ('${summary.openTasks}', 'مهام مفتوحة', Icons.list_alt_rounded),
      ('${summary.urgentTasks}', 'عاجلة', Icons.circle_notifications_rounded),
      ('${summary.missions}', 'مهمات', Icons.calendar_month_rounded),
      ('${summary.convoys}', 'قوافل', Icons.directions_bus_rounded),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: cells
              .map(
                (cell) => Expanded(
                  child: Column(
                    children: [
                      Icon(cell.$3, size: 20, color: AppColors.brandPrimary),
                      const SizedBox(height: 4),
                      Text(
                        cell.$1,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        cell.$2,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.canManage,
    required this.busy,
    required this.onTransition,
  });

  final MobileOpsTask task;
  final bool canManage;
  final bool busy;
  final ValueChanged<String> onTransition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MobileStatusPill(task.status),
              ],
            ),
            if (task.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text(
                task.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(context, Icons.person_outline_rounded, task.assigneeName),
                _chip(context, Icons.flag_outlined, _priorityLabel(task.priority)),
                if (task.dueDate != null)
                  _chip(
                    context,
                    Icons.event_outlined,
                    _dateLabel(task.dueDate!),
                  ),
              ],
            ),
            if (canManage && !busy) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (task.status != 'in_progress')
                    TextButton.icon(
                      onPressed: () => onTransition('in_progress'),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('بدء التنفيذ'),
                    ),
                  if (task.status != 'done')
                    TextButton.icon(
                      onPressed: () => onTransition('done'),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('إنهاء'),
                    ),
                  if (task.status != 'cancelled')
                    TextButton.icon(
                      onPressed: () => onTransition('cancelled'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('إلغاء'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _priorityLabel(String priority) => switch (priority) {
    'low' => 'منخفضة',
    'medium' => 'متوسطة',
    'high' => 'مرتفعة',
    'urgent' => 'عاجلة',
    _ => priority,
  };

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Widget _chip(BuildContext context, IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

class _MissionCard extends StatelessWidget {
  const _MissionCard({required this.mission});

  final MobileOpsMission mission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'مهمة إلى ${mission.destination}',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MobileStatusPill(mission.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              mission.purpose,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(context, Icons.person_outline_rounded, mission.employeeName),
                if (mission.startAt != null)
                  _chip(context, Icons.login_rounded, _timeLabel(mission.startAt!)),
                if (mission.endAt != null)
                  _chip(context, Icons.logout_rounded, _timeLabel(mission.endAt!)),
                if (mission.transportMode != null)
                  _chip(context, Icons.directions_car_rounded, _transportLabel(mission.transportMode!)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _transportLabel(String mode) => switch (mode) {
    'company_vehicle' => 'سيارة الجمعية',
    'personal' => 'شخصية',
    'public' => 'مواصلات عامة',
    'flight' => 'طيران',
    'other' => 'أخرى',
    _ => mode,
  };

  String _timeLabel(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $h:$m';
  }

  Widget _chip(BuildContext context, IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

class _ConvoyCard extends StatelessWidget {
  const _ConvoyCard({required this.convoy});

  final MobileOpsConvoy convoy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    convoy.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                MobileStatusPill(convoy.status),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.trending_flat_rounded, size: 16, color: AppColors.brandPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'من ${convoy.origin} إلى ${convoy.destination}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(context, Icons.person_outline_rounded, convoy.employeeName),
                if (convoy.departureAt != null)
                  _chip(context, Icons.login_rounded, _timeLabel(convoy.departureAt!)),
                if (convoy.returnAt != null)
                  _chip(context, Icons.logout_rounded, _timeLabel(convoy.returnAt!)),
                _chip(context, Icons.people_outline_rounded, '${convoy.passengers} راكب'),
                _chip(context, Icons.directions_bus_rounded, '${convoy.vehicles} مركبة'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $h:$m';
  }

  Widget _chip(BuildContext context, IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
