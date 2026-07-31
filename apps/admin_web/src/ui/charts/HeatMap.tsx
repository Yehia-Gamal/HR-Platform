import { useCallback, useMemo, useState } from 'react';

import { ARABIC_DAYS } from './chartTheme';

/**
 * خريطة حرارية (HeatMap) — شبكة CSS بحتة (بدون recharts).
 * 7 أعمدة (أيام الأسبوع) × 24 صفاً (ساعات اليوم).
 * شدة اللون مبنية على القيمة (أدنى → أعلى = شفافية 0.1 → 1.0).
 */

export interface HeatMapDatum {
  /** اسم اليوم بالعربية (الأحد, الاثنين, …) */
  day: string;
  /** الساعة (0–23) */
  hour: number;
  /** القيمة الرقمية */
  value: number;
}

interface HeatMapProps {
  data: HeatMapDatum[];
  /** ارتفاع الخلية بالبكسل */
  height?: number;
  /** مقياس اللون */
  colorScale?: 'green' | 'blue' | 'red';
}

/* ألوان القاعدة لكل مقياس — تعمل في الوضعين الفاتح والداكن */
const BASE_COLORS: Record<string, string> = {
  green: 'var(--success)',
  blue: 'var(--brand-primary)',
  red: 'var(--danger)',
};

/** تنسيق الأرقام بالعربية */
function formatNumber(value: number): string {
  return value.toLocaleString('ar-EG');
}

/** تحويل الساعة إلى نص عربي (مثال: ٠٣:٠٠) */
function formatHour(h: number): string {
  return `${h.toString().padStart(2, '0')}:00`.replace(/\d/g, (d) => String.fromCharCode(0x0660 + Number(d)));
}

/* ───────────────── المكون ───────────────── */

export function HeatMap({ data, height = 18, colorScale = 'green' }: HeatMapProps) {
  const [tooltip, setTooltip] = useState<{
    day: string;
    hour: number;
    value: number;
    x: number;
    y: number;
  } | null>(null);

  /* بناء خريطة بحث (day → hour → value) + حساب الحد الأدنى/الأعلى */
  const { lookup, minVal, maxVal } = useMemo(() => {
    const map = new Map<string, Map<number, number>>();
    let mn = Infinity;
    let mx = -Infinity;

    for (const d of data) {
      if (!map.has(d.day)) map.set(d.day, new Map());
      map.get(d.day)!.set(d.hour, d.value);
      if (d.value < mn) mn = d.value;
      if (d.value > mx) mx = d.value;
    }

    return { lookup: map, minVal: mn === Infinity ? 0 : mn, maxVal: mx === -Infinity ? 0 : mx };
  }, [data]);

  /** حساب الشفافية بناءً على القيمة (0.1 → 1.0) */
  const getOpacity = useCallback(
    (value: number | undefined): number => {
      if (value == null) return 0;
      if (maxVal === minVal) return 0.5;
      return 0.1 + ((value - minVal) / (maxVal - minVal)) * 0.9;
    },
    [minVal, maxVal],
  );

  const baseColor = BASE_COLORS[colorScale] ?? BASE_COLORS.green;

  /* ساعات اليوم من 0 إلى 23 */
  const hours = Array.from({ length: 24 }, (_, i) => i);

  return (
    <div className="relative w-full overflow-x-auto" style={{ direction: 'rtl' }}>
      {/* ── الشبكة ── */}
      <div
        className="inline-grid gap-px"
        style={{
          /* عمود التسميات + 7 أعمدة أيام */
          gridTemplateColumns: `2.5rem repeat(7, minmax(0, 1fr))`,
          gridTemplateRows: `auto repeat(24, ${height}px)`,
          minWidth: 360,
          width: '100%',
        }}
      >
        {/* ── صف رأس الأيام ── */}
        <div />
        {ARABIC_DAYS.map((day) => (
          <div key={day} className="grid place-items-center text-[0.65rem] font-extrabold text-[var(--text-muted)]">
            {day}
          </div>
        ))}

        {/* ── الصفوف (ساعات) ── */}
        {hours.map((h) => (
          <>
            {/* تسمية الساعة */}
            <div key={`h-${h}`} className="grid place-items-center text-[0.6rem] font-bold text-[var(--text-muted)]">
              {h % 3 === 0 ? formatHour(h) : ''}
            </div>

            {/* خلايا الأيام */}
            {ARABIC_DAYS.map((day) => {
              const val = lookup.get(day)?.get(h);
              const opacity = getOpacity(val);

              return (
                <div
                  key={`${day}-${h}`}
                  className="cursor-pointer rounded-sm transition-transform hover:scale-110"
                  style={{
                    background: val != null ? baseColor : 'var(--surface-muted)',
                    opacity: val != null ? opacity : 0.15,
                  }}
                  onMouseEnter={(e) => {
                    const rect = e.currentTarget.getBoundingClientRect();
                    setTooltip({
                      day,
                      hour: h,
                      value: val ?? 0,
                      x: rect.left + rect.width / 2,
                      y: rect.top,
                    });
                  }}
                  onMouseLeave={() => setTooltip(null)}
                  role="gridcell"
                  aria-label={`${day} ${formatHour(h)}: ${formatNumber(val ?? 0)}`}
                />
              );
            })}
          </>
        ))}
      </div>

      {/* ── التلميح ── */}
      {tooltip && (
        <div
          className="pointer-events-none fixed z-50 rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3 py-2 text-xs shadow-lg"
          style={{
            direction: 'rtl',
            left: tooltip.x,
            top: tooltip.y - 8,
            transform: 'translate(-50%, -100%)',
          }}
        >
          <p className="font-extrabold text-[var(--text-primary)]">
            {tooltip.day} — {formatHour(tooltip.hour)}
          </p>
          <p className="mt-0.5 text-[var(--text-muted)]">
            القيمة: <span className="font-bold text-[var(--text-primary)]">{formatNumber(tooltip.value)}</span>
          </p>
        </div>
      )}
    </div>
  );
}
