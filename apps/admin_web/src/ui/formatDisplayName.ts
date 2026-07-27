/**
 * أدوات تنسيق اسم العرض والترحيب.
 * تُستخدم في الـ sidebar والـ dashboard hero والـ header profile.
 */

/** أول كلمتين من الاسم الكامل — مناسب للترحيب والعرض المختصر. */
export function getShortName(fullName: string): string {
  const parts = fullName.trim().split(/\s+/);
  if (parts.length <= 2) return fullName.trim();
  return parts.slice(0, 2).join(' ');
}

/** تحية حسب الوقت: صباح الخير / مساء الخير. */
export function getTimeGreeting(): string {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return 'صباح الخير';
  if (hour >= 12 && hour < 17) return 'مساء الخير';
  if (hour >= 17 && hour < 21) return 'مساء الخير';
  return 'أهلاً';
}
