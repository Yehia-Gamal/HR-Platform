import { useMemo } from 'react';
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  Line,
  LineChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';

/** تعريف خط واحد في الرسم البياني */
export interface LineDef {
  key: string;
  label: string;
  color?: string;
}

interface AppLineChartProps {
  data: Record<string, unknown>[];
  lines: LineDef[];
  xKey?: string;
  height?: number;
  area?: boolean;
  curved?: boolean;
}

/* ألوان افتراضية مأخوذة من متغيرات التصميم */
const PALETTE = [
  'var(--brand-primary)',
  'var(--success)',
  'var(--warning)',
  'var(--danger)',
  'var(--info)',
  'var(--brand-accent)',
];

/** تنسيق الأرقام بالعربية */
function formatNumber(value: unknown): string {
  if (typeof value !== 'number') return String(value ?? '');
  return value.toLocaleString('ar-EG');
}

/* ───────────────── محتوى التلميح ───────────────── */

function ChartTooltip({
  active,
  payload,
  label,
  lines,
}: {
  active?: boolean;
  payload?: { dataKey: string; value: number; color: string }[];
  label?: string;
  lines: LineDef[];
}) {
  if (!active || !payload?.length) return null;

  const labelMap = new Map(lines.map((l) => [l.key, l.label]));

  return (
    <div
      className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3.5 py-2.5 text-xs shadow-lg"
      style={{ direction: 'rtl' }}
    >
      <p className="mb-1.5 font-extrabold text-[var(--text-primary)]">{label}</p>
      {payload.map((entry) => (
        <div key={entry.dataKey} className="flex items-center gap-2 py-0.5">
          <span
            className="inline-block size-2.5 shrink-0 rounded-full"
            style={{ background: entry.color }}
          />
          <span className="text-[var(--text-muted)]">{labelMap.get(entry.dataKey) ?? entry.dataKey}</span>
          <span className="mr-auto font-bold text-[var(--text-primary)]">{formatNumber(entry.value)}</span>
        </div>
      ))}
    </div>
  );
}

/* ───────────────── مكون الرسم البياني الخطي ───────────────── */

export function AppLineChart({
  data,
  lines,
  xKey = 'name',
  height = 320,
  area = false,
  curved = true,
}: AppLineChartProps) {
  const resolvedLines = useMemo(
    () => lines.map((l, i) => ({ ...l, color: l.color ?? PALETTE[i % PALETTE.length] })),
    [lines],
  );

  const legendPayload = useMemo(
    () => resolvedLines.map((l) => ({ value: l.label, type: 'circle' as const, color: l.color })),
    [resolvedLines],
  );

  const curveType = curved ? 'monotone' : 'linear';

  const Chart = area ? AreaChart : LineChart;

  return (
    <ResponsiveContainer width="100%" height={height}>
      <Chart data={data} margin={{ top: 8, left: 4, right: 4, bottom: 4 }}>
        <CartesianGrid
          strokeDasharray="6 4"
          stroke="var(--border)"
          vertical={false}
        />
        <XAxis
          dataKey={xKey}
          reversed
          tick={{ fill: 'var(--text-muted)', fontSize: 12 }}
          axisLine={{ stroke: 'var(--border)' }}
          tickLine={false}
          tickFormatter={(v: unknown) => String(v ?? '')}
          dy={8}
        />
        <YAxis
          orientation="right"
          tick={{ fill: 'var(--text-muted)', fontSize: 12 }}
          axisLine={false}
          tickLine={false}
          tickFormatter={(v: number) => formatNumber(v)}
          dx={4}
        />
        <Tooltip
          content={<ChartTooltip lines={resolvedLines} />}
          cursor={{ stroke: 'var(--border-strong)', strokeDasharray: '4 4' }}
        />
        <Legend
          // eslint-disable-next-line @typescript-eslint/no-explicit-any -- Recharts Legend payload type mismatch
          {...{ payload: legendPayload } as any}
          wrapperStyle={{ direction: 'rtl', paddingTop: 12 }}
          iconType="circle"
          iconSize={10}
          formatter={(value: string) => (
            <span className="text-xs font-bold text-[var(--text-muted)]">{value}</span>
          )}
        />
        {area
          ? resolvedLines.map((l) => (
              <Area
                key={l.key}
                type={curveType}
                dataKey={l.key}
                name={l.label}
                stroke={l.color}
                strokeWidth={2.5}
                fill={l.color}
                fillOpacity={0.12}
                dot={false}
                activeDot={{ r: 5, strokeWidth: 2, fill: 'var(--surface)' }}
                animationDuration={700}
                animationEasing="ease-out"
              />
            ))
          : resolvedLines.map((l) => (
              <Line
                key={l.key}
                type={curveType}
                dataKey={l.key}
                name={l.label}
                stroke={l.color}
                strokeWidth={2.5}
                dot={false}
                activeDot={{ r: 5, strokeWidth: 2, fill: 'var(--surface)' }}
                animationDuration={700}
                animationEasing="ease-out"
              />
            ))}
      </Chart>
    </ResponsiveContainer>
  );
}
