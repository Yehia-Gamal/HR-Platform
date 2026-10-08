import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/penalties_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// غرامات الحضور الفورية وصندوق الزمالة:
/// «غراماتي» لكل موظف، و«غرامات الموظفين» بأسمائهم للإدارة وHR والمديرين
/// (الخادم يقصر المدير على فريقه — 0642)، و«صندوق الزمالة» برصيده وحركاته.
/// السداد نقدًا لدى مسؤول الصندوق وتؤكده الإدارة (أُزيل السداد عبر إنستاباي).
class MyInstantPenaltiesPage extends ConsumerWidget {
  const MyInstantPenaltiesPage({this.highlightId, super.key});

  /// معرّف الغرامة القادمة من إشعار — تُبرز بطاقتها عند الفتح.
  final String? highlightId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTeam = canSeeOthersPenalties(ref);
    final tabs = <(String, IconData, Widget)>[
      (
        'غراماتي',
        Icons.person_outline_rounded,
        _MyPenaltiesTab(highlightId: highlightId),
      ),
      if (showTeam)
        ('غرامات الموظفين', Icons.groups_outlined, const _TeamPenaltiesTab()),
      ('صندوق الزمالة', Icons.volunteer_activism_outlined, const _FundTab()),
    ];
    return DefaultTabController(
      key: ValueKey(tabs.length),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('غرامات الحضور وصندوق الزمالة'),
          bottom: TabBar(
            isScrollable: tabs.length > 2,
            tabAlignment: tabs.length > 2 ? TabAlignment.center : null,
            tabs: [
              for (final t in tabs) Tab(icon: Icon(t.$2, size: 20), text: t.$1),
            ],
          ),
        ),
        body: TabBarView(children: [for (final t in tabs) t.$3]),
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
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _MySummaryCard(items: items),
              const SizedBox(height: 10),
              const _PolicyCard(),
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

class _MySummaryCard extends StatelessWidget {
  const _MySummaryCard({required this.items});

