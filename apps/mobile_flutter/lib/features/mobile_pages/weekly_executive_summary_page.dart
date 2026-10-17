import 'package:ahla_shabab_management_os/core/sharing/whatsapp_share_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/app_avatar.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/admin_attendance_day_edit_sheet.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/employee_profile_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/my_instant_penalties_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/org_chart_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/people_hub_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// بيانات إحصائية ملخصة عن موظف في التقرير الأسبوعي
class WeeklyEmployeeStat {
  const WeeklyEmployeeStat({
    required this.employeeName,
    this.employeeId,
    this.count = 0,
    this.totalMinutes = 0,
  });

  final String employeeName;
  final String? employeeId;
  final int count;
  final int totalMinutes;
}

/// نموذج موحد لبيانات الملخص الأسبوعي للحضور التنفيذي
class WeeklyExecutiveSummaryData {
  const WeeklyExecutiveSummaryData({
    required this.startDateText,
    required this.endDateText,
    required this.periodLabel,
    required this.presentCount,
    required this.lateCount,
    required this.absentCount,
    required this.onLeaveCount,
    required this.presentRate,
    required this.lateRate,
    required this.absentRate,
    required this.totalLateMinutes,
    required this.totalEarlyLeaveMinutes,
    required this.totalOvertimeMinutes,
    required this.activeEmployees,
    required this.topLateEmployees,
    required this.absentGt3Employees,
    required this.rawBody,
  });

  final String startDateText;
  final String endDateText;
  final String periodLabel;
  final int presentCount;
  final int lateCount;
  final int absentCount;
  final int onLeaveCount;
  final double presentRate;
  final double lateRate;
  final double absentRate;
  final int totalLateMinutes;
  final int totalEarlyLeaveMinutes;
  final int totalOvertimeMinutes;
  final int activeEmployees;
  final List<WeeklyEmployeeStat> topLateEmployees;
  final List<WeeklyEmployeeStat> absentGt3Employees;
  final String rawBody;

  /// تحليل ذكي من كائن الإشعار (سواء من metadata المنظمة أو body النصي)
  factory WeeklyExecutiveSummaryData.fromNotification(
    MobileNotificationItem item,
  ) {
    return WeeklyExecutiveSummaryData.fromMetadataAndBody(
      metadata: item.metadata,
      body: item.body ?? '',
    );
  }

