import 'dart:async';

import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/session_cleanup.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_executive_insights_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_home_box.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_announcement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_brief_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_employee_summary_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_location_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/executive_reports_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_action_inbox_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_official_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/association_projects/association_projects_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/honor_board_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

// تبويبات المساحة التنفيذية — كل تبويب صفحة واحدة بلا شريط علوي خاص ولا
// تبويبات متداخلة؛ التنقل الرئيسي من الشريط السفلي في [ExecutiveWorkspace].

const _pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 28);

Color _rateColor(int pct) => pct >= 85
    ? AppColors.statusSuccess
    : pct >= 70
    ? AppColors.statusWarning
    : AppColors.statusDanger;

// ═══════════════════════════════════════════════════════════════
// الرئيسية
// ═══════════════════════════════════════════════════════════════
class ExecutiveHomeTab extends ConsumerWidget {
  const ExecutiveHomeTab({
    required this.access,
    required this.onOpenTab,
    required this.onOpenLocation,
    super.key,
  });

  final AccessContext access;
  final ValueChanged<int> onOpenTab;
  final VoidCallback onOpenLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(executiveDashboardProvider);
    final today = DateFormat('EEEE، d MMMM y', 'ar').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(executiveDashboardProvider);
        ref.invalidate(myNotificationsProvider);
        ref.invalidate(dailyReportsFeedProvider(null));
        try {
          await ref.read(executiveDashboardProvider.future);
        } catch (_) {
          // تعرض البطاقة الخطأ نفسه مع زر إعادة المحاولة
        }
      },
      child: ListView(
        padding: _pagePadding,
        children: [
          Text(
            today,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          dashboard.when(
            loading: () => const _LoadingCard(height: 210),
            error: (error, _) => _ErrorCard(
              message: humanizeError(error),
              onRetry: () => ref.invalidate(executiveDashboardProvider),
            ),
            data: (d) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AttendanceSummaryCard(summary: d, onTap: () => onOpenTab(1)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CountTile(
                        icon: Icons.approval_rounded,
                        label: 'بانتظار قرارك',
                        value: d.pendingApprovals,
                        hint: d.urgentActions > 0
                            ? '${d.urgentActions} عاجل الآن'
                            : 'لا يوجد عاجل',
                        hintColor: d.urgentActions > 0
                            ? AppColors.statusDanger
                            : null,
                        onTap: () => onOpenTab(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _CountTile(
                        icon: Icons.my_location_rounded,
                        label: 'طلبات الموقع',
                        value: d.activeLocationRequests,
                        hint: 'النشطة الآن',
                        onTap: onOpenLocation,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const MobileSectionHeader(title: 'إجراءات سريعة'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.campaign_outlined,
                  label: 'نشر قرار\nأو تعميم',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveAnnouncementPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.auto_awesome_outlined,
                  label: 'الملخص\nاليومي',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ExecutiveBriefPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.insights_rounded,
                  label: 'التقارير\nالتنفيذية',
                  onTap: () => pushMobileSubpage(
                    context,
                    'التقارير التنفيذية',
                    const ExecutiveReportsPage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QuickAction(
                  icon: Icons.notifications_active_outlined,
                  label: 'تنبيه\nطارئ',
                  danger: true,
                  onTap: () => showExecutiveBroadcastDialog(context, ref),
                ),
              ),
            ],
          ),
          const _UrgentNotificationsSection(),
          const SizedBox(height: 22),
          const DailyReportsHomeBox(),
          if (dashboard.hasValue) ...[
            const SizedBox(height: 22),
            const MobileSectionHeader(
              title: 'المتابعة',
              subtitle: 'تقارير الأداء والقرارات والقضايا.',
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    icon: Icons.fact_check_outlined,
                    label: 'تقارير KPI',
                    value: dashboard.requireValue.pendingFinalKpi,
                    onTap: () => pushMobileSubpage(
                      context,
                      'مؤشرات الأداء KPI',
                      MobileKpiPage(access: access, employeeOnly: false),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.gavel_rounded,
                    label: 'قرارات منشورة',
                    value: dashboard.requireValue.publishedDecisions,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const MobileOfficialFeedPage(canPublish: true),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    icon: Icons.balance_rounded,
                    label: 'قضايا مفتوحة',
                    value: dashboard.requireValue.openCases,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendanceSummaryCard extends StatelessWidget {
  const _AttendanceSummaryCard({required this.summary, required this.onTap});

  final ExecutiveDashboardSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = summary;
    final hasDuty = d.attendanceRequired > 0;
    final pct = d.attendanceRate;
    final color = hasDuty ? _rateColor(pct) : scheme.onSurfaceVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.groups_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('حضور اليوم', style: text.titleMedium)),
                  Text(
                    'التفاصيل',
                    style: text.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(Icons.chevron_left_rounded, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasDuty ? '$pct%' : '—',
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasDuty
                          ? '${d.attendancePresent} حضروا من ${d.attendanceRequired} مطلوب حضورهم'
                          : 'لا دوام مطلوب اليوم',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (hasDuty) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pct / 100,
                    minHeight: 8,
                    color: color,
                    backgroundColor: color.withValues(alpha: .14),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip('متأخر', d.attendanceLate, AppColors.statusWarning),
                  _StatChip('غائب', d.attendanceAbsent, AppColors.statusDanger),
                  if (d.attendanceNotYet > 0)
                    _StatChip(
                      'لم يحضر بعد',
                      d.attendanceNotYet,
                      scheme.onSurfaceVariant,
                    ),
                  _StatChip('إجازة', d.onLeave, AppColors.statusInfo),
                  _StatChip('عمل ميداني', d.fieldWork, AppColors.statusViolet),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.label, this.count, this.color);

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count ',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          TextSpan(text: label),
        ],
      ),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.hint,
    this.hintColor,
  });

  final IconData icon;
  final String label;
  final int value;
  final String? hint;
  final Color? hintColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(icon, size: 19, color: scheme.onPrimaryContainer),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_left_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$value',
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (hint != null)
                Text(
                  hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: hintColor ?? scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : scheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        button: true,
        label: label.replaceAll('\n', ' '),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: fg.withValues(alpha: .12),
                  child: Icon(icon, color: fg, size: 21),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Column(
            children: [
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrgentNotificationsSection extends ConsumerWidget {
  const _UrgentNotificationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final urgent =
        ref
            .watch(myNotificationsProvider)
            .asData
            ?.value
            .where(
              (n) =>
                  !n.isRead && (n.priority == 'urgent' || n.priority == 'high'),
            )
            .take(3)
            .toList() ??
        const <MobileNotificationItem>[];
    if (urgent.isEmpty) return const SizedBox.shrink();
    void openAll() => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MobileNotificationsPage()),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MobileSectionHeader(
            title: 'تنبيهات عاجلة',
            subtitle: 'إشعارات عالية الأولوية لم تُقرأ بعد.',
            action: TextButton(onPressed: openAll, child: const Text('الكل')),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < urgent.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.error.withValues(alpha: .12),
                      child: Icon(
                        Icons.priority_high_rounded,
                        color: scheme.error,
                      ),
                    ),
                    title: Text(
                      urgent[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      urgent[i].body?.trim().isNotEmpty == true
                          ? urgent[i].body!
                          : 'إشعار عاجل',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_left_rounded),
                    onTap: openAll,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) => Card(
    child: SizedBox(
      height: height,
      child: const Center(child: CircularProgressIndicator()),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════
// الاعتمادات
// ═══════════════════════════════════════════════════════════════
class ExecutiveApprovalsTab extends StatelessWidget {
  const ExecutiveApprovalsTab({super.key});

  @override
  Widget build(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: MobileSectionHeader(
          title: 'الاعتمادات والإجراءات',
          subtitle: 'طلبات وإجراءات تنتظر قرارك — الأعجل أولًا.',
        ),
      ),
      Expanded(child: MobileActionInboxPage()),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════
// الموظفون: الدليل + طلب الموقع
// ═══════════════════════════════════════════════════════════════
class ExecutivePeopleTab extends StatelessWidget {
  const ExecutivePeopleTab({required this.segment, super.key});

  /// 0 = الدليل، 1 = طلب الموقع — يضبطه الرئيسي عند فتح «طلبات الموقع».
  final ValueNotifier<int> segment;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: segment,
    builder: (context, value, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.badge_outlined),
                label: Text('دليل الموظفين'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.my_location_rounded),
                label: Text('طلب الموقع'),
              ),
            ],
            selected: {value},
            onSelectionChanged: (s) => segment.value = s.first,
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: value,
            children: const [
              _PeopleDirectory(),
              ExecutiveLocationRequestsView(),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PeopleDirectory extends ConsumerStatefulWidget {
  const _PeopleDirectory();

  @override
  ConsumerState<_PeopleDirectory> createState() => _PeopleDirectoryState();
}

class _PeopleDirectoryState extends ConsumerState<_PeopleDirectory> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(mobileExecutivePeopleProvider(_query));
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(mobileExecutivePeopleProvider(_query)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          TextField(
            controller: _search,
            onChanged: _onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'ابحث بالاسم أو القسم أو الكود',
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: scheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...people.when(
            loading: () => const [
              Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, _) => [
              _ErrorCard(
                message: humanizeError(error),
                onRetry: () =>
                    ref.invalidate(mobileExecutivePeopleProvider(_query)),
              ),
            ],
            data: (list) => list.isEmpty
                ? const [
                    Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('لا توجد نتائج مطابقة')),
                    ),
                  ]
                : [
                    Text(
                      arEmployees(list.length),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final p in list) _PersonTile(person: p),
                  ],
          ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final ExecutivePersonItem person;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = person;
    final subtitle = [
      p.jobTitle,
      p.department,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).toSet().join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExecutiveEmployeeSummaryPage(
              employeeId: p.id,
              employeeName: p.name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              // AppAvatar يحمّل الصور الخاصة عبر Storage SDK بتوكن الجلسة
              AppAvatar(name: p.name, photoUrl: p.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (p.pendingRequests > 0)
                      Text(
                        '${p.pendingRequests} طلبات معلقة',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
              ),
              if ((p.attendanceStatus ?? '').isNotEmpty) ...[
                const SizedBox(width: 8),
                MobileStatusPill(p.attendanceStatus!),
              ],
              Icon(Icons.chevron_left_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// المزيد
// ═══════════════════════════════════════════════════════════════
class ExecutiveMoreTab extends ConsumerWidget {
  const ExecutiveMoreTab({required this.access, super.key});

  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void push(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return ListView(
      padding: _pagePadding,
      children: [
        _MoreSection(
          title: 'القرارات والتواصل',
          entries: [
            _MoreEntry(
              icon: Icons.campaign_outlined,
              title: 'نشر قرار أو تعميم',
              subtitle: 'يصل فورًا كإشعار لكل الموظفين المعنيين.',
              onTap: () => push(const ExecutiveAnnouncementPage()),
            ),
            _MoreEntry(
              icon: Icons.feed_outlined,
              title: 'القرارات والتعاميم المنشورة',
              subtitle: 'السجل الرسمي لكل ما نُشر.',
              onTap: () => push(const MobileOfficialFeedPage(canPublish: true)),
            ),
            _MoreEntry(
              icon: Icons.notifications_active_outlined,
              title: 'تنبيه طارئ لكل الموظفين',
              subtitle: 'وميض واهتزاز على كل الأجهزة — للحالات الطارئة فقط.',
              danger: true,
              onTap: () => showExecutiveBroadcastDialog(context, ref),
            ),
          ],
        ),
        _MoreSection(
          title: 'التقارير والمتابعة',
          entries: [
            _MoreEntry(
              icon: Icons.auto_awesome_outlined,
              title: 'الملخص التنفيذي اليومي',
              subtitle: 'الحضور والقرارات وأبرز ما يحتاج متابعتك.',
              onTap: () => push(const ExecutiveBriefPage()),
            ),
            _MoreEntry(
              icon: Icons.insights_rounded,
              title: 'التقارير التنفيذية',
              subtitle: 'مركز القيادة التشغيلية والطلبات الميدانية.',
              onTap: () => pushMobileSubpage(
                context,
                'التقارير التنفيذية',
                const ExecutiveReportsPage(),
              ),
            ),
            _MoreEntry(
              icon: Icons.newspaper_outlined,
              title: 'تقارير الموظفين اليومية',
              subtitle: 'ما أنجزه الموظفون يومًا بيوم.',
              onTap: () => push(const DailyReportsFeedPage()),
            ),
            _MoreEntry(
              icon: Icons.fact_check_outlined,
              title: 'مؤشرات الأداء KPI',
              subtitle: 'التقييمات الشهرية ومراحل اعتمادها.',
              onTap: () => pushMobileSubpage(
                context,
                'مؤشرات الأداء KPI',
                MobileKpiPage(access: access, employeeOnly: false),
              ),
            ),
          ],
        ),
        _MoreSection(
          title: 'الموظفون والمشاريع والطلبات',
          entries: [
            _MoreEntry(
              icon: Icons.folder_special_outlined,
              title: 'مشاريع الجمعية',
              subtitle: 'متابعة مشاريع الإدارات وخطوات العمل والمهام.',
              onTap: () => push(const AssociationProjectsPage()),
            ),
            _MoreEntry(
              icon: Icons.military_tech_outlined,
              title: 'لوحة الشرف والتكريم',
              subtitle: 'الموظفون المتميزون في الانضباط والحضور لهذا الشهر.',
              onTap: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => const HonorBoardSheet(),
              ),
            ),
            _MoreEntry(
              icon: Icons.account_tree_outlined,
              title: 'الموظفون والهيكل التنظيمي',
              subtitle: 'الملفات والأقسام والتسلسل الإداري.',
              onTap: () => push(const PeopleHubPage()),
            ),
            _MoreEntry(
              icon: Icons.assignment_outlined,
              title: 'كل الطلبات',
              subtitle: 'متابعة الطلبات وحالاتها.',
              onTap: () => pushMobileSubpage(
                context,
                'كل الطلبات',
                const MobileRequestsPage(showAllByDefault: true),
              ),
            ),
          ],
        ),
        _MoreSection(
          title: 'الحساب والخدمات الشخصية',
          entries: [
            _MoreEntry(
              icon: Icons.account_circle_outlined,
              title: 'حسابي وملفي',
              subtitle: 'بياناتك وكلمة المرور والإعدادات.',
              onTap: () => push(const MobileProfilePage()),
            ),
            _MoreEntry(
              icon: Icons.fingerprint_rounded,
              title: 'تسجيل البصمة الذكية',
              subtitle: 'إثبات الحضور والانصراف عبر الموقع والشبكة.',
              onTap: () => push(const MobileAttendancePage()),
            ),
            _MoreEntry(
              icon: Icons.edit_calendar_outlined,
              title: 'الخدمة الذاتية وتقديم طلب',
              subtitle: 'طلب إجازة أو إذن أو مأمورية ومتابعة الأرصدة.',
              onTap: () => push(const MobileSelfServicePage()),
            ),
            _MoreEntry(
              icon: Icons.calendar_month_outlined,
              title: 'بيان الحضور الشهري',
              subtitle: 'سجل الحضور والانصراف وساعات الدوام للشهر.',
              onTap: () => push(const MonthlyAttendanceStatementPage()),
            ),
            _MoreEntry(
              icon: Icons.logout_rounded,
              title: 'تسجيل الخروج',
              danger: true,
              onTap: () => _signOut(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من هذا الجهاز؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // نلتقط الحاوية قبل الخروج: شاشة الدخول تزيل هذا الـ widget فلا يصح ref بعدها.
    final container = ProviderScope.containerOf(context, listen: false);
    final client = container.read(supabaseProvider);
    final userId = client.auth.currentUser?.id;
    await cleanupOnSignOut(userId: userId);
    await client.auth.signOut();
    container.invalidate(accessContextProvider);
  }
}

class _MoreSection extends StatelessWidget {
  const _MoreSection({required this.title, required this.entries});

  final String title;
  final List<_MoreEntry> entries;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 64),
                entries[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _MoreEntry extends StatelessWidget {
  const _MoreEntry({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger ? scheme.error : scheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: .12),
        child: Icon(icon, color: color, size: 21),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: danger ? scheme.error : null,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(
        Icons.chevron_left_rounded,
        color: scheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// تنبيه طارئ شامل — نسخة واحدة (كانت مكررة في موضعين)
// ═══════════════════════════════════════════════════════════════
Future<void> showExecutiveBroadcastDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final commands = ref.read(mobileCommandsProvider);
  final messenger = ScaffoldMessenger.of(context);
  final text = await showDialog<String>(
    context: context,
    builder: (_) => const _BroadcastDialog(),
  );
  if (text == null) return;
  try {
    await commands.sendBroadcastAlert(text);
    messenger.showSnackBar(
      const SnackBar(content: Text('أُرسل التنبيه الطارئ لكل الموظفين')),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذّر الإرسال: ${humanizeError(e)}')),
    );
  }
}

/// الحوار يملك متحكم النص ويتخلص منه بعد انتهاء حركة الإغلاق — التخلص منه
/// فور عودة showDialog يكسر TextField أثناء حركة الخروج.
class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog();

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.notifications_active_outlined, color: scheme.error),
      title: const Text('تنبيه طارئ لكل الموظفين'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'يصل فورًا لكل الموظفين: تومض الشاشة ويعمل فلاش الجهاز والاهتزاز حتى يطّلعوا عليه. استخدمه للحالات الطارئة فقط.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص التنبيه',
                hintText: 'مثال: اجتماع طارئ فورًا في مقر الجمعية الرئيسي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () {
            final value = _controller.text.trim();
            if (value.length < 3) return;
            Navigator.pop(context, value);
          },
          child: const Text('إرسال الآن'),
        ),
      ],
    );
  }
}