  final List<MobileInstantPenalty> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = items.where((p) => p.status == 'pending_payment');
    final escalated = items.where(
      (p) => p.status == 'doubled' || p.status == 'suspended',
    );
    final paid = items.where((p) => p.status == 'paid');
    final cancelled = items.where((p) => p.status == 'cancelled');
    double sum(Iterable<MobileInstantPenalty> list) =>
        list.fold<double>(0, (s, p) => s + p.currentAmount);
    final dueTotal = sum(pending) + sum(escalated);
    final hasDue = dueTotal > 0;
    final heroColor = hasDue
        ? (escalated.isNotEmpty
              ? AppColors.statusDanger
              : AppColors.statusWarning)
        : AppColors.statusSuccess;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── أهم رقم أولًا: ما عليك الآن ──
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: heroColor.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    hasDue ? Icons.payments_outlined : Icons.verified_rounded,
                    color: heroColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasDue ? 'المستحق عليك الآن' : 'لا مستحقات عليك',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasDue
                            ? _money(dueTotal)
                            : items.isEmpty
                            ? 'سجلّك نظيف'
                            : 'كل غراماتك مسددة أو ملغاة',
                        style: TextStyle(
                          fontSize: hasDue ? 24 : 16,
                          fontWeight: FontWeight.w900,
                          color: heroColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _CountTile(
                  label: 'بانتظار السداد',
                  count: pending.length,
                  amount: sum(pending),
                  color: AppColors.statusWarning,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'مضاعفة',
                  count: escalated.length,
                  amount: sum(escalated),
                  color: AppColors.statusDanger,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'مسددة',
                  count: paid.length,
                  amount: sum(paid),
                  color: AppColors.statusSuccess,
                ),
                const SizedBox(width: 8),
                _CountTile(
                  label: 'ملغاة/معفاة',
                  count: cancelled.length,
                  color: const Color(0xFF64748B),
                ),
              ],
            ),
            if (items.any((p) => p.status == 'suspended')) ...[
              const SizedBox(height: 12),
              const _Notice(
                icon: Icons.block_rounded,
                color: AppColors.statusDanger,
                text:
                    'حسابك موقوف بسبب غرامة مضاعفة لم تُسدَّد — توجّه للموارد البشرية للسداد وإعادة فتح الحساب.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PolicyCard extends ConsumerWidget {
  const _PolicyCard();

  static String _formatClockOffset(String timeStr, int offsetMinutes) {
    final parts = timeStr.split(':');
    if (parts.length < 2) return '';
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final totalM = h * 60 + m + offsetMinutes;
    final targetH = (totalM ~/ 60) % 24;
    final targetM = totalM % 60;
    final period = targetH < 12 ? 'ص' : 'م';
    final h12 = targetH == 0 ? 12 : (targetH > 12 ? targetH - 12 : targetH);
    final mStr = targetM > 0 ? ':${targetM.toString().padLeft(2, '0')}' : ':00';
    return '$h12$mStr $period';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final shiftInfo = ref.watch(myWorkShiftInfoProvider).asData?.value;
    final shift = shiftInfo?.currentShift;

    final String startLabel;
    final String tier1Label;
    final String tier2Label;
    final String tier3Label;

    if (shift != null) {
      final baseStart = shift.activeStartTime;
      final grace = shift.graceInMinutes;
      final hasPermit = shift.hasPermitToday;

      tier1Label = 'حتى ${_formatClockOffset(baseStart, 30)}';
      tier2Label = 'حتى ${_formatClockOffset(baseStart, 60)}';
      tier3Label = 'حتى ${_formatClockOffset(baseStart, 120)}';

      // سطر واحد واضح بدل الأقواس المتداخلة «(10 ص – 6 م) (بداية الدوام…)»
      if (hasPermit) {
        startLabel =
            'إذن تأخير اليوم: يبدأ حسابك ${shift.formattedActiveStartTime} · سماح $grace د حتى ${shift.formattedActiveGraceEndTime}';
      } else {
        startLabel =
            '${shift.name} · يبدأ ${shift.formattedStartTime} · سماح $grace د حتى ${shift.formattedGraceEndTime}';
      }
    } else {
      startLabel = 'يبدأ الدوام 10:00 ص · سماح 15 د حتى 10:15 ص';
      tier1Label = 'حتى 10:30 ص';
      tier2Label = 'حتى 11:00 ص';
      tier3Label = 'حتى 12:00 م';
    }

    // سُلّم متدرّج اللون؛ كل خانة سطران ثابتان (المبلغ + متى) فلا تنكسر
    // «بعد 24 ساعة دون سداد» على ثلاثة أسطر.
    Widget tier(String time, String amount, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                time,
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.rule_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'لائحة غرامات التأخير',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (shift?.hasPermitToday ?? false)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.statusInfo.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.statusInfo.withValues(alpha: .3),
                      ),
                    ),
                    child: Text(
                      'إذن تأخير نشط اليوم',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.statusInfo,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    startLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tier(tier1Label, '20 ج.م', AppColors.statusWarning),
                const SizedBox(width: 6),
                tier(tier2Label, '50 ج.م', const Color(0xFFE07A10)),
                const SizedBox(width: 6),
                tier(tier3Label, '150 ج.م', const Color(0xFFE2582A)),
                const SizedBox(width: 6),
                tier('دون سداد 24 س', '500 ج.م', AppColors.statusDanger),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.volunteer_activism_outlined,
                  size: 15,
                  color: AppColors.statusSuccess,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'لا تُخصم من الراتب — تُودَع كاملة في صندوق الزمالة لدعم الزملاء.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PayReminderCard extends StatelessWidget {
  const _PayReminderCard({required this.unpaid});

  final List<MobileInstantPenalty> unpaid;

  @override
  Widget build(BuildContext context) {
    final total = unpaid.fold<double>(0, (s, p) => s + p.currentAmount);
    return Card(
      color: AppColors.statusWarning.withValues(alpha: .08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.statusWarning.withValues(alpha: .4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Notice(
              icon: Icons.payments_outlined,
              color: AppColors.statusWarning,
              text:
                  'عليك ${_money(total)} — السداد نقدًا لدى مسؤول صندوق الزمالة خلال 24 ساعة من تسجيل الغرامة، وتظهر «مسددة» بعد تأكيد الإدارة.',
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                const text =
                    'السلام عليكم، أود الاستفسار بخصوص سداد غرامة الحضور لصندوق الزمالة.';
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(text)}',
                );
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('استفسار عبر واتساب'),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// بطاقة الغرامة — كل التفاصيل
// ═══════════════════════════════════════════════════════════════════════════

class _PenaltyCard extends ConsumerWidget {
  const _PenaltyCard({
    required this.item,
    this.highlighted = false,
    this.canAct = false,
    this.manage = false,
  });

  final MobileInstantPenalty item;
  final bool highlighted;

  /// غرامتي: يمكن تقديم عذر عليها.
  final bool canAct;

  /// الإدارة وHR: تأكيد السداد، الإلغاء/الإعفاء، رفع الإيقاف، مراجعة العذر.
  final bool manage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = _statusMeta(item);
    final work = DateTime.tryParse(item.workDate);
    final notes = _parseNotes(item.notes);
    final cancelReason = item.cancelledReason?.trim().isNotEmpty ?? false
        ? item.cancelledReason!.trim()
        : notes.reasons.join('، ');
    final active = _isUnpaid(item.status);
    final escalated = item.currentAmount != item.originalAmount;
    final deadline = item.createdAt.toLocal().add(const Duration(hours: 24));
    final remaining = deadline.difference(DateTime.now());

    final cancelled = item.status == 'cancelled';
    final lateText = item.lateMinutes >= 240
        ? 'لم يسجّل بصمة الحضور'
        : 'تأخير ${_minutes(item.lateMinutes)}';
    // التأخير والمبلغ في الترويسة؛ الصفوف لما يتغيّر بحسب الحالة فقط
    final rows = <(String, String, Color?)>[
      if (escalated && !cancelled)
        (
          'بعد المضاعفة',
          '${_money(item.originalAmount)} ← ${_money(item.currentAmount)}',
          AppColors.statusDanger,
        ),
      if (item.status == 'pending_payment')
        (
          'آخر موعد للسداد',
          remaining.inMinutes > 0
              ? '${_dateTime(deadline)} (متبقٍ ${_duration(remaining)})'
              : _dateTime(deadline),
          AppColors.statusWarning,
        ),
      if (item.paidAt != null) ('تاريخ السداد', _dateTime(item.paidAt!), null),
      if (item.status == 'paid')
        ('طريقة السداد', _paymentLabel(item.paymentMethod), null),
      if (item.suspendedAt != null)
        ('تاريخ الإيقاف', _dateTime(item.suspendedAt!), AppColors.statusDanger),
      if (item.suspensionLiftedAt != null)
        ('رُفع الإيقاف', _dateTime(item.suspensionLiftedAt!), null),
      if (item.status == 'cancelled' && cancelReason.isNotEmpty)
        (meta.exempt ? 'سبب الإعفاء' : 'سبب الإلغاء', cancelReason, null),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted
              ? theme.colorScheme.primary
              : meta.color.withValues(alpha: .35),
          width: highlighted ? 2 : 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── الترويسة: الحالة + اليوم + التأخير | المبلغ ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: meta.color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(meta.icon, size: 21, color: meta.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work == null
                            ? item.workDate
                            : DateFormat('EEEE d MMMM y', 'ar').format(work),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$lateText · سُجّلت ${_registeredAt(item.createdAt, work)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(
                        cancelled ? item.originalAmount : item.currentAmount,
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: cancelled
                            ? theme.colorScheme.onSurfaceVariant
                            : meta.color,
                        decoration: cancelled
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Pill(text: meta.label, color: meta.color),
                  ],
                ),
              ],
            ),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: .35,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    for (final r in rows)
                      _DetailRow(label: r.$1, value: r.$2, color: r.$3),
                  ],
                ),
              ),
            ],
            if (notes.lines.isNotEmpty) _NotesToggle(lines: notes.lines),
            if (item.excuseStatus == 'submitted' && active) ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.hourglass_top_rounded,
                color: AppColors.statusViolet,
                text:
                    'عذر قيد مراجعة الموارد البشرية'
                    '${item.excuseText?.isNotEmpty ?? false ? ': ${item.excuseText}' : ''}',
              ),
            ] else if (item.excuseStatus == 'approved') ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.statusSuccess,
                text:
                    'قُبل العذر وأُلغيت الغرامة'
                    '${item.excuseNotes?.isNotEmpty ?? false ? ' — ${item.excuseNotes}' : ''}',
              ),
            ] else if (item.excuseStatus == 'rejected') ...[
              const SizedBox(height: 10),
              _Notice(
                icon: Icons.cancel_outlined,
                color: AppColors.statusDanger,
                text:
                    'رُفض العذر'
                    '${item.excuseNotes?.isNotEmpty ?? false ? ' — السبب: ${item.excuseNotes}' : ''}',
              ),
            ],
            if (canAct &&
                active &&
                (item.excuseStatus == 'none' ||
                    item.excuseStatus == 'rejected')) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => _showSubmitExcuseSheet(context, ref, item),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: const Text('تقديم عذر'),
                ),
              ),
            ],
            if (manage && active) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (item.excuseStatus == 'submitted') ...[
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          _reviewExcuse(context, ref, item, approve: true),
                      icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
                      label: const Text('قبول العذر'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _reviewExcuse(context, ref, item, approve: false),
                      icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
                      label: const Text('رفض العذر'),
                    ),
                  ],
                  if (active)
                    FilledButton.icon(
                      onPressed: () => _confirmPayment(context, ref, item),
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('تأكيد السداد'),
                    ),
                  if (item.status == 'suspended')
                    OutlinedButton.icon(
                      onPressed: () => _liftSuspension(context, ref, item),
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text('رفع الإيقاف'),
                    ),
                  if (active)
                    OutlinedButton.icon(
                      onPressed: () => _cancelPenalty(context, ref, item),
                      icon: const Icon(
                        Icons.do_not_disturb_on_outlined,
                        size: 18,
                      ),
                      label: const Text('إلغاء أو إعفاء'),
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // التسمية في البداية والقيمة محاذاة للنهاية — قراءة سطر بسطر كالإيصال
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// تفاصيل الحساب (من ملاحظات الخادم) مطوية افتراضيًا — كانت تطيل كل بطاقة.
class _NotesToggle extends StatefulWidget {
  const _NotesToggle({required this.lines});

  final List<String> lines;

  @override
  State<_NotesToggle> createState() => _NotesToggleState();
}

class _NotesToggleState extends State<_NotesToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notes_rounded, size: 15, color: muted),
                const SizedBox(width: 6),
                Text(
                  _open ? 'إخفاء التفاصيل' : 'التفاصيل',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: muted,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final line in widget.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                '• $line',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
      ],
    );
  }
}

