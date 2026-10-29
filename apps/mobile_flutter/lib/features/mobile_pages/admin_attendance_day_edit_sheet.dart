import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// ورقة التعديل الإداري لحالة يوم الموظف وساعات عمله — مخصصة للموارد البشرية والإدارة
class AdminAttendanceDayEditSheet extends ConsumerStatefulWidget {
  const AdminAttendanceDayEditSheet({
    required this.employeeId,
    this.employeeName,
    required this.initialDate,
    this.initialDay,
    this.hasExistingOverride = false,
    this.onSaved,
    super.key,
  });

  final String employeeId;
  final String? employeeName;
  final String initialDate; // YYYY-MM-DD
  final AttendanceStatementDay? initialDay;
  final bool hasExistingOverride;
  final VoidCallback? onSaved;

  /// فتح الورقة بسهولة من أي شاشة في التطبيق
  static Future<bool?> show(
    BuildContext context, {
    required String employeeId,
    String? employeeName,
    required String initialDate,
    AttendanceStatementDay? initialDay,
    bool hasExistingOverride = false,
    VoidCallback? onSaved,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdminAttendanceDayEditSheet(
        employeeId: employeeId,
        employeeName: employeeName,
        initialDate: initialDate,
        initialDay: initialDay,
        hasExistingOverride: hasExistingOverride,
        onSaved: onSaved,
      ),
    );
    if (result == true) {
      onSaved?.call();
    }
    return result;
  }

  @override
  ConsumerState<AdminAttendanceDayEditSheet> createState() =>
      _AdminAttendanceDayEditSheetState();
}

