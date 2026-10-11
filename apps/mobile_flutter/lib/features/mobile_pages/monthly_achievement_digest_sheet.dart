import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

const List<String> _arabicMonths = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

/// فتح نافذة تجميع ومُلخص الإنجاز الشهري الذكي
Future<void> showMonthlyAchievementDigestSheet(
  BuildContext context, {
  String? employeeId,
  String? employeeName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => MonthlyAchievementDigestSheet(
      employeeId: employeeId,
      employeeName: employeeName,
    ),
  );
}

class MonthlyAchievementDigestSheet extends ConsumerStatefulWidget {
  const MonthlyAchievementDigestSheet({
    this.employeeId,
    this.employeeName,
    super.key,
  });

  final String? employeeId;
  final String? employeeName;

  @override
  ConsumerState<MonthlyAchievementDigestSheet> createState() =>
      _MonthlyAchievementDigestSheetState();
}

class _MonthlyAchievementDigestSheetState
    extends ConsumerState<MonthlyAchievementDigestSheet> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
  }

  void _prevMonth() {
    setState(() {
      if (_selectedMonth == 1) {
        _selectedMonth = 12;
        _selectedYear--;
      } else {
        _selectedMonth--;
      }
    });
  }

  void _nextMonth() {
    setState(() {
      if (_selectedMonth == 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
  }

  String get _monthName => _arabicMonths[_selectedMonth - 1];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final reportsAsync = ref.watch(mobileDailyReportsProvider(widget.employeeId));
    final profileAsync = ref.watch(mobileProfileProvider);

    final resolvedEmployeeName = widget.employeeName ??
        profileAsync.asData?.value.fullNameAr ??
        'الموظف';
    final resolvedDepartment = profileAsync.asData?.value.department;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // مقبض السحب
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // الرأس
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.success,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'مُولّد ملخص الإنجاز الشهري',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'تجميع ذكي لمنجزات $resolvedEmployeeName',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // محدد الشهر والسنة
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'الشهر التالي',
                    onPressed: _nextMonth,
                  ),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_monthName $_selectedYear',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'الشهر السابق',
                    onPressed: _prevMonth,
                  ),
                ],
              ),
            ),

            // المحتوى الرئيسي
            Expanded(
              child: reportsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('تعذر تحميل التقارير: $err'),
                  ),
                ),
                data: (allReports) {
                  // فلترة الشهر المختار
                  final monthReports = allReports
                      .where((r) =>
                          r.reportDate.year == _selectedYear &&
                          r.reportDate.month == _selectedMonth)
                      .toList()
                    ..sort((a, b) => b.reportDate.compareTo(a.reportDate));

                  // استخلاص الإنجازات والمعوقات
                  final achievements = <Map<String, String>>[];
                  final blockers = <Map<String, String>>[];
                  final managerNotes = <Map<String, String>>[];

                  final df = DateFormat('yyyy-MM-dd', 'ar');

                  for (final rep in monthReports) {
                    final dateStr = df.format(rep.reportDate);
                    if (rep.achievements != null && rep.achievements!.trim().isNotEmpty) {
                      final lines = rep.achievements!
                          .split('\n')
                          .map((l) => l.trim())
                          .where((l) => l.length > 2);
                      for (final line in lines) {
                        achievements.add({'date': dateStr, 'text': line});
                      }
                    }
                    if (rep.blockers != null &&
                        rep.blockers!.trim().isNotEmpty &&
                        !['لا يوجد', 'لا توجد', 'لا', 'none', '-'].contains(rep.blockers!.trim())) {
                      blockers.add({'date': dateStr, 'text': rep.blockers!.trim()});
                    }
                    if (rep.managerComment != null && rep.managerComment!.trim().isNotEmpty) {
                      managerNotes.add({
                        'date': dateStr,
                        'text': rep.managerComment!.trim(),
                        'reviewer': rep.reviewerName ?? 'الإدارة',
                      });
                    }
                  }

                  if (monthReports.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_note_rounded,
                              size: 56,
                              color: isDark ? Colors.white24 : Colors.black26,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد تقارير يومية مسجلة في $_monthName $_selectedYear',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'يمكنك تغيير الشهر من الأعلى أو تدوين تقارير العمل بانتظام لتوثيق منجزاتك.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      // بطاقات الإحصائيات الأربعة
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              label: 'أيام التوثيق',
                              value: '${monthReports.length} يوماً',
                              icon: Icons.calendar_today_rounded,
                              color: AppColors.success,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              label: 'إجمالي المهام',
                              value: '${achievements.length} إنجازاً',
                              icon: Icons.trending_up_rounded,
                              color: AppColors.brandPrimary,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              label: 'معوقات عولجت',
                              value: '${blockers.length}',
                              icon: Icons.shield_rounded,
                              color: AppColors.warning,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              label: 'توجيهات الإدارة',
                              value: '${managerNotes.length}',
                              icon: Icons.military_tech_rounded,
                              color: Colors.purpleAccent,
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // سجل الإنجازات المجمعة
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'سجل الإنجازات المجمعة (${achievements.length} مهمة)',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      ...achievements.map((ach) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? Colors.white12 : Colors.black12,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    ach['date'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.success,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ach['text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),

                      if (blockers.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'المعوقات المعالجة (${blockers.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: AppColors.warning,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...blockers.map((b) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.warning.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b['date'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    b['text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],

                      if (managerNotes.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            const Icon(
                              Icons.military_tech_rounded,
                              size: 18,
                              color: Colors.purpleAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'توجيهات وملاحظات الإدارة (${managerNotes.length})',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: Colors.purpleAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...managerNotes.map((m) => Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.purple.withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'بواسطة: ${m['reviewer']}',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.purpleAccent,
                                        ),
                                      ),
                                      Text(
                                        m['date'] ?? '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m['text'] ?? '',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  );
                },
              ),
            ),

            // شريط الإجراءات السفلي الثابت
            reportsAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (allReports) {
                final monthReports = allReports
                    .where((r) =>
                        r.reportDate.year == _selectedYear &&
                        r.reportDate.month == _selectedMonth)
                    .toList();
                if (monthReports.isEmpty) return const SizedBox.shrink();

                final topAchs = <String>[];
                for (final r in monthReports) {
                  if (r.achievements != null && r.achievements!.trim().isNotEmpty) {
                    final lines = r.achievements!
                        .split('\n')
                        .map((l) => l.trim())
                        .where((l) => l.length > 2);
                    topAchs.addAll(lines);
                  }
                }

                return SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      border: Border(
                        top: BorderSide(
                          color: isDark ? Colors.white12 : Colors.black12,
                        ),
                      ),
                    ),
                  child: Row(
                    children: [
                      // زر المشاركة عبر واتساب
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.share_rounded, size: 18),
                          label: const Text(
                            'مشاركة واتساب',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          onPressed: () {
                            WhatsAppShareService.shareMonthlyAchievementReport(
                              employeeName: resolvedEmployeeName,
                              monthName: _monthName,
                              year: _selectedYear,
                              reportedDays: monthReports.length,
                              achievementsCount: topAchs.length,
                              topAchievements: topAchs,
                              department: resolvedDepartment,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // زر نسخ التقرير
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text(
                          'نسخ التقرير',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () async {
                          final buffer = StringBuffer();
                          buffer.writeln(
                              '📋 تقرير إنجازات شهر ($_monthName $_selectedYear)');
                          buffer.writeln('الموظف: $resolvedEmployeeName');
                          if (resolvedDepartment != null) {
                            buffer.writeln('القسم: $resolvedDepartment');
                          }
                          buffer.writeln('───────────────');
                          buffer.writeln(
                              '• أيام العمل الموثقة: ${monthReports.length} يوماً');
                          buffer.writeln(
                              '• إجمالي المنجزات: ${topAchs.length} إنجازاً');
                          buffer.writeln('───────────────');
                          buffer.writeln('أبرز الإنجازات:');
                          for (var i = 0;
                              i < topAchs.length && i < 15;
                              i++) {
                            buffer.writeln('${i + 1}) ${topAchs[i]}');
                          }
                          await Clipboard.setData(
                              ClipboardData(text: buffer.toString()));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'تم نسخ تقرير الإنجاز الشهري بنجاح للحافظة!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