Future<void> _showSubmitExcuseSheet(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var isSubmitting = false;
  final work = DateTime.tryParse(item.workDate);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تقديم عذر عن تأخير ${work == null ? item.workDate : DateFormat('d MMMM y', 'ar').format(work)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'اكتب سبب التأخير (${_minutes(item.lateMinutes)}). تراجع الموارد البشرية العذر وتُبلغك بالقرار.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'اكتب العذر بالتفصيل…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (val) => val == null || val.trim().length < 5
                    ? 'اكتب عذرًا واضحًا لا يقل عن 5 أحرف'
                    : null,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => isSubmitting = true);
                        try {
                          await Supabase.instance.client.rpc<dynamic>(
                            'submit_instant_penalty_excuse',
                            params: {
                              'p_penalty_id': item.id,
                              'p_reason': controller.text.trim(),
                            },
                          );
                          ref.invalidate(myInstantPenaltiesProvider);
                          if (ctx.mounted) {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('أُرسل العذر للمراجعة'),
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isSubmitting = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'تعذر إرسال العذر: ${humanizeError(e)}',
                                ),
                              ),
                            );
                          }
                        }
                      },
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  isSubmitting ? 'جارٍ الإرسال…' : 'إرسال العذر للمراجعة',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// إجراءات الإدارة على الغرامة (الخادم يتحقق من الصلاحية)
// ═══════════════════════════════════════════════════════════════════════════

