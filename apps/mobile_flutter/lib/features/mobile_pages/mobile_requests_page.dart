import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/host_app_bar_scope.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_list_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/team_requests_page.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class MobileRequestsPage extends ConsumerStatefulWidget {
  const MobileRequestsPage({
    this.focusRequestId,
    this.showAllByDefault = false,
    super.key,
  });

  final String? focusRequestId;

  /// «كل الطلبات» للإدارة التنفيذية؛ الافتراضي «طلباتي».
  final bool showAllByDefault;

  @override
  ConsumerState<MobileRequestsPage> createState() => _MobileRequestsPageState();
}

class _MobileRequestsPageState extends ConsumerState<MobileRequestsPage> {
  final _searchController = TextEditingController();
  String _search = '';
  String _status = 'all';
  late bool _showAll = widget.showAllByDefault;

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
      // تُفتح منفردة من الرئيسية والإشعارات — كانت بلا عنوان ولا زر رجوع
      appBar: HostAppBarScope.isActive(context)
          ? null
          : AppBar(title: const Text('الطلبات')),
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
        data: (all) {
          final access = ref.watch(accessContextProvider).value;
          final isClinicStaff = access?.isClinicStaff == true;
          final me = access?.employeeId;
          final mineList = all.where((r) => r.isMineFor(me)).toList();
          final others = isClinicStaff ? const <MobileRequest>[] : all.where((r) => !r.isMineFor(me)).toList();
          final items = (!isClinicStaff && _showAll) ? others : mineList;
          // طلبات الآخرين التي تنتظر قرار المستخدم — اختصار لصفحة الاعتماد
          final awaitingMe = isClinicStaff
              ? 0
              : others
                  .where(
                    (r) =>
                        r.status == 'pending' &&
                        (r.awaitingMe ?? r.canDecide ?? false),
                  )
                  .length;
          return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            if (!isClinicStaff && others.isNotEmpty) ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.person_rounded),
                    label: Text('طلباتي (${mineList.length})'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.groups_rounded),
                    label: Text('طلبات الآخرين (${others.length})'),
                  ),
                ],
                selected: {_showAll},
                onSelectionChanged: (v) => setState(() => _showAll = v.first),
              ),
              const SizedBox(height: 12),
            ],
            if (!isClinicStaff && awaitingMe > 0) ...[
              Card(
                elevation: 0,
                color: AppColors.statusInfo.withValues(alpha: .08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: const Icon(
                    Icons.notifications_active_rounded,
                    color: AppColors.statusInfo,
                  ),
                  title: Text(
                    '${arRequests(awaitingMe)} بانتظار قرارك',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text('افتح «اعتماد طلبات الفريق» للبت فيها.'),
                  trailing: const Icon(Icons.chevron_left_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TeamRequestsPage()),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!_showAll) ...[
              const MobileSectionHeader(title: 'أرصدة الإجازات'),
              const SizedBox(height: 10),
              balances.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('تعذر تحميل الأرصدة الآن.'),
                data: (values) => LeaveBalanceStrip(
                  balances: values,
                  // النقر على الرصيد يفتح الخدمة الذاتية حيث يُقدَّم طلب الإجازة
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileSelfServicePage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            MobileSectionHeader(title: _showAll ? 'طلبات الآخرين' : 'طلباتي'),
            const SizedBox(height: 10),
            if (!_showAll) ...[
              RequestMonthSummary(requests: mineList),
              const SizedBox(height: 10),
            ],
            MobileFilterBar(
              searchHint: 'بحث بالاسم أو العنوان أو رقم الطلب',
              controller: _searchController,
              onSearchChanged: (value) =>
                  setState(() => _search = value.trim().toLowerCase()),
              options: const [
                MobileFilterOption('all', 'الكل'),
                MobileFilterOption('pending', 'قيد المراجعة'),
                MobileFilterOption('approved', 'معتمد'),
                MobileFilterOption('rejected', 'مرفوض أو مُعاد'),
                MobileFilterOption('cancelled', 'مسحوب'),
              ],
              selected: _status,
              onSelected: (value) => setState(() => _status = value),
              resultLabel:
                  '${items.where(_matches).length} من ${items.length}',
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
              ...withRequestGroupHeaders<MobileRequest>(
                items.where(_matches).toList(),
                (item) => item.createdAt,
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: RequestListCard(item: item, showOwner: _showAll),
                ),
              ),
          ],
          );
        },
      ),
    );
  }

  bool _matches(MobileRequest item) {
    final haystack =
        '${item.employeeName} ${item.title ?? ''} ${item.reason ?? ''} ${item.number}'
            .toLowerCase();
    final statusOk = switch (_status) {
      'all' => true,
      'rejected' => item.status == 'rejected' || item.status == 'returned',
      _ => item.status == _status,
    };
    return (_search.isEmpty || haystack.contains(_search)) && statusOk;
  }

  Future<void> _createRequest(BuildContext context, WidgetRef ref) async {
    List<DisputeDirectoryEmployee> substituteOptions = const [];
    try {
      substituteOptions = await ref.read(disputeDirectoryProvider('').future);
    } catch (_) {
      // The request remains usable if the optional directory is unavailable.
    }
    if (!context.mounted) return;
    final isClinicStaff =
        ref.read(accessContextProvider).value?.isClinicStaff == true;
    var type = 'leave';
    var leaveType = 'annual';
    var permitKind = 'late_arrival';
    DateTime? startDate;
    DateTime? endDate;
    DateTime? permitDate;
    TimeOfDay? startTime;
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
                  items: [
                    const DropdownMenuItem(value: 'leave', child: Text('إجازة')),
                    if (!isClinicStaff)
                      const DropdownMenuItem(value: 'mission', child: Text('مأمورية عمل')),
                    const DropdownMenuItem(value: 'permit', child: Text('طلب إذن')),
                    const DropdownMenuItem(
                      value: 'attendance_correction',
                      child: Text('تصحيح حضور'),
                    ),
                    if (!isClinicStaff) ...const [
                      DropdownMenuItem(
                        value: 'convoy',
                        child: Text('تكليف قافلة'),
                      ),
                      DropdownMenuItem(
                        value: 'fundraising',
                        child: Text('فاندي'),
                      ),
                    ],
                  ],
                  onChanged: (value) => setModalState(() {
                    type = value ?? 'leave';
                    startDate = null;
                    endDate = null;
                    permitDate = null;
                    startTime = null;
                    if (type == 'mission') {
                      if (title.text.trim().isEmpty) title.text = 'مأمورية عمل خارجية';
                      if (reason.text.trim().isEmpty) reason.text = 'مأمورية عمل رسمية بتكليف من الإدارة';
                      if (location.text.trim().isEmpty) location.text = 'مأمورية عمل خارجية';
                    }
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
                        value: 'weekly_rest_comp',
                        child: Text('بدل راحة أسبوعية (يُخصم من رصيد البدل)'),
                      ),
                    ],
                    onChanged: (value) =>
                        setModalState(() => leaveType = value ?? 'annual'),
                  ),
                  if (leaveType == 'sick') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(sheetContext).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(sheetContext).colorScheme.tertiary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.health_and_safety_outlined,
                            size: 16,
                            color: Theme.of(sheetContext).colorScheme.tertiary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'الإجازة المرضية تتطلب كشفاً أو تقريراً طبياً معتمداً.',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                if (type == 'mission') ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(sheetContext).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Theme.of(sheetContext).colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'تبدأ المأمورية فور إرسالها، ويُسجَّل وقتها وموقعك الحالي ليراهما مديرك. '
                            'إن أرسلتها بعد موعد الدوام يُحسب التأخير حتى لحظة الإرسال.',
                            style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                              color: Theme.of(sheetContext).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (type == 'leave' ||
                    type == 'convoy' ||
                    type == 'fundraising') ...[
                  Builder(
                    builder: (context) {
                      final now = DateTime.now();
                      final monthStart = DateTime(now.year, now.month, 1);
                      final allowedFirstDate = (type == 'leave' && (leaveType == 'casual' || leaveType == 'sick'))
                          ? monthStart
                          : null;
                      return Row(
                        children: [
                          Expanded(
                            child: _DateButton(
                              label: 'من تاريخ',
                              value: startDate,
                              firstDate: allowedFirstDate,
                              onPressed: () async {
                                final picked = await _pickDate(
                                  sheetContext,
                                  startDate,
                                  firstDate: allowedFirstDate,
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
                              firstDate: startDate ?? allowedFirstDate,
                              onPressed: () async {
                                final picked = await _pickDate(
                                  sheetContext,
                                  endDate ?? startDate,
                                  firstDate: startDate ?? allowedFirstDate,
                                );
                                if (picked != null) {
                                  setModalState(() => endDate = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      );
                    },
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
                  if (type != 'mission') ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await _pickTime(
                          sheetContext,
                          startTime,
                        );
                        if (picked != null) {
                          setModalState(() => startTime = picked);
                        }
                      },
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(
                        startTime == null
                            ? 'وقت بداية التكليف (اختياري)'
                            : 'وقت البداية: ${_formatTimeValue(startTime!)}',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
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
    } else if (type == 'mission') {
      final now = DateTime.now();
      final todayStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final effectiveLocation =
          requestLocation.isEmpty ? 'مأمورية عمل خارجية' : requestLocation;
      payload.addAll({
        'startDate': todayStr,
        'endDate': todayStr,
        'startTime': timeStr,
        'location': effectiveLocation,
        'startedAtCreation': true,
      });
    } else if (type == 'convoy' || type == 'fundraising') {
      payload.addAll({
        'startDate': _dateValue(startDate!),
        'endDate': _dateValue(endDate!),
        'location': requestLocation,
        if (startTime != null) 'startTime': _formatTimeValue(startTime!),
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
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(myLeaveBalancesProvider);
      ref.invalidate(attendanceStateProvider);
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
        type == 'convoy' ||
        type == 'fundraising') {
      if (startDate == null || endDate == null) {
        return 'حدد تاريخ البداية والنهاية.';
      }
      if (endDate.isBefore(startDate)) {
        return 'تاريخ النهاية يجب ألا يسبق البداية.';
      }
    }
    if ((type == 'convoy' || type == 'fundraising') &&
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
