import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class MobileRequestsPage extends ConsumerStatefulWidget {
  const MobileRequestsPage({this.focusRequestId, super.key});

  final String? focusRequestId;

  @override
  ConsumerState<MobileRequestsPage> createState() => _MobileRequestsPageState();
}

class _MobileRequestsPageState extends ConsumerState<MobileRequestsPage> {
  final _searchController = TextEditingController();
  String _search = '';
  String _status = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.focusRequestId != null) {
      return MobileRequestDetailPage(requestId: widget.focusRequestId!);
    }

    final requests = ref.watch(mobileRequestsProvider);
    final balances = ref.watch(myLeaveBalancesProvider);
    // تبويبات بلا إعادة تحميل: الإجازات/الطلبات + تكليفات العمل (البند 12).
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createRequest(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('طلب جديد'),
      ),
      body: _buildRequestsTab(context, requests, balances),
    );
  }

  Widget _buildRequestsTab(
    BuildContext context,
    AsyncValue<List<MobileRequest>> requests,
    AsyncValue<List<MobileLeaveBalance>> balances,
  ) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(mobileRequestsProvider),
      child: requests.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 260),
            Center(
              child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل'),
            ),
          ],
        ),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              humanizeError(error),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(mobileRequestsProvider),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
        data: (items) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            ...[
              const MobileSectionHeader(title: 'أرصدة الإجازات'),
              const SizedBox(height: 10),
              balances.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('تعذر تحميل الأرصدة الآن.'),
                data: (values) => SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: values.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final balance = values[index];
                      return SizedBox(
                        width: 190,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            // النقر على رصيد الإجازة يفتح الخدمة الذاتية
                            // حيث يُقدَّم طلب الإجازة الجديد.
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MobileSelfServicePage(),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    balance.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${balance.availableUnits.toStringAsFixed(balance.availableUnits % 1 == 0 ? 0 : 1)} متاح',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    'محجوز ${balance.reservedUnits.toStringAsFixed(1)} · مستهلك ${balance.consumedUnits.toStringAsFixed(1)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            const MobileSectionHeader(title: 'طلباتي'),
            const SizedBox(height: 10),
            MobileFilterBar(
              searchHint: 'بحث بالاسم أو العنوان أو رقم الطلب',
              controller: _searchController,
              onSearchChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
              options: const [
                MobileFilterOption('all', 'الكل'),
                MobileFilterOption('pending', 'قيد المراجعة'),
                MobileFilterOption('approved', 'معتمد'),
                MobileFilterOption('rejected', 'مرفوض'),
                MobileFilterOption('cancelled', 'ملغي'),
              ],
              selected: _status,
              onSelected: (value) => setState(() => _status = value),
              resultLabel:
                  '${items.where(_matches).length} من ${items.length} طلب',
              onClear: _search.isEmpty && _status == 'all'
                  ? null
                  : () {
                      _searchController.clear();
                      setState(() {
                        _search = '';
                        _status = 'all';
                      });
                    },
            ),
            const SizedBox(height: 12),
            if (items.where(_matches).isEmpty) ...[
              const SizedBox(height: 100),
              Center(
                child: Icon(
                  Icons.search_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  semanticLabel: 'لا توجد نتائج',
                ),
              ),
              const Center(child: Text('لا توجد طلبات مطابقة للفلاتر')),
            ] else
              ...items
                  .where(_matches)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RequestCard(item: item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  bool _matches(MobileRequest item) {
    final haystack =
        '${item.employeeName} ${item.title ?? ''} ${item.reason ?? ''} ${item.number}'
            .toLowerCase();
    return (_search.isEmpty || haystack.contains(_search)) &&
        (_status == 'all' || item.status == _status);
  }

  Future<void> _createRequest(BuildContext context, WidgetRef ref) async {
    List<DisputeDirectoryEmployee> substituteOptions = const [];
    try {
      substituteOptions = await ref.read(disputeDirectoryProvider('').future);
    } catch (_) {
      // The request remains usable if the optional directory is unavailable.
    }
    if (!context.mounted) return;
    var type = 'leave';
    var leaveType = 'annual';
    var permitKind = 'late_arrival';
    DateTime? startDate;
    DateTime? endDate;
    DateTime? permitDate;
    TimeOfDay? startTime;
    TimeOfDay? endTime;
    final title = TextEditingController();
    final reason = TextEditingController();
    final location = TextEditingController();
    final minutes = TextEditingController(text: '60');
    var substituteId = '';
    var attachments = <XFile>[];

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'إنشاء طلب جديد',
                  style: Theme.of(
                    sheetContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'نوع الطلب'),
                  items: const [
                    DropdownMenuItem(value: 'leave', child: Text('إجازة')),
                    DropdownMenuItem(value: 'mission', child: Text('مأمورية')),
                    DropdownMenuItem(value: 'permit', child: Text('طلب إذن')),
                    DropdownMenuItem(
                      value: 'attendance_correction',
                      child: Text('تصحيح حضور'),
                    ),
                    DropdownMenuItem(
                      value: 'convoy',
                      child: Text('تكليف قافلة'),
                    ),
                    DropdownMenuItem(
                      value: 'fundraising',
                      child: Text('فاندي'),
                    ),
                  ],
                  onChanged: (value) => setModalState(() {
                    type = value ?? 'leave';
                    startDate = null;
                    endDate = null;
                    permitDate = null;
                    startTime = null;
                    endTime = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (type == 'leave') ...[
                  DropdownButtonFormField<String>(
                    value: leaveType,
                    decoration: const InputDecoration(labelText: 'نوع الإجازة'),
                    items: const [
                      DropdownMenuItem(
                        value: 'annual',
                        child: Text('اعتيادية'),
                      ),
                      DropdownMenuItem(value: 'sick', child: Text('مرضية')),
                      DropdownMenuItem(
                        value: 'casual',
                        child: Text('عارضة / طارئة (تنفيذ فوري)'),
                      ),
                      DropdownMenuItem(
                        value: 'unpaid',
                        child: Text('بدون راتب'),
                      ),
                      DropdownMenuItem(
                        value: 'weekly_rest_comp',
                        child: Text('بدل راحة أسبوعية (يُخصم من رصيد البدل)'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => leaveType = value ?? 'annual'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (type == 'leave' ||
                    type == 'mission' ||
                    type == 'convoy' ||
                    type == 'fundraising') ...[
                  Row(
                    children: [
                      Expanded(
                        child: _DateButton(
                          label: 'من تاريخ',
                          value: startDate,
                          onPressed: () async {
                            final picked = await _pickDate(
                              sheetContext,
                              startDate,
                            );
                            if (picked != null) {
                              setModalState(() {
                                startDate = picked;
                                if (endDate != null &&
                                    endDate!.isBefore(picked)) {
                                  endDate = picked;
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DateButton(
                          label: 'إلى تاريخ',
                          value: endDate,
                          firstDate: startDate,
                          onPressed: () async {
                            final picked = await _pickDate(
                              sheetContext,
                              endDate ?? startDate,
                              firstDate: startDate,
                            );
                            if (picked != null) {
                              setModalState(() => endDate = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (type == 'mission' ||
                    type == 'convoy' ||
                    type == 'fundraising') ...[
                  TextField(
                    controller: location,
                    decoration: const InputDecoration(
                      labelText: 'المكان أو جهة التكليف',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _pickTime(
                              sheetContext,
                              startTime,
                            );
                            if (picked != null) {
                              setModalState(() {
                                startTime = picked;
                                if (endTime != null &&
                                    endTime!.isBefore(picked)) {
                                  endTime = picked;
                                }
                              });
                            }
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            startTime == null
                                ? 'من وقت (اختياري)'
                                : _formatTimeValue(startTime!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await _pickTime(
                              sheetContext,
                              endTime ?? startTime,
                            );
                            if (picked != null) {
                              setModalState(() => endTime = picked);
                            }
                          },
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            endTime == null
                                ? 'إلى وقت (اختياري)'
                                : _formatTimeValue(endTime!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                if (type == 'leave') ...[
                  DropdownButtonFormField<String>(
                    value: substituteId,
                    decoration: const InputDecoration(
                      labelText: 'البديل أثناء الإجازة (اختياري)',
                      helperText: 'سيظهر للمدير مع أي تعارض في فترة الطلب.',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('دون بديل'),
                      ),
                      for (final employee in substituteOptions)
                        DropdownMenuItem(
                          value: employee.id,
                          child: Text(employee.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => substituteId = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                ],
                if (type == 'leave' ||
                    type == 'mission' ||
                    type == 'convoy') ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await ImagePicker().pickMultiImage(
                        imageQuality: 82,
                        limit: 5,
                        requestFullMetadata: false,
                      );
                      if (picked.isNotEmpty) {
                        setModalState(
                          () => attachments = picked.take(5).toList(),
                        );
                      }
                    },
                    icon: const Icon(Icons.attach_file_rounded),
                    label: Text(
                      attachments.isEmpty
                          ? 'إضافة مرفقات (اختياري)'
                          : '${attachments.length} مرفق محدد',
                    ),
                  ),
                  if (attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        attachments.map((file) => file.name).join('، '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(sheetContext).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (type == 'permit' ||
                    type == 'late_permit' ||
                    type == 'early_permit') ...[
                  DropdownButtonFormField<String>(
                    value: permitKind,
                    decoration: const InputDecoration(labelText: 'نوع الإذن'),
                    items: const [
                      DropdownMenuItem(
                        value: 'late_arrival',
                        child: Text('إذن حضور'),
                      ),
                      DropdownMenuItem(
                        value: 'early_departure',
                        child: Text('إذن انصراف'),
                      ),
                    ],
                    onChanged: (value) => setModalState(
                      () => permitKind = value ?? 'late_arrival',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _DateButton(
                    label: 'تاريخ الإذن',
                    value: permitDate,
                    onPressed: () async {
                      final picked = await _pickDate(sheetContext, permitDate);
                      if (picked != null) {
                        setModalState(() => permitDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        sheetContext,
                      ).colorScheme.primaryContainer.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'كل إذن ساعتين كاملة · 4 أذونات شهريًا',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'عنوان الطلب'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'السبب والتفاصيل',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final validation = _validateRequest(
                      type: type,
                      title: title.text,
                      reason: reason.text,
                      startDate: startDate,
                      endDate: endDate,
                      location: location.text,
                      permitDate: permitDate,
                      minutes: minutes.text,
                    );
                    if (validation != null) {
                      ScaffoldMessenger.of(
                        sheetContext,
                      ).showSnackBar(SnackBar(content: Text(validation)));
                      return;
                    }
                    Navigator.pop(sheetContext, true);
                  },
                  child: const Text('إرسال الطلب'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final requestTitle = title.text.trim();
    final requestReason = reason.text.trim();
    final requestLocation = location.text.trim();
    title.dispose();
    reason.dispose();
    location.dispose();
    minutes.dispose();
    if (confirmed != true) return;

    final payload = <String, dynamic>{};
    if (type == 'leave') {
      payload.addAll({
        'leaveType': leaveType,
        'startDate': _dateValue(startDate!),
        'endDate': _dateValue(endDate!),
        if (substituteId.isNotEmpty) 'substituteEmployeeId': substituteId,
      });
    } else if (type == 'mission' || type == 'convoy' || type == 'fundraising') {
      payload.addAll({
        'startDate': _dateValue(startDate!),
        'endDate': _dateValue(endDate!),
        'location': requestLocation,
        if (startTime != null) 'startTime': _formatTimeValue(startTime!),
        if (endTime != null) 'endTime': _formatTimeValue(endTime!),
      });
    } else if (type == 'permit' ||
        type == 'late_permit' ||
        type == 'early_permit') {
      payload.addAll({
        'permitDate': _dateValue(permitDate!),
        'minutes': 120,
        'permitKind': permitKind,
      });
    }

    // حل النوع الموحّد "permit" إلى النوع الفعلي للباك إند.
    var resolvedType = type;
    if (type == 'permit') {
      resolvedType = permitKind == 'early_departure'
          ? 'early_permit'
          : 'late_permit';
    }

    final commands = ref.read(mobileCommandsProvider);
    final uploaded = <Map<String, dynamic>>[];
    try {
      for (final attachment in attachments) {
        final bytes = await attachment.readAsBytes();
        if (bytes.length > 10 * 1024 * 1024) {
          throw StateError('ATTACHMENT_TOO_LARGE');
        }
        uploaded.add(
          await commands.uploadRequestAttachment(
            bytes: bytes,
            fileName: attachment.name,
            mimeType: attachment.mimeType ?? '',
          ),
        );
      }
      if (uploaded.isNotEmpty) payload['attachmentPaths'] = uploaded;
      await commands.submitRequest(
        resolvedType,
        requestTitle,
        requestReason,
        payload,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطلب إلى مسار الاعتماد.')),
        );
      }
    } catch (error) {
      try {
        await commands.deleteRequestAttachments(
          uploaded.map((item) => item['path'] as String),
        );
      } catch (_) {
        // Orphan cleanup can be retried later; preserve the original error.
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  static String? _validateRequest({
    required String type,
    required String title,
    required String reason,
    required DateTime? startDate,
    required DateTime? endDate,
    required String location,
    required DateTime? permitDate,
    required String minutes,
  }) {
    if (title.trim().length < 3) return 'اكتب عنوانًا واضحًا للطلب.';
    if (reason.trim().length < 3) return 'اكتب سبب الطلب وتفاصيله.';
    if (reason.trim().length > 300) {
      return 'السبب طويل جدًا (300 حرف كحد أقصى).';
    }
    if (type == 'leave' ||
        type == 'mission' ||
        type == 'convoy' ||
        type == 'fundraising') {
      if (startDate == null || endDate == null) {
        return 'حدد تاريخ البداية والنهاية.';
      }
      if (endDate.isBefore(startDate)) {
        return 'تاريخ النهاية يجب ألا يسبق البداية.';
      }
    }
    if ((type == 'mission' || type == 'convoy' || type == 'fundraising') &&
        location.trim().length < 2) {
      return 'حدد مكان أو جهة التكليف.';
    }
    if (type == 'permit' || type == 'late_permit' || type == 'early_permit') {
      if (permitDate == null) return 'حدد تاريخ الإذن.';
    }
    return null;
  }

  static Future<DateTime?> _pickDate(
    BuildContext context,
    DateTime? initial, {
    DateTime? firstDate,
  }) {
    final today = DateUtils.dateOnly(DateTime.now());
    return showDatePicker(
      context: context,
      initialDate: initial ?? firstDate ?? today,
      firstDate: firstDate ?? today,
      lastDate: today.add(const Duration(days: 730)),
    );
  }

  static String _dateValue(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Future<TimeOfDay?> _pickTime(
    BuildContext context,
    TimeOfDay? initial,
  ) {
    return showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    );
  }

  /// صيغة HH:MM ثابتة (الخادم يرفض "9:00" — يتطلب خانتين).
  static String _formatTimeValue(TimeOfDay value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.value,
    required this.onPressed,
    this.firstDate,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPressed;
  final DateTime? firstDate;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.event_outlined),
    label: Text(
      value == null ? label : DateFormat('d MMMM y', 'ar').format(value!),
    ),
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.item});

  final MobileRequest item;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MobileRequestDetailPage(requestId: item.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MobileStatusPill(item.status),
                const Spacer(),
                Text(
                  '#${item.number}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item.title ?? _typeLabel(item.type),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                AppAvatar(
                  name: item.employeeName,
                  photoUrl: item.employeePhotoUrl,
                  radius: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.employeeName,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (item.reason?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(item.reason!, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const Divider(height: 26),
            Row(
              children: [
                const Icon(Icons.route_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item.activeStepName ?? 'اكتمل المسار',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Text(
                  DateFormat('d MMM', 'ar').format(item.createdAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  static String _typeLabel(String type) => switch (type) {
    'leave' => 'طلب إجازة',
    'mission' => 'مأمورية',
    'late_permit' => 'إذن حضور',
    'early_permit' => 'إذن انصراف',
    'attendance_correction' => 'تصحيح حضور',
    'convoy' => 'قافلة',
    'fundraising' => 'فاندي',
    _ => 'طلب',
  };
}