  factory WeeklyExecutiveSummaryData.fromMetadataAndBody({
    required Map<String, dynamic> metadata,
    required String body,
  }) {
    final summary = metadata['summary'] is Map
        ? Map<String, dynamic>.from(metadata['summary'] as Map)
        : const <String, dynamic>{};

    // 1) استخراج التواريخ
    String start = (metadata['startDate'] ?? summary['startDate']) as String? ?? '';
    String end = (metadata['endDate'] ?? summary['endDate']) as String? ?? '';

    // إذا كانت غير موجودة في metadata، نستخرجها من نص body: (04/10/2026 - 10/10/2026)
    if (start.isEmpty || end.isEmpty) {
      final dateMatch = RegExp(r'\(([0-9/.\-]+)\s*[-–]\s*([0-9/.\-]+)\)').firstMatch(body);
      if (dateMatch != null) {
        start = dateMatch.group(1) ?? '';
        end = dateMatch.group(2) ?? '';
      }
    }

    // 2) استخراج أرقام الحضور والغياب والتأخر
    int present = _asInt(summary['present']);
    int late = _asInt(summary['late']);
    int absent = _asInt(summary['absent']);
    int onLeave = _asInt(summary['onLeave']);

    // استخراج بديل من النص إن كانت القيم صفرية وغير موجودة بـ metadata
    if (summary.isEmpty && body.isNotEmpty) {
      final pMatch = RegExp(r'حضور\s+(\d+)').firstMatch(body);
      if (pMatch != null) present = int.tryParse(pMatch.group(1) ?? '') ?? present;

      final lMatch = RegExp(r'تأخر\s+(\d+)').firstMatch(body);
      if (lMatch != null) late = int.tryParse(lMatch.group(1) ?? '') ?? late;

      final aMatch = RegExp(r'غياب\s+(\d+)').firstMatch(body);
      if (aMatch != null) absent = int.tryParse(aMatch.group(1) ?? '') ?? absent;

      final olMatch = RegExp(r'إجازة\s+(\d+)').firstMatch(body);
      if (olMatch != null) onLeave = int.tryParse(olMatch.group(1) ?? '') ?? onLeave;
    }

    // 3) استخراج النسب
    double lateR = _asDouble(summary['lateRate']);
    double absentR = _asDouble(summary['absentRate']);
    double presentR = _asDouble(summary['presentRate']);

    if (summary.isEmpty && body.isNotEmpty) {
      final lrMatch = RegExp(r'نسبة التأخر\s+([\d.]+)%').firstMatch(body);
      if (lrMatch != null) lateR = double.tryParse(lrMatch.group(1) ?? '') ?? lateR;

      final arMatch = RegExp(r'نسبة الغياب\s+([\d.]+)%').firstMatch(body);
      if (arMatch != null) absentR = double.tryParse(arMatch.group(1) ?? '') ?? absentR;
    }

    final totalWorkdays = present + late + absent;
    if (presentR <= 0 && totalWorkdays > 0) {
      presentR = (present / totalWorkdays) * 100;
    }
    if (lateR <= 0 && totalWorkdays > 0) {
      lateR = (late / totalWorkdays) * 100;
    }
    if (absentR <= 0 && totalWorkdays > 0) {
      absentR = (absent / totalWorkdays) * 100;
    }

    // 4) أعلى المتأخرين
    final topLateList = <WeeklyEmployeeStat>[];
    if (metadata['topLateEmployees'] is List) {
      for (final raw in metadata['topLateEmployees'] as List) {
        if (raw is Map) {
          topLateList.add(
            WeeklyEmployeeStat(
              employeeName: (raw['employeeName'] ?? raw['name'] ?? 'موظف') as String,
              employeeId: raw['employeeId'] as String?,
              count: _asInt(raw['lateCount'] ?? raw['count']),
              totalMinutes: _asInt(raw['totalMinutes'] ?? raw['lateMinutes'] ?? raw['totalLateMinutes']),
            ),
          );
        }
      }
    }
    // احتياطي نصي إن لم يتوفر JSON
    if (topLateList.isEmpty && body.isNotEmpty) {
      final topLateMatch = RegExp(r'أعلى المتأخرين:\s*([^.;]+)').firstMatch(body);
      if (topLateMatch != null) {
        final rawNames = topLateMatch.group(1)?.trim() ?? '';
        if (rawNames.isNotEmpty && rawNames != 'لا يوجد') {
          for (final name in rawNames.split(RegExp(r'[،,]'))) {
            final trimmed = name.trim();
            if (trimmed.isNotEmpty) {
              topLateList.add(WeeklyEmployeeStat(employeeName: trimmed));
            }
          }
        }
      }
    }

    // 5) أكثر من 3 غيابات
    final topAbsentList = <WeeklyEmployeeStat>[];
    if (metadata['absentGt3Employees'] is List) {
      for (final raw in metadata['absentGt3Employees'] as List) {
        if (raw is Map) {
          topAbsentList.add(
            WeeklyEmployeeStat(
              employeeName: (raw['employeeName'] ?? raw['name'] ?? 'موظف') as String,
              employeeId: raw['employeeId'] as String?,
              count: _asInt(raw['absentCount'] ?? raw['count']),
            ),
          );
        }
      }
    }

    return WeeklyExecutiveSummaryData(
      startDateText: start.isNotEmpty ? start : '—',
      endDateText: end.isNotEmpty ? end : '—',
      periodLabel: (start.isNotEmpty && end.isNotEmpty)
          ? 'الفترة من $start إلى $end'
          : 'الأسبوع الأخير',
      presentCount: present,
      lateCount: late,
      absentCount: absent,
      onLeaveCount: onLeave,
      presentRate: double.parse(presentR.toStringAsFixed(1)),
      lateRate: double.parse(lateR.toStringAsFixed(1)),
      absentRate: double.parse(absentR.toStringAsFixed(1)),
      totalLateMinutes: _asInt(summary['totalLateMinutes']),
      totalEarlyLeaveMinutes: _asInt(summary['totalEarlyLeaveMinutes']),
      totalOvertimeMinutes: _asInt(summary['totalOvertimeMinutes']),
      activeEmployees: _asInt(summary['activeEmployees']),
      topLateEmployees: topLateList,
      absentGt3Employees: topAbsentList,
      rawBody: body,
    );
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}

/// صفحة عرض الملخص الأسبوعي للحضور التنفيذي
class WeeklyExecutiveSummaryPage extends ConsumerWidget {
  const WeeklyExecutiveSummaryPage({
    this.item,
    this.periodId,
    this.startDate,
    this.endDate,
    super.key,
  });

