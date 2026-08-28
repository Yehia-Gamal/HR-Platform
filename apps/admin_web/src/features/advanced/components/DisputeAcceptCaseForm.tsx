import { useState } from 'react';
import { CheckCircle2 } from 'lucide-react';
import type { DisputeCase, Person, RunFn } from './DisputeTypes';
import type { Commands } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  people: Person[];
  commands: Commands;
  run: RunFn;
}

export function DisputeAcceptCaseForm({ selected, people, commands, run }: Props) {
  const [assignedTo, setAssignedTo] = useState(selected.assignedTo ?? '');
  const [quorum, setQuorum] = useState(selected.quorum);

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">قبول المشكلة للدراسة</h3>
      <p className="muted mt-1 text-sm">بعد القبول لا يستطيع مقدم المشكلة إلغاءها.</p>
      <div className="mt-4 grid gap-3 md:grid-cols-[1fr_140px_auto]">
        <select className="input" aria-label="المحقق أو المسؤول" value={assignedTo} onChange={(event) => setAssignedTo(event.target.value)}>
          <option value="">المحقق أو المسؤول</option>
          {people.map((person) => (
            <option key={person.id} value={person.id}>
              {person.name}
              {person.department ? ` — ${person.department}` : ''}
            </option>
          ))}
        </select>
        <input className="input" type="number" min="1" aria-label="نصاب اللجنة" value={quorum} onChange={(event) => setQuorum(Number(event.target.value))} />
        <button
          className="btn-primary"
          disabled={!assignedTo || commands.acceptCase.isPending}
          onClick={() =>
            void run(
              () => commands.acceptCase.mutateAsync({ p_case_id: selected.id, p_assigned_to: assignedTo, p_quorum: quorum, p_due_at: null }),
              'تم قبول المشكلة وبدأ المسار الرسمي.',
            )
          }
        >
          <CheckCircle2 className="size-4" aria-hidden="true" />
          قبول المشكلة
        </button>
      </div>
    </section>
  );
}
