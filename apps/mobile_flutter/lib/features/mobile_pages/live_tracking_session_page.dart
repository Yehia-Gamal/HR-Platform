import 'dart:async';

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
    extends ConsumerState<LiveTrackingSessionPage> {
  StreamSubscription<Position>? subscription;
  Timer? timer;
  int secondsLeft = 0;
  int sent = 0;
  String? error;
  bool stopping = false;

  @override
  void initState() {
    super.initState();
    secondsLeft = widget.request.durationMinutes * 60;
    _start();
  }

  Future<void> _start() async {
    try {
      final first = await LocationService.current();
      await _send(first);
      subscription = LocationService.stream().listen(
        _send,
        onError: (Object value) {
          if (mounted) setState(() => error = _humanizeError(value));
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
    } catch (value) {
      if (mounted) setState(() => error = _humanizeError(value));
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
    } catch (value) {
      if (mounted) setState(() => error = _humanizeError(value));
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
          SnackBar(content: Text('تعذر إرسال إغلاق الجلسة: ${_humanizeError(e)}')),
        );
      }
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    timer?.cancel();
    subscription?.cancel();
    super.dispose();
  }

  static String _humanizeError(Object e) {
    final s = e.toString();
    if (s.contains('LocationServiceDisabledException') || s.contains('GpsDisabledException')) {
      return 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
    }
    if (s.contains('GpsPermissionDeniedException')) {
      return 'إذن الموقع مطلوب للمتابعة.';
    }
    if (s.contains('GpsAccuracyException')) {
      return 'دقة الموقع غير كافية. اخرج إلى مكان مفتوح وأعد المحاولة.';
    }
    return 'حدث خطأ أثناء التتبع. أعد المحاولة.';
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
