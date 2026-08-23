import 'dart:async';
import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/core/widgets/gps_preflight_banner.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_corrections_section.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/attendance_history_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/monthly_attendance_statement_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/passkey_devices_page.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_widgets.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/mobile_attendance_services_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

class MobileAttendancePage extends ConsumerStatefulWidget {
  const MobileAttendancePage({super.key});

  @override
  ConsumerState<MobileAttendancePage> createState() =>
      _MobileAttendancePageState();
}

class _MobileAttendancePageState extends ConsumerState<MobileAttendancePage>
    with WidgetsBindingObserver {
  bool _working = false;

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
    });
  }

  /// عند العودة من إعدادات الموقع أو التطبيق — إعادة المحاولة تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
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
      _register(skipDialog: true);
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
      appBar: AppBar(title: const Text('الحضور والانصراف')),
      body: SafeArea(
        child: Column(
          children: [
            const GpsPreflightBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(attendanceStateProvider),
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
    // V20: تسجيل تلقائي للجهاز — لا حاجة لخطوة يدوية.
    if (value.attendanceRequired &&
        value.selfPunchEnabled &&
        !value.hasActiveLocalDevice &&
        value.localDeviceStatus != 'pending' &&
        !_working) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _register(skipDialog: true);
      });
    }
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
          _QuickLinksRow(working: _working),
        ],
      );
    }

    final action = value.suggestedAction == 'CHECK_OUT'
        ? 'CHECK_OUT'
        : 'CHECK_IN';
    final actionLabel = action == 'CHECK_IN'
        ? 'تسجيل الحضور'
        : 'تسجيل الانصراف';
    final actionIcon = action == 'CHECK_IN' ? Icons.login : Icons.logout;

    // 0439: اكتمل اليوم (حضور + انصراف) → نخفي زر البصمة ونعرض التوقيتين.
    // بعد منتصف الليل يمرّر الخادم اليوم الجديد فتعود القيم فارغة ويظهر الزر.
    final dayCompleted = value.todayCheckOutAt != null;

    // 0450: يوم مأمورية/تكليف — زر البصمة يتحول لدورة المأمورية كاملة:
    // approved → زر بدء، in_progress → بطاقة جارية بانتظار الإنهاء،
    // completed قبل نهاية الدوام → يعود زر الانصراف العادي تلقائيًا
    // (لأن الخادم سجّل أول حضور = توقيت البدء)، وبعد نهاية الدوام →
    // اكتمال تلقائي بلا بصمة إضافية.
    final mission = value.missionToday;
    if (!dayCompleted && mission != null) {
      if (mission.execStatus == 'approved') {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MissionStartCard(
              type: mission.type,
              startTime: mission.startTime,
              working: _working,
              onStart: () => _startMission(mission.requestId),
            ),
            const SizedBox(height: 14),
            _TodayStatusCard(state: value),
            const SizedBox(height: 14),
            _QuickLinksRow(working: _working),
          ],
        );
      }
      if (mission.execStatus == 'in_progress') {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _MissionInProgressCard(
              startedAt: mission.startedAt,
              working: _working,
              onEnd: () => _endMissionFlow(mission),
            ),
            const SizedBox(height: 14),
            _TodayStatusCard(state: value),
            const SizedBox(height: 14),
            _QuickLinksRow(working: _working),
          ],
        );
      }
      // completed && !autoCheckout ⇒ تسقط للأسفل: زر انصراف عادي.
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          ),
        const SizedBox(height: 14),

        // ── بطاقة حالة اليوم ──
        _TodayStatusCard(state: value),
        const SizedBox(height: 14),

        // V20: تصحيحات الحضور داخل صفحة البصمة — لا حاجة لصفحة منفصلة.
        _CorrectionsSection(),
        const SizedBox(height: 14),

        // ── روابط سريعة ──
        _QuickLinksRow(working: _working),
        const SizedBox(height: 14),

        // ── ملاحظة أمان مختصرة ──
        const _SecurityNote(),
        const SizedBox(height: 14),

        // ── طلبات تصحيح الحضور ──
        AttendanceCorrectionsSection(),
      ],
    );
  }

  Future<void> _register({bool skipDialog = false}) async {
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
    } on GpsDisabledException {
      if (mounted) {
        setState(() => _issueKind = _LocationIssueKind.gpsOff);
        final opened = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('الموقع مغلق'),
            content: const Text(
              'يرجى تفعيل خدمة الموقع (GPS) لتتمكن من تسجيل الجهاز.',
            ),
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
          _pendingRetry = _PendingRetry.register;
          await Geolocator.openLocationSettings();
        } else {
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
            _pendingRetry = _PendingRetry.register;
            await Geolocator.openAppSettings();
          } else {
            setState(() {
              _issueKind = null;
              _pendingRetry = null;
            });
          }
        } else {
          // صلاحية مرفوضة (ليست نهائية) — نطلبها مباشرة
          final perm = await Geolocator.requestPermission();
          if (!mounted) return;
          if (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse) {
            _register(skipDialog: true);
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
      if (mounted) {
        if (kDebugMode) {
          debugPrint('[_register] ${error.runtimeType}: $error\n$stack');
        }
        final msg = error.toString();
        final isCancelled =
            msg.contains('إلغاء') ||
            msg.toLowerCase().contains('cancel') ||
            msg.toLowerCase().contains('dismissed');
        final text = isCancelled
            ? 'تم إلغاء التحقق.'
            : msg.contains('الجهاز لا يدعم')
            ? 'فعّل قفل الشاشة (نقش أو PIN) من إعدادات الجهاز.'
            : humanizeError(error, stack);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
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
      if (mounted) {
        if (kDebugMode) {
          debugPrint('[_punch] ${error.runtimeType}: $error\n$stack');
        }
        final msg = error.toString();
        final isCancelled =
            msg.contains('إلغاء') ||
            msg.toLowerCase().contains('cancel') ||
            msg.toLowerCase().contains('dismissed');
        final text = isCancelled
            ? 'تم إلغاء التحقق.'
            : humanizeError(error, stack);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _working = false);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('إنهاء المأمورية'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'عند العودة إلى المقر أكّد إنهاء المهمة مع تقرير موجز.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reportController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'تقرير المأمورية *',
                  hintText: 'ماذا أنجزت في المهمة؟',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: outcomeController,
                decoration: const InputDecoration(
                  labelText: 'النتيجة (اختياري)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لاحقًا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('إنهاء المأمورية'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_working) return;
    setState(() => _working = true);
    try {
      await ref
          .read(mobileCommandsProvider)
          .endMission(
            requestId: mission.requestId,
            report: reportController.text.trim(),
            outcome: outcomeController.text.trim().isEmpty
                ? null
                : outcomeController.text.trim(),
          );
      ref.invalidate(attendanceStateProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إنهاء المأمورية بنجاح.'),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                colors: [scheme.primary, scheme.secondary],
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.fingerprint, color: scheme.onPrimary, size: 38),
                const SizedBox(height: 10),
                Text(
                  actionLabel,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'بصمة أو نقش + الموقع → يتم التحقق تلقائياً',
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: 0.7),
                    fontSize: 13,
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
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(actionIcon),
        label: Text(actionLabel),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
    'fundraising' => 'مهمة فاندي',
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
                      ? 'ابدأ مباشرة من نقطة المهمة — لا حاجة للمرور بالمقر.'
                      : 'الوقت المتوقع للبداية: $startTime — لا حاجة للمرور بالمقر.',
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
                      ? 'بانتظار الانتهاء — عند العودة إلى المقر أنهِ المهمة.'
                      : 'بدأت الساعة $startedLabel — بانتظار الانتهاء عند العودة للمقر.',
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
  const _TodayStatusCard({required this.state});
  final AttendanceState state;

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
                if (hasStatus) MobileStatusPill(state.todayStatus!),
              ],
            ),
            const SizedBox(height: 12),

            // أمان الجهاز
            _StatusRow(
              icon: Icons.lock_outline,
              label: 'أمان الجهاز',
              value: state.hasActiveLocalDevice ? 'مفعلة' : 'غير مفعلة',
              valueColor: state.hasActiveLocalDevice
                  ? AppColors.statusSuccess
                  : scheme.error,
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
// روابط سريعة — شبكة 3 أزرار مدمجة
// ═══════════════════════════════════════════════════════════════════════════════

class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow({required this.working});
  final bool working;

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
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(height: 6),
                Text(
                  label,
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

/// V20: قسم تصحيحات الحضور — مدمج داخل صفحة البصمة بدل صفحة منفصلة.
/// يعرض آخر طلبات التصحيح وزر "طلب تصحيح جديد".
class _CorrectionsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(myAttendanceServicesProvider);
    final corrections = services.asData?.value.corrections ?? [];
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.edit_calendar_rounded,
                  size: 22,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'تصحيحات الحضور',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                  label: const Text('طلب تصحيح'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MobileAttendanceServicesPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            if (corrections.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Text(
                    'لا توجد طلبات تصحيح سابقة',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ...corrections
                  .take(3)
                  .map(
                    (c) => ListTile(
                      dense: true,
                      leading: Icon(
                        c.status == 'approved'
                            ? Icons.check_circle_outline
                            : c.status == 'rejected'
                            ? Icons.cancel_outlined
                            : Icons.pending_actions,
                        size: 20,
                        color: c.status == 'approved'
                            ? AppColors.statusSuccess
                            : c.status == 'rejected'
                            ? AppColors.statusDanger
                            : AppColors.statusWarning,
                      ),
                      title: Text(
                        DateFormat('yyyy/MM/dd').format(c.workDate),
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        c.reason.isNotEmpty ? c.reason : c.type,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        c.status == 'approved'
                            ? 'موافق'
                            : c.status == 'rejected'
                            ? 'مرفوض'
                            : 'معلّق',
                        style: TextStyle(
                          fontSize: 11,
                          color: c.status == 'approved'
                              ? AppColors.statusSuccess
                              : c.status == 'rejected'
                              ? AppColors.statusDanger
                              : AppColors.statusWarning,
                        ),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
