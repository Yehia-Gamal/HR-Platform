import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// تفضيلات الإشعارات المحلية (بند 8): كتم قنوات + ساعات هدوء.
///
/// تُخزَّن على الجهاز وتُطبَّق في PushService قبل عرض أي إشعار محلي.
/// استثناء أمان ثابت: طلبات الموقع العاجلة (live_location_request)
/// تتجاوز الكتم وساعات الهدوء دائماً — لا يمكن كتمها من الواجهة أصلاً.
class NotificationPreferences {
  const NotificationPreferences({
    this.mutedKinds = const <String>{},
    this.quietHoursEnabled = false,
    this.quietStartMinutes = 22 * 60,
    this.quietEndMinutes = 7 * 60,
  });

  static const _storageKey = 'notification_preferences_v1';

  /// القنوات المكتومة — أنواع موحّدة (canonical kinds).
  final Set<String> mutedKinds;

  final bool quietHoursEnabled;

  /// بداية الهدوء بالدقائق من منتصف الليل (افتراضي 22:00).
  final int quietStartMinutes;

  /// نهاية الهدوء بالدقائق من منتصف الليل (افتراضي 07:00).
  final int quietEndMinutes;

  /// القنوات القابلة للكتم مع تسمياتها العربية.
  /// طلبات الموقع مستثناة عمداً — إشعار أمان بشاشة كاملة.
  static const mutableChannels = <String, String>{
    'request': 'الطلبات والموافقات',
    'kpi': 'تقييمات الأداء',
    'attendance': 'الحضور والبصمة',
    'dispute': 'النزاعات',
    'task': 'المهام',
    'decision': 'القرارات الرسمية',
    'announcement': 'الإعلانات',
    'recognition': 'التقديرات',
    'daily_report': 'التقارير اليومية',
  };

  bool isKindMuted(String kind) => mutedKinds.contains(kind);

  /// هل نحن داخل نافذة الهدوء الآن؟ يدعم النطاف الملفوف حول منتصف الليل
  /// (مثل 22:00 → 07:00).
  bool get isQuietNow {
    if (!quietHoursEnabled) return false;
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    if (quietStartMinutes == quietEndMinutes) return false;
    if (quietStartMinutes < quietEndMinutes) {
      return minutes >= quietStartMinutes && minutes < quietEndMinutes;
    }
    return minutes >= quietStartMinutes || minutes < quietEndMinutes;
  }

  /// القرار النهائي: هل نكتم هذا الإشعار؟
  /// طلبات الموقع تتجاوز كل شيء دائماً.
  bool shouldSuppress(String kind) {
    if (kind == 'live_location_request') return false;
    return isKindMuted(kind) || isQuietNow;
  }

  NotificationPreferences copyWith({
    Set<String>? mutedKinds,
    bool? quietHoursEnabled,
    int? quietStartMinutes,
    int? quietEndMinutes,
  }) {
    return NotificationPreferences(
      mutedKinds: mutedKinds ?? this.mutedKinds,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
    'mutedKinds': mutedKinds.toList(),
    'quietHoursEnabled': quietHoursEnabled,
    'quietStartMinutes': quietStartMinutes,
    'quietEndMinutes': quietEndMinutes,
  };

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      mutedKinds: ((json['mutedKinds'] as List<dynamic>?) ?? const [])
          .map((e) => e.toString())
          .toSet(),
      quietHoursEnabled: json['quietHoursEnabled'] as bool? ?? false,
      quietStartMinutes:
          (json['quietStartMinutes'] as num?)?.toInt() ?? 22 * 60,
      quietEndMinutes: (json['quietEndMinutes'] as num?)?.toInt() ?? 7 * 60,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(toJson()));
  }

  static Future<NotificationPreferences> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return const NotificationPreferences();
      return NotificationPreferences.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map<dynamic, dynamic>),
      );
    } catch (_) {
      return const NotificationPreferences();
    }
  }
}
