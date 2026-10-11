import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart'
    show NewRequestSheet;
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// محاكي ومخطط الإجازات الذكي (Leave Simulator & Conflict Prevention).
/// يُمكّن الموظف من تجربة الأيام المقترحة واحتساب الرصيد المتبقي بدقة
/// وكشف التضارب مع زملائه في نفس القسم قبل تقديم الطلب.
class LeavePlannerSheet extends ConsumerStatefulWidget {
  const LeavePlannerSheet({this.initialLeaveType = 'annual', super.key});

  final String initialLeaveType;

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LeavePlannerSheet(),
    );
  }

  @override
  ConsumerState<LeavePlannerSheet> createState() => _LeavePlannerSheetState();
}

class _LeavePlannerSheetState extends ConsumerState<LeavePlannerSheet> {
  late String _leaveType;
  late DateTime _startDate;
  late DateTime _endDate;

  @override
  void initState() {
    super.initState();
    _leaveType = widget.initialLeaveType;
    final now = DateTime.now();
    // الافتراضي: يبدأ من الغد لمدة يوم واحد
    _startDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    _endDate = _startDate;
  }

  int get _requestedDays {
    final diff = _endDate.difference(_startDate).inDays + 1;
    return diff > 0 ? diff : 1;
  }

  void _applyQuickShortcut(int mode) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      switch (mode) {
        case 1: // غداً (1 يوم)
          _startDate = today.add(const Duration(days: 1));
          _endDate = _startDate;
        case 2: // بعد غد (1 يوم)
          _startDate = today.add(const Duration(days: 2));
          _endDate = _startDate;
        case 3: // نهاية هذا الأسبوع (خميس)
          // نحسب أقرب يوم خميس قادم
          var d = today;
          while (d.weekday != DateTime.thursday) {
            d = d.add(const Duration(days: 1));
          }
          _startDate = d;
          _endDate = d;
        case 4: // الأسبوع القادم كاملاً (أحد إلى خميس)
          var d = today;
          while (d.weekday != DateTime.sunday) {
            d = d.add(const Duration(days: 1));
          }
          _startDate = d;
          _endDate = d.add(const Duration(days: 4)); // الخميس
      }
    });
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('ar'),
      helpText: 'اختر فترة الإجازة المقترحة',
      cancelText: 'إلغاء',
      confirmText: 'تطبيق',
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balancesAsync = ref.watch(myLeaveBalancesProvider);
    final balances = balancesAsync.asData?.value ?? const <MobileLeaveBalance>[];
    final allRequests = ref.watch(mobileRequestsProvider).asData?.value ?? const <MobileRequest>[];
    final myEmployeeId = ref.watch(accessContextProvider).value?.employeeId;

    // رصيد النوع المختار
    MobileLeaveBalance? selectedBalance;
    for (final b in balances) {
      if (b.code == _leaveType) {
        selectedBalance = b;
        break;
      }
    }

    final avail = selectedBalance?.availableUnits ?? 0;
    final reserved = selectedBalance?.reservedUnits ?? 0;
    final count = _requestedDays;
    final remaining = avail - count;
    final isSufficient = remaining >= 0;

    // فحص التضارب مع طلبات الزملاء ونفس الموظف
    final dateFmt = DateFormat('yyyy-MM-dd');
    final sStr = dateFmt.format(_startDate);
    final eStr = dateFmt.format(_endDate);

    final colleagueConflicts = <String>[];
    final selfConflicts = <String>[];

    for (final r in allRequests) {
      if (r.status != 'approved' && r.status != 'pending') continue;
      final payload = r.payload;
      final rStart = payload['startDate']?.toString();
      final rEnd = payload['endDate']?.toString();
      if (rStart == null || rEnd == null) continue;

      // فحص التداخل الزمني
      final overlap = (rStart.compareTo(eStr) <= 0) && (rEnd.compareTo(sStr) >= 0);
      if (!overlap) continue;

      final isColleague = (r.isMine == false) ||
          (myEmployeeId != null && r.employeeId != null && r.employeeId != myEmployeeId);

      if (isColleague) {
        final statusText = r.status == 'approved' ? 'إجازة معتمدة' : 'طلب قيد الاعتماد';
        colleagueConflicts.add(
          'زميلك في القسم (${r.employeeName}) لديه $statusText في نفس الفترة ($rStart إلى $rEnd)',
        );
      } else {
        selfConflicts.add(
          'لديك بالفعل طلب (${requestTypeLabel(r.type)}) رقم #${r.number} متداخل في هذه الفترة',
        );
      }
    }

    final startStr = DateFormat('EEEE، d MMMM y', 'ar').format(_startDate);
    final endStr = DateFormat('EEEE، d MMMM y', 'ar').format(_endDate);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // مقبض السحب والعنوان
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF0284C7).withValues(alpha: .15),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Color(0xFF0284C7),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تخطيط ومحاكي إجازتي الذكي',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'محاكاة فورية للرصيد وتفادي التضارب مع زملاء القسم',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),

              // 1. اختيار نوع الإجازة
              const Text(
                'نوع الإجازة المراد تخطيطها',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'annual',
                    label: Text('سنوية', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 'casual',
                    label: Text('عارضة', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 'sick',
                    label: Text('مرضية', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: 'weekly_rest_comp',
                    label: Text('بدل راحة', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_leaveType},
                onSelectionChanged: (set) => setState(() => _leaveType = set.first),
              ),
              const SizedBox(height: 16),

              // 2. اختصارات سريعة وتحديد الفترة
              Row(
                children: [
                  const Text(
                    'الفترة المقترحة',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.calendar_month_outlined, size: 16),
                    label: const Text('تحديد في التقويم', style: TextStyle(fontSize: 12)),
                    onPressed: _pickCustomRange,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      label: const Text('غداً (1 يوم)'),
                      onPressed: () => _applyQuickShortcut(1),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('بعد غد (1 يوم)'),
                      onPressed: () => _applyQuickShortcut(2),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('نهاية هذا الأسبوع (خميس)'),
                      onPressed: () => _applyQuickShortcut(3),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('الأسبوع القادم كاملاً (5 أيام)'),
                      onPressed: () => _applyQuickShortcut(4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // بطاقة الفترة المحددة
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range_rounded, color: Color(0xFF0284C7), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _startDate == _endDate ? startStr : 'من: $startStr',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                          if (_startDate != _endDate) ...[
                            const SizedBox(height: 2),
                            Text(
                              'إلى: $endStr',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count ${count == 1 ? 'يوم' : 'أيام'}',
                        style: const TextStyle(
                          color: Color(0xFF0284C7),
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 3. النتيجة الذكية للرصيد
              const Text(
                'نتائج المحاكاة وتحليل الرصيد',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isSufficient
                      ? AppColors.statusSuccess.withValues(alpha: .09)
                      : AppColors.statusDanger.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSufficient
                        ? AppColors.statusSuccess.withValues(alpha: .35)
                        : AppColors.statusDanger.withValues(alpha: .35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isSufficient ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: isSufficient ? AppColors.statusSuccess : AppColors.statusDanger,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isSufficient
                                ? 'رصيدك الحالي يكفي بالكامل ✅'
                                : 'تنبيه: رصيدك الحالي لا يكفي ⚠️',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: isSufficient
                                  ? AppColors.statusSuccess
                                  : AppColors.statusDanger,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isSufficient
                          ? 'رصيدك المتاح حالياً (${fmtUnits(avail)} يوم)، وسيتبقى لك بعد هذا الطلب (${fmtUnits(remaining)} يوم) حتى نهاية العام.'
                          : 'الرصيد المتاح حالياً (${fmtUnits(avail)} يوم) أقل من المدة المطلوبة ($count يوم). العجز: (${fmtUnits(-remaining)} يوم). قد يتم رفض الطلب أو احتسابه كإجازة بدون راتب.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (reserved > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        '💡 ملاحظة: لديك أيضاً (${fmtUnits(reserved)} يوم) محجوزة بانتظار اعتماد طلبات سابقة.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: const Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 4. كاشف التضارب مع زملاء القسم
              const Text(
                'كاشف التضارب وتنسيق القسم',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              if (colleagueConflicts.isNotEmpty) ...[
                for (final msg in colleagueConflicts) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFD97706).withValues(alpha: .35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.group_outlined,
                          color: Color(0xFFD97706),
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'يُرجى التنسيق المسبق مع زميلك لضمان عدم تعطل العمل بالقسم قبل رفع الطلب.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.statusSuccess.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusSuccess.withValues(alpha: .2),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        color: AppColors.statusSuccess,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'لا يوجد أي تضارب زمني مسجل مع زملائك في القسم — الوقت مناسب للتقديم! 🌿',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.statusSuccess,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (selfConflicts.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final msg in selfConflicts)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusDanger.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.statusDanger,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            msg,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.statusDanger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 22),

              // 5. أزرار الإجراءات الفورية
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.brandPrimary,
                ),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'تقديم طلب الإجازة الآن 🚀',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => NewRequestSheet(
                      type: 'leave',
                      initial: {
                        'title': 'طلب ${leaveTypeLabel(_leaveType)}',
                        'reason': 'طلب إجازة وفق مخطط الإجازات الذكي',
                        'payload': {
                          'leaveType': _leaveType,
                          'startDate': DateFormat('yyyy-MM-dd').format(_startDate),
                          'endDate': DateFormat('yyyy-MM-dd').format(_endDate),
                        },
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: const Color(0xFF128C7E),
                  side: const BorderSide(color: Color(0xFF25D366)),
                ),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text(
                  'تنسيق ومشاركة المخطط عبر واتساب 💬',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  final text = '''
السلام عليكم ورحمة الله وبركاته،
أود التنسيق المسبق بخصوص التخطيط لإجازة:
• النوع: ${leaveTypeLabel(_leaveType)}
• الفترة: من $startStr إلى $endStr
• المدة: $count ${count == 1 ? 'يوم' : 'أيام'}
• موقف الرصيد: ${isSufficient ? 'يغطي المدة بالكامل (المتبقي: ${fmtUnits(remaining)} يوم)' : 'يحتاج مراجعة'}

أردت التنسيق معكم مسبقاً لضمان سير العمل بالقسم بكل سلاسة 🌿
— منظومة جمعية أحلى شباب الإدارية
'''.trim();
                  WhatsAppShareService.shareText(text);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
