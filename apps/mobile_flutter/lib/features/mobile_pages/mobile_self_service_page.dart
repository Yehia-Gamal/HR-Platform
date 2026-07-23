import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// صفحة الخدمات الذاتية — إجازة، مأمورية، قافلة/فاندي، إذن، نسيان بصمة.
class MobileSelfServicePage extends ConsumerWidget {
  const MobileSelfServicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final balances = ref.watch(myLeaveBalancesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات الذاتية')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeaveBalancesProvider);
          ref.invalidate(mobileRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // ── قسم الطلبات الجديدة ──
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
                    title: 'مأمورية',
                    subtitle: 'مهمة عمل خارجية',
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
                    onTap: () => _submitRequest(context, ref, 'field_assignment'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.schedule_rounded,
                    title: 'طلب إذن',
                    subtitle: 'تأخير أو خروج مبكر',
                    color: const Color(0xFFBF6A22),
                    onTap: () => _submitRequest(context, ref, 'permission'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.fingerprint_rounded,
                    title: 'نسيان بصمة حضور',
                    subtitle: 'تصحيح وقت الدخول',
                    color: scheme.error,
                    onTap: () => _submitCorrection(context, ref, 'forgot_check_in'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ServiceCard(
                    icon: Icons.fingerprint_rounded,
                    title: 'نسيان بصمة انصراف',
                    subtitle: 'تصحيح وقت الخروج',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => _submitCorrection(context, ref, 'forgot_check_out'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Icon(Icons.edit_calendar_rounded, color: scheme.primary),
                title: const Text('جدولي وتصحيحات الحضور'),
                subtitle: const Text('جدول الورديات وطلبات التصحيح السابقة'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MobileAttendanceServicesPage(),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: Icon(Icons.description_outlined, color: scheme.primary),
                title: const Text('طلباتي السابقة'),
                subtitle: const Text('عرض ومتابعة جميع الطلبات'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MobileRequestsPage(allowDecision: false),
                  ),
                ),
              ),
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
                return Column(
                  children: items.map((b) => _LeaveBalanceCard(balance: b)).toList(),
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
    String type,
  ) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _NewRequestSheet(type: type),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(mobileCommandsProvider).submitRequest(
            type,
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
    String type,
  ) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ForgotPunchSheet(type: type),
    );
    if (result == null || !context.mounted) return;

    try {
      await ref.read(mobileCommandsProvider).requestAttendanceCorrection(
            workDate: result['workDate'] as DateTime,
            type: type,
            reason: result['reason'] as String,
            checkIn: result['checkIn'] as DateTime?,
            checkOut: result['checkOut'] as DateTime?,
          );
      ref.invalidate(myAttendanceServicesProvider);
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

class _LeaveBalanceCard extends StatelessWidget {
  const _LeaveBalanceCard({required this.balance});
  final MobileLeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final used = balance.consumedUnits;
    final total = balance.availableUnits + balance.consumedUnits + balance.reservedUnits;
    final remaining = balance.availableUnits;
    final progress = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    balance.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: remaining > 0
                        ? Colors.green.withValues(alpha: .12)
                        : scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'متبقي $remaining من $total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: remaining > 0 ? Colors.green.shade700 : scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
                color: remaining > 0 ? scheme.primary : scheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewRequestSheet extends StatefulWidget {
  const _NewRequestSheet({required this.type});
  final String type;
  @override
  State<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends State<_NewRequestSheet> {
  final _titleController = TextEditingController();
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;

  String get _typeLabel => switch (widget.type) {
        'leave' => 'طلب إجازة',
        'mission' => 'طلب مأمورية',
        'field_assignment' => 'طلب قافلة / فاندي',
        'permission' => 'طلب إذن',
        _ => 'طلب جديد',
      };

  @override
  void dispose() {
    _titleController.dispose();
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('ar'),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _startDate == null
                        ? 'من تاريخ'
                        : DateFormat('d/M/y').format(_startDate!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      locale: const Locale('ar'),
                    );
                    if (picked != null) setState(() => _endDate = picked);
                  },
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    _endDate == null
                        ? 'إلى تاريخ'
                        : DateFormat('d/M/y').format(_endDate!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_titleController.text.trim().isEmpty) return;
              if (_reasonController.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'title': _titleController.text.trim(),
                'reason': _reasonController.text.trim(),
                'payload': <String, dynamic>{
                  'startDate': _startDate?.toIso8601String(),
                  'endDate': _endDate?.toIso8601String(),
                },
              });
            },
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
  }
}

class _ForgotPunchSheet extends StatefulWidget {
  const _ForgotPunchSheet({required this.type});
  final String type;
  @override
  State<_ForgotPunchSheet> createState() => _ForgotPunchSheetState();
}

class _ForgotPunchSheetState extends State<_ForgotPunchSheet> {
  final _reasonController = TextEditingController();
  DateTime _workDate = DateTime.now();
  TimeOfDay? _time;

  String get _label => widget.type == 'forgot_check_in'
      ? 'نسيان بصمة حضور'
      : 'نسيان بصمة انصراف';

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
          Text(
            _label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
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
            decoration: const InputDecoration(
              labelText: 'السبب',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              if (_reasonController.text.trim().isEmpty) return;
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
                if (widget.type == 'forgot_check_in') {
                  checkIn = dt;
                } else {
                  checkOut = dt;
                }
              }
              Navigator.pop(context, {
                'workDate': _workDate,
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
