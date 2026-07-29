import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class MobileAttendanceServicesPage extends ConsumerWidget {
  const MobileAttendanceServicesPage({this.highlightId, super.key});
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(myAttendanceServicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('جدولي وتصحيحات الحضور')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createCorrection(context, ref),
        icon: const Icon(Icons.edit_calendar_outlined),
        label: const Text('طلب تصحيح'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myAttendanceServicesProvider),
        child: data.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 160),
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
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(myAttendanceServicesProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (catalog) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              const MobileSectionHeader(title: 'جدول العمل القادم'),
              const SizedBox(height: 10),
              if (catalog.schedule.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Icon(
                          Icons.event_busy_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'لم يُنشر لك جدول ورديات خلال الفترة الحالية.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...catalog.schedule
                    .take(45)
                    .map(
                      (day) => Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            child: Text(
                              DateFormat('d', 'ar').format(day.workDate),
                            ),
                          ),
                          title: Text(
                            day.shiftName ?? _dayStatus(day.dayStatus),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '${DateFormat('EEEE، d MMM', 'ar').format(day.workDate)}${day.startTime == null ? '' : ' · ${day.startTime} — ${day.endTime ?? ''}'}',
                          ),
                          trailing: MobileStatusPill(day.dayStatus),
                        ),
                      ),
                    ),
              const SizedBox(height: 22),
              const MobileSectionHeader(title: 'طلبات التصحيح'),
              const SizedBox(height: 10),
              if (catalog.corrections.isEmpty)
                Card(
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
                )
              else
                ...catalog.corrections.map(
                  (item) {
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
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createCorrection(BuildContext context, WidgetRef ref) async {
    DateTime workDate = DateTime.now().subtract(const Duration(days: 1));
    String type = 'missing_check_in';
    final reason = TextEditingController();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
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
        ),
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

  String _dayStatus(String value) => switch (value) {
    'scheduled' => 'عمل',
    'rest' => 'راحة',
    'holiday' => 'عطلة',
    'leave' => 'إجازة',
    'mission' => 'مأمورية',
    _ => value,
  };
  String _correctionType(String value) => switch (value) {
    'missing_check_in' => 'حضور ناقص',
    'missing_check_out' => 'انصراف ناقص',
    'wrong_time' => 'وقت خاطئ',
    'wrong_status' => 'حالة خاطئة',
    'mission' => 'مأمورية',
    'leave' => 'إجازة',
    _ => 'تصحيح',
  };
}
