import { ArrowUpLeft, ArrowLeft, type LucideIcon } from 'lucide-react';
import { Link } from 'react-router';

export function MetricCard({
  label,
  value,
  hint,
  icon: Icon,
  trend,
  to,
}: {
  label: string;
  value: number | string;
  hint?: string;
  icon: LucideIcon;
  trend?: string;
  to?: string;
}) {
  const card = (
    <article className={`metric-card${to ? ' metric-card--linked' : ''}`}>
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
      {to ? (
        <span className="mt-2 flex items-center gap-1 text-xs font-bold text-[var(--brand-primary)]">
          <ArrowLeft className="size-3" aria-hidden="true" />
          عرض
        </span>
      ) : null}
    </article>
  );

  return to ? (
    <Link to={to} className="block no-underline text-inherit">{card}</Link>
  ) : (
    card
  );
}
