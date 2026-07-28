import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_team_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ManagerHomePage extends ConsumerWidget {
  const ManagerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(managerDashboardProvider);
    final profile = ref.watch(mobileProfileProvider);
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(managerDashboardProvider);
        ref.invalidate(mobileTeamProvider);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: scheme.primaryContainer,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                profile.whenOrNull(
                  data: (p) => AppAvatar(
                    name: p.fullNameAr,
                    photoUrl: p.photoUrl,
                    radius: 26,
                  ),
                ) ?? Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.groups_rounded, color: scheme.onPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'صورة فريقك اليوم',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'تابع الحضور والطلبات والتقييمات دون تجاوز نطاقك الإداري.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: .75,
                          ),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'المؤشرات الرئيسية',
            subtitle: 'أهم ما يحتاج انتباهك داخل الفريق.',
          ),
          const SizedBox(height: 12),
          data.when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator(semanticsLabel: 'جاري التحميل')),
              ),
            ),
            error: (error, stackTrace) => Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded),
                    const SizedBox(height: 8),
                    const Text(
                      'تعذر تحميل بيانات الفريق',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(managerDashboardProvider),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
            data: (item) => MetricGrid(
              cards: [
                (
                  'أعضاء الفريق',
                  item.teamMembers.toString(),
                  Icons.groups_rounded,
                  null,
                ),
                (
                  'طلبات تنتظرني',
                  item.pendingRequests.toString(),
                  Icons.approval_rounded,
                  null,
                ),
                (
                  'تقييمات معلقة',
                  item.pendingKpi.toString(),
                  Icons.rate_review_rounded,
                  null,
                ),
                (
                  'تأخيرات اليوم',
                  item.lateToday.toString(),
                  Icons.schedule_rounded,
                  null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'حضور الفريق اليوم',
            subtitle: 'توزيع حالات الحضور لأعضاء فريقك.',
          ),
          const SizedBox(height: 12),
          ref.watch(mobileTeamProvider).when(
            loading: () => const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: CircularProgressIndicator.adaptive(semanticsLabel: 'جاري التحميل'),
                ),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
            data: (members) => _TeamAttendanceCard(members: members),
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'إجراءات المدير',
            subtitle: 'ابدأ من العناصر الأعلى تأثيرًا على الفريق.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.groups_outlined, color: scheme.primary),
                  ),
                  title: const Text(
                    'ملفات أعضاء الفريق',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: const Text('الحضور والطلبات والتقييمات ضمن نطاقك.'),
                  trailing: const Icon(
                    Icons.chevron_left_rounded,
                    semanticLabel: 'فتح ملفات أعضاء الفريق',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          title: const Text('أعضاء فريقي'),
                          actions: const [
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Center(child: BrandLogoMark(size: 34)),
                            ),
                          ],
                        ),
                        body: const MobileTeamPage(),
                      ),
                    ),
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                const ListTile(
                  contentPadding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text(
                    'الموافقات والتقييمات',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'استخدم التبويبات السفلية للانتقال إلى العناصر المعلقة.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: scheme.secondaryContainer.withValues(alpha: .7),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, color: scheme.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'كل رقم وملف هنا يمر عبر RLS ونطاق المدير الحقيقي؛ إخفاء الشاشة وحده ليس هو الحماية.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamAttendanceCard extends StatelessWidget {
  const _TeamAttendanceCard({required this.members});
  final List<MobileTeamMember> members;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final m in members) {
      var status = m.attendanceStatus ?? 'absent';
      if (status == 'leave') status = 'on_leave';
      counts[status] = (counts[status] ?? 0) + 1;
    }

    final order = <(String, String, Color)>[
      ('present', 'حاضر', AppColors.statusSuccess),
      ('late', 'متأخر', AppColors.statusWarning),
      ('mission', 'مهمة', AppColors.statusViolet),
      ('on_leave', 'إجازة', AppColors.statusInfo),
      ('absent', 'غائب', AppColors.statusDanger),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (key, label, color) in order)
              _CountChip(label: label, count: counts[key] ?? 0, color: color),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 14,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: color,
          ),
        ),
      ],
    ),
  );
}