class _AdminAttendanceDayEditSheetState
    extends ConsumerState<AdminAttendanceDayEditSheet> {
  late DateTime _selectedDate;
  late String _dayType;
  late String _leaveType;
  late TextEditingController _checkInController;
  late TextEditingController _checkOutController;
  late TextEditingController _reasonController;
  late TextEditingController _notesController;
  bool _clearCheckIn = false;
  bool _clearCheckOut = false;
  bool _isSubmitting = false;

  static const _dayTypes = [
    ('work', 'يوم عمل (حاضر)', Icons.work_outline),
    ('rest', 'راحة أسبوعية', Icons.wb_sunny_rounded),
    ('leave', 'إجازة معتمدة', Icons.beach_access_outlined),
    ('mission', 'مأمورية عمل', Icons.directions_car_outlined),
    ('convoy', 'قافلة مساعدات (كامب)', Icons.volunteer_activism_outlined),
    ('fundraising', 'يوم ترفيهي (فاندي)', Icons.celebration_outlined),
    ('holiday', 'عطلة رسمية', Icons.calendar_today_outlined),
    ('absent', 'تأكيد غياب', Icons.cancel_outlined),
  ];

  static const _leaveTypes = [
    ('annual', 'إجازة سنوية (اعتيادية)'),
    ('casual', 'إجازة عارضة'),
    ('sick', 'إجازة مرضية'),
    ('unpaid', 'إجازة بدون راتب'),
    ('weekly_rest_comp', 'بدل راحة أسبوعية'),
  ];

  static const _quickHours = [
    ('8 س (09:00 - 17:00)', '09:00', '17:00'),
    ('8 س (08:00 - 16:00)', '08:00', '16:00'),
    ('4 س (09:00 - 13:00)', '09:00', '13:00'),
    ('10 س (08:00 - 18:00)', '08:00', '18:00'),
  ];

  static const _presetReasons = [
    'راحة أسبوعية معتمدة',
    'تعديل ساعات العمل المعتمدة',
    'تصحيح وقت الحضور والانصراف',
    'إجازة معتمدة من الإدارة',
    'مأمورية عمل رسمية',
    'عطلة رسمية معتمدة',
    'دوام كامل معتمد',
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.tryParse(widget.initialDate) ?? DateTime.now();

    final existingType =
        widget.initialDay?.adminOverride?['dayType'] as String? ?? 'work';
    _dayType = existingType;
    _leaveType =
        widget.initialDay?.adminOverride?['leaveType'] as String? ?? 'annual';

    _checkInController = TextEditingController(
      text: widget.initialDay?.checkIn != null &&
              widget.initialDay!.checkIn!.length >= 5
          ? widget.initialDay!.checkIn!.substring(0, 5)
          : '09:00',
    );
    _checkOutController = TextEditingController(
      text: widget.initialDay?.checkOut != null &&
              widget.initialDay!.checkOut!.length >= 5
          ? widget.initialDay!.checkOut!.substring(0, 5)
          : '17:00',
    );
    _reasonController = TextEditingController(
      text: widget.initialDay?.adminOverride?['reason'] as String? ??
          'تعديل ساعات وحضور معتمد',
    );
    _notesController = TextEditingController(
      text: widget.initialDay?.adminOverride?['notes'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _checkInController.dispose();
    _checkOutController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String get _currentDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);

  void _setDate(DateTime dt) {
    setState(() {
      _selectedDate = dt;
    });
  }

  /// تطبيق إعداد سريع بنقرة واحدة (مثلاً: إضافة راحة أسبوعية)
  void _applyQuickPreset({
    required String dayType,
    String? leaveType,
    required String reason,
    String? inTime,
    String? outTime,
  }) {
    setState(() {
      _dayType = dayType;
      if (leaveType != null) _leaveType = leaveType;
      _reasonController.text = reason;
      if (inTime != null) _checkInController.text = inTime;
      if (outTime != null) _checkOutController.text = outTime;
      _clearCheckIn = dayType != 'work';
      _clearCheckOut = dayType != 'work';
    });
  }

  Future<void> _pickCustomTime(TextEditingController controller) async {
    final parts = controller.text.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          )
        : const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      final h = picked.hour.toString().padLeft(2, '0');
      final m = picked.minute.toString().padLeft(2, '0');
      setState(() {
        controller.text = '$h:$m';
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      _setDate(picked);
    }
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(mobileCommandsProvider).setAttendanceDayAdmin(
            employeeId: widget.employeeId,
            date: _currentDateStr,
            dayType: _dayType,
            checkIn: _dayType == 'work' && !_clearCheckIn
                ? _checkInController.text.trim()
                : null,
            checkOut: _dayType == 'work' && !_clearCheckOut
                ? _checkOutController.text.trim()
                : null,
            clearCheckIn: _dayType != 'work' || _clearCheckIn,
            clearCheckOut: _dayType != 'work' || _clearCheckOut,
            reason: _reasonController.text.trim().isNotEmpty
                ? _reasonController.text.trim()
                : 'اعتماد الحالة',
            notes: _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
            leaveType:
                _dayType == 'leave' || _dayType == 'absent' ? _leaveType : null,
          );

      // تحديث مزودات الحضور والإشعارات
      ref.invalidate(myNotificationsProvider);
      ref.invalidate(myMonthlyStatementProvider);
      ref.invalidate(employeeMonthlyStatementProvider);
      ref.invalidate(myAttendanceHistoryProvider);
      ref.invalidate(employee360Provider(widget.employeeId));
      widget.onSaved?.call();

      if (mounted) {
        Navigator.pop(context, true);
        final label = _dayTypes.firstWhere((t) => t.$1 == _dayType).$2;
        final name = widget.employeeName != null ? ' للزميل ${widget.employeeName}' : '';
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F9F6E),
            content: Text('تم اعتماد ($label) يوم $_currentDateStr$name بنجاح.'),
          ),
        );
      }
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(humanizeError(error)),
          ),
        );
      }
    }
  }

  Future<void> _revertOverride() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء التعديل الإداري'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء التعديل الإداري واستعادة احتساب النظام التلقائي للبصمات؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(mobileCommandsProvider).clearAttendanceDayAdmin(
            employeeId: widget.employeeId,
            date: _currentDateStr,
          );

      ref.invalidate(myNotificationsProvider);
      ref.invalidate(myMonthlyStatementProvider);
      ref.invalidate(employeeMonthlyStatementProvider);
      ref.invalidate(myAttendanceHistoryProvider);
      ref.invalidate(employee360Provider(widget.employeeId));
      widget.onSaved?.call();

      if (mounted) {
        Navigator.pop(context, true);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء التعديل الإداري واستعادة احتساب النظام بنجاح.'),
          ),
        );
      }
    } catch (error) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: Text(humanizeError(error)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final beforeYesterday = today.subtract(const Duration(days: 2));

    final isSelectedToday = _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;
    final isSelectedYesterday = _selectedDate.year == yesterday.year &&
        _selectedDate.month == yesterday.month &&
        _selectedDate.day == yesterday.day;
    final isSelectedBeforeYesterday = _selectedDate.year == beforeYesterday.year &&
        _selectedDate.month == beforeYesterday.month &&
        _selectedDate.day == beforeYesterday.day;

    final dateArabic = DateFormat('EEEE d MMMM yyyy', 'ar').format(_selectedDate);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: DraggableScrollableSheet(
          initialChildSize: 0.88,
          maxChildSize: 0.95,
          minChildSize: 0.45,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              children: [
                // 1) مقبض السحب بالأعلى
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // 2) الرأس: اسم الموظف والتاريخ
                Row(
                  children: [
                    if (widget.employeeName != null) ...[
                      AppAvatar(name: widget.employeeName!, radius: 22),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'تعديل يوم $_currentDateStr',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'إدارة الموارد البشرية',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.employeeName != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'للموظف: ${widget.employeeName}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // 3) شريط اختيار التاريخ السريع
                Row(
                  children: [
                    Icon(
                      Icons.event_note_rounded,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dateArabic,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'اختيار تاريخ آخر من التقويم',
                      visualDensity: VisualDensity.compact,
                      onPressed: _pickDate,
                      icon: const Icon(Icons.edit_calendar_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('اليوم', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor: isSelectedToday ? scheme.primaryContainer : null,
                      side: BorderSide(
                        color: isSelectedToday ? scheme.primary : scheme.outlineVariant,
                      ),
                      onPressed: () => _setDate(today),
                    ),
                    ActionChip(
                      label: const Text('أمس', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor: isSelectedYesterday ? scheme.primaryContainer : null,
                      side: BorderSide(
                        color: isSelectedYesterday ? scheme.primary : scheme.outlineVariant,
                      ),
                      onPressed: () => _setDate(yesterday),
                    ),
                    ActionChip(
                      label: const Text('أول أمس', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor: isSelectedBeforeYesterday ? scheme.primaryContainer : null,
                      side: BorderSide(
                        color: isSelectedBeforeYesterday ? scheme.primary : scheme.outlineVariant,
                      ),
                      onPressed: () => _setDate(beforeYesterday),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_outlined, size: 14),
                      label: const Text('تقويم…', style: TextStyle(fontSize: 11)),
                      onPressed: _pickDate,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4) الاختصارات السريعة بلمسة واحدة (Super Fast 1-Tap Actions)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bolt_rounded, size: 18, color: Colors.amber.shade800),
                          const SizedBox(width: 6),
                          const Text(
                            'إجراءات سريعة بلمسة واحدة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.amber.shade100,
                              foregroundColor: Colors.amber.shade900,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.wb_sunny_rounded, size: 16),
                            label: const Text(
                              'إضافة راحة أسبوعية',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _applyQuickPreset(
                              dayType: 'rest',
                              reason: 'راحة أسبوعية معتمدة',
                            ),
                          ),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.work_rounded, size: 16),
                            label: const Text(
                              'دوام كامل (09:00 - 17:00)',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _applyQuickPreset(
                              dayType: 'work',
                              reason: 'دوام كامل معتمد',
                              inTime: '09:00',
                              outTime: '17:00',
                            ),
                          ),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.blue.shade100,
                              foregroundColor: Colors.blue.shade900,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.beach_access_rounded, size: 16),
                            label: const Text(
                              'إجازة سنوية',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _applyQuickPreset(
                              dayType: 'leave',
                              leaveType: 'annual',
                              reason: 'إجازة معتمدة من الإدارة',
                            ),
                          ),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.teal.shade100,
                              foregroundColor: Colors.teal.shade900,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.directions_car_rounded, size: 16),
                            label: const Text(
                              'مأمورية رسمية',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                            ),
                            onPressed: () => _applyQuickPreset(
                              dayType: 'mission',
                              reason: 'مأمورية عمل رسمية',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5) اختيار حالة اليوم الرئيسية
                Text(
                  'حالة اليوم',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _dayTypes.map((t) {
                    final isSelected = _dayType == t.$1;
                    return ChoiceChip(
                      avatar: Icon(
                        t.$3,
                        size: 16,
                        color: isSelected ? scheme.onPrimary : scheme.primary,
                      ),
                      label: Text(
                        t.$2,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      selected: isSelected,
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? scheme.onPrimary : scheme.onSurface,
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() {
                            _dayType = t.$1;
                            if (_dayType == 'leave' || _dayType == 'absent') {
                              _leaveType = _dayType == 'absent' ? 'unpaid' : 'annual';
                            }
                            if (_dayType == 'rest') {
                              _reasonController.text = 'راحة أسبوعية معتمدة';
                            }
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 6) تفاصيل الإجازة إن اختيرت
                if (_dayType == 'leave' || _dayType == 'absent') ...[
                  Text(
                    'نوع الإجازة',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _leaveType,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _leaveTypes
                        .map((lt) => DropdownMenuItem(value: lt.$1, child: Text(lt.$2)))
                        .toList(),
                    onChanged: (val) => setState(() => _leaveType = val ?? 'annual'),
                  ),
                  const SizedBox(height: 16),
                ],

                // 7) ساعات وأوقات العمل عند اختيار يوم عمل
                if (_dayType == 'work') ...[
                  Text(
                    'ساعات وأوقات العمل',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _quickHours.map((qh) {
                      final isActive = _checkInController.text == qh.$2 &&
                          _checkOutController.text == qh.$3 &&
                          !_clearCheckIn &&
                          !_clearCheckOut;
                      return ActionChip(
                        label: Text(qh.$1, style: const TextStyle(fontSize: 11)),
                        backgroundColor: isActive ? scheme.primaryContainer : null,
                        side: BorderSide(
                          color: isActive ? scheme.primary : scheme.outlineVariant,
                        ),
                        onPressed: () {
                          setState(() {
                            _checkInController.text = qh.$2;
                            _checkOutController.text = qh.$3;
                            _clearCheckIn = false;
                            _clearCheckOut = false;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _checkInController,
                          enabled: !_clearCheckIn,
                          decoration: InputDecoration(
                            labelText: 'وقت الحضور (HH:MM)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.access_time_rounded, size: 18),
                              onPressed: !_clearCheckIn
                                  ? () => _pickCustomTime(_checkInController)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _checkOutController,
                          enabled: !_clearCheckOut,
                          decoration: InputDecoration(
                            labelText: 'وقت الانصراف (HH:MM)',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.access_time_rounded, size: 18),
                              onPressed: !_clearCheckOut
                                  ? () => _pickCustomTime(_checkOutController)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('بدون حضور', style: TextStyle(fontSize: 11)),
                          value: _clearCheckIn,
                          onChanged: (v) => setState(() => _clearCheckIn = v ?? false),
                        ),
                      ),
                      Expanded(
                        child: CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('بدون انصراف', style: TextStyle(fontSize: 11)),
                          value: _clearCheckOut,
                          onChanged: (v) => setState(() => _clearCheckOut = v ?? false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // 8) سبب التعديل
                Text(
                  'سبب التعديل',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _presetReasons.map((pr) {
                    return ActionChip(
                      label: Text(pr, style: const TextStyle(fontSize: 11)),
                      onPressed: () => setState(() => _reasonController.text = pr),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'اكتب سبب التعديل…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),

                // 9) ملاحظات إدارية
                TextField(
                  controller: _notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إضافية (اختيارية)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 22),

                // 10) زر الحفظ الرئيسي
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded),
                    label: Text(
                      _isSubmitting ? 'جارٍ الحفظ والاعتماد…' : 'حفظ التعديل الإداري',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ),

                // 11) زر إلغاء التعديل واستعادة احتساب النظام (إن وُجد تعديل مسبق)
                if (widget.hasExistingOverride ||
                    widget.initialDay?.hasAdminOverride == true) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text(
                        'إلغاء التعديل واستعادة احتساب النظام',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onPressed: _isSubmitting ? null : _revertOverride,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
