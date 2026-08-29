import { useState } from 'react';
import { UserCheck } from 'lucide-react';
import { formatDate } from './DisputeTypes';
import type { DisputeCase, RunFn } from './DisputeTypes';
import { StatusBadge } from '../../../ui/StatusBadge';

interface Props {
  selected: DisputeCase;
  commands: ReturnType<typeof useDisputeCommands>;
  run: RunFn;
}

export function DisputeActionTracker({ selected, commands, run }: Props) {
  const [proofs, setProofs] = useState<Record<string, string>>({});

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">متابعة تنفيذ القرارات</h3>
      <div className="mt-4 space-y-3">
        {selected.actions.map((action) => (
          <article key={action.id} className="rounded-2xl border border-[var(--border)] p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <strong>{action.type}</strong>
                <p className="muted mt-1 text-sm">
                  المسؤول: {action.assignedName ?? '—'} · الموعد: {formatDate(action.dueAt)}
                </p>
              </div>
              <StatusBadge value={action.status ?? 'pending'} />
            </div>
            {action.note ? <p className="mt-3 text-sm leading-7">{action.note}</p> : null}
            {action.status !== 'completed' ? (
              <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                <input
                  className="input flex-1"
                  placeholder="إثبات التنفيذ"
                  value={proofs[action.id] ?? ''}
                  onChange={(event) => setProofs({ ...proofs, [action.id]: event.target.value })}
                />
                <button
                  className="btn-primary"
                  disabled={(proofs[action.id] ?? '').trim().length < 5 || commands.completeAction.isPending}
                  onClick={() =>
                    void run(
                      () => commands.completeAction.mutateAsync({ p_action_id: action.id, p_proof: proofs[action.id] }),
                      'تم تسجيل إثبات التنفيذ. يمكن إغلاق القضية بعد اكتمال جميع الإجراءات.',
                    )
                  }
                >
                  <UserCheck className="size-4" aria-hidden="true" />
                  تأكيد التنفيذ
                </button>
              </div>
            ) : (
              <p className="mt-3 rounded-xl bg-[var(--success-soft)] p-3 text-sm text-[var(--success)]">إثبات التنفيذ: {action.proof}</p>
            )}
          </article>
        ))}
      </div>
    </section>
  );
}
