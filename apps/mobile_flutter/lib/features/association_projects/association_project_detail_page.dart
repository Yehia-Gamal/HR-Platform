import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_project_form_page.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_models.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_page.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _fmtDate(DateTime? d) => d == null ? '—' : '${d.day}/${d.month}/${d.year}';

/// تفاصيل مشروع: في أي مرحلة هو، ما تم وما تبقى، والتحديثات —
/// وإدارة الخطوات لأعضاء إدارة المشروع.
class AssociationProjectDetailPage extends ConsumerStatefulWidget {
  const AssociationProjectDetailPage({super.key, required this.projectId, this.title});

  final String projectId;
  final String? title;

  @override
  ConsumerState<AssociationProjectDetailPage> createState() => _AssociationProjectDetailPageState();
}

class _AssociationProjectDetailPageState extends ConsumerState<AssociationProjectDetailPage> {
  bool _busy = false;

  AssociationProjectCommands get _cmd => ref.read(associationProjectCommandsProvider);

  String? get _myEmployeeId => ref.read(associationProjectsProvider).value?.myEmployeeId;

  Future<void> _openEdit(AssociationProjectDetail d) async {
    final catalog = ref.read(associationProjectsProvider).value;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssociationProjectFormPage(
          project: d.project,
          permissions: d.permissions,
          isFullAccess: catalog?.isFullAccess ?? false,
          myEmployeeId: catalog?.myEmployeeId,
          myDepartmentId: catalog?.myDepartmentId,
        ),
      ),
    );
  }

  /// ينفذ عملية ويعرض نتيجتها — رسالة الخادم العربية تظهر كما هي عند الخطأ.
  Future<bool> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      }
      return true;
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e, st)), backgroundColor: AppColors.statusDanger),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(associationProjectDetailProvider(widget.projectId));
    final detail = async.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.project.name ?? widget.title ?? 'تفاصيل المشروع'),
        actions: [
          if (detail != null && (detail.permissions.canEdit || detail.permissions.canEditTeam))
            IconButton(
              tooltip: 'تعديل المشروع وفريقه',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _busy ? null : () => _openEdit(detail),
            ),
          if (detail != null && detail.permissions.canDelete)
            IconButton(
              tooltip: 'حذف المشروع',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy ? null : () => _confirmDelete(detail.project),
            ),
        ],
        bottom: _busy ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator()) : null,
      ),
      floatingActionButton: detail != null && detail.permissions.canManage
          ? FloatingActionButton.extended(
              onPressed: _busy ? null : () => _editStep(detail),
              icon: const Icon(Icons.playlist_add),
              label: const Text('خطوة'),
            )
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(humanizeError(e), textAlign: TextAlign.center),
                TextButton.icon(
                  onPressed: () => ref.invalidate(associationProjectDetailProvider(widget.projectId)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(associationProjectDetailProvider(widget.projectId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              _header(d),
              const SizedBox(height: 12),
              _statusBanner(d),
              _summary(d),
              const SizedBox(height: 16),
              _team(d),
              const SizedBox(height: 16),
              _steps(d),
              const SizedBox(height: 16),
              _updates(d),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(AssociationProjectDetail d) {
    final p = d.project;
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ProjectLedLamp(p.led, size: 18),
            const SizedBox(width: 8),
            Text(p.led.label, style: TextStyle(color: projectLedColor(p.led), fontWeight: FontWeight.w900)),
            const Spacer(),
            Text(approvalLabels[p.approvalStatus] ?? '', style: muted),
          ],
        ),
        const SizedBox(height: 8),
        Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        Text('${p.code} • ${p.scopeLabel} • القائد: ${p.leaderName}', style: muted),
        if (projectRoleLabels[p.myRole] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Icon(Icons.verified_user_outlined, size: 14, color: AppColors.brandPrimary),
                const SizedBox(width: 4),
                Text(
                  projectRoleLabels[p.myRole]!,
                  style: const TextStyle(color: AppColors.brandPrimary, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        if (p.description != null) ...[
          const SizedBox(height: 8),
          Text(p.description!),
        ],
      ],
    );
  }

  Widget _statusBanner(AssociationProjectDetail d) {
    final p = d.project;
    final perms = d.permissions;
    final catalog = ref.watch(associationProjectsProvider).value;
    final isFull = catalog?.isFullAccess ?? false;
    final since = daysAgoLabel(p.activityDays);

    final (String? text, Color color) = switch (p.led) {
      ProjectLed.critical => (
          isFull
              ? 'لا يوجد أي تحديث (آخر نشاط $since). يحتاج تدخلك لمعرفة سبب التوقف.'
              : 'المشروع بلا تحديث (آخر نشاط $since) وتم تنبيه المدير التنفيذي. حدّث الخطوات أو سجّل تحديثاً.',
          AppColors.statusDanger,
        ),
      ProjectLed.halted => ('المشروع متوقف أو لم يُحدَّث منذ فترة (آخر نشاط $since).', AppColors.statusDanger),
      ProjectLed.pending => (
          isFull ? 'أُرسل هذا المشروع وينتظر قرارك.' : 'بانتظار اعتماد المدير التنفيذي. يمكنك إضافة الخطوات من الآن.',
          AppColors.statusWarning,
        ),
      ProjectLed.rejected => (
          'أُعيد المشروع للتعديل${p.rejectionReason != null ? ': «${p.rejectionReason}»' : '.'} عدّله ثم أعد إرساله.',
          AppColors.statusDanger,
        ),
      ProjectLed.draft => ('مسودة لم تُرسل بعد للاعتماد.', AppColors.statusInfo),
      _ => (null, AppColors.statusInfo),
    };

    final actions = <Widget>[
      if (perms.canApprove) ...[
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(() => _cmd.approve(p.id), success: 'تم اعتماد المشروع'),
          icon: const Icon(Icons.check),
          label: const Text('اعتماد'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.statusDanger),
          onPressed: _busy ? null : () => _reject(p),
          icon: const Icon(Icons.undo),
          label: const Text('إعادة للتعديل'),
        ),
      ],
      if (perms.canSubmit && perms.canManage)
        FilledButton.icon(
          onPressed: _busy ? null : () => _run(() => _cmd.submit(p.id), success: 'تم إرسال المشروع للاعتماد'),
          icon: const Icon(Icons.send),
          label: const Text('إرسال للاعتماد'),
        ),
      if (perms.canUpdate && perms.canManage && !p.isClosed)
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _addUpdate(d),
          icon: const Icon(Icons.edit_note),
          label: const Text('تسجيل تحديث'),
        ),
    ];

    if (text == null && actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text != null) Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, height: 1.6)),
            if (actions.isNotEmpty) ...[
              if (text != null) const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summary(AssociationProjectDetail d) {
    final p = d.project;
    final done = d.steps.where((s) => s.isDone).length;
    final current = d.currentStep;
    final scheme = Theme.of(context).colorScheme;
    final color = projectLedColor(p.led);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${p.progress.round()}%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Text('نسبة الإنجاز', style: TextStyle(color: scheme.onSurfaceVariant)),
                const Spacer(),
                Text(projectStatusLabels[p.status] ?? p.status, style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (p.progress / 100).clamp(0, 1).toDouble(),
                minHeight: 10,
                color: color,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _stat('تم إنجازه', '$done خطوة', AppColors.statusSuccess),
                _stat('متبقي', '${d.steps.length - done} خطوة', null),
                _stat('الأولوية', projectPriorityLabels[p.priority] ?? p.priority, null),
                _stat('الموعد المستهدف', _fmtDate(p.targetEndDate), p.isOverdue ? AppColors.statusDanger : null),
              ],
            ),
            if (current != null && p.status != 'completed') ...[
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  text: 'المرحلة الحالية: ',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                  children: [
                    TextSpan(
                      text: current.title,
                      style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color? color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
        ],
      );

  Widget _steps(AssociationProjectDetail d) {
    final canManage = d.permissions.canManage;
    final scheme = Theme.of(context).colorScheme;
    final done = d.steps.where((s) => s.isDone).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('خطوات التنفيذ والمهام', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        Text(
          'تم $done • متبقي ${d.steps.length - done}${canManage ? ' — اضغط الدائرة عند إنجاز الخطوة' : ''}',
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (d.steps.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'لم تُضف خطوات بعد. قسّم المشروع إلى خطوات واضحة ليظهر تقدمه تلقائياً.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (var i = 0; i < d.steps.length; i++) _stepTile(d, d.steps[i], i, isCurrent: d.steps[i].id == d.currentStep?.id),
      ],
    );
  }

  Widget _stepTile(AssociationProjectDetail d, AssociationProjectStep s, int index, {required bool isCurrent}) {
    final scheme = Theme.of(context).colorScheme;
    final canManage = d.permissions.canManage;
    final color = switch (s.status) {
      'done' => AppColors.statusSuccess,
      'blocked' => AppColors.statusDanger,
      'in_progress' => AppColors.brandPrimary,
      _ => scheme.outline,
    };
    final icon = switch (s.status) {
      'done' => Icons.check_circle,
      'blocked' => Icons.block,
      _ => Icons.radio_button_unchecked,
    };
    final isMine = _myEmployeeId != null && s.assigneeId == _myEmployeeId && !s.isDone;
    final meta = <String>[
      if (isMine) 'مهمتك',
      if (s.assigneeName != null && !isMine) 'المكلَّف: ${s.assigneeName}',
      if (s.dueDate != null) 'الموعد: ${_fmtDate(s.dueDate)}${s.isOverdue ? ' — متأخرة' : ''}',
      if (s.isDone && s.completedAt != null) 'تمت ${_fmtDate(s.completedAt)}',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isMine
              ? AppColors.statusWarning
              : isCurrent
                  ? AppColors.brandPrimary
                  : scheme.outlineVariant,
          width: isCurrent || isMine ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: canManage && !_busy ? () => _editStep(d, s) : null,
        leading: IconButton(
          tooltip: s.isDone ? 'إلغاء الإنجاز' : 'تعليم كمنجزة',
          onPressed: !canManage || _busy
              ? null
              : () => _run(() => _cmd.setStepStatus(d.project.id, s.id, s.isDone ? 'pending' : 'done')),
          icon: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              if (!s.isDone && s.status != 'blocked')
                Text('${index + 1}', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        title: Text(
          s.title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            decoration: s.isDone ? TextDecoration.lineThrough : null,
            color: s.isDone ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: meta.isEmpty
            ? Text(stepStatusLabels[s.status] ?? s.status)
            : Text(
                '${stepStatusLabels[s.status] ?? s.status} • ${meta.join(' • ')}',
                style: TextStyle(color: s.isOverdue ? AppColors.statusDanger : null),
              ),
        trailing: canManage
            ? PopupMenuButton<String>(
                tooltip: 'خيارات الخطوة',
                enabled: !_busy,
                onSelected: (v) {
                  if (v == 'delete') {
                    _confirmDeleteStep(d.project.id, s);
                  } else if (v == 'edit') {
                    _editStep(d, s);
                  } else if (v == 'up' || v == 'down') {
                    _run(() => _cmd.moveStep(d.project.id, s.id, up: v == 'up'));
                  } else {
                    _run(() => _cmd.setStepStatus(d.project.id, s.id, v));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('تعديل / تكليف')),
                  if (index > 0) const PopupMenuItem(value: 'up', child: Text('تحريك لأعلى')),
                  if (index < d.steps.length - 1) const PopupMenuItem(value: 'down', child: Text('تحريك لأسفل')),
                  for (final e in stepStatusLabels.entries)
                    if (e.key != s.status) PopupMenuItem(value: e.key, child: Text('تعليم: ${e.value}')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('حذف الخطوة', style: TextStyle(color: AppColors.statusDanger)),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _team(AssociationProjectDetail d) {
    final p = d.project;
    final scheme = Theme.of(context).colorScheme;
    final canEditTeam = d.permissions.canEditTeam;
    final me = _myEmployeeId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'فريق المشروع',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            if (canEditTeam)
              TextButton.icon(
                onPressed: _busy ? null : () => _openEdit(d),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: const Text('تعديل الفريق'),
              ),
          ],
        ),
        for (final m in p.team)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            color: m.isLeader ? AppColors.statusWarning.withValues(alpha: 0.10) : null,
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                backgroundColor: m.isLeader ? AppColors.statusWarning : scheme.surfaceContainerHighest,
                child: m.isLeader
                    ? const Icon(Icons.workspace_premium, color: Colors.white, size: 20)
                    : Text(m.name.trim().isEmpty ? '؟' : m.name.trim()[0], style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              title: Text(
                '${m.name}${m.employeeId == me ? ' (أنت)' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(m.subtitle.isEmpty ? 'عضو الفريق' : m.subtitle),
            ),
          ),
        if (p.departments.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'الإدارات المسؤولة — موظفوها يتابعون المشروع ويديرون خطواته',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final dep in p.departments)
                Chip(
                  avatar: const Icon(Icons.apartment, size: 16),
                  label: Text(dep.name),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _updates(AssociationProjectDetail d) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('سجل التحديثات', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (d.updates.isEmpty)
          Text(
            d.project.isApproved ? 'لا توجد تحديثات بعد.' : 'تبدأ التحديثات بعد اعتماد المشروع.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          )
        else
          for (final u in d.updates)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(u.authorName, style: const TextStyle(fontWeight: FontWeight.w800))),
                        Text(_fmtDate(u.createdAt), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(u.note),
                    if (u.statusChange != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'الحالة ← ${projectStatusLabels[u.statusChange] ?? u.statusChange}',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  // ── الحوارات ──────────────────────────────────────────────

  /// إضافة خطوة أو تعديلها مع المكلَّف — المكلَّف من الفريق أو من موظفي
  /// الإدارات المرتبطة (يتحقق الخادم من ذلك ويُشعره بمهمته).
  Future<void> _editStep(AssociationProjectDetail d, [AssociationProjectStep? step]) async {
    final title = TextEditingController(text: step?.title ?? '');
    final description = TextEditingController(text: step?.description ?? '');
    DateTime? due = step?.dueDate;
    String? assigneeId = step?.assigneeId;

    // موظفو الإدارات المرتبطة من خارج الفريق (إن وُجدت إدارات).
    var deptStaff = <PickerEmployee>[];
    if (d.project.departments.isNotEmpty) {
      try {
        final pickers = await ref.read(associationProjectPickersProvider.future);
        final deptIds = d.project.departments.map((x) => x.id).toSet();
        final teamIds = d.project.team.map((m) => m.employeeId).toSet();
        deptStaff = pickers.employees
            .where((e) => e.departmentId != null && deptIds.contains(e.departmentId) && !teamIds.contains(e.id))
            .toList();
      } catch (_) {
        // القائمة اختيارية — الفريق وحده يكفي للتكليف.
      }
    }
    if (!mounted) return;

    final options = <(String, String)>[
      for (final m in d.project.team) (m.employeeId, m.isLeader ? '${m.name} (القائد)' : m.name),
      for (final e in deptStaff) (e.id, e.departmentName == null ? e.name : '${e.name} — ${e.departmentName}'),
    ];
    // مكلَّف سابق خرج من النطاق يبقى ظاهراً حتى يُغيَّر.
    if (assigneeId != null && !options.any((o) => o.$1 == assigneeId)) {
      options.add((assigneeId, step?.assigneeName ?? 'المكلَّف الحالي'));
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  step == null ? 'خطوة / مهمة جديدة' : 'تعديل الخطوة',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: title,
                  autofocus: step == null,
                  decoration: const InputDecoration(labelText: 'عنوان الخطوة *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'تفاصيل (اختياري)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: assigneeId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'المكلَّف بالتنفيذ',
                    helperText: 'يُشعَر المكلَّف بمهمته',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('— بدون —')),
                    for (final o in options)
                      DropdownMenuItem<String?>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setSheet(() => assigneeId = v),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined),
                  label: Text(due == null ? 'موعد الإنجاز (اختياري)' : 'الموعد: ${_fmtDate(due)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: due ?? now.add(const Duration(days: 7)),
                      firstDate: now.subtract(const Duration(days: 365)),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null && ctx.mounted) setSheet(() => due = picked);
                  },
                ),
                if (due != null)
                  TextButton(onPressed: () => setSheet(() => due = null), child: const Text('إزالة الموعد')),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    if (title.text.trim().isNotEmpty) Navigator.pop(ctx, true);
                  },
                  child: Text(step == null ? 'إضافة الخطوة' : 'حفظ الخطوة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final text = title.text.trim();
    final details = description.text.trim();
    title.dispose();
    description.dispose();
    if (ok == true && text.isNotEmpty) {
      await _run(
        () => _cmd.upsertStep(
          d.project.id,
          stepId: step?.id,
          title: text,
          description: details.isEmpty ? null : details,
          sortOrder: step?.sortOrder,
          status: step?.status ?? 'pending',
          dueDate: due,
          assigneeId: assigneeId,
        ),
        success: step == null ? 'تمت إضافة الخطوة' : 'تم حفظ الخطوة',
      );
    }
  }

  Future<void> _addUpdate(AssociationProjectDetail d) async {
    final note = TextEditingController();
    var status = d.project.status == 'planned' ? 'active' : d.project.status;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تسجيل تحديث', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ما الذي تم إنجازه؟ *',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('حالة المشروع', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in const ['active', 'on_hold', 'completed'])
                    ChoiceChip(
                      label: Text(projectStatusLabels[s]!),
                      selected: status == s,
                      onSelected: (_) => setSheet(() => status = s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (note.text.trim().isNotEmpty) Navigator.pop(ctx, true);
                },
                child: const Text('حفظ التحديث'),
              ),
            ],
          ),
        ),
      ),
    );
    final text = note.text.trim();
    note.dispose();
    if (ok == true && text.isNotEmpty) {
      await _run(
        () => _cmd.addUpdate(
          d.project.id,
          note: text,
          statusChange: status != d.project.status ? status : null,
        ),
        success: 'تم تسجيل التحديث',
      );
    }
  }

  Future<void> _reject(AssociationProject p) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة المشروع للتعديل'),
        content: TextField(
          controller: reason,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ما المطلوب تعديله؟', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () {
              if (reason.text.trim().isNotEmpty) Navigator.pop(ctx, true);
            },
            child: const Text('إعادة'),
          ),
        ],
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (ok == true) {
      await _run(() => _cmd.reject(p.id, text), success: 'تمت إعادة المشروع لفريقه');
    }
  }

  Future<void> _confirmDeleteStep(String projectId, AssociationProjectStep s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخطوة'),
        content: Text('ستُحذف «${s.title}» نهائياً ويُعاد حساب نسبة الإنجاز.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await _run(() => _cmd.deleteStep(projectId, s.id), success: 'تم حذف الخطوة');
  }

  Future<void> _confirmDelete(AssociationProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المشروع'),
        content: Text('سيُحذف مشروع «${p.name}» بكل خطواته وتحديثاته نهائياً.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.statusDanger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _run(() => _cmd.deleteProject(p.id), success: 'تم حذف المشروع');
    if (deleted && mounted) Navigator.of(context).pop();
  }
}