  final MobileNotificationItem? item;
  final String? periodId;
  final String? startDate;
  final String? endDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // محاولة إيجاد الإشعار من مزوّد الإشعارات إن لم يُمرَّر كائن item مباشرة
    final notificationsAsync = ref.watch(myNotificationsProvider);
    final allNotifications = notificationsAsync.value ?? const <MobileNotificationItem>[];

    MobileNotificationItem? resolvedItem = item;
    if (resolvedItem == null && allNotifications.isNotEmpty) {
      resolvedItem = allNotifications.cast<MobileNotificationItem?>().firstWhere(
        (n) {
          if (n == null) return false;
          if (periodId != null && n.meta('periodId') == periodId) return true;
          if (startDate != null && n.meta('startDate') == startDate) return true;
          return n.canonicalType == 'weekly_executive_summary' ||
              n.entityType == 'weekly_executive_summary' ||
              n.title.contains('الملخص الأسبوعي');
        },
        orElse: () => null,
      );
    }

    final data = resolvedItem != null
        ? WeeklyExecutiveSummaryData.fromNotification(resolvedItem)
        : WeeklyExecutiveSummaryData.fromMetadataAndBody(
            metadata: {
              if (startDate != null) 'startDate': startDate,
              if (endDate != null) 'endDate': endDate,
              if (periodId != null) 'periodId': periodId,
            },
            body: '',
          );

