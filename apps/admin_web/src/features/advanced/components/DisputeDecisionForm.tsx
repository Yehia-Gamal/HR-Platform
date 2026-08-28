import { useState } from 'react';
import { Gavel } from 'lucide-react';
import type { DisputeCase, Person, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  people: Person[];
  commands: ReturnType<typeof import('../useAdvancedOperations').useDisputeCommands>;
  run: RunFn;
}

export function DisputeDecisionForm({ selected, people, commands, run }: Props) {
  const [decision, setDecision] = useState({ sessionId: '', text: '', rationale: '', outcome: 'mediation', ownerId: '', dueAt: '' });

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">إصدار قرار اللجنة</h3>
      <div className="mt-4 grid gap-3">
        <select
          className="input"
          aria-label="اختر جلسة مكتملة"
          value={decision.sessionId}
          onChange={(event) => setDecision({ ...decision, sessionId: event.target.value })}
        >
          <option value="">اختر جلسة مكتملة</option>
          {selected.sessions
            .filter((item) => item.status === 'held')
            .map((item) => (
              <option value={item.id} key={item.id}>
                {item.type} — {item.heldAt ? new Intl.DateTimeFormat('ar-EG', { dateStyle: 'medium' }).format(new Date(item.heldAt)) : '—'}
              </option>
            ))}
        </select>
        <textarea
          className="input min-h-24"
          placeholder="نص القرار المسموح بإبلاغه للأطراف"
          value={decision.text}
          onChange={(event) => setDecision({ ...decision, text: event.target.value })}
        />
        <textarea
          className="input min-h-24"
          placeholder="الحيثيات والمبررات الداخلية"
          value={decision.rationale}
          onChange={(event) => setDecision({ ...decision, rationale: event.target.value })}
        />
        <div className="grid gap-3 md:grid-cols-3">
          <select
            className="input"
            aria-label="نتيجة القرار"
            value={decision.outcome}
            onChange={(event) => setDecision({ ...decision, outcome: event.target.value })}
          >
            <option value="mediation">صلح أو تسوية</option>
            <option value="warning">تنبيه إداري</option>
            <option value="corrective_action">إجراء تصحيحي</option>
            <option value="disciplinary_recommendation">توصية إدارية</option>
            <option value="dismissed">حفظ لعدم الثبوت</option>
            <option value="escalation">تصعيد</option>
            <option value="other">قرار آخر</option>
          </select>
          <select
            className="input"
            aria-label="مسؤول التنفيذ"
            value={decision.ownerId}
            onChange={(event) => setDecision({ ...decision, ownerId: event.target.value })}
          >
            <option value="">لا يحتاج مسؤول تنفيذ</option>
            {people.map((person) => (
              <option value={person.id} key={person.id}>
                {person.name}
              </option>
            ))}
          </select>
          <input
            className="input"
            type="datetime-local"
            aria-label="موعد التنفيذ"
            value={decision.dueAt}
            onChange={(event) => setDecision({ ...decision, dueAt: event.target.value })}
          />
        </div>
        <button
          className="btn-primary"
          disabled={!decision.sessionId || decision.text.trim().length < 20 || decision.rationale.trim().length < 20 || commands.issueDecision.isPending}
          onClick={() =>
            void run(
              () =>
                commands.issueDecision.mutateAsync({
                  p_case_id: selected.id,
                  p_session_id: decision.sessionId,
                  p_text: decision.text,
                  p_rationale: decision.rationale,
                  p_outcome: decision.outcome,
                  p_owner_id: decision.ownerId || null,
                  p_due_at: decision.dueAt ? new Date(decision.dueAt).toISOString() : null,
                }),
              'صدر القرار وأُبلغ الأطراف ومسؤول التنفيذ.',
            )
          }
        >
          <Gavel className="size-4" aria-hidden="true" />
          إصدار القرار
        </button>
      </div>
    </section>
  );
}
