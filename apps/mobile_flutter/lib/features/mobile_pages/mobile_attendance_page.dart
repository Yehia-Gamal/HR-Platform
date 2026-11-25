import 'dart:async';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/network/offline_sync_queue.dart';
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
import 'package:ahla_shabab_management_os/core/time/app_time.dart';

part 'attendance/attendance_page_actions.dart';
part 'attendance/attendance_punch_flow.dart';
part 'attendance/attendance_punch_and_readiness_cards.dart';
part 'attendance/attendance_mission_and_day_cards.dart';
part 'attendance/attendance_today_status_card.dart';
part 'attendance/attendance_quick_links_and_banners.dart';
part 'attendance/attendance_work_shift_section.dart';
part 'attendance/attendance_work_shift_active_card.dart';
part 'attendance/attendance_shift_metrics.dart';
part 'attendance/attendance_shift_timeline.dart';
part 'attendance/attendance_shift_selection_sheet.dart';
part 'attendance/attendance_corrections_section.dart';
part 'attendance/attendance_penalty_compensate_banner.dart';

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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
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

    // حسم الإجراء: إذا كانت القيمة CHECK_OUT أو CHECK_IN صريحة نعتمدها،
    // أما إذا كانت قيمة أخرى (مثل MISSION_IN_PROGRESS أو غيرها) وكان الموظف حاضراً بالفعل ولم ينصرف،
    // فالإجراء الحتمي للبصمة هو الانصراف CHECK_OUT لتفادي أي حضور مكرر.
    final action = value.suggestedAction == 'CHECK_OUT'
        ? 'CHECK_OUT'
        : (value.suggestedAction == 'CHECK_IN'
            ? 'CHECK_IN'
            : ((value.todayCheckInAt != null && value.todayCheckOutAt == null)
                ? 'CHECK_OUT'
                : 'CHECK_IN'));
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
    final isMissionInProgress = !dayCompleted && mission != null && mission.execStatus == 'in_progress';
    Widget? missionCard;
    if (!dayCompleted && mission != null) {
      if (mission.execStatus == 'approved') {
        missionCard = _MissionStartCard(
          type: mission.type,
          startTime: mission.startTime,
          working: _working,
          onStart: () => _startMission(mission.requestId),
          onCancel: () => _cancelMissionFlow(mission.requestId),
        );
      } else if (mission.execStatus == 'pending') {
        missionCard = _MissionPendingCard(
          type: mission.type,
          working: _working,
          onStart: () => _startMission(mission.requestId),
          onCancel: () => _cancelMissionFlow(mission.requestId),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
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
        if (dayCompleted) ...[
          if (value.todayCheckInAt != null)
            _PenaltyCompensateBanner(state: value, checkInAt: value.todayCheckInAt),
          _DayCompletedCard(
            checkIn: value.todayCheckInAt,
            checkOut: value.todayCheckOutAt,
          ),
        ] else if (isMissionInProgress) ...[
          _MissionInProgressCard(
            startedAt: mission.startedAt,
            working: _working,
            onEnd: () => _endMissionFlow(mission),
            onCancel: () => _cancelMissionFlow(mission.requestId),
          ),
        ] else ...[
          if (value.todayCheckInAt != null)
            _PenaltyCompensateBanner(state: value, checkInAt: value.todayCheckInAt),
          _PrePunchReadinessStrip(
            state: value,
            preflight: ref.watch(gpsPreflightProvider),
            onRefresh: () {
              ref.invalidate(gpsPreflightProvider);
              ref.invalidate(attendanceStateProvider);
            },
          ),
          const SizedBox(height: 10),
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
            todayCheckInAt: value.todayCheckInAt,
          ),
        ],
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

  void _updateUi(VoidCallback fn) {
    if (mounted) setState(fn);
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

