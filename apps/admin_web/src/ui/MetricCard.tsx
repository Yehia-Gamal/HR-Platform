import { ArrowUpLeft, ArrowRight, type LucideIcon } from 'lucide-react';
import { Link } from 'react-router';

export function MetricCard({
  label,
  value,
  hint,
  icon: Icon,
  trend,
  to,
  onClick,
  ariaLabel,
  compact = false,
}: {
  label: string;
  value: number | string;
  hint?: string;
  icon: LucideIcon;
  trend?: string;
  to?: string;
  onClick?: () => void;
  ariaLabel?: string;
  compact?: boolean;
}) {
  const clickable = Boolean(to) || Boolean(onClick);
  const a11yLabel = ariaLabel ?? `عرض تفاصيل ${label}`;
  const card = (
    <article className={`metric-card${compact ? ' !p-3 sm:!p-3.5' : ''}${clickable ? ' metric-card--linked' : ''}`}>
      <div className="flex items-start justify-between gap-2.5">
        <div className="min-w-0 flex-1">
          <p className="truncate text-xs font-extrabold text-[var(--text-muted)]">{label}</p>
          <div className={`${compact ? 'mt-1' : 'mt-2'} flex flex-wrap items-end gap-2`}>
            <p className={`${compact ? 'text-2xl' : 'text-3xl'} font-black tracking-tight text-[var(--text-primary)]`}>{value}</p>
            {trend ? (
              <span className="metric-trend">
                <ArrowUpLeft className="size-3" aria-hidden="true" />
                {trend}
              </span>
            ) : null}
          </div>
        </div>
        <span className={`metric-icon ${compact ? '!size-9 shrink-0 !rounded-lg' : ''}`}>
          <Icon className={compact ? 'size-4' : 'size-5'} aria-hidden="true" />
        </span>
      </div>
      {hint ? <p className={`${compact ? 'mt-2 text-[11px] leading-4' : 'mt-3 text-xs leading-5'} text-[var(--text-muted)] truncate`}>{hint}</p> : null}
      {clickable ? (
        <span className={`${compact ? 'mt-1.5 text-[11px]' : 'mt-2 text-xs'} flex items-center gap-1 font-bold text-[var(--brand-primary)]`}>
          <ArrowRight className="size-3" aria-hidden="true" />
          عرض التفاصيل
        </span>
      ) : null}
    </article>
  );

  if (to) {
    return (
      <Link to={to} className="block no-underline text-inherit" aria-label={a11yLabel}>
        {card}
      </Link>
    );
  }
  if (onClick) {
    return (
      <button type="button" onClick={onClick} aria-label={a11yLabel} className="metric-card--action block w-full text-start text-inherit">
        {card}
      </button>
    );
  }
  return card;
}
