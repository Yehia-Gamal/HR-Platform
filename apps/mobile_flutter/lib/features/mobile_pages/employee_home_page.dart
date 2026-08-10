import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_feed_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class EmployeeHomePage extends ConsumerWidget {
  const EmployeeHomePage({required this.access, super.key});
  final AccessContext access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(employeeHomeProvider);
    final profile = ref.watch(mobileProfileProvider);
    final scheme = Theme.of(context).colorScheme;
    final date = DateFormat('EEEE، d MMMM', 'ar_EG').format(DateTime.now());

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(employeeHomeProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color.lerp(scheme.primary, Colors.black, .25)!,
                  scheme.primary,
                  scheme.secondary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: .22),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        date,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .9),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const BrandLogoMark(inverse: true, size: 40),
                    const SizedBox(width: 8),
                    profile.whenOrNull(
                      data: (p) => AppAvatar(
                        name: p.fullNameAr,
                        photoUrl: p.photoUrl,
                        radius: 20,
                      ),
                    ) ?? ExcludeSemantics(
                      child: Icon(
                        Icons.wb_sunny_outlined,
                        color: Colors.white.withValues(alpha: .8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'جاهز ليوم جديد؟',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'راجع حضورك ومهامك والطلبات التي تحتاج متابعتك.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .8),
                    height: 1.5,
                  ),
                ),
                if (access.attendancePolicy.selfPunchEnabled) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: scheme.primary,
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MobileAttendancePage(),
                      ),
                    ),
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('تسجيل الحضور أو الانصراف'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'اختصارات اليوم',
            subtitle: 'أسرع الإجراءات التي تحتاجها أثناء العمل.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickAction(
                  icon: Icons.location_searching_rounded,
                  title: 'طلبات الموقع',
                  subtitle: 'موافقة واضحة ومؤقتة',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationRequestsPage(access: access),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickAction(
                  icon: Icons.newspaper_rounded,
                  title: 'تقارير الجميع',
                  subtitle: 'أضف تقريرك واطّلع على تقارير الفريق',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DailyReportsFeedPage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const MobileSectionHeader(
            title: 'ملخص حسابك',
            subtitle: 'الأرقام التالية محدثة من الخادم حسب نطاقك.',
          ),
          const SizedBox(height: 12),
          summary.when(
            loading: () => const _LoadingSummary(),
            error: (error, _) => _ErrorCard(
              message: 'تعذر تحميل الملخص. تحقق من الاتصال وأعد المحاولة.',
              onRetry: () => ref.invalidate(employeeHomeProvider),
            ),
            data: (data) => MetricGrid(
              cards: [
                (
                  'طلبات معلقة',
                  data.pendingRequests.toString(),
                  Icons.description_outlined,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileRequestsPage(allowDecision: false),
                    ),
                  ),
                ),
                (
                  'مهام نشطة',
                  data.activeTasks.toString(),
                  Icons.task_alt_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileTasksPage(),
                    ),
                  ),
                ),
                (
                  'مرحلة التقييم', 
                  _stage(data.kpiStage), 
                  Icons.speed_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MobileKpiPage(access: access, employeeOnly: true),
                    ),
                  ),
                ),
                (
                  'غير مقروء',
                  (data.unreadOfficial + data.unreadNotifications).toString(),
                  Icons.notifications_active_outlined,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MobileNotificationsPage(),
                    ),
                  ),
                ),
                (
                  'طلبات موقع',
                  data.pendingLocationRequests.toString(),
                  Icons.location_searching_rounded,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LocationRequestsPage(access: access),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            color: scheme.secondaryContainer.withValues(alpha: .55),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.secondary.withValues(alpha: .12),
                    child: Icon(
                      Icons.verified_user_outlined,
                      color: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'خصوصيتك جزء من التصميم',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'الموقع لا يُطلب إلا بسبب ومدة محددين، وتظهر لك الجلسة بوضوح قبل الموافقة.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                        ),
                      ],
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

  String _stage(String? value) => switch (value) {
    'self' => 'ذاتي',
    'hr_review' => 'مراجعة HR',
    'manager_review' => 'مراجعة المدير',
    'parallel_review' => 'متوازية',
    'secretary_review' => 'السكرتير',
    'executive_review' => 'التنفيذي',
    'finalized' => 'في التقرير',
    'closed' => 'مغلق',
    'archived' => 'مؤرشف',
    _ => '—',
  };
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
  );
}

class _LoadingSummary extends StatelessWidget {
  const _LoadingSummary();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Semantics(
          label: 'جاري التحميل',
          child: const CircularProgressIndicator(),
        ),
      ),
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
          Text(
            'تعذر تحميل ملخص حسابك',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    ),
  );
}
