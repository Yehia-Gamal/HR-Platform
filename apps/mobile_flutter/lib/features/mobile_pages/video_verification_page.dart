import 'dart:async';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/location_service.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:ahla_shabab_management_os/core/theme/app_theme.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// شاشة فيديو التحقق (5 ثوانٍ) لطلبات الموقع من المدير التنفيذي.
///
/// السلوك:
/// 1. تهيئة الكاميرا الأمامية (بدون صوت).
/// 2. عند الضغط على «بدء تسجيل 5 ثوانٍ»:
///    - فحص GPS والصلاحية (throws إذا كانت مغلقة).
///    - رسم لقطة الخريطة off-screen وحفظها.
///    - بدء التسجيل، عد تنازلي 5→1 ثم إيقاف التلقائي.
///    - رفع الفيديو ولقطة الخريطة والإحداثيات إلى Supabase.
/// 3. جميع الرسائل بالعربية؛ لا يظهر أي Exception خام للمستخدم.
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
  bool _initializing = false;
  int countdown = 5;
  String? error;
  Position? mapPosition;
  final ScreenshotController mapScreenshot = ScreenshotController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final cameras = await availableCameras();
      final selected =
          cameras
              .where((c) => c.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          cameras.firstOrNull;
      if (selected == null) {
        if (mounted) {
          setState(() => error = 'لا توجد كاميرا متاحة على الجهاز.');
        }
        return;
      }
      final next = CameraController(
        selected,
        // Medium keeps the file small enough to upload over cellular while
        // preserving enough detail for identity verification. Samsung devices
        // occasionally fail at `high` when the sensor is busy elsewhere.
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        controller = next;
        error = null;
      });
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => error = _cameraExceptionMessage(e));
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'تعذر تهيئة الكاميرا. أعد المحاولة.');
      }
    } finally {
      _initializing = false;
    }
  }

  String _postgrestErrorMessage(PostgrestException e) {
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (msg.contains('permission denied') || code == '42501') {
      return 'ليس لديك صلاحية تنفيذ هذا الإجراء. تواصل مع المسؤول.';
    }
    if (msg.contains('foreign key') || msg.contains('violates foreign key')) {
      return 'الطلب غير موجود أو تم حذفه. أعد تحميل الصفحة.';
    }
    if (code == 'P0002' || msg.contains('employee is not active')) {
      return 'حسابك غير نشط. تواصل مع المسؤول.';
    }
    if (msg.contains('location request') && msg.contains('expired')) {
      return 'انتهت صلاحية طلب الموقع. أعد المحاولة.';
    }
    if (msg.contains('rls') || msg.contains('row-level security')) {
      return 'خطأ في صلاحيات الوصول. أعد تسجيل الدخول.';
    }
    return 'خطأ في الخادم (${code.isNotEmpty ? code : 'DB'}). أعد المحاولة.';
  }

  String _cameraExceptionMessage(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('permission') || code.contains('denied')) {
      return 'إذن الكاميرا مرفوض. افتح إعدادات التطبيق وامنح صلاحية الكاميرا.';
    }
    if (code.contains('audio')) {
      return 'تعذر تسجيل الفيديو. أعد المحاولة.';
    }
    if (code.contains('busy') || code.contains('inuse')) {
      return 'الكاميرا مشغولة بتطبيق آخر. أغلقه ثم أعد المحاولة.';
    }
    return 'تعذر فتح الكاميرا. أعد فتح الصفحة.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = controller;
    if (current == null) return;
    // Never dispose the camera while a recording is in progress. Losing the
    // controller mid-recording throws SecurityException on the platform side
    // and leaves the app in a stuck state.
    if (busy && current.value.isRecordingVideo) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (!current.value.isInitialized) return;
      current.dispose();
      if (mounted) setState(() => controller = null);
    } else if (state == AppLifecycleState.resumed) {
      if (controller == null) _initialize();
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
      // ── 1) قراءة الموقع (يرمي استثناء عند إغلاق GPS أو منع الصلاحية) ──
      final position = await LocationService.current();

      // ── 2) تجهيز خريطة صغيرة للقطة والانتظار ريثما تُحمّل البلاطات ──
      if (mounted) setState(() => mapPosition = position);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      Uint8List? mapBytes;
      try {
        mapBytes = await mapScreenshot.capture(pixelRatio: 2);
      } catch (_) {
        mapBytes = null; // Snapshot اختياري — لا يجب أن يفشل التسجيل بسببه
      }

      // ── 3) بدء التسجيل ──
      try {
        await current.startVideoRecording();
      } on CameraException catch (e) {
        throw StateError(_cameraExceptionMessage(e));
      }

      // ── 4) عدّ تنازلي 5→1 ──
      for (var i = 5; i > 0; i--) {
        if (mounted) setState(() => countdown = i);
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      // ── 5) إيقاف التسجيل وقراءة الملف ──
      final file = await current.stopVideoRecording();
      final videoBytes = await file.readAsBytes();
      if (videoBytes.isEmpty) {
        throw StateError('الفيديو المسجل فارغ. أعد المحاولة.');
      }

      // ── 6) رفع الفيديو ──
      // A deterministic path makes a transport retry overwrite the same
      // object instead of creating duplicate evidence for one request.
      final videoPath =
          '${widget.employeeId}/${widget.request.id}/verification.mp4';
      try {
        await ref
            .read(supabaseProvider)
            .storage
            .from('live-location-videos')
            .uploadBinary(
              videoPath,
              videoBytes,
              fileOptions: const FileOptions(
                contentType: 'video/mp4',
                upsert: true,
              ),
            );
      } catch (_) {
        throw StateError('تعذر رفع الفيديو. تحقق من الاتصال وأعد المحاولة.');
      }

      // ── 7) رفع لقطة الخريطة (اختياري — لا يوقف السير إن فشل) ──
      String? mapPath;
      if (mapBytes != null && mapBytes.isNotEmpty) {
        mapPath = '${widget.employeeId}/${widget.request.id}/map.png';
        try {
          await ref
              .read(supabaseProvider)
              .storage
              .from('live-location-map-snapshots')
              .uploadBinary(
                mapPath,
                mapBytes,
                fileOptions: const FileOptions(
                  contentType: 'image/png',
                  upsert: true,
                ),
              );
        } catch (_) {
          mapPath = null;
        }
      }

      // ── 8) العنوان العكسي (اختياري) ──
      final addressAr = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final mapsUrl =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';

      // ── 9) تسليم الإحداثيات للخادم ──
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
            addressAr: '${addressAr ?? ''} | $mapsUrl',
          );

      // ── 10) ربط لقطة الخريطة بالسجل إذا رُفعت ──
      if (mapPath != null) {
        try {
          await ref
              .read(mobileCommandsProvider)
              .registerLocationMapSnapshot(
                widget.request.id,
                storagePath: mapPath,
              );
        } catch (_) {
          // اختياري — الخريطة قد لا تكون مطلوبة لاكتمال الطلب.
        }
      }

      // ── 11) ربط الفيديو بالسجل واعتماد الطلب مكتملًا ──
      await ref
          .read(mobileCommandsProvider)
          .registerLocationVideo(
            widget.request.id,
            storagePath: videoPath,
            durationSeconds: 5,
            sizeBytes: videoBytes.length,
            mimeType: 'video/mp4',
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
          );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      // إيقاف أي تسجيل متبقٍّ حتى لا تبقى الكاميرا في حالة محجوزة.
      try {
        if (controller?.value.isRecordingVideo == true) {
          await controller?.stopVideoRecording();
        }
      } catch (_) {
        // Best-effort: camera cleanup may fail if already released.
      }
      if (!mounted) return;

      if (e is GpsDisabledException) {
        _showGpsDialog();
        setState(
          () => error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.',
        );
      } else if (e is GpsPermissionDeniedException) {
        setState(() => error = e.message);
      } else if (e is GpsAccuracyException) {
        setState(() => error = e.message);
      } else if (e is CameraException) {
        setState(() => error = _cameraExceptionMessage(e));
      } else if (e is StateError) {
        setState(() => error = e.message);
      } else if (e is PostgrestException) {
        setState(() => error = _postgrestErrorMessage(e));
      } else {
        setState(() => error = 'تعذر إكمال العملية. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _sendLocationOnly() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final position = await LocationService.current();
      if (mounted) setState(() => mapPosition = position);
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      String? mapPath;
      try {
        final mapBytes = await mapScreenshot.capture(pixelRatio: 2);
        if (mapBytes != null && mapBytes.isNotEmpty) {
          mapPath =
              '${widget.employeeId}/${widget.request.id}/${DateTime.now().toUtc().millisecondsSinceEpoch}-map.png';
          try {
            await ref
                .read(supabaseProvider)
                .storage
                .from('live-location-map-snapshots')
                .uploadBinary(
                  mapPath,
                  mapBytes,
                  fileOptions: const FileOptions(
                    contentType: 'image/png',
                    upsert: true,
                  ),
                );
          } catch (_) {
            mapPath = null;
          }
        }
      } catch (_) {
        // Map snapshot is optional.
      }

      final addressAr = await LocationService.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final mapsUrl =
          'https://maps.google.com/?q=${position.latitude},${position.longitude}';
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
            addressAr: '${addressAr ?? ''} | $mapsUrl',
          );
      if (mapPath != null) {
        try {
          await ref
              .read(mobileCommandsProvider)
              .registerLocationMapSnapshot(
                widget.request.id,
                storagePath: mapPath,
              );
        } catch (_) {
          // Map snapshot registration is optional — do not block completion.
        }
      }
      await ref
          .read(mobileCommandsProvider)
          .completeLocation(widget.request.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال الموقع بنجاح.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;
      if (e is GpsDisabledException) {
        _showGpsDialog();
        setState(
          () => error = 'خدمة الموقع غير مفعلة. فعّل GPS ثم أعد المحاولة.',
        );
      } else if (e is GpsPermissionDeniedException) {
        setState(() => error = e.message);
      } else if (e is GpsAccuracyException) {
        setState(() => error = e.message);
      } else if (e is StateError) {
        setState(() => error = e.message);
      } else if (e is PostgrestException) {
        setState(() => error = _postgrestErrorMessage(e));
      } else {
        setState(
          () => error = 'تعذر إرسال الموقع. تحقق من الاتصال وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _showGpsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: AppTheme.dark(),
        child: AlertDialog(
          title: const Text('الموقع الجغرافي مغلق'),
          content: const Text(
            'الرجاء تفعيل خدمة الموقع (GPS) من إعدادات الجهاز للمتابعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
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
      ),
    );
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
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── معاينة الكاميرا: AspectRatio يمنع تشويه الوجه ──
                if (initialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: 1 / current!.value.aspectRatio,
                      child: CameraPreview(current),
                    ),
                  )
                else
                  Center(
                    child: error == null
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.videocam_off_rounded,
                                  color: Colors.white70,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  error!,
                                  style: const TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: _initializing
                                      ? null
                                      : () {
                                          setState(() => error = null);
                                          _initialize();
                                        },
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('إعادة فتح الكاميرا'),
                                ),
                              ],
                            ),
                          ),
                  ),

                // ── العد التنازلي أثناء التسجيل ──
                if (busy)
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
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

                // ── لقطة الخريطة off-screen (تُلتقط بواسطة Screenshot) ──
                // نُظهرها بحجم صغير أعلى الشاشة أثناء التقاطها، ثم يمكن إخفاؤها
                // بعد اكتمال الالتقاط. الأداء والحجم محدودان.
                if (mapPosition case final position?)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: Screenshot(
                      controller: mapScreenshot,
                      child: Container(
                        width: 160,
                        height: 110,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.white, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(
                              position.latitude,
                              position.longitude,
                            ),
                            initialZoom: 16,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName:
                                  'org.ahlashabab.ahla_shabab_management_os',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: LatLng(
                                    position.latitude,
                                    position.longitude,
                                  ),
                                  width: 42,
                                  height: 42,
                                  child: const Icon(
                                    Icons.location_pin,
                                    size: 42,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                            const RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  '© OpenStreetMap contributors',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // ── شارة "تسجيل" ──
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
                          Icon(
                            Icons.fiber_manual_record,
                            color: Colors.white,
                            size: 14,
                          ),
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
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error != null && !busy && initialized) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: busy
                          ? Colors.red
                          : Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      disabledBackgroundColor: Colors.grey.shade700,
                      disabledForegroundColor: Colors.white70,
                    ),
                    onPressed: busy || !initialized ? null : _record,
                    icon: Icon(
                      busy ? Icons.stop_rounded : Icons.videocam_rounded,
                    ),
                    label: Text(
                      busy ? 'جاري التسجيل... $countdown' : 'بدء تسجيل 5 ثوانٍ',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!widget.request.needsVideo)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: busy ? null : _sendLocationOnly,
                      icon: const Icon(Icons.location_on_outlined, size: 20),
                      label: const Text('إرسال الموقع فقط'),
                    )
                  else
                    const Text(
                      'هذا الطلب يتطلب فيديو صامتًا مدته 5 ثوانٍ ولا يمكن إكماله بالموقع فقط.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
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
