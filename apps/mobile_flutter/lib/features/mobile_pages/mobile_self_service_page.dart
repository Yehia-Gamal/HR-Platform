import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// مركز الطلبات الموحّد — 6 أنواع طلبات + عرض الطلبات السابقة مع فلاتر الحالة.
class MobileSelfServicePage extends ConsumerStatefulWidget {
  const MobileSelfServicePage({super.key});

  @override
  ConsumerState<MobileSelfServicePage> createState() =>
      _MobileSelfServicePageState();
}

class _MobileSelfServicePageState extends ConsumerState<MobileSelfServicePage> {
  String _statusFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balances = ref.watch(myLeaveBalancesProvider);
    final requests = ref.watch(mobileRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('طلباتي')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeaveBalancesProvider);
          ref.invalidate(mobileRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // ── تقديم طلب جديد ──
            const MobileSectionHeader(
              title: 'تقديم طلب جديد',
              subtitle: 'اختر نوع الطلب من الخيارات التالية.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.beach_access_rounded,
                    title: 'طلب إجازة',
                    subtitle: 'سنوية، مرضية، طارئة',
                    color: scheme.primary,
                    onTap: () => _submitRequest(context, ref, 'leave'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.work_outline_rounded,
                    title: 'مهمة عمل',
                    subtitle: 'مأمورية خارجية',
                    color: scheme.tertiary,
                    onTap: () => _submitRequest(context, ref, 'mission'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.directions_bus_rounded,
                    title: 'قافلة / فاندي',
                    subtitle: 'تكليف ميداني',
                    color: const Color(0xFF0D7C66),
                    onTap: () => _submitRequest(context, ref, 'convoy'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.access_time_rounded,
                    title: 'طلب إذن',
                    subtitle: 'حضور أو انصراف (ساعتين)',
                    color: const Color(0xFFBF6A22),
                    onTap: () => _submitRequest(context, ref, 'permit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ServiceCard(
              icon: Icons.fingerprint_rounded,
              title: 'تصحيح حضور',
              subtitle: 'نسيان بصمة دخول أو خروج',
              color: scheme.error,
              onTap: () => _submitCorrection(context, ref),
            ),

            // ── أرصدة الإجازات ──
            const SizedBox(height: 20),
            const MobileSectionHeader(
              title: 'أرصدة الإجازات',
              subtitle: 'الرصيد المتاح لكل نوع إجازة في السنة الحالية.',
            ),
            const SizedBox(height: 10),
            balances.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, color: scheme.error),
                      const SizedBox(height: 8),
                      Text(humanizeError(error), textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => ref.invalidate(myLeaveBalancesProvider),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          Icon(
                            Icons.event_available_outlined,
                            size: 32,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'لم تُضبط أرصدة إجازات لهذا الحساب بعد.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return SizedBox(
                  height: 116,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final balance = items[index];
                      return SizedBox(
                        width: 190,
                        child: Card(
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
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),

            // ── طلباتي السابقة ──
            const SizedBox(height: 20),
            const MobileSectionHeader(
              title: 'طلباتي السابقة',
              subtitle: 'تابع حالة طلباتك المقدمة.',
            ),
            const SizedBox(height: 10),

            // فلاتر الحالة
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _StatusChip(
                    label: 'الكل',
                    value: 'all',
                    selected: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: 'قيد المراجعة',
                    value: 'pending',
                    selected: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: 'مقبول',
                    value: 'approved',
                    selected: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(width: 6),
                  _StatusChip(
                    label: 'مرفوض',
                    value: 'rejected',
                    selected: _statusFilter,
                    onSelected: (v) => setState(() => _statusFilter = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            requests.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(Icons.error_outline, color: scheme.error),
                      const SizedBox(height: 8),
                      Text(humanizeError(error), textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () =>
                            ref.invalidate(mobileRequestsProvider),
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) {
                final filtered = items
                    .where(
                      (r) =>
                          _statusFilter == 'all' ||
                          r.status == _statusFilter,
                    )
                    .toList();
                if (filtered.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusFilter == 'all'
                              ? 'لم تُقدم أي طلبات بعد.'
                              : 'لا توجد طلبات بهذه الحالة.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: filtered
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RequestCard(item: item),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitRequest(
    BuildContext context,
    WidgetRef ref,
    String type, {
    String? permitKind,
  }) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NewRequestSheet(type: type, permitKind: permitKind),
    );
    if (result == null || !context.mounted) return;

    // الإذن الموحّد: ترجمة النوع إلى late_permit / early_permit حسب اختيار المستخدم
    var resolvedType = type;
    if (type == 'permit') {
      final kind = (result['payload'] as Map<String, dynamic>)['permitKind'] as String?;
      resolvedType = kind == 'early_departure' ? 'early_permit' : 'late_permit';
    }

    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            resolvedType,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(employeeHomeProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطلب بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }

  Future<void> _submitCorrection(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const _ForgotPunchSheet(),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(mobileCommandsProvider).requestAttendanceCorrection(
            workDate: result['workDate'] as DateTime,
            type: result['type'] as String,
            reason: result['reason'] as String,
            checkIn: result['checkIn'] as DateTime?,
            checkOut: result['checkOut'] as DateTime?,
          );
      ref.invalidate(mobileRequestsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب التصحيح بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }
}

// ── بطاقة نوع الخدمة ──

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ── شريحة فلتر الحالة ──

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected == value,
        onSelected: (_) => onSelected(value),
      );
}

// ── بطاقة طلب سابق ──

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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                if (item.reason?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.reason!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
        'mission' => 'مهمة عمل',
        'late_permit' => 'إذن حضور',
        'early_permit' => 'إذن انصراف',
        'permit' => 'طلب إذن',
        'attendance_correction' => 'تصحيح حضور',
        'convoy' => 'قافلة',
        _ => 'طلب',
      };
}

// ── نموذج طلب جديد ──

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet({required this.type, this.permitKind});
  final String type;
  final String? permitKind;
  @override
  State<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends State<_NewRequestSheet> {
  final _titleController = TextEditingController();
  final _reasonController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _permitDate;
  String _leaveType = 'annual';
  late String _permitKind;

  @override
  void initState() {
    super.initState();
    _permitKind = widget.permitKind ?? 'late_arrival';
  }

  String get _typeLabel => switch (widget.type) {
        'leave' => 'طلب إجازة',
        'mission' => 'طلب مهمة عمل',
        'convoy' => 'طلب قافلة / فاندي',
        'permit' => 'طلب إذن',
        'late_permit' => 'إذن حضور',
        'early_permit' => 'إذن انصراف',
        _ => 'طلب جديد',
      };

  @override
  void dispose() {
    _titleController.dispose();
    _reasonController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? DateTime.now() : (_startDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    final reason = _reasonController.text.trim();
    if (title.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة عنوان واضح (3 أحرف على الأقل)')),
      );
      return;
    }
    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى كتابة سبب الطلب (3 أحرف على الأقل)')),
      );
      return;
    }
    if (reason.length > 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('السبب طويل جدًا (300 حرف كحد أقصى)')),
      );
      return;
    }

    final Map<String, dynamic> payload;
    switch (widget.type) {
      case 'leave':
        if (_startDate == null || _endDate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تحديد تاريخ البداية والنهاية')),
          );
          return;
        }
        payload = {
          'leaveType': _leaveType,
          'startDate': _startDate!.toIso8601String().substring(0, 10),
          'endDate': _endDate!.toIso8601String().substring(0, 10),
        };
      case 'mission':
      case 'convoy':
        if (_startDate == null || _endDate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تحديد تاريخ البداية والنهاية')),
          );
          return;
        }
        final loc = _locationController.text.trim();
        if (loc.length < 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى إدخال موقع المأمورية')),
          );
          return;
        }
        payload = {
          'startDate': _startDate!.toIso8601String().substring(0, 10),
          'endDate': _endDate!.toIso8601String().substring(0, 10),
          'location': loc,
        };
      case 'permit':
      case 'late_permit':
      case 'early_permit':
        if (_permitDate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى تحديد تاريخ الإذن')),
          );
          return;
        }
        payload = {
          'permitDate': _permitDate!.toIso8601String().substring(0, 10),
          'minutes': 120,
          'permitKind': _permitKind,
        };
      default:
        payload = {};
    }
    Navigator.pop(context, {
      'title': title,
      'reason': reason,
      'payload': payload,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset > 0 ? bottomInset + 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _typeLabel,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'عنوان الطلب',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),

          // ── حقول حسب النوع ──
          if (widget.type == 'leave') ...[
            DropdownButtonFormField<String>(
              value: _leaveType,
              decoration: const InputDecoration(
                labelText: 'نوع الإجازة',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'annual', child: Text('سنوية')),
                DropdownMenuItem(value: 'casual', child: Text('طارئة')),
                DropdownMenuItem(value: 'sick', child: Text('مرضية')),
                DropdownMenuItem(value: 'unpaid', child: Text('بدون راتب')),
              ],
              onChanged: (v) => setState(() => _leaveType = v!),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_startDate == null
                        ? 'من تاريخ'
                        : DateFormat('d/M/y').format(_startDate!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_endDate == null
                        ? 'إلى تاريخ'
                        : DateFormat('d/M/y').format(_endDate!)),
                  ),
                ),
              ],
            ),
          ] else if (widget.type == 'mission' || widget.type == 'convoy') ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(true),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_startDate == null
                        ? 'من تاريخ'
                        : DateFormat('d/M/y').format(_startDate!)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(false),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_endDate == null
                        ? 'إلى تاريخ'
                        : DateFormat('d/M/y').format(_endDate!)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'الموقع / الوجهة',
                border: OutlineInputBorder(),
              ),
            ),
          ] else if (widget.type == 'permit' || widget.type == 'late_permit' || widget.type == 'early_permit') ...[
            // اختيار نوع الإذن (حضور / انصراف)
            DropdownButtonFormField<String>(
              value: _permitKind,
              decoration: const InputDecoration(
                labelText: 'نوع الإذن',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: 'late_arrival', child: Text('إذن حضور')),
                DropdownMenuItem(
                    value: 'early_departure', child: Text('إذن انصراف')),
              ],
              onChanged: (v) => setState(() => _permitKind = v!),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _permitDate ?? DateTime.now(),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 30)),
                  locale: const Locale('ar'),
                );
                if (picked != null) setState(() => _permitDate = picked);
              },
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(_permitDate == null
                  ? 'تاريخ الإذن'
                  : DateFormat('d/M/y').format(_permitDate!)),
            ),
            const SizedBox(height: 12),
            // معلومات الإذن — ساعتين ثابتة و 4 أذونات شهريًا
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'كل إذن ساعتين كاملة · 4 أذونات شهريًا',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonController,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submit,
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}

