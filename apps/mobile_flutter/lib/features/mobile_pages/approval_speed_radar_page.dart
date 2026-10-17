import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/request_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// موفر بيانات تقرير سرعة الاعتماد ورادار التعطل
/// موفر بيانات تقرير سرعة الاعتماد ورادار التعطل
/// الفلاتر: 0 = هذا الشهر، 1 = آخر 30 يوم، 2 = كل الأوقات
final approvalSpeedRadarProvider =
    FutureProvider.family<Map<String, dynamic>, int>((
      ref,
      filterIndex,
    ) async {
      final now = DateTime.now();
      final dateFmt = DateFormat('yyyy-MM-dd');
      final params = <String, dynamic>{};

      if (filterIndex == 0) {
        // هذا الشهر
        final start = DateTime(now.year, now.month, 1);
        params['p_from'] = dateFmt.format(start);
        params['p_to'] = dateFmt.format(now);
      } else if (filterIndex == 1) {
        // آخر 30 يوماً
        final start = now.subtract(const Duration(days: 30));
        params['p_from'] = dateFmt.format(start);
        params['p_to'] = dateFmt.format(now);
      }
      // filterIndex == 2 => كل الأوقات (بدون قيود زمنية)

      final data = await rpcWithTimeout(
        ref
            .watch(supabaseProvider)
            .rpc<dynamic>('get_approval_speed_report', params: params),
      );
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return const <String, dynamic>{};
    });

/// رادار تعطل الإجراءات وسرعة الاعتماد (Bottleneck Radar & SLA Tracker).
/// لوحة متابعة للمدير التنفيذي ومديري الموارد البشرية ترصد متوسط سرعة الرد
/// وأماكن التعطل بين المكاتب وتُتيح التواصل السريع عبر واتساب لإنهاء المعلقات.
class ApprovalSpeedRadarPage extends ConsumerStatefulWidget {
  const ApprovalSpeedRadarPage({super.key});

  @override
  ConsumerState<ApprovalSpeedRadarPage> createState() =>
      _ApprovalSpeedRadarPageState();
}

