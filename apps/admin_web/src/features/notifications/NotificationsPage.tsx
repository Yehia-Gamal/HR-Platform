import { CheckCheck, Trash2 } from 'lucide-react';
import { useState } from 'react';
import { Link, useLocation } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ListSkeleton } from '../../ui/Skeletons';
import { ErrorBanner, ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useToast } from '../../ui/Toast';
import { PageHeader } from '../../ui/PageHeader';
import { StatusBadge } from '../../ui/StatusBadge';
import { relativeTime } from '../../core/formatTime';
import { notificationTargetPath, notificationWorkspaceFromPath } from './notificationTarget';
import { notificationCategoryIcon, notificationCategoryLabel } from './notificationMeta';
import { useDeleteNotifications, useMarkNotificationsRead, useNotifications } from './useNotifications';

type Filter = 'all' | 'unread';

export function NotificationsPage() {
  const { toast } = useToast();
  const location = useLocation();
  const workspace = notificationWorkspaceFromPath(location.pathname);
  const q = useNotifications();
  const mark = useMarkNotificationsRead();
  const del = useDeleteNotifications();
  const [filter, setFilter] = useState<Filter>('all');
  const items = q.data ?? [];
  const unread = items.filter((x) => !x.isRead);
  const visible = filter === 'unread' ? unread : items;

  const handleDelete = (id: string) => {
    del.mutate([id], {
      onError: () => toast({ message: 'تعذر حذف الإشعار', tone: 'error' }),
    });
  };

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
      {del.isError ? <ErrorBanner message={safeErrorMessage(del.error)} /> : null}

      {q.isError ? (
        <ErrorState title="تعذر تحميل الإشعارات" description={safeErrorMessage(q.error)} onRetry={() => void q.refetch()} />
      ) : q.isLoading ? (
        <section aria-label="جارٍ تحميل الإشعارات">
          <ListSkeleton rows={3} label="جارٍ تحميل الإشعارات…" />
        </section>
      ) : (
        <>
          <div className="flex gap-2" role="tablist" aria-label="فلترة الإشعارات">
            <button
              role="tab"
              aria-selected={filter === 'all'}
              onClick={() => setFilter('all')}
              className={`rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${filter === 'all' ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-muted)] text-[var(--text-muted)] hover:text-[var(--text-strong)]'}`}
            >
              الكل ({items.length})
            </button>
            <button
              role="tab"
              aria-selected={filter === 'unread'}
              onClick={() => setFilter('unread')}
              className={`rounded-full px-4 py-1.5 text-sm font-bold transition-colors ${filter === 'unread' ? 'bg-[var(--brand-primary)] text-white' : 'bg-[var(--surface-muted)] text-[var(--text-muted)] hover:text-[var(--text-strong)]'}`}
            >
              غير المقروء ({unread.length})
            </button>
          </div>

          {!visible.length ? (
            <EmptyState
              title={filter === 'unread' ? 'لا توجد إشعارات غير مقروءة' : 'لا توجد إشعارات'}
              description={filter === 'unread' ? 'كل الإشعارات مقروءة — رائع.' : 'ستظهر هنا التنبيهات الموجهة إلى حسابك.'}
            />
          ) : (
            <section className="space-y-3" aria-label={filter === 'unread' ? 'الإشعارات غير المقروءة' : 'كل الإشعارات'}>
              {visible.map((n) => {
                const target = notificationTargetPath(n, workspace);
                const Icon = notificationCategoryIcon(n.category);
                const card = (
                  <article
                    aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}
                    className={`card p-5 ${n.isRead ? 'opacity-75' : 'border-[var(--brand-primary)]/40'}`}
                  >
                    <div className="flex flex-col gap-4 md:flex-row md:items-center">
                      <span
                        aria-hidden="true"
                        className="grid size-11 shrink-0 place-items-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]"
                      >
                        <Icon className="size-5" />
                      </span>

                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <StatusBadge value={n.priority} />
                          <span className="muted text-xs">{notificationCategoryLabel(n.category)}</span>
                          {!n.isRead ? <span className="rounded-full bg-[var(--brand-primary)] px-2 py-0.5 text-xs font-bold text-white">جديد</span> : null}
                        </div>

                        <h2 className="mt-2 font-black">{n.title}</h2>

                        {n.body ? <p className="muted mt-1 text-sm">{n.body}</p> : null}

                        <time
                          dateTime={new Date(n.createdAt).toISOString()}
                          title={new Intl.DateTimeFormat('ar-EG', { dateStyle: 'full', timeStyle: 'short' }).format(new Date(n.createdAt))}
                          className="muted mt-2 block text-xs"
                        >
                          {relativeTime(n.createdAt)}
                        </time>
                      </div>

                      {target ? (
                        <span className="text-sm font-bold text-[var(--brand-primary)]" aria-hidden="true">
                          فتح
                        </span>
                      ) : null}

                      <button
                        type="button"
                        aria-label="حذف الإشعار"
                        disabled={del.isPending}
                        onClick={(event) => {
                          event.preventDefault();
                          event.stopPropagation();
                          handleDelete(n.id);
                        }}
                        className="icon-button shrink-0 text-[var(--danger)] hover:bg-[var(--danger)]/10"
                      >
                        <Trash2 className="size-4" aria-hidden="true" />
                      </button>
                    </div>
                  </article>
                );

                // بلا وجهة: بطاقة قابلة للنقر تعلم مقروء فقط عند اللمس.
                if (!target) {
                  return (
                    <div
                      key={n.id}
                      role="button"
                      tabIndex={0}
                      className="block w-full cursor-pointer"
                      aria-label={n.isRead ? undefined : 'إشعار غير مقروء'}
                      onClick={() => !n.isRead && mark.mutate([n.id])}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter' || event.key === ' ') {
                          event.preventDefault();
                          if (!n.isRead) mark.mutate([n.id]);
                        }
                      }}
                    >
                      {card}
                    </div>
                  );
                }

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
        </>
      )}
    </div>
  );
}
