// أدوات تنسيق الوقت المشتركة — تستخدمها لوحة المتابعة التنفيذية
// وقسم "نبض اليوم" وصفحة الموقع الحي لتفادي تكرار المنطق.

/** يحوّل ISO إلى نص نسبي عربي مثل "منذ 5 د" أو "الآن" أو "منذ 3 س". */
export function relativeTime(value: string | null | undefined, fallback = '—'): string {
  if (!value) return fallback;
  const m = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 60000));
  if (m < 1) return 'الآن';
  if (m < 60) return `منذ ${m} د`;
  const h = Math.round(m / 60);
  return h < 24 ? `منذ ${h} س` : `منذ ${Math.round(h / 24)} يوم`;
}

/** ينسّق الوقت فقط (ساعة:دقيقة) بالعربية. */
export function formatClock(value: string | null | undefined): string {
  if (!value) return '—';
  return new Intl.DateTimeFormat('ar-EG', { hour: '2-digit', minute: '2-digit' }).format(new Date(value));
}
