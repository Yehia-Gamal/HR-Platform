import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class ExecutiveEmployeeSummaryPage extends ConsumerWidget {
  const ExecutiveEmployeeSummaryPage({
    required this.employeeId,
    required this.employeeName,
    super.key,
  });

  final String employeeId;
  final String employeeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(
      mobileExecutiveEmployeeSummaryProvider(employeeId),
    );
    return Scaffold(
      appBar: AppBar(title: Text(employeeName)),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(mobileExecutiveEmployeeSummaryProvider(employeeId)),
        child: summary.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 230),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 90),
              Icon(
                Icons.person_off_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                humanizeError(error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () => ref.invalidate(
                    mobileExecutiveEmployeeSummaryProvider(employeeId),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ),
            ],
          ),
          data: (item) => _content(context, item),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, ExecutiveEmployeeSummary item) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Semantics(
                  label: item.name,
                  child: CircleAvatar(
                    radius: 34,
                    backgroundImage: item.photoUrl == null
                        ? null
                        : NetworkImage(item.photoUrl!),
                    child: item.photoUrl == null
                        ? Text(
                            item.name.isEmpty ? '؟' : item.name[0],
                            style: const TextStyle(fontSize: 25),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(item.jobTitle ?? item.position ?? '—'),
                      Text(
                        item.employeeCode,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                MobileStatusPill(item.status),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        MetricGrid(
          cards: [
            (
              'طلبات معلقة',
              item.pendingRequests.toString(),
              Icons.approval_rounded,
              null,
            ),
            ('مهام مفتوحة', item.openTasks.toString(), Icons.task_outlined, null),
            (
              'KPI الأخير',
              item.latestKpi?.score?.toStringAsFixed(1) ?? '—',
              Icons.analytics_outlined,
              null,
            ),
            (
              'وثائق قريبة',
              item.expiringDocuments.toString(),
              Icons.warning_amber_rounded,
              null,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MobileSectionHeader(title: 'الملخص التنظيمي'),
                const SizedBox(height: 8),
                _info(Icons.account_tree_outlined, 'الإدارة', item.department),
                _info(Icons.groups_outlined, 'الفريق', item.team),
                _info(Icons.business_outlined, 'الفرع', item.branch),
                _info(Icons.location_on_outlined, 'موقع العمل', item.workSite),
                _info(
                  Icons.supervisor_account_outlined,
                  'المدير المباشر',
                  item.managerName,
                ),
                _info(
                  Icons.event_outlined,
                  'تاريخ التعيين',
                  item.hireDate == null
                      ? null
                      : DateFormat('d MMM y', 'ar').format(item.hireDate!),
                ),
              ],
            ),
          ),
        ),
        if (item.latestKpi != null) ...[
          const SizedBox(height: 14),
          Card(
            color: scheme.primaryContainer.withValues(alpha: .45),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const CircleAvatar(child: Icon(Icons.speed_rounded)),
              title: const Text(
                'آخر تقييم أداء',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text(
                '${_kpiStage(item.latestKpi!.stage)}${item.latestKpi!.periodMonth == null ? '' : ' · ${DateFormat('MMMM y', 'ar').format(item.latestKpi!.periodMonth!)}'}',
              ),
              trailing: Text(
                item.latestKpi!.score?.toStringAsFixed(1) ?? '—',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        const MobileSectionHeader(
          title: 'الحضور الحديث',
          subtitle: 'آخر 14 سجلًا مجمعًا دون عرض بيانات تحقق حساسة.',
        ),
        const SizedBox(height: 10),
        if (item.recentAttendance.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: Text('لا توجد سجلات حضور حديثة.')),
            ),
          )
        else
          Card(
            child: Column(
              children: item.recentAttendance
                  .map(
                    (attendance) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: _attendanceColor(
                          context,
                          attendance.status,
                        ).withValues(alpha: .12),
                        child: Icon(
                          _attendanceIcon(attendance.status),
                          color: _attendanceColor(context, attendance.status),
                        ),
                      ),
                      title: Text(
                        DateFormat(
                          'EEEE، d MMM',
                          'ar',
                        ).format(attendance.workDate),
                      ),
                      subtitle: Text(
                        attendance.lateMinutes > 0
                            ? 'تأخير ${attendance.lateMinutes} دقيقة'
                            : '${(attendance.workMinutes / 60).toStringAsFixed(1)} ساعة عمل',
                      ),
                      trailing: Text(
                        _attendanceLabel(attendance.status),
                        style: TextStyle(
                          color: _attendanceColor(context, attendance.status),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExecutiveLocationPage()),
          ),
          icon: const Icon(Icons.location_searching_rounded),
          label: const Text('فتح دليل الموقع وطلب تحقق مصرح'),
        ),
        const SizedBox(height: 12),
        Text(
          'آخر تحديث ${DateFormat('d MMM، h:mm a', 'ar').format(item.lastUpdatedAt.toLocal())}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  static Widget _info(IconData icon, String label, String? value) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    trailing: SizedBox(
      width: 165,
      child: Text(
        value ?? '—',
        textAlign: TextAlign.end,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  static String _kpiStage(String value) => switch (value) {
    'self' => 'تقييم ذاتي',
    'manager' => 'مراجعة المدير',
    'hr' => 'مراجعة HR',
    'secretary' => 'المراجعة التنفيذية',
    'executive' => 'الاعتماد التنفيذي',
    'finalized' => 'مكتمل',
    _ => value,
  };

  static String _attendanceLabel(String value) => switch (value) {
    'present' => 'حاضر',
    'late' => 'متأخر',
    'partial' => 'جزئي',
    'on_leave' => 'إجازة',
    'absent' => 'غائب',
    'holiday' => 'عطلة',
    'weekend' => 'راحة',
    _ => value,
  };

  static IconData _attendanceIcon(String value) => switch (value) {
    'present' => Icons.check_rounded,
    'late' => Icons.schedule_rounded,
    'on_leave' => Icons.event_busy_outlined,
    'absent' => Icons.person_off_outlined,
    _ => Icons.event_outlined,
  };

  Color _attendanceColor(BuildContext context, String value) {
    final scheme = Theme.of(context).colorScheme;
    return switch (value) {
      'present' => const Color(0xFF0F9F6E),
      'late' => const Color(0xFFD98508),
      'absent' => const Color(0xFFDC3D4B),
      'on_leave' => scheme.primary,
      _ => scheme.onSurfaceVariant,
    };
  }
}
