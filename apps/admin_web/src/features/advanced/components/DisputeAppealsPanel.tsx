import { useState } from 'react';
import { RotateCcw } from 'lucide-react';
import type { DisputeCase, RunFn } from './DisputeTypes';
import type { DisputeCommands } from '../useAdvancedOperations';
import { StatusBadge } from '../../../ui/StatusBadge';

interface Props {
  selected: DisputeCase;
  commands: DisputeCommands;
  run: RunFn;
}

export function DisputeAppealsPanel({ selected, commands, run }: Props) {
  const [appealResolution, setAppealResolution] = useState<Record<string, string>>({});

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">الاعتراضات</h3>
      <div className="mt-4 space-y-3">
        {selected.appeals.map((appeal) => (
          <article key={appeal.id} className="rounded-2xl border border-[var(--border)] p-4">
            <div className="flex items-center justify-between gap-3">
              <strong>{appeal.appellantName}</strong>
              <StatusBadge value={appeal.status} />
            </div>
            <p className="mt-3 leading-7">{appeal.reason}</p>
            {['submitted', 'under_review'].includes(appeal.status) ? (
              <div className="mt-3">
                <textarea
                  className="input min-h-20"
                  placeholder="سبب القرار في الاعتراض"
                  value={appealResolution[appeal.id] ?? ''}
                  onChange={(event) => setAppealResolution({ ...appealResolution, [appeal.id]: event.target.value })}
                />
                <div className="mt-2 flex gap-2">
                  <button
                    className="btn-primary"
                    disabled={(appealResolution[appeal.id] ?? '').trim().length < 10}
                    onClick={() =>
                      void run(
                        () => commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'accepted', p_resolution: appealResolution[appeal.id] }),
                        'تم قبول الاعتراض وإعادة فتح المشكلة.',
                      )
                    }
                  >
                    <RotateCcw className="size-4" aria-hidden="true" />
                    قبول وإعادة فتح
                  </button>
                  <button
                    className="btn-secondary"
                    disabled={(appealResolution[appeal.id] ?? '').trim().length < 10}
                    onClick={() =>
                      void run(
                        () => commands.decideAppeal.mutateAsync({ p_appeal_id: appeal.id, p_decision: 'rejected', p_resolution: appealResolution[appeal.id] }),
                        'تم رفض الاعتراض مع تسجيل السبب.',
                      )
                    }
                  >
                    رفض الاعتراض
                  </button>
                </div>
              </div>
            ) : appeal.resolution ? (
              <p className="muted mt-3">النتيجة: {appeal.resolution}</p>
            ) : null}
          </article>
        ))}
      </div>
    </section>
  );
}