    final access = ref.watch(accessContextProvider).value;
    final isHrAdmin = access?.canAdminEditAttendanceDays ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'الملخص الأسبوعي للحضور',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (isHrAdmin)
            IconButton(
              tooltip: 'تعديل دوام موظف / إضافة راحة',
              icon: const Icon(Icons.edit_calendar_rounded),
              onPressed: () => _openEmployeePickerAndEdit(context, ref, data),
            ),
          IconButton(
            tooltip: 'مشاركة الملخص',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareSummary(context, data),
          ),
          IconButton(
            tooltip: 'نسخ التقرير',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copySummary(context, data),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(myNotificationsProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1) بطاقة العنوان والمدة الزمنية
                _buildHeaderCard(
                  context,
                  data,
                  isHrAdmin: isHrAdmin,
                  onOpenPicker: () =>
                      _openEmployeePickerAndEdit(context, ref, data),
                ),
                const SizedBox(height: 16),

                // 2) شبكة المؤشرات الأساسية (حضور - تأخير - غياب - إجازات)
                _buildMetricsGrid(context, data),
                const SizedBox(height: 16),

                // 3) تفاصيل إضافية (ساعات التأخير والإضافي) إن وُجدت
                if (data.totalLateMinutes > 0 ||
                    data.totalOvertimeMinutes > 0 ||
                    data.totalEarlyLeaveMinutes > 0 ||
                    data.activeEmployees > 0) ...[
                  _buildAdditionalStatsRow(context, data),
                  const SizedBox(height: 16),
                ],

                // 4) قائمة أعلى الموظفين تأخراً
                if (data.topLateEmployees.isNotEmpty) ...[
                  _buildTopLateSection(context, ref, data, isHrAdmin: isHrAdmin),
                  const SizedBox(height: 16),
                ],

                // 5) قائمة الموظفين الأكثر غياباً (> 3 أيام)
                if (data.absentGt3Employees.isNotEmpty) ...[
                  _buildTopAbsentSection(context, ref, data, isHrAdmin: isHrAdmin),
                  const SizedBox(height: 16),
                ],

                // 6) نص الإشعار والتقرير الصادر من النظام
                if (data.rawBody.isNotEmpty) ...[
                  _buildSystemBodyCard(context, data),
                  const SizedBox(height: 24),
                ],

                // 7) أزرار الإجراء السريعة بالأسفل
                _buildActionButtons(context, ref, data, isHrAdmin: isHrAdmin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 1. بطاقة الهيرو الأساسية
  Widget _buildHeaderCard(
    BuildContext context,
    WeeklyExecutiveSummaryData data, {
    required bool isHrAdmin,
    required VoidCallback onOpenPicker,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primaryContainer,
            scheme.surfaceContainerHighest,
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.analytics_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'تقرير نظامي دوري',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: scheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الملخص التنفيذي للأسبوع',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.periodLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (data.activeEmployees > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${data.activeEmployees} موظف نشط',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          if (isHrAdmin) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'إجراءات HR: تعديل دوام موظف أو إضافة راحة',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: onOpenPicker,
                    child: const Text(
                      'تعديل',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 2. شبكة المؤشرات الأساسية الأربعة
  Widget _buildMetricsGrid(BuildContext context, WeeklyExecutiveSummaryData data) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'حضور',
                count: data.presentCount,
                rate: '${data.presentRate}%',
                subtitle: 'نسبة الالتزام بالدوام',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF0F9F6E), // Green
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'تأخر',
                count: data.lateCount,
                rate: '${data.lateRate}%',
                subtitle: data.totalLateMinutes > 0
                    ? '${data.totalLateMinutes} دقيقة إجمالاً'
                    : 'سجلات التأخير',
                icon: Icons.access_time_filled_rounded,
                color: const Color(0xFFD97706), // Amber
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'غياب',
                count: data.absentCount,
                rate: '${data.absentRate}%',
                subtitle: 'نسبة الغياب عن العمل',
                icon: Icons.cancel_rounded,
                color: const Color(0xFFDC2626), // Red
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'إجازات',
                count: data.onLeaveCount,
                rate: null,
                subtitle: 'رسمية واعتيادية',
                icon: Icons.beach_access_rounded,
                color: const Color(0xFF2563EB), // Blue
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 3. شريط الإحصائيات الإضافية (دقائق التأخير، إضافي، انصراف مبكر)
  Widget _buildAdditionalStatsRow(BuildContext context, WeeklyExecutiveSummaryData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        alignment: WrapAlignment.spaceAround,
        children: [
          if (data.totalLateMinutes > 0)
            _MiniStatPill(
              icon: Icons.timer_outlined,
              label: 'إجمالي التأخير',
              value: '${data.totalLateMinutes} دقيقة',
              color: Colors.amber.shade800,
            ),
          if (data.totalEarlyLeaveMinutes > 0)
            _MiniStatPill(
              icon: Icons.logout_rounded,
              label: 'انصراف مبكر',
              value: '${data.totalEarlyLeaveMinutes} دقيقة',
              color: Colors.orange.shade800,
            ),
          if (data.totalOvertimeMinutes > 0)
            _MiniStatPill(
              icon: Icons.more_time_rounded,
              label: 'عمل إضافي',
              value: '${data.totalOvertimeMinutes} دقيقة',
              color: scheme.primary,
            ),
        ],
      ),
    );
  }

  /// 4. أعلى الموظفين تأخراً
  Widget _buildTopLateSection(
    BuildContext context,
    WidgetRef ref,
    WeeklyExecutiveSummaryData data, {
    required bool isHrAdmin,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.timer_off_outlined,
                  size: 20,
                  color: Colors.amber.shade900,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'أعلى الموظفين تأخراً خلال الأسبوع',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.topLateEmployees.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...data.topLateEmployees.asMap().entries.map((entry) {
            final idx = entry.key;
            final emp = entry.value;
            return _EmployeeStatTile(
              rank: idx + 1,
              name: emp.employeeName,
              employeeId: emp.employeeId,
              badgeText: emp.count > 0 ? '${emp.count} مرات تأخر' : null,
              secondaryBadgeText: emp.totalMinutes > 0 ? '${emp.totalMinutes} د' : null,
              badgeColor: Colors.amber.shade800,
              isHrAdmin: isHrAdmin,
              onAdjustDay: () => _openDayEditForStat(
                context,
                ref,
                emp,
                data,
                defaultDayType: 'work',
              ),
              onQuickAddRest: () => _openDayEditForStat(
                context,
                ref,
                emp,
                data,
                defaultDayType: 'rest',
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 5. الموظفون الأكثر غياباً (> 3 أيام)
  Widget _buildTopAbsentSection(
    BuildContext context,
    WidgetRef ref,
    WeeklyExecutiveSummaryData data, {
    required bool isHrAdmin,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_off_rounded,
                  size: 20,
                  color: Colors.red.shade900,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'تكرار الغياب (أكثر من 3 أيام غياب)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${data.absentGt3Employees.length}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...data.absentGt3Employees.asMap().entries.map((entry) {
            final idx = entry.key;
            final emp = entry.value;
            return _EmployeeStatTile(
              rank: idx + 1,
              name: emp.employeeName,
              employeeId: emp.employeeId,
              badgeText: emp.count > 0 ? '${emp.count} أيام غياب' : null,
              badgeColor: const Color(0xFFDC2626),
              isHrAdmin: isHrAdmin,
              onAdjustDay: () => _openDayEditForStat(
                context,
                ref,
                emp,
                data,
                defaultDayType: 'leave',
              ),
              onQuickAddRest: () => _openDayEditForStat(
                context,
                ref,
                emp,
                data,
                defaultDayType: 'rest',
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 6. نص التقرير النظامي الأصلي
  Widget _buildSystemBodyCard(BuildContext context, WeeklyExecutiveSummaryData data) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 20,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'نص الإشعار الصادر للإدارة',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'نسخ النص',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () => _copySummary(context, data),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data.rawBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.6,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  /// 7. أزرار الإجراء السريعة
  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    WeeklyExecutiveSummaryData data, {
    required bool isHrAdmin,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        if (isHrAdmin) ...[
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _openEmployeePickerAndEdit(context, ref, data),
              icon: const Icon(Icons.manage_accounts_rounded),
              label: const Text(
                'تعديل حالة موظف أو إضافة راحة أسبوعية',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), // WhatsApp Green
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _shareSummary(context, data),
            icon: const Icon(Icons.share_rounded),
            label: const Text(
              'مشاركة الملخص عبر واتساب',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MonthlyAttendanceStatementPage(),
                ),
              );
            },
            icon: const Icon(Icons.calendar_month_outlined),
            label: const Text(
              'الانتقال لبيان الحضور الشهري الكامل',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyInstantPenaltiesPage(),
                ),
              );
            },
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text(
              'غرامات التأخير وصندوق الزمالة والتكافل',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  /// بناء النص المنسق الكامل للملخص الأسبوعي
  String _buildFormattedSummaryText(WeeklyExecutiveSummaryData data) {
    final buffer = StringBuffer();
    buffer.writeln('📊 *الملخص الأسبوعي للحضور والانضباط — جمعية أحلى شباب* 📊');
    buffer.writeln('📅 *${data.periodLabel}*');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('✅ *الحضور:* ${data.presentCount} (${data.presentRate}%)');
    buffer.writeln('⏳ *التأخر:* ${data.lateCount} (${data.lateRate}%)');
    if (data.totalLateMinutes > 0) {
      buffer.writeln('⏱️ *إجمالي دقائق التأخير:* ${data.totalLateMinutes} دقيقة');
    }
    buffer.writeln('❌ *الغياب:* ${data.absentCount} (${data.absentRate}%)');
    buffer.writeln('🏖️ *الإجازات:* ${data.onLeaveCount}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    if (data.topLateEmployees.isNotEmpty) {
      buffer.writeln('⚠️ *أعلى المتأخرين:*');
      for (final e in data.topLateEmployees.take(5)) {
        final details = e.totalMinutes > 0 ? ' (${e.totalMinutes} د)' : '';
        buffer.writeln('• ${e.employeeName}$details');
      }
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    }

    if (data.absentGt3Employees.isNotEmpty) {
      buffer.writeln('🚨 *أكثر من 3 أيام غياب:*');
      for (final e in data.absentGt3Employees.take(5)) {
        final details = e.count > 0 ? ' (${e.count} أيام)' : '';
        buffer.writeln('• ${e.employeeName}$details');
      }
      buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    }

    buffer.writeln('🤝 *صندوق الزمالة والتكافل الاجتماعي:*');
    buffer.writeln('• جميع غرامات التأخير تُورّد بالكامل لحساب صندوق الزمالة لدعم الزملاء في الأزمات والرعاية.');
    buffer.writeln('• سجل الغرامات ومساهمات الصندوق متاح بشفافية تامة لجميع الزملاء داخل التطبيق.');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');

    buffer.writeln('— *صادر آلياً من منظومة أحلى شباب الإدارية*');
    return buffer.toString();
  }

  /// مشاركة نص الملخص عبر واتساب
  Future<void> _shareSummary(
    BuildContext context,
    WeeklyExecutiveSummaryData data,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _buildFormattedSummaryText(data);
    final ok = await WhatsAppShareService.shareText(text);
    if (!ok && context.mounted) {
      await Clipboard.setData(ClipboardData(text: text));
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح واتساب مباشرة. تم نسخ نص التقرير للحافظة!'),
        ),
      );
    }
  }

  /// نسخ النص إلى الحافظة
  Future<void> _copySummary(
    BuildContext context,
    WeeklyExecutiveSummaryData data,
  ) async {
    final text = _buildFormattedSummaryText(data);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ نص التقرير المنسق كاملاً إلى الحافظة بنجاح')),
      );
    }
  }

  /// فتح شاشة تعديل اليوم لموظف محدد من إحصائيات التقرير
  Future<void> _openDayEditForStat(
    BuildContext context,
    WidgetRef ref,
    WeeklyEmployeeStat stat,
    WeeklyExecutiveSummaryData data, {
    String defaultDayType = 'work',
  }) async {
    final empId = _resolveEmployeeId(ref, stat.employeeName, stat.employeeId);
    if (empId == null || empId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر العثور على معرّف الموظف (${stat.employeeName}) في السجل.',
          ),
        ),
      );
      return;
    }

    final dateToUse = _resolveDefaultDate(data);

    await AdminAttendanceDayEditSheet.show(
      context,
      employeeId: empId,
      employeeName: stat.employeeName,
      initialDate: dateToUse,
    );
  }

  String? _resolveEmployeeId(WidgetRef ref, String name, String? existingId) {
    if (existingId != null && existingId.isNotEmpty) return existingId;
    final orgList = ref.read(peopleOrgChartProvider).value;
    if (orgList != null) {
      for (final e in orgList) {
        if (e.fullNameAr.trim() == name.trim() ||
            e.fullNameAr.contains(name) ||
            name.contains(e.fullNameAr)) {
          return e.id;
        }
      }
    }
    return null;
  }

  static String _resolveDefaultDate(WeeklyExecutiveSummaryData data) {
    if (data.endDateText.isNotEmpty && data.endDateText != '—') {
      final text = data.endDateText;
      if (text.contains('/')) {
        final p = text.split('/');
        if (p.length == 3) {
          if (p[0].length == 4) {
            return '${p[0]}-${p[1].padLeft(2, '0')}-${p[2].padLeft(2, '0')}';
          }
          if (p[2].length == 4) {
            return '${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}';
          }
        }
      }
      return text;
    }
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }

  /// فتح ورقة اختيار أي موظف لتعديل حالته أو إضافة راحة
  Future<void> _openEmployeePickerAndEdit(
    BuildContext context,
    WidgetRef ref,
    WeeklyExecutiveSummaryData data,
  ) async {
    final orgAsync = ref.read(peopleOrgChartProvider);
    final allOrg = orgAsync.value ?? const <OrgEmployee>[];

    final weekStats = <WeeklyEmployeeStat>[
      ...data.topLateEmployees,
      ...data.absentGt3Employees,
    ];
    final seenNames = <String>{};
    final uniqueWeekEmployees =
        weekStats.where((s) => seenNames.add(s.employeeName)).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return _EmployeePickerSheet(
          weekEmployees: uniqueWeekEmployees,
          allOrgEmployees: allOrg,
          defaultDate: _resolveDefaultDate(data),
          onSelect: (empId, empName, date) {
            Navigator.pop(modalCtx);
            AdminAttendanceDayEditSheet.show(
              context,
              employeeId: empId,
              employeeName: empName,
              initialDate: date,
            );
          },
        );
      },
    );
  }
}

/// بطاقة مؤشر KPI مفردة
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.count,
    required this.rate,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final int count;
  final String? rate;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (rate != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    rate!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$count',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
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
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// عنصر سطر إحصائي مصغر
class _MiniStatPill extends StatelessWidget {
  const _MiniStatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// سطر موظف في قائمة المتأخرين أو المتغيبين
class _EmployeeStatTile extends StatelessWidget {
  const _EmployeeStatTile({
    required this.rank,
    required this.name,
    this.employeeId,
    this.badgeText,
    this.secondaryBadgeText,
    required this.badgeColor,
    this.isHrAdmin = false,
    this.onAdjustDay,
    this.onQuickAddRest,
  });

  final int rank;
  final String name;
  final String? employeeId;
  final String? badgeText;
  final String? secondaryBadgeText;
  final Color badgeColor;
  final bool isHrAdmin;
  final VoidCallback? onAdjustDay;
  final VoidCallback? onQuickAddRest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasProfile = employeeId != null && employeeId!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasProfile
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeeProfilePage(
                        employeeId: employeeId!,
                        employeeName: name,
                      ),
                    ),
                  );
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppAvatar(name: name, radius: 15),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: hasProfile ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      if (badgeText != null || secondaryBadgeText != null) ...[
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (badgeText != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  badgeText!,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: badgeColor,
                                  ),
                                ),
                              ),
                            if (secondaryBadgeText != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  secondaryBadgeText!,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (isHrAdmin) ...[
                  // زر إضافة راحة أسبوعية سريعة بنقرة واحدة
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'إضافة راحة أسبوعية سريعة',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.amber.withValues(alpha: 0.12),
                      foregroundColor: Colors.amber.shade800,
                      padding: const EdgeInsets.all(6),
                    ),
                    icon: const Icon(Icons.wb_sunny_rounded),
                    onPressed: onQuickAddRest,
                  ),
                  const SizedBox(width: 4),
                  // زر فتح شاشة تعديل اليوم بالتفصيل
                  IconButton(
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'تعديل حالة اليوم',
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary.withValues(alpha: 0.1),
                      foregroundColor: scheme.primary,
                      padding: const EdgeInsets.all(6),
                    ),
                    icon: const Icon(Icons.edit_calendar_rounded),
                    onPressed: onAdjustDay,
                  ),
                ] else if (hasProfile) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 13,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ورقة منبثقة لاختيار أي موظف وتحديد التاريخ المراد لتعديل حالته
class _EmployeePickerSheet extends StatefulWidget {
  const _EmployeePickerSheet({
    required this.weekEmployees,
    required this.allOrgEmployees,
    required this.defaultDate,
    required this.onSelect,
  });

