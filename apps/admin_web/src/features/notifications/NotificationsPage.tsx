import { Bell, CheckCheck } from 'lucide-react';
import { Link, useLocation } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { notificationTargetPath, notificationWorkspaceFromPath } from './notificationTarget';
import { useMarkNotificationsRead, useNotifications } from './useNotifications';

export function NotificationsPage() {
  const { toast } = useToast();
  const location = useLocation();
  const workspace = notificationWorkspaceFromPath(location.pathname);
  const q = useNotifications();
  const mark = useMarkNotificationsRead();
  const items = q.data ?? [];
  const unread = items.filter((x) => !x.isRead);

  return (
    <div className="space-y-6">
      <PageHeader
        title="الإشعارات"
        description="كل إشعار يفتح وجهته الفعلية، ويُصفّر العداد عند فتح مركز الإشعارات أو تنفيذ القراءة."
        actions={
          <button
            disabled={!unread.length || mark.isPending}
            onClick={() =>
              mark.mutate(undefined, {
                onSuccess: () => toast({ message: 'تم تعليم كل الإشعارات كمقروءة', tone: 'success' }),
                onError: () => toast({ message: 'تعذر تعليم الإشعارات', tone: 'error' }),
              })
            }
            className="btn-secondary disabled:opacity-50"
          >
            <CheckCheck className="size-4" aria-hidden="true" />
            تعليم الكل كمقروء
          </button>
        }
      />

      {mark.isError ? <ErrorBanner message={safeErrorMessage(mark.error)} /> : null}

      {q.isError ? (
        <ErrorState title="تعذر تحميل الإشعارات" description={safeErrorMessage(q.error)} onRetry={() => void q.refetch()} />
      ) : q.isLoading ? (
        <section aria-label="جارٍ تحميل الإشعارات">
          <ListSkeleton rows={3} label="جارٍ تحميل الإشعارات…" />
        </section>
      ) : !items.length ? (
        <EmptyState title="لا توجد إشعارات" description="ستظهر هنا التنبيهات الموجهة إلى حسابك." />
      ) : (
        <section className="space-y-3">
          {items.map((n) => {
            const target = notificationTargetPath(n, workspace);
            const card = (
              <article
                aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}
                className={`card p-5 ${n.isRead ? 'opacity-75' : 'border-[var(--brand-primary)]/40'}`}
              >
                <div className="flex flex-col gap-4 md:flex-row md:items-center">
                  <span aria-hidden="true" className="grid size-11 shrink-0 place-items-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
                    <Bell className="size-5" />
                  </span>

                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap gap-2">
                      <StatusBadge value={n.priority} />
                      <span className="muted text-xs">{n.category}</span>
                      {!n.isRead ? <span className="rounded-full bg-[var(--brand-primary)] px-2 py-0.5 text-xs font-bold text-white">جديد</span> : null}
                    </div>

                    <h2 className="mt-2 font-black">{n.title}</h2>

                    {n.body ? <p className="muted mt-1 text-sm">{n.body}</p> : null}

                    <time dateTime={new Date(n.createdAt).toISOString()} className="muted mt-2 block text-xs">
                      {new Intl.DateTimeFormat('ar-EG', {
                        dateStyle: 'medium',
                        timeStyle: 'short',
                      }).format(new Date(n.createdAt))}
                    </time>
                  </div>

                  {target ? (
                    <span className="text-sm font-bold text-[var(--brand-primary)]" aria-hidden="true">
                      فتح
                    </span>
                  ) : null}
                </div>
              </article>
            );

            if (!target) return <div key={n.id}>{card}</div>;

            return (
              <Link
                key={n.id}
                to={target}
                className="block"
                aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}
                onClick={() => !n.isRead && mark.mutate([n.id])}
              >
                {card}
              </Link>
            );
          })}
        </section>
      )}
    </div>
  );
}
