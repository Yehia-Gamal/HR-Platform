import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ملف الموظف الشامل (قراءة فقط) — يُعرض للمدير المباشر/HR عبر get_employee_360 (V22).
class EmployeeProfilePage extends ConsumerWidget {
  const EmployeeProfilePage({
    required this.employeeId,
    this.employeeName,
    super.key,
  });

  final String employeeId;
  final String? employeeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(employee360Provider(employeeId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(employeeName ?? 'ملف الموظف'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => ref.invalidate(employee360Provider(employeeId)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(employee360Provider(employeeId)),
          child: profile.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 40,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      humanizeError(error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(employee360Provider(employeeId)),
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
            data: (emp) => _ProfileBody(employee: emp),
          ),
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.employee});

  final Employee360 employee;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeaderCard(employee: employee),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MonthlyAttendanceStatementPage(
                employeeId: employee.id,
                employeeName: employee.fullNameAr,
              ),
            ),
          ),
          icon: const Icon(Icons.calendar_month_rounded),
          label: const Text('كشف الحضور والانصراف الشهري'),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'بيانات التوظيف',
          children: [
            _Row('القسم', employee.department),
            _Row('الفريق', employee.team),
            _Row('الفرع', employee.branch),
            _Row('موقع العمل', employee.workSite),
            _Row('الدرجة', employee.grade),
            _Row('المسمى الوظيفي', employee.jobTitle),
            _Row('المنصب', employee.position),
            _Row('المدير المباشر', employee.managerName),
            _Row('تاريخ التعيين', _fmtDate(employee.hireDate)),
            _Row('نهاية العقد', _fmtDate(employee.contractEnd)),
            _Row('نهاية فترة التجربة', _fmtDate(employee.probationEnd)),
            if (employee.email != null) _Row('البريد الإلكتروني', employee.email),
          ],
        ),
        if (employee.roles.isNotEmpty)
          _SectionCard(
            title: 'الأدوار',
            children: [
              _Row('الأدوار', employee.roles.map((r) => r.name).join('، ')),
            ],
          ),
        if (employee.departments.isNotEmpty)
          _SectionCard(
            title: 'الأقسام المرتبطة',
            children: employee.departments
                .map(
                  (d) => _Row(
                    d.departmentName,
                    [
                      if (d.jobTitle != null) d.jobTitle!,
                      if (d.isPrimary) 'رئيسي',
                    ].join(' — '),
                  ),
                )
                .toList(),
          ),
        _SectionCard(
          title: 'الحضور آخر 30 يومًا',
          children: [
            Row(
              children: [
                _StatTile(
                  value: '${employee.attendance30.present}',
                  label: 'حضور',
                ),
                _StatTile(
                  value: '${employee.attendance30.lateDays}',
                  label: 'تأخيرات',
                ),
                _StatTile(
                  value: '${employee.attendance30.absent}',
                  label: 'غياب',
                ),
                _StatTile(
                  value: _fmtHours(employee.attendance30.workMinutes),
                  label: 'ساعات عمل',
                ),
              ],
            ),
          ],
        ),
        _SectionCard(
          title: 'الطلبات',
          children: [
            Row(
              children: [
                _StatTile(
                  value: '${employee.requestCounts.pending}',
                  label: 'معلّقة',
                ),
                _StatTile(
                  value: '${employee.requestCounts.approved}',
                  label: 'معتمدة',
                ),
                _StatTile(
                  value: '${employee.requestCounts.rejected}',
                  label: 'مرفوضة',
                ),
              ],
            ),
          ],
        ),
        if (employee.latestKpi != null)
          _SectionCard(
            title: 'آخر تقييم KPI',
            children: [
              _Row('دورة التقييم', employee.latestKpi!.periodMonth),
              _Row('المرحلة الحالية', employee.latestKpi!.currentStage),
              if (employee.latestKpi!.finalScore != null)
                _Row('النتيجة النهائية', '${employee.latestKpi!.finalScore}'),
              if (employee.latestKpi!.finalRating != null)
                _Row('التقدير', employee.latestKpi!.finalRating),
            ],
          ),
        if (employee.documents.isNotEmpty)
          _SectionCard(
            title: 'المستندات',
            children: employee.documents
                .map(
                  (d) => _Row(
                    d.title.isEmpty ? d.type : '${d.type} — ${d.title}',
                    [
                      if (d.expiryDate != null) 'ينتهي ${_fmtDate(d.expiryDate)}',
                      _docStatusLabel(d.status),
                    ].join(' · '),
                  ),
                )
                .toList(),
          ),
        if (employee.assets.isNotEmpty)
          _SectionCard(
            title: 'الأصول (العهد)',
            children: employee.assets
                .map(
                  (a) => _Row(
                    a.assetName,
                    [
                      if (a.assetType.isNotEmpty) a.assetType,
                      if (a.serial != null) 'رقم: ${a.serial}',
                      if (a.handedOverAt != null)
                        'استلم ${_fmtDate(a.handedOverAt)}',
                      if (a.returnedAt != null) 'أُعيد ${_fmtDate(a.returnedAt)}',
                    ].join(' · '),
                  ),
                )
                .toList(),
          ),
        if (employee.recentRequests.isNotEmpty)
          _SectionCard(
            title: 'أحدث الطلبات',
            children: employee.recentRequests
                .map(
                  (r) => _Row(
                    r.title ?? r.requestType,
                    '${_reqStatusLabel(r.status)} — #${r.requestNumber}',
                  ),
                )
                .toList(),
          ),
        if (employee.recentTasks.isNotEmpty)
          _SectionCard(
            title: 'المهام الأخيرة',
            children: employee.recentTasks
                .map(
                  (t) => _Row(
                    t.title,
                    [
                      if (t.priority != null) t.priority!,
                      _taskStatusLabel(t.status),
                      if (t.dueDate != null) 'استحقاق ${_fmtDate(t.dueDate)}',
                    ].join(' · '),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.employee});

  final Employee360 employee;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountStatus = employee.accountStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppAvatar(name: employee.fullNameAr, photoUrl: employee.photoUrl, radius: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullNameAr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (employee.fullNameEn?.isNotEmpty ?? false)
                        Text(
                          employee.fullNameEn!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (employee.jobTitle?.isNotEmpty ?? false)
                            employee.jobTitle!,
                          if (employee.position?.isNotEmpty ?? false)
                            employee.position!,
                        ].join(' — '),
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        'كود الموظف: ${employee.employeeCode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (accountStatus != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(_accountStatusLabel(accountStatus)),
                    backgroundColor: _statusColor(
                      context,
                      accountStatus,
                    ).withValues(alpha: .14),
                    side: BorderSide(
                      color: _statusColor(context, accountStatus),
                    ),
                  ),
                if (employee.managerName?.isNotEmpty ?? false)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.manage_accounts_outlined, size: 16),
                    label: Text('يتبعه: ${employee.managerName}'),
                  ),
                if (employee.directReports > 0)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.groups_2_outlined, size: 16),
                    label: Text('فريق مباشر: ${employee.directReports}'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v == null || v.isEmpty ? '—' : v,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtDate(DateTime? date) {
  if (date == null) return '—';
  final y = date.year;
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$d/$m/$y';
}

String _fmtHours(int minutes) {
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  return hours > 0 ? '$hoursس $remد' : '$remد';
}

Color _statusColor(BuildContext context, String status) =>
    switch (status) {
      'active' => Colors.green,
      'terminated' => Colors.red,
      'suspended' => Colors.orange,
      'invited' => Colors.blue,
      'pending' => Colors.amber,
      'probation_failed' => Colors.redAccent,
      'notice_period' => Colors.teal,
      'inactive' => Colors.grey,
      _ => Theme.of(context).colorScheme.primary,
    };

String _accountStatusLabel(String status) => switch (status) {
  'active' => 'على رأس العمل',
  'terminated' => 'منتهي/مُنهى',
  'suspended' => 'موقوف',
  'invited' => 'مدعو',
  'pending' => 'قيد التفعيل',
  'probation_failed' => 'راسب في التجربة',
  'notice_period' => 'فترة إنذار',
  'inactive' => 'غير نشط',
  _ => status,
};

String _docStatusLabel(String status) => switch (status) {
  'active' => 'ساري',
  'expiring' => 'قارب على الانتهاء',
  'expired' => 'منتهي',
  _ => status,
};

String _reqStatusLabel(String status) => switch (status) {
  'pending' => 'معلّقة',
  'approved' => 'معتمدة',
  'rejected' => 'مرفوضة',
  'cancelled' => 'ملغاة',
  _ => status,
};

String _taskStatusLabel(String status) => switch (status) {
  'pending' => 'قيد الانتظار',
  'in_progress' => 'قيد التنفيذ',
  'completed' => 'مكتملة',
  'overdue' => 'متأخرة',
  _ => status,
};
