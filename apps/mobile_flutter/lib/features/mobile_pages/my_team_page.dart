import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/kpi_evaluation_detail_page.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/team_requests_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// طريقة عرض صفحة الفريق: إدارة فريقي / ملفات أعضاء الفريق / جداول الحضور.
enum TeamPageMode {
  /// نظرة عامة على فريقك المباشر وحالة حضورهم اليوم (إدارة فريقي).
  overview,

  /// بحث في فريقك وفتح ملف الموظف الشامل (ملفات أعضاء الفريق).
  files,

  /// اختيار عضو لفتح كشف الحضور والانصراف الشهري (جداول الحضور والتقارير).
  attendance,
}

/// فريقي — صفحة موحّدة بتبويبات (V22): نظرة عامة + ملفات الفريق + جداول الحضور.
class MyTeamPage extends StatelessWidget {
  const MyTeamPage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('فريقي'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'نظرة عامة'),
            Tab(text: 'ملفات الفريق'),
            Tab(text: 'جداول الحضور'),
          ],
        ),
      ),
      body: const TabBarView(
        children: [
          _TeamMembersView(mode: TeamPageMode.overview, embedded: true),
          _TeamMembersView(mode: TeamPageMode.files, embedded: true),
          _TeamMembersView(mode: TeamPageMode.attendance, embedded: true),
        ],
      ),
    ),
  );
}

/// ملفات أعضاء الفريق — بحث في فريقك المباشر وفتح الملف الشامل (V22).
class TeamFilesPage extends StatelessWidget {
  const TeamFilesPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TeamMembersView(mode: TeamPageMode.files);
}

/// جداول الحضور والتقارير — اختيار عضو لفتح كشفه الشهري.
class TeamAttendancePage extends StatelessWidget {
  const TeamAttendancePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _TeamMembersView(mode: TeamPageMode.attendance);
}

class _TeamMembersView extends ConsumerStatefulWidget {
  const _TeamMembersView({required this.mode, this.embedded = false});

  final TeamPageMode mode;

  /// داخل تبويبات صفحة «فريقي» الموحّدة — بلا Scaffold/AppBar خاص.
  final bool embedded;

  @override
  ConsumerState<_TeamMembersView> createState() => _TeamMembersViewState();
}

