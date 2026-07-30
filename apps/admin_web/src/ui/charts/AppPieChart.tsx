import { useCallback } from 'react';
import { PieChart, Pie, Cell, Tooltip, Legend } from 'recharts';
import { getChartColors, TOOLTIP_STYLE } from './chartTheme';

type PieDataPoint = { name: string; value: number; color?: string };

/**
 * رسم بياني دائري (Pie / Donut) مع تسميات ووسائل إيضاح عربية.
 */
export function AppPieChart({
  data,
  height = 300,
  donut = false,
  showLabels = true,
}: {
  data: PieDataPoint[];
  height?: number;
  donut?: boolean;
  showLabels?: boolean;
}) {
  const palette = getChartColors();
  const total = data.reduce((s, d) => s + d.value, 0);

  const formatAr = useCallback(
    (v: number) => new Intl.NumberFormat('ar-SA').format(v),
    [],
  );

  /** تسمية عربية مخصصة — الاسم + النسبة المئوية */
  const renderLabel = useCallback(
    (entry: { name?: string; value?: number; cx?: number; cy?: number; midAngle?: number; outerRadius?: number }) => {
      if (!showLabels || total === 0) return null;
      const RADIAN = Math.PI / 180;
      const { cx = 0, cy = 0, midAngle = 0, outerRadius = 0, name = '', value = 0 } = entry;
      const radius = outerRadius + 22;
      const x = cx + radius * Math.cos(-midAngle * RADIAN);
      const y = cy + radius * Math.sin(-midAngle * RADIAN);
      const pct = ((value / total) * 100).toFixed(1);

      return (
        <text
          x={x}
          y={y}
          textAnchor={x > cx ? 'start' : 'end'}
          dominantBaseline="central"
          style={{
            fontSize: 11,
            fontWeight: 700,
            fill: 'var(--text-primary)',
            direction: 'rtl',
          }}
        >
          {`${name} (${pct}٪)`}
        </text>
      );
    },
    [showLabels, total],
  );

  return (
    <PieChart width={500} height={height}>
      <Pie
        data={data}
        dataKey="value"
        nameKey="name"
        cx="50%"
        cy="50%"
        innerRadius={donut ? '60%' : 0}
        outerRadius="75%"
        paddingAngle={data.length > 1 ? 2 : 0}
        // eslint-disable-next-line @typescript-eslint/no-explicit-any -- Recharts PieLabelRenderProps mismatch
        label={showLabels ? (renderLabel as any) : false}
        labelLine={showLabels}
        isAnimationActive
      >
        {data.map((entry, i) => (
          <Cell key={entry.name} fill={entry.color ?? palette[i % palette.length]} />
        ))}
      </Pie>

      <Tooltip
        contentStyle={TOOLTIP_STYLE}
        formatter={(value: unknown, name: unknown) => [
          formatAr(Number(value ?? 0)),
          String(name ?? ''),
        ]}
        separator=" : "
      />

      <Legend
        verticalAlign="bottom"
        align="center"
        iconType="circle"
        iconSize={8}
        wrapperStyle={{
          direction: 'rtl',
          fontSize: 11,
          fontWeight: 700,
          paddingTop: 8,
        }}
        formatter={(value: string) => {
          const item = data.find((d) => d.name === value);
          if (!item || total === 0) return value;
          const pct = ((item.value / total) * 100).toFixed(1);
          return `${value} (${formatAr(item.value)} — ${pct}٪)`;
        }}
      />
    </PieChart>
  );
}
