import type { ReactNode } from 'react';
import { ResponsiveContainer } from 'recharts';
import { Inbox } from 'lucide-react';

/**
 * بطاقة غلاف للرسوم البيانية — عنوان + منطقة رسم مع أحوال التحميل والفراغ.
 */
export function ChartCard({
  title,
  subtitle,
  children,
  loading = false,
  empty = false,
  height = 300,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  loading?: boolean;
  empty?: boolean;
  height?: number;
}) {
  return (
    <article className="card overflow-hidden">
      {/* ── الرأس ── */}
      <div className="flex items-start justify-between gap-3 p-4 pb-0">
        <div className="min-w-0">
          <h3 className="truncate text-sm font-black">{title}</h3>
          {subtitle ? <p className="mt-0.5 text-xs leading-5 text-[var(--text-muted)]">{subtitle}</p> : null}
        </div>
      </div>

      {/* ── منطقة الرسم ── */}
      <div className="px-2 pb-3 pt-2" style={{ height }}>
        {loading ? (
          <div className="flex h-full items-center justify-center" aria-busy="true">
            <div className="w-full space-y-3 px-4">
              <div className="h-3 w-3/4 animate-pulse rounded bg-[var(--surface-muted)]" />
              <div className="h-3 w-1/2 animate-pulse rounded bg-[var(--surface-muted)]" />
              <div className="mx-auto h-28 w-full animate-pulse rounded-xl bg-[var(--surface-muted)]" />
              <div className="h-3 w-2/3 animate-pulse rounded bg-[var(--surface-muted)]" />
            </div>
          </div>
        ) : empty ? (
          <div className="grid h-full place-items-center text-center">
            <div className="max-w-xs">
              <span className="mx-auto grid size-12 place-items-center rounded-2xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
                <Inbox className="size-5" aria-hidden="true" />
              </span>
              <p className="mt-3 text-sm font-black">لا توجد بيانات</p>
              <p className="mt-1 text-xs leading-5 text-[var(--text-muted)]">لم تتوفر بيانات كافية لعرض الرسم البياني</p>
            </div>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            {children as React.ReactElement}
          </ResponsiveContainer>
        )}
      </div>
    </article>
  );
}
