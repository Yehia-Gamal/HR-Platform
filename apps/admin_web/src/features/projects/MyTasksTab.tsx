import type { MyProjectTask } from '@ahla/shared-contracts';
import { CalendarClock, CheckCircle2, FolderOpen, Loader2 } from 'lucide-react';
import { EmptyState } from '../../ui/EmptyState';
import { ErrorState } from '../../ui/ErrorState';
import { safeErrorMessage } from '../../core/errorMapper';
import { useMyProjectTasks, useSetProjectStepStatus } from './useAssociationProjects';
import { STEP_STATUS_LABELS, formatDate } from './projectLedStatus';

/** تبويب «مهامي»: كل ما كُلّفت به عبر المشاريع — المتأخر أولاً. */
export function MyTasksTab({ onOpenProject }: { onOpenProject: (projectId: string) => void }) {
  const { data, isLoading, error, refetch } = useMyProjectTasks();
  const setStatus = useSetProjectStepStatus();

  if (isLoading) {
    return (
      <div className="grid place-items-center p-10">
        <Loader2 className="size-6 animate-spin text-[var(--brand-primary)]" aria-label="جارٍ التحميل" />
      </div>
    );
  }
  if (error) return <ErrorState description={safeErrorMessage(error)} onRetry={() => void refetch()} />;

  const tasks = data ?? [];
  if (tasks.length === 0) {
    return <EmptyState title="لا توجد مهام مكلَّف بها" description="عندما يكلّفك قائد مشروع بخطوة تظهر هنا مع موعدها، وتصلك تذكرة قبل الموعد بيوم." />;
  }

  const groups: { title: string; tone: string; items: MyProjectTask[] }[] = [
    { title: 'متأخرة عن موعدها', tone: 'var(--danger)', items: tasks.filter((t) => t.isOverdue) },
    { title: 'موعدها خلال يومين', tone: 'var(--warning)', items: tasks.filter((t) => !t.isOverdue && t.isDueSoon) },
    { title: 'لاحقاً / بلا موعد', tone: 'var(--text-muted)', items: tasks.filter((t) => !t.isOverdue && !t.isDueSoon) },
  ];

  return (
    <div className="space-y-6">
      {groups
        .filter((g) => g.items.length > 0)
        .map((g) => (
          <section key={g.title} className="space-y-2">
            <h3 className="text-sm font-black" style={{ color: g.tone }}>
              {g.title} ({g.items.length})
            </h3>
            <ul className="space-y-2">
              {g.items.map((t) => (
                <li key={t.stepId} className="card flex flex-col gap-3 p-4 sm:flex-row sm:items-center" style={{ borderInlineStart: `4px solid ${g.tone}` }}>
                  <div className="min-w-0 flex-1">
                    <p className="font-black">{t.title}</p>
                    <button className="mt-0.5 inline-flex items-center gap-1 text-xs font-bold text-[var(--brand-primary)] hover:underline" onClick={() => onOpenProject(t.projectId)}>
                      <FolderOpen className="size-3.5" aria-hidden="true" /> {t.projectName}
                    </button>
                    <p className="mt-1 flex flex-wrap items-center gap-x-3 text-xs text-[var(--text-muted)]">
                      <span>{STEP_STATUS_LABELS[t.status]}</span>
                      {t.dueDate && (
                        <span className={t.isOverdue ? 'font-bold text-[var(--danger)]' : ''}>
                          <CalendarClock className="inline size-3" aria-hidden="true" /> {formatDate(t.dueDate)}
                        </span>
                      )}
                      {t.leaderName && <span>القائد: {t.leaderName}</span>}
                    </p>
                  </div>
                  <div className="flex shrink-0 gap-2">
                    {t.status === 'pending' && (
                      <button
                        className="btn-secondary btn-sm"
                        disabled={setStatus.isPending}
                        onClick={() => setStatus.mutate({ stepId: t.stepId, status: 'in_progress' })}
                      >
                        بدأت التنفيذ
                      </button>
                    )}
                    <button className="btn-primary btn-sm" disabled={setStatus.isPending} onClick={() => setStatus.mutate({ stepId: t.stepId, status: 'done' })}>
                      <CheckCircle2 className="size-4" aria-hidden="true" /> تمت
                    </button>
                  </div>
                </li>
              ))}
            </ul>
          </section>
        ))}
    </div>
  );
}
