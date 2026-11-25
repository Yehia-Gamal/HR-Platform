import 'dart:convert';

/// أدوات تحليل JSON آمنة لحماية نماذج الموبايل من القيم الفارغة أو تغيّر الأنواع
/// عند تعديل دوال الخادم أو غياب الحقول الاختيارية.

String asString(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value is String ? value : value.toString();
}

String? asNullableString(Object? value) {
  if (value == null) return null;
  return value is String ? value : value.toString();
}

int asInt(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    return int.tryParse(trimmed) ??
        double.tryParse(trimmed)?.toInt() ??
        fallback;
  }
  return fallback;
}

int? asNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.toInt();
  }
  return null;
}

double asDouble(Object? value, [double fallback = 0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim()) ?? fallback;
  }
  return fallback;
}

double? asNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

num? asNullableNum(Object? value) {
  if (value == null) return null;
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

num asNum(Object? value, [num fallback = 0]) => asNullableNum(value) ?? fallback;

bool asBool(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final norm = value.trim().toLowerCase();
    if (norm == 'true' || norm == '1' || norm == 'yes') return true;
    if (norm == 'false' || norm == '0' || norm == 'no') return false;
  }
  return fallback;
}

bool? asNullableBool(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final norm = value.trim().toLowerCase();
    if (norm == 'true' || norm == '1' || norm == 'yes') return true;
    if (norm == 'false' || norm == '0' || norm == 'no') return false;
  }
  return null;
}

DateTime reqDate(Object? value) {
  if (value is DateTime) return value;
  final str = value?.toString().trim() ?? '';
  if (str.isEmpty) return DateTime(0);
  return DateTime.tryParse(str) ?? DateTime(0);
}

DateTime? optDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty || s == 'null') return null;
  return DateTime.tryParse(s);
}

Map<String, dynamic> asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // السلسلة ليست JSON object صالحًا — نرجع خريطة فارغة بدل الانهيار.
    }
  }
  return const <String, dynamic>{};
}

Map<String, dynamic>? asNullableMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

List<dynamic> asList(Object? value) {
  if (value is List) return value;
  return const <dynamic>[];
}

List<Map<String, dynamic>> asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final result = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is Map<String, dynamic>) {
      result.add(item);
    } else if (item is Map) {
      result.add(Map<String, dynamic>.from(item));
    }
  }
  return List<Map<String, dynamic>>.unmodifiable(result);
}

List<String> asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .where((e) => e != null)
      .map((e) => e.toString())
      .toList(growable: false);
}
