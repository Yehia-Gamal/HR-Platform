import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      'pending' =>
        result.where((m) => m.pendingRequests > 0).toList(growable: false),
      'late' => result
          .where((m) => _status(m) == 'late' || m.lateMinutes > 0)
          .toList(growable: false),
      'absent' => result
          .where((m) => _status(m) == 'absent')
          .toList(growable: false),
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
                if (widget.mode != TeamPageMode.overview) ...[
                  const SizedBox(height: 8),
                  MobileFilterBar(
                    searchHint: 'بحث بالاسم أو كود الموظف',
                    controller: _search,
                    onSearchChanged: (v) => setState(() => _query = v),
                    options: const [
                      MobileFilterOption('all', 'الكل'),
                      MobileFilterOption('pending', 'طلبات معلّقة'),
                      MobileFilterOption('late', 'متأخر اليوم'),
                      MobileFilterOption('absent', 'غائب اليوم'),
                      MobileFilterOption('kpi', 'بمرحلة KPI'),
                    ],
                    selected: _filter,
                    onSelected: (v) => setState(() => _filter = v),
                    resultLabel: filtered.isEmpty
                        ? 'لا نتائج'
                        : '${filtered.length} موظف',
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  _SummaryStrip(members: data),
                ],
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
      member.attendanceStatus ?? 'absent';
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.members});

  final List<MobileTeamMember> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final present = members.where((m) => m.attendanceStatus == 'present').length;
    final late = members.where((m) => m.attendanceStatus == 'late').length;
    final absent = members.where((m) => m.attendanceStatus == 'absent').length;
    final pending =
        members.fold<int>(0, (sum, m) => sum + m.pendingRequests);
    final onLeave =
        members.where((m) => m.attendanceStatus == 'on_leave').length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            _summaryCell(theme, '${members.length}', 'الفريق'),
            _summaryCell(theme, '$present', 'حاضر'),
            _summaryCell(theme, '$late', 'متأخر'),
            _summaryCell(theme, '$absent', 'غائب'),
            _summaryCell(theme, '$onLeave', 'إجازة'),
            _summaryCell(theme, '$pending', 'طلبات'),
          ],
        ),
      ),
    );
  }

  Widget _summaryCell(ThemeData theme, String value, String label) =>
      Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
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
    final status = member.attendanceStatus ?? 'absent';
    final checkIn = member.firstCheckIn;
    final time = checkIn == null
        ? null
        : '${checkIn.hour.toString().padLeft(2, '0')}:${checkIn.minute.toString().padLeft(2, '0')}';
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
                            _statusChip(status),
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
                                text: '${member.pendingRequests} طلب معلّق',
                              ),
                            if (member.kpiStage?.isNotEmpty ?? false)
                              _metaChip(
                                context,
                                icon: Icons.analytics_outlined,
                                text: 'KPI: ${member.kpiStage}',
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
    'present' => Colors.green,
    'late' => Colors.orange,
    'absent' => Colors.red,
    'on_leave' => Colors.blue,
    'holiday' || 'weekend' => Colors.teal,
    'partial' => Colors.amber,
    'pending' => Colors.blueGrey,
    _ => Colors.grey,
  };

  String _statusLabel(String status) => switch (status) {
    'present' => 'حضر',
    'late' => 'متأخر',
    'absent' => 'غائب',
    'on_leave' => 'إجازة',
    'holiday' => 'عطلة',
    'weekend' => 'إجازة أسبوعية',
    'partial' => 'حضور جزئي',
    'pending' => 'قيد التحقق',
    _ => status,
  };

  Widget _statusChip(String status) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _statusColor(status).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _statusColor(status)),
    ),
    child: Text(
      _statusLabel(status),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: _statusColor(status),
      ),
    ),
  );

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
          const SizedBox(height: 6),
          Text(
            'عند إسناد موظفين إليك كمدير مباشر سيظهرون هنا.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
