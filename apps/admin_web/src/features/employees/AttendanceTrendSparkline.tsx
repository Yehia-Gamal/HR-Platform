import { cairoDateIso } from './useAttendanceTrend';
import type { AttendanceTrendPoint } from './useAttendanceTrend';

// منحنّى مصغّر (sparkline) أسبوعي لنسبة الحضور — 7 أعمدة SVG بدون مكتبات.
// لون كل عمود: أخضر >80% · برتقالي 50-80% · أحمر <50%.
// التمرير فوق أي عمود يُظهر تاريخ اليوم والنسبة عبر عنصر <title> الأصلي.

export function AttendanceTrendSparkline({
  points,
}: {
  points: AttendanceTrendPoint[];
}) {
  const data = points.length ? points : [];
  const width = 140;
  const height = 36;
  const gap = 3;
  const barWidth = data.length ? (width - gap * (data.length - 1)) / data.length : 0;

  const fmtDate = (iso: string): string => {
    const d = new Date(`${iso}T00:00:00`);
    return new Intl.DateTimeFormat('ar-EG', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(d);
  };

  return (
    <div className="mt-2 flex flex-col gap-1 border-t border-[var(--border)] pt-2">
      <div className="flex items-center justify-between">
        <span className="text-[10px] font-bold text-[var(--text-muted)]">اتجاه 7 أيام</span>
      </div>
      <svg
        role="img"
        aria-label="اتجاه نسبة الحضور آخر 7 أيام"
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        className="overflow-visible"
      >
        {data.map((p, i) => {
          const ratio = p.scheduled > 0 ? p.present / p.scheduled : 0;
          const pct = Math.round(ratio * 100);
          const barH = Math.max(2, ratio * height);
          const x = i * (barWidth + gap);
          const y = height - barH;
          const fill = pct > 80 ? 'var(--success)' : pct >= 50 ? 'var(--warning)' : 'var(--danger)';
          return (
            <rect
              key={p.date}
              x={x}
              y={y}
              width={Math.max(1, barWidth)}
              height={barH}
              rx={1.5}
              fill={fill}
              opacity={0.9}
            >
              <title>{`${fmtDate(p.date)}: ${pct}% (${p.present}/${p.scheduled})`}</title>
            </rect>
          );
        })}
      </svg>
      <div className="flex items-center justify-between text-[9px] text-[var(--text-muted)]">
        <span>{data.length ? fmtDate(data[0].date) : '—'}</span>
        <span>{data.length ? fmtDate(data[data.length - 1].date) : cairoDateIso(0)}</span>
      </div>
    </div>
  );
}
