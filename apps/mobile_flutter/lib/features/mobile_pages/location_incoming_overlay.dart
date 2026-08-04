import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/video_verification_page.dart';
// V17 §9: video_verification_page removed — video permanently disabled.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// شاشة منبثقة كاملة تظهر فوق كل شيء عند ورود طلب موقع عاجل من الإدارة.
/// تُعرض عبر [LocationIncomingListener] الذي يراقب [pendingIncomingLocationRequestProvider].
class LocationIncomingOverlay extends ConsumerStatefulWidget {
  const LocationIncomingOverlay({
    required this.request,
    this.employeeId,
    super.key,
  });
  final MobileLocationRequest request;

  /// معرّف الموظف من جدول employees (وليس auth.uid) — مطلوب لمسار حفظ الفيديو.
  final String? employeeId;
  @override
  ConsumerState<LocationIncomingOverlay> createState() =>
      _LocationIncomingOverlayState();
}

class _LocationIncomingOverlayState
    extends ConsumerState<LocationIncomingOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulse;
  bool _busy = false;
  String? _status;
  String? _error;

  /// نوع مشكلة الموقع — لتحديد زر الإعدادات المناسب.
  _LocationIssueKind? _issueKind;

  /// هل سبق أن نجح respondLocation؟ لتجنب تكراره عند إعادة المحاولة بعد GPS.
  bool _accepted = false;
  static const _urgentPlatform = MethodChannel(
    'com.ahlashabab/urgent_notification',
  );

  Future<void> _stopUrgentAlarm() async {
    try {
      await _urgentPlatform.invokeMethod<void>('stopUrgentNotification', {
        'requestId': widget.request.id,
      });
    } catch (_) {
      // Older Android builds do not expose the native alarm service.
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _vibrateSeries();
    // أوقف المنبه الأصلي (Kotlin) فوراً عند ظهور شاشة Flutter
    // لمنع تداخل شاشتين + إيقاف الصوت المكرر.
    _stopUrgentAlarm();
  }

  void _vibrateSeries() {
    for (var i = 0; i < 5; i++) {
      Future<void>.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) HapticFeedback.heavyImpact();
      });
    }
  }

  /// عند العودة من إعدادات الموقع أو الصلاحيات، نعيد الفحص والإرسال تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _issueKind != null &&
        !_busy) {
      // تأخير صغير ليكتمل تفعيل GPS / الصلاحية في النظام
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && !_busy && _issueKind != null) {
          _recheckAndRetry();
        }
      });
    }
  }

  Future<void> _recheckAndRetry() async {
    // فحص حالة الخدمة والصلاحية معاً
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;
    if (!enabled) return; // لا تزال مغلقة — انتظر عودة أخرى

    final permission = await Geolocator.checkPermission();
    if (!mounted) return;
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      // صلاحية مرفوضة — حاول طلبها
      final newPerm = await Geolocator.requestPermission();
      if (!mounted) return;
      if (newPerm == LocationPermission.denied ||
          newPerm == LocationPermission.deniedForever) {
        return; // لا تزال مرفوضة
      }
    }

    // كلا الشرطين تحققا — امسح الخطأ وأعد الإرسال
    setState(() {
      _error = null;
      _issueKind = null;
    });
    _send();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _issueKind = null;
      _status = _accepted
          ? LocationService.phaseLabel(LocationPhase.acquiringLocation)
          : 'جاري قبول الطلب...';
    });
    try {
      if (!_accepted) {
        await ref
            .read(mobileCommandsProvider)
            .respondLocation(widget.request.id, true);
        _accepted = true;
      }

      final position = await LocationService.current(
        onPhase: (phase) {
          if (mounted) {
            setState(() => _status = LocationService.phaseLabel(phase));
          }
        },
      );

      if (!mounted) return;
      setState(() => _status = LocationService.phaseLabel(LocationPhase.reverseGeocoding));
      final address = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      // V17 §9: video path removed — needsVideo is always false.
      if (widget.request.isTracking) {
        // tracking mode — accept was enough; location_requests_page handles the rest
      } else {
        if (!mounted) return;
        setState(() => _status = 'جاري إرسال الموقع...');
        // رابط Google Maps للموقع الحالي
        final mapsUrl =
            'https://maps.google.com/?q=${position.latitude},${position.longitude}';
        if (widget.request.needsPoint) {
          await ref
              .read(mobileCommandsProvider)
              .submitLocationPoint(
                widget.request.id,
                latitude: position.latitude,
                longitude: position.longitude,
                accuracy: position.accuracy,
                altitude: position.altitude,
                speed: position.speed,
                heading: position.heading,
                isMock: position.isMocked,
                addressAr: '${address ?? ''} | $mapsUrl',
              );
        }
        if (widget.request.needsVideo) {
          final employeeId = widget.employeeId;
          if (employeeId == null || employeeId.isEmpty) {
            throw StateError('تعذر تحديد ملف الموظف لرفع فيديو التحقق.');
          }
          if (!mounted) return;
          setState(() => _status = 'افتح الكاميرا لتسجيل فيديو التحقق...');
          final completed = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => VideoVerificationPage(
                request: widget.request,
                employeeId: employeeId,
                position: position,
              ),
            ),
          );
          if (completed != true) {
            throw StateError('لم يكتمل تسجيل فيديو التحقق.');
          }
        }
      }
      await _stopUrgentAlarm();
      if (mounted) Navigator.of(context).pop(true);
    } on GpsDisabledException {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
          _issueKind = _LocationIssueKind.gpsOff;
        });
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = e.message;
          _issueKind = e.isDeniedForever
              ? _LocationIssueKind.deniedForever
              : _LocationIssueKind.permissionDenied;
        });
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = e.message;
          _issueKind = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _error = humanizeError(e);
          _issueKind = null;
        });
      }
    }
  }

  Future<void> _reject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض الطلب'),
        content: const Text('هل أنت متأكد من رفض طلب الموقع العاجل؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('رفض'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(mobileCommandsProvider)
          .respondLocation(widget.request.id, false);
      await _stopUrgentAlarm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(humanizeError(e))));
      }
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF140008),
        body: SafeArea(
          child: Column(
            children: [
              // ── حقل الطوارئ العلوي ─────────────────────────────────────
              Container(
                width: double.infinity,
                color: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'طلب موقع عاجل من الإدارة',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              // ── المحتوى الرئيسي ─────────────────────────────────────────
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // أيقونة نابضة
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) => Container(
                            width: 130 + _pulse.value * 22,
                            height: 130 + _pulse.value * 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.red.withValues(
                                alpha: 0.15 + _pulse.value * 0.18,
                              ),
                              border: Border.all(
                                color: Colors.red.withValues(
                                  alpha: 0.4 + _pulse.value * 0.4,
                                ),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.my_location_rounded,
                              size: 70,
                              color: Colors.red,
                            ),
                          ),
                        ),
                        const SizedBox(height: 36),
                        const Text(
                          'طلب تحقق من الموقع',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${widget.request.requesterName} يطلب التحقق من موقعك الآن',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white70,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Text(
                            _modeLabel(widget.request.mode),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_status != null) ...[
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white60,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _status!,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.red.shade900.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (_issueKind == _LocationIssueKind.gpsOff) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () =>
                                  Geolocator.openLocationSettings(),
                              icon: const Icon(Icons.gps_fixed_rounded),
                              label: const Text('فتح إعدادات الموقع'),
                            ),
                          ],
                          if (_issueKind ==
                              _LocationIssueKind.deniedForever) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Geolocator.openAppSettings(),
                              icon: const Icon(Icons.settings_rounded),
                              label: const Text('فتح إعدادات التطبيق'),
                            ),
                          ],
                          if (_issueKind ==
                              _LocationIssueKind.permissionDenied) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                final perm =
                                    await Geolocator.requestPermission();
                                if (!mounted) return;
                                if (perm == LocationPermission.always ||
                                    perm == LocationPermission.whileInUse) {
                                  setState(() {
                                    _error = null;
                                    _issueKind = null;
                                  });
                                  _send();
                                }
                              },
                              icon: const Icon(Icons.location_on_rounded),
                              label: const Text('منح صلاحية الموقع'),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              // ── أزرار الاستجابة ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: _busy
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              textStyle: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _send,
                            icon: const Icon(Icons.send_rounded, size: 26),
                            label: const Text('أرسل موقعي الآن'),
                          ),
                          const SizedBox(height: 14),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white38,
                              side: const BorderSide(color: Colors.white12),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: _reject,
                            child: const Text('رفض الطلب'),
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

  // V23: الفيديو ملغى نهائيًا (V12 §9) والتتبع مقصور على snapshot (V17).
  // الأوضاع القديمة تبقى للقراءة التاريخية فقط — تُعرض جميعها كـ"لقطة موقع فورية".
  String _modeLabel(String mode) => switch (mode) {
    'snapshot' => 'لقطة موقع فورية',
    _ => 'لقطة موقع فورية', // V17+: كل الأوضاع القديمة تُعامل كلقطة
  };
}

/// نوع مشكلة الموقع — يحدد زر الإعدادات المعروض.
enum _LocationIssueKind {
  gpsOff,
  permissionDenied,
  deniedForever,
}

/// مستمع يُستخدم داخل [WorkspaceScaffold] لعرض الشاشة المنبثقة عند ورود طلب.
class LocationIncomingListener extends ConsumerWidget {
  const LocationIncomingListener({
    required this.child,
    this.employeeId,
    super.key,
  });
  final Widget child;

  /// معرّف الموظف من جدول employees — يُمرَّر من AccessContext.employeeId.
  final String? employeeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<MobileLocationRequest?>>(
      pendingIncomingLocationRequestProvider,
      (prev, next) {
        final prevId = prev?.asData?.value?.id;
        final incoming = next.asData?.value;
        if (incoming != null && incoming.id != prevId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => LocationIncomingOverlay(
                    request: incoming,
                    employeeId: employeeId,
                  ),
                ),
              );
            }
          });
        }
      },
    );
    return child;
  }
}
