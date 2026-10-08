import 'dart:async';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/core/widgets/host_app_bar_scope.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_correction_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_corrections_section.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_request_detail_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_self_service_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';

class MobileAttendancePage extends ConsumerStatefulWidget {
  const MobileAttendancePage({super.key});

  @override
  ConsumerState<MobileAttendancePage> createState() =>
      _MobileAttendancePageState();
}

class _MobileAttendancePageState extends ConsumerState<MobileAttendancePage>
    with WidgetsBindingObserver {
  bool _working = false;

  /// فحص توفر قفل الشاشة (نقش/PIN) أو البصمة محلياً على الجهاز.
  bool? _deviceLockConfigured;

  /// تحديث احتياطي لبيانات الحضور والتصحيحات أثناء ظهور الصفحة.
  /// التحديث الفوري يأتي من قناة Realtime (attendanceRealtimeProvider) —
  /// يبقى المؤقت صمام أمان لانقطاع socket أو تعثر القناة.
  Timer? _refreshTimer;

  /// نوع مشكلة الموقع — لتحديد زر الإعدادات المناسب.
  _LocationIssueKind? _issueKind;

  /// العملية المعلقة بعد العودة من إعدادات GPS.
  _PendingRetry? _pendingRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoRefresh();
    _checkDeviceSecurity();
  }

  Future<void> _checkDeviceSecurity() async {
    if (kIsWeb) return;
    try {
      final localAuth = LocalAuthentication();
      final supported = await localAuth.isDeviceSupported();
      final canBiometrics = await localAuth.canCheckBiometrics;
      if (mounted) setState(() => _deviceLockConfigured = supported || canBiometrics);
    } catch (_) {
      if (mounted) setState(() => _deviceLockConfigured = true);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// تحديث احتياطي كل 60 ثانية فقط عندما تكون الصفحة ظاهرة.
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      ref.invalidate(attendanceStateProvider);
      ref.invalidate(myAttendanceServicesProvider);
      ref.invalidate(myWorkShiftInfoProvider);
    });
  }

  /// عند العودة من إعدادات الموقع أو التطبيق — إعادة المحاولة تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
      _checkDeviceSecurity();
      if (_issueKind != null && _pendingRetry != null && !_working) {
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted &&
              _issueKind != null &&
              _pendingRetry != null &&
              !_working) {
            _recheckAndRetry();
          }
        });
      }
    }
  }

  Future<void> _recheckAndRetry() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!enabled) return;

    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      final newPerm = await Geolocator.requestPermission();
      if (!mounted) return;
      if (newPerm == LocationPermission.denied ||
          newPerm == LocationPermission.deniedForever) {
        return;
      }
    }

    // كلا الشرطين تحققا — امسح الخطأ وأعد العملية المعلقة
    final retry = _pendingRetry;
    setState(() {
      _issueKind = null;
      _pendingRetry = null;
    });
    if (retry == _PendingRetry.register) {
      _register();
    } else if (retry != null) {
      _punch(retry.action!, skipDialog: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // تفعيل قناة Realtime طوال عمر الصفحة — بطلان الحالة فور أي بصمة جديدة.
    ref.watch(attendanceRealtimeProvider);
    final state = ref.watch(attendanceStateProvider);
    return Scaffold(
      appBar: HostAppBarScope.isActive(context)
          ? null
          : AppBar(title: const Text('الحضور والانصراف')),
      body: SafeArea(
        child: Column(
          children: [
            const GpsPreflightBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(attendanceStateProvider);
                  ref.invalidate(myAttendanceServicesProvider);
                  ref.invalidate(myWorkShiftInfoProvider);
                },
                child: state.when(
                  loading: () => LayoutBuilder(
                    builder: (context, constraints) => ListView(
                      children: [
                        SizedBox(
                          height: constraints.maxHeight,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  error: (error, _) => ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _ErrorCard(
                        message: humanizeError(error),
                        onRetry: () => ref.invalidate(attendanceStateProvider),
                      ),
                    ],
                  ),
                  data: (value) => _body(value),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(AttendanceState value) {
    if (!value.attendanceRequired || !value.selfPunchEnabled) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _InfoBanner(
            icon: Icons.verified_user_outlined,
            title: 'لا توجد بصمة شخصية لهذا الحساب',
            body: 'سياسة الحساب الحالية لا تتطلب حضورًا أو انصرافًا شخصيًا.',
          ),
          const SizedBox(height: 16),
          _QuickLinksRow(working: _working, onMissionTap: _openMissionSheet),
        ],
      );
    }

    final action = value.suggestedAction == 'CHECK_OUT'
        ? 'CHECK_OUT'
        : 'CHECK_IN';
    final isSecondSessionCheckIn = value.isSplitShift &&
        action == 'CHECK_IN' &&
        value.todayCheckOutAt != null;
    final isSecondSessionCheckOut = value.isSplitShift &&
        action == 'CHECK_OUT' &&
        value.checkInCount >= 2;

    final actionLabel = action == 'CHECK_IN'
        ? (isSecondSessionCheckIn ? 'تسجيل حضور (الفترة الثانية)' : 'تسجيل الحضور')
        : (isSecondSessionCheckOut
            ? 'تسجيل انصراف (الفترة الثانية)'
            : (value.isSplitShift ? 'تسجيل انصراف (استراحة)' : 'تسجيل الانصراف'));
    final actionIcon = action == 'CHECK_IN' ? Icons.login : Icons.logout;

    // 0439 / 0588: اكتمل اليوم (حضور + انصراف).
    // بالنسبة للوردية المجزأة (Split Shift): لا يُقفل اليوم عند انصراف الاستراحة، بل يستمر حتى اكتمال الفترتين.
    final dayCompleted = value.suggestedAction == 'DAY_COMPLETED' ||
        (value.todayCheckOutAt != null && (!value.isSplitShift || value.checkInCount >= 2));

    // 0450 (مُعدّل بطلب الإدارة): زر البصمة يبقى ظاهراً دائماً (حضور/انصراف)
    // وبطاقات المأمورية إضافية فوقه لا بديلة عنه:
    // approved → بطاقة بدء المأمورية (تُحسب حضوراً)، in_progress → بطاقة
    // جارية بانتظار الإنهاء (الإنهاء = عودة للمجمع + موقع نطاق المجمع)،
    // وبعد الإنهاء يبقى زر الانصراف العادي متاحاً حتى بعد نهاية الدوام.
    final mission = value.missionToday;
    Widget? missionCard;
    if (!dayCompleted && mission != null) {
      if (mission.execStatus == 'approved') {
        missionCard = _MissionStartCard(
          type: mission.type,
          startTime: mission.startTime,
          working: _working,
          onStart: () => _startMission(mission.requestId),
        );
      } else if (mission.execStatus == 'in_progress') {
        missionCard = _MissionInProgressCard(
          startedAt: mission.startedAt,
          working: _working,
          onEnd: () => _endMissionFlow(mission),
        );
      } else if (mission.execStatus == 'pending') {
        missionCard = _MissionPendingCard(
          type: mission.type,
          working: _working,
          onStart: () => _startMission(mission.requestId),
        );
      }
    }

    final currentShift = ref.watch(myWorkShiftInfoProvider).asData?.value.currentShift;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(attendanceStateProvider);
        ref.invalidate(myAttendanceServicesProvider);
        ref.invalidate(myWorkShiftInfoProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
        // ── بطاقة المأمورية (إضافية — لا تحجب زر البصمة) ──
        if (missionCard != null) ...[
          missionCard,
          const SizedBox(height: 14),
        ],

        // ── إرشاد قفل الشاشة عند عدم ضبطه والجهاز غير مسجل بعد ──
        if (!value.hasActiveLocalDevice && _deviceLockConfigured == false) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.statusWarning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.statusWarning.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.statusWarning,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تأمين الجهاز موصى به',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.statusWarning,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يُفضّل تفعيل بصمة أو قفل شاشة (نقش أو PIN) لتعزيز حماية حضورك، ويمكنك أيضاً تفعيل الحضور بربط هذا الهاتف مباشرة.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // ── بطاقة الإجراء الرئيسية ──
        if (dayCompleted)
          _DayCompletedCard(
            checkIn: value.todayCheckInAt,
            checkOut: value.todayCheckOutAt,
          )
        else
          _PunchCard(
            actionLabel: actionLabel,
            actionIcon: actionIcon,
            isCheckIn: action == 'CHECK_IN',
            hasActiveDevice: value.hasActiveLocalDevice,
            devicePending: value.localDeviceStatus == 'pending',
            canPunch: value.canPunch,
            working: _working,
            onRegister: _register,
            onPunch: () => _punch(action),
            currentShift: currentShift,
          ),
        const SizedBox(height: 14),

        // ── بطاقة حالة اليوم ──
        _TodayStatusCard(
          state: value,
          deviceLockConfigured: _deviceLockConfigured,
          currentShift: currentShift,
        ),
        const SizedBox(height: 14),

        // ── بند فترات العمل (الورديات المرنة) واختيار واعتماد الفترة الأساسية ──
        const _WorkShiftSection(),
        const SizedBox(height: 14),

        // V20: تصحيحات الحضور داخل صفحة البصمة — لا حاجة لصفحة منفصلة.
        const _CorrectionsSection(),
        const SizedBox(height: 14),

        // ── روابط سريعة ──
        _QuickLinksRow(working: _working, onMissionTap: _openMissionSheet),
        const SizedBox(height: 14),

        // ── ملاحظة أمان مختصرة ──
        const _SecurityNote(),
      ],
      ),
    );
  }

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
    setState(() => _working = true);
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
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _punch(String action, {bool skipDialog = false}) async {
    // حارس إعادة الدخول: يمنع أي طلب بصمة ثانٍ أثناء وجود طلب قيد التنفيذ
    // (من زر ثانٍ أو إعادة محاولة عند الاستئناف) — تجنّب إرسال حضور مكرر.
    if (_working) return;
    if (!skipDialog) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            action == 'CHECK_IN'
                ? 'تأكيد تسجيل الحضور'
                : 'تأكيد تسجيل الانصراف',
          ),
          content: const Text(
            'سيتم قراءة موقعك الحالي وطلب بصمة أو نقش الجهاز للتحقق.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    setState(() => _working = true);
    try {
      final result = await ref
          .read(mobileCommandsProvider)
          .punchAttendanceLocal(eventType: action);

      // الخادم يرجع ok: false عند رفض العملية (خارج النطاق، تكرار، إلخ)
      if (result['ok'] != true) {
        if (mounted) {
          final errorCode = result['error'] as String? ?? 'unknown_error';
          // أخطاء الإعدادات (نطاق جغرافي غير معرّف) — بانر معلوماتي برتقالي.
          // أخطاء الانتهاك (خارج النطاق، موقع مزيف) — بانر أحمر.
          final isConfigIssue =
              errorCode == 'attendance_geofence_not_configured';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_humanizePunchError(errorCode)),
              backgroundColor: isConfigIssue
                  ? AppColors.statusWarning
                  : AppColors.statusDanger,
            ),
          );
        }
        return;
      }

      // punchAttendanceLocal() already invalidates the relevant providers.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'CHECK_IN'
                  ? 'تم تسجيل الحضور بنجاح ✓'
                  : 'تم تسجيل الانصراف بنجاح ✓',
            ),
            backgroundColor: AppColors.statusSuccess,
          ),
        );
      }
    } on GpsDisabledException {
      if (mounted) {
        setState(() => _issueKind = _LocationIssueKind.gpsOff);
        final opened = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الموقع مغلق'),
            content: const Text('يرجى تفعيل خدمة الموقع (GPS) للمتابعة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('تفعيل الموقع'),
              ),
            ],
          ),
        );
        if (opened == true) {
          _pendingRetry = _PendingRetry.punch(action);
          await Geolocator.openLocationSettings();
        } else {
          if (!mounted) return;
          setState(() {
            _issueKind = null;
            _pendingRetry = null;
          });
        }
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        if (e.isDeniedForever) {
          setState(() => _issueKind = _LocationIssueKind.deniedForever);
          final opened = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('صلاحية الموقع مرفوضة'),
              content: const Text(
                'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('فتح الإعدادات'),
                ),
              ],
            ),
          );
          if (opened == true) {
            _pendingRetry = _PendingRetry.punch(action);
            await Geolocator.openAppSettings();
          } else {
            if (!mounted) return;
            setState(() {
              _issueKind = null;
              _pendingRetry = null;
            });
          }
        } else {
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            // أُعيد التعيين قبل الاستدعاء التكراري لتجاوز حارس إعادة الدخول،
            // ثم يُنتظَر الطلب الداخلي حتى يكتمل قبل أن يُعيد finally تفعيل الزر.
            if (mounted) setState(() => _working = false);
            await _punch(action, skipDialog: true);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى منح صلاحية الموقع للمتابعة.')),
          );
        }
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (error, stack) {
      _showErrorFeedback(error, stack, contextTag: '_punch');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// إظهار رسائل الخطأ بوضوح وتوجيه الموظف إذا كانت المشكلة في قفل الشاشة أو البصمة.
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
      case 'invalid_attendance_location':
        return 'إحداثيات الموقع غير صالحة. أعد المحاولة.';
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
    setState(() => _working = true);
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
      if (mounted) setState(() => _working = false);
    }
  }

  /// إنهاء المأمورية مع تقرير إلزامي — بعده يعود زر الانصراف تلقائيًا
  /// أو يكتمل اليوم إن تجاوز الوقت نهاية الدوام (انصراف تلقائي).
  Future<void> _endMissionFlow(MissionToday mission) async {
    final reportController = TextEditingController();
    final outcomeController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag_circle_outlined),
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
                'سجّل تقرير إنجاز المهمة، ثم اختر ما إذا كنت تريد تسجيل بصمة انصراف أم استمرار الدوام.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reportController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'تقرير المأمورية *',
                  hintText: 'ماذا أنجزت في المهمة؟',
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
              FilledButton.icon(
                onPressed: () {
                  if (reportController.text.trim().length < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال تقرير لا يقل عن 3 أحرف.')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, true);
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('إنهاء المأمورية وبصمة انصراف'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.statusSuccess,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  if (reportController.text.trim().length < 3) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال تقرير لا يقل عن 3 أحرف.')),
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, false);
                },
                icon: const Icon(Icons.task_alt_rounded),
                label: const Text('إنهاء فقط (استمرار الدوام)'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
    setState(() => _working = true);
    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(
            requestId: mission.requestId,
            report: reportText,
            outcome: outcomeText.isEmpty ? null : outcomeText,
            withCheckout: result,
          );
      ref.invalidate(attendanceStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result
                  ? 'تم إنهاء المأمورية وتسجيل بصمة انصراف بنجاح.'
                  : 'تم إنهاء المأمورية فقط واستمرار الدوام بنجاح.',
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
      if (mounted) setState(() => _working = false);
    }
  }
}

/// العملية المعلقة بعد العودة من إعدادات GPS — لإعادة المحاولة تلقائياً.
class _PendingRetry {
  const _PendingRetry._(this.action);
  static const register = _PendingRetry._(null);
  factory _PendingRetry.punch(String action) => _PendingRetry._(action);
  final String? action;
}

/// نوع مشكلة الموقع — يحدد سلوك إعادة المحاولة التلقائية.
enum _LocationIssueKind { gpsOff, deniedForever }

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة البصمة الرئيسية — إجراء واحد واضح
// ═══════════════════════════════════════════════════════════════════════════════

class _PunchCard extends StatelessWidget {
  const _PunchCard({
    required this.actionLabel,
    required this.actionIcon,
    required this.isCheckIn,
    required this.hasActiveDevice,
    required this.devicePending,
    required this.canPunch,
    required this.working,
    required this.onRegister,
    required this.onPunch,
    this.currentShift,
  });

  final String actionLabel;
  final IconData actionIcon;
  final bool isCheckIn;
  final bool hasActiveDevice;
  final bool devicePending;
  final bool canPunch;
  final bool working;
  final VoidCallback onRegister;
  final VoidCallback onPunch;
  final CurrentWorkShift? currentShift;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // البانر العلوي
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isCheckIn
                    ? [AppColors.brandPrimary, const Color(0xFF1E3A8A)]
                    : [const Color(0xFFD97706), const Color(0xFF9A3412)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isCheckIn ? Icons.fingerprint : Icons.logout_rounded,
                  color: Colors.white,
                  size: 40,
                ),
                const SizedBox(height: 10),
                Text(
                  actionLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (currentShift != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCheckIn ? Icons.schedule_rounded : Icons.timer_outlined,
                          size: 13,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isCheckIn
                                ? (currentShift!.hasTodayPermit
                                    ? 'الوردية: ${currentShift!.formattedStartTime} · إذن حتى ${currentShift!.formattedActiveStartTime} (سماح ${currentShift!.formattedActiveGraceEndTime})'
                                    : 'الوردية: ${currentShift!.formattedStartTime} · سماح حتى ${currentShift!.formattedGraceEndTime}')
                                : (currentShift!.hasTodayPermit && currentShift!.todayPermit?.isEarlyDeparture == true
                                    ? 'الانصراف المصرح: ${currentShift!.formattedActiveEndTime} (إذن -${currentShift!.todayPermit!.permitMinutes} د)'
                                    : 'الانصراف الرسمي: ${currentShift!.formattedEndTime}'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  isCheckIn
                      ? 'بصمة أو نقش + الموقع → يتم التحقق تلقائياً'
                      : 'تسجيل انصراف اليوم وحفظ ساعات العمل',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          // زر الإجراء
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildActionButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (devicePending) {
      return _WarningBanner(
        icon: Icons.hourglass_top_outlined,
        text: 'جهازك مسجل وينتظر موافقة المسؤول',
      );
    }

    if (!hasActiveDevice) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: working ? null : onRegister,
          icon: working
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.fingerprint),
          label: const Text('تفعيل الحضور بأمان الجهاز'),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: working || !canPunch ? null : onPunch,
        icon: working
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(actionIcon),
        label: Text(actionLabel),
        style: FilledButton.styleFrom(
          backgroundColor: isCheckIn ? null : const Color(0xFFD97706),
          foregroundColor: isCheckIn ? null : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 0450: بطاقات دورة يوم المأمورية — تحل محل زر البصمة في يوم التكليف
// ═══════════════════════════════════════════════════════════════════════════════

class _MissionStartCard extends StatelessWidget {
  const _MissionStartCard({
    required this.type,
    required this.startTime,
    required this.working,
    required this.onStart,
  });

  final String type;
  final String? startTime;
  final bool working;
  final VoidCallback onStart;

  String get _typeLabel => switch (type) {
    'convoy' => 'تكليف قافلة',
    'fundraising' => 'يوم ترفيهي (فاندي)',
    _ => 'مأمورية',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.tour_outlined, color: scheme.onPrimary, size: 38),
                const SizedBox(height: 10),
                Text(
                  'لديك $_typeLabel اليوم',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  startTime == null
                      ? 'ابدأ مباشرة من نقطة المهمة — لا حاجة للمرور بمقر الجمعية.'
                      : 'الوقت المتوقع للبداية: $startTime — لا حاجة للمرور بمقر الجمعية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: working ? null : onStart,
                icon: working
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('بدء المأمورية الآن'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissionPendingCard extends StatelessWidget {
  const _MissionPendingCard({
    required this.type,
    this.working = false,
    this.onStart,
  });

  final String type;
  final bool working;
  final VoidCallback? onStart;

  String get _typeLabel => switch (type) {
    'convoy' => 'تكليف قافلة',
    'fundraising' => 'يوم ترفيهي (فاندي)',
    _ => 'مأمورية عمل خارجية',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.statusWarning.withValues(alpha: 0.4)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.statusWarning.withValues(alpha: 0.08),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarning.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.hourglass_top_rounded,
                    color: AppColors.statusWarning,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'طلب $_typeLabel قيد المراجعة',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'طلب المأمورية مرفوع وبانتظار اعتماد الإدارة. يمكنك بدؤها الآن مباشرة عند الانطلاق.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onStart != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: working ? null : onStart,
                  icon: working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_rounded),
                  label: const Text('بدء المأمورية الآن'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.statusWarning,
                    foregroundColor: Colors.black87,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MissionInProgressCard extends StatelessWidget {
  const _MissionInProgressCard({
    required this.startedAt,
    required this.working,
    required this.onEnd,
  });

  final DateTime? startedAt;
  final bool working;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startedLabel = startedAt == null
        ? null
        : DateFormat('h:mm a', 'ar').format(startedAt!.toLocal());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: scheme.tertiaryContainer),
            child: Column(
              children: [
                Icon(
                  Icons.route_outlined,
                  color: scheme.onTertiaryContainer,
                  size: 38,
                ),
                const SizedBox(height: 10),
                Text(
                  'تم بدء المأمورية',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  startedLabel == null
                      ? 'بانتظار الانتهاء — عند العودة إلى مقر الجمعية أنهِ المهمة.'
                      : 'بدأت الساعة $startedLabel — بانتظار الانتهاء عند العودة لمقر الجمعية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: working ? null : onEnd,
                icon: working
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.task_alt_rounded),
                label: const Text('إنهاء المأمورية والعودة للمقر'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة اكتمال اليوم — تظهر مكان زر البصمة بعد حضور وانصراف اليوم
// ═══════════════════════════════════════════════════════════════════════════════

class _DayCompletedCard extends StatelessWidget {
  const _DayCompletedCard({required this.checkIn, required this.checkOut});
  final DateTime? checkIn;
  final DateTime? checkOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final formatter = DateFormat('h:mm a', 'ar');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.statusSuccess, scheme.secondary],
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: scheme.onPrimary,
                  size: 38,
                ),
                const SizedBox(height: 10),
                Text(
                  'اكتمل حضورك وانصرافك اليوم',
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ستظهر بصمتك من جديد بعد منتصف الليل',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _StatusRow(
                  icon: Icons.login,
                  label: 'الحضور',
                  value: checkIn == null
                      ? '—'
                      : formatter.format(checkIn!.toLocal()),
                  valueColor: AppColors.statusSuccess,
                ),
                const SizedBox(height: 8),
                _StatusRow(
                  icon: Icons.logout,
                  label: 'الانصراف',
                  value: checkOut == null
                      ? '—'
                      : formatter.format(checkOut!.toLocal()),
                  valueColor: AppColors.statusSuccess,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقة حالة اليوم — تُخفي الحقول الفارغة
// ═══════════════════════════════════════════════════════════════════════════════

class _TodayStatusCard extends StatelessWidget {
  const _TodayStatusCard({
    required this.state,
    this.deviceLockConfigured,
    this.currentShift,
  });
  final AttendanceState state;
  final bool? deviceLockConfigured;
  final CurrentWorkShift? currentShift;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('h:mm a', 'ar');
    final scheme = Theme.of(context).colorScheme;
    final hasEvent = state.lastEventType != null;
    final hasStatus =
        state.todayStatus != null &&
        state.todayStatus != '—' &&
        state.todayStatus!.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'حالة اليوم',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                if (hasStatus)
                  MobileStatusPill(state.todayStatus!)
                else if (state.missionToday != null)
                  MobileStatusPill(state.missionToday!.type)
                else
                  const MobileStatusPill('not_recorded'),
              ],
            ),
            const SizedBox(height: 12),

            // أوقات الحضور والانصراف ومقارنتها بالوردية المعتمدة
            if (state.todayCheckInAt != null || state.todayCheckOutAt != null || currentShift != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.login_rounded,
                                size: 16,
                                color: state.todayCheckInAt != null
                                    ? AppColors.statusSuccess
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'وقت الحضور',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.todayCheckInAt != null
                                ? formatter.format(state.todayCheckInAt!.toLocal())
                                : 'لم يُسجل بعد',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: state.todayCheckInAt != null ? scheme.onSurface : scheme.onSurfaceVariant,
                            ),
                          ),
                          if (currentShift != null) ...[
                            const SizedBox(height: 3),
                            Builder(
                              builder: (_) {
                                if (state.todayCheckInAt != null) {
                                  final metric = _computeShiftDisciplineMetric(
                                    startTime: currentShift!.activeStartTime,
                                    graceInMinutes: currentShift!.graceInMinutes,
                                    todayCheckInAt: state.todayCheckInAt,
                                    hasPermit: currentShift!.hasTodayPermit,
                                    permitMinutes: currentShift!.todayPermit?.permitMinutes,
                                    originalStartTime: currentShift!.startTime,
                                  );
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(metric.icon, size: 12, color: metric.color),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          metric.badgeLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w700,
                                            color: metric.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                } else {
                                  return Text(
                                    currentShift!.hasTodayPermit && currentShift!.todayPermit?.isLateArrival == true
                                        ? 'المقرر: ${currentShift!.formattedActiveStartTime} (إذن +${currentShift!.todayPermit!.permitMinutes} د)'
                                        : 'المقرر: ${currentShift!.formattedStartTime}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 42,
                      color: scheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.logout_rounded,
                                size: 16,
                                color: state.todayCheckOutAt != null
                                    ? AppColors.statusSuccess
                                    : AppColors.statusWarning,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'وقت الانصراف',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.todayCheckOutAt != null
                                ? formatter.format(state.todayCheckOutAt!.toLocal())
                                : (state.todayCheckInAt != null ? 'قيد العمل الآن' : '—'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: state.todayCheckOutAt != null
                                  ? scheme.onSurface
                                  : (state.todayCheckInAt != null ? AppColors.statusWarning : scheme.onSurfaceVariant),
                            ),
                          ),
                          if (currentShift != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              state.todayCheckOutAt != null
                                  ? 'نهاية الوردية: ${currentShift!.formattedActiveEndTime}'
                                  : (currentShift!.hasTodayPermit && currentShift!.todayPermit?.isEarlyDeparture == true
                                      ? 'المقرر: ${currentShift!.formattedActiveEndTime} (إذن -${currentShift!.todayPermit!.permitMinutes} د)'
                                      : 'المقرر: ${currentShift!.formattedEndTime}'),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // الوردية المعتمدة
            if (currentShift != null) ...[
              _StatusRow(
                icon: Icons.schedule_rounded,
                label: 'الوردية المعتمدة',
                value: '${currentShift!.name} (${currentShift!.formattedRange})',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (currentShift!.hasTodayPermit && currentShift!.todayPermit != null) ...[
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD97706).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFD97706).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          currentShift!.todayPermit!.isLateArrival
                              ? 'إذن +${currentShift!.todayPermit!.durationLabel}'
                              : 'إذن -${currentShift!.todayPermit!.durationLabel}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFD97706),
                          ),
                        ),
                      ),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (currentShift!.isAssigned ? AppColors.statusSuccess : scheme.primary).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        currentShift!.badgeLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: currentShift!.isAssigned ? AppColors.statusSuccess : scheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // التكليف الميداني الحالي إن وُجد
            if (state.missionToday != null) ...[
              _StatusRow(
                icon: Icons.location_on_outlined,
                label: 'التكليف الميداني',
                value: switch (state.missionToday!.type) {
                  'convoy' => 'قافلة معتمدة',
                  'fundraising' => 'يوم ترفيهي (فاندي)',
                  _ => 'مأمورية عمل خارجية',
                },
                valueColor: switch (state.missionToday!.type) {
                  'convoy' => const Color(0xFF7C3AED),
                  'fundraising' => const Color(0xFF0D9488),
                  _ => const Color(0xFF2563EB),
                },
              ),
              const SizedBox(height: 8),
            ],

            // أمان الجهاز
            _StatusRow(
              icon: Icons.lock_outline,
              label: 'أمان الجهاز',
              value: !state.hasActiveLocalDevice
                  ? 'غير مفعلة'
                  : (deviceLockConfigured == false)
                      ? 'مفعلة (قفل الشاشة مطلوب)'
                      : 'مفعلة',
              valueColor: !state.hasActiveLocalDevice
                  ? scheme.error
                  : (deviceLockConfigured == false)
                      ? AppColors.statusWarning
                      : AppColors.statusSuccess,
            ),

            // آخر عملية (فقط عند وجود بيانات)
            if (hasEvent) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: state.lastEventType == 'CHECK_IN'
                    ? Icons.login
                    : Icons.logout,
                label: 'آخر عملية',
                value:
                    '${state.lastEventType == 'CHECK_IN' ? 'حضور' : 'انصراف'}'
                    '${state.lastEventAt != null ? ' · ${formatter.format(state.lastEventAt!.toLocal())}' : ''}',
              ),
            ],

            // حالة التحقق (فقط عند وجودها)
            if (state.lastEventStatus != null) ...[
              const SizedBox(height: 8),
              _StatusRow(
                icon: Icons.verified_outlined,
                label: 'التحقق',
                trailing: MobileStatusPill(state.lastEventStatus!),
              ),
            ],

            // رسالة عندما لا يوجد أي نشاط
            if (!hasEvent && !hasStatus) ...[
              const SizedBox(height: 4),
              Text(
                'لم تُسجَّل أي عملية حضور اليوم',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
        const Spacer(),
        if (trailing != null)
          trailing!
        else
          Text(
            value ?? '—',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: valueColor,
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// روابط سريعة — شبكة 4 أزرار مدمجة
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow({required this.working, this.onMissionTap});
  final bool working;
  final VoidCallback? onMissionTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _QuickLink(
          icon: Icons.history_rounded,
          label: 'السجل',
          onTap: working
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AttendanceHistoryPage(),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        _QuickLink(
          icon: Icons.calendar_month_outlined,
          label: 'كشف الشهر',
          onTap: working
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MonthlyAttendanceStatementPage(),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        _QuickLink(
          icon: Icons.work_outline_rounded,
          label: 'طلب مأمورية',
          onTap: working ? null : onMissionTap,
        ),
        const SizedBox(width: 8),
        _QuickLink(
          icon: Icons.devices_outlined,
          label: 'أجهزتي',
          onTap: working
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PasskeyDevicesPage()),
                ),
        ),
      ],
    );
  }
}

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: scheme.primary, size: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

// ═══════════════════════════════════════════════════════════════════════════════
// ملاحظة الأمان — مدمجة وغير مشتتة
// ═══════════════════════════════════════════════════════════════════════════════

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'التحقق (بصمة أو نقش) يتم داخل الجهاز فقط، ثم يتحقق الخادم من الجلسة والجهاز والموقع.',
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// بطاقات مساعدة
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: scheme.error),
            const SizedBox(height: 10),
            const Text(
              'تعذر تحميل حالة الحضور',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.statusWarning.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.statusWarning, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.statusWarning,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    ),
  );
}

/// ═══════════════════════════════════════════════════════════════════════════════
/// بند فترات العمل (الورديات المرنة) واختيار واعتماد الفترة الأساسية للموظف
/// ═══════════════════════════════════════════════════════════════════════════════

class _WorkShiftSection extends ConsumerWidget {
  const _WorkShiftSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftInfoAsync = ref.watch(myWorkShiftInfoProvider);
    final attendanceStateAsync = ref.watch(attendanceStateProvider);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'فترة العمل والورديات',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'الوردية الأساسية المعتمدة لحساب التأخير والخصومات',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text(
                    'تغيير الفترة',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  onPressed: () => showWorkShiftSelectionSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 12),
            shiftInfoAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
              error: (err, _) => Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'الدوام الأساسي المعتمد: 10:00 ص – 06:00 م (سماح 15 د)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              data: (info) {
                final current = info.currentShift;
                final pending = info.pendingRequest;
                final shiftIcon = _getShiftIcon(current.code);
                final shiftColor = _getShiftColor(current.code, scheme);
                final liveStatus = _computeShiftLiveStatus(
                  startTime: current.activeStartTime,
                  endTime: current.activeEndTime,
                  graceInMinutes: current.graceInMinutes,
                  hasPermit: current.hasTodayPermit,
                  permitActiveStartTime: current.activeStartTime,
                );
                final todayCheckIn = attendanceStateAsync.asData?.value.todayCheckInAt;
                final disciplineMetric = _computeShiftDisciplineMetric(
                  startTime: current.activeStartTime,
                  graceInMinutes: current.graceInMinutes,
                  todayCheckInAt: todayCheckIn,
                  hasPermit: current.hasTodayPermit,
                  permitMinutes: current.todayPermit?.permitMinutes,
                  originalStartTime: current.startTime,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // بطاقة الوردية المعتمدة بتصميم راقٍ
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            shiftColor.withValues(alpha: 0.07),
                            scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                          ],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: shiftColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: shiftColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(shiftIcon, size: 18, color: shiftColor),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  current.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: current.isAssigned
                                      ? AppColors.statusSuccess.withValues(alpha: 0.14)
                                      : scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: current.isAssigned
                                        ? AppColors.statusSuccess.withValues(alpha: 0.4)
                                        : scheme.primary.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      current.isAssigned
                                          ? Icons.verified_rounded
                                          : Icons.schedule_outlined,
                                      size: 14,
                                      color: current.isAssigned
                                          ? AppColors.statusSuccess
                                          : scheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      current.badgeLabel,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: current.isAssigned
                                            ? AppColors.statusSuccess
                                            : scheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _ShiftDetailChip(
                                icon: Icons.login_rounded,
                                label: 'الحضور: ${current.formattedStartTime}',
                                color: scheme.primary,
                              ),
                              _ShiftDetailChip(
                                icon: Icons.hourglass_empty_rounded,
                                label: 'سماح: ${current.graceInMinutes} دقيقة',
                                color: AppColors.statusWarning,
                              ),
                              _ShiftDetailChip(
                                icon: Icons.logout_rounded,
                                label: 'الانصراف: ${current.formattedEndTime}',
                                color: scheme.secondary,
                              ),
                            ],
                          ),

                          // شارة وبطاقة إذن الحضور أو الانصراف المعتمد لليوم (إن وُجد)
                          if (current.todayPermit != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD97706).withValues(alpha: 0.09),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFD97706).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFD97706).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.verified_user_rounded,
                                      size: 18,
                                      color: Color(0xFFD97706),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                current.todayPermit!.isLateArrival
                                                    ? 'إذن حضور معتمد (+${current.todayPermit!.durationLabel})'
                                                    : 'إذن انصراف مبكر معتمد (${current.todayPermit!.durationLabel})',
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFFB45309),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.statusSuccess.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'معتمد لليوم',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.statusSuccess,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          current.todayPermit!.isLateArrival
                                              ? 'الموعد المصرح بعد الإذن: ${current.formattedActiveStartTime} · فترة السماح حتى ${current.formattedActiveGraceEndTime}'
                                              : 'الانصراف المصرح: ${current.formattedActiveEndTime}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: scheme.onSurface,
                                          ),
                                        ),
                                        if (current.todayPermit!.title.isNotEmpty &&
                                            current.todayPermit!.title != 'إذن معتمد') ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'السبب: ${current.todayPermit!.title}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),

                          // شريط ومؤشر الحالة اللحظية للوردية
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: liveStatus.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: liveStatus.color.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(liveStatus.icon, size: 16, color: liveStatus.color),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        liveStatus.statusLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: liveStatus.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        liveStatus.detailLabel,
                                        textAlign: TextAlign.end,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (liveStatus.progress != null) ...[
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: liveStatus.progress,
                                      backgroundColor: liveStatus.color.withValues(alpha: 0.15),
                                      valueColor: AlwaysStoppedAnimation<Color>(liveStatus.color),
                                      minHeight: 4,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── بطاقة احتساب التأخير والانضباط والخصومات الفردية ──
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: disciplineMetric.color.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: disciplineMetric.color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(disciplineMetric.icon, size: 16, color: disciplineMetric.color),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        disciplineMetric.statusTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: disciplineMetric.color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: disciplineMetric.color.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        disciplineMetric.badgeLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: disciplineMetric.color,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  disciplineMetric.statusSubtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // ── مخطط محطات الوردية اليومية ──
                          _ShiftTimelineBar(
                            startTime: current.startTime,
                            endTime: current.endTime,
                            graceInMinutes: current.graceInMinutes,
                            hasPermit: current.hasTodayPermit,
                            permitMinutes: current.todayPermit?.permitMinutes,
                            effectiveStartTime: current.hasTodayPermit ? current.formattedActiveStartTime : null,
                            effectiveGraceEndTime: current.hasTodayPermit ? current.formattedActiveGraceEndTime : null,
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'تُحتسب التأخيرات والخصومات الفردية بناءً على مواعيد هذه الوردية المعتمدة.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _showShiftPolicyDialog(context),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.info_outline, size: 13, color: scheme.primary),
                                      const SizedBox(width: 2),
                                      Text(
                                        'السياسة',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // إشعار طلب التغيير المعلق (إن وجد) بتصميم تفاعلي ينقل مباشرة للتفاصيل
                    if (pending != null) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MobileRequestDetailPage(
                                requestId: pending.requestId,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.statusWarning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.statusWarning.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.hourglass_top_rounded,
                                size: 18,
                                color: AppColors.statusWarning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'طلب قيد المراجعة والاعتماد: ${pending.requestedShiftName ?? 'تغيير الوردية'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.statusWarning,
                                      ),
                                    ),
                                    if (pending.reason != null && pending.reason!.trim().isNotEmpty)
                                      Text(
                                        pending.reason!.trim(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.statusWarning.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'بانتظار الإدارة',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.statusWarning,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// عرض نافذة منبثقة تشرح سياسة احتساب الحضور والتأخير بناءً على الوردية
void _showShiftPolicyDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Icon(Icons.policy_rounded, color: Theme.of(ctx).colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'سياسة فترات العمل والتأخير',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PolicyPoint(
              number: '1',
              title: 'الوردية المعتمدة رسمياً',
              body: 'تحدد مواعيد الحضور والانصراف المقررة لك، ويتم تطبيق السياسة الفردية بناءً عليها.',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '2',
              title: 'فترة السماح (15 دقيقة)',
              body: 'لا يُحتسب أي تأخير أو خصم إذا سجّلت حضورك خلال فترة السماح (مثلاً حتى 10:15 ص للدوام الأساسي).',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '3',
              title: 'احتساب التأخير الفردي',
              body: 'عند تجاوز فترة السماح، يُحتسب إجمالي دقائق التأخير بدءاً من موعد بداية الوردية الرسمي (مثلاً من 10:00 ص).',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '4',
              title: 'تغيير فترة العمل',
              body: 'يمكنك اختيار فترة عمل بديلة وتقديم طلب مبرر، وتُطبق المواعيد الجديدة فور اعتمادها من الإدارة.',
            ),
            SizedBox(height: 10),
            _PolicyPoint(
              number: '5',
              title: 'أذونات الحضور والانصراف',
              body: 'أذونات التأخير المعتمدة تؤخر موعد الحضور الرسمي بمقدار مدة الإذن (مثلاً إذن ساعتان يؤخر الحضور من 11:00 ص إلى 1:00 م)، وتُطبق فترة السماح والخصومات الفردية بناءً على الموعد المصرح الجديد.',
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('حسناً، فهمت'),
        ),
      ],
    ),
  );
}

class _PolicyPoint extends StatelessWidget {
  const _PolicyPoint({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftDetailChip extends StatelessWidget {
  const _ShiftDetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShiftLiveStatus {
  const _ShiftLiveStatus({
    required this.statusLabel,
    required this.detailLabel,
    required this.color,
    required this.icon,
    this.progress,
    this.isGraceActive = false,
  });

  final String statusLabel;
  final String detailLabel;
  final Color color;
  final IconData icon;
  final double? progress;
  final bool isGraceActive;
}

_ShiftLiveStatus _computeShiftLiveStatus({
  required String startTime,
  required String endTime,
  required int graceInMinutes,
  bool hasPermit = false,
  String? permitActiveStartTime,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final effectiveStart = hasPermit && permitActiveStartTime != null ? permitActiveStartTime : startTime;
  final startParts = effectiveStart.split(':');
  final endParts = endTime.split(':');
  if (startParts.length < 2 || endParts.length < 2) {
    return const _ShiftLiveStatus(
      statusLabel: 'فترة العمل المعتمدة',
      detailLabel: 'وفق الجدول المحدد',
      color: Color(0xFF2563EB),
      icon: Icons.schedule_rounded,
    );
  }
  final startH = int.tryParse(startParts[0]) ?? 10;
  final startM = int.tryParse(startParts[1]) ?? 0;
  final endH = int.tryParse(endParts[0]) ?? 18;
  final endM = int.tryParse(endParts[1]) ?? 0;

  final todayStart = DateTime(current.year, current.month, current.day, startH, startM);
  final todayGraceEnd = todayStart.add(Duration(minutes: graceInMinutes));
  final todayEnd = DateTime(current.year, current.month, current.day, endH, endM);

  if (current.isBefore(todayStart)) {
    final diff = todayStart.difference(current);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    final timeText = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
    return _ShiftLiveStatus(
      statusLabel: hasPermit ? 'إذن حضور سارٍ حالياً' : 'الدوام لم يبدأ بعد',
      detailLabel: hasPermit
          ? 'يبدأ الحضور المصرح بعد $timeText (وفق الإذن المعتمد)'
          : 'يبدأ حضور الوردية بعد $timeText',
      color: hasPermit ? const Color(0xFFD97706) : const Color(0xFF0284C7),
      icon: hasPermit ? Icons.verified_user_rounded : Icons.access_time_rounded,
    );
  } else if (current.isBefore(todayGraceEnd)) {
    final diff = todayGraceEnd.difference(current);
    final mins = diff.inMinutes;
    return _ShiftLiveStatus(
      statusLabel: 'فترة السماح نشطة حالياً',
      detailLabel: hasPermit
          ? 'متبقي $mins دقيقة قبل احتساب التأخير بعد الإذن'
          : 'متبقي $mins دقيقة قبل احتساب التأخير الفردي',
      color: AppColors.statusWarning,
      icon: Icons.hourglass_top_rounded,
      isGraceActive: true,
      progress: 0.08,
    );
  } else if (current.isBefore(todayEnd)) {
    final totalDuration = todayEnd.difference(todayStart).inMinutes;
    final elapsed = current.difference(todayStart).inMinutes;
    final progress = totalDuration > 0 ? (elapsed / totalDuration).clamp(0.0, 1.0) : 0.5;
    final diff = todayEnd.difference(current);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    final timeText = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
    return _ShiftLiveStatus(
      statusLabel: 'ساعات العمل الرسمية جارية',
      detailLabel: 'متبقي حتى نهاية الوردية: $timeText',
      color: AppColors.statusSuccess,
      icon: Icons.work_history_rounded,
      progress: progress,
    );
  } else {
    return const _ShiftLiveStatus(
      statusLabel: 'انتهت ساعات الوردية لليوم',
      detailLabel: 'اكتملت ساعات الدوام المقررة رسمياً',
      color: Color(0xFF059669),
      icon: Icons.task_alt_rounded,
      progress: 1.0,
    );
  }
}

class _ShiftDisciplineMetric {
  const _ShiftDisciplineMetric({
    required this.statusTitle,
    required this.statusSubtitle,
    required this.badgeLabel,
    required this.color,
    required this.icon,
    required this.isDeductionRisk,
    this.consumedGraceMinutes,
    this.lateMinutes,
  });

  final String statusTitle;
  final String statusSubtitle;
  final String badgeLabel;
  final Color color;
  final IconData icon;
  final bool isDeductionRisk;
  final int? consumedGraceMinutes;
  final int? lateMinutes;
}

_ShiftDisciplineMetric _computeShiftDisciplineMetric({
  required String startTime,
  required int graceInMinutes,
  required DateTime? todayCheckInAt,
  bool hasPermit = false,
  int? permitMinutes,
  String? originalStartTime,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final startParts = startTime.split(':');
  final startH = startParts.length >= 2 ? (int.tryParse(startParts[0]) ?? 10) : 10;
  final startM = startParts.length >= 2 ? (int.tryParse(startParts[1]) ?? 0) : 0;

  final referenceDate = todayCheckInAt?.toLocal() ?? current;
  final todayStart = DateTime(referenceDate.year, referenceDate.month, referenceDate.day, startH, startM);
  final todayGraceEnd = todayStart.add(Duration(minutes: graceInMinutes));

  if (todayCheckInAt != null) {
    final checkIn = todayCheckInAt.toLocal();
    if (checkIn.isBefore(todayStart) || checkIn.isAtSameMomentAs(todayStart)) {
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit ? 'حضور منضبط مع الإذن المعتمد ✓' : 'حضور مبكر ومنضبط تماماً ✓',
        statusSubtitle: hasPermit
            ? 'سُجل الحضور في موعد الإذن المصرح به · 0 دقيقة تأخير و 0 خصومات فردية'
            : 'سُجل الحضور في موعد الوردية الرسمي · 0 دقيقة تأخير و 0 خصومات فردية',
        badgeLabel: 'منضبط 100%',
        color: AppColors.statusSuccess,
        icon: Icons.verified_rounded,
        isDeductionRisk: false,
        lateMinutes: 0,
        consumedGraceMinutes: 0,
      );
    } else if (checkIn.isBefore(todayGraceEnd) || checkIn.isAtSameMomentAs(todayGraceEnd)) {
      final consumed = checkIn.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'حضور ضمن فترة السماح للإذن ($consumed دقيقة)'
            : 'حضور ضمن فترة السماح ($consumed دقيقة)',
        statusSubtitle: hasPermit
            ? 'سُجل الحضور في نطاق سماح الإذن المعتمد ($graceInMinutes د) · لا يُحتسب أي خصم أو تأخير مالي'
            : 'سُجل الحضور في نطاق السماح المعتمد ($graceInMinutes د) · لا يُحتسب أي خصم أو تأخير مالي',
        badgeLabel: 'سماح معتمد',
        color: const Color(0xFFD97706),
        icon: Icons.shield_outlined,
        isDeductionRisk: false,
        consumedGraceMinutes: consumed,
        lateMinutes: 0,
      );
    } else {
      final lateMins = checkIn.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'تأخير بعد انتهاء الإذن: $lateMins دقيقة'
            : 'تأخير فردي مسجل: $lateMins دقيقة',
        statusSubtitle: hasPermit
            ? 'تم تجاوز موعد الإذن المعتمد ($startTime) وفترة السماح ($graceInMinutes د) · يُطبق الخصم الفردي من الموعد المصرح'
            : 'تم استنفاد فترة السماح ($graceInMinutes د) · يُطبق الخصم الفردي من موعد الوردية وفق لائحة العمل',
        badgeLabel: hasPermit ? 'تأخير بعد الإذن' : 'تأخير مسجل',
        color: const Color(0xFFDC2626),
        icon: Icons.warning_amber_rounded,
        isDeductionRisk: true,
        lateMinutes: lateMins,
      );
    }
  } else {
    if (current.isBefore(todayStart)) {
      final diff = todayStart.difference(current);
      final hours = diff.inHours;
      final mins = diff.inMinutes % 60;
      final timeStr = hours > 0 ? '$hours ساعة و$mins دقيقة' : '$mins دقيقة';
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'إذن حضور سارٍ · يبدأ الحضور بعد $timeStr'
            : 'الدوام لم يبدأ بعد · يبدأ بعد $timeStr',
        statusSubtitle: hasPermit
            ? 'لديك إذن حضور معتمد (+${permitMinutes ?? 120} د) · موعدك المصرح حتى $startTime (سماح $graceInMinutes د)'
            : 'سجل حضورك في الموعد المعتمد للاستفادة من فترة السماح وضمان انضباط تام دون خصومات',
        badgeLabel: hasPermit ? 'إذن سارٍ' : 'بانتظار البدء',
        color: hasPermit ? const Color(0xFFD97706) : const Color(0xFF0284C7),
        icon: hasPermit ? Icons.verified_user_rounded : Icons.schedule_rounded,
        isDeductionRisk: false,
      );
    } else if (current.isBefore(todayGraceEnd)) {
      final remaining = todayGraceEnd.difference(current).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: 'فترة السماح نشطة حالياً · متبقي $remaining دقيقة',
        statusSubtitle: hasPermit
            ? 'سارع بتسجيل الحضور للاستفادة من رصيد السماح بعد الإذن المعتمد وتفادي الخصم الفردي'
            : 'سارع بتسجيل الحضور الآن للاستفادة من رصيد السماح وتفادي احتساب التأخير الفردي',
        badgeLabel: 'سماح جارٍ',
        color: const Color(0xFFD97706),
        icon: Icons.hourglass_top_rounded,
        isDeductionRisk: false,
        consumedGraceMinutes: graceInMinutes - remaining,
      );
    } else {
      final lateSoFar = current.difference(todayStart).inMinutes;
      return _ShiftDisciplineMetric(
        statusTitle: hasPermit
            ? 'تأخير بعد الإذن: $lateSoFar دقيقة'
            : 'تأخير غير مسجل: $lateSoFar دقيقة عن الوردية',
        statusSubtitle: hasPermit
            ? 'تم استنفاد فترة السماح بعد الإذن المعتمد · سارع بتسجيل الحضور للحد من دقائق الخصم الفردي'
            : 'تم استنفاد فترة السماح ($graceInMinutes د) · سارع بتسجيل الحضور للحد من دقائق الخصم الفردي',
        badgeLabel: hasPermit ? 'تأخير بعد الإذن' : 'تأخير جارٍ',
        color: const Color(0xFFDC2626),
        icon: Icons.alarm_on_rounded,
        isDeductionRisk: true,
        lateMinutes: lateSoFar,
      );
    }
  }
}

class _ShiftTimelineBar extends StatelessWidget {
  const _ShiftTimelineBar({
    required this.startTime,
    required this.endTime,
    required this.graceInMinutes,
    this.hasPermit = false,
    this.permitMinutes,
    this.effectiveStartTime,
    this.effectiveGraceEndTime,
  });

  final String startTime;
  final String endTime;
  final int graceInMinutes;
  final bool hasPermit;
  final int? permitMinutes;
  final String? effectiveStartTime;
  final String? effectiveGraceEndTime;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final startDisplay = startTime.length >= 5 ? startTime.substring(0, 5) : startTime;
    final endDisplay = endTime.length >= 5 ? endTime.substring(0, 5) : endTime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline_rounded, size: 14, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasPermit
                      ? 'مخطط محطات الوردية بعد تطبيق الإذن المعتمد:'
                      : 'مخطط محطات الوردية اليومية والاحتساب:',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (hasPermit)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD97706).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'معدل بالإذن',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasPermit && effectiveStartTime != null) ...[
            Row(
              children: [
                Expanded(
                  child: _TimelinePoint(
                    time: startDisplay,
                    label: 'الوردية الأصلية',
                    sublabel: 'الموعد الأساسي',
                    color: scheme.onSurfaceVariant,
                    isFirst: true,
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: '+${permitMinutes ?? 120} د',
                    label: 'إذن معتمد',
                    sublabel: 'إزاحة رسمية',
                    color: const Color(0xFFD97706),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: effectiveStartTime!,
                    label: 'الموعد المصرح',
                    sublabel: 'سماح $graceInMinutes د',
                    color: const Color(0xFF2563EB),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: endDisplay,
                    label: 'الانصراف',
                    sublabel: 'نهاية اليوم',
                    color: const Color(0xFF059669),
                    isLast: true,
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _TimelinePoint(
                    time: startDisplay,
                    label: 'بداية الوردية',
                    sublabel: 'بدء الدوام',
                    color: scheme.primary,
                    isFirst: true,
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: '+$graceInMinutes د',
                    label: 'نهاية السماح',
                    sublabel: '0 خصم',
                    color: const Color(0xFFD97706),
                  ),
                ),
                Expanded(
                  child: _TimelinePoint(
                    time: endDisplay,
                    label: 'الانصراف المقرر',
                    sublabel: 'اكتملت الساعات',
                    color: const Color(0xFF059669),
                    isLast: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelinePoint extends StatelessWidget {
  const _TimelinePoint({
    required this.time,
    required this.label,
    required this.sublabel,
    required this.color,
    this.isFirst = false,
    this.isLast = false,
  });

  final String time;
  final String label;
  final String sublabel;
  final Color color;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: isFirst
                  ? const SizedBox.shrink()
                  : Container(
                      height: 2,
                      color: color.withValues(alpha: 0.35),
                    ),
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            Expanded(
              child: isLast
                  ? const SizedBox.shrink()
                  : Container(
                      height: 2,
                      color: color.withValues(alpha: 0.35),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          sublabel,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

IconData _getShiftIcon(String code) {
  switch (code.toUpperCase()) {
    case 'SHIFT_9_5':
      return Icons.wb_sunny_rounded;
    case 'SHIFT_11_7':
      return Icons.nights_stay_rounded;
    case 'SHIFT_CLINIC_3_11':
      return Icons.medical_services_outlined;
    case 'OFFICIAL':
    default:
      return Icons.business_center_rounded;
  }
}

Color _getShiftColor(String code, ColorScheme scheme) {
  switch (code.toUpperCase()) {
    case 'SHIFT_9_5':
      return const Color(0xFFD97706);
    case 'SHIFT_11_7':
      return const Color(0xFF7C3AED);
    case 'SHIFT_CLINIC_3_11':
      return const Color(0xFF0D9488);
    case 'OFFICIAL':
    default:
      return scheme.primary;
  }
}

/// نافذة سفلية سلسة لاختيار وتغيير فترة العمل والتنقل بين الورديات
Future<void> showWorkShiftSelectionSheet(BuildContext context, WidgetRef ref) async {
  final shiftInfo = ref.read(myWorkShiftInfoProvider).asData?.value;
  final available = shiftInfo?.availableShifts ?? [];
  final current = shiftInfo?.currentShift;
  final pending = shiftInfo?.pendingRequest;

  String? selectedShiftId = current?.id;
  final reasonController = TextEditingController();
  bool submitting = false;

  final quickReasons = const [
    '🚌 مواعيد المواصلات',
    '👨‍👩‍👧 ظروف أسرية وعائلية',
    '👥 تنسيق مع جدول الفريق',
    '📚 التزامات دراسية/شخصية',
    '⚡ ذروة الإنتاجية اليومية',
  ];

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final scheme = Theme.of(ctx).colorScheme;
        final viewInsets = MediaQuery.of(ctx).viewInsets.bottom;
        final selectedShift = available.cast<MobileWorkShift?>().firstWhere(
              (s) => s?.id == selectedShiftId,
              orElse: () => null,
            );

        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, viewInsets + 24),
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
                      color: scheme.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.schedule_rounded, color: scheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'اختيار وتغيير فترة العمل',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'اختر الفترة الأنسب لجدولك اليومي للاعتماد من الإدارة',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'إغلاق',
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                if (pending != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.statusWarning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.statusWarning.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: AppColors.statusWarning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لديك طلب قيد المراجعة حالياً (${pending.requestedShiftName ?? 'تغيير الوردية'}). إرسال طلب جديد سيحدّث بيانات طلبك.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                // الورديات المتاحة
                if (available.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ...available.map((shift) {
                    final isSelected = selectedShiftId == shift.id;
                    final isCurrent = current?.id == shift.id;
                    final shiftIcon = _getShiftIcon(shift.code);
                    final shiftColor = _getShiftColor(shift.code, scheme);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          setModalState(() => selectedShiftId = shift.id);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? shiftColor.withValues(alpha: 0.08)
                                : scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? shiftColor
                                  : scheme.outlineVariant.withValues(alpha: 0.3),
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: shiftColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(shiftIcon, color: shiftColor, size: 20),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            shift.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                              color: isSelected
                                                  ? shiftColor
                                                  : scheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (isCurrent) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.statusSuccess.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'فترتك الحالية',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.statusSuccess,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        _ShiftMiniChip(
                                          label: 'الحضور: ${shift.formattedStartTime}',
                                          color: scheme.primary,
                                        ),
                                        _ShiftMiniChip(
                                          label: 'سماح: ${shift.graceInMinutes} د',
                                          color: AppColors.statusWarning,
                                        ),
                                        _ShiftMiniChip(
                                          label: 'الانصراف: ${shift.formattedEndTime}',
                                          color: scheme.secondary,
                                        ),
                                      ],
                                    ),
                                    if (shift.description != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        shift.description!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // مؤشر اختيار دائري راقٍ
                              Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected ? shiftColor : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? shiftColor
                                        : scheme.outlineVariant,
                                    width: isSelected ? 0 : 2,
                                  ),
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                // ملخص الانتقال عند اختيار وردية مختلفة
                if (selectedShiftId != null &&
                    selectedShiftId != current?.id &&
                    selectedShift != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.swap_horiz_rounded, size: 16, color: scheme.primary),
                            const SizedBox(width: 6),
                            Text(
                              'ملخص التغيير المطلوب:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'الوردية الحالية:\n${current?.formattedRange ?? ''}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Icon(Icons.arrow_back_rounded, size: 16, color: scheme.primary),
                            Expanded(
                              child: Text(
                                'الوردية الجديدة:\n${selectedShift.formattedRange}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'تنويه: عند اعتماد الطلب، سيتم احتساب وقت الحضور والتأخير بناءً على مواعيد الوردية الجديدة فوراً.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // رقائق أسباب سريعة (Quick Justification Chips)
                const SizedBox(height: 4),
                Text(
                  'أسباب شائعة للاختيار السريع:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: quickReasons.map((qr) {
                    return InkWell(
                      onTap: () {
                        setModalState(() {
                          final clean = qr.replaceAll(RegExp(r'[^\u0621-\u064A\s]'), '').trim();
                          if (reasonController.text.trim().isEmpty) {
                            reasonController.text = clean;
                          } else if (!reasonController.text.contains(clean)) {
                            reasonController.text = '${reasonController.text.trim()} - $clean';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          qr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 10),
                TextField(
                  controller: reasonController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'سبب طلب التغيير (اختياري)',
                    hintText: 'اكتب مبررات تغيير فترة العمل لمساعدة الإدارة في سرعة الاعتماد...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: submitting || selectedShiftId == null || selectedShiftId == current?.id
                      ? null
                      : () async {
                          setModalState(() => submitting = true);
                          try {
                            await ref.read(mobileCommandsProvider).requestShiftChange(
                                  shiftId: selectedShiftId!,
                                  reason: reasonController.text.trim(),
                                );
                            ref.invalidate(myWorkShiftInfoProvider);
                            ref.invalidate(attendanceStateProvider);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم إرسال طلب تغيير فترة العمل للاعتماد بنجاح'),
                                  backgroundColor: AppColors.statusSuccess,
                                ),
                              );
                            }
                          } catch (e) {
                            setModalState(() => submitting = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(humanizeError(e)),
                                  backgroundColor: AppColors.statusDanger,
                                ),
                              );
                            }
                          }
                        },
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    submitting
                        ? 'جارٍ إرسال الطلب...'
                        : (selectedShiftId == current?.id
                            ? 'هذه هي فترتك الحالية بالفعل'
                            : 'إرسال طلب تغيير الوردية للاعتماد'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _ShiftMiniChip extends StatelessWidget {
  const _ShiftMiniChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

/// V20: قسم تصحيحات وبلاغات الحضور المطور — تصميم عصري، تصفية ذكية، واختصارات فورية
class _CorrectionsSection extends ConsumerStatefulWidget {
  const _CorrectionsSection();

  @override
  ConsumerState<_CorrectionsSection> createState() => _CorrectionsSectionState();
}

class _CorrectionsSectionState extends ConsumerState<_CorrectionsSection> {
  int _filterIndex = 0; // 0: الكل, 1: قيد المراجعة, 2: معتمدة, 3: مرفوضة

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(myAttendanceServicesProvider);
    final corrections = services.asData?.value.corrections ?? [];
    final scheme = Theme.of(context).colorScheme;

    final pendingList = corrections.where((c) => c.status == 'pending').toList();
    final approvedList = corrections.where((c) => c.status == 'approved').toList();
    final rejectedList = corrections.where((c) => c.status == 'rejected').toList();

    final filteredList = switch (_filterIndex) {
      1 => pendingList,
      2 => approvedList,
      3 => rejectedList,
      _ => corrections,
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fact_check_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تصحيحات وبلاغات الحضور',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        corrections.isEmpty
                            ? 'معالجة نسيان البصمة وأخطاء التسجيل'
                            : '${corrections.length} ${corrections.length == 1 ? 'طلب مسجل' : corrections.length == 2 ? 'طلبين مسجلين' : 'طلبات مسجلة'}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text(
                    'طلب تصحيح',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  onPressed: () => showAttendanceCorrectionSheet(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── شريط الاختصارات السريعة لنسيان البصمة ──
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _QuickCorrectionActionChip(
                  icon: Icons.login_rounded,
                  label: 'نسيت حضور اليوم؟',
                  color: const Color(0xFF2563EB),
                  onTap: () => showAttendanceCorrectionSheet(
                    context,
                    ref,
                    initialWorkDate: DateTime.now(),
                    initialType: 'missing_check_in',
                  ),
                ),
                _QuickCorrectionActionChip(
                  icon: Icons.logout_rounded,
                  label: 'نسيت انصراف الأمس؟',
                  color: const Color(0xFFD97706),
                  onTap: () => showAttendanceCorrectionSheet(
                    context,
                    ref,
                    initialWorkDate: DateTime.now().subtract(const Duration(days: 1)),
                    initialType: 'missing_check_out',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 10),

            // ── تبويبات التصفية التفاعلية ──
            if (corrections.isNotEmpty) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterTabChip(
                      label: 'الكل',
                      count: corrections.length,
                      isSelected: _filterIndex == 0,
                      onTap: () => setState(() => _filterIndex = 0),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'قيد المراجعة',
                      count: pendingList.length,
                      color: AppColors.statusWarning,
                      isSelected: _filterIndex == 1,
                      onTap: () => setState(() => _filterIndex = 1),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'معتمدة',
                      count: approvedList.length,
                      color: AppColors.statusSuccess,
                      isSelected: _filterIndex == 2,
                      onTap: () => setState(() => _filterIndex = 2),
                    ),
                    const SizedBox(width: 6),
                    _FilterTabChip(
                      label: 'مرفوضة',
                      count: rejectedList.length,
                      color: AppColors.statusDanger,
                      isSelected: _filterIndex == 3,
                      onTap: () => setState(() => _filterIndex = 3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            if (services.isLoading && !services.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (corrections.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 20,
                      color: AppColors.statusSuccess.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لا توجد طلبات تصحيح مسجلة حالياً — يمكنك تقديم بلاغ تصحيح فوري عند نسيان الحضور أو الانصراف.',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (filteredList.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    switch (_filterIndex) {
                      1 => 'لا توجد طلبات قيد المراجعة حالياً ✓',
                      2 => 'لا توجد طلبات معتمدة في هذا القسم',
                      3 => 'سجلك نظيف — لا توجد أي طلبات تصحيح مرفوضة ✓',
                      _ => 'لا توجد طلبات تطابق هذا التبويب',
                    },
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else ...[
              ...filteredList.take(3).map((c) {
                final statusColor = switch (c.status) {
                  'approved' => AppColors.statusSuccess,
                  'rejected' => AppColors.statusDanger,
                  _ => AppColors.statusWarning,
                };
                final statusIcon = switch (c.status) {
                  'approved' => Icons.check_circle_rounded,
                  'rejected' => Icons.cancel_rounded,
                  _ => Icons.hourglass_top_rounded,
                };
                final typeIcon = _getCorrectionTypeIcon(c.type);
                final typeColor = _getCorrectionTypeColor(c.type);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AttendanceCorrectionDetailPage(correctionId: c.id),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(typeIcon, size: 16, color: typeColor),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _formatCorrectionType(c.type),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                MobileStatusPill(c.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.event_outlined, size: 13, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat('EEEE، d MMMM', 'ar').format(c.workDate),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                if (c.requestedCheckIn != null || c.requestedCheckOut != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: scheme.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      c.requestedCheckIn != null
                                          ? 'المطلوب: ${DateFormat('h:mm a', 'ar').format(c.requestedCheckIn!.toLocal())}'
                                          : 'المطلوب: ${DateFormat('h:mm a', 'ar').format(c.requestedCheckOut!.toLocal())}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (c.reason.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  c.reason.trim(),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            // ── رد الإدارة / المراجع إن وُجد ──
                            if (c.reviewNote != null && c.reviewNote!.trim().isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(statusIcon, size: 14, color: statusColor),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'رد الإدارة: ${c.reviewNote!.trim()}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (corrections.length > 3) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    icon: const Icon(Icons.history_rounded, size: 16),
                    label: Text(
                      'عرض كافة طلبات التصحيح (${corrections.length})',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MobileAttendanceServicesPage(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static String _formatCorrectionType(String type) => switch (type) {
    'missing_check_in' => 'بصمة حضور ناقصة',
    'missing_check_out' => 'بصمة انصراف ناقصة',
    'wrong_time' => 'تصحيح وقت البصمة',
    'wrong_status' => 'تصحيح حالة اليوم',
    'mission' => 'مأمورية عمل',
    'leave' => 'طلب إجازة',
    _ => 'تصحيح حضور',
  };

  static IconData _getCorrectionTypeIcon(String type) => switch (type) {
    'missing_check_in' => Icons.login_rounded,
    'missing_check_out' => Icons.logout_rounded,
    'wrong_time' => Icons.update_rounded,
    'wrong_status' => Icons.rule_rounded,
    'mission' => Icons.work_history_rounded,
    'leave' => Icons.beach_access_rounded,
    _ => Icons.edit_calendar_rounded,
  };

  static Color _getCorrectionTypeColor(String type) => switch (type) {
    'missing_check_in' => const Color(0xFF2563EB),
    'missing_check_out' => const Color(0xFFD97706),
    'wrong_time' => const Color(0xFF7C3AED),
    'wrong_status' => const Color(0xFF0284C7),
    'mission' => const Color(0xFF0D9488),
    'leave' => const Color(0xFFE11D48),
    _ => const Color(0xFF2563EB),
  };
}

class _FilterTabChip extends StatelessWidget {
  const _FilterTabChip({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.color,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeColor = color ?? scheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : scheme.outlineVariant.withValues(alpha: 0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCorrectionActionChip extends StatelessWidget {
  const _QuickCorrectionActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
