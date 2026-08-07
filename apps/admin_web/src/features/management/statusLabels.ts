// خريطة تسميات حالات الحضور اليومي — مشتركة بين لوحة المتابعة التنفيذية
// وقسم "نبض اليوم" في دليل الموظفين.
export const ATTENDANCE_STATUS_LABELS: Record<string, string> = {
  present: 'حاضر',
  late: 'متأخر',
  not_yet: 'لم يحضر بعد',
  absent: 'غائب',
  checked_out: 'انصرف',
  left_early: 'انصرف مبكرًا',
  on_leave: 'إجازة',
  assignment: 'مأمورية/قافلة/فاندي',
  weekend: 'راحة أسبوعية',
};

export function attendanceStatusLabel(status: string): string {
  return ATTENDANCE_STATUS_LABELS[status] ?? status;
}
