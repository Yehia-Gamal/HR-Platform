import 'package:ahla_design_tokens/ahla_design_tokens.dart';
import 'package:flutter/material.dart';

/// حالة اليوم للموظف — تسمية وألوان وأيقونات واحدة لكل الشاشات، مطابقة لدالة
/// الخادم _today_status_public (0631): «حاضر في الجمعية / غائب / في مأمورية /
/// في قافلة / في فاندي ترفيهي / في إجازة / انصرف …».
const todayStatusLabels = <String, String>{
  'present': 'حاضر في الجمعية',
  'late': 'متأخر',
  'left_early': 'انصرف مبكرًا',
  'checked_out': 'انصرف',
  'absent': 'غائب',
  'mission': 'في مأمورية',
  'convoy': 'في قافلة',
  'fundraising': 'في فاندي ترفيهي',
  'on_leave': 'في إجازة',
  'holiday': 'عطلة رسمية',
  'weekend': 'إجازة أسبوعية',
  'exempt': 'معفى من البصمة',
  'partial': 'حضور جزئي',
  'not_recorded': 'لم يسجّل حضوره بعد',
};

String todayStatusLabel(String? status, {String? fallback}) =>
    todayStatusLabels[status] ??
    (fallback != null && fallback.trim().isNotEmpty
        ? fallback.trim()
        : todayStatusLabels['not_recorded']!);

Color todayStatusColor(String? status) => switch (status) {
  'present' => AppColors.statusSuccess,
  'late' || 'partial' || 'left_early' => AppColors.statusWarning,
  'checked_out' => const Color(0xFF64748B),
  'absent' => AppColors.statusDanger,
  'mission' => const Color(0xFF2563EB),
  'convoy' => const Color(0xFF7C3AED),
  'fundraising' => const Color(0xFF0D9488),
  'on_leave' => const Color(0xFF0284C7),
  'holiday' || 'weekend' || 'exempt' => const Color(0xFF6B7280),
  _ => Colors.blueGrey,
};

IconData todayStatusIcon(String? status) => switch (status) {
  'present' => Icons.check_circle_rounded,
  'late' => Icons.alarm_on_rounded,
  'left_early' || 'checked_out' => Icons.logout_rounded,
  'absent' => Icons.cancel_rounded,
  'mission' => Icons.business_center_rounded,
  'convoy' => Icons.directions_bus_rounded,
  'fundraising' => Icons.festival_rounded,
  'on_leave' => Icons.beach_access_rounded,
  'holiday' => Icons.celebration_rounded,
  'weekend' => Icons.weekend_rounded,
  'exempt' => Icons.verified_user_rounded,
  _ => Icons.hourglass_empty_rounded,
};

bool isOffsiteStatus(String? status) =>
    status == 'mission' || status == 'convoy' || status == 'fundraising';

/// مجموعات ملخص اليوم في شاشة الموظفين.
enum TodayStatusGroup {
  present('حاضرون', AppColors.statusSuccess, Icons.check_circle_rounded),
  absent('غائبون', AppColors.statusDanger, Icons.cancel_rounded),
  offsite('خارج الجمعية', Color(0xFF2563EB), Icons.business_center_rounded),
  leave('إجازات', Color(0xFF0284C7), Icons.beach_access_rounded),
  other('لم يسجّلوا', Color(0xFF6B7280), Icons.hourglass_empty_rounded);

  const TodayStatusGroup(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  static TodayStatusGroup of(String? status) => switch (status) {
    'present' || 'late' || 'checked_out' || 'left_early' || 'partial' =>
      TodayStatusGroup.present,
    'absent' => TodayStatusGroup.absent,
    'mission' || 'convoy' || 'fundraising' => TodayStatusGroup.offsite,
    'on_leave' => TodayStatusGroup.leave,
    _ => TodayStatusGroup.other,
  };
}

/// تواريخ ISO داخل النصوص (2026-10-03) تنقلب في سياق عربي إلى 03-10-2026؛
/// الشرطة المائلة لا تنقلب.
String humanizeIsoDates(String text) => text.replaceAllMapped(
  RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})'),
  (m) => '${m[3]!.padLeft(2, '0')}/${m[2]!.padLeft(2, '0')}/${m[1]}',
);
