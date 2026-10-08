import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/formatting/arabic_text.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

/// عناصر قوائم الطلبات المشتركة بين «الطلبات» و«طلباتي» (الخدمة الذاتية).

/// أرصدة الإجازات: المتاح بخط كبير، وشريط المستهلك والمحجوز من الإجمالي.
class LeaveBalanceStrip extends StatelessWidget {
  const LeaveBalanceStrip({required this.balances, this.onTap, super.key});

  final List<MobileLeaveBalance> balances;
  final VoidCallback? onTap;

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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (balances.isEmpty) {
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
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: balances.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final balance = balances[index];
          return SizedBox(
            width: 190,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balance.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: fmtUnits(balance.availableUnits),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            TextSpan(
                              text: '  ${availableWord(balance.availableUnits)}',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: usedShare(balance),
                          backgroundColor:
                              AppColors.statusSuccess.withValues(alpha: .18),
                          valueColor: const AlwaysStoppedAnimation(
                            AppColors.statusWarning,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'مستهلك ${fmtUnits(balance.consumedUnits)} · محجوز ${fmtUnits(balance.reservedUnits)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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
                  CircleAvatar(
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
                  RequestStatusChip(item.status, dense: true),
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