class _TeamMembersViewState extends ConsumerState<_TeamMembersView>
    with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'all';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _title => switch (widget.mode) {
    TeamPageMode.overview => 'إدارة فريقي',
    TeamPageMode.files => 'ملفات أعضاء الفريق',
    TeamPageMode.attendance => 'جداول الحضور والتقارير',
  };

  String get _subtitle => switch (widget.mode) {
    TeamPageMode.overview => 'فريقك المباشر وحالة حضورهم اليوم.',
    TeamPageMode.files => 'تصفّح ملفات أعضاء فريقك المباشر.',
    TeamPageMode.attendance => 'اختر عضوًا لعرض كشف الحضور والانصراف الشهري.',
  };

  void _openMember(BuildContext context, MobileTeamMember member) {
    switch (widget.mode) {
      case TeamPageMode.overview:
      case TeamPageMode.files:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeProfilePage(
              employeeId: member.id,
              employeeName: member.name,
            ),
          ),
        );
      case TeamPageMode.attendance:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MonthlyAttendanceStatementPage(
              employeeId: member.id,
              employeeName: member.name,
            ),
          ),
        );
    }
  }

  List<MobileTeamMember> _applyFilters(List<MobileTeamMember> members) {
    final q = _query.trim().toLowerCase();
    var result = members;
    if (q.isNotEmpty) {
      result = result
          .where(
            (m) =>
                m.name.toLowerCase().contains(q) ||
                (m.employeeCode?.toLowerCase().contains(q) ?? false) ||
                (m.jobTitle?.toLowerCase().contains(q) ?? false) ||
                (m.department?.toLowerCase().contains(q) ?? false),
          )
          .toList(growable: false);
    }
    return switch (_filter) {
      'present' => result
          .where((m) => _status(m) == 'present')
          .toList(growable: false),
      'field' => result
          .where((m) =>
              _status(m) == 'mission' ||
              _status(m) == 'convoy' ||
              _status(m) == 'fundraising')
          .toList(growable: false),
      'late' => result
          .where((m) => _status(m) == 'late' || m.lateMinutes > 0)
          .toList(growable: false),
      'absent' => result
          .where((m) => _status(m) == 'absent')
          .toList(growable: false),
      'on_leave' => result
          .where((m) => _status(m) == 'on_leave')
          .toList(growable: false),
      'pending' =>
        result.where((m) => m.pendingRequests > 0).toList(growable: false),
      'kpi' => result.where((m) => m.kpiStage != null).toList(growable: false),
      _ => result,
    };
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final members = ref.watch(mobileTeamProvider);
    final body = SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => ref.invalidate(mobileTeamProvider),
        child: members.when(
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
                  onPressed: () => ref.invalidate(mobileTeamProvider),
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
          data: (data) {
            final filtered = _applyFilters(data);
            if (data.isEmpty) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 40, 16, 32),
                children: const [
                  _EmptyHint(),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                MobileSectionHeader(title: _title, subtitle: _subtitle),
                const SizedBox(height: 8),
                _SummaryStrip(
                  members: data,
                  selectedFilter: _filter,
                  onSelectFilter: (key) => setState(() {
                    _filter = _filter == key ? 'all' : key;
                  }),
                ),
                const SizedBox(height: 8),
                MobileFilterBar(
                  searchHint: 'بحث بالاسم أو كود الموظف',
                  controller: _search,
                  onSearchChanged: (v) => setState(() => _query = v),
                  options: const [
                    MobileFilterOption('all', 'الكل'),
                    MobileFilterOption('present', 'حاضر'),
                    MobileFilterOption('field', 'ميداني'),
                    MobileFilterOption('late', 'متأخر'),
                    MobileFilterOption('absent', 'غائب'),
                    MobileFilterOption('on_leave', 'إجازة'),
                    MobileFilterOption('pending', 'معلّق'),
                  ],
                  selected: _filter,
                  onSelected: (v) => setState(() => _filter = v),
                  resultLabel: filtered.isEmpty
                      ? 'لا نتائج'
                      : arEmployees(filtered.length),
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('لا توجد نتائج مطابقة')),
                  )
                else
                  ...filtered.map(
                    (member) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MemberCard(
                        member: member,
                        onTap: () => _openMember(context, member),
                        onOpenFile: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeProfilePage(
                              employeeId: member.id,
                              employeeName: member.name,
                            ),
                          ),
                        ),
                        onOpenAttendance: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MonthlyAttendanceStatementPage(
                              employeeId: member.id,
                              employeeName: member.name,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: body,
    );
  }

  static String _status(MobileTeamMember member) =>
      member.attendanceStatus ?? 'not_recorded';
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.members,
    this.selectedFilter,
    this.onSelectFilter,
  });

  final List<MobileTeamMember> members;
  final String? selectedFilter;
  final ValueChanged<String>? onSelectFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = members.where((m) => m.attendanceStatus == 'present').length;
    final fieldActivity = members.where((m) =>
        m.attendanceStatus == 'mission' ||
        m.attendanceStatus == 'convoy' ||
        m.attendanceStatus == 'fundraising').length;
    final late = members.where((m) => m.attendanceStatus == 'late').length;
    final absent = members.where((m) => m.attendanceStatus == 'absent').length;
    final onLeave =
        members.where((m) => m.attendanceStatus == 'on_leave').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            _summaryCell(theme, '${members.length}', 'الفريق', 'all'),
            _summaryCell(theme, '$present', 'حاضر', 'present', const Color(0xFF0F9F6E)),
            _summaryCell(theme, '$fieldActivity', 'ميداني', 'field', const Color(0xFF2563EB)),
            _summaryCell(theme, '$late', 'متأخر', 'late', const Color(0xFFD97706)),
            _summaryCell(theme, '$absent', 'غائب', 'absent', const Color(0xFFDC2626)),
            _summaryCell(theme, '$onLeave', 'إجازة', 'on_leave', const Color(0xFF0284C7)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCell(
    ThemeData theme,
    String value,
    String label,
    String filterKey, [
    Color? color,
  ]) {
    final isSelected = selectedFilter == filterKey;
    final activeColor = color ?? theme.colorScheme.primary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onSelectFilter != null ? () => onSelectFilter!(filterKey) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: isSelected
              ? BoxDecoration(
                  color: activeColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: activeColor),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: isSelected ? activeColor : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.normal,
                  color: isSelected
                      ? activeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onTap,
    required this.onOpenFile,
    required this.onOpenAttendance,
  });

  final MobileTeamMember member;
  final VoidCallback onTap;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenAttendance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = member.attendanceStatus ?? 'not_recorded';
    final checkIn = member.firstCheckIn;
    final time = checkIn == null
        ? null
        : DateFormat('h:mm a', 'ar').format(checkIn.toLocal());
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppAvatar(name: member.name, photoUrl: member.photoUrl, radius: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (member.jobTitle?.isNotEmpty ?? false)
                              member.jobTitle!,
                            if (member.department?.isNotEmpty ?? false)
                              member.department!,
                          ].join(' — '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _statusChip(status, member.statusLabel),
                            if (member.activityTitle != null && member.activityTitle!.trim().isNotEmpty)
                              _metaChip(
                                context,
                                icon: Icons.location_on_rounded,
                                text: member.activityTitle!.trim(),
                              ),
                            if (status == 'late' && member.lateMinutes > 0)
                              _metaChip(
                                context,
                                icon: Icons.access_time_rounded,
                                text: 'تأخير ${member.lateMinutes} د',
                              ),
                            if (time != null)
                              _metaChip(
                                context,
                                icon: Icons.login_rounded,
                                text: 'حضور $time',
                              ),
                            if (member.pendingRequests > 0)
                              _metaChip(
                                context,
                                icon: Icons.pending_actions_rounded,
                                text: 'طلبات معلّقة: ${member.pendingRequests}',
                              ),
                            if (member.kpiStage?.isNotEmpty ?? false)
                              _metaChip(
                                context,
                                icon: Icons.analytics_outlined,
                                text: 'التقييم: ${kpiStageLabel(member.kpiStage!)}',
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _quickAction(
                      context,
                      icon: Icons.folder_shared_outlined,
                      label: 'الملف الشامل',
                      onPressed: onOpenFile,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _quickAction(
                      context,
                      icon: Icons.calendar_month_outlined,
                      label: 'كشف شهري',
                      onPressed: onOpenAttendance,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
    'present' => const Color(0xFF0F9F6E),
    'late' => const Color(0xFFD97706),
    'absent' => const Color(0xFFDC2626),
    'convoy' => const Color(0xFF7C3AED),
    'fundraising' => const Color(0xFF0D9488),
    'mission' => const Color(0xFF2563EB),
    'on_leave' => const Color(0xFF0284C7),
    'holiday' || 'weekend' => const Color(0xFF6B7280),
    'partial' => const Color(0xFFD97706),
    'pending' => Colors.blueGrey,
    'not_recorded' => const Color(0xFF6B7280),
    _ => Colors.grey,
  };

  String _statusLabel(String status) => switch (status) {
    'present' => 'حاضر في الجمعية',
    'late' => 'متأخر',
    'absent' => 'غائب',
    'convoy' => 'في قافلة',
    'fundraising' => 'في فاندي ترفيهي',
    'mission' => 'في مأمورية',
    'on_leave' => 'إجازة',
    'holiday' => 'عطلة',
    'weekend' => 'إجازة أسبوعية',
    'partial' => 'حضور جزئي',
    'pending' => 'قيد التحقق',
    'not_recorded' => 'لم يسجل بعد',
    'checked_out' => 'انصرف',
    'left_early' => 'انصرف مبكرًا',
    'missing_checkout' => 'لم يسجل الانصراف',
    'exempt' => 'معفى من البصمة',
    // لا يظهر رمز إنجليزي خام للمستخدم
    _ => 'غير محدد',
  };

  Widget _statusChip(String status, [String? customLabel]) {
    final label = (customLabel != null && customLabel.trim().isNotEmpty)
        ? customLabel
        : _statusLabel(status);
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _metaChip(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Text(
              text,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Icon(
              Icons.group_off_outlined,
              size: 52,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 14),
            Text(
              'لا يوجد أعضاء في فريقك المباشر حاليًا',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'عند إسناد موظفين إليك كمدير مباشر سيظهرون هنا، مع متابعة حضورهم اليومي وتقاريرهم.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TeamRequestsPage(),
                    ),
                  ),
                  icon: const Icon(Icons.approval_outlined, size: 18),
                  label: const Text('اعتماد طلبات الفريق'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PeopleHubPage(),
                    ),
                  ),
                  icon: const Icon(Icons.account_tree_outlined, size: 18),
                  label: const Text('الموظفون والهيكل الإداري'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
