import 'dart:async';
import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class VideoVerificationPage extends ConsumerStatefulWidget {
  const VideoVerificationPage({
    required this.request,
    required this.employeeId,
    super.key,
  });
  final MobileLocationRequest request;
  final String employeeId;

  @override
  ConsumerState<VideoVerificationPage> createState() =>
      _VideoVerificationPageState();
}

class _VideoVerificationPageState extends ConsumerState<VideoVerificationPage>
    with WidgetsBindingObserver {
  CameraController? controller;
  bool busy = false;
  int countdown = 5;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      // الكاميرا الأمامية مفضلة للتحقق
      final selected =
          cameras.where((c) => c.lensDirection == CameraLensDirection.front).firstOrNull ??
          cameras.firstOrNull;
      if (selected == null) {
        if (mounted) setState(() => error = 'لا توجد كاميرا متاحة على الجهاز.');
        return;
      }
      final next = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      // تثبيت الاتجاه الصحيح لتجنب التمدد
      await next.lockCaptureOrientation();
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() => controller = next);
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        setState(() {
          error = msg.contains('CameraException')
              ? 'تعذر فتح الكاميرا. تأكد من إذن الكاميرا وأعد المحاولة.'
              : 'حدث خطأ أثناء تهيئة الكاميرا. أعد المحاولة.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = controller;
    if (current == null || !current.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      current.dispose();
      controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initialize();
    }
  }

  Future<void> _record() async {
    final current = controller;
    if (current == null || !current.value.isInitialized || busy) return;
    setState(() {
      busy = true;
      countdown = 5;
      error = null;
    });
    try {
      // جلب الموقع قبل التسجيل
      final position = await LocationService.current();
      await current.startVideoRecording();
      for (var i = 5; i > 0; i--) {
        if (mounted) setState(() => countdown = i);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final file = await current.stopVideoRecording();
      final bytes = await file.readAsBytes();
      final path =
          '${widget.employeeId}/${widget.request.id}/${DateTime.now().toUtc().millisecondsSinceEpoch}.mp4';
      await ref
          .read(supabaseProvider)
          .storage
          .from('live-location-videos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: true,
            ),
          );
      final addressAr = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
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
        addressAr: '${addressAr ?? ''} | $mapsUrl',
      );
      await ref.read(mobileCommandsProvider).registerLocationVideo(
        widget.request.id,
        storagePath: path,
        durationSeconds: 5,
        sizeBytes: bytes.length,
        mimeType: 'video/mp4',
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      try {
        if (controller?.value.isRecordingVideo == true) {
          await controller?.stopVideoRecording();
        }
      } catch (_) {}
      String msg;
      if (e is GpsDisabledException) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: Colors.grey.shade900,
              title: const Text('الموقع الجغرافي مغلق', style: TextStyle(color: Colors.white)),
              content: const Text(
                'الرجاء تفعيل خدمة الموقع (GPS) من إعدادات الجهاز للمتابعة.',
                style: TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                  },
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openLocationSettings();
                  },
                  child: const Text('فتح الإعدادات'),
                ),
              ],
            ),
          );
        }
        msg = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.';
      } else if (e is GpsPermissionDeniedException) {
        msg = e.message;
      } else if (e is GpsAccuracyException) {
        msg = e.message;
      } else {
        msg = 'حدث خطأ أثناء التسجيل. أعد المحاولة.';
      }
      if (mounted) setState(() => error = msg);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = controller;
    final initialized = current?.value.isInitialized == true;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('فيديو تحقق 5 ثوانٍ'),
      ),
      body: Column(
        children: [
          // ── معاينة الكاميرا ────────────────────────────────────────
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // معاينة الكاميرا تملأ الشاشة بشكل طبيعي بدون أشرطة سوداء
                if (initialized)
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: 100,
                        height: 100 * current!.value.aspectRatio,
                        child: CameraPreview(current),
                      ),
                    ),
                  )
                else
                  Center(
                    child: error == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                  ),
                // عداد تنازلي فوق الكاميرا أثناء التسجيل
                if (busy)
                  Center(
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.85),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$countdown',
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                // مؤشر تسجيل نشط
                if (busy)
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.fiber_manual_record,
                              color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text(
                            'تسجيل',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── خطأ وزر التسجيل ────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null && !busy) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: busy ? Colors.red : null,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: busy || !initialized ? null : _record,
                    icon: Icon(busy ? Icons.stop_rounded : Icons.videocam_rounded),
                    label: Text(busy ? 'جاري التسجيل... $countdown' : 'بدء تسجيل 5 ثوانٍ'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _IterableFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
