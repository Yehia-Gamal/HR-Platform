import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// حالات فحص الموقع — State Machine
enum LocationPhase {
  checkingService,
  requestingPermission,
  acquiringLocation,
  validatingAccuracy,
  reverseGeocoding,
  ready,
  failed,
}

/// نتيجة فحص جاهزية GPS قبل بدء العملية.
class GpsPreflightResult {
  const GpsPreflightResult({
    required this.serviceEnabled,
    required this.permission,
  });

  final bool serviceEnabled;
  final LocationPermission permission;

  bool get isReady =>
      serviceEnabled &&
      (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse);

  bool get isGpsOff => !serviceEnabled;

  bool get isPermissionDenied =>
      permission == LocationPermission.denied;

  bool get isDeniedForever =>
      permission == LocationPermission.deniedForever;

  /// ملخص بالعربية للحالة.
  String get arabicSummary {
    if (!serviceEnabled) return 'خدمة الموقع (GPS) غير مفعلة';
    if (isDeniedForever) return 'صلاحية الموقع مرفوضة نهائيًا';
    if (isPermissionDenied) return 'صلاحية الموقع غير ممنوحة';
    return 'GPS جاهز';
  }
}

class GpsDisabledException implements Exception {
  GpsDisabledException([this.message = 'خدمة الموقع غير مفعلة']);
  final String message;
  @override
  String toString() => message;
}

class GpsPermissionDeniedException implements Exception {
  GpsPermissionDeniedException([
    this.message = 'تم رفض صلاحية الموقع',
    this.isDeniedForever = false,
  ]);
  final String message;

  /// هل رُفضت الصلاحية نهائيًا (لن يظهر حوار النظام)؟
  /// يستخدم لتحديد نوع زر الإعدادات: openAppSettings vs openLocationSettings.
  final bool isDeniedForever;
  @override
  String toString() => message;
}

class GpsAccuracyException implements Exception {
  GpsAccuracyException(
      [this.message = 'دقة الموقع غير كافية، أعد المحاولة']);
  final String message;
  @override
  String toString() => message;
}

class LocationService {
  const LocationService._();

  /// فحص جاهزية GPS بدون طلب صلاحية — مناسب للـ preflight.
  static Future<GpsPreflightResult> preflight() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    return GpsPreflightResult(
      serviceEnabled: enabled,
      permission: permission,
    );
  }

  /// يجلب الموقع الحالي مع فحص دقيق للحالة.
  /// يرمي استثناءات محددة يمكن للواجهة التعامل معها.
  /// يستدعي [onPhase] عند كل مرحلة لعرض تقدم مفصّل.
  static Future<Position> current({
    void Function(LocationPhase phase)? onPhase,
  }) async {
    onPhase?.call(LocationPhase.checkingService);
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      onPhase?.call(LocationPhase.failed);
      throw GpsDisabledException();
    }

    onPhase?.call(LocationPhase.requestingPermission);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      onPhase?.call(LocationPhase.failed);
      throw GpsPermissionDeniedException();
    }
    if (permission == LocationPermission.deniedForever) {
      onPhase?.call(LocationPhase.failed);
      throw GpsPermissionDeniedException(
        'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
        true,
      );
    }

    onPhase?.call(LocationPhase.acquiringLocation);
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    onPhase?.call(LocationPhase.validatingAccuracy);
    if (position.accuracy > 100) {
      onPhase?.call(LocationPhase.failed);
      throw GpsAccuracyException(
        'دقة الموقع الحالية ${position.accuracy.toStringAsFixed(0)} متر — أعد المحاولة.',
      );
    }

    onPhase?.call(LocationPhase.ready);
    return position;
  }

  static Stream<Position> stream() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 10,
    ),
  );

  // ترميز جغرافي عكسي عبر Nominatim/OSM (مجاني، بسياسة استخدام).
  // يعيد null بهدوء عند أي فشل — العنوان اختياري ولا يجب أن يُفشل المسار.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toString(),
        'lon': lng.toString(),
        'accept-language': 'ar',
        'zoom': '18',
      });
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final request = await client.getUrl(uri);
      // سياسة Nominatim تتطلب User-Agent معرِّفًا.
      request.headers.set(HttpHeaders.userAgentHeader, 'AhlaShababHR/1.0 (location-verify)');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        client.close();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      client.close();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final display = data['display_name'] as String?;
      if (display == null || display.trim().isEmpty) return null;
      return display.trim();
    } catch (_) {
      return null;
    }
  }

  /// وصف عربي لمرحلة الموقع الحالية.
  static String phaseLabel(LocationPhase phase) => switch (phase) {
    LocationPhase.checkingService => 'فحص خدمة الموقع...',
    LocationPhase.requestingPermission => 'طلب صلاحية الموقع...',
    LocationPhase.acquiringLocation => 'تحديد الموقع بدقة عالية...',
    LocationPhase.validatingAccuracy => 'التحقق من دقة الموقع...',
    LocationPhase.reverseGeocoding => 'الحصول على العنوان...',
    LocationPhase.ready => 'الموقع جاهز',
    LocationPhase.failed => 'فشل في تحديد الموقع',
  };
}
