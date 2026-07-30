import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:intl/intl.dart';
// V23: image_picker removed — evidence/attachments no longer in employee form

class MobileDisputesPage extends ConsumerWidget {
  const MobileDisputesPage({this.highlightId, super.key});
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(myDisputePortalProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الشكاوى ولجنة الخلافات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        tooltip: 'شكوى جديدة',
        icon: const Icon(Icons.add),
        label: const Text('شكوى جديدة'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myDisputePortalProvider),
        child: portal.when(
          loading: () => ListView(
            children: [
              const SizedBox(height: 240),
              const Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 40,
                        color: Theme.of(context).colorScheme.error,
                        semanticLabel: 'خطأ',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        humanizeError(error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () =>
                            ref.invalidate(myDisputePortalProvider),
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          data: (data) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const MobileSectionHeader(title: 'قضاياي'),
              const SizedBox(height: 10),
              if (data.cases.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.gavel_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          semanticLabel: 'لا توجد شكاوى',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'لا توجد شكاوى أو قضايا مرتبطة بحسابك.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'يمكنك تقديم شكوى جديدة بسرية عبر الزر أدناه.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...data.cases.map(
                  (item) => _CaseCard(
                    item: item,
                    isHighlighted: item.id == highlightId,
                    onCancel: item.canCancel
                        ? () => _cancel(context, ref, item)
                        : null,
                    onRespond: item.status == 'needs_more_information'
                        ? () => _respondToInfoRequest(context, ref, item)
                        : null,
                  ),
                ),
              if (data.decisions.isNotEmpty) ...[
                const SizedBox(height: 22),
                const MobileSectionHeader(title: 'القرارات الصادرة'),
                const SizedBox(height: 10),
                ...data.decisions.map(
                  (item) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.decisionNumber,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Text(item.decisionText),
                          const SizedBox(height: 6),
                          Text(
                            'الأسباب: ${item.rationale}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (item.canAppeal)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => _appeal(context, ref, item),
                                icon: const Icon(Icons.rate_review_outlined),
                                label: const Text('تقديم اعتراض'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (data.appeals.isNotEmpty) ...[
                const SizedBox(height: 22),
                const MobileSectionHeader(title: 'اعتراضاتي'),
                ...data.appeals.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.reason),
                      subtitle: Text(
                        DateFormat('d MMM y', 'ar').format(item.submittedAt),
                      ),
                      trailing: MobileStatusPill(item.status),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _NewDisputeForm()),
    );
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تقديم الشكوى بسرية.')));
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    MobileDisputeCase item,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إلغاء الشكوى'),
        content: TextField(
          controller: reason,
          decoration: const InputDecoration(labelText: 'سبب الإلغاء'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إلغاء الشكوى'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    if (reason.text.trim().length < 5) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى إدخال 5 أحرف على الأقل لسبب الإلغاء')),
        );
      }
      reason.dispose();
      return;
    }
    try {
      await ref.read(mobileCommandsProvider).cancelDispute(item.id, reason.text);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _appeal(
    BuildContext context,
    WidgetRef ref,
    MobileDisputeDecision item,
  ) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('اعتراض على القرار'),
        content: TextField(
          controller: reason,
          minLines: 4,
          maxLines: 7,
          decoration: const InputDecoration(labelText: 'أسباب الاعتراض'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تقديم الاعتراض'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      return;
    }
    if (reason.text.trim().length < 20) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى كتابة 20 حرفًا على الأقل لأسباب الاعتراض'),
          ),
        );
      }
      reason.dispose();
      return;
    }
    try {
      await ref
          .read(mobileCommandsProvider)
          .appealDisputeDecision(item.id, reason.text);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      reason.dispose();
    }
  }

  Future<void> _respondToInfoRequest(
    BuildContext context,
    WidgetRef ref,
    MobileDisputeCase item,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RespondToInfoRequestSheet(caseId: item.id),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.item, this.isHighlighted = false, this.onCancel, this.onRespond});

  final MobileDisputeCase item;
  final bool isHighlighted;
  final VoidCallback? onCancel;
  final VoidCallback? onRespond;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: isHighlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      color: isHighlighted ? scheme.primaryContainer.withValues(alpha: .15) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                MobileStatusPill(item.status),
              ],
            ),
            if (item.caseNumber != null)
              Text(
                item.caseNumber!,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            const SizedBox(height: 6),
            if (item.description != null)
              Text(
                item.description!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Text(
              'فُتحت ${DateFormat('d MMM y', 'ar').format(item.openedAt)}'
              '${item.respondentName == null ? '' : ' · الطرف الآخر: ${item.respondentName}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (onCancel != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('إلغاء قبل القبول'),
                ),
              ),
            if (onRespond != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.icon(
                  onPressed: onRespond,
                  icon: const Icon(Icons.reply),
                  label: const Text('الرد على طلب المعلومات'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _caseTypes = <String, String>{
  'employee_conflict': 'خلاف بين موظفين',
  'inappropriate_conduct': 'سلوك غير لائق',
  'verbal_abuse': 'إساءة لفظية',
  'management_chain': 'مشكلة مع سلسلة الإدارة',
  'direct_manager': 'مشكلة مع المدير المباشر',
  'department_conflict': 'خلاف بين إدارات',
  'misunderstanding': 'سوء تفاهم',
  'work_environment': 'بيئة العمل',
  'donor_beneficiary': 'متعلقة بمتبرع أو مستفيد',
  'administrative_violation': 'مخالفة إدارية',
  'agreement_breach': 'إخلال باتفاق',
  'other': 'أخرى',
};

// V23: _priorities removed — employee form no longer has priority field
// V23: priority is always 'normal' server-side via submit_my_dispute_v23

/// V23: عدد الكلمات — يطابق word_count() في الخادم
int _wordCount(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  return trimmed.split(RegExp(r'\s+')).length;
}

class _NewDisputeForm extends ConsumerStatefulWidget {
  const _NewDisputeForm();

  @override
  ConsumerState<_NewDisputeForm> createState() => _NewDisputeFormState();
}

class _NewDisputeFormState extends ConsumerState<_NewDisputeForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  // V23: _location removed — incident_location no longer in employee form
  // V23: _requestedAction removed — requested_action no longer in employee form

  String _type = 'employee_conflict';
  // V23: _priority removed — always 'normal' server-side
  final List<DisputeDirectoryEmployee> _respondents = [];
  final List<DisputeDirectoryEmployee> _witnesses = [];
  // V23: _attachments removed — evidence/attachments no longer in employee form
  bool _truthConfirmed = false;
  bool _confidentialityAccepted = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refresh);
    _description.addListener(_refresh);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    // V23: _location.dispose() and _requestedAction.dispose() removed
    super.dispose();
  }

  void _refresh() => setState(() {});

  // V23: validation uses word count (3–300 words) instead of character count
  bool get _canSubmit =>
      !_submitting &&
      _title.text.trim().length >= 3 &&
      _wordCount(_description.text) >= 3 &&
      _wordCount(_description.text) <= 300 &&
      _respondents.isNotEmpty &&
      _truthConfirmed &&
      _confidentialityAccepted;

  Future<void> _pickPeople({required bool witnesses}) async {
    final selectedIds = {
      for (final e in (witnesses ? _witnesses : _respondents)) e.id,
    };
    final excludeIds = {
      for (final e in (witnesses ? _respondents : _witnesses)) e.id,
    };
    final result = await showModalBottomSheet<DisputeDirectoryEmployee>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DirectoryPicker(
        title: witnesses ? 'إضافة شاهد' : 'إضافة طرف',
        selectedIds: selectedIds,
        excludeIds: excludeIds,
      ),
    );
    if (result == null) return;
    setState(() {
      final list = witnesses ? _witnesses : _respondents;
      if (!list.any((e) => e.id == result.id)) list.add(result);
    });
  }

  Future<void> _confirmAndSubmit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تقديم الشكوى'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('النوع', _caseTypes[_type] ?? _type),
              // V23: priority row removed
              _summaryRow('العنوان', _title.text.trim()),
              _summaryRow(
                'الأطراف',
                _respondents.map((e) => e.name).join('، '),
              ),
              if (_witnesses.isNotEmpty)
                _summaryRow(
                  'الشهود',
                  _witnesses.map((e) => e.name).join('، '),
                ),
              // V23: attachments row removed
              const SizedBox(height: 8),
              const Text(
                'سيتم تقديم الشكوى بسرية إلى لجنة حل المشكلات. لن يتم إشعار الطرف'
                'الآخر إلا بعد قبول اللجنة للشكوى وقرارها بذلك.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('مراجعة'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('تأكيد وتقديم'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    try {
      // V23: use submitDisputeV23 — no priority, location, requestedAction, attachments
      await ref
          .read(mobileCommandsProvider)
          .submitDisputeV23(
            title: _title.text,
            description: _description.text,
            caseType: _type,
            respondentIds: _respondents.map((e) => e.id).toList(),
            witnessIds: _witnesses.map((e) => e.id).toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final descWords = _wordCount(_description.text);
    return Scaffold(
      appBar: AppBar(title: const Text('تقديم شكوى')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(labelText: 'نوع الشكوى'),
              items: [
                for (final entry in _caseTypes.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? 'employee_conflict'),
            ),
            // V23: priority dropdown removed
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'عنوان واضح',
                helperText: '3 أحرف على الأقل',
              ),
              validator: (value) =>
                  (value ?? '').trim().length < 3 ? 'العنوان قصير جدًا' : null,
            ),
            const SizedBox(height: 12),
            // V23: description uses word count (3–300 كلمة) instead of character count
            TextFormField(
              controller: _description,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'التفاصيل',
                hintText: 'اكتب الوقائع والتوقيت وما تطلبه من اللجنة',
                helperText: '٣–٣٠٠ كلمة (الآن: $descWords)',
              ),
              validator: (value) {
                final words = _wordCount(value ?? '');
                if (words < 3) return 'التفاصيل غير كافية (٣ كلمات على الأقل)';
                if (words > 300) return 'التفاصيل طويلة جدًا (٣٠٠ كلمة كحد أقصى)';
                return null;
              },
            ),
            // V23: incident_location field removed
            // V23: requested_action field removed
            // V23: attachments picker removed
            const SizedBox(height: 18),
            _peopleSection(
              label: 'الأطراف المعنية',
              hint: 'اختر طرفًا واحدًا على الأقل',
              people: _respondents,
              onAdd: () => _pickPeople(witnesses: false),
              onRemove: (e) => setState(() => _respondents.remove(e)),
              required: true,
            ),
            const SizedBox(height: 14),
            _peopleSection(
              label: 'الشهود (اختياري)',
              hint: 'أضف شهودًا إن وجدوا',
              people: _witnesses,
              onAdd: () => _pickPeople(witnesses: true),
              onRemove: (e) => setState(() => _witnesses.remove(e)),
              required: false,
            ),
            const SizedBox(height: 18),
            CheckboxListTile(
              value: _truthConfirmed,
              onChanged: (v) => setState(() => _truthConfirmed = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('أقر بأن ما ورد في الشكوى صحيح.'),
            ),
            CheckboxListTile(
              value: _confidentialityAccepted,
              onChanged: (v) =>
                  setState(() => _confidentialityAccepted = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('أوافق على سرية الإجراءات وحماية الأطراف.'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _canSubmit ? _confirmAndSubmit : null,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('مراجعة وتقديم بسرية'),
          ),
        ),
      ),
    );
  }

  Widget _peopleSection({
    required String label,
    required String hint,
    required List<DisputeDirectoryEmployee> people,
    required VoidCallback onAdd,
    required void Function(DisputeDirectoryEmployee) onRemove,
    required bool required,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('إضافة'),
            ),
          ],
        ),
        if (people.isEmpty)
          Text(
            hint,
            style: TextStyle(
              color: required
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).textTheme.bodySmall?.color,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in people)
                Chip(
                  label: Text(e.name),
                  onDeleted: () => onRemove(e),
                ),
            ],
          ),
      ],
    );
  }
}

