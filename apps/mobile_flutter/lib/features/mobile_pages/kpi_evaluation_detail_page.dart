import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Arabic labels for kpi_evaluations.workflow_status (migration 0058 + V23 migration 0163).
/// Shared by the KPI list and detail pages so both stay in sync.
String kpiWorkflowLabel(String value) => switch (value) {
  'DRAFT' => 'مسودة قبل فتح الدورة',
  'OPEN_FOR_SELF_EVALUATION' => 'مفتوح للتقييم الذاتي',
  'SUBMITTED_TO_DIRECT_MANAGER' => 'أُرسل إلى المدير المباشر',
  'SUBMITTED_TO_HR' => 'أُرسل إلى الموارد البشرية',
  'MANAGER_REVIEW' => 'قيد مراجعة المدير المباشر',
  'HR_REVIEW' => 'قيد مراجعة الموارد البشرية',
  'RETURNED_TO_MANAGER_FOR_FINAL_APPROVAL' =>
    'عاد إلى المدير للاعتماد النهائي',
  'MANAGER_APPROVED' => 'اعتمده المدير المباشر',
  'INCLUDED_IN_MONTHLY_REPORT' => 'مدرج في التقرير الشهري',
  'CYCLE_CLOSED' => 'أُغلقت الدورة',
  'ARCHIVED' => 'مؤرشف',
  'NOT_STARTED' => 'لم تبدأ',
  'EMPLOYEE_INPUT_IN_PROGRESS' => 'الموظف يُدخل بياناته',
  'HR_DATA_PENDING' => 'بانتظار تجهيز بيانات HR',
  'SESSION_SCHEDULED' => 'الجلسة مجدولة',
  'SESSION_COMPLETED' => 'تمت الجلسة',
  'MANAGER_EVALUATION_IN_PROGRESS' => 'تقييم المدير جارٍ',
  'HR_EVALUATION_IN_PROGRESS' => 'تقييم HR جارٍ',
  'EMPLOYEE_ACKNOWLEDGEMENT_PENDING' => 'بانتظار اطلاع الموظف',
  'EMPLOYEE_ACKNOWLEDGED' => 'أقرّ الموظف بالاطلاع',
  'FINAL_REVIEW' => 'قيد المراجعة النهائية',
  'SENT_TO_EXECUTIVE_DIRECTOR' => 'مُرسل للمدير التنفيذي',
  'RETURNED_FOR_REVISION' => 'أُعيد للتصحيح',
  'APPROVED' => 'معتمد',
  'CLOSED' => 'مؤرشف',
  'OVERDUE' => 'متأخر عن الموعد',
  // V23: حالات المسار المتوازي
  'PARALLEL_REVIEW_IN_PROGRESS' => 'مراجعة HR والمدير جارية بالتوازي',
  'HR_COMPLETED' => 'أنهى HR مراجعته — بانتظار المدير',
  'MANAGER_COMPLETED' => 'أنهى المدير مراجعته — بانتظار HR',
  'SECRETARY_REVIEW' => 'قيد مراجعة السكرتير التنفيذي',
  'EXECUTIVE_REVIEW' => 'بانتظار إقرار المدير التنفيذي',
  'EXECUTIVE_ACKNOWLEDGED' => 'أقرّ المدير التنفيذي',
  'RETURNED_BY_EXECUTIVE' => 'أعاده المدير التنفيذي للمراجعة',
  _ => value,
};

class KpiEvaluationDetailPage extends ConsumerStatefulWidget {
  const KpiEvaluationDetailPage({required this.evaluationId, super.key});
  final String evaluationId;

  @override
  ConsumerState<KpiEvaluationDetailPage> createState() =>
      _KpiEvaluationDetailPageState();
}