/// يطلب ملاحظة/سببًا ثم ينفّذ الإجراء ويحدّث الشاشات.
Future<void> _runPenaltyAction(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required String confirmLabel,
  required String inputLabel,
  required bool inputRequired,
  required String success,
  required Future<void> Function(String note) action,
  bool destructive = false,
}) async {
  // لا يُتلف بعد الإغلاق مباشرة — الحوار ما زال يرسمه أثناء حركة الخروج.
  final controller = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: inputLabel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.statusDanger,
                  )
                : null,
            onPressed: inputRequired && controller.text.trim().length < 3
                ? null
                : () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final note = controller.text.trim();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action(note);
    ref
      ..invalidate(teamInstantPenaltiesProvider)
      ..invalidate(myInstantPenaltiesProvider)
      ..invalidate(fellowshipFundSummaryProvider)
      ..invalidate(fellowshipFundTransactionsProvider);
    messenger.showSnackBar(SnackBar(content: Text(success)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('تعذر التنفيذ: ${humanizeError(e)}')),
    );
  }
}

Future<void> _confirmPayment(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'تأكيد سداد الغرامة',
  message:
      'تأكيد استلام ${_money(item.currentAmount)} نقدًا من ${item.employeeName ?? 'الموظف'}، ويُودَع المبلغ في صندوق الزمالة.',
  confirmLabel: 'تأكيد السداد',
  inputLabel: 'ملاحظة (اختياري)',
  inputRequired: false,
  success: 'تم تأكيد السداد وإيداعه في صندوق الزمالة',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'confirm_instant_penalty_payment',
        params: {
          'p_penalty_id': item.id,
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

Future<void> _cancelPenalty(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'إلغاء أو إعفاء الغرامة',
  message:
      'تُلغى غرامة ${item.employeeName ?? 'الموظف'} (${_money(item.currentAmount)}) ولا تُحصَّل، ويُسجَّل السبب في ملفها.',
  confirmLabel: 'إلغاء الغرامة',
  inputLabel: 'السبب (مطلوب)',
  inputRequired: true,
  destructive: true,
  success: 'تم إلغاء الغرامة',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'cancel_instant_penalty',
        params: {'p_penalty_id': item.id, 'p_reason': note},
      ),
);

Future<void> _liftSuspension(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item,
) => _runPenaltyAction(
  context,
  ref,
  title: 'رفع إيقاف الحساب',
  message:
      'يُعاد فتح حساب ${item.employeeName ?? 'الموظف'}، وتعود الغرامة «بانتظار السداد».',
  confirmLabel: 'رفع الإيقاف',
  inputLabel: 'ملاحظة (اختياري)',
  inputRequired: false,
  success: 'تم رفع الإيقاف',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'lift_instant_penalty_suspension',
        params: {
          'p_penalty_id': item.id,
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

Future<void> _reviewExcuse(
  BuildContext context,
  WidgetRef ref,
  MobileInstantPenalty item, {
  required bool approve,
}) => _runPenaltyAction(
  context,
  ref,
  title: approve ? 'قبول العذر' : 'رفض العذر',
  message: approve
      ? 'قبول العذر يُلغي الغرامة ويُبلَّغ الموظف بالقرار.'
      : 'تبقى الغرامة مستحقة، ويُبلَّغ الموظف بسبب الرفض.',
  confirmLabel: approve ? 'قبول' : 'رفض',
  inputLabel: approve ? 'ملاحظة (اختياري)' : 'سبب الرفض (مطلوب)',
  inputRequired: !approve,
  destructive: !approve,
  success: approve ? 'تم قبول العذر وإلغاء الغرامة' : 'تم رفض العذر',
  action: (note) => ref
      .read(supabaseProvider)
      .rpc<dynamic>(
        'review_instant_penalty_excuse',
        params: {
          'p_penalty_id': item.id,
          'p_action': approve ? 'approved' : 'rejected',
          'p_notes': note.isEmpty ? null : note,
        },
      ),
);

/// صرف من صندوق الزمالة (الإدارة والمالية فقط — الخادم يتحقق ويرفض ما يتجاوز الرصيد).
Future<void> _showWithdrawSheet(
  BuildContext context,
  WidgetRef ref,
  double balance,
) async {
  final amountCtrl = TextEditingController();
  final reasonCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  const categories = [
    'مساعدة زميل',
    'رعاية صحية',
    'مناسبة اجتماعية',
    'حالة طارئة',
    'أخرى',
  ];
  var category = categories.first;
  var submitting = false;
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
        final valid =
            amount > 0 &&
            amount <= balance &&
            reasonCtrl.text.trim().length >= 3;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'تسجيل صرف من صندوق الزمالة',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'الرصيد المتاح: ${_money(balance)} — يُبلَّغ الفريق بالصرف وسببه للشفافية.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'المبلغ (ج.م)',
                  errorText: amount > balance
                      ? 'المبلغ أكبر من رصيد الصندوق'
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: category,
                decoration: InputDecoration(
                  labelText: 'البند',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: [
                  for (final c in categories)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => category = v ?? category),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'سبب الصرف (مطلوب)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                  labelText: 'ملاحظات (اختياري)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !valid || submitting
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        try {
                          await ref
                              .read(supabaseProvider)
                              .rpc<dynamic>(
                                'withdraw_from_fellowship_fund',
                                params: {
                                  'p_amount': amount,
                                  'p_category': category,
                                  'p_reason': reasonCtrl.text.trim(),
                                  'p_beneficiary_employee_id': null,
                                  'p_notes': notesCtrl.text.trim().isEmpty
                                      ? null
                                      : notesCtrl.text.trim(),
                                },
                              );
                          ref
                            ..invalidate(fellowshipFundSummaryProvider)
                            ..invalidate(fellowshipFundTransactionsProvider);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم تسجيل صرف ${_money(amount)} من الصندوق',
                              ),
                            ),
                          );
                        } catch (e) {
                          setState(() => submitting = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('تعذر الصرف: ${humanizeError(e)}'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.outbox_rounded, size: 18),
                label: Text(submitting ? 'جارٍ التسجيل…' : 'تسجيل الصرف'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// غرامات الموظفين — كل شخص باسمه
// ═══════════════════════════════════════════════════════════════════════════

enum _TeamFilter {
  all('الكل'),
  unpaid('غير مسددة'),
  excuses('أعذار للمراجعة'),
  paid('مسددة'),
  cancelled('ملغاة ومعفاة');

  const _TeamFilter(this.label);
  final String label;

  bool matches(MobileInstantPenalty p) => switch (this) {
    _TeamFilter.all => true,
    _TeamFilter.unpaid => _isUnpaid(p.status),
    _TeamFilter.excuses => p.excuseStatus == 'submitted' && _isUnpaid(p.status),
    _TeamFilter.paid => p.status == 'paid',
    _TeamFilter.cancelled => p.status == 'cancelled',
  };
}

/// الفترة حسب يوم الغرامة.
enum _Period {
  thisMonth('هذا الشهر'),
  lastMonth('الشهر الماضي'),
  all('كل الفترات');

  const _Period(this.label);
  final String label;

  bool contains(MobileInstantPenalty p) {
    if (this == _Period.all) return true;
    final d = DateTime.tryParse(p.workDate);
    if (d == null) return false;
    final now = DateTime.now();
    final start = this == _Period.thisMonth
        ? DateTime(now.year, now.month)
        : DateTime(now.year, now.month - 1);
    final end = DateTime(start.year, start.month + 1);
    return !d.isBefore(start) && d.isBefore(end);
  }
}

class _TeamPenaltiesTab extends ConsumerStatefulWidget {
  const _TeamPenaltiesTab();

  @override
  ConsumerState<_TeamPenaltiesTab> createState() => _TeamPenaltiesTabState();
}

class _TeamPenaltiesTabState extends ConsumerState<_TeamPenaltiesTab> {
  final _search = TextEditingController();
  String _query = '';
  _TeamFilter _filter = _TeamFilter.unpaid;
  _Period _period = _Period.all;
  final _expanded = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(teamInstantPenaltiesProvider);
    final manage = canManagePenalties(ref);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(teamInstantPenaltiesProvider),
      child: data.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(teamInstantPenaltiesProvider),
        ),
        data: (everything) {
          // الأرقام والقائمة للفترة المختارة
          final all = everything.where(_period.contains).toList();
          final excusesWaiting = all
              .where(
                (p) => p.excuseStatus == 'submitted' && _isUnpaid(p.status),
              )
              .length;
          final unpaidAll = all.where((p) => _isUnpaid(p.status));
          final dueTotal = unpaidAll.fold<double>(
            0,
            (s, p) => s + p.currentAmount,
          );
          final dueEmployees = {for (final p in unpaidAll) p.employeeId}.length;
          final paidTotal = all
              .where((p) => p.status == 'paid')
              .fold<double>(0, (s, p) => s + p.currentAmount);

          // التجميع بالموظف بعد التصفية
          final groups = <String, List<MobileInstantPenalty>>{};
          for (final p in all.where(_filter.matches)) {
            final hay = '${p.employeeName ?? ''} ${p.departmentName ?? ''}'
                .toLowerCase();
            if (_query.isNotEmpty && !hay.contains(_query)) continue;
            groups
                .putIfAbsent(p.employeeId ?? p.employeeName ?? '-', () => [])
                .add(p);
          }
          double due(List<MobileInstantPenalty> l) => l
              .where((p) => _isUnpaid(p.status))
              .fold<double>(0, (s, p) => s + p.currentAmount);
          final ordered = groups.entries.toList()
            ..sort((a, b) {
              final d = due(b.value).compareTo(due(a.value));
              if (d != 0) return d;
              return (a.value.first.employeeName ?? '').compareTo(
                b.value.first.employeeName ?? '',
              );
            });

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      _CountTile(
                        label: 'غير مسدد',
                        count: unpaidAll.length,
                        amount: dueTotal,
                        color: AppColors.statusWarning,
                      ),
                      const SizedBox(width: 8),
                      _CountTile(
                        label: 'موظفون عليهم مستحقات',
                        count: dueEmployees,
                        color: AppColors.statusDanger,
                      ),
                      const SizedBox(width: 8),
                      _CountTile(
                        label: 'مسدد للصندوق',
                        count: all.where((p) => p.status == 'paid').length,
                        amount: paidTotal,
                        color: AppColors.statusSuccess,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم الموظف أو الإدارة…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: .5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_Period>(
                showSelectedIcon: false,
                segments: [
                  for (final per in _Period.values)
                    ButtonSegment(value: per, label: Text(per.label)),
                ],
                selected: {_period},
                onSelectionChanged: (v) => setState(() => _period = v.first),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in _TeamFilter.values)
                    if (f != _TeamFilter.excuses || excusesWaiting > 0)
                      ChoiceChip(
                        label: Text(
                          f == _TeamFilter.excuses
                              ? '${f.label} ($excusesWaiting)'
                              : f.label,
                        ),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                ],
              ),
              const SizedBox(height: 12),
              if (ordered.isEmpty)
                const _EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'لا توجد غرامات مطابقة',
                  subtitle: 'غيّر التصفية أو البحث.',
                )
              else
                for (final g in ordered) ...[
                  _EmployeeGroupCard(
                    penalties: g.value,
                    manage: manage,
                    expanded: _expanded.contains(g.key),
                    onToggle: () => setState(() {
                      if (!_expanded.remove(g.key)) _expanded.add(g.key);
                    }),
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _EmployeeGroupCard extends StatelessWidget {
  const _EmployeeGroupCard({
    required this.penalties,
    required this.expanded,
    required this.onToggle,
    this.manage = false,
  });

  final List<MobileInstantPenalty> penalties;
  final bool expanded;
  final VoidCallback onToggle;
  final bool manage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = penalties.first;
    final name = first.employeeName ?? 'موظف';
    final unpaid = penalties.where((p) => _isUnpaid(p.status));
    final due = unpaid.fold<double>(0, (s, p) => s + p.currentAmount);
    final paid = penalties.where((p) => p.status == 'paid').length;
    final cancelled = penalties.where((p) => p.status == 'cancelled').length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AppAvatar(name: name, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (first.departmentName?.isNotEmpty ?? false)
                          Text(
                            first.departmentName!,
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
                            if (unpaid.isNotEmpty)
                              _Pill(
                                text: 'مستحق ${_money(due)} (${unpaid.length})',
                                color: AppColors.statusWarning,
                              ),
                            if (paid > 0)
                              _Pill(
                                text: 'مسددة: $paid',
                                color: AppColors.statusSuccess,
                              ),
                            if (cancelled > 0)
                              _Pill(
                                text: 'ملغاة: $cancelled',
                                color: const Color(0xFF64748B),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (final p in penalties) ...[
                    _PenaltyCard(item: p, manage: manage),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// صندوق الزمالة
// ═══════════════════════════════════════════════════════════════════════════

class _FundTab extends ConsumerWidget {
  const _FundTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(fellowshipFundSummaryProvider);
    final txs = ref.watch(fellowshipFundTransactionsProvider);
    final canWithdraw = canWithdrawFromFund(ref);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(fellowshipFundSummaryProvider);
        ref.invalidate(fellowshipFundTransactionsProvider);
      },
      child: summary.when(
        loading: () => const _Loading(),
        error: (error, _) => _ErrorView(
          message: humanizeError(error),
          onRetry: () => ref.invalidate(fellowshipFundSummaryProvider),
        ),
        data: (s) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Card(
              color: AppColors.statusSuccess.withValues(alpha: .08),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: AppColors.statusSuccess.withValues(alpha: .35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(
                      Icons.volunteer_activism_rounded,
                      color: AppColors.statusSuccess,
                      size: 30,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'رصيد صندوق الزمالة والتكافل',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _money(s.currentBalance),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.statusSuccess,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _CountTile(
                          label: 'إجمالي الوارد',
                          count: s.inflowsCount,
                          amount: s.totalInflows,
                          color: AppColors.statusSuccess,
                        ),
                        const SizedBox(width: 8),
                        _CountTile(
                          label: 'إجمالي المصروف',
                          count: s.outflowsCount,
                          amount: s.totalOutflows,
                          color: AppColors.statusDanger,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'هذا الشهر: وارد ${_money(s.monthlyInflows)} · مصروف ${_money(s.monthlyOutflows)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            const _Notice(
              icon: Icons.info_outline_rounded,
              color: AppColors.statusInfo,
              text:
                  'تُودَع غرامات التأخير كاملة في الصندوق ولا تُخصم من الرواتب، ويُصرف منه لدعم الزملاء في الحالات الطارئة والرعاية الصحية والمناسبات الاجتماعية.',
            ),
            if (s.categories.isNotEmpty) ...[
              const SizedBox(height: 16),
              const _SectionTitle(title: 'حسب البند'),
              const SizedBox(height: 6),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      for (final c in s.categories)
                        _DetailRow(
                          label: c.category,
                          value:
                              '${c.type == 'outflow' ? 'مصروف' : 'وارد'} ${_money(c.total)} (${c.count})',
                          color: c.type == 'outflow'
                              ? AppColors.statusDanger
                              : AppColors.statusSuccess,
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (canWithdraw) ...[
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: s.currentBalance > 0
                    ? () => _showWithdrawSheet(context, ref, s.currentBalance)
                    : null,
                icon: const Icon(Icons.outbox_rounded),
                label: Text(
                  s.currentBalance > 0
                      ? 'تسجيل صرف من الصندوق'
                      : 'لا يوجد رصيد للصرف',
                ),
              ),
            ],
            const SizedBox(height: 16),
            const _SectionTitle(title: 'حركات الصندوق'),
            const SizedBox(height: 6),
            txs.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(humanizeError(error)),
              data: (list) => list.isEmpty
                  ? const _EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'لا توجد حركات بعد',
                      subtitle:
                          'تظهر هنا مبالغ الغرامات المسددة وما يُصرف من الصندوق.',
                    )
                  : Card(
                      child: Column(
                        children: [
                          for (var i = 0; i < list.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _FundTxTile(tx: list[i]),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FundTxTile extends StatelessWidget {
  const _FundTxTile({required this.tx});

  final FellowshipFundTransaction tx;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tx.isInflow
        ? AppColors.statusSuccess
        : AppColors.statusDanger;
    final title = tx.isInflow
        ? (tx.sourceType == 'instant_penalty'
              ? 'سداد غرامة تأخير'
              : (tx.category ?? 'إيداع'))
        : (tx.category ?? 'صرف من الصندوق');
    final sub = [
      if (tx.employeeName != null) tx.employeeName!,
      if (tx.reason != null && tx.reason != tx.category) tx.reason!,
      '${DateFormat('d MMMM y', 'ar').format(tx.createdAt)} · ${DateFormat('h:mm a', 'ar').format(tx.createdAt)}',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: .12),
            child: Icon(
              tx.isInflow ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                for (final line in sub)
                  Text(
                    humanizeIsoLike(line),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // الاتجاه بالأيقونة واللون — علامة +/− تنقلب مع «ج.م» في سياق عربي
              Text(
                _money(tx.amount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
              if (tx.balanceAfter != null)
                Text(
                  'الرصيد ${_money(tx.balanceAfter!)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// عناصر مشتركة
// ═══════════════════════════════════════════════════════════════════════════

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.count,
    required this.color,
    this.amount,
  });

  final String label;
  final int count;
  final double? amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .25)),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            // سطر واحد دائمًا — كانت «مضاعفة / موقوفة» تنكسر فتختلف الارتفاعات
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            if (amount != null && amount! > 0) ...[
              const SizedBox(height: 2),
              Text(
                _money(amount!),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(
            icon,
            size: 52,
            color: theme.colorScheme.primary.withValues(alpha: .6),
          ),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      SizedBox(height: 200),
      Center(child: CircularProgressIndicator()),
    ],
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 100),
      Icon(
        Icons.error_outline,
        size: 48,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المحاولة'),
        ),
      ),
    ],
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// صياغة
// ═══════════════════════════════════════════════════════════════════════════

bool _isUnpaid(String status) =>
    status == 'pending_payment' || status == 'doubled' || status == 'suspended';

String _money(num v) => '${fmtUnits(v)} ج.م';

String _minutes(int m) => switch (m) {
  1 => 'دقيقة واحدة',
  2 => 'دقيقتان',
  >= 3 && <= 10 => '$m دقائق',
  _ => '$m دقيقة',
};

String _duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return _minutes(m);
  return m == 0 ? '$h ساعة' : '$h ساعة و$m دقيقة';
}

String _dateTime(DateTime t) {
  final local = t.toLocal();
  return '${DateFormat('d MMMM y', 'ar').format(local)} · ${DateFormat('h:mm a', 'ar').format(local)}';
}

/// وقت تسجيل الغرامة: الساعة وحدها إن كانت يوم العمل نفسه (الغالب)، وإلا
/// التاريخ معها.
String _registeredAt(DateTime createdAt, DateTime? workDate) {
  final local = createdAt.toLocal();
  final time = DateFormat('h:mm a', 'ar').format(local);
  final sameDay =
      workDate != null &&
      local.year == workDate.year &&
      local.month == workDate.month &&
      local.day == workDate.day;
  return sameDay ? time : '${DateFormat('d MMM', 'ar').format(local)} · $time';
}

String _paymentLabel(String? method) => switch (method) {
  null || 'cash' => 'نقدًا لدى مسؤول الصندوق',
  'vodafone_cash' => 'فودافون كاش',
  'bank_transfer' => 'تحويل بنكي',
  'wallet' => 'محفظة إلكترونية',
  'instapay' => 'تحويل إلكتروني',
  _ => 'نقدًا',
};

/// ({label, color, icon, exempt}) لحالة الغرامة.
({String label, Color color, IconData icon, bool exempt}) _statusMeta(
  MobileInstantPenalty item,
) {
  if (item.status == 'cancelled') {
    final hay = '${item.cancelledReason ?? ''} ${item.notes ?? ''}';
    final exempt = const [
      'إعفاء',
      'معفى',
      'إلغاء تلقائي',
      'بأثر رجعي',
      'مأمورية',
      'إجازة',
      'قافلة',
      'فاندي',
      'استثناء',
    ].any(hay.contains);
    return exempt
        ? (
            label: 'معفاة',
            color: const Color(0xFF0D9488),
            icon: Icons.verified_outlined,
            exempt: true,
          )
        : (
            label: 'ملغاة',
            color: const Color(0xFF64748B),
            icon: Icons.cancel_outlined,
            exempt: false,
          );
  }
  return switch (item.status) {
    'pending_payment' => (
      label: 'بانتظار السداد',
      color: AppColors.statusWarning,
      icon: Icons.schedule_rounded,
      exempt: false,
    ),
    'doubled' => (
      label: 'مضاعفة',
      color: const Color(0xFFEA580C),
      icon: Icons.trending_up_rounded,
      exempt: false,
    ),
    'suspended' => (
      label: 'الحساب موقوف',
      color: AppColors.statusDanger,
      icon: Icons.block_rounded,
      exempt: false,
    ),
    'paid' => (
      label: 'مسددة',
      color: AppColors.statusSuccess,
      icon: Icons.check_circle_rounded,
      exempt: false,
    ),
    _ => (
      label: 'غير محددة',
      color: const Color(0xFF64748B),
      icon: Icons.help_outline_rounded,
      exempt: false,
    ),
  };
}

/// الملاحظات القديمة متداخلة («تم الإلغاء بواسطة الإدارة: س (تم الإلغاء… (…)))»)
/// وبأوقات AM/PM — تُفك إلى أسباب الإلغاء وأسطر التفاصيل بالعربية.
({List<String> reasons, List<String> lines}) _parseNotes(String? notes) {
  var text = (notes ?? '').trim();
  final reasons = <String>[];
  const prefix = 'تم الإلغاء بواسطة الإدارة: ';
  while (text.startsWith(prefix)) {
    final rest = text.substring(prefix.length);
    final open = rest.indexOf(' (');
    if (open < 0) {
      reasons.add(rest.trim());
      text = '';
      break;
    }
    reasons.add(rest.substring(0, open).trim());
    var inner = rest.substring(open + 2).trim();
    if (inner.endsWith(')')) inner = inner.substring(0, inner.length - 1);
    text = inner.trim();
  }
  final lines = text.isEmpty
      ? <String>[]
      : text
            .split(' | ')
            .map((l) => humanizeIsoLike(l.trim()))
            .where((l) => l.isNotEmpty)
            .toList();
  return (reasons: reasons.toSet().toList(), lines: lines);
}

/// «11:57 AM» ← «11:57 ص»، وتواريخ ISO داخل النص بصيغة عربية لا تنقلب.
String humanizeIsoLike(String text) => text
    .replaceAllMapped(
      RegExp(r'(\d{1,2}:\d{2})\s*(AM|am)\b'),
      (m) => '${m[1]} ص',
    )
    .replaceAllMapped(
      RegExp(r'(\d{1,2}:\d{2})\s*(PM|pm)\b'),
      (m) => '${m[1]} م',
    )
    .replaceAllMapped(
      RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
      (m) => '${m[3]!.padLeft(2, '0')}/${m[2]!.padLeft(2, '0')}/${m[1]}',
    );
