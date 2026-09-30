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

function toCairoDateParts(date: string | Date): { year: number; month: number; day: number } {
  if (typeof date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
    const [y, m, d] = date.split('-').map(Number);
    return { year: y, month: m, day: d };
  }
  const d = typeof date === 'string' ? new Date(date) : date;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: CAIRO_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(d);
  const map: Record<string, string> = {};
  for (const part of parts) map[part.type] = part.value;
  return {
    year: Number(map.year),
    month: Number(map.month),
    day: Number(map.day),
  };
}

function formatDateParts(y: number, m: number, d: number): string {
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/** إضافة أيام لتاريخ (مع احترام توقيت القاهرة وحماية كاملة من إزاحات التوقيت) */
export function addDays(date: string | Date, days: number): string {
  const p = toCairoDateParts(date);
  const dt = new Date(Date.UTC(p.year, p.month - 1, p.day));
  dt.setUTCDate(dt.getUTCDate() + days);
  return formatDateParts(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

/** بداية أسبوع العمل (السبت) لتاريخ معين */
export function startOfWeek(date: string | Date): string {
  const p = toCairoDateParts(date);
  const dt = new Date(Date.UTC(p.year, p.month - 1, p.day));
  const weekday = dt.getUTCDay();
  const daysSinceSaturday = (weekday + 1) % 7;
  dt.setUTCDate(dt.getUTCDate() - daysSinceSaturday);
  return formatDateParts(dt.getUTCFullYear(), dt.getUTCMonth() + 1, dt.getUTCDate());
}

/** نهاية أسبوع العمل (الخميس) لتاريخ معين (الجمعة هي يوم الراحة الأسبوعية) */
export function endOfWeek(date: string | Date): string {
  return addDays(startOfWeek(date), 5);
}

/** بداية الشهر لتاريخ معين */
export function startOfMonth(date: string | Date): string {
  const p = toCairoDateParts(date);
  return formatDateParts(p.year, p.month, 1);
}

/** نهاية الشهر لتاريخ معين */
export function endOfMonth(date: string | Date): string {
  const p = toCairoDateParts(date);
  const lastDay = new Date(Date.UTC(p.year, p.month, 0)).getUTCDate();
  return formatDateParts(p.year, p.month, lastDay);
}

/** تنسيق تاريخ بصيغة ISO مع توقيت القاهرة */
export function formatISO(date: string | Date): string {
  const p = toCairoDateParts(date);
  return formatDateParts(p.year, p.month, p.day);
}
