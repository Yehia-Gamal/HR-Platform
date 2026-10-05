import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_models.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _fmt(DateTime? d) => d == null ? '' : '${d.day}/${d.month}/${d.year}';

/// عنصر قابل للاختيار في ورقة البحث.
class _Option {
  const _Option(this.id, this.title, this.subtitle);
  final String id;
  final String title;
  final String subtitle;
}

/// ورقة اختيار بالبحث — شخص واحد (القائد) أو عدة أشخاص/إدارات.
/// تُرجع القائمة المختارة، أو null عند الإلغاء.
Future<List<String>?> _showSelectionSheet(
  BuildContext context, {
  required String title,
  required List<_Option> options,
  required List<String> selected,
  bool single = false,
}) {
  return showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      var query = '';
      final chosen = [...selected];
      return StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = normalizeArabic(query);
          final visible = options
              .where((o) => q.isEmpty || normalizeArabic('${o.title} ${o.subtitle}').contains(q))
              .take(150)
              .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.8,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(ctx).viewInsets.bottom + 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  TextField(
                    autofocus: options.length > 8,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'ابحث بالاسم أو الوظيفة أو الإدارة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setSheet(() => query = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(child: Text('لا توجد نتائج'))
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final o = visible[i];
                              final isOn = chosen.contains(o.id);
                              final subtitle = o.subtitle.isEmpty ? null : Text(o.subtitle);
                              if (single) {
                                return ListTile(
                                  leading: Icon(
                                    isOn ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                    color: isOn ? AppColors.brandPrimary : null,
                                  ),
                                  title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: subtitle,
                                  onTap: () => Navigator.pop(ctx, [o.id]),
                                );
                              }
                              return CheckboxListTile(
                                value: isOn,
                                controlAffinity: ListTileControlAffinity.leading,
                                title: Text(o.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: subtitle,
                                onChanged: (v) => setSheet(() => v == true ? chosen.add(o.id) : chosen.remove(o.id)),
                              );
                            },
                          ),
                  ),
                  if (!single)
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, chosen),
                      child: Text(chosen.isEmpty ? 'تم' : 'تم (${chosen.length})'),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// إنشاء/تعديل مشروع بفريقه: قائد واحد + أعضاء + إدارات اختيارية.
class AssociationProjectFormPage extends ConsumerStatefulWidget {
  const AssociationProjectFormPage({
    super.key,
    this.project,
    this.permissions,
    required this.isFullAccess,
    this.myEmployeeId,
    this.myDepartmentId,
  });

  /// غيابه = مشروع جديد.
  final AssociationProject? project;
  final AssociationProjectPermissions? permissions;
  final bool isFullAccess;
  final String? myEmployeeId;
  final String? myDepartmentId;

  @override
  ConsumerState<AssociationProjectFormPage> createState() => _AssociationProjectFormPageState();
}

class _AssociationProjectFormPageState extends ConsumerState<AssociationProjectFormPage> {
  late final TextEditingController _name = TextEditingController(text: widget.project?.name ?? '');
  late final TextEditingController _description = TextEditingController(text: widget.project?.description ?? '');
  late String _priority = widget.project?.priority ?? 'medium';
  late DateTime? _start = widget.project?.startDate;
  late DateTime? _targetEnd = widget.project?.targetEndDate;
  late String? _leaderId = widget.project?.ownerId ?? widget.myEmployeeId;
  late List<String> _memberIds = widget.project == null
      ? []
      : widget.project!.members.where((m) => !m.isLeader).map((m) => m.employeeId).toList();
  late List<String> _departmentIds = widget.project != null
      ? widget.project!.departments.map((d) => d.id).toList()
      : (!widget.isFullAccess && widget.myDepartmentId != null ? [widget.myDepartmentId!] : []);
  bool _submitNow = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.project != null;

