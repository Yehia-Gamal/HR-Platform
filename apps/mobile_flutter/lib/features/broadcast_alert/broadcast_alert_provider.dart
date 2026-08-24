import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ahla_shabab_management_os/features/auth/auth_providers.dart';

/// تنبيه شامل صادر من الإدارة (HR / المدير التنفيذي).
class BroadcastAlert {
  const BroadcastAlert({
    required this.id,
    required this.message,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String message;
  final DateTime createdAt;
  final DateTime expiresAt;

  static BroadcastAlert? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final message = json['message'];
    if (id is! String || message is! String) return null;
    return BroadcastAlert(
      id: id,
      message: message,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.now().add(const Duration(minutes: 15)),
    );
  }
}

/// يستعلم دوريًا (كل 20 ثانية) عن التنبيه النشط — يُبطل الصمت عند صدور
/// تنبيه بمعرّف جديد.
class BroadcastAlertNotifier extends Notifier<BroadcastAlert?> {
  Timer? _timer;
  String? _dismissedAlertId;

  @override
  BroadcastAlert? build() {
    _startPolling();
    ref.onDispose(_stopPolling);
    return null;
  }

  void dismiss() {
    _dismissedAlertId = state?.id;
    state = null;
  }

  void _startPolling() {
    _pollOnce();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _pollOnce());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _pollOnce() async {
    try {
      final client = ref.read(supabaseProvider);
      if (client.auth.currentSession == null) return;
      final data = await client
          .rpc<dynamic>('get_active_broadcast_alert')
          .timeout(const Duration(seconds: 10));
      if (data is! Map<String, dynamic>) return;
      final alert = BroadcastAlert.fromJson(data);
      if (alert == null) return;
      if (alert.id == _dismissedAlertId) return;
      if (state?.id == alert.id && state != null) return;
      state = alert;
    } catch (_) {
      // لا شبكة أو جلسة غير جاهزة — تُعاد المحاولة في الدورة التالية.
    }
  }
}

final broadcastAlertProvider =
    NotifierProvider<BroadcastAlertNotifier, BroadcastAlert?>(
  BroadcastAlertNotifier.new,
);

/// يُشغل فلاش الكاميرا الخلفية والاهتزاز بشكل متقطع أثناء ظهور التنبيه.
/// يستخدم حزمة camera المتوفرة أصلًا بلا اعتماديات جديدة.
class TorchBlinker {
  CameraController? _camera;
  Timer? _timer;
  bool _torchOn = false;
  bool _starting = false;

  bool get isActive => _timer != null;

  Future<void> start() async {
    if (_timer != null || _starting) return;
    _starting = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      _camera = controller;
      _timer = Timer.periodic(const Duration(milliseconds: 700), (_) {
        HapticFeedback.heavyImpact();
        final target = _torchOn ? FlashMode.off : FlashMode.torch;
        _camera?.setFlashMode(target).then((_) {
          _torchOn = !_torchOn;
        }).catchError((_) {});
      });
    } catch (_) {
      // جهاز بلا كاميرا أو إذن مرفوض — يبقى الطفح الشاشي فقط.
      await _releaseCamera();
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    try {
      await _camera?.setFlashMode(FlashMode.off);
    } catch (_) {}
    await _releaseCamera();
    _torchOn = false;
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    try {
      await camera?.dispose();
    } catch (_) {}
  }
}

final torchBlinkerProvider = Provider<TorchBlinker>((ref) {
  final blinker = TorchBlinker();
  ref.onDispose(() => blinker.stop());
  return blinker;
});

/// يشغّل/يوقف الفلاش تلقائيًا بحسب حالة التنبيه داخل دورة بناء آمنة.
void syncTorchWithAlert(WidgetRef ref, BroadcastAlert? alert) {
  final blinker = ref.read(torchBlinkerProvider);
  SchedulerBinding.instance.addPostFrameCallback((_) {
    if (alert != null) {
      blinker.start();
    } else {
      blinker.stop();
    }
  });
}