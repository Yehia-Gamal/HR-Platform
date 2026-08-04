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
