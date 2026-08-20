import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// قسم «طلبات التصحيح» القابل لإعادة الاستخدام — يُعرض داخل صفحة الحضور
/// وصفحة «جدولي وتصحيحات الحضور».
class AttendanceCorrectionsSection extends ConsumerWidget {
  const AttendanceCorrectionsSection({this.highlightId, super.key});

  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(myAttendanceServicesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: MobileSectionHeader(title: 'طلبات التصحيح')),
            IconButton.filledTonal(
              tooltip: 'طلب تصحيح',
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              onPressed: () => showAttendanceCorrectionSheet(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 10),
        catalog.when(
          loading: () => const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ),
          error: (error, _) => Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('تعذر تحميل طلبات التصحيح'),
              subtitle: Text(
                humanizeError(error),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'إعادة المحاولة',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.invalidate(myAttendanceServicesProvider),
              ),
            ),
          ),
          data: (catalog) {
            if (catalog.corrections.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Icon(
                        Icons.edit_calendar_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'لا توجد طلبات تصحيح حضور.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }
            return Column(
              children: catalog.corrections.map((item) {
                final isHighlighted = item.id == highlightId;
                final scheme = Theme.of(context).colorScheme;
                return Card(
                  shape: isHighlighted
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: scheme.primary, width: 2),
                        )
                      : null,
                  color: isHighlighted
                      ? scheme.primaryContainer.withValues(alpha: .15)
                      : null,
                  child: ListTile(
                    leading: Icon(
                      item.status == 'approved'
                          ? Icons.check_circle_outline
                          : item.status == 'rejected'
                          ? Icons.cancel_outlined
                          : Icons.schedule_outlined,
                      color: item.status == 'approved'
                          ? const Color(0xFF0F9F6E)
                          : item.status == 'rejected'
                          ? const Color(0xFFDC3D4B)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      '${_correctionType(item.type)} · ${DateFormat('d MMM y', 'ar').format(item.workDate)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${item.reason}${item.reviewNote == null ? '' : '\nرد المراجعة: ${item.reviewNote}'}',
                    ),
                    trailing: MobileStatusPill(item.status),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

/// فتح نافذة إنشاء طلب تصحيح حضور.
Future<void> showAttendanceCorrectionSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  DateTime workDate = DateTime.now().subtract(const Duration(days: 1));
  String type = 'missing_check_in';
  final reason = TextEditingController();
  // 0439: نعرض وقت البصمة المتوقع من جدول الموظف عند اختيار اليوم ونوع التصحيح.
  final schedule =
      ref.read(myAttendanceServicesProvider).asData?.value.schedule ??
      const <MobileScheduleDay>[];
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setState) {
        final day = _scheduleDayFor(schedule, workDate);
        final expectedLabel = _expectedTimeLabel(type, day);
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'طلب تصحيح حضور',
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('يوم العمل'),
                subtitle: Text(DateFormat('d MMMM y', 'ar').format(workDate)),
                trailing: const Tooltip(
                  message: 'اختيار يوم العمل',
                  child: Icon(Icons.calendar_month_outlined),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetContext,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now(),
                    initialDate: workDate,
                  );
                  if (picked != null) setState(() => workDate = picked);
                },
              ),
              DropdownButtonFormField<String>(
                value: type,
                decoration: const InputDecoration(labelText: 'نوع التصحيح'),
                items: const [
                  DropdownMenuItem(
                    value: 'missing_check_in',
                    child: Text('بصمة حضور ناقصة'),
                  ),
                  DropdownMenuItem(
                    value: 'missing_check_out',
                    child: Text('بصمة انصراف ناقصة'),
                  ),
                  DropdownMenuItem(
                    value: 'wrong_time',
                    child: Text('وقت غير صحيح'),
                  ),
                  DropdownMenuItem(
                    value: 'wrong_status',
                    child: Text('حالة اليوم غير صحيحة'),
                  ),
                  DropdownMenuItem(value: 'mission', child: Text('مأمورية')),
                  DropdownMenuItem(value: 'leave', child: Text('إجازة')),
                  DropdownMenuItem(value: 'other', child: Text('أخرى')),
                ],
                onChanged: (value) => setState(() => type = value ?? 'other'),
              ),
              // 0439: وقت البصمة المتوقع لليوم المختار حسب نوع التصحيح.
              if (expectedLabel != null) ...[
                const SizedBox(height: 12),
                _ExpectedTimeTile(
                  label: expectedLabel,
                  shiftName: day?.shiftName,
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'سبب التصحيح',
                  hintText: 'اشرح ما حدث بوضوح',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: const Text('إرسال للمراجعة'),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (accepted != true) {
    reason.dispose();
    return;
  }
  if (reason.text.trim().length < 5) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال 5 أحرف على الأقل لسبب التصحيح'),
        ),
      );
    }
    reason.dispose();
    return;
  }
  try {
    await ref
        .read(mobileCommandsProvider)
        .requestAttendanceCorrection(
          workDate: workDate,
          type: type,
          reason: reason.text,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال طلب التصحيح.')));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
    }
  } finally {
    reason.dispose();
  }
}

String _correctionType(String value) => switch (value) {
  'missing_check_in' => 'حضور ناقص',
  'missing_check_out' => 'انصراف ناقص',
  'wrong_time' => 'وقت خاطئ',
  'wrong_status' => 'حالة خاطئة',
  'mission' => 'مأمورية',
  'leave' => 'إجازة',
  _ => 'تصحيح',
};

/// 0439: البحث عن يوم العمل في الجدول (للعرض فقط — لا يعدّل الطلب).
MobileScheduleDay? _scheduleDayFor(
  List<MobileScheduleDay> schedule,
  DateTime date,
) {
  for (final s in schedule) {
    if (s.workDate.year == date.year &&
        s.workDate.month == date.month &&
        s.workDate.day == date.day) {
      return s;
    }
  }
  return null;
}

/// 0439: نص الوقت المتوقع حسب نوع التصحيح — null إذا لم يوجد وقت أو لا يناسب النوع.
String? _expectedTimeLabel(String type, MobileScheduleDay? day) {
  if (day == null) return null;
  final start = _fmtShiftTime(day.startTime);
  final end = _fmtShiftTime(day.endTime);
  switch (type) {
    case 'missing_check_in':
      return start.isEmpty ? null : 'وقت الدخول المتوقع: $start';
    case 'missing_check_out':
      return end.isEmpty ? null : 'وقت الخروج المتوقع: $end';
    case 'wrong_time':
      if (start.isNotEmpty && end.isNotEmpty) {
        return 'وقتا الوردية المتوقعان: $start — $end';
      }
      if (start.isNotEmpty) return 'الوقت المتوقع: $start';
      if (end.isNotEmpty) return 'الوقت المتوقع: $end';
      return null;
    default:
      return null;
  }
}

/// تنظيف صيغة الوقت من الخادم: "09:00:00" ← "09:00".
String _fmtShiftTime(String? value) {
  if (value == null || value.isEmpty) return '';
  if (value.length >= 8 && value.endsWith(':00')) {
    return value.substring(0, 5);
  }
  return value;
}

/// بطاقة صغيرة توضح الوقت المتوقع للتصحيح حسب اليوم والنوع.
class _ExpectedTimeTile extends StatelessWidget {
  const _ExpectedTimeTile({required this.label, this.shiftName});
  final String label;
  final String? shiftName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              shiftName == null ? label : '$label — وردية: $shiftName',
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
