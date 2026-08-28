import { StatusBadge } from '../../../ui/StatusBadge';
import type { DisputeCase } from './DisputeTypes';

interface Props {
  item: DisputeCase;
  isSelected: boolean;
  onSelect: () => void;
}

export function DisputeCaseListItem({ item, isSelected, onSelect }: Props) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`w-full rounded-2xl border p-4 text-start transition ${isSelected ? 'border-[var(--brand-primary)] bg-[var(--surface-muted)]' : 'border-[var(--border)] hover:border-[var(--border-strong)]'}`}
    >
      <div className="flex items-start justify-between gap-2">
        <strong className="line-clamp-2">{item.title}</strong>
        <StatusBadge value={item.status} />
      </div>
      <p className="muted mt-2 text-xs">
        {item.caseNumber ?? 'بدون رقم'} · {item.actorName ?? 'مقدم غير محدد'}
      </p>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <StatusBadge value={item.priority} />
        {item.overdue ? <StatusBadge value="overdue" /> : null}
        <span className="muted text-xs">{remainingLabel(item.reviewDueAt)}</span>
      </div>
    </button>
  );
}

function remainingLabel(value?: string | null) {
  if (!value) return 'لا توجد مهلة';
  const hours = Math.ceil((new Date(value).getTime() - Date.now()) / 3_600_000);
  if (hours < 0) return `متأخرة ${Math.abs(hours)} س`;
  if (hours === 0) return 'أقل من ساعة';
  return `متبقي ${hours} س`;
}
