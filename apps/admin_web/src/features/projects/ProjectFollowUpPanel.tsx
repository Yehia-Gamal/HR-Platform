import type { AssociationProjectListItem } from '@ahla/shared-contracts';
import { ArrowLeft, ClipboardList } from 'lucide-react';
import { FOLLOW_UP, compareProjectFollowUp, projectFollowUpReasons, type FollowUpFilter, type FollowUpReason } from './projectFollowUp';

export function ProjectFollowUpPanel({
  projects,
  filter,
  onFilter,
  onOpen,
}: {
  projects: AssociationProjectListItem[];
  filter: FollowUpFilter;
  onFilter: (filter: FollowUpFilter) => void;
  onOpen: (projectId: string) => void;
}) {
  const queue = [...projects]
    .sort(compareProjectFollowUp)
    .flatMap((project) => {
      const reasons = projectFollowUpReasons(project);
      const [firstReason] = reasons;
      return firstReason ? [{ project, reasons, firstReason }] : [];
    });
  const reasons = Object.keys(FOLLOW_UP) as FollowUpReason[];
  const visible = queue.filter((item) => filter === 'all' || item.reasons.includes(filter));
  if (!queue.length && filter === 'all') return null;

  return (
    <section className="card overflow-hidden" aria-labelledby="project-follow-up">
      <header className="flex items-center gap-3 border-b border-[var(--border)] bg-[var(--surface-subtle)] p-4">
        <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-[var(--brand-primary-soft)] text-[var(--brand-primary)]">
          <ClipboardList className="size-5" aria-hidden="true" />
        </span>
        <div className="min-w-0">
          <h2 id="project-follow-up" className="font-black">أولويات المتابعة</h2>
          <p className="text-xs text-[var(--text-secondary)]">{queue.length} من {projects.length} مشروع معتمد يحتاج مراجعة</p>
        </div>
      </header>
      <div className="flex flex-wrap gap-2 px-4 pt-4" role="group" aria-label="تصفية المشاريع حسب سبب المتابعة">
        {filter !== 'all' && (
          <button type="button" className="filter-chip" onClick={() => onFilter('all')}>إلغاء تصفية المتابعة</button>
        )}
        {reasons.map((reason) => {
          const count = queue.filter((item) => item.reasons.includes(reason)).length;
          if (count === 0 && reason !== filter) return null;
          return (
            <button
              key={reason}
              type="button"
              className={`filter-chip${filter === reason ? ' is-active' : ''}`}
              aria-pressed={filter === reason}
              onClick={() => onFilter(filter === reason ? 'all' : reason)}
            >
              {FOLLOW_UP[reason].filter} <span className="tabular font-black">{count}</span>
            </button>
          );
        })}
      </div>
      {visible.length > 0 && (
        <ul className="divide-y divide-[var(--border)] px-4 py-2">
          {visible.slice(0, 3).map(({ project, firstReason }) => {
            const reason = filter === 'all' ? firstReason : filter;
            return (
              <li key={project.id}>
                <button
                  type="button"
                  className="flex w-full items-center gap-3 rounded-lg py-3 text-start hover:bg-[var(--surface-subtle)]"
                  onClick={() => onOpen(project.id)}
                >
                  <span className="min-w-0 flex-1">
                    <span className="block font-bold">{project.name}</span>
                    <span className="block text-sm text-[var(--text-secondary)]">
                      {FOLLOW_UP[reason].label} · {project.leaderName ?? project.ownerName}
                    </span>
                  </span>
                  <ArrowLeft className="size-4 shrink-0 text-[var(--brand-primary)]" aria-hidden="true" />
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
