import { AlertCircle, ArrowLeft, ClipboardList, Clock3, FileCheck2, Gavel, Inbox, Landmark, Megaphone, PenLine } from 'lucide-react';
import { Link } from 'react-router';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { MetricCard } from '../../ui/MetricCard';
import { PageHeader } from '../../ui/PageHeader';
import { MetricSkeletonRow, ListSkeleton } from '../../ui/Skeletons';
import { StatusBadge } from '../../ui/StatusBadge';
import { relativeTime } from '../../core/formatTime';
import { useActionCenter } from './useActionCenter';
import type { ActionCenterItem } from '@ahla/shared-contracts';

const KIND_META: Record<ActionCenterItem['kind'], { label: string; icon: typeof Inbox }> = {
  request: { label: 'طلب موظف', icon: ClipboardList },
  kpi: { label: 'تقييم أداء', icon: PenLine },
  decision: { label: 'قرار رسمي', icon: Megaphone },
  report: { label: 'تقرير', icon: FileCheck2 },
  case: { label: 'قضية خلافات', icon: Gavel },
  task: { label: 'مهمة', icon: Clock3 },
  policy: { label: 'سياسة', icon: Landmark },
};

export function ActionCenterPage() {
  const query = useActionCenter();
  const items = query.data ?? [];
  const isInitialLoading = query.isLoading && items.length === 0;

  return (
    <div className="space-y-6">
      <PageHeader
        eyebrow="مركز الإجراءات"
        title="مركز الإجراءات الموحد"
        description="كل عنصر ينتظر منك قرارًا أو مراجعة أو متابعة في قائمة واحدة — الأحدث أولاً."
      />

      {isInitialLoading ? (
        <MetricSkeletonRow count={3} />
      ) : (
        <section className="grid gap-4 sm:grid-cols-3">
          <MetricCard label="إجمالي العناصر" value={items.length} icon={Inbox} />
          <MetricCard label="عاجل" value={items.filter((x) => x.priority === 'urgent').length} icon={AlertCircle} />
          <MetricCard label="مرتفع" value={items.filter((x) => x.priority === 'high').length} icon={Clock3} />
        </section>
      )}

      {query.isError ? (
        <ErrorState title="تعذر تحميل مركز الإجراءات" description={safeErrorMessage(query.error)} onRetry={() => void query.refetch()} />
      ) : isInitialLoading ? (
        <ListSkeleton rows={3} label="جارٍ تحميل الإجراءات" />
      ) : items.length === 0 ? (
        <EmptyState title="لا توجد إجراءات معلقة" description="لا توجد عناصر تحتاج تدخلك حاليًا." />
      ) : (
        <section className="space-y-3">
          {items.map((item) => {
            const meta = KIND_META[item.kind] ?? KIND_META.task;
            const Icon = meta.icon;
            return (
              <article
                key={item.id}
                className="card flex flex-col gap-4 p-5 transition-colors hover:border-[var(--brand-primary)]/50 md:flex-row md:items-center"
              >
                <span aria-hidden="true" className="grid size-11 shrink-0 place-items-center rounded-xl bg-[var(--surface-muted)] text-[var(--brand-primary)]">
                  <Icon className="size-5" />
                </span>

                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="muted text-xs font-bold">{meta.label}</span>
                    <StatusBadge value={item.priority} />
                    <StatusBadge value={item.status} />
                  </div>

                  <h2 className="mt-2 font-black">{item.title}</h2>

                  {item.subtitle ? <p className="muted mt-1 text-sm">{item.subtitle}</p> : null}

                  <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1">
                    {item.dueAt ? (
                      <p className="text-xs font-bold text-[var(--warning)]">
                        المهلة:{' '}
                        {new Intl.DateTimeFormat('ar-EG', {
                          dateStyle: 'medium',
                          timeStyle: 'short',
                        }).format(new Date(item.dueAt))}
                      </p>
                    ) : null}
                    {item.sourceUpdatedAt ? (
                      <p className="muted text-xs" title={new Date(item.sourceUpdatedAt).toLocaleString('ar-EG')}>
                        آخر تحديث {relativeTime(item.sourceUpdatedAt)}
                      </p>
                    ) : null}
                  </div>
                </div>

                <Link className="btn-primary shrink-0" to={item.actionUrl}>
                  فتح الإجراء
                  <ArrowLeft className="size-4" aria-hidden="true" />
                </Link>
              </article>
            );
          })}
        </section>
      )}
    </div>
  );
}
