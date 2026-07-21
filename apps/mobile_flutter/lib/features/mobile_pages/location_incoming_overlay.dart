import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_pages/video_verification_page.dart';
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
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _busy = false;
  String? _status;
  String? _error;
  bool _gpsOff = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _vibrateSeries();
  }

  void _vibrateSeries() {
    for (var i = 0; i < 5; i++) {
      Future<void>.delayed(Duration(milliseconds: i * 400), () {
        if (mounted) HapticFeedback.heavyImpact();
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _gpsOff = false;
      _status = 'جاري قبول الطلب...';
    });
    try {
      await ref
          .read(mobileCommandsProvider)
          .respondLocation(widget.request.id, true);

      setState(() => _status = 'جاري تحديد الموقع بدقة عالية...');
      final position = await LocationService.current();

      setState(() => _status = 'جاري الحصول على العنوان...');
      final address = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (widget.request.needsVideo) {
        setState(() => _status = 'جاري فتح الكاميرا...');
        final empId = widget.employeeId ??
            ref.read(supabaseProvider).auth.currentUser?.id ??
            '';
        if (mounted) {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => VideoVerificationPage(
                request: widget.request,
                employeeId: empId,
              ),
            ),
          );
        }
      } else if (widget.request.isTracking) {
        // tracking mode — accept was enough; location_requests_page handles the rest
      } else {
        setState(() => _status = 'جاري إرسال الموقع...');
        // رابط Google Maps للموقع الحالي
        final mapsUrl =
            'https://maps.google.com/?q=${position.latitude},${position.longitude}';
        await ref.read(mobileCommandsProvider).submitLocationPoint(
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
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        String msg;
        bool gpsOff = false;
        if (e is GpsDisabledException) {
          msg = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
          gpsOff = true;
        } else if (e is GpsPermissionDeniedException) {
          msg = e.message;
        } else if (e is GpsAccuracyException) {
          msg = e.message;
        } else {
          msg = 'حدث خطأ غير متوقع. أعد المحاولة.';
        }
        setState(() {
          _busy = false;
          _status = null;
          _error = msg;
          _gpsOff = gpsOff;
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(humanizeError(e))),
        );
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
                    Icon(
                      Icons.warning_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
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
                          if (_gpsOff) ...[
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                Geolocator.openLocationSettings();
                              },
                              icon: const Icon(Icons.gps_fixed_rounded),
                              label: const Text('فتح إعدادات الموقع'),
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

  String _modeLabel(String mode) => switch (mode) {
    'snapshot' => 'لقطة موقع فورية',
    'video_5s' => 'موقع + فيديو 5 ثوانٍ',
    'location_video' => 'موقع + فيديو توثيقي',
    'track_5' => 'تتبع 5 دقائق',
    'track_10' => 'تتبع 10 دقائق',
    'track_15' => 'تتبع 15 دقيقة',
    'track_30' => 'تتبع 30 دقيقة',
    _ => mode,
  };
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
