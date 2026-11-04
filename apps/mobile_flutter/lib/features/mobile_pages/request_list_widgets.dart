import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

/// عناصر قوائم الطلبات المشتركة بين «الطلبات» و«طلباتي» (الخدمة الذاتية).

/// أرصدة الإجازات وأذونات الشهر: المتاح بخط بارز، وشريط المستهلك والمحجوز.
/// يعرض جميع أرصدة الإجازات وأذونات الشهر الـ 4 مع خيار التبديل بين الشبكة والشريط.
class LeaveBalanceStrip extends ConsumerStatefulWidget {
  const LeaveBalanceStrip({
    required this.balances,
    this.onTap,
    this.onPermitTap,
    super.key,
  });

  final List<MobileLeaveBalance> balances;
  final VoidCallback? onTap;
  final VoidCallback? onPermitTap;

  /// «14 يومًا متاحًا» / «6 أيام متاحة» / «يومان متاحان».
  static String availableWord(double v) {
    if (v % 1 != 0) return 'يوم متاح';
    final n = v.toInt();
    if (n == 2) return 'يومان متاحان';
    final m = n % 100;
    if (n > 2 && m >= 3 && m <= 10) return 'أيام متاحة';
    if (m >= 11 && m <= 99) return 'يومًا متاحًا';
    return 'يوم متاح';
  }

  /// نصيب المستهلك والمحجوز من إجمالي الرصيد (لشريط البطاقة).
  static double usedShare(MobileLeaveBalance b) {
    final used = b.consumedUnits + b.reservedUnits;
    final total = used + (b.availableUnits > 0 ? b.availableUnits : 0);
    return total <= 0 ? 0 : (used / total).clamp(0, 1).toDouble();
  }

  @override
  ConsumerState<LeaveBalanceStrip> createState() => _LeaveBalanceStripState();
}

class _LeaveBalanceStripState extends ConsumerState<LeaveBalanceStrip> {
  bool _isGridView = true;

  static Color _balanceColor(String code) {
    return switch (code.toLowerCase()) {
      'annual' => const Color(0xFF0284C7),
      'casual' => const Color(0xFFF59E0B),
      'rest_day' || 'weekly_rest' || 'rest' => const Color(0xFF10B981),
      'sick' => const Color(0xFFE11D48),
      'permit' => const Color(0xFF6366F1),
      _ => const Color(0xFF8B5CF6),
    };
  }

