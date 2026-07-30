import { useCallback } from 'react';
import {
  RadarChart,
  Radar,
  PolarGrid,
  PolarAngleAxis,
  PolarRadiusAxis,
  Tooltip,
  Legend,
} from 'recharts';
import { getChartColors, TOOLTIP_STYLE } from './chartTheme';

type RadarSeries = { key: string; label: string; color?: string };

/**
 * رسم بياني شبكي (Radar) مع دعم سلاسل متعددة وتسميات عربية.
 */
export function AppRadarChart({
  data,
  series,
  height = 300,
}: {
  data: Record<string, unknown>[];
  series: RadarSeries[];
  height?: number;
}) {
  const palette = getChartColors();

  const formatAr = useCallback(
    (v: number) => new Intl.NumberFormat('ar-SA').format(v),
    [],
  );

  return (
    <RadarChart
      width={500}
      height={height}
      data={data}
      cx="50%"
      cy="50%"
      outerRadius="70%"
    >
      <PolarGrid stroke="var(--border)" strokeDasharray="4 4" />

      <PolarAngleAxis
        dataKey="subject"
        tick={{
          fill: 'var(--text-primary)',
          fontSize: 11,
          fontWeight: 700,
        }}
        style={{ direction: 'rtl' }}
      />

      <PolarRadiusAxis
        angle={90}
        tick={{
          fill: 'var(--text-muted)',
          fontSize: 10,
          fontWeight: 700,
        }}
        axisLine={false}
      />

      {series.map((s, i) => {
        const color = s.color ?? palette[i % palette.length];
        return (
          <Radar
            key={s.key}
            name={s.label}
            dataKey={s.key}
            stroke={color}
            fill={color}
            fillOpacity={0.15}
            strokeWidth={2}
            isAnimationActive
          />
        );
      })}

      <Tooltip
        contentStyle={TOOLTIP_STYLE}
        formatter={(value: number, name: string) => [
          formatAr(value),
          name,
        ]}
        separator=" : "
        labelStyle={{
          direction: 'rtl',
          fontWeight: 700,
          marginBottom: 4,
        }}
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
      />
    </RadarChart>
  );
}
