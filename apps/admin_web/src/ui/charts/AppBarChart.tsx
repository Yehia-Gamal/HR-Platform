import { useMemo } from 'react';
import { Bar, BarChart, CartesianGrid, Legend, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';

/** تعريف عمود واحد في الرسم البياني */
export interface BarDef {
  key: string;
  label: string;
  color?: string;
}

interface AppBarChartProps {
  data: Record<string, unknown>[];
  bars: BarDef[];
  xKey?: string;
  height?: number;
  horizontal?: boolean;
  stacked?: boolean;
}

/* ألوان افتراضية مأخوذة من متغيرات التصميم */
const PALETTE = ['var(--brand-primary)', 'var(--success)', 'var(--warning)', 'var(--danger)', 'var(--info)', 'var(--brand-accent)'];

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
  bars,
}: {
  active?: boolean;
  payload?: { dataKey: string; value: number; color: string }[];
  label?: string;
  bars: BarDef[];
}) {
  if (!active || !payload?.length) return null;

  const labelMap = new Map(bars.map((b) => [b.key, b.label]));

  return (
    <div className="rounded-xl border border-[var(--border)] bg-[var(--surface)] px-3.5 py-2.5 text-xs shadow-lg" style={{ direction: 'rtl' }}>
      <p className="mb-1.5 font-extrabold text-[var(--text-primary)]">{label}</p>
      {payload.map((entry) => (
        <div key={entry.dataKey} className="flex items-center gap-2 py-0.5">
          <span className="inline-block size-2.5 shrink-0 rounded" style={{ background: entry.color }} />
          <span className="text-[var(--text-muted)]">{labelMap.get(entry.dataKey) ?? entry.dataKey}</span>
          <span className="mr-auto font-bold text-[var(--text-primary)]">{formatNumber(entry.value)}</span>
        </div>
      ))}
    </div>
  );
}

/* ───────────────── مكون الرسم البياني العمودي ───────────────── */

export function AppBarChart({ data, bars, xKey = 'name', height = 320, horizontal = false, stacked = false }: AppBarChartProps) {
  const resolvedBars = useMemo(() => bars.map((b, i) => ({ ...b, color: b.color ?? PALETTE[i % PALETTE.length] })), [bars]);

  const legendPayload = useMemo(() => resolvedBars.map((b) => ({ value: b.label, type: 'rect' as const, color: b.color })), [resolvedBars]);

  const stackId = stacked ? 'stack' : undefined;

  /* في الوضع الأفقي: المحاور تنعكس (category → Y, value → X) */
  const categoryAxis = (
    <XAxis
      {...(horizontal ? { type: 'number' as const } : { dataKey: xKey })}
      reversed={!horizontal}
      tick={{ fill: 'var(--text-muted)', fontSize: 12 }}
      axisLine={{ stroke: 'var(--border)' }}
      tickLine={false}
      tickFormatter={(v: unknown) => (horizontal ? formatNumber(v) : String(v ?? ''))}
      dy={horizontal ? 0 : 8}
    />
  );

  const valueAxis = (
    <YAxis
      {...(horizontal ? { dataKey: xKey, type: 'category' as const } : {})}
      orientation="right"
      tick={{ fill: 'var(--text-muted)', fontSize: 12 }}
      axisLine={false}
      tickLine={false}
      tickFormatter={(v: unknown) => (horizontal ? String(v ?? '') : formatNumber(v))}
      dx={4}
      width={horizontal ? 80 : 48}
    />
  );

  return (
    <ResponsiveContainer width="100%" height={height}>
      <BarChart data={data} layout={horizontal ? 'vertical' : 'horizontal'} margin={{ top: 8, left: 4, right: 4, bottom: 4 }} barCategoryGap="22%">
        <CartesianGrid strokeDasharray="6 4" stroke="var(--border)" horizontal={!horizontal} vertical={horizontal} />
        {categoryAxis}
        {valueAxis}
        <Tooltip content={<ChartTooltip bars={resolvedBars} />} cursor={{ fill: 'var(--surface-muted)', opacity: 0.6 }} />
        <Legend
          // eslint-disable-next-line @typescript-eslint/no-explicit-any -- Recharts Legend payload type mismatch
          {...({ payload: legendPayload } as any)}
          wrapperStyle={{ direction: 'rtl', paddingTop: 12 }}
          iconType="rect"
          iconSize={10}
          formatter={(value: string) => <span className="text-xs font-bold text-[var(--text-muted)]">{value}</span>}
        />
        {resolvedBars.map((b) => (
          <Bar
            key={b.key}
            dataKey={b.key}
            name={b.label}
            fill={b.color}
            stackId={stackId}
            radius={stacked ? 0 : [4, 4, 0, 0]}
            animationDuration={700}
            animationEasing="ease-out"
          />
        ))}
      </BarChart>
    </ResponsiveContainer>
  );
}