class _ApprovalSpeedRadarPageState
    extends ConsumerState<ApprovalSpeedRadarPage> {
  // فترات الفلترة: 0 = هذا الشهر، 1 = آخر 30 يوم، 2 = كل الأوقات
  int _selectedFilter = 0;

  String _formatHours(num hours) {
    if (hours <= 0) return '0 س';
    if (hours < 1) {
      final mins = (hours * 60).round();
      return '$mins دقيقة';
    }
    return '${hours.toStringAsFixed(1)} ساعة';
  }

  (Color, String) _speedTone(num avgHours) {
    if (avgHours <= 0) {
      return (const Color(0xFF64748B), 'لا قرارات');
    }
    if (avgHours <= 2) {
      return (AppColors.statusSuccess, 'قياسي جداً (< 2 س)');
    }
    if (avgHours <= 6) {
      return (const Color(0xFF0284C7), 'سريع ومثالي (2-6 س)');
    }
    if (avgHours <= 24) {
      return (const Color(0xFFD97706), 'معتدل (6-24 س)');
    }
    return (AppColors.statusDanger, 'متأخر (> 24 س)');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reportAsync = ref.watch(approvalSpeedRadarProvider(_selectedFilter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('رادار سرعة الاعتماد وتعطل الإجراءات'),
        actions: [
          IconButton(
            tooltip: 'تحديث البيانات',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(approvalSpeedRadarProvider(_selectedFilter)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(approvalSpeedRadarProvider(_selectedFilter)),
        child: reportAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    'تعذر تحميل رادار سرعة الاعتماد: ${humanizeError(err)}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => ref.invalidate(
                        approvalSpeedRadarProvider(_selectedFilter)),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          ),
          data: (data) {
            final summary = data['summary'] is Map
                ? Map<String, dynamic>.from(data['summary'] as Map)
                : const <String, dynamic>{};
            final approvers = (data['approvers'] as List<dynamic>? ?? const [])
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false);
            final byType = (data['byRequestType'] as List<dynamic>? ?? const [])
                .whereType<Map<dynamic, dynamic>>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(growable: false);

            final totalDecisions =
                (summary['total_decisions'] as num?)?.toInt() ?? 0;
            final totalApproved =
                (summary['total_approved'] as num?)?.toInt() ?? 0;
            final totalRejected =
                (summary['total_rejected'] as num?)?.toInt() ?? 0;
            final avgHours =
                (summary['avg_turnaround_hours'] as num?)?.toDouble() ?? 0.0;
            final medianHours =
                (summary['median_turnaround_hours'] as num?)?.toDouble() ?? 0.0;
            final totalPending =
                (summary['total_pending'] as num?)?.toInt() ?? 0;
            final totalEscalated =
                (summary['total_escalated'] as num?)?.toInt() ?? 0;

            final approvalRate = totalDecisions > 0
                ? ((totalApproved / totalDecisions) * 100).round()
                : 0;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                // فلتر الفترة
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ChoiceChip(
                        label: const Text('هذا الشهر'),
                        selected: _selectedFilter == 0,
                        onSelected: (v) {
                          if (v) setState(() => _selectedFilter = 0);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('آخر 30 يوماً'),
                        selected: _selectedFilter == 1,
                        onSelected: (v) {
                          if (v) setState(() => _selectedFilter = 1);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('جميع الأوقات'),
                        selected: _selectedFilter == 2,
                        onSelected: (v) {
                          if (v) setState(() => _selectedFilter = 2);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // بطاقة سرعة البت الرئيسية (Hero SLA Speed)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .15),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: .2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.speed_rounded,
                              color: Color(0xFF34D399),
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'مؤشر سرعة الاستجابة العام',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'متوسط زمن إنهاء واعتماد الطلبات عبر المنظومة',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatHours(avgHours),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'المتوسط العام للإنجاز',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 36,
                            width: 1,
                            color: Colors.white.withValues(alpha: .15),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatHours(medianHours),
                                  style: const TextStyle(
                                    color: Color(0xFF38BDF8),
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'الوسيط الزمني (أغلب الطلبات)',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // بطاقات العدادات السريعة (4 Metrics Grid)
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'الطلبات المعلقة',
                        value: '$totalPending',
                        subtitle: totalPending > 0
                            ? 'بانتظار دور المعتمِد'
                            : 'لا يوجد تعطل 👏',
                        color: totalPending > 0
                            ? const Color(0xFFD97706)
                            : AppColors.statusSuccess,
                        icon: Icons.hourglass_top_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'القرارات الصادرة',
                        value: '$totalDecisions',
                        subtitle: '$totalApproved معتمد · $totalRejected مرفوض',
                        color: const Color(0xFF0284C7),
                        icon: Icons.verified_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'نسبة الاعتماد',
                        value: '$approvalRate%',
                        subtitle: 'من إجمالي ما تم البت فيه',
                        color: AppColors.statusSuccess,
                        icon: Icons.pie_chart_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        title: 'حالات التصعيد',
                        value: '$totalEscalated',
                        subtitle: 'صُعِّدت تلقائياً لتأخر الرد',
                        color: totalEscalated > 0
                            ? AppColors.statusDanger
                            : const Color(0xFF64748B),
                        icon: Icons.trending_up_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // لوحة تنافس وسرعة المعتمِدين (Leaderboard & Bottleneck Detector)
                Row(
                  children: [
                    const Text(
                      'ترتيب سرعة المعتمِدين وأماكن التعطل',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${approvers.length} معتمدين',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                if (approvers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'لا توجد قرارات مسجلة للمعتمِدين في هذه الفترة.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                else
                  for (var i = 0; i < approvers.length; i++) ...[
                    _ApproverCard(
                      rank: i + 1,
                      item: approvers[i],
                      formatHours: _formatHours,
                      speedTone: _speedTone,
                    ),
                    const SizedBox(height: 10),
                  ],

                const SizedBox(height: 18),

                // توزيع السرعة حسب نوع الطلب
                if (byType.isNotEmpty) ...[
                  const Text(
                    'متوسط سرعة الإنجاز حسب نوع الطلب',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .6),
                      ),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < byType.length; i++) ...[
                          if (i > 0) const Divider(height: 1, indent: 48),
                          _TypeSpeedTile(
                            item: byType[i],
                            formatHours: _formatHours,
                            speedTone: _speedTone,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApproverCard extends StatelessWidget {
  const _ApproverCard({
    required this.rank,
    required this.item,
    required this.formatHours,
    required this.speedTone,
  });

  final int rank;
  final Map<String, dynamic> item;
  final String Function(num) formatHours;
  final (Color, String) Function(num) speedTone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = item['name']?.toString() ?? 'غير محدد';
    final code = item['code']?.toString() ?? '';
    final decisions = (item['total_decisions'] as num?)?.toInt() ?? 0;
    final approved = (item['approved_count'] as num?)?.toInt() ?? 0;
    final rejected = (item['rejected_count'] as num?)?.toInt() ?? 0;
    final avgH = (item['avg_hours'] as num?)?.toDouble() ?? 0.0;
    final pendingCount = (item['pending_count'] as num?)?.toInt() ?? 0;
    final oldestH = (item['oldest_pending_hours'] as num?)?.toDouble() ?? 0.0;
    final (toneColor, toneLabel) = speedTone(avgH);

    final rankBadge = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => '#$rank',
    };

    final hasPendingIssue = pendingCount > 0 && oldestH >= 24;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: hasPendingIssue
              ? AppColors.statusDanger.withValues(alpha: .5)
              : scheme.outlineVariant.withValues(alpha: .6),
          width: hasPendingIssue ? 1.2 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: toneColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    rankBadge,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (code.isNotEmpty)
                        Text(
                          'كود: $code · $decisions قرار منجز',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: toneColor.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatHours(avgH),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          color: toneColor,
                        ),
                      ),
                      Text(
                        toneLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: toneColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // تفاصيل الاعتماد والتأخير
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text(
                    '✅ معتمد: $approved  |  ❌ مرفوض: $rejected',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (pendingCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hasPendingIssue
                            ? AppColors.statusDanger.withValues(alpha: .15)
                            : const Color(0xFFD97706).withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'معلق عنده: $pendingCount طلب (${formatHours(oldestH)})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: hasPendingIssue
                              ? AppColors.statusDanger
                              : const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'لا معلقات عنده 🌿',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.statusSuccess,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // زر تذكير واتساب في حال التعطل
            if (pendingCount > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: const Color(0xFF128C7E),
                  side: const BorderSide(color: Color(0xFF25D366)),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.share_rounded, size: 16),
                label: const Text(
                  'تذكير وتنسيق فوري عبر واتساب 💬',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  final text = '''
السلام عليكم أ/ $name،
تحية طيبة وبعد،
يُرجى التكرم بالاطلاع على الطلبات المعلقة طرفكم في منظومة أحلى شباب:
• عدد الطلبات المعلقة: $pendingCount
• أقدم طلب معلق له: ${formatHours(oldestH)}

نأمل البت فيها لتسهيل مهام الزملاء وسير العمل بالجمعية بكل سلاسة 🌿
https://ahla-shabab-management-os.vercel.app
— الإدارة التنفيذية لجمعية أحلى شباب
'''.trim();
                  WhatsAppShareService.shareText(text);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeSpeedTile extends StatelessWidget {
  const _TypeSpeedTile({
    required this.item,
    required this.formatHours,
    required this.speedTone,
  });

  final Map<String, dynamic> item;
  final String Function(num) formatHours;
  final (Color, String) Function(num) speedTone;

  @override
  Widget build(BuildContext context) {
    final type = item['request_type']?.toString() ?? '';
    final count = (item['decisions_count'] as num?)?.toInt() ?? 0;
    final avgH = (item['avg_hours'] as num?)?.toDouble() ?? 0.0;
    final (toneColor, _) = speedTone(avgH);

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: requestTypeColor(type).withValues(alpha: .15),
        child: Icon(
          requestTypeIcon(type),
          color: requestTypeColor(type),
          size: 17,
        ),
      ),
      title: Text(
        requestTypeLabel(type),
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
      subtitle: Text(
        '$count قرار منجز',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: toneColor.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          formatHours(avgH),
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            color: toneColor,
          ),
        ),
      ),
    );
  }
}
