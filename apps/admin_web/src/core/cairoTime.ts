const CAIRO_TZ = 'Africa/Cairo';

function cairoParts(): Record<string, string> {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: CAIRO_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  }).formatToParts(new Date());
  const map: Record<string, string> = {};
  for (const part of parts) map[part.type] = part.value;
  return map;
}

/** تاريخ اليوم في توقيت القاهرة بصيغة YYYY-MM-DD */
export function cairoTodayIso(): string {
  const p = cairoParts();
  return `${p.year}-${p.month}-${p.day}`;
}

/** الشهر الحالي في توقيت القاهرة بصيغة YYYY-MM */
export function cairoMonthIso(): string {
  return cairoTodayIso().slice(0, 7);
}

/** إضافة أيام لتاريخ (مع احترام توقيت القاهرة) */
export function addDays(date: string | Date, days: number): string {
  const d = new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ }));
  d.setDate(d.getDate() + days);
  return d.toISOString().split('T')[0];
}

/** بداية الأسبوع (الأحد) لتاريخ معين */
export function startOfWeek(date: string | Date): string {
  const d = new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ }));
  const day = d.getDay();
  const diff = d.getDate() - day;
  d.setDate(diff);
  return d.toISOString().split('T')[0];
}

/** نهاية الأسبوع (السبت) لتاريخ معين */
export function endOfWeek(date: string | Date): string {
  const d = new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ }));
  const day = d.getDay();
  const diff = d.getDate() + (6 - day);
  d.setDate(diff);
  return d.toISOString().split('T')[0];
}

/** بداية الشهر لتاريخ معين */
export function startOfMonth(date: string | Date): string {
  const d = new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ }));
  d.setDate(1);
  return d.toISOString().split('T')[0];
}

/** نهاية الشهر لتاريخ معين */
export function endOfMonth(date: string | Date): string {
  const d = new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ }));
  d.setMonth(d.getMonth() + 1, 0);
  return d.toISOString().split('T')[0];
}

/** تنسيق تاريخ بصيغة ISO مع توقيت القاهرة */
export function formatISO(date: string | Date): string {
  return new Date(new Date(date).toLocaleString('en-US', { timeZone: CAIRO_TZ })).toISOString();
}