// ── نموذج تصحيح حضور ──

class _ForgotPunchSheet extends StatefulWidget {
  const _ForgotPunchSheet();
  @override
  State<_ForgotPunchSheet> createState() => _ForgotPunchSheetState();
}

class _ForgotPunchSheetState extends State<_ForgotPunchSheet> {
  final _reasonController = TextEditingController();
  DateTime _workDate = DateTime.now();
  TimeOfDay? _time;
  String _correctionType = 'missing_check_in';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset > 0 ? bottomInset + 16 : 40,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تصحيح حضور',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _correctionType,
            decoration: const InputDecoration(
              labelText: 'نوع التصحيح',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'missing_check_in', child: Text('نسيان بصمة حضور')),
              DropdownMenuItem(
                  value: 'missing_check_out', child: Text('نسيان بصمة انصراف')),
            ],
            onChanged: (v) => setState(() => _correctionType = v!),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _workDate,
                firstDate: DateTime.now().subtract(const Duration(days: 14)),
                lastDate: DateTime.now(),
                locale: const Locale('ar'),
              );
              if (picked != null) setState(() => _workDate = picked);
            },
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text('التاريخ: ${DateFormat('d/M/y').format(_workDate)}'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
              );
              if (picked != null) setState(() => _time = picked);
            },
            icon: const Icon(Icons.access_time, size: 18),
            label: Text(
              _time == null
                  ? 'الوقت التقريبي'
                  : 'الوقت: ${_time!.format(context)}',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonController,
            maxLines: 2,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_reasonController.text.trim().length < 3) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('يرجى إدخال سبب التصحيح (3 أحرف على الأقل)'),
                  ),
                );
                return;
              }
              DateTime? checkIn;
              DateTime? checkOut;
              if (_time != null) {
                final dt = DateTime(
                  _workDate.year,
                  _workDate.month,
                  _workDate.day,
                  _time!.hour,
                  _time!.minute,
                );
                if (_correctionType == 'missing_check_in') {
                  checkIn = dt;
                } else {
                  checkOut = dt;
                }
              }
              Navigator.pop(context, {
                'workDate': _workDate,
                'type': _correctionType,
                'reason': _reasonController.text.trim(),
                'checkIn': checkIn,
                'checkOut': checkOut,
              });
            },
            child: const Text('إرسال طلب التصحيح'),
          ),
        ],
      ),
    );
  }
}
