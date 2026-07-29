import { Bell, CheckCheck } from 'lucide-react';
import { Link } from 'react-router-dom';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { useMarkNotificationsRead, useNotifications } from './useNotifications';

export function NotificationsPage() {
  const q = useNotifications();
  const mark = useMarkNotificationsRead();
  const items = q.data ?? [];
  const unread = items.filter(x => !x.isRead);

  return (
    <div className="space-y-6">
      <PageHeader
        title="الإشعارات"
        description="كل إشعار يفتح وجهته الفعلية، ويُصفّر العداد عند فتح مركز الإشعارات أو تنفيذ القراءة."
        actions={
          <button
            disabled={!unread.length || mark.isPending}
            onClick={() => mark.mutate(undefined)}
            className="btn-secondary disabled:opacity-50"
          >
            <CheckCheck className="size-4" aria-hidden="true" />
            تعليم الكل كمقروء
          </button>
        }
      />

      {q.isError ? (
        <ErrorState
          title="تعذر تحميل الإشعارات"
          description={q.error instanceof Error ? q.error.message : undefined}
          onRetry={() => void q.refetch()}
        />
      ) : q.isLoading ? (
        <section className="space-y-3" aria-label="جارٍ تحميل الإشعارات">
          {[1, 2, 3].map(i => (
            <div
              key={i}
              className="card h-24 animate-pulse bg-[var(--surface-muted)]"
            />
          ))}
        </section>
      ) : !items.length ? (
        <EmptyState
          title="لا توجد إشعارات"
          description="ستظهر هنا التنبيهات الموجهة إلى حسابك."
        />
      ) : (
        <section className="space-y-3">
          {items.map(n => (
            <article
              key={n.id}
              aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}
              className={`card p-5 ${n.isRead ? 'opacity-75' : 'border-[var(--brand-primary)]/40'}`}
            >
              <div className="flex flex-col gap-4 md:flex-row md:items-center">
                <span
                  aria-hidden="true"
                  className="grid size-11 shrink-0 place-items-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]"
                >
                  <Bell className="size-5" />
                </span>

                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap gap-2">
                    <StatusBadge value={n.priority} />
                    <span className="muted text-xs">{n.category}</span>
                    {!n.isRead ? (
                      <span className="rounded-full bg-[var(--brand-primary)] px-2 py-0.5 text-xs font-bold text-white">
                        جديد
                      </span>
                    ) : null}
                  </div>

                  <h2 className="mt-2 font-black">{n.title}</h2>

                  {n.body ? (
                    <p className="muted mt-1 text-sm">{n.body}</p>
                  ) : null}

                  <time
                    dateTime={new Date(n.createdAt).toISOString()}
                    className="muted mt-2 block text-xs"
                  >
                    {new Intl.DateTimeFormat('ar-EG', {
                      dateStyle: 'medium',
                      timeStyle: 'short',
                    }).format(new Date(n.createdAt))}
                  </time>
                </div>

                {n.actionUrl ? (
                  <Link
                    to={n.actionUrl}
                    onClick={() => !n.isRead && mark.mutate([n.id])}
                    className="btn-primary text-sm"
                  >
                    فتح
                  </Link>
                ) : null}
              </div>
            </article>
          ))}
        </section>
      )}
    </div>
  );
}
