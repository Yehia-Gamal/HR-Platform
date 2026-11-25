part of '../monthly_attendance_statement_page.dart';

class _StatementBody extends StatelessWidget {
  const _StatementBody({required this.statement});

  final MonthlyAttendanceStatement statement;

  static String _formatOvertimeValue(int minutes) {
    if (minutes <= 0) return '0';
    if (minutes < 60) return '$minutes';
    final hours = minutes / 60.0;
    return hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1);
  }

  static String _formatOvertimeUnit(int minutes) {
    if (minutes <= 0) return 'ساعة';
    if (minutes < 60) return 'دقيقة';
    return 'ساعة ($minutes د)';
  }

  @override
  Widget build(BuildContext context) {
    final s = statement.summary;
    final scheme = Theme.of(context).colorScheme;
    final isExecutive =
        statement.employeeId == '7b0740fa-66ba-4616-8674-3dbd8e14109e' ||
        statement.employeeNameAr.contains('محمد يوسف') ||
        statement.jobTitle.contains('المدير التنفيذي');

    if (s.isAttendanceExempt || isExecutive) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _EmployeeHeader(statement: statement),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.verified_user_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    isExecutive
                        ? 'المدير التنفيذي — معفى من البصمة'
                        : 'معفى من تسجيل الحضور والانصراف',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isExecutive
                        ? 'المدير التنفيذي معفى تمامًا من سجلات الحضور والانصراف بقرار الإدارة العليا، ولا يخضع لنظام البصمة أو تقارير الدوام.'
                        : 'هذا الموظف معفى من نظام البصمة وسجلات الحضور بقرار إداري.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final convoyDays = statement.days
        .where(
          (d) =>
              (d.status.contains('قافلة') || d.hasConvoyFundi) &&
              !d.status.contains('فاندي'),
        )
        .length;
    final fundiDays = statement.days
        .where((d) => d.status.contains('فاندي'))
        .length;
    final cDays = statement.days.isNotEmpty ? convoyDays : s.convoyFundiDays;
    final fDays = statement.days.isNotEmpty ? fundiDays : 0;
    // أربع بطاقات في صف واحد على هاتف 360–420dp تُضغط التسميات في عمود ضيق
    // جدًا. نستخدم عمودين حتى 420dp ونربط الارتفاع بحجم الخط.
    final narrowScreen = MediaQuery.sizeOf(context).width < 420;
    final metricColumns = narrowScreen ? 2 : 4;
    final metricExtent = MediaQuery.textScalerOf(
      context,
    ).scale(100).clamp(100.0, 150.0).toDouble();
    final summaryExtent = MediaQuery.textScalerOf(
      context,
    ).scale(66).clamp(66.0, 108.0).toDouble();
    final metricTiles = <Widget>[
      _MetricTile(
        icon: Icons.check_circle_outline,
        label: 'حضور',
        value: '${s.presentDays}',
        color: const Color(0xFF0F9F6E),
      ),
      _MetricTile(
        icon: Icons.cancel_outlined,
        label: 'غياب',
        value: '${s.absentDays}',
        color: scheme.error,
      ),
      _MetricTile(
        icon: Icons.beach_access_outlined,
        label: 'إجازات',
        value: '${s.leaveDays}',
        color: const Color(0xFF4F46E5),
      ),
      _MetricTile(
        icon: Icons.directions_car_outlined,
        label: 'مأموريات',
        value: '${s.missionDays}',
        color: const Color(0xFF0284C7),
      ),
      _MetricTile(
        icon: Icons.assignment_outlined,
        label: 'أذونات',
        value: '${s.permitCount}',
        color: const Color(0xFFD97706),
      ),
      _MetricTile(
        icon: Icons.volunteer_activism_outlined,
        label: 'قوافل',
        value: '$cDays',
        color: const Color(0xFF7C3AED),
      ),
      _MetricTile(
        icon: Icons.attractions_outlined,
        label: 'فاندي (ترفيهي)',
        value: '$fDays',
        color: const Color(0xFFDB2777),
      ),
      _MetricTile(
        icon: Icons.bed_outlined,
        label: 'عطلات',
        value: '${s.restDays + s.holidayDays}',
        color: const Color(0xFF64748B),
      ),
    ];
    final summaryTiles = <Widget>[
      _SummaryTile(
        label: 'إجمالي الساعات',
        value: s.totalWorkHours.toStringAsFixed(1),
        unit: 'ساعة',
      ),
      _SummaryTile(
        label: 'متوسط يومي',
        value: s.averageWorkHours.toStringAsFixed(1),
        unit: 'ساعة/يوم',
      ),
      _SummaryTile(
        label: 'إجمالي التأخير',
        value: '${s.totalLateMinutes}',
        unit: 'دقيقة',
      ),
      _SummaryTile(
        label: 'خروج مبكر',
        value: '${s.totalEarlyLeaveMinutes}',
        unit: 'دقيقة',
      ),
      _SummaryTile(
        label: 'ساعات إضافية',
        value: _formatOvertimeValue(s.totalOvertimeMinutes),
        unit: _formatOvertimeUnit(s.totalOvertimeMinutes),
      ),
      _SummaryTile(
        label: 'تصحيحات معتمدة',
        value: '${s.correctionCount}',
        unit: '',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        // ───── بطاقة بيانات الموظف ─────
        _EmployeeHeader(statement: statement),
        const SizedBox(height: 16),

        // ───── دائرة نسبة الحضور والالتزام ─────
        _AttendancePercentageCard(statement: statement),
        const SizedBox(height: 16),

        // ───── بطاقات الملخص الرئيسية ─────
        Text(
          'ملخص الشهر',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metricTiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: metricColumns,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
            mainAxisExtent: metricExtent,
          ),
          itemBuilder: (context, index) => metricTiles[index],
        ),
        const SizedBox(height: 16),

        // ───── مستهدف ساعات العمل الشهرية ─────
        _WorkingHoursGoalCard(statement: statement),
        const SizedBox(height: 16),

        // ───── بطاقات الساعات والتأخيرات ─────
        Text(
          'الساعات والمخالفات',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: summaryTiles.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
            mainAxisExtent: summaryExtent,
            ),
          itemBuilder: (context, index) => summaryTiles[index],
        ),
        const SizedBox(height: 16),

        // ───── الرؤى والإرشادات الذكية ─────
        _MonthlySmartInsights(statement: statement),

        // ───── تنبيه نقص البصمة التفاعلي ─────
        if (s.missingCheckInCount > 0 || s.missingCheckOutCount > 0) ...[
          const SizedBox(height: 12),
          _MissingPunchesBanner(statement: statement),
        ],

        const SizedBox(height: 20),

        // ───── التقويم الشهري ─────
        Text(
          'التقويم الشهري',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          'اضغط على أي يوم لعرض التفاصيل والإجراءات المتاحة.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        _MonthlyCalendarGrid(
          statement: statement,
          days: statement.days,
          year: statement.year,
          month: statement.month,
        ),

        // ───── دليل الألوان ─────
        const SizedBox(height: 12),
        const Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LegendChip(color: Color(0xFF0F9F6E), label: 'حضور'),
            _LegendChip(color: Color(0xFFDC2626), label: 'غياب'),
            _LegendChip(color: Color(0xFF4F46E5), label: 'إجازة'),
            _LegendChip(color: Color(0xFF0284C7), label: 'مأمورية'),
            _LegendChip(color: Color(0xFF7C3AED), label: 'قافلة'),
            _LegendChip(color: Color(0xFFDB2777), label: 'فاندي (يوم ترفيهي)'),
            _LegendChip(color: Color(0xFFD97706), label: 'مراجعة / تأخير'),
            _LegendChip(color: Color(0xFF94A3B8), label: 'راحة / عطلة'),
            _LegendChip(color: Color(0xFF64748B), label: 'قادم'),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─── بطاقة بيانات الموظف ──────────────────────────────────────────

class _EmployeeHeader extends StatelessWidget {
  const _EmployeeHeader({required this.statement});
  final MonthlyAttendanceStatement statement;

  static String _formatEmployeeCodeOrPhone(String? code) {
    if (code == null || code.trim().isEmpty) return '';
    final cleaned = PhoneDisplay.stripCountryCode(code);
    if (cleaned.startsWith('01') && cleaned.length >= 11) {
      return 'الهاتف: $cleaned';
    }
    // لو بدأ بـ + دولي غير مصري
    if (cleaned.startsWith('+')) {
      return 'الهاتف: $cleaned';
    }
    return 'كود: $cleaned';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    final job = statement.jobTitle.trim();
    final dept = statement.department.trim();
    final isSameJobAndDept = job.isNotEmpty && (job == dept);
    final managerName = statement.manager.replaceAll('ألشيخ', 'الشيخ').trim();
    final codeOrPhone = _formatEmployeeCodeOrPhone(statement.employeeCode);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // الاسم والكود/الهاتف مع الصورة الرمزية الرسمية
            Row(
              children: [
                AppAvatar(
                  name: statement.employeeNameAr,
                  photoUrl: statement.photoUrl,
                  radius: 24,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statement.employeeNameAr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      if (codeOrPhone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(codeOrPhone, style: muted),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // تفاصيل وظيفية — إزالة التكرار
            if (isSameJobAndDept)
              _InfoRow(
                icon: Icons.work_outline,
                label: 'القسم والمسمى',
                value: job,
              )
            else ...[
              _InfoRow(
                icon: Icons.work_outline,
                label: 'المسمى الوظيفي',
                value: job,
              ),
              _InfoRow(
                icon: Icons.business_outlined,
                label: 'القسم',
                value: dept,
              ),
            ],
            _InfoRow(
              icon: Icons.location_city_outlined,
              label: 'الفرع',
              value: statement.branch,
            ),
            _InfoRow(
              icon: Icons.supervisor_account_outlined,
              label: 'المدير المباشر',
              value: managerName,
            ),
            _InfoRow(
              icon: Icons.calendar_month_outlined,
              label: 'الفترة',
              value: '${_months[statement.month - 1]} ${statement.year}',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text('$label: ', style: muted),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── دائرة ونسبة الحضور والالتزام ────────────────────────────────

