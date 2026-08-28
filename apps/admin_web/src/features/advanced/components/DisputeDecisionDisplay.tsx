import { formatDate } from './DisputeTypes';
import type { DisputeCase } from './DisputeTypes';
import { StatusBadge } from '../../../ui/StatusBadge';

interface Props {
  selected: DisputeCase;
}

export function DisputeDecisionDisplay({ selected }: Props) {
  const d = selected.decision;
  if (!d) return null;
  return (
    <section className="card p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-lg font-black">القرار {d.number}</h3>
          <p className="muted mt-1 text-sm">صدر {formatDate(d.issuedAt)}</p>
        </div>
        <StatusBadge value={d.status} />
      </div>
      <p className="mt-4 whitespace-pre-wrap leading-8">{d.text}</p>
      <details className="mt-4 rounded-2xl bg-[var(--surface-muted)] p-4">
        <summary className="cursor-pointer font-black">الحيثيات الداخلية</summary>
        <p className="mt-3 whitespace-pre-wrap leading-7">{d.rationale}</p>
      </details>
    </section>
  );
}