  /// بعد الإرسال للاعتماد: الاسم والوصف هما ما اعتُمد.
  bool get _coreLocked => _isEdit && !widget.isFullAccess && widget.permissions?.canEditCore == false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  /// اسم الموظف: من قائمة الاختيار، أو من فريق المشروع الحالي.
  String _nameOf(String id, ProjectPickers? pickers) {
    final e = pickers?.byId(id);
    if (e != null) return e.name;
    for (final m in widget.project?.members ?? const <ProjectMember>[]) {
      if (m.employeeId == id) return m.name;
    }
    return '—';
  }

  List<_Option> _people(ProjectPickers pickers) =>
      pickers.employees.map((e) => _Option(e.id, e.name, e.subtitle)).toList(growable: false);

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _start : _targetEnd;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (start ? now : now.add(const Duration(days: 30))),
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null || !mounted) return;
    setState(() => start ? _start = picked : _targetEnd = picked);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'اكتب اسم المشروع');
      return;
    }
    if (_leaderId == null) {
      setState(() => _error = 'اختر قائد المشروع');
      return;
    }
    if (_start != null && _targetEnd != null && _targetEnd!.isBefore(_start!)) {
      setState(() => _error = 'الموعد المستهدف يجب أن يكون بعد تاريخ البدء');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(associationProjectCommandsProvider).save(
            projectId: widget.project?.id,
            name: _name.text.trim(),
            description: _description.text.trim(),
            priority: _priority,
            startDate: _start,
            targetEndDate: _targetEnd,
            leaderId: _leaderId,
            memberIds: _memberIds.where((id) => id != _leaderId).toList(),
            departmentIds: _departmentIds,
            submit: !_isEdit && !widget.isFullAccess && _submitNow,
          );
      if (!mounted) return;
      final message = _isEdit
          ? 'تم حفظ المشروع'
          : widget.isFullAccess
              ? 'تم إنشاء المشروع واعتماده'
              : _submitNow
                  ? 'تم إرسال المشروع للمدير التنفيذي لاعتماده'
                  : 'تم حفظ المشروع كمسودة';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = humanizeError(e, st);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickersAsync = ref.watch(associationProjectPickersProvider);
    final pickers = pickersAsync.value;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
    final members = _memberIds.where((id) => id != _leaderId).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'تعديل المشروع وفريقه' : 'مشروع جديد')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _isEdit
                        ? 'حفظ التعديلات'
                        : widget.isFullAccess
                            ? 'إنشاء واعتماد المشروع'
                            : _submitNow
                                ? 'إنشاء وإرسال للاعتماد'
                                : 'حفظ كمسودة',
                  ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.statusDanger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: const TextStyle(color: AppColors.statusDanger, fontWeight: FontWeight.w700)),
            ),
          if (!_isEdit)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                widget.isFullAccess
                    ? 'المشاريع التي ينشئها المدير التنفيذي تُعتمد مباشرة.'
                    : 'حدّد قائد المشروع وفريقه (والإدارات إن وُجدت)، ثم يُرسل للمدير التنفيذي لاعتماده.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
              ),
            ),
          TextField(
            controller: _name,
            enabled: !_coreLocked,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'اسم المشروع *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            enabled: !_coreLocked,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'الهدف والوصف المختصر', border: OutlineInputBorder()),
          ),
          if (_coreLocked)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('الاسم والوصف مقفلان بعد إرسال المشروع للاعتماد — يمكن تعديل الفريق والأولوية والمواعيد.', style: muted),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text(_start == null ? 'تاريخ البدء' : 'البدء ${_fmt(_start)}'),
                  onPressed: () => _pickDate(start: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined, size: 18),
                  label: Text(_targetEnd == null ? 'الموعد المستهدف' : 'الانتهاء ${_fmt(_targetEnd)}'),
                  onPressed: () => _pickDate(start: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── فريق المشروع ──
          Text('فريق المشروع', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('قائد واحد مسؤول أول، ومعه أعضاء يديرون الخطوات ويسجّلون التحديثات.', style: muted),
          const SizedBox(height: 10),
          if (pickersAsync.isLoading && pickers == null)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (pickersAsync.hasError && pickers == null)
            Text(humanizeError(pickersAsync.error!), style: const TextStyle(color: AppColors.statusDanger))
          else ...[
            Card(
              margin: EdgeInsets.zero,
              color: AppColors.statusWarning.withValues(alpha: 0.10),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: AppColors.statusWarning,
                  child: Icon(Icons.workspace_premium, color: Colors.white),
                ),
                title: Text(_leaderId == null ? 'اختر قائد المشروع *' : _nameOf(_leaderId!, pickers)),
                subtitle: const Text('قائد المشروع'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: pickers == null
                    ? null
                    : () async {
                        final picked = await _showSelectionSheet(
                          context,
                          title: 'قائد المشروع',
                          options: _people(pickers),
                          selected: _leaderId == null ? [] : [_leaderId!],
                          single: true,
                        );
                        if (picked == null || picked.isEmpty || !mounted) return;
                        final next = picked.first;
                        setState(() {
                          // القائد السابق يبقى عضواً في الفريق بدل أن يخرج فجأة.
                          if (_leaderId != null && _leaderId != next) {
                            _memberIds = [..._memberIds.where((x) => x != next), _leaderId!];
                          }
                          _leaderId = next;
                        });
                      },
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in members)
                  InputChip(
                    label: Text(_nameOf(id, pickers)),
                    onDeleted: () => setState(() => _memberIds = _memberIds.where((x) => x != id).toList()),
                    deleteButtonTooltipMessage: 'إزالة',
                  ),
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt_1, size: 18),
                  label: Text(members.isEmpty ? 'إضافة أعضاء' : 'تعديل الأعضاء'),
                  onPressed: pickers == null
                      ? null
                      : () async {
                          final picked = await _showSelectionSheet(
                            context,
                            title: 'أعضاء الفريق',
                            options: _people(pickers).where((o) => o.id != _leaderId).toList(),
                            selected: members,
                          );
                          if (picked != null && mounted) setState(() => _memberIds = picked);
                        },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── الإدارات (اختياري) ──
            Text('الإدارات المسؤولة (اختياري)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('يمكن الاكتفاء بالفريق، أو ربط إدارة أو أكثر — موظفو الإدارة المرتبطة يتابعون المشروع ويديرون خطواته.', style: muted),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in _departmentIds)
                  InputChip(
                    avatar: const Icon(Icons.apartment, size: 16),
                    label: Text(pickers?.departments.where((d) => d.id == id).map((d) => d.name).firstOrNull ??
                        widget.project?.departments.where((d) => d.id == id).map((d) => d.name).firstOrNull ??
                        '—'),
                    onDeleted: () => setState(() => _departmentIds = _departmentIds.where((x) => x != id).toList()),
                    deleteButtonTooltipMessage: 'إزالة',
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_business_outlined, size: 18),
                  label: Text(_departmentIds.isEmpty ? 'ربط إدارة' : 'تعديل الإدارات'),
                  onPressed: pickers == null
                      ? null
                      : () async {
                          final picked = await _showSelectionSheet(
                            context,
                            title: 'الإدارات المسؤولة',
                            options: pickers.departments.map((d) => _Option(d.id, d.name, '')).toList(),
                            selected: _departmentIds,
                          );
                          if (picked != null && mounted) setState(() => _departmentIds = picked);
                        },
                ),
              ],
            ),
          ],
          if (!_isEdit && !widget.isFullAccess) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _submitNow,
              onChanged: (v) => setState(() => _submitNow = v),
              title: const Text('إرسال للمدير التنفيذي للاعتماد فوراً'),
              subtitle: const Text('أو احفظه مسودة وأرسله لاحقاً'),
            ),
          ],
        ],
      ),
    );
  }
}
