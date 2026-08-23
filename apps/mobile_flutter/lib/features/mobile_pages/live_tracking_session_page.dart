import 'dart:async';

import 'package:ahla_shabab_management_os/core/network/connectivity_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class LiveTrackingSessionPage extends ConsumerStatefulWidget {
  const LiveTrackingSessionPage({required this.request, super.key});
  final MobileLocationRequest request;

  @override
  ConsumerState<LiveTrackingSessionPage> createState() =>
      _LiveTrackingSessionPageState();
}

class _LiveTrackingSessionPageState
    extends ConsumerState<LiveTrackingSessionPage>
    with WidgetsBindingObserver {
  StreamSubscription<Position>? subscription;
  Timer? timer;
  int secondsLeft = 0;
  int sent = 0;
  String? error;
  bool stopping = false;

  /// نوع مشكلة الموقع — لتحديد زر الإعدادات المناسب.
  _LocationIssueKind? _issueKind;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    secondsLeft = widget.request.durationMinutes * 60;
    _start();
  }

  /// عند العودة من إعدادات الموقع أو التطبيق — إعادة المحاولة تلقائياً.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _issueKind != null &&
        subscription == null) {
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted && _issueKind != null && subscription == null) {
          _recheckAndRetry();
        }
      });
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

    setState(() {
      error = null;
      _issueKind = null;
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final first = await LocationService.current();
      await _send(first);
      subscription = LocationService.stream().listen(
        _send,
        onError: (Object e) {
          if (!mounted) return;
          if (e is GpsDisabledException) {
            setState(() {
              error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
              _issueKind = _LocationIssueKind.gpsOff;
            });
          } else if (e is GpsPermissionDeniedException) {
            setState(() {
              error = e.message;
              _issueKind = e.isDeniedForever
                  ? _LocationIssueKind.deniedForever
                  : _LocationIssueKind.permissionDenied;
            });
          } else if (e is GpsAccuracyException) {
            setState(() => error = e.message);
          } else {
            setState(() => error = 'حدث خطأ أثناء التتبع. أعد المحاولة.');
          }
        },
      );
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (secondsLeft <= 1) {
          _finish();
        } else {
          setState(() => secondsLeft--);
        }
      });
    } on GpsDisabledException {
      if (mounted) {
        setState(() {
          error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
          _issueKind = _LocationIssueKind.gpsOff;
        });
      }
    } on GpsPermissionDeniedException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          _issueKind = e.isDeniedForever
              ? _LocationIssueKind.deniedForever
              : _LocationIssueKind.permissionDenied;
        });
      }
    } on GpsAccuracyException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'حدث خطأ أثناء التتبع. أعد المحاولة.');
      }
    }
  }

  Future<void> _send(Position position) async {
    try {
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
          );
      if (mounted) setState(() => sent++);
    } catch (e) {
      if (mounted) setState(() => error = humanizeError(e));
    }
  }

  Future<void> _finish() async {
    if (stopping) return;
    stopping = true;
    timer?.cancel();
    await subscription?.cancel();
    try {
      await ref
          .read(mobileCommandsProvider)
          .completeLocation(widget.request.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال إغلاق الجلسة: ${humanizeError(e)}')),
        );
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalSeconds = widget.request.durationMinutes * 60;
    final progress = totalSeconds <= 0 ? 0.0 : secondsLeft / totalSeconds;
    final minutes = secondsLeft ~/ 60;
    final seconds = secondsLeft % 60;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('جلسة التتبع النشطة'),
          actions: [
            // شارة «مباشر» النابضة — 0451
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 14),
              child: Center(
                child: _LiveBadge(),
              ),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              // ── العدّاد الدائري ──
              Center(
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 190,
                        height: 190,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 10,
                          backgroundColor: scheme.surfaceContainerHighest
                              .withValues(alpha: .6),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            scheme.primary,
                          ),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$minutes:${seconds.toString().padLeft(2, '0')}',
                            style: Theme.of(context)
                                .textTheme
                                .displaySmall
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'الوقت المتبقي',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── معلومات الجلسة ──
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: .6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _sessionRow(
                        context,
                        icon: Icons.person_outline_rounded,
                        label: 'الطالب',
                        value: widget.request.requesterName,
                      ),
                      const SizedBox(height: 8),
                      _sessionRow(
                        context,
                        icon: Icons.swap_horiz_rounded,
                        label: 'نوع الجلسة',
                        value: 'تتبع ${widget.request.durationMinutes} دقيقة',
                      ),
                      const SizedBox(height: 8),
                      _sessionRow(
                        context,
                        icon: Icons.send_outlined,
                        label: 'نقاط أُرسلت',
                        value: '$sent',
                      ),
                    ],
                  ),
                ),
              ),

              // ── أخطاء الموقع ──
              if (error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.error.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_issueKind == _LocationIssueKind.gpsOff) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => Geolocator.openLocationSettings(),
                      icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                      label: const Text('فتح إعدادات الموقع'),
                    ),
                  ),
                ],
                if (_issueKind == _LocationIssueKind.deniedForever) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () => Geolocator.openAppSettings(),
                      icon: const Icon(Icons.settings_rounded, size: 18),
                      label: const Text('فتح إعدادات التطبيق'),
                    ),
                  ),
                ],
                if (_issueKind == _LocationIssueKind.permissionDenied) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final perm = await Geolocator.requestPermission();
                        if (!mounted) return;
                        if (perm == LocationPermission.always ||
                            perm == LocationPermission.whileInUse) {
                          setState(() {
                            error = null;
                            _issueKind = null;
                          });
                          _start();
                        }
                      },
                      icon: const Icon(Icons.location_on_rounded, size: 18),
                      label: const Text('منح صلاحية الموقع'),
                    ),
                  ),
                ],
              ],
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _finish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  foregroundColor: scheme.error,
                  backgroundColor: scheme.error.withValues(alpha: .08),
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('إنهاء المشاركة الآن'),
              ),
              const SizedBox(height: 6),
              Text(
                'عند انتهاء المدة تُغلق الجلسة وتتوقف المشاركة تلقائياً.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// صف معلومات الجلسة — 0451
  Widget _sessionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 17, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

/// شارة «مباشر» بنبض — 0451
class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: .35, end: 1).animate(_controller),
            child: Icon(Icons.circle, size: 9, color: scheme.error),
          ),
          const SizedBox(width: 5),
          Text(
            'مباشر',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: scheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

/// نوع مشكلة الموقع — يحدد زر الإعدادات المعروض.
enum _LocationIssueKind {
  gpsOff,
  permissionDenied,
  deniedForever,
}