class _KpiEvaluationDetailPageState
    extends ConsumerState<KpiEvaluationDetailPage> {
  final Map<String, double> _scores = {};
  final Map<String, TextEditingController> _criterionNotes = {};
  final _generalNote = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _criterionNotes.values) {
      controller.dispose();
    }
    _generalNote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncForm = ref.watch(kpiEvaluationFormProvider(widget.evaluationId));
    return Scaffold(
      appBar: AppBar(title: const Text('تفاصيل التقييم')),
      body: SafeArea(
        child: asyncForm.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    humanizeError(error),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(
                      kpiEvaluationFormProvider(widget.evaluationId),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (form) {
            _initialize(form);
            return _content(form);
          },
        ),
      ),
    );
  }

  void _initialize(KpiEvaluationForm form) {
    if (_initialized) return;
    final stage = form.editableStage;
    for (final criterion in form.criteria) {
      final own = stage == null ? null : criterion.stageScores[stage];
      final fallback =
          criterion.stageScores['manager'] ?? criterion.stageScores['self'];
      _scores[criterion.id] = own?.score ?? fallback?.score ?? 0;
      _criterionNotes[criterion.id] = TextEditingController(
        text: own?.note ?? '',
      );
    }
    _initialized = true;
  }

  Widget _content(KpiEvaluationForm form) {
    // V23: في المراجعة المتوازية، الموظف يمكنه تعديل الدرجات أيضًا.
    final canEditScores =
        form.editableStage == 'self' ||
        form.editableStage == 'manager_review' ||
        form.editableStage == 'parallel_review';
    final canAct = form.editableStage != null && !form.locked;
    // V23: إظهار الامتثال والجلسة في المراجعة المتوازية.
    final isParallel = form.editableStage == 'parallel_review';
    final showCompliance = form.editableStage == 'hr_review' || isParallel;
    final showSession = form.editableStage == 'manager_review' || isParallel;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  form.employeeName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${form.employeeCode ?? 'بدون كود'} · ${DateFormat('MMMM y', 'ar').format(form.periodMonth)}',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('المرحلة: ${_stage(form.currentStage)}'),
                    if (form.editableStage != null)
                      _chip('دورك: ${_stage(form.editableStage!)}'),
                    if (form.locked) const MobileStatusPill('closed'),
                    if (form.finalScore != null)
                      _chip('النتيجة ${form.finalScore!.toStringAsFixed(1)}%'),
                    if (form.parallelFlow == true)
                      _chip('مسار V23 المتوازي'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _workflow(form.workflowStatus),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // V23: مؤشر تقدم المراجعة المتوازية.
        if (form.currentStage == 'parallel_review') ...[
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.sync_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'HR ${form.hrCompleted == true ? '✓' : '⏳'} · المدير ${form.managerCompleted == true ? '✓' : '⏳'}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _KpiStageStepper(
          currentStage: form.currentStage,
          parallelFlow: form.parallelFlow,
        ),
        const SizedBox(height: 12),
        if (form.goals.isNotEmpty) ...[
          const MobileSectionHeader(title: 'الأهداف — 40 درجة'),
          const SizedBox(height: 8),
          for (final goal in form.goals) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            goal.title,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          '${goal.calculatedScore.toStringAsFixed(1)}/${goal.weight.toStringAsFixed(0)}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'المستهدف ${goal.targetValue} ${goal.unit} · المحقق ${goal.achievedValue}',
                    ),
                    if (form.editableStage == 'self') ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _editGoal(form, goal),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('تحديث الإنجاز والأدلة'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        // V23: تسجيل الجلسة متاح في المراجعة المتوازية أيضًا.
        if (showSession) ...[
          FilledButton.tonalIcon(
            onPressed: _saving ? null : () => _recordSession(form),
            icon: const Icon(Icons.groups_outlined),
            label: const Text('تسجيل جلسة الموظف والمدير'),
          ),
          const SizedBox(height: 12),
        ],
        for (final criterion in form.criteria) ...[
          _criterionCard(criterion, form.editableStage, canEditScores),
          const SizedBox(height: 10),
        ],
        if (form.attendance != null) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تفاصيل الحضور المحسوبة تلقائيًا',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'تأخير: ${form.attendance!.lateCount} · انصراف مبكر: ${form.attendance!.earlyLeaveCount} · غياب: ${form.attendance!.unexcusedAbsenceCount}',
                  ),
                  Text(
                    'نقص ساعات: ${form.attendance!.shortagePenalty} · بصمة ناقصة: ${form.attendance!.missingPunchCount}',
                  ),
                  Text(
                    'الدرجة: ${form.attendance!.score}/20${form.attendance!.hasPendingItems ? ' · توجد مراجعات معلقة' : ''}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // V23: الامتثال متاح في المراجعة المتوازية أيضًا.
        if (showCompliance) ...[
          for (final metric in const ['PRAYER', 'HALAQA']) ...[
            OutlinedButton.icon(
              onPressed: _saving ? null : () => _editCompliance(form, metric),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                metric == 'PRAYER'
                    ? 'تسجيل الالتزام بالصلاة'
                    : 'تسجيل حضور حلقة الشيخ وليد يوسف',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (form.validationErrors.isNotEmpty) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'متطلبات الاعتماد غير المكتملة',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...form.validationErrors.map(
                    (item) => Text(
                      '• $item',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (canAct) ...[
          TextField(
            controller: _generalNote,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'ملاحظة عامة للمرحلة',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (form.editableStage != 'self')
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : () => _returnStage(form),
                    icon: const Icon(Icons.undo),
                    label: const Text('إعادة للمرحلة السابقة'),
                  ),
                ),
              if (form.editableStage != 'self') const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : () => _submit(form),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_submitLabel(form.editableStage)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ] else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'هذه المرحلة للعرض فقط أو تم إغلاق التقييم.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  // V23: تسميات أزرار الاعتماد حسب المرحلة.
  String _submitLabel(String? stage) => switch (stage) {
    'manager_review' => 'اعتماد النتيجة وإدراجها في التقرير',
    'parallel_review' => 'اعتماد مراجعتي وإرسال',
    'secretary_review' => 'اعتماد وإرسال للمدير التنفيذي',
    'executive_review' => 'إقرار واعتماد نهائي',
    _ => 'حفظ وإرسال',
  };

  Widget _criterionCard(
    KpiCriterionForm criterion,
    String? editableStage,
    bool canEditScores,
  ) {
    final value = (_scores[criterion.id] ?? 0)
        .clamp(0, criterion.maxScore)
        .toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    criterion.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text('الوزن ${criterion.weight.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 12),
            if (criterion.stageScores.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: criterion.stageScores.entries
                    .map((entry) {
                      return _chip(
                        '${_stage(entry.key)}: ${entry.value.score?.toStringAsFixed(1) ?? '—'}',
                      );
                    })
                    .toList(growable: false),
              ),
            if (canEditScores && criterion.editable) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: 'درجة معيار ${criterion.name}',
                      value: value.toStringAsFixed(1),
                      child: Slider(
                        value: value,
                        min: 0,
                        max: criterion.maxScore,
                        divisions: criterion.maxScore
                            .round()
                            .clamp(1, 100)
                            .toInt(),
                        label: value.toStringAsFixed(1),
                        onChanged: (newValue) =>
                            setState(() => _scores[criterion.id] = newValue),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 58,
                    child: Text(
                      '${value.toStringAsFixed(1)}/${criterion.maxScore.toStringAsFixed(0)}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _criterionNotes[criterion.id],
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة على المعيار',
                ),
              ),
            ] else if (editableStage != null) ...[
              const SizedBox(height: 10),
              const Text(
                'راجع الدرجات والملاحظات، ثم اعتمد أو أعد التقييم للمرحلة السابقة.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(KpiEvaluationForm form) async {
    final stage = form.editableStage;
    if (stage == null) return;
    // V23: إرسال الدرجات في مراحل التقييم الذاتي والمدير والمراجعة المتوازية.
    final scorePayload = stage == 'self' || stage == 'manager_review' || stage == 'parallel_review'
        ? form.criteria
              .where((criterion) => criterion.editable)
              .map(
                (criterion) => {
                  'criterion_id': criterion.id,
                  'score': _scores[criterion.id],
                  'note': _criterionNotes[criterion.id]?.text.trim(),
                },
              )
              .toList(growable: false)
        : null;
    setState(() => _saving = true);
    try {
      await ref
          .read(mobileCommandsProvider)
          .advanceKpi(
            form.id,
            stage,
            _generalNote.text.trim(),
            scores: scorePayload,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ التقييم ونقله للمرحلة التالية.'),
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _returnStage(KpiEvaluationForm form) async {
    // V23: أهداف الإرجاع حسب المرحلة — المتوازي يرجع للموظف، السكرتير للمتوازي، التنفيذي للسكرتير.
    final target = switch (form.editableStage) {
      'hr_review' => 'self',
      'manager_review' => 'hr_review',
      'parallel_review' => 'self',
      'secretary_review' => 'parallel_review',
      'executive_review' => 'secretary_review',
      _ => null,
    };
    if (target == null) return;
    if (_generalNote.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اكتب سبب الإعادة بوضوح أولًا.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(mobileCommandsProvider)
          .returnKpi(form.id, target, _generalNote.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إعادة التقييم للمرحلة السابقة.')),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _chip(String text) => Chip(label: Text(text));

  // V23: أضفنا المراحل الجديدة.
  String _stage(String value) => switch (value) {
    'self' => 'الموظف',
    'hr' => 'الموارد البشرية',
    'hr_review' => 'مراجعة الموارد البشرية',
    'manager' => 'المدير المباشر',
    'manager_review' => 'مراجعة المدير المباشر',
    'parallel_review' => 'مراجعة متوازية',
    'manager_final' => 'اعتماد المدير النهائي',
    'secretary_review' => 'مراجعة السكرتير',
    'executive_review' => 'إقرار المدير التنفيذي',
    'finalized' => 'مدرج في التقرير الشهري',
    'closed' => 'مغلق',
    'archived' => 'مؤرشف',
    _ => value,
  };

  // Arabic labels for kpi_evaluations.workflow_status (migration 0058 + V23).
  String _workflow(String value) => kpiWorkflowLabel(value);

  Future<void> _editGoal(KpiEvaluationForm form, KpiGoalForm goal) async {
    final achieved = TextEditingController(text: goal.achievedValue.toString());
    final evidence = TextEditingController(text: goal.evidenceSource ?? '');
    final note = TextEditingController(text: goal.employeeNote ?? '');
    var status = goal.status;
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(goal.title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: achieved,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'القيمة المحققة',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: status,
                  items: const [
                    DropdownMenuItem(
                      value: 'NOT_STARTED',
                      child: Text('لم يبدأ'),
                    ),
                    DropdownMenuItem(
                      value: 'IN_PROGRESS',
                      child: Text('قيد التنفيذ'),
                    ),
                    DropdownMenuItem(value: 'COMPLETED', child: Text('مكتمل')),
                    DropdownMenuItem(
                      value: 'PARTIALLY_COMPLETED',
                      child: Text('مكتمل جزئيًا'),
                    ),
                    DropdownMenuItem(value: 'BLOCKED', child: Text('متعثر')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => status = value ?? status),
                  decoration: const InputDecoration(labelText: 'الحالة'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: evidence,
                  decoration: const InputDecoration(
                    labelText: 'مصدر إثبات الإنجاز',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: note,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'ملاحظتك'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      setState(() => _saving = true);
      try {
        await ref
            .read(mobileCommandsProvider)
            .saveKpiGoalProgress(
              form.id,
              goal,
              achievedValue:
                  double.tryParse(achieved.text) ?? goal.achievedValue,
              status: status,
              evidenceSource: evidence.text.trim(),
              employeeNote: note.text.trim(),
            );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    achieved.dispose();
    evidence.dispose();
    note.dispose();
  }

  Future<void> _recordSession(KpiEvaluationForm form) async {
    final summary = TextEditingController();
    final strengths = TextEditingController();
    final improvements = TextEditingController();
    final nextGoals = TextEditingController();
    var mode = 'ONSITE';
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('جلسة التقييم'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: mode,
                  items: const [
                    DropdownMenuItem(value: 'ONSITE', child: Text('حضوريًا')),
                    DropdownMenuItem(value: 'REMOTE', child: Text('عن بُعد')),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => mode = value ?? mode),
                  decoration: const InputDecoration(labelText: 'طريقة الجلسة'),
                ),
                TextField(
                  controller: summary,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'ملخص المناقشة'),
                ),
                TextField(
                  controller: strengths,
                  decoration: const InputDecoration(labelText: 'نقاط القوة'),
                ),
                TextField(
                  controller: improvements,
                  decoration: const InputDecoration(labelText: 'نقاط التحسين'),
                ),
                TextField(
                  controller: nextGoals,
                  decoration: const InputDecoration(
                    labelText: 'أهداف الشهر القادم',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      setState(() => _saving = true);
      try {
        await ref.read(mobileCommandsProvider).saveKpiSession(form.id, {
          'scheduledAt': null,
          'heldAt': DateTime.now().toUtc().toIso8601String(),
          'mode': mode,
          'discussionSummary': summary.text.trim(),
          'strengths': strengths.text.trim(),
          'improvementPoints': improvements.text.trim(),
          'nextMonthGoals': nextGoals.text.trim(),
          'employeeNotes': null,
          'managerNotes': null,
          'employeeAttended': true,
          'managerAttended': true,
        });
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    summary.dispose();
    strengths.dispose();
    improvements.dispose();
    nextGoals.dispose();
  }

  Future<void> _editCompliance(KpiEvaluationForm form, String metric) async {
    final existing = form.compliance
        .where((item) => item.metric == metric)
        .firstOrNull;
    final required = TextEditingController(
      text: '${existing?.requiredCount ?? 0}',
    );
    final actual = TextEditingController(text: '${existing?.actualCount ?? 0}');
    final exempt = TextEditingController(text: '${existing?.exemptCount ?? 0}');
    final cancelled = TextEditingController(
      text: '${existing?.cancelledCount ?? 0}',
    );
    final note = TextEditingController(text: existing?.note ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(metric == 'PRAYER' ? 'الالتزام بالصلاة' : 'حضور الحلقة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: required,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العدد المطلوب'),
              ),
              TextField(
                controller: actual,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'العدد الفعلي'),
              ),
              TextField(
                controller: exempt,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'أعذار معتمدة'),
              ),
              TextField(
                controller: cancelled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ملغي إداريًا'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'ملاحظة HR'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حساب واعتماد'),
          ),
        ],
      ),
    );
    if (save == true) {
      setState(() => _saving = true);
      try {
        await ref
            .read(mobileCommandsProvider)
            .saveKpiCompliance(
              form.id,
              metric,
              int.tryParse(required.text) ?? 0,
              int.tryParse(actual.text) ?? 0,
              int.tryParse(exempt.text) ?? 0,
              int.tryParse(cancelled.text) ?? 0,
              note.text.trim(),
            );
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    required.dispose();
    actual.dispose();
    exempt.dispose();
    cancelled.dispose();
    note.dispose();
  }
}

class _KpiStageStepper extends StatelessWidget {
  const _KpiStageStepper({
    required this.currentStage,
    this.parallelFlow = false,
  });
  final String currentStage;
  final bool parallelFlow;

  // V23: المسار المتوازي يمر بمراحل مختلفة عن V17.
  List<(String, String)> get _stages => parallelFlow
      ? const [
          ('self', 'الموظف'),
          ('parallel_review', 'HR + المدير'),
          ('secretary_review', 'السكرتير'),
          ('executive_review', 'التنفيذي'),
          ('finalized', 'معتمد'),
        ]
      : const [
          ('self', 'الموظف'),
          ('hr_review', 'الموارد البشرية'),
          ('manager_review', 'المدير المباشر'),
          ('finalized', 'معتمد'),
        ];

  int _resolveIndex() {
    final stages = _stages;
    for (var i = 0; i < stages.length; i++) {
      if (stages[i].$1 == currentStage) return i;
    }
    // closed / archived → treat as fully completed
    if (currentStage == 'closed' || currentStage == 'archived') {
      return stages.length;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = _resolveIndex();
    final stages = _stages;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            for (var i = 0; i < stages.length; i++) ...[
              if (i > 0)
                Expanded(
                  child: Container(
                    height: 2,
                    color: i <= active
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < active
                          ? scheme.primary
                          : i == active
                              ? scheme.primaryContainer
                              : scheme.surfaceContainerHighest,
                      border: i == active
                          ? Border.all(color: scheme.primary, width: 2.5)
                          : null,
                    ),
                    child: Center(
                      child: i < active
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: scheme.onPrimary,
                            )
                          : Text(
                              '${i + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: i == active
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stages[i].$2,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight:
                          i == active ? FontWeight.w900 : FontWeight.w600,
                      color: i <= active
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
