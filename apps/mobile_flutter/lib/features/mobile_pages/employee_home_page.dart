import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/core/widgets/brand_logo.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/location_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/daily_reports_home_box.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_requests_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_tasks_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_kpi_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_notifications_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_payslips_page.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
import 'package:ahla_shabab_management_os/shared/access_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
      onRefresh: () async {
        ref.invalidate(employeeHomeProvider);
        ref.invalidate(dailyReportsFeedProvider(null));
      },
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
          const _ConnectivitySyncBanner(),
          const _RecognitionSummaryCard(),
          _ProactiveSmartAlertBanner(summary: summary.value, access: access),
          const MobileSectionHeader(
            title: 'اختصارات اليوم',
            subtitle: 'أسرع الإجراءات التي تحتاجها أثناء العمل.',
          ),
          const SizedBox(height: 12),
          // 0455: زر "تنبيه شامل" بارز — يظهر على الشاشة الرئيسية فقط لمن يملك
          // alerts.broadcast.send (HR / المدير التنفيذي) — فلاش/صوت/اهتزاز لكل الموظفين.
          if (access.hasPermission('alerts.broadcast.send')) ...[
            const _BroadcastAlertCard(),
            const SizedBox(height: 12),
          ],
          _QuickAction(
            icon: Icons.location_searching_rounded,
            title: 'طلبات الموقع',
            subtitle: 'موافقة واضحة ومؤقتة',
            badgeCount: summary.value?.pendingLocationRequests,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LocationRequestsPage(access: access),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickAction(
            icon: Icons.receipt_long_rounded,
            title: 'قسائم الرواتب والمستحقات',
            subtitle: 'استعراض قسائم الراتب والمكافآت والبدلات',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MyPayslipsPage(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _QuickAction(
            icon: Icons.calendar_month_rounded,
            title: 'كشف الحضور الشهري',
            subtitle: 'سجل البصمات ومعدل الالتزام والدوام',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MonthlyAttendanceStatementPage(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const DailyReportsHomeBox(),
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
                      builder: (_) => const MobileRequestsPage(),
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
          const _AttendanceSparkline(),
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

/// 0455: بطاقة "تنبيه شامل" بارزة — تُعرض على الشاشة الرئيسية لمن يملك
/// alerts.broadcast.send (HR / المدير التنفيذي). نفس حوار المساحة التنفيذية:
/// نص اختياري ثم send_broadcast_alert (فلاش/صوت/اهتزاز لكل الموظفين).
class _BroadcastAlertCard extends ConsumerWidget {
  const _BroadcastAlertCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: scheme.errorContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: () => _showBroadcastDialog(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.campaign_outlined,
                    color: scheme.onErrorContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تنبيه شامل',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'أرسل تنبيهاً فورياً لكل الموظفين — فلاش وصوت واهتزاز',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer.withValues(alpha: .8),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_left_rounded, color: scheme.onErrorContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showBroadcastDialog(BuildContext context, WidgetRef ref) {
    final commands = ref.read(mobileCommandsProvider);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إرسال تنبيه شامل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سيصل التنبيه فورًا لكامل الموظفين — تومض الشاشة ويُشغَّل فلاش الجهاز والاهتزاز حتى ينتهي التنبيه أو يعطلوه. استخدمه للحالات الطارئة فقط.',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'نص التنبيه (3 أحرف على الأقل)',
                hintText: 'مثال: اجتماع طارئ فورًا في المقر الرئيسي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length < 3) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              commands
                  .sendBroadcastAlert(text)
                  .then((_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('أُرسل التنبيه الشامل لكل الموظفين'),
                      ),
                    );
                  })
                  .catchError((e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('فشل الإرسال: $e')),
                    );
                  });
            },
            child: const Text('إرسال الآن'),
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badgeCount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// 0451: شارة عدد اختيارية (مثل طلبات الموقع المعلقة).
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: scheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (badgeCount != null && badgeCount! > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.chevron_left_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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

/// شريط اتجاه الحضور لآخر 7 أيام — نقاط ملوّنة تعكس الحضور/التأخر/الغياب.
class _AttendanceSparkline extends ConsumerWidget {
  const _AttendanceSparkline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final statement = ref.watch(myMonthlyStatementProvider((now.year, now.month)));
    return statement.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (data) {
        final today = DateTime(now.year, now.month, now.day);
        final last7 = data.days
            .where((d) {
              if (d.isFuture || d.date.isEmpty) return false;
              final dt = DateTime.tryParse(d.date);
              return dt != null && !dt.isAfter(today);
            })
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final visible = last7.length > 7 ? last7.sublist(last7.length - 7) : last7;
        if (visible.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.show_chart_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'اتجاه الحضور — آخر 7 أيام',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: visible.map((d) => _SparkDot(day: d)).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SparkDot extends StatelessWidget {
  const _SparkDot({required this.day});
  final AttendanceStatementDay day;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _dotColor(context, day);
    return Tooltip(
      message: '${day.dayNameAr}: $label',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            child: Center(
              child: Text(
                (DateTime.tryParse(day.date)?.day ?? '?').toString(),
                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            day.dayNameAr.isNotEmpty ? day.dayNameAr[0] : '',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  static (Color, String) _dotColor(BuildContext context, AttendanceStatementDay day) {
    if (day.isOfficialHoliday || day.dayNameAr == 'الجمعة' || day.dayNameAr == 'السبت') {
      return (Colors.grey.shade400, 'إجازة');
    }
    if (day.hasLeave) return (Colors.blue.shade400, 'إجازة');
    if (day.hasMission) return (const Color(0xFF0EA5E9), 'مأمورية');
    if (day.hasConvoyFundi) return (const Color(0xFF8B5CF6), 'قافلة/فاندي');
    if (day.isAbsent) return (Colors.red.shade400, 'غياب');
    if (day.lateMinutes > 0) return (Colors.orange.shade400, 'تأخر ${day.lateMinutes} د');
    if (day.isCompleted) return (Colors.green.shade500, 'حضور كامل');
    return (Colors.grey.shade300, 'غير مسجل');
  }
}

class _ConnectivitySyncBanner extends ConsumerWidget {
  const _ConnectivitySyncBanner();

  void _showSyncDetailsBottomSheet(BuildContext context, WidgetRef ref, bool isOffline) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _SyncDetailsSheet(isOffline: isOffline),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityProvider);
    final isOffline = connectivity == ConnectivityState.offline ||
        connectivity == ConnectivityState.reconnecting;

    final primaryColor = isOffline ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final icon = isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded;
    final text = isOffline
        ? 'وضع عدم الاتصال نشط · البصمات تحفظ محلياً وسترفع فور عودة الشبكة (اضغط للتفاصيل)'
        : 'متصل بالخادم · البصمات والمزامنة آمنة ومحدثة (اضغط للتفاصيل)';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: isOffline ? .1 : .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withValues(alpha: isOffline ? .3 : .24),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSyncDetailsBottomSheet(context, ref, isOffline),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: isOffline ? 10 : 8),
            child: Row(
              children: [
                Icon(icon, size: isOffline ? 20 : 16, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isOffline ? const Color(0xFFB45309) : const Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: isOffline ? const Color(0xFFB45309) : const Color(0xFF10B981),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncDetailsSheet extends ConsumerStatefulWidget {
  const _SyncDetailsSheet({required this.isOffline});
  final bool isOffline;

  @override
  ConsumerState<_SyncDetailsSheet> createState() => _SyncDetailsSheetState();
}

class _SyncDetailsSheetState extends ConsumerState<_SyncDetailsSheet> {
  bool _isSyncing = false;
  List<SyncQueueItem> _items = [];
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadSyncInfo();
  }

  Future<void> _loadSyncInfo() async {
    final items = await OfflineSyncQueue.instance.getAll();
    final lastSync = await OfflineSyncQueue.instance.lastSyncTime;
    if (mounted) {
      setState(() {
        _items = items;
        _lastSync = lastSync;
      });
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isSyncing = true);
    try {
      final client = Supabase.instance.client;
      final syncedCount = await OfflineSyncQueue.instance.processQueue(client);
      ref.invalidate(employeeHomeProvider);
      await _loadSyncInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              syncedCount > 0
                  ? 'تمت مزامنة $syncedCount عملية بنجاح مع الخادم.'
                  : 'تم التحقق من المزامنة — لا توجد عمليات معلقة.',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر الاتصال بالخادم لمزامنة البيانات حالياً.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = widget.isOffline ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.isOffline ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                  color: statusColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حالة الاتصال ومزامنة البصمات',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    Text(
                      widget.isOffline ? 'وضع بدون اتصال (Offline)' : 'متصل بالخادم سحابياً',
                      style: TextStyle(
                        fontSize: 12,
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('العمليات المعلقة في الطابور:', style: TextStyle(fontSize: 12)),
                    Text(
                      '${_items.length} عملية',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: _items.isEmpty ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('آخر مزامنة ناجحة:', style: TextStyle(fontSize: 12)),
                    Text(
                      _lastSync != null
                          ? DateFormat('HH:mm  yyyy/MM/dd').format(_lastSync!.toLocal())
                          : 'لم تسجل بعد',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'العمليات بانتظار الإرسال:',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 140),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 4),
                itemBuilder: (context, idx) {
                  final item = _items[idx];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(item.actionLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        Text(
                          'محاولات: ${item.retryCount}',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _isSyncing ? null : _triggerManualSync,
            icon: _isSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(_isSyncing ? 'جاري المزامنة...' : 'مزامنة يدوية فورية الآن'),
          ),
        ],
      ),
    );
  }
}

class _RecognitionSummaryCard extends StatelessWidget {
  const _RecognitionSummaryCard();

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _RecognitionDetailsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: .28),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'أوسمة التميز والتحفيز',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                          Spacer(),
                          Text(
                            '⭐ 150 نقطة',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'درع الالتزام التام · وسام دقة المواعيد',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ],
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

class _RecognitionDetailsSheet extends StatelessWidget {
  const _RecognitionDetailsSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: Color(0xFFF59E0B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'أوسمة التميز والتقدير الوظيفي',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'سجل نقاط التحفيز والإنجاز المؤسسي',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // بطاقة الرتبة الحالية
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFF59E0B).withValues(alpha: .15),
                      const Color(0xFFD97706).withValues(alpha: .05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Text(
                          '🥈 الرتبة الحالية: الفضي (Silver)',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        Spacer(),
                        Text(
                          '150 / 250 نقطة',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFD97706),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: 150 / 250,
                        minHeight: 8,
                        backgroundColor: scheme.outlineVariant.withValues(alpha: .3),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'المستوى التالي: الذهبي 🥇',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'متبقي 100 نقطة للترقية',
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'الأوسمة المستحقة الممنوحة لك:',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildBadgeItem(
                context,
                icon: '🏆',
                title: 'درع الالتزام والانضباط التام',
                description: 'حضور كامل خلال الشهر بدون أي تأخيرات أو انقطاع غير مبرر.',
                points: '+50 نقطة',
              ),
              _buildBadgeItem(
                context,
                icon: '⚡',
                title: 'وسام سرعة الاستجابة الميدانية',
                description: 'إنجاز كافة المهام والمأموريات الموكلة في الموعد المحدد وبدقة.',
                points: '+40 نقطة',
              ),
              _buildBadgeItem(
                context,
                icon: '🤝',
                title: 'وسام روح الفريق والمبادرة',
                description: 'مشاركة فعالة ومتميزة في إسناد زملاء العمل بالمقر والمواقع.',
                points: '+35 نقطة',
              ),
              _buildBadgeItem(
                context,
                icon: '🛡️',
                title: 'وسام الاستقرار والانتماء المؤسسي',
                description: 'إتمام أكثر من عام من العطاء والخدمة المستمرة بتفانٍ وإخلاص.',
                points: '+25 نقطة',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tips_and_updates_outlined, size: 20, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'نصيحة: حافظ على تسجيل البصمة في موعدها وأكمل مهامك اليومية لكسب نقاط إضافية والترقية للرتبة الذهبية.',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildBadgeItem(
    BuildContext context, {
    required String icon,
    required String title,
    required String description,
    required String points,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                    Text(
                      points,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProactiveSmartAlertBanner extends StatelessWidget {
  const _ProactiveSmartAlertBanner({
    required this.summary,
    required this.access,
  });

  final EmployeeHomeSummary? summary;
  final AccessContext access;

  @override
  Widget build(BuildContext context) {
    if (summary == null) return const SizedBox.shrink();

    final pendingLoc = summary!.pendingLocationRequests;
    final pendingReq = summary!.pendingRequests;
    final unreadAnnouncements = summary!.unreadOfficial;

    // حالة عدم وجود طلبات معلقة: نصيحة ذكية محفزة
    if (pendingLoc == 0 && pendingReq == 0 && unreadAnnouncements == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '💡 نصيحة اليوم: سجل حضورك وانصرافك في الموعد المحدد للحفاظ على رصيد نقاط تميزك ونيل درع الانضباط!',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                      ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // تنبيه استباقي: طلبات موقع معلقة تحتاج استجابة
    if (pendingLoc > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LocationRequestsPage(access: access),
              ),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.location_searching_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تنبيه استباقي: لديك طلب موقع بانتظار استجابتك',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'انقر هنا للموافقة المؤقتة ومشاركة موقعك الميداني مع الإدارة.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.amber),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // تنبيه بالقرارات أو الإعلانات الرسمية غير المقروءة
    if (unreadAnnouncements > 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MobileNotificationsPage(),
              ),
            ),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'إعلانات وقرارات إدارية جديدة ($unreadAnnouncements)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'يرجى الاطلاع على القرارات الإدارية وتحديثات سياسات العمل.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // تنبيه بالطلبات قيد المراجعة
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const MobileRequestsPage(),
            ),
          ),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    size: 18,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'لديك $pendingReq طلبات إجازة/خدمات قيد المراجعة',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'انقر لمتابعة حالة الاعتماد وتحديثات الإدارة.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                              fontSize: 11,
                            ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.blue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


