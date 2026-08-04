import 'dart:async';
import 'dart:io';

import 'package:ahla_shabab_management_os/features/mobile_data/mobile_models.dart';
import 'package:ahla_shabab_management_os/features/mobile_data/mobile_providers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class VideoVerificationPage extends ConsumerStatefulWidget {
  const VideoVerificationPage({
    required this.request,
    required this.employeeId,
    required this.position,
    super.key,
  });

  final MobileLocationRequest request;
  final String employeeId;
  final Position position;

  @override
  ConsumerState<VideoVerificationPage> createState() =>
      _VideoVerificationPageState();
}

class _VideoVerificationPageState extends ConsumerState<VideoVerificationPage>
    with WidgetsBindingObserver {
  static const _recordingDuration = Duration(seconds: 5);

  CameraController? _controller;
  bool _initializing = true;
  bool _recording = false;
  bool _uploading = false;
  String? _error;
  int _remainingSeconds = _recordingDuration.inSeconds;
  Timer? _timer;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (!_recording) {
        unawaited(controller.dispose());
        _controller = null;
      }
    } else if (state == AppLifecycleState.resumed && !_recording) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      final selected = front.isNotEmpty ? front.first : cameras.first;
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await _controller?.dispose();
      setState(() {
        _controller = controller;
        _initializing = false;
        _remainingSeconds = _recordingDuration.inSeconds;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _cameraMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'تعذر فتح الكاميرا الأمامية. أعد المحاولة.';
      });
    }
  }

  Future<void> _recordAndUpload() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _recording ||
        _uploading) {
      return;
    }
    setState(() {
      _recording = true;
      _error = null;
      _remainingSeconds = _recordingDuration.inSeconds;
    });

    XFile video;
    try {
      await controller.startVideoRecording();
      _stopwatch
        ..reset()
        ..start();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        final remaining = _recordingDuration - _stopwatch.elapsed;
        setState(() {
          _remainingSeconds = remaining.inMilliseconds <= 0
              ? 0
              : (remaining.inMilliseconds / 1000).ceil();
        });
      });
      await Future<void>.delayed(_recordingDuration);
      video = await controller.stopVideoRecording();
    } catch (_) {
      if (controller.value.isRecordingVideo) {
        await controller.stopVideoRecording().catchError((_) => XFile(''));
      }
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = 'حدث خطأ أثناء تسجيل الفيديو. أعد المحاولة.';
      });
      return;
    } finally {
      _timer?.cancel();
      _stopwatch.stop();
    }

    final file = File(video.path);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    if (!exists || size <= 0) {
      if (!mounted) return;
      setState(() {
        _recording = false;
        _error = 'لم يتم حفظ الفيديو بشكل صحيح. أعد التسجيل.';
      });
      return;
    }

    setState(() {
      _recording = false;
      _uploading = true;
    });
    try {
      await ref.read(mobileCommandsProvider).uploadLocationVideo(
            widget.request.id,
            employeeId: widget.employeeId,
            filePath: video.path,
            durationSeconds: _recordingDuration.inSeconds,
            latitude: widget.position.latitude,
            longitude: widget.position.longitude,
            accuracy: widget.position.accuracy,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = 'تعذر رفع الفيديو وتسجيله. تحقق من الاتصال وأعد المحاولة.';
      });
    }
  }

  String _cameraMessage(CameraException error) {
    final code = error.code.toLowerCase();
    if (code.contains('denied') || code.contains('restricted')) {
      return 'صلاحية الكاميرا غير ممنوحة. افتح إعدادات التطبيق وفعّل الكاميرا.';
    }
    return 'تعذر فتح الكاميرا الأمامية. أعد المحاولة.';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final busy = _recording || _uploading;

    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('فيديو التحقق'),
          automaticallyImplyLeading: !busy,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(
                        child: _initializing
                            ? const CircularProgressIndicator()
                            : ready
                                ? AspectRatio(
                                    aspectRatio: controller.value.aspectRatio,
                                    child: CameraPreview(controller),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      _error ??
                                          'تعذر عرض الكاميرا. أعد المحاولة.',
                                      style:
                                          const TextStyle(color: Colors.white),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _recording
                      ? 'جار تسجيل فيديو أمامي: $_remainingSeconds ث'
                      : _uploading
                          ? 'جار رفع الفيديو وتسجيل النتيجة...'
                          : 'سيتم تسجيل فيديو أمامي مدته 5 ثوان بدون صوت.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (!ready && !_initializing)
                  FilledButton.icon(
                    onPressed: _initializeCamera,
                    icon: const Icon(Icons.cameraswitch_rounded),
                    label: const Text('إعادة فتح الكاميرا'),
                  )
                else
                  FilledButton.icon(
                    onPressed: ready && !busy ? _recordAndUpload : null,
                    icon: Icon(_recording
                        ? Icons.fiber_manual_record_rounded
                        : Icons.videocam_rounded),
                    label: Text(
                      _recording
                          ? 'جار التسجيل...'
                          : _uploading
                              ? 'جار الرفع...'
                              : 'تسجيل 5 ثوان وإرسال',
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
