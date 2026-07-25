import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class MobileDisputesPage extends ConsumerWidget {
  const MobileDisputesPage({super.key});

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
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
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
                    onCancel: item.canCancel
                        ? () => _cancel(context, ref, item)
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
    if (confirmed != true || reason.text.trim().length < 5) return;
    await ref.read(mobileCommandsProvider).cancelDispute(item.id, reason.text);
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
    if (confirmed != true || reason.text.trim().length < 20) return;
    await ref
        .read(mobileCommandsProvider)
        .appealDisputeDecision(item.id, reason.text);
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({required this.item, this.onCancel});

  final MobileDisputeCase item;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => Card(
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
        ],
      ),
    ),
  );
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

const _priorities = <String, String>{
  'normal': 'عادية',
  'urgent': 'عاجلة',
};

class _NewDisputeForm extends ConsumerStatefulWidget {
  const _NewDisputeForm();

  @override
  ConsumerState<_NewDisputeForm> createState() => _NewDisputeFormState();
}

class _NewDisputeFormState extends ConsumerState<_NewDisputeForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _location = TextEditingController();
  final _requestedAction = TextEditingController();

  String _type = 'employee_conflict';
  String _priority = 'normal';
  final List<DisputeDirectoryEmployee> _respondents = [];
  final List<DisputeDirectoryEmployee> _witnesses = [];
  List<XFile> _attachments = [];
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
    _location.dispose();
    _requestedAction.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  bool get _canSubmit =>
      !_submitting &&
      _title.text.trim().length >= 3 &&
      _description.text.trim().length >= 3 &&
      _description.text.trim().length <= 300 &&
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
              _summaryRow('الأولوية', _priorities[_priority] ?? _priority),
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
              if (_attachments.isNotEmpty)
                _summaryRow('المرفقات', '${_attachments.length} مرفق'),
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
    String? createdCaseId;
    try {
      createdCaseId = await ref
          .read(mobileCommandsProvider)
          .submitDispute(
            title: _title.text,
            description: _description.text,
            caseType: _type,
            priority: _priority,
            respondentIds: _respondents.map((e) => e.id).toList(),
            witnessIds: _witnesses.map((e) => e.id).toList(),
            incidentLocation: _location.text.trim().isEmpty
                ? null
                : _location.text,
            requestedAction: _requestedAction.text.trim().isEmpty
                ? null
                : _requestedAction.text,
          );
      for (final attachment in _attachments) {
        final bytes = await attachment.readAsBytes();
        if (bytes.length > 15 * 1024 * 1024) {
          throw StateError('ATTACHMENT_TOO_LARGE');
        }
        await ref.read(mobileCommandsProvider).uploadDisputeEvidence(
              caseId: createdCaseId,
              bytes: bytes,
              fileName: attachment.name,
              mimeType: attachment.mimeType ?? '',
            );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        if (createdCaseId != null) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop(true);
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'تم تقديم المشكلة، لكن تعذر رفع أحد المرفقات. يمكنك إضافته لاحقًا من تفاصيل القضية.',
              ),
            ),
          );
          return;
        }
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _priority,
              decoration: const InputDecoration(labelText: 'الأولوية'),
              items: [
                for (final entry in _priorities.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) =>
                  setState(() => _priority = value ?? 'normal'),
            ),
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
            TextFormField(
              controller: _description,
              minLines: 5,
              maxLines: 8,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'التفاصيل',
                hintText: 'اكتب الوقائع والتوقيت وما تطلبه من اللجنة',
                helperText: '3–300 حرف',
              ),
              validator: (value) {
                final len = (value ?? '').trim().length;
                if (len < 3) return 'التفاصيل غير كافية (3 أحرف على الأقل)';
                if (len > 300) return 'التفاصيل طويلة جدًا (300 حرف كحد أقصى)';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'مكان الواقعة (اختياري)',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _requestedAction,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'ما الذي تطلبه من اللجنة؟ (اختياري)',
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _submitting
                  ? null
                  : () async {
                      final picked = await ImagePicker().pickMultiImage(
                        imageQuality: 82,
                        limit: 5,
                        requestFullMetadata: false,
                      );
                      if (picked.isNotEmpty) {
                        setState(() => _attachments = picked.take(5).toList());
                      }
                    },
              icon: const Icon(Icons.attach_file_rounded),
              label: Text(
                _attachments.isEmpty
                    ? 'إضافة مرفقات أو أدلة (اختياري)'
                    : '${_attachments.length} مرفق محدد',
              ),
            ),
            if (_attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _attachments.map((file) => file.name).join('، '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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