  final List<WeeklyEmployeeStat> weekEmployees;
  final List<OrgEmployee> allOrgEmployees;
  final String defaultDate;
  final void Function(String employeeId, String employeeName, String date) onSelect;

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  late String _selectedDate;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.defaultDate;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDate() async {
    final initial = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: 'اختر تاريخ اليوم المراد تعديله',
      cancelText: 'إلغاء',
      confirmText: 'اختيار',
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  void _setDatePreset(int daysOffset) {
    final d = DateTime.now().add(Duration(days: daysOffset));
    setState(() {
      _selectedDate = DateFormat('yyyy-MM-dd').format(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterdayStr = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

    final weekWithIds = widget.weekEmployees.map((w) {
      String? matchedId = w.employeeId;
      if (matchedId == null || matchedId.isEmpty) {
        for (final o in widget.allOrgEmployees) {
          if (o.fullNameAr.trim() == w.employeeName.trim() ||
              o.fullNameAr.contains(w.employeeName) ||
              w.employeeName.contains(o.fullNameAr)) {
            matchedId = o.id;
            break;
          }
        }
      }
      return (stat: w, resolvedId: matchedId);
    }).where((item) => item.resolvedId != null).toList();

    final filteredAll = widget.allOrgEmployees.where((e) {
      if (_query.isEmpty) return true;
      final q = _query.trim().toLowerCase();
      return e.fullNameAr.toLowerCase().contains(q) ||
          e.employeeCode.toLowerCase().contains(q) ||
          e.jobTitle.toLowerCase().contains(q) ||
          e.departmentName.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.manage_accounts_rounded, color: scheme.primary, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إدارة دوام موظف / إضافة راحة',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      Text(
                        'اختر اليوم والموظف لتعديل حالته فورياً وسجل التدقيق',
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // شريط اختيار تاريخ التعديل
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      const Text(
                        'تاريخ اليوم المستهدف للتعديل:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _selectedDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildDateChip('اليوم', _selectedDate == todayStr, () => _setDatePreset(0)),
                        const SizedBox(width: 6),
                        _buildDateChip('أمس', _selectedDate == yesterdayStr, () => _setDatePreset(-1)),
                        const SizedBox(width: 6),
                        _buildDateChip('تاريخ التقرير', _selectedDate == widget.defaultDate, () {
                          setState(() => _selectedDate = widget.defaultDate);
                        }),
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: const Icon(Icons.edit_calendar_rounded, size: 16),
                          label: const Text('تاريخ مخصص', style: TextStyle(fontSize: 12)),
                          onPressed: _pickCustomDate,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // شريط البحث
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'ابحث عن موظف بالاسم أو الكود أو الوظيفة...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          // قائمة الموظفين
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                if (_query.isEmpty && weekWithIds.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'موظفو ملخص هذا الأسبوع (${weekWithIds.length})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...weekWithIds.map((item) {
                    return _buildEmployeeRow(
                      id: item.resolvedId!,
                      name: item.stat.employeeName,
                      subtitle: item.stat.count > 0 ? 'سجل تأخر / غياب في التقرير' : null,
                      isHighlighted: true,
                    );
                  }),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                ],

                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _query.isEmpty
                        ? 'جميع الموظفين (${widget.allOrgEmployees.length})'
                        : 'نتائج البحث (${filteredAll.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (filteredAll.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'لا يوجد موظفون مطابقون',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  ...filteredAll.map((emp) {
                    return _buildEmployeeRow(
                      id: emp.id,
                      name: emp.fullNameAr,
                      subtitle: [
                        if (emp.jobTitle.isNotEmpty) emp.jobTitle,
                        if (emp.departmentName.isNotEmpty) emp.departmentName,
                      ].join(' • '),
                      code: emp.employeeCode,
                      photoUrl: emp.photoUrl,
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(String label, bool isSelected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primaryContainer,
      showCheckmark: false,
    );
  }

  Widget _buildEmployeeRow({
    required String id,
    required String name,
    String? subtitle,
    String? code,
    String? photoUrl,
    bool isHighlighted = false,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isHighlighted
            ? scheme.primaryContainer.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onSelect(id, name, _selectedDate),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                AppAvatar(name: name, photoUrl: photoUrl, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
                if (code != null && code.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      code,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Icon(
                  Icons.edit_calendar_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

