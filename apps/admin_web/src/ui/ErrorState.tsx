import { AlertTriangle, RefreshCw } from 'lucide-react';
import type { ReactNode } from 'react';

/**
 * Distinct, danger-styled error surface for failed data loads.
 * Use this instead of EmptyState (which reads as a benign "no data" state)
 * whenever a query fails, so a load failure is visually and semantically
 * flagged as an error. Tokenised so it adapts to the dark theme.
 */
export function ErrorState({
  title = 'تعذّر تحميل البيانات',
  description,
  onRetry,
  action,
}: {
  title?: string;
  description?: string;
  onRetry?: () => void;
  action?: ReactNode;
}) {
  return (
    <div
      role="alert"
      className="card grid min-h-56 place-items-center border-[var(--danger)]/40 p-8 text-center"
      style={{ borderColor: 'color-mix(in srgb, var(--danger) 40%, var(--border))' }}
    >
      <div className="max-w-md">
        <span className="mx-auto grid size-14 place-items-center rounded-2xl bg-[var(--danger-soft)] text-[var(--danger)]">
          <AlertTriangle className="size-6" aria-hidden="true" />
        </span>
        <h2 className="mt-4 text-lg font-black">{title}</h2>
        {description ? <p className="mt-2 text-sm leading-7 text-[var(--text-muted)]">{description}</p> : null}
        {action ? (
          <div className="mt-4 flex justify-center">{action}</div>
        ) : onRetry ? (
          <div className="mt-4 flex justify-center">
            <button type="button" className="btn-secondary" onClick={onRetry}>
              <RefreshCw className="size-4" />إعادة المحاولة
            </button>
          </div>
        ) : null}
      </div>
    </div>
  );
}

/** Compact inline error banner for mutation failures inside a form/panel. */
export function ErrorBanner({ message }: { message: string }) {
  return (
    <div
      role="alert"
      className="rounded-xl border p-3.5 text-sm font-bold"
      style={{
        borderColor: 'color-mix(in srgb, var(--danger) 40%, var(--border))',
        background: 'var(--danger-soft)',
        color: 'var(--danger)',
      }}
    >
      {message}
    </div>
  );
}
