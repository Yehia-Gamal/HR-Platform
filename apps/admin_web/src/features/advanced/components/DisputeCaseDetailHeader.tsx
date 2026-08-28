import { formatDate, remainingLabel, caseTypes } from './DisputeTypes';
import type { DisputeCase } from './DisputeTypes';
import { StatusBadge } from '../../../ui/StatusBadge';

interface Props {
  selected: DisputeCase;
}

export function DisputeCaseDetailHeader({ selected }: Props) {
  return (
    <section className="card p-5">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge value={selected.status} />
            <StatusBadge value={selected.priority} />
            {selected.overdue ? <StatusBadge value="overdue" /> : null}
          </div>
          <h2 className="mt-3 text-xl font-black">{selected.title}</h2>
          <p className="muted mt-1">
            {selected.caseNumber} · {caseTypes[selected.caseType] ?? selected.caseType}
          </p>
        </div>
        <div className="rounded-2xl bg-[var(--surface-muted)] px-4 py-3 text-start">
          <span className="muted block text-xs">مهلة المراجعة</span>
          <strong className={selected.overdue ? 'text-[var(--danger)]' : ''}>{remainingLabel(selected.reviewDueAt)}</strong>
        </div>
      </div>
      <p className="mt-5 whitespace-pre-wrap leading-8">{selected.description ?? 'لا يوجد وصف.'}</p>
      <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Info label="مقدم المشكلة" value={`${selected.actorName ?? '—'}${selected.actorDepartment ? ` — ${selected.actorDepartment}` : ''}`} />
        <Info label="الطرف الرئيسي" value={selected.respondentName ?? '—'} />
        <Info label="تاريخ الواقعة" value={formatDate(selected.incidentAt)} />
        <Info label="مكان الواقعة" value={selected.incidentLocation ?? '—'} />
        <Info label="الإجراء المطلوب" value={selected.requestedAction ?? '—'} />
        <Info label="التواصل مع المدير" value={selected.directManagerContacted == null ? 'غير محدد' : selected.directManagerContacted ? 'تم' : 'لم يتم'} />
        <Info label="محاولة حل ودي" value={selected.amicableAttempted == null ? 'غير محدد' : selected.amicableAttempted ? 'تمت' : 'لم تتم'} />
        <Info label="المسؤول الحالي" value={selected.assignedName ?? 'لم يُسند'} />
      </div>
    </section>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-[var(--surface-muted)] p-3">
      <span className="muted block text-xs">{label}</span>
      <strong className="mt-1 block text-sm leading-6">{value}</strong>
    </div>
  );
}
