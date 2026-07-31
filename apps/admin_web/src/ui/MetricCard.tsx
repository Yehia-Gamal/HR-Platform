import { ArrowUpLeft, type LucideIcon } from 'lucide-react';

export function MetricCard({
  label,
  value,
  hint,
  icon: Icon,
  trend,
}: {
  label: string;
  value: number | string;
  hint?: string;
  icon: LucideIcon;
  trend?: string;
}) {
  return (
    <article className="metric-card">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate text-xs font-extrabold text-[var(--text-muted)]">{label}</p>
          <div className="mt-2 flex flex-wrap items-end gap-2">
            <p className="text-3xl font-black tracking-tight">{value}</p>
            {trend ? (
              <span className="metric-trend">
                <ArrowUpLeft className="size-3" aria-hidden="true" />
                {trend}
              </span>
            ) : null}
          </div>
        </div>
        <span className="metric-icon">
          <Icon className="size-5" aria-hidden="true" />
        </span>
      </div>
      {hint ? <p className="mt-3 text-xs leading-5 text-[var(--text-muted)]">{hint}</p> : null}
    </article>
  );
}
