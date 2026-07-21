/**
 * Shared in-page loading skeletons that match the app's card/metric surfaces.
 * Use these while a query is loading instead of leaving the content area blank
 * or dropping in a bare "جارٍ التحميل…" line, so the layout is stable and the
 * loading experience is consistent across pages.
 */

export function SkeletonCard({ className = '' }: { className?: string }) {
  return <div className={`card animate-pulse bg-[var(--surface-muted)] ${className}`} aria-hidden="true" />;
}

/** A grid of metric-card sized skeletons — mirrors the standard 4-up metric row. */
export function MetricSkeletonRow({ count = 4 }: { count?: number }) {
  return (
    <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-hidden="true">
      {Array.from({ length: count }).map((_, index) => (
        <div key={index} className="metric-card animate-pulse">
          <div className="h-3.5 w-24 rounded bg-[var(--surface-muted)]" />
          <div className="mt-3 h-8 w-16 rounded bg-[var(--surface-muted)]" />
          <div className="mt-3 h-3 w-full rounded bg-[var(--surface-muted)]" />
        </div>
      ))}
    </section>
  );
}

/** A stack of list-row skeletons for feed/list content areas. */
export function ListSkeleton({ rows = 3, label = 'جارٍ التحميل…' }: { rows?: number; label?: string }) {
  return (
    <section className="space-y-3" aria-busy="true" aria-label={label}>
      {Array.from({ length: rows }).map((_, index) => (
        <div key={index} className="card animate-pulse p-5">
          <div className="h-4 w-1/3 rounded bg-[var(--surface-muted)]" />
          <div className="mt-3 h-3 w-2/3 rounded bg-[var(--surface-muted)]" />
          <div className="mt-2 h-3 w-1/2 rounded bg-[var(--surface-muted)]" />
        </div>
      ))}
    </section>
  );
}
