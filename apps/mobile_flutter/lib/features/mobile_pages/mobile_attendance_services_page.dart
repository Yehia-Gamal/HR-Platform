import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_corrections_section.dart';
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
        onPressed: () => showAttendanceCorrectionSheet(context, ref),
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
              AttendanceCorrectionsSection(highlightId: highlightId),
            ],
          ),
        ),
      ),
    );
  }

  String _dayStatus(String value) => switch (value) {
    'scheduled' => 'عمل',
    'rest' => 'راحة',
    'holiday' => 'عطلة',
    'leave' => 'إجازة',
    'mission' => 'مأمورية',
    _ => value,
  };
}