  static IconData _balanceIcon(String code) {
    return switch (code.toLowerCase()) {
      'annual' => Icons.beach_access_rounded,
      'casual' => Icons.flash_on_rounded,
      'rest_day' || 'weekly_rest' || 'rest' => Icons.weekend_rounded,
      'sick' => Icons.healing_rounded,
      'permit' => Icons.alarm_on_rounded,
      _ => Icons.event_note_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final permitBalance = ref.watch(myPermitBalanceProvider).asData?.value;

    final remPermits = permitBalance?.remainingPermits ?? 4;
    final maxPermits = permitBalance?.maxPermits ?? 4;
    final remHours = permitBalance?.remainingHours ?? (remPermits * 2);
    final totalUsed = permitBalance?.totalUsed ?? 0;
    final usedPending = permitBalance?.usedPending ?? 0;
    final permitProgress =
        maxPermits > 0 ? (totalUsed / maxPermits).clamp(0.0, 1.0) : 0.0;

    final permitCard = _BalanceCard(
      icon: Icons.alarm_on_rounded,
      title: 'أذونات الشهر',
      tag: 'شهري',
      valueText: '$remPermits',
      unitText: 'من $maxPermits أذونات',
      extraText: '($remHours س)',
      progress: permitProgress,
      progressColor: remPermits == 0
          ? AppColors.statusDanger
          : remPermits <= 1
          ? AppColors.statusWarning
          : const Color(0xFF6366F1),
      footerText: 'مستهلك $totalUsed من 4 · محجوز $usedPending',
      accentColor: const Color(0xFF6366F1),
      onTap: widget.onPermitTap ?? widget.onTap,
    );

    final leaveCards = widget.balances.map((balance) {
      final accent = _balanceColor(balance.code);
      final icon = _balanceIcon(balance.code);
      final progress = LeaveBalanceStrip.usedShare(balance);
      return _BalanceCard(
        icon: icon,
        title: balance.name,
        tag: 'سنوي',
        valueText: fmtUnits(balance.availableUnits),
        unitText: LeaveBalanceStrip.availableWord(balance.availableUnits),
        progress: progress,
        progressColor: balance.availableUnits <= 0
            ? AppColors.statusDanger
            : balance.availableUnits <= 3
            ? AppColors.statusWarning
            : AppColors.statusSuccess,
        footerText:
            'مستهلك ${fmtUnits(balance.consumedUnits)} · محجوز ${fmtUnits(balance.reservedUnits)}',
        accentColor: accent,
        onTap: widget.onTap,
      );
    }).toList();

    // تنظيم البطاقات بحيث تظهر السنوية والعارضة أولاً، ثم الأذونات، ثم بدل الراحة والإجازات الأخرى
    final allCards = <Widget>[];
    final annualIndex = widget.balances.indexWhere((b) => b.code == 'annual');
    final casualIndex = widget.balances.indexWhere((b) => b.code == 'casual');

    if (annualIndex != -1) allCards.add(leaveCards[annualIndex]);
    if (casualIndex != -1) allCards.add(leaveCards[casualIndex]);
    allCards.add(permitCard);

    for (int i = 0; i < widget.balances.length; i++) {
      if (i != annualIndex && i != casualIndex) {
        allCards.add(leaveCards[i]);
      }
    }

    if (allCards.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.event_available_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              const Expanded(child: Text('لم تُضبط أرصدة إجازات لهذا الحساب بعد.')),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الأرصدة المتاحة (${allCards.length})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _isGridView = !_isGridView),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isGridView
                            ? Icons.view_carousel_rounded
                            : Icons.grid_view_rounded,
                        size: 15,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isGridView ? 'عرض شريط' : 'عرض شبكي',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isGridView)
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final tileWidth = (width - 10) / 2;
              const targetHeight = 124.0;
              final ratio = (tileWidth / targetHeight).clamp(1.1, 3.8);
              return GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: ratio,
                children: allCards,
              );
            },
          )
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: allCards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => SizedBox(
                width: 195,
                child: allCards[index],
              ),
            ),
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.icon,
    required this.title,
    required this.tag,
    required this.valueText,
    required this.unitText,
    this.extraText,
    required this.progress,
    required this.progressColor,
    required this.footerText,
    required this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String tag;
  final String valueText;
  final String unitText;
  final String? extraText;
  final double progress;
  final Color progressColor;
  final String footerText;
  final Color accentColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: isDark ? 0.09 : 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accentColor.withValues(alpha: isDark ? 0.28 : 0.18),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // الصف العلوي: الأيقونة + العنوان + التاج
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(icon, size: 14, color: accentColor),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // القيمة الرئيسية المتاحة
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      valueText,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      unitText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (extraText != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        extraText!,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 5),

              // شريط نسبة الاستهلاك
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: progress,
                  backgroundColor: accentColor.withValues(alpha: .14),
                  valueColor: AlwaysStoppedAnimation(progressColor),
                ),
              ),
              const SizedBox(height: 4),

              // التذييل: المستهلك والمحجوز
              Text(
                footerText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ملخص طلباتي هذا الشهر: العدد وتوزيع الحالات.
class RequestMonthSummary extends StatelessWidget {
  const RequestMonthSummary({required this.requests, super.key});

  final List<MobileRequest> requests;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = requests
        .where((r) {
          final t = r.createdAt.toLocal();
          return t.year == now.year && t.month == now.month;
        })
        .toList(growable: false);
    int count(bool Function(MobileRequest) test) => month.where(test).length;
    final approved = count((r) => r.status == 'approved');
    final pending = count((r) => r.status == 'pending');
    final declined = count((r) => r.status == 'rejected' || r.status == 'returned');
    final monthName = DateFormat('MMMM', 'ar').format(now);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            month.isEmpty
                ? 'لا طلبات لك في $monthName حتى الآن'
                : 'طلباتك في $monthName: ${arRequests(month.length)}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          if (month.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (approved > 0)
                  RequestMetaChip(
                    icon: Icons.verified_rounded,
                    text: 'معتمد $approved',
                    color: AppColors.statusSuccess,
                  ),
                if (pending > 0)
                  RequestMetaChip(
                    icon: Icons.hourglass_top_rounded,
                    text: 'قيد المراجعة $pending',
                    color: AppColors.statusWarning,
                  ),
                if (declined > 0)
                  RequestMetaChip(
                    icon: Icons.undo_rounded,
                    text: 'مرفوض أو مُعاد $declined',
                    color: AppColors.statusDanger,
                  ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'اضغط «طلب جديد» لتقديم إجازة أو مأمورية أو إذن.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة طلب في القوائم (طلباتي / طلبات الآخرين) بتصميم موحّد.
class RequestListCard extends StatelessWidget {
  const RequestListCard({required this.item, this.showOwner = false, super.key});

  final MobileRequest item;

  /// في «طلبات الآخرين» يظهر اسم صاحب الطلب.
  final bool showOwner;

  static const _resubmittable = {
    'leave',
    'mission',
    'convoy',
    'fundraising',
    'late_permit',
    'early_permit',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final typeColor = requestTypeColor(item.type);
    final typeLabel = requestTypeLabel(item.type);
    final title = item.title?.trim();
    final brief = requestBriefLine(item.type, item.payload);
    final style = requestStatusStyle(item.status);
    final canFix =
        !showOwner &&
        (item.status == 'returned' || item.status == 'rejected') &&
        _resubmittable.contains(item.type);
    final pending = item.status == 'pending';
    final due = pending ? requestDueStatus(item.effectiveDueAt) : null;
    final stage = item.activeStepName == null
        ? null
        : requestStageName(item.activeStepName, roleSlug: item.activeStepRole);

    final footer = switch (item.status) {
      'pending' => stage == null ? 'قيد المراجعة' : 'بانتظار قرار $stage',
      'approved' =>
        item.decidedByName == null ? 'تم الاعتماد' : 'اعتمده ${item.decidedByName}',
      'rejected' =>
        item.decidedByName == null ? 'رُفض الطلب' : 'رفضه ${item.decidedByName}',
      'returned' =>
        item.decidedByName == null
            ? 'أُعيد للتعديل'
            : 'أعاده ${item.decidedByName} للتعديل',
      'cancelled' => 'سُحب الطلب',
      _ => style.label,
    };
    final footerTime = item.decidedAt ?? item.createdAt;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: canFix
              ? style.color.withValues(alpha: .4)
              : scheme.outlineVariant.withValues(alpha: .6),
        ),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MobileRequestDetailPage(requestId: item.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  showOwner
                      ? Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AppAvatar(
                              name: item.employeeName,
                              photoUrl: item.employeePhotoUrl,
                              radius: 21,
                            ),
                            Positioned(
                              bottom: -2,
                              left: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: typeColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Icon(
                                  requestTypeIcon(item.type),
                                  size: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        )
                      : CircleAvatar(
                          radius: 21,
                          backgroundColor: typeColor.withValues(alpha: .12),
                          child: Icon(
                            requestTypeIcon(item.type),
                            size: 21,
                            color: typeColor,
                          ),
                        ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          showOwner ? '$typeLabel · ${item.employeeName}' : typeLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: typeColor,
                          ),
                        ),
                        Text(
                          'طلب رقم ${item.number} · ${arAgo(item.createdAt)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RequestStatusChip(item.status, dense: true),
                      const SizedBox(height: 4),
                      RequestSlaChip(
                        sla: calculateRequestSla(
                          createdAt: item.createdAt,
                          status: item.status,
                          decidedAt: item.decidedAt,
                          activeStepName: item.activeStepName,
                          activeStepRole: item.activeStepRole,
                          decidedByName: item.decidedByName,
                        ),
                        dense: true,
                        showDetail: false,
                      ),
                    ],
                  ),
                ],
              ),
              if (title != null && title.isNotEmpty && title != typeLabel) ...[
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    height: 1.35,
                  ),
                ),
              ],
              if (brief.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  brief,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              // 0452: الطلب المرفوض/المُعاد يُعدَّل ويعاد رفعه من صفحته
              if (canFix) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note_rounded, size: 17, color: style.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.status == 'returned'
                              ? 'أُعيد إليك — افتحه لتعديله وإعادة رفعه'
                              : 'يمكنك تعديله وإعادة رفعه من صفحته',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: style.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 20),
              Row(
                children: [
                  Icon(style.icon, size: 16, color: style.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      footer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (due != null)
                    RequestMetaChip(
                      icon: due.overdue
                          ? Icons.warning_amber_rounded
                          : Icons.schedule_rounded,
                      text: due.label,
                      color: due.overdue ? AppColors.statusDanger : null,
                      strong: due.overdue,
                    )
                  else
                    Text(
                      arDateTime(footerTime),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
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
}
