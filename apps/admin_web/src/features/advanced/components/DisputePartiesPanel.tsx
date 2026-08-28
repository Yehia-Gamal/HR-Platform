import type { DisputeCase } from './DisputeTypes';
import { StatusBadge } from '../../../ui/StatusBadge';
import { formatDate } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
}

export function DisputePartiesPanel({ selected }: Props) {
  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">الأطراف وحالة الإشعار</h3>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        {selected.parties.map((party) => (
          <article key={party.id} className="rounded-2xl bg-[var(--surface-muted)] p-4">
            <div className="flex items-center justify-between">
              <strong>{party.name}</strong>
              <StatusBadge value={party.notificationStatus} />
            </div>
            <p className="muted mt-1 text-xs">
              {party.type} · {party.statementSubmittedAt ? `قدّم إفادته ${formatDate(party.statementSubmittedAt)}` : 'لم يقدم إفادة'}
            </p>
          </article>
        ))}
      </div>
    </section>
  );
}
