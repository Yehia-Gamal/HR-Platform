import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/phone_display.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/today_status_style.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// ملف الموظف — get_employee_360.
///
/// الملف الأساسي (البطاقة، حالته اليوم بوضوح، مديره المباشر وفريقه، بيانات
/// الوظيفة، أدواره) متاح لكل منسوبي الجمعية. التفاصيل (أوقات الحضور
/// والتأخير، الحضور الشهري، الطلبات، المهام، التواصل والتواريخ) لمن يملك
/// قراءة ملفه فقط: هو، مديره المباشر، الإدارة التنفيذية، الموارد البشرية.
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
    final me = ref.watch(accessContextProvider).value;
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
            data: (emp) => _ProfileBody(
              employee: emp,
              detailed: _canSeeDetails(emp, me),
            ),
          ),
        ),
      ),
    );
  }
}

/// الخادم (0631) يحدد النطاق؛ مع خادم أقدم نقدّره من أدوار المستخدم.
bool _canSeeDetails(Employee360 employee, AccessContext? me) {
  final scope = employee.viewerScope;
  if (scope != null) return scope == 'full';
  if (me == null) return true;
  final myId = me.employeeId;
  if (myId != null && (myId == employee.id || myId == employee.managerId)) {
    return true;
  }
  const privileged = {
    'admin',
    'system-admin',
    'executive-secretary',
    'executive',
    'executive-director',
    'hr-manager',
    'hr-specialist',
    'operations-manager',
    'operations-manager-1',
    'operations-manager-2',
    'clinics-manager',
  };
  return me.roles.any(privileged.contains);
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({required this.employee, required this.detailed});

  final Employee360 employee;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final code = PhoneDisplay.stripCountryCode(employee.employeeCode);
    final phone = PhoneDisplay.stripCountryCode(employee.phoneE164);
    // الحقول الفارغة لا تُعرض؛ المدير المباشر في «الهيكل الإداري».
    final employment = <(String, String?)>[
      ('القسم', employee.department),
      ('الفريق', employee.team),
      ('الفرع', employee.branch),
      ('موقع العمل', employee.workSite),
      ('المسمى الوظيفي', employee.jobTitle),
      ('المنصب', employee.position),
      if (detailed) ...[
        ('الدرجة', employee.grade),
        ('تاريخ التعيين', _fmtDateOrNull(employee.hireDate)),
        ('مدة الخدمة', _serviceLength(employee.hireDate)),
        ('نهاية العقد', _fmtDateOrNull(employee.contractEnd)),
        ('نهاية فترة التجربة', _fmtDateOrNull(employee.probationEnd)),
        if (phone != code) ('رقم الهاتف', phone),
        ('البريد الإلكتروني', employee.email),
      ],
    ].where((row) => _hasText(row.$2)).toList(growable: false);
    final kpi = employee.latestKpi;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _HeroCard(employee: employee, detailed: detailed, code: code),
        const SizedBox(height: 12),
        if (detailed)
          TodayStatusSection(
            todayStatus: employee.todayStatus,
            title: 'تفاصيل حضور اليوم',
            showStatusPill: false,
          ),
        _OrgTreeCard(employee: employee),
        if (detailed)
          _MonthlyAttendanceCard(
            employeeId: employee.id,
            employeeName: employee.fullNameAr,
          ),
        if (employment.isNotEmpty)
          _SectionCard(
            title: 'بيانات الوظيفة',
            icon: Icons.work_outline_rounded,
            children: [for (final row in employment) _Row(row.$1, row.$2)],
          ),
        _RolesCard(roles: employee.roles),
        // قسم واحد = نفس «القسم» في بيانات الوظيفة؛ تُعرض فقط عند تعدد الأقسام.
        if (employee.departments.length > 1)
          _SectionCard(
            title: 'الأقسام المرتبطة',
            icon: Icons.apartment_rounded,
            children: [
              for (final d in employee.departments)
                _Row(
                  d.departmentName,
                  [
                    if (_hasText(d.jobTitle)) d.jobTitle!.trim(),
                    d.isPrimary ? 'القسم الرئيسي' : 'قسم إضافي',
                  ].join(' — '),
                ),
            ],
          ),
        if (detailed) ...[
          _SectionCard(
            title: 'الطلبات',
            icon: Icons.description_outlined,
            children: [
              Row(
                children: [
                  _StatTile(
                    value: '${employee.requestCounts.pending}',
                    label: 'معلّقة',
                    color: employee.requestCounts.pending > 0
                        ? AppColors.statusWarning
                        : null,
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
              if (employee.recentRequests.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 16),
                Text(
                  'أحدث الطلبات',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                ..._separated([
                  for (final r in employee.recentRequests.take(5))
                    _RequestTile(request: r),
                ]),
              ],
            ],
          ),
          if (kpi != null)
            _SectionCard(
              title: 'آخر تقييم KPI',
              icon: Icons.insights_rounded,
              children: [
                _Row('دورة التقييم', _fmtMonth(kpi.periodMonth)),
                _Row('المرحلة الحالية', kpiStageLabel(kpi.currentStage)),
                if (kpi.finalScore != null)
                  _Row('النتيجة النهائية', '${kpi.finalScore}'),
                if (kpi.finalRating != null) _Row('التقدير', kpi.finalRating),
              ],
            ),
          if (employee.recentTasks.isNotEmpty)
            _SectionCard(
              title: 'المهام الأخيرة',
              icon: Icons.task_alt_rounded,
              children: _separated([
                for (final t in employee.recentTasks.take(5)) _TaskTile(task: t),
              ]),
            ),
          if (employee.documents.isNotEmpty)
            _SectionCard(
              title: 'المستندات',
              icon: Icons.folder_open_rounded,
              children: [
                for (final d in employee.documents)
                  _Row(
                    d.title.isEmpty ? d.type : '${d.type} — ${d.title}',
                    [
                      if (d.expiryDate != null)
                        'ينتهي ${_fmtDate(d.expiryDate)}',
                      _docStatusLabel(d.status),
                    ].join(' · '),
                  ),
              ],
            ),
          if (employee.assets.isNotEmpty)
            _SectionCard(
              title: 'الأصول (العهد)',
              icon: Icons.inventory_2_outlined,
              children: [
                for (final a in employee.assets)
                  _Row(
                    a.assetName,
                    [
                      if (a.assetType.isNotEmpty) a.assetType,
                      if (a.serial != null) 'رقم: ${a.serial}',
                      if (a.handedOverAt != null)
                        'استلم ${_fmtDate(a.handedOverAt)}',
                      if (a.returnedAt != null)
                        'أُعيد ${_fmtDate(a.returnedAt)}',
                    ].join(' · '),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// البطاقة الرئيسية: الصورة بحلقة بلون حالة اليوم + الاسم والوظيفة + الحالة
// اليوم بوضوح (للجميع).
// ---------------------------------------------------------------------------
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.employee,
    required this.detailed,
    required this.code,
  });

  final Employee360 employee;
  final bool detailed;
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = _DisplayStatus.of(employee.todayStatus, detailed: detailed);
    final subtitle = [
      if (_hasText(employee.jobTitle)) employee.jobTitle!.trim(),
      if (_hasText(employee.position)) employee.position!.trim(),
    ].join(' — ');
    // «على رأس العمل» هو الطبيعي فلا يُعرض؛ يظهر التنبيه فقط إن لم يكن الحساب نشطًا.
    final account = employee.accountStatus;
    final accountNote = detailed && account != null && account != 'active'
        ? _accountStatusNote(account)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: today.color, width: 2.5),
                  ),
                  child: AppAvatar(
                    name: employee.fullNameAr,
                    photoUrl: employee.photoUrl,
                    radius: 34,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employee.fullNameAr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (_hasText(employee.department))
                        Text(
                          employee.department!.trim(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (code.isNotEmpty)
                        Text(
                          'كود الموظف: $code',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: today.color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: today.color.withValues(alpha: .35)),
              ),
              child: Row(
                children: [
                  Icon(today.icon, color: today.color, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'حالته اليوم',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          today.destination == null
                              ? today.label
                              : '${today.label} — ${today.destination}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: today.color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (accountNote != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.statusWarning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      accountNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.statusWarning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الهيكل الإداري: مديره المباشر ← الموظف ← فريقه المباشر بأسمائهم وحالاتهم.
// ---------------------------------------------------------------------------
class _OrgTreeCard extends StatelessWidget {
  const _OrgTreeCard({required this.employee});

  final Employee360 employee;

  /// موضع خط الشجرة من بداية السطر = مركز صورة البطاقة (حشوة 10 + نصف القطر 20).
  static const double _lineX = 30;
  static const double _gutter = 46;

  void _open(BuildContext context, Employee360Person person) {
    if (person.id.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeProfilePage(
          employeeId: person.id,
          employeeName: person.fullNameAr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lineColor = scheme.outlineVariant;
    final manager = employee.manager ??
        (_hasText(employee.managerName)
            ? Employee360Person(
                id: employee.managerId ?? '',
                fullNameAr: employee.managerName!.trim(),
              )
            : null);
    final team = employee.teamMembers;
    // خادم أقدم من 0631 يرسل العدد فقط بلا أسماء.
    final hiddenTeamCount = team.isEmpty ? employee.directReports : 0;

    Widget caption(String text) => Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );

    Widget link({double height = 16, Widget? child}) => SizedBox(
      height: child == null ? height : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _gutter,
            child: CustomPaint(
              painter: _TreeLinePainter(
                color: lineColor,
                lineX: _lineX,
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
            ),
          ),
          if (child != null)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: child,
              ),
            ),
        ],
      ),
    );

    return _SectionCard(
      title: 'الهيكل الإداري',
      icon: Icons.account_tree_rounded,
      children: [
        if (manager != null) ...[
          caption('مديره المباشر'),
          const SizedBox(height: 6),
          _PersonNode(
            person: manager,
            onTap: manager.id.isEmpty ? null : () => _open(context, manager),
          ),
          link(),
        ] else ...[
          caption('أعلى الهيكل الإداري — لا يتبع مديرًا مباشرًا'),
          const SizedBox(height: 6),
        ],
        _PersonNode(
          person: Employee360Person(
            id: employee.id,
            fullNameAr: employee.fullNameAr,
            jobTitle: employee.jobTitle,
            photoUrl: employee.photoUrl,
          ),
          highlighted: true,
        ),
        if (team.isNotEmpty) ...[
          IntrinsicHeight(
            child: link(child: caption('فريقه المباشر (${team.length})')),
          ),
          for (var i = 0; i < team.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutter,
                    child: CustomPaint(
                      painter: _TreeLinePainter(
                        color: lineColor,
                        lineX: _lineX,
                        rtl: Directionality.of(context) == TextDirection.rtl,
                        elbow: true,
                        last: i == team.length - 1,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _PersonNode(
                        person: team[i],
                        compact: true,
                        onTap: () => _open(context, team[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ] else if (hiddenTeamCount > 0) ...[
          const SizedBox(height: 10),
          caption('فريقه المباشر: $hiddenTeamCount'),
        ],
      ],
    );
  }
}

class _TreeLinePainter extends CustomPainter {
  _TreeLinePainter({
    required this.color,
    required this.lineX,
    required this.rtl,
    this.elbow = false,
    this.last = false,
  });

  final Color color;
  final double lineX;
  final bool rtl;

  /// فرع إلى بطاقة عضو (خط أفقي حتى نهاية الهامش).
  final bool elbow;

  /// آخر عضو: الخط الرأسي ينتهي عند الفرع بانحناءة.
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final x = rtl ? size.width - lineX : lineX;
    if (!elbow) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      return;
    }
    final midY = size.height / 2;
    final endX = rtl ? 0.0 : size.width;
    const radius = 8.0;
    final dir = rtl ? -1.0 : 1.0;
    if (last) {
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x, midY - radius)
        ..quadraticBezierTo(x, midY, x + dir * radius, midY)
        ..lineTo(endX, midY);
      canvas.drawPath(path, paint);
    } else {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      canvas.drawLine(Offset(x, midY), Offset(endX, midY), paint);
    }
  }

  @override
  bool shouldRepaint(_TreeLinePainter old) =>
      old.color != color ||
      old.rtl != rtl ||
      old.elbow != elbow ||
      old.last != last ||
      old.lineX != lineX;
}

class _PersonNode extends StatelessWidget {
  const _PersonNode({
    required this.person,
    this.highlighted = false,
    this.compact = false,
    this.onTap,
  });

  final Employee360Person person;
  final bool highlighted;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasStatus = person.status != null;
    final status = hasStatus
        ? _DisplayStatus.of(
            Employee360TodayStatus(
              status: person.status,
              statusLabel: person.statusLabel,
              activityTitle: person.activityTitle,
            ),
            detailed: true,
          )
        : null;

    return Material(
      color: highlighted
          ? scheme.primaryContainer.withValues(alpha: .45)
          : scheme.surfaceContainerHighest.withValues(alpha: .45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: highlighted
              ? scheme.primary.withValues(alpha: .55)
              : scheme.outlineVariant.withValues(alpha: .6),
          width: highlighted ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              AppAvatar(
                name: person.fullNameAr,
                photoUrl: person.photoUrl,
                radius: compact ? 17 : 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.fullNameAr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_hasText(person.jobTitle))
                      Text(
                        person.jobTitle!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (status != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: status.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              status.destination == null
                                  ? status.label
                                  : '${status.label} — ${status.destination}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: status.color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الحضور الشهري (الشهر الحالي أو الماضي) — من كشف الحضور الرسمي نفسه.
// ---------------------------------------------------------------------------
class _MonthlyAttendanceCard extends ConsumerStatefulWidget {
  const _MonthlyAttendanceCard({
    required this.employeeId,
    required this.employeeName,
  });

  final String employeeId;
  final String employeeName;

  @override
  ConsumerState<_MonthlyAttendanceCard> createState() =>
      _MonthlyAttendanceCardState();
}

class _MonthlyAttendanceCardState
    extends ConsumerState<_MonthlyAttendanceCard> {
  late final DateTime _current;
  late final DateTime _previous;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _current = DateTime(now.year, now.month);
    _previous = DateTime(now.year, now.month - 1);
    _selected = _current;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statement = ref.watch(
      employeeMonthlyStatementProvider(
        (widget.employeeId, _selected.year, _selected.month),
      ),
    );
    // السنة بأرقام الصفحة نفسها (DateFormat العربي يكتبها ٢٠٢٦).
    String monthName(DateTime d) =>
        '${DateFormat('MMMM', 'ar').format(d)} ${d.year}';

    return _SectionCard(
      title: 'الحضور خلال ${monthName(_selected)}',
      icon: Icons.calendar_month_rounded,
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<DateTime>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _current,
                label: Text('الشهر الحالي (${DateFormat('MMMM', 'ar').format(_current)})'),
              ),
              ButtonSegment(
                value: _previous,
                label: Text('الشهر الماضي (${DateFormat('MMMM', 'ar').format(_previous)})'),
              ),
            ],
            selected: {_selected},
            onSelectionChanged: (s) => setState(() => _selected = s.first),
          ),
        ),
        const SizedBox(height: 14),
        statement.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              humanizeError(error),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          data: (st) {
            final s = st.summary;
            if (s.isAttendanceExempt) {
              return Text(
                'معفى من تسجيل الحضور والبصمة.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              );
            }
            final rate = st.attendancePercentage.clamp(0, 100).toDouble();
            final rateColor = rate >= 90
                ? AppColors.statusSuccess
                : rate >= 70
                ? AppColors.statusWarning
                : AppColors.statusDanger;
            final lateDays = st.days.where((d) => d.lateMinutes > 0).length;
            final offsiteDays = s.missionDays + s.convoyFundiDays;
            final notes = [
              'ساعات العمل: ${_fmtHours((s.totalWorkHours * 60).round())}',
              if (s.totalLateMinutes > 0)
                'إجمالي التأخير: ${_fmtMinutes(s.totalLateMinutes)}',
              if (s.missingCheckOutCount > 0)
                'أيام بلا انصراف: ${s.missingCheckOutCount}',
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'نسبة الحضور',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${rate.round()}%',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: rateColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: rate / 100,
                    minHeight: 8,
                    color: rateColor,
                    backgroundColor: rateColor.withValues(alpha: .15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'حضر ${s.attendanceRatePresentDays} من أصل ${_workDays(s.attendanceRateDueDays)}'
                  '${_selected == _current ? ' حتى اليوم' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatTile(
                      value: '${s.attendanceRatePresentDays}',
                      label: 'حضور',
                    ),
                    _StatTile(value: '$offsiteDays', label: 'خارج المقر'),
                    _StatTile(
                      value: '$lateDays',
                      label: 'تأخير',
                      color: lateDays > 0 ? AppColors.statusWarning : null,
                    ),
                    _StatTile(
                      value: '${s.absentDays}',
                      label: 'غياب',
                      color: s.absentDays > 0 ? AppColors.statusDanger : null,
                    ),
                    _StatTile(value: '${s.leaveDays}', label: 'إجازات'),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Text(
                    notes.join('  •  '),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MonthlyAttendanceStatementPage(
                employeeId: widget.employeeId,
                employeeName: widget.employeeName,
                initialYear: _selected.year,
                initialMonth: _selected.month,
              ),
            ),
          ),
          icon: const Icon(Icons.receipt_long_rounded),
          label: Text('كشف ${monthName(_selected)} بالتفصيل'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// الأدوار في المنظومة: كل دور بأيقونته ووصف مختصر لما يتيحه.
// ---------------------------------------------------------------------------
class _RolesCard extends StatelessWidget {
  const _RolesCard({required this.roles});

  final List<EmployeeRoleLink> roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final seen = <String>{};
    final unique = [
      for (final r in roles)
        if (r.name.trim().isNotEmpty && seen.add(r.name.trim())) r,
    ];
    // «موظف» دور أساسي لدى الجميع؛ يُعرض فقط إن لم يكن له دور غيره.
    final shown = unique.length > 1
        ? unique.where((r) => r.slug != 'employee').toList()
        : unique;
    if (shown.isEmpty) return const SizedBox.shrink();
    shown.sort((a, b) => _roleRank(a.slug).compareTo(_roleRank(b.slug)));

    return _SectionCard(
      title: 'الأدوار في المنظومة',
      icon: Icons.verified_user_outlined,
      children: _separated([
        for (final role in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _roleMeta(role.slug).$2.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _roleMeta(role.slug).$1,
                    size: 20,
                    color: _roleMeta(role.slug).$2,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.name.trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (_roleMeta(role.slug).$3.isNotEmpty)
                        Text(
                          _roleMeta(role.slug).$3,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ]),
    );
  }
}

int _roleRank(String slug) => switch (slug) {
  'executive-director' || 'executive' => 0,
  'executive-secretary' => 1,
  'admin' => 2,
  'system-admin' => 3,
  'hr-manager' => 4,
  'hr-specialist' => 5,
  'operations-manager' ||
  'operations-manager-1' ||
  'operations-manager-2' => 6,
  'department-manager' => 7,
  'clinics-manager' => 8,
  'direct-manager' => 9,
  'operations-officer' => 10,
  'committee-chair' => 11,
  'committee-secretary' => 12,
  'committee-member' => 13,
  'clinic-staff' => 14,
  _ => 20,
};

/// (أيقونة، لون، وصف مختصر) لكل دور.
(IconData, Color, String) _roleMeta(String slug) => switch (slug) {
  'executive-director' || 'executive' => (
    Icons.workspace_premium_rounded,
    const Color(0xFFB7791F),
    'الإدارة العليا للجمعية والاعتماد النهائي',
  ),
  'executive-secretary' => (
    Icons.event_note_rounded,
    AppColors.statusViolet,
    'متابعة أعمال المكتب التنفيذي',
  ),
  'admin' => (
    Icons.admin_panel_settings_rounded,
    AppColors.statusDanger,
    'إدارة المنظومة بكامل الصلاحيات',
  ),
  'system-admin' => (
    Icons.engineering_rounded,
    AppColors.statusInfo,
    'الدعم الفني وإعدادات المنظومة',
  ),
  'hr-manager' => (
    Icons.badge_rounded,
    AppColors.statusSuccess,
    'إدارة شؤون الموظفين والسياسات',
  ),
  'hr-specialist' => (
    Icons.badge_outlined,
    AppColors.statusSuccess,
    'متابعة ملفات الموظفين والحضور',
  ),
  'operations-manager' ||
  'operations-manager-1' ||
  'operations-manager-2' => (
    Icons.hub_rounded,
    AppColors.brandPrimary,
    'متابعة التشغيل اليومي لإداراته',
  ),
  'department-manager' => (
    Icons.apartment_rounded,
    AppColors.brandPrimary,
    'إدارة القسم وفريقه',
  ),
  'clinics-manager' => (
    Icons.medical_services_rounded,
    AppColors.statusInfo,
    'إدارة العيادات وفريقها',
  ),
  'direct-manager' => (
    Icons.supervisor_account_rounded,
    AppColors.brandPrimary,
    'يعتمد طلبات فريقه ويتابع حضورهم',
  ),
  'operations-officer' => (
    Icons.directions_run_rounded,
    AppColors.statusWarning,
    'تنسيق العمليات الميدانية',
  ),
  'committee-chair' => (
    Icons.gavel_rounded,
    AppColors.statusViolet,
    'رئاسة لجنة حل المشكلات',
  ),
  'committee-secretary' => (
    Icons.edit_note_rounded,
    AppColors.statusViolet,
    'تنسيق أعمال لجنة حل المشكلات',
  ),
  'committee-member' => (
    Icons.groups_rounded,
    AppColors.statusViolet,
    'عضو في لجنة حل المشكلات',
  ),
  'clinic-staff' => (
    Icons.local_hospital_outlined,
    AppColors.statusInfo,
    'ضمن فريق العيادات',
  ),
  'employee' => (
    Icons.person_rounded,
    AppColors.statusInfo,
    'الخدمات الذاتية: الحضور والطلبات',
  ),
  _ => (Icons.person_outline_rounded, AppColors.statusInfo, ''),
};

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final IconData? icon;
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
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
    final v = value?.trim();
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

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request});

  final EmployeeRequestBrief request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = _requestTypeLabel(request.requestType);
    final rawTitle = humanizeIsoDates(request.title?.trim() ?? '');
    final title = rawTitle.isEmpty ? type : rawTitle;
    final meta = [
      if (title != type) type,
      if (request.requestNumber > 0) 'رقم ${request.requestNumber}',
      _fmtDate(request.createdAt.toLocal()),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          MobileStatusPill(request.status),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final EmployeeTaskBrief task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (_hasText(task.priority)) 'الأولوية: ${_priorityLabel(task.priority!)}',
      if (task.dueDate != null) 'الاستحقاق: ${_fmtDate(task.dueDate)}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          MobileStatusPill(task.status),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// حالة اليوم المعروضة: تسمية واحدة لكل الشاشات (مطابقة لـ _today_status_public
// في 0631)، والزملاء لا يرون «متأخر» حتى مع خادم أقدم.
// ---------------------------------------------------------------------------
class _DisplayStatus {
  const _DisplayStatus(this.status, this.label, this.destination);

  factory _DisplayStatus.of(
    Employee360TodayStatus? ts, {
    required bool detailed,
  }) {
    var status = ts?.status ?? 'not_recorded';
    final hasCheckout = ts?.checkOutAt != null;
    if (!detailed && status == 'late') {
      status = hasCheckout ? 'checked_out' : 'present';
    }
    if (!detailed && status == 'left_early') status = 'checked_out';
    final label = todayStatusLabel(status, fallback: ts?.statusLabel);
    final activity = humanizeIsoDates(ts?.activityTitle?.trim() ?? '');
    final offsite =
        status == 'mission' || status == 'convoy' || status == 'fundraising';
    return _DisplayStatus(
      status,
      label,
      offsite && activity.isNotEmpty ? activity : null,
    );
  }

  final String status;
  final String label;

  /// وجهة المأمورية/القافلة/الفاندي.
  final String? destination;

  Color get color => todayStatusColor(status);
  IconData get icon => todayStatusIcon(status);
}

/// بطاقة تفاصيل حضور اليوم (الأوقات والتأخير وحالة الطلب) — مشتركة بين ملف
/// الموظف وملخص المدير التنفيذي. تُعرض لمن يملك تفاصيل الملف فقط.
class TodayStatusSection extends StatelessWidget {
  const TodayStatusSection({
    required this.todayStatus,
    this.title = 'الحالة اليومية',
    this.showStatusPill = true,
    super.key,
  });

  final Employee360TodayStatus? todayStatus;
  final String title;

  /// في ملف الموظف تظهر الحالة في البطاقة الرئيسية فلا تتكرر هنا.
  final bool showStatusPill;

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    return DateFormat('hh:mm a', 'ar').format(dt.toLocal());
  }

  /// "10:15" → «10:15 ص».
  String? _fmtDue(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return DateFormat('hh:mm a', 'ar').format(DateTime(2000, 1, 1, h, m));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ts = todayStatus;
    final display = _DisplayStatus.of(ts, detailed: true);
    final status = display.status;
    final color = display.color;
    final checkIn = ts?.checkInAt;
    final checkOut = ts?.checkOutAt;
    final lateMins = ts?.lateMinutes ?? 0;
    final workMins = ts?.workMinutes ?? 0;
    final activity = humanizeIsoDates(ts?.activityTitle?.trim() ?? '');
    final offsiteKind = switch (status) {
      'mission' => 'مأمورية',
      'convoy' => 'قافلة',
      'fundraising' => 'فاندي ترفيهي',
      _ => null,
    };
    // الخادم يُرجع النشاط/الإجازة المعتمدة والمعلّقة معًا؛ لا نفترض الاعتماد.
    final isPending = ts?.requestStatus == 'pending';
    final approvalColor = isPending
        ? AppColors.statusWarning
        : AppColors.statusSuccess;
    final noWorkToday =
        (status == 'weekend' || status == 'holiday') && checkIn == null;
    final due = _fmtDue(ts?.dueTime);

    final String? note;
    final List<Widget> tiles;
    if (offsiteKind != null && checkIn == null) {
      note = null;
      tiles = [
        _StatTile(value: offsiteKind, label: 'نوع العمل اليوم'),
        _StatTile(
          value: isPending ? 'بانتظار الاعتماد' : 'معتمد',
          label: 'حالة الطلب',
          color: approvalColor,
        ),
      ];
    } else if (status == 'on_leave') {
      note = null;
      tiles = [
        _StatTile(
          value: activity.isEmpty ? 'إجازة' : activity,
          label: 'تفاصيل الإجازة',
        ),
        _StatTile(
          value: isPending ? 'بانتظار الاعتماد' : 'معتمدة',
          label: 'حالة الطلب',
          color: approvalColor,
        ),
      ];
    } else if (noWorkToday) {
      note = 'لا يوجد دوام اليوم';
      tiles = const [];
    } else if (status == 'exempt') {
      note = 'معفى من تسجيل الحضور والبصمة';
      tiles = const [];
    } else {
      note = null;
      tiles = [
        _StatTile(value: _fmtTime(checkIn), label: 'وقت الحضور'),
        _StatTile(value: _fmtTime(checkOut), label: 'وقت الانصراف'),
        if (lateMins > 0)
          _StatTile(
            value: _fmtMinutes(lateMins),
            label: 'مدة التأخير',
            color: AppColors.statusWarning,
          ),
        if (checkOut != null && workMins > 0)
          _StatTile(value: _fmtHours(workMins), label: 'ساعات العمل')
        else if (checkIn != null && checkOut == null && lateMins == 0)
          const _StatTile(value: 'قيد العمل', label: 'الحالة')
        else if (checkIn == null && due != null)
          _StatTile(value: due, label: 'موعد الحضور'),
      ];
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: status == 'not_recorded'
              ? theme.colorScheme.outlineVariant.withValues(alpha: .5)
              : color.withValues(alpha: .35),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.today_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (showStatusPill)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: .6)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(display.icon, size: 14, color: color),
                        const SizedBox(width: 6),
                        Text(
                          display.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (offsiteKind != null && activity.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: .25)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 16, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'الوجهة: $activity',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 24),
            if (note != null)
              Center(
                child: Text(
                  note,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tiles,
              ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

List<Widget> _separated(List<Widget> items) => [
  for (var i = 0; i < items.length; i++) ...[
    if (i > 0) const Divider(height: 1),
    items[i],
  ],
];

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String _fmtDate(DateTime? date) {
  if (date == null) return '—';
  final y = date.year;
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$d/$m/$y';
}

String? _fmtDateOrNull(DateTime? date) =>
    date == null ? null : _fmtDate(date);

String _fmtMonth(String periodMonth) {
  final date = DateTime.tryParse(periodMonth);
  return date == null ? periodMonth : DateFormat('MMMM y', 'ar').format(date);
}

/// مدة الخدمة من تاريخ التعيين بصيغة عربية سليمة العدد («4 سنوات و9 أشهر»).
String? _serviceLength(DateTime? hireDate) {
  if (hireDate == null) return null;
  final now = DateTime.now();
  var months = (now.year - hireDate.year) * 12 + now.month - hireDate.month;
  if (now.day < hireDate.day) months--;
  if (months < 0) return null;
  if (months == 0) return 'أقل من شهر';
  String years(int n) => switch (n) {
    1 => 'سنة',
    2 => 'سنتان',
    <= 10 => '$n سنوات',
    _ => '$n سنة',
  };
  String monthsLabel(int n) => switch (n) {
    1 => 'شهر',
    2 => 'شهران',
    <= 10 => '$n أشهر',
    _ => '$n شهرًا',
  };
  final y = months ~/ 12;
  final m = months % 12;
  return [if (y > 0) years(y), if (m > 0) monthsLabel(m)].join(' و');
}

/// «يوم عمل واحد / يوما عمل / 4 أيام عمل / 26 يوم عمل».
String _workDays(int n) => switch (n) {
  1 => 'يوم عمل واحد',
  2 => 'يومي عمل',
  >= 3 && <= 10 => '$n أيام عمل',
  _ => '$n يوم عمل',
};

String _fmtHours(int minutes) {
  if (minutes <= 0) return '0';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (hours == 0) return '$remد';
  return rem == 0 ? '$hoursس' : '$hoursس $remد';
}

String _fmtMinutes(int minutes) {
  if (minutes >= 60) return _fmtHours(minutes);
  return switch (minutes) {
    1 => 'دقيقة',
    2 => 'دقيقتان',
    <= 10 => '$minutes دقائق',
    _ => '$minutes دقيقة',
  };
}

String _accountStatusNote(String status) => switch (status) {
  'pending' || 'invited' => 'لم يفعّل حسابه على المنظومة بعد',
  'suspended' => 'الحساب موقوف حاليًا',
  'terminated' => 'انتهت خدمته',
  'probation_failed' => 'لم يجتز فترة التجربة',
  'notice_period' => 'في فترة الإخطار',
  'inactive' => 'الحساب غير نشط',
  _ => 'حالة الحساب: $status',
};

String _docStatusLabel(String status) => switch (status) {
  'active' => 'ساري',
  'expiring' => 'قارب على الانتهاء',
  'expired' => 'منتهي',
  _ => status,
};

String _requestTypeLabel(String type) => switch (type) {
  'leave' => 'طلب إجازة',
  'mission' => 'مأمورية',
  'late_permit' => 'إذن حضور',
  'early_permit' => 'إذن انصراف',
  'attendance_correction' => 'تصحيح حضور',
  'convoy' => 'قافلة',
  'fundraising' => 'فاندي ترفيهي',
  'shift_change' => 'تغيير فترة العمل',
  _ => 'طلب',
};

String _priorityLabel(String priority) => switch (priority) {
  'urgent' => 'عاجلة',
  'high' => 'مرتفعة',
  'medium' || 'normal' => 'متوسطة',
  'low' => 'منخفضة',
  _ => priority,
};

