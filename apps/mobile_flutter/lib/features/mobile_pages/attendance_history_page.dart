import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// سجل الحضور والانصراف: يوم واحد = بطاقة واحدة (حضور، انصراف، مدة العمل)،
/// الأحدث أولًا — بدل بطاقة لكل عملية بشرائح مبهمة («21 م» = متر أم مساءً؟).
class AttendanceHistoryPage extends ConsumerWidget {
  const AttendanceHistoryPage({this.highlightDate, super.key});

  /// تاريخ اليوم (yyyy-MM-dd) القادم من إشعار حضور — تُبرز عمليات ذلك اليوم.
  final String? highlightDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(myAttendanceHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الحضور والانصراف')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myAttendanceHistoryProvider),
          child: history.when(
            loading: () => LayoutBuilder(
              builder: (context, constraints) => ListView(
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            ),
            error: (error, _) => ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 40,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          humanizeError(error),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () =>
                              ref.invalidate(myAttendanceHistoryProvider),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.history_toggle_off,
                        size: 52,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'لا توجد عمليات حضور حتى الآن',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : _HistoryList(items: items, highlightDate: highlightDate),
          ),
        ),
      ),
    );
  }
}

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.items, required this.highlightDate});

  final List<AttendanceHistoryItem> items;
  final String? highlightDate;

  @override
  Widget build(BuildContext context) {
    // تجميع بالأيام (بالتوقيت المحلي): الأيام الأحدث أولًا، والعمليات داخل
    // اليوم بترتيبها الزمني (حضور ثم انصراف).
    final byDay = <String, List<AttendanceHistoryItem>>{};
    for (final item in items) {
      (byDay[_dayKey(item.eventAt.toLocal())] ??= []).add(item);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final list in byDay.values) {
      list.sort((a, b) => a.eventAt.compareTo(b.eventAt));
    }

    final checkIns = items.where((e) => e.eventType == 'CHECK_IN').toList();
    final attendedDays = {
      for (final e in checkIns) _dayKey(e.eventAt.toLocal()),
    }.length;
    final lateIns = checkIns.where((e) => e.lateMinutes > 0).toList();
    final lateMinutes = lateIns.fold<int>(0, (s, e) => s + e.lateMinutes);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: days.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _SummaryStrip(
              attendedDays: attendedDays,
              lateDays: lateIns.length,
              lateMinutes: lateMinutes,
              operations: items.length,
            ),
          );
        }
        final key = days[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _DayCard(
            day: DateTime.parse(key),
            events: byDay[key]!,
            highlighted: highlightDate == key,
          ),
        );
      },
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.attendedDays,
    required this.lateDays,
    required this.lateMinutes,
    required this.operations,
  });

  final int attendedDays;
  final int lateDays;
  final int lateMinutes;
  final int operations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget stat(String value, String label, Color color) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    Widget divider() => Container(
      width: 1,
      height: 30,
      color: scheme.outlineVariant.withValues(alpha: .6),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            AppColors.brandPrimary.withValues(alpha: .14),
            AppColors.accent.withValues(alpha: .05),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .18)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              stat('$attendedDays', 'يوم حضور', scheme.primary),
              divider(),
              stat(
                '$lateDays',
                'أيام تأخير',
                lateDays > 0
                    ? AppColors.statusWarning
                    : AppColors.statusSuccess,
              ),
              divider(),
              stat(
                '$lateMinutes',
                'دقيقة تأخير',
                lateMinutes > 0
                    ? AppColors.statusWarning
                    : AppColors.statusSuccess,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'آخر 30 يومًا · $operations عملية مسجلة',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.events,
    this.highlighted = false,
  });

  final DateTime day;
  final List<AttendanceHistoryItem> events;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(DateTime(day.year, day.month, day.day));
    final relative = switch (diff.inDays) {
      0 => 'اليوم',
      1 => 'أمس',
      _ => null,
    };

    final ins = events.where((e) => e.eventType == 'CHECK_IN').toList();
    final outs = events.where((e) => e.eventType == 'CHECK_OUT').toList();
    final firstIn = ins.isEmpty ? null : ins.first;
    final lastOut = outs.isEmpty ? null : outs.last;
    final late = firstIn?.lateMinutes ?? 0;
    Duration? worked;
    if (firstIn != null &&
        lastOut != null &&
        lastOut.eventAt.isAfter(firstIn.eventAt)) {
      worked = lastOut.eventAt.difference(firstIn.eventAt);
    }

    // شارة اليوم: التأخير أهم ما يُرى، ثم انصراف لم يُسجَّل لليوم الماضي
    final (String, Color)? badge = late > 0
        ? ('تأخير $late د', AppColors.statusWarning)
        : firstIn != null && lastOut == null && diff.inDays > 0
        ? ('بلا انصراف', AppColors.statusDanger)
        : firstIn != null
        ? ('في الموعد', AppColors.statusSuccess)
        : null;

    return Container(
      decoration: BoxDecoration(
        color: highlighted
            ? scheme.primary.withValues(alpha: .07)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: .55),
          width: highlighted ? 1.6 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── اليوم + شارته ──
          Row(
            children: [
              Text(
                DateFormat('EEEE d MMMM', 'ar').format(day),
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (relative != null) ...[
                const SizedBox(width: 6),
                Text(
                  '· $relative',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ],
              const Spacer(),
              if (badge != null) _Badge(label: badge.$1, color: badge.$2),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _EventRow(item: events[i]),
          ],
          if (worked != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.timelapse_rounded,
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  'مدة التواجد ${_duration(worked)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '$m د';
    if (m == 0) return '$h س';
    return '$h س $m د';
  }
}

/// سطر عملية واحدة: النوع والوقت بوضوح، والتفاصيل التقنية شرائح صغيرة.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.item});

  final AttendanceHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final checkIn = item.eventType == 'CHECK_IN';
    final accent = checkIn ? AppColors.statusSuccess : AppColors.statusInfo;
    final (verifyIcon, verifyLabel, verifyColor) = _verification(
      item.verificationStatus,
      scheme,
    );
    final source = _sourceLabel(item.source);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              checkIn ? Icons.login_rounded : Icons.logout_rounded,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      checkIn ? 'حضور' : 'انصراف',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('h:mm a', 'ar').format(item.eventAt.toLocal()),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    if (item.status != 'accepted')
                      MobileStatusPill(item.status),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _MiniChip(
                      icon: verifyIcon,
                      label: verifyLabel,
                      color: verifyColor,
                    ),
                    if (source != null)
                      _MiniChip(
                        icon: Icons.bolt_rounded,
                        label: source,
                        color: AppColors.statusViolet,
                      ),
                    if (item.distanceMeters != null)
                      _MiniChip(
                        icon: Icons.near_me_rounded,
                        label: 'على بُعد ${item.distanceMeters!.round()} م',
                        color: item.status == 'accepted'
                            ? AppColors.statusSuccess
                            : scheme.onSurfaceVariant,
                      ),
                    if (item.accuracyMeters != null)
                      _MiniChip(
                        icon: Icons.gps_fixed_rounded,
                        label: 'دقة ±${item.accuracyMeters!.round()} م',
                        color: scheme.onSurfaceVariant,
                      ),
                    if (item.requiresReview)
                      _MiniChip(
                        icon: Icons.flag_outlined,
                        label: 'يحتاج مراجعة',
                        color: scheme.error,
                      ),
                  ],
                ),
                if ((item.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.notes!.trim(),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// قيم verification_status الفعلية (attendance_events): كان
  /// server_verified يظهر «غير موثق».
  static (IconData, String, Color) _verification(
    String value,
    ColorScheme scheme,
  ) => switch (value) {
    'passkey_verified' => (
      Icons.key_rounded,
      'مفتاح المرور',
      AppColors.statusSuccess,
    ),
    'biometric_verified' => (
      Icons.fingerprint_rounded,
      'بصمة الجهاز',
      AppColors.statusSuccess,
    ),
    'server_verified' => (
      Icons.verified_rounded,
      'تحقق الخادم',
      AppColors.statusSuccess,
    ),
    'failed' => (Icons.close_rounded, 'فشل التحقق', scheme.error),
    _ => (Icons.help_outline_rounded, 'غير موثّق', scheme.onSurfaceVariant),
  };

  /// المصدر يُذكر فقط حين لا يكون التطبيق نفسه.
  static String? _sourceLabel(String source) => switch (source) {
    'mission_auto' => 'تلقائي — نهاية مأمورية',
    'kiosk' => 'جهاز الحضور',
    'web' => 'من الويب',
    'service' => 'تسجيل إداري',
    'import' => 'مستورد',
    _ => null,
  };
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    ),
  );
}

/// شريحة معلومات صغيرة (أيقونة + نص)
class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}
