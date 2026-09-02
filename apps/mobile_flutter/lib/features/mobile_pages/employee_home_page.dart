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
