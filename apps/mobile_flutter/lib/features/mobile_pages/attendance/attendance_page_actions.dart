part of '../mobile_attendance_page.dart';

extension _AttendancePageActions on _MobileAttendancePageState {
  Future<void> _openMissionSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => const NewRequestSheet(type: 'mission'),
    );
    if (result == null || !mounted) return;

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('جاري إرسال طلب المأمورية...'),
              ],
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
      await ref.read(mobileCommandsProvider).submitRequest(
            'mission',
            result['title'] as String,
            result['reason'] as String,
            result['payload'] as Map<String, dynamic>,
          );
      ref.invalidate(attendanceStateProvider);
      ref.invalidate(mobileRequestsProvider);
      ref.invalidate(employeeHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب المأمورية بنجاح إلى مسار الاعتماد.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(error))),
        );
      }
    }
  }

  Future<void> _register() async {
    if (_working) return;
    _updateUi(() => _working = true);
    try {
      await ref.read(mobileCommandsProvider).registerLocalBiometricDevice();
      ref.invalidate(attendanceStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الجهاز بنجاح — جاهز للاستخدام الآن.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (error, stack) {
      _showErrorFeedback(error, stack, contextTag: '_register');
    } finally {
      if (mounted) _updateUi(() => _working = false);
    }
  }

  void _showErrorFeedback(
    dynamic error,
    StackTrace? stack, {
    required String contextTag,
  }) {
    if (!mounted) return;
    if (kDebugMode) {
      debugPrint('[$contextTag] ${error.runtimeType}: $error\n$stack');
    }
    final msg = error.toString();
    final isCancelled =
        msg.contains('إلغاء') ||
        msg.toLowerCase().contains('cancel') ||
        msg.toLowerCase().contains('dismissed');
    if (isCancelled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إلغاء التحقق.')),
      );
      return;
    }

    final text = humanizeError(error, stack);
    final isPasscodeIssue =
        text.contains('قفل الشاشة') ||
        text.contains('PIN') ||
        text.contains('PasscodeNotSet') ||
        text.contains('NotEnrolled') ||
        msg.contains('PasscodeNotSet') ||
        msg.contains('NotEnrolled') ||
        msg.contains('الجهاز لا يدعم');

    if (isPasscodeIssue) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.lock_reset_rounded,
            color: AppColors.statusWarning,
            size: 36,
          ),
          title: const Text(
            'إعداد قفل الشاشة مطلوب',
            textAlign: TextAlign.center,
          ),
          content: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً، فهمت'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: AppColors.statusDanger,
        ),
      );
    }
  }

  /// ترجمة أكواد الخطأ من الخادم إلى رسائل عربية واضحة للمستخدم.
  String _humanizePunchError(String code) {
    switch (code) {
      case 'attendance_outside_complex':
        return 'تم التحقق من الجهاز بنجاح، لكنك خارج نطاق المجمع. يُرجى التسجيل من داخل موقع العمل.';
      case 'attendance_mock_location_rejected':
        return 'تم التحقق من الجهاز بنجاح، لكن تم رفض الموقع — يُشتبه في استخدام موقع مزيف.';
      case 'attendance_location_accuracy_too_low':
        return 'تم التحقق من الجهاز بنجاح، لكن دقة الموقع منخفضة جداً. حاول في مكان مفتوح.';
      case 'attendance_geofence_not_configured':
        return 'لم يتم تحديد نطاق جغرافي لحضورك. تواصل مع المسؤول.';
      case 'attendance_location_required':
        return 'الموقع مطلوب لتسجيل الحضور.';
      case 'duplicate_attendance_event':
        return 'تم تسجيل هذا الحدث مسبقاً.';
      case 'attendance_period_finalized':
        return 'فترة الحضور مغلقة ولا يمكن التعديل عليها.';
      case 'attendance_check_in_required':
        return 'يجب تسجيل الحضور أولاً قبل الانصراف.';
      case 'attendance_check_out_required':
        return 'يجب تسجيل الانصراف أولاً قبل حضور جديد.';
      case 'attendance_rapid_punch_rejected':
        return 'تم تسجيل بصمة بنجاح منذ قليل. يُرجى الانتظار 30 ثانية قبل تسجيل أي بصمة أخرى.';
      case 'attendance_checkout_too_early':
        return 'سُجّل حضورك للتو. لا يمكن تسجيل الانصراف إلا بعد مضي دقيقتين على الأقل لمنع الانصراف غير المقصود.';
      // 0226: Device errors now return structured JSON instead of RAISE.
      case 'local_biometric_device_not_active':
        return 'هذا الجهاز غير مفعّل للحضور. سجّل الجهاز من جديد أو تواصل مع المسؤول.';
      default:
        return 'حدث خطأ غير متوقع ($code). حاول مرة أخرى.';
    }
  }

  // ── 0450: دورة يوم المأمورية ─────────────────────────────────────────
  /// بدء المأمورية من نقطة المهمة مباشرة — بلا حاجة لبصمة المقر.
  Future<void> _startMission(String requestId) async {
    if (_working) return;
    _updateUi(() => _working = true);
    try {
      await ref.read(mobileCommandsProvider).startMission(requestId);
      ref.invalidate(attendanceStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم بدء المأمورية — بالتوفيق في مهمتك.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      if (mounted) _updateUi(() => _working = false);
    }
  }

  /// إنهاء المأمورية (تقرير اختياري + خياران للعودة أو الانصراف):
  /// 1) إنهاء المأمورية والعودة لمقر العمل (استمرار الدوام) ثم إتاحة زر بصمة الانصراف العادي.
  /// 2) أو إنهاء المأمورية مع الانصراف المباشر من الموقع الحالي (من برة برة).
  Future<void> _endMissionFlow(MissionToday mission) async {
    final reportController = TextEditingController();
    final outcomeController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag_circle_outlined, color: AppColors.brandPrimary),
            SizedBox(width: 8),
            Text('إنهاء المأمورية'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'سجّل تقرير إنجاز المهمة (اختياري - غير إلزامي)، ثم اختر ما إذا كنت ستعود لمقر العمل لمتابعة يومك، أم أن المأمورية امتدت وتريد الانصراف من موقعك الحالي مباشرة.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reportController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'تقرير المأمورية (اختياري)',
                  hintText: 'ماذا أنجزت في المهمة؟ (اختياري - يمكنك تركه فارغاً)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: outcomeController,
                decoration: const InputDecoration(
                  labelText: 'النتيجة (اختياري)',
                  hintText: 'مثال: اكتملت بنجاح…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, false),
                icon: const Icon(Icons.business_rounded),
                label: const Text('إنهاء والعودة للجمعية (استمرار الدوام)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'ستعود لمتابعة دوامك، ويظهر لك زر بصمة الانصراف العادي عند خروجك.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('إنهاء المأمورية مع تسجيل الانصراف الميداني'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.statusSuccess,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 4),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'يُسجَّل انصرافك فوراً وكأنك بصمت، دون الحاجة للذهاب للمقر.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    final reportText = reportController.text.trim();
    final outcomeText = outcomeController.text.trim();
    reportController.dispose();
    outcomeController.dispose();
    if (result == null || !mounted) return;
    if (_working) return;
    _updateUi(() => _working = true);

    Position? position;
    if (result == true) {
      try {
        position = await LocationService.current();
      } catch (locErr) {
        debugPrint('[endMissionFlow] GPS location note: $locErr');
      }
    }

    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(
            requestId: mission.requestId,
            report: reportText.isEmpty ? 'تم إنجاز المأمورية بنجاح' : reportText,
            outcome: outcomeText.isEmpty ? null : outcomeText,
            withCheckout: result,
            latitude: position?.latitude,
            longitude: position?.longitude,
            accuracy: position?.accuracy,
            isMock: position?.isMocked ?? false,
          );
      ref.invalidate(attendanceStateProvider);
      ref.invalidate(employeeHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result
                  ? 'تم إنهاء المأمورية وتسجيل بصمة انصراف ميدانية بنجاح.'
                  : 'تم إنهاء المأمورية بنجاح — دوامك مستمر، وزر الانصراف متاح الآن.',
            ),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(error))));
      }
    } finally {
      if (mounted) _updateUi(() => _working = false);
    }
  }

  /// إلغاء المأمورية والعودة للوضع الطبيعي للحضور مع إمكانية الانصراف
  Future<void> _cancelMissionFlow(String requestId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.statusDanger),
            const SizedBox(width: 8),
            const Text('إلغاء المأمورية'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'هل أنت متأكد من رغبتك في إلغاء هذه المأمورية؟ سيتم إلغاؤها فوراً وإعادتك لوضع الحضور الطبيعي لتتمكن من تسجيل الانصراف أو مواصلة عملك بالجمعية.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء (اختياري)',
                hintText: 'مثال: تم إلغاء المهمة، لم أخرج…',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusDanger,
              foregroundColor: Colors.white,
            ),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );

    final reason = reasonController.text.trim();
    reasonController.dispose();

    if (confirmed != true || !mounted) return;
    if (_working) return;
    _updateUi(() => _working = true);

    try {
      await ref.read(mobileCommandsProvider).cancelMission(
        requestId: requestId,
        reason: reason.isEmpty ? null : reason,
      );
      ref.invalidate(attendanceStateProvider);
      ref.invalidate(employeeHomeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء المأمورية بنجاح. يمكنك الآن تسجيل الانصراف أو مواصلة عملك.'),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إلغاء المأمورية: ${humanizeError(error)}')),
        );
      }
    } finally {
      if (mounted) _updateUi(() => _working = false);
    }
  }
}
