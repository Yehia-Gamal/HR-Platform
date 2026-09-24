import type { AssociationProjectActivity } from '@ahla/shared-contracts';
import { EmptyState } from '../../ui/EmptyState';
import { STATUS_LABELS } from './projectLedStatus';

interface Props {
  activities: AssociationProjectActivity[];
  onOpenProject: (projectId: string) => void;
}

/** آخر التحديثات الفعلية التي سجلتها الإدارات على مشاريعها. */
export function ActivityFeed({ activities, onOpenProject }: Props) {
  if (activities.length === 0) {
    return <EmptyState title="لا توجد تحديثات بعد" description="ستظهر هنا التحديثات التي تسجلها الإدارات على مشاريعها المعتمدة." />;
  }

  return (
    <ol className="card divide-y divide-[var(--border)]">
      {activities.map((a) => (
        <li key={a.id}>
          <button type="button" onClick={() => onOpenProject(a.projectId)} className="w-full p-4 text-start transition-colors hover:bg-[var(--surface-hover)]">
            <div className="flex flex-wrap items-baseline justify-between gap-2">
              <span className="font-black">{a.projectName}</span>
              <time className="text-xs text-[var(--text-muted)]" dateTime={a.createdAt}>
                {new Date(a.createdAt).toLocaleString('ar-EG', { dateStyle: 'medium', timeStyle: 'short' })}
              </time>
            </div>
            <p className="mt-1 line-clamp-2 text-sm leading-7 text-[var(--text-secondary)]">{a.note}</p>
            <p className="mt-1 text-xs text-[var(--text-muted)]">
              {a.authorName}
              {a.statusChange ? ` • الحالة ← ${STATUS_LABELS[a.statusChange as keyof typeof STATUS_LABELS] ?? a.statusChange}` : ''}
            </p>
          </button>
        </li>
      ))}
    </ol>
  );
}