class _DirectoryPicker extends ConsumerStatefulWidget {
  const _DirectoryPicker({
    required this.title,
    required this.selectedIds,
    required this.excludeIds,
  });

  final String title;
  final Set<String> selectedIds;
  final Set<String> excludeIds;

  @override
  ConsumerState<_DirectoryPicker> createState() => _DirectoryPickerState();
}

class _DirectoryPickerState extends ConsumerState<_DirectoryPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final directory = ref.watch(disputeDirectoryProvider(_search));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'بحث بالاسم أو الرقم الوظيفي',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: directory.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) =>
                  Center(child: Text(humanizeError(error))),
              data: (people) {
                final visible = people
                    .where((e) => !widget.excludeIds.contains(e.id))
                    .toList(growable: false);
                if (visible.isEmpty) {
                  return const Center(child: Text('لا توجد نتائج.'));
                }
                return ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (_, index) {
                    final person = visible[index];
                    final already = widget.selectedIds.contains(person.id);
                    return ListTile(
                      title: Text(person.name),
                      subtitle: Text(
                        [
                          if (person.employeeCode != null) person.employeeCode!,
                          if (person.department != null) person.department!,
                        ].join(' · '),
                      ),
                      trailing: already
                          ? const Tooltip(
                              message: 'مضاف بالفعل',
                              child: Icon(
                                Icons.check,
                                color: Color(0xFF0F9F6E),
                              ),
                            )
                          : const Tooltip(
                              message: 'إضافة',
                              child: Icon(Icons.add),
                            ),
                      enabled: !already,
                      onTap: already
                          ? null
                          : () => Navigator.pop(context, person),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ورقة الرد على طلب معلومات إضافية من اللجنة
class _RespondToInfoRequestSheet extends ConsumerStatefulWidget {
  const _RespondToInfoRequestSheet({required this.caseId});
  final String caseId;

  @override
  ConsumerState<_RespondToInfoRequestSheet> createState() =>
      _RespondToInfoRequestSheetState();
}

class _RespondToInfoRequestSheetState
    extends ConsumerState<_RespondToInfoRequestSheet> {
  final _response = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _response.text.trim();
    if (text.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة 10 أحرف على الأقل')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(mobileCommandsProvider).transitionDisputeCase(
            caseId: widget.caseId,
            action: 'resume',
            reason: text,
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الرد بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('الرد على طلب المعلومات',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'اللجنة طلبت معلومات إضافية حول قضيتك. اكتب ردك أدناه.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _response,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'ردك على طلب المعلومات',
              hintText: 'اكتب المعلومات المطلوبة هنا...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: const Text('إرسال الرد'),
            ),
          ),
        ],
      ),
    );
  }
}
