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
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('جلسة التتبع النشطة')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.location_searching,
                size: 70,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'الموقع قيد المشاركة',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        '${secondsLeft ~/ 60}:${(secondsLeft % 60).toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.displaySmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'تم إرسال $sent نقطة موقع',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          error!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_issueKind == _LocationIssueKind.gpsOff) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Geolocator.openLocationSettings(),
                    icon: const Icon(Icons.gps_fixed_rounded, size: 18),
                    label: const Text('فتح إعدادات الموقع'),
                  ),
                ],
                if (_issueKind == _LocationIssueKind.deniedForever) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Geolocator.openAppSettings(),
                    icon: const Icon(Icons.settings_rounded, size: 18),
                    label: const Text('فتح إعدادات التطبيق'),
                  ),
                ],
                if (_issueKind == _LocationIssueKind.permissionDenied) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
                    ),
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
                ],
              ],
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: _finish,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('إنهاء المشاركة الآن'),
              ),
            ],
          ),
        ),
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
