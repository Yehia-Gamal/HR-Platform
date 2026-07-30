import { useMemo } from 'react';
import { Line, LineChart, ResponsiveContainer, YAxis } from 'recharts';

/**
 * خط بياني مصغّر (Sparkline) — بلا محاور أو تسميات.
 * يُستخدم داخل بطاقات المؤشرات (MetricCard) لعرض الاتجاه بسرعة.
 */

interface SparklineProps {
  /** مصفوفة القيم الرقمية */
  data: number[];
  /** لون الخط — يُتجاهل عند تفعيل التلوين حسب الاتجاه */
  color?: string;
  /** ارتفاع المكون بالبكسل */
  height?: number;
  /** عرض المكون بالبكسل */
  width?: number;
}

/** يحدد لون الاتجاه: أخضر إذا صاعد، أحمر إذا هابط */
function getTrendColor(data: number[]): string {
  if (data.length < 2) return 'var(--brand-primary)';
  const first = data[0];
  const last = data[data.length - 1];
  if (last > first) return 'var(--success)';
  if (last < first) return 'var(--danger)';
  return 'var(--brand-primary)';
}

export function Sparkline({
  data,
  color,
  height = 32,
  width = 120,
}: SparklineProps) {
  /* تحويل المصفوفة لنقاط بيانات recharts */
  const points = useMemo(
    () => data.map((v, i) => ({ i, v })),
    [data],
  );

  const strokeColor = color ?? getTrendColor(data);

  if (!data.length) return null;

  return (
    <div style={{ width, height }} className="inline-block shrink-0">
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={points} margin={{ top: 2, right: 2, bottom: 2, left: 2 }}>
          {/* محور Y مخفي لضبط النطاق تلقائياً */}
          <YAxis hide domain={['dataMin', 'dataMax']} />
          <Line
            type="monotone"
            dataKey="v"
            stroke={strokeColor}
            strokeWidth={2}
            dot={false}
            activeDot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
