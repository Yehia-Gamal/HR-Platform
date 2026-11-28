part of '../monthly_attendance_statement_page.dart';

extension _DayDetailActions on _DayDetailSheet {
  List<Widget> _buildActions(
    BuildContext context,
    WidgetRef ref,
    ColorScheme scheme,
  ) {
    final actions = <Widget>[];

    final now = AppTime.now();
    final isSameMonth = year == now.year && month == now.month;
    final canModifyDay = !isFuture && isSameMonth;

    final isClinicStaff =
        ref.watch(accessContextProvider).value?.isClinicStaff == true;
    // طلبات الإجازة والأذونات والتصحيح وتعديل حالة اليوم تُقدَّم باسم من يستخدم
    // التطبيق، فلا تظهر على كشف موظف آخر (كان المدير يراها على كشف مرؤوسه فيقدّمها
    // باسمه هو). هناك يظهر التعديل الإداري وحده، بقرار الخادم (canEditDays).
    final isOwn = _isOwnStatement(ref, statement);

    // ── تعديل حالة اليوم بأثر رجعي في نفس الشهر (إجازة/مأمورية/قافلة مساعدات/فاندي) ──
    if (isOwn && canModifyDay) {
      actions.add(
        _ActionTile(
          icon: Icons.published_with_changes_rounded,
          label: 'تعديل حالة هذا اليوم',
          subtitle: isClinicStaff
              ? 'طلب تحويل اليوم إلى إجازة معتمدة.'
              : 'طلب تحويل اليوم إلى إجازة، مأمورية عمل، قافلة مساعدات، أو يوم ترفيهي (فاندي).',
          color: const Color(0xFF4F46E5),
          onTap: () => _openRetroactiveDayChange(context, ref),
        ),
      );
    }

    // يوم ماضٍ غائب قد يُغطّى أيضاً بإجازة بأثر رجعي.
    if (isOwn &&
        !isFuture &&
        !isToday &&
        day != null &&
        day!.status == 'غائب دون إذن') {
      actions.add(
        _ActionTile(
          icon: Icons.beach_access_outlined,
          label: 'طلب إجازة لتغطية هذا اليوم',
          subtitle: 'تقديم طلب إجازة بأثر رجعي يعتمده المدير المباشر.',
          color: const Color(0xFF6366F1),
          onTap: () => _openLeaveRequest(context, ref),
        ),
      );
    }

    final eligibleTypes = _correctionTypes(ref);
    if (isOwn && eligibleTypes.isNotEmpty) {
      actions.add(
        _ActionTile(
          icon: Icons.fingerprint,
          label: 'طلب تصحيح بصمة',
          subtitle: eligibleTypes.length == 1
              ? '${_correctionTypeLabel(eligibleTypes.single)} · يُرسل للمدير للمراجعة.'
              : 'اختر البصمة التي لم تُسجَّل. يُرسل الطلب للمدير للمراجعة.',
          color: scheme.primary,
          onTap: () => _openCorrectionRequest(context, ref, eligibleTypes),
        ),
      );
    }

    // ── تأخير → إذن حضور ──
    if (isOwn &&
        !isFuture &&
        day != null &&
        day!.lateMinutes > 0 &&
        !day!.hasPermit) {
      actions.add(
        _ActionTile(
          icon: Icons.schedule,
          label: 'طلب إذن حضور',
          subtitle: 'تغطية ${day!.lateMinutes} دقيقة تأخير بإذن مُعتمَد.',
          color: const Color(0xFFF59E0B),
          onTap: () => _openPermitRequest(context, ref, 'late_arrival'),
        ),
      );
    }

    // ── خروج مبكر → إذن انصراف ──
    if (isOwn &&
        !isFuture &&
        day != null &&
        day!.earlyLeaveMinutes > 0 &&
        !day!.hasPermit) {
      actions.add(
        _ActionTile(
          icon: Icons.exit_to_app,
          label: 'طلب إذن انصراف',
          subtitle: 'تغطية ${day!.earlyLeaveMinutes} دقيقة خروج مبكر.',
          color: const Color(0xFFF59E0B),
          onTap: () => _openPermitRequest(context, ref, 'early_departure'),
        ),
      );
    }

    // ── يوم قادم → طلب إجازة مسبقة ──
    if (isOwn && isFuture) {
      actions.add(
        _ActionTile(
          icon: Icons.beach_access_outlined,
          label: 'طلب إجازة مسبقة',
          subtitle: 'تقديم طلب إجازة لهذا اليوم — يعتمده المدير المباشر.',
          color: const Color(0xFF6366F1),
          onTap: () => _openLeaveRequest(context, ref),
        ),
      );
    }

    final access = ref.watch(accessContextProvider).value;
    final canEditDaysAdmin =
        statement.canEditDays && (access?.canAdminEditAttendanceDays ?? false);

    // ── التعديل الإداري لليوم أو إلغاؤه — الموارد البشرية والسكرتير التنفيذي حصراً ──
    if (canEditDaysAdmin) {
      actions.add(
        _ActionTile(
          icon: Icons.edit_calendar_rounded,
          label: 'تعديل اليوم إدارياً (حالة اليوم وساعات العمل)',
          subtitle:
              'تعديل نوع اليوم إلى عمل أو إجازة أو مأمورية أو ضبط الساعات.',
          color: scheme.primary,
          onTap: () => _openAdminEditDaySheet(context, ref),
        ),
      );
    }

    if (day?.hasAdminOverride == true && canEditDaysAdmin) {
      actions.add(
        _ActionTile(
          icon: Icons.restart_alt_rounded,
          label: 'إلغاء التعديل الإداري والعودة لاحتساب النظام',
          subtitle: 'حذف الاستثناء الإداري واستعادة الاحتساب التلقائي للبصمات.',
          color: scheme.error,
          onTap: () => _revertAdminOverride(context, ref),
        ),
      );
    }

    if (actions.isEmpty) {
      actions.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              isOwn
                  ? 'لا توجد إجراءات متاحة لهذا اليوم.'
                  : 'للاطلاع فقط — الطلبات يقدّمها الموظف من حسابه، والتعديل الإداري للموارد البشرية.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return actions;
  }

  // ── إلغاء التعديل الإداري والعودة لاحتساب النظام ──
  Future<void> _revertAdminOverride(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء التعديل الإداري'),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء التعديل الإداري والعودة لاحتساب النظام الأصلي للبصمات؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final empId = statement.employeeId;
      await ref
          .read(mobileCommandsProvider)
          .clearAttendanceDayAdmin(employeeId: empId, date: _dateStr);
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء التعديل الإداري واستعادة احتساب النظام.'),
          ),
        );
        if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  // ── فتح ورقة التعديل الإداري ──
  Future<void> _openAdminEditDaySheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await AdminAttendanceDayEditSheet.show(
      context,
      employeeId: statement.employeeId,
      employeeName: statement.employeeNameAr,
      initialDate: _dateStr,
      initialDay: day,
      hasExistingOverride: day?.hasAdminOverride == true,
    );
    if (result == true && context.mounted) {
      _invalidateProviders(ref);
      if (ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
    }
  }

