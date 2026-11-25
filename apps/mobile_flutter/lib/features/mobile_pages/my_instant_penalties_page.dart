import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/penalties_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/penalty_disputes_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ahla_shabab_management_os/core/time/app_time.dart';

part 'penalties/penalty_summary_and_policy_cards.dart';
part 'penalties/penalty_card.dart';
part 'penalties/penalty_excuse_and_withdraw_sheets.dart';
part 'penalties/penalty_suspension_actions.dart';
part 'penalties/team_penalties_tab.dart';
part 'penalties/suspended_employees_tab.dart';
part 'penalties/suspended_employee_card.dart';
part 'penalties/fund_tab.dart';
part 'penalties/penalty_shared_widgets.dart';

/// غرامات الحضور الفورية وصندوق الزمالة:
/// «غراماتي» لكل موظف، و«غرامات الموظفين» بأسمائهم للإدارة وHR والمديرين
/// (الخادم يقصر المدير على فريقه — 0642)، و«صندوق الزمالة» برصيده وحركاته.
/// السداد نقدًا لدى مسؤول الصندوق وتؤكده الإدارة (أُزيل السداد عبر إنستاباي).
class MyInstantPenaltiesPage extends ConsumerWidget {
  const MyInstantPenaltiesPage({
    this.highlightId,
    this.initialIndex,
    super.key,
  });

  /// معرّف الغرامة القادمة من إشعار — تُبرز بطاقتها عند الفتح.
  final String? highlightId;

  /// الفهرس الأولي للتبويب المفتوح (مثلاً التبويب الموقوفون عن العمل).
  final int? initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTeam = canSeeOthersPenalties(ref);
    final manage = canManagePenalties(ref);
    final tabs = <(String, IconData, Widget)>[
      (
        'غراماتي',
        Icons.person_outline_rounded,
        _MyPenaltiesTab(highlightId: highlightId),
      ),
      if (showTeam)
        ('غرامات الموظفين', Icons.groups_outlined, const _TeamPenaltiesTab()),
      if (manage)
        (
          'الموقوفون عن العمل',
          Icons.person_off_rounded,
          const _SuspendedEmployeesTab(),
        ),
      ('صندوق الزمالة', Icons.volunteer_activism_outlined, const _FundTab()),
    ];
    final activeInitial =
        (initialIndex != null &&
            initialIndex! >= 0 &&
            initialIndex! < tabs.length)
        ? initialIndex!
        : 0;
    return DefaultTabController(
      key: ValueKey(tabs.length),
      initialIndex: activeInitial,
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('غرامات الحضور وصندوق الزمالة'),
          bottom: TabBar(
            // Prevent clipping in RTL when exactly three tabs are present.
            // Scrollable only if more than three tabs.
            isScrollable: tabs.length > 3,
            tabAlignment: tabs.length > 3 ? TabAlignment.center : null,
            tabs: [
              for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: TabBarView(children: [for (final t in tabs) t.$3]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// غراماتي
// ═══════════════════════════════════════════════════════════════════════════

class _MyPenaltiesTab extends ConsumerWidget {
  const _MyPenaltiesTab({this.highlightId});

  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final penalties = ref.watch(myInstantPenaltiesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myInstantPenaltiesProvider),
      child: penalties.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(myInstantPenaltiesProvider),
        ),
        data: (items) {
          final unpaid = items.where((p) => _isUnpaid(p.status)).toList();
          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          final unpaidToday = unpaid
              .where((p) => p.workDate == todayStr)
              .firstOrNull;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              _MySummaryCard(items: items),
              if (unpaidToday != null) ...[
                const SizedBox(height: 10),
                _TodayCompensationProposalBanner(penalty: unpaidToday),
              ],
              const SizedBox(height: 10),
              const _PolicyCard(),
              const SizedBox(height: 10),
              // منفذ طعون الغرامات — الصفحة كانت موجودة لكن غير قابلة للوصول.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PenaltyDisputesPage(),
                    ),
                  ),
                  icon: const Icon(Icons.gavel_rounded, size: 18),
                  label: const Text('طعون الغرامات'),
                ),
              ),
              if (unpaid.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PayReminderCard(unpaid: unpaid),
              ],
              const SizedBox(height: 16),
              if (items.isEmpty)
                _EmptyState(
                  icon: Icons.military_tech_outlined,
                  title: 'لا توجد غرامات على حسابك',
                  subtitle:
                      ref
                              .watch(myWorkShiftInfoProvider)
                              .asData
                              ?.value
                              .currentShift !=
                          null
                      ? 'سجلّك نظيف — استمر في الحضور قبل نهاية فترة السماح (${ref.watch(myWorkShiftInfoProvider).asData!.value.currentShift.formattedActiveGraceEndTime}).'
                      : 'سجلّك نظيف — استمر في الحضور قبل نهاية فترة السماح.',
                )
              else ...[
                _SectionTitle(
                  title: 'سجل غراماتي',
                  trailing: arCount(
                    items.length,
                    one: 'غرامة واحدة',
                    two: 'غرامتان',
                    few: 'غرامات',
                    many: 'غرامة',
                    base: 'غرامة',
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in items) ...[
                  _PenaltyCard(
                    item: item,
                    highlighted: highlightId != null && item.id == highlightId,
                    canAct: true,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

