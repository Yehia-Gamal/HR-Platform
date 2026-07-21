import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';

/// حالات فحص الموقع — State Machine
enum LocationPhase {
  checkingService,
  requestingPermission,
  waitingForGps,
  acquiringLocation,
  validatingAccuracy,
  reverseGeocoding,
  ready,
  failedRecoverable,
}

class GpsDisabledException implements Exception {
  GpsDisabledException([this.message = 'خدمة الموقع غير مفعلة']);
  final String message;
  @override
  String toString() => message;
}

class GpsPermissionDeniedException implements Exception {
  GpsPermissionDeniedException([this.message = 'تم رفض صلاحية الموقع']);
  final String message;
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

  /// يجلب الموقع الحالي مع فحص دقيق للحالة.
  /// يرمي استثناءات محددة يمكن للواجهة التعامل معها.
  static Future<Position> current() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw GpsDisabledException();
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw GpsPermissionDeniedException();
    }
    if (permission == LocationPermission.deniedForever) {
      throw GpsPermissionDeniedException(
        'صلاحية الموقع مرفوضة نهائيًا. افتح إعدادات التطبيق لتفعيلها.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    if (position.accuracy > 100) {
      throw GpsAccuracyException(
        'دقة الموقع الحالية ${position.accuracy.toStringAsFixed(0)} متر — أعد المحاولة.',
      );
    }
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
}

