import 'dart:async';

import 'package:ahla_shabab_management_os/core/observability/crash_reporter.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// خدمة وقت موحّدة للتطبيق — تضمن تحويل التواريخ والأوقات إلى توقيت القاهرة
/// (`Africa/Cairo`) بغض النظر عن المنطقة الزمنية المضبوطة على جهاز الموظف.
class AppTime {
  AppTime._();

  static const String timeZoneName = 'Africa/Cairo';
  static bool _initialized = false;
  static tz.Location? _cairoLocation;

  /// يهيّئ قاعدة بيانات المناطق الزمنية ويعيّن `Africa/Cairo` منطقةً افتراضية.
  /// آمن للاستدعاء المتكرر (idempotent).
  static void initialize() {
    if (_initialized && _cairoLocation != null) return;
    _initialized = true;
    try {
      tz_data.initializeTimeZones();
      final location = tz.getLocation(timeZoneName);
      _cairoLocation = location;
      tz.setLocalLocation(location);
    } catch (error, stackTrace) {
      unawaited(
        CrashReporter.instance.captureError(
          error,
          stackTrace,
          context: 'app_time_initialize',
        ),
      );
    }
  }

  static tz.Location? _ensureCairoLocation() {
    if (_cairoLocation != null) return _cairoLocation;
    if (!_initialized) initialize();
    return _cairoLocation;
  }

  /// يحوّل أي [DateTime] إلى توقيت `Africa/Cairo` الفعلي مع مراعاة التوقيت الصيفي.
  /// إذا تعذّرت تهيئة قاعدة المناطق (نادرًا في بيئات معزولة)، يرجع لتوقيت مصر القياسي UTC+2.
  static DateTime toCairo(DateTime dt) {
    final cairo = _ensureCairoLocation();
    final utc = dt.isUtc ? dt : dt.toUtc();
    if (cairo != null) {
      return tz.TZDateTime.from(utc, cairo);
    }
    return utc.add(const Duration(hours: 2));
  }

  /// يحوّل تاريخًا اختياريًا إلى توقيت `Africa/Cairo` أو يرجع `null`.
  static DateTime? tryToCairo(DateTime? dt) => dt == null ? null : toCairo(dt);

  /// الوقت الحالي بتوقيت `Africa/Cairo`.
  static DateTime now() => toCairo(DateTime.now().toUtc());

  /// يحلّل نصًا أو قيمة تاريخية إلى توقيت `Africa/Cairo`، أو يرجع `null`.
  static DateTime? tryParse(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return toCairo(raw);
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final parsed = DateTime.tryParse(str);
    return parsed == null ? null : toCairo(parsed);
  }

  /// مفتاح اليوم `YYYY-MM-DD` وفق تقويم `Africa/Cairo`.
  static String dayKey(DateTime dt) {
    final c = toCairo(dt);
    return '${c.year}-${c.month.toString().padLeft(2, '0')}-${c.day.toString().padLeft(2, '0')}';
  }

  static String formatTimeAr(DateTime dt) =>
      DateFormat('h:mm a', 'ar').format(toCairo(dt));

  static String formatDateAr(DateTime dt) =>
      DateFormat('d MMMM y', 'ar').format(toCairo(dt));

  static String formatShortDateTimeAr(DateTime dt) =>
      DateFormat('d MMM، h:mm a', 'ar').format(toCairo(dt));
}