  // ── فتح نموذج تعديل حالة اليوم بأثر رجعي (إجازة / مأمورية / قافلة / يوم ترفيهي فاندي) ──
  Future<void> _openRetroactiveDayChange(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final isClinicStaff =
        ref.read(accessContextProvider).value?.isClinicStaff == true;
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RetroactiveDayChangeSheet(
        dateStr: _dateStr,
        dayNameAr: day?.dayNameAr ?? _dayNameFull,
        currentStatus: day?.status ?? 'غير مسجل',
        isClinicStaff: isClinicStaff,
      ),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(mobileCommandsProvider)
          .submitRequest(
            result['type'] as String,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      ref.invalidate(myLeaveBalancesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب تعديل حالة اليوم بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  // ── فتح نموذج طلب إجازة سريع ──
  Future<void> _openLeaveRequest(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickLeaveSheet(dateStr: _dateStr),
    );
    if (result == null || !context.mounted) return;
    try {
      await ref
          .read(mobileCommandsProvider)
          .submitRequest(
            'leave',
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الإجازة بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  // ── فتح نموذج تصحيح حضور سريع ──
  Future<void> _openCorrectionRequest(
    BuildContext context,
    WidgetRef ref,
    List<String> eligibleTypes,
  ) async {
    final commands = ref.read(mobileCommandsProvider);
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuickCorrectionSheet(
        dateStr: _dateStr,
        allowedTypes: eligibleTypes,
        onSubmit: (type, reason, checkIn, checkOut) =>
            commands.requestAttendanceCorrection(
              workDate: DateTime.parse(_dateStr),
              type: type,
              reason: reason,
              checkIn: checkIn,
              checkOut: checkOut,
            ),
      ),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب التصحيح للمراجعة.')),
      );
    }
  }

  // ── فتح نموذج إذن سريع ──
  Future<void> _openPermitRequest(
    BuildContext context,
    WidgetRef ref,
    String permitKind,
  ) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _QuickPermitSheet(dateStr: _dateStr, permitKind: permitKind),
    );
    if (result == null || !context.mounted) return;
    final resolvedType = permitKind == 'early_departure'
        ? 'early_permit'
        : 'late_permit';
    try {
      await ref
          .read(mobileCommandsProvider)
          .submitRequest(
            resolvedType,
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      _invalidateProviders(ref);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب الإذن بنجاح.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    }
  }

  void _invalidateProviders(WidgetRef ref) {
    ref.invalidate(mobileRequestsProvider);
    ref.invalidate(myMonthlyStatementProvider((year, month)));
    if (statement.employeeId.isNotEmpty) {
      ref.invalidate(
        employeeMonthlyStatementProvider((statement.employeeId, year, month)),
      );
    }
  }
}
