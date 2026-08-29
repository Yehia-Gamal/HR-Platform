import { useState } from 'react';
import { Scale } from 'lucide-react';
import type { DisputeCase, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: ReturnType<typeof useDisputeCommands>;
  run: RunFn;
}

export function DisputeSettlementForm({ selected, commands, run }: Props) {
  const [settlement, setSettlement] = useState({ type: 'written_apology', fromId: '', toId: '', text: '', place: '', dueAt: '' });

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">الاعتذار أو التسوية</h3>
      <div className="mt-4 grid gap-3 md:grid-cols-2">
        <select
          className="input"
          aria-label="نوع التسوية"
          value={settlement.type}
          onChange={(event) => setSettlement({ ...settlement, type: event.target.value })}
        >
          <option value="verbal_apology">اعتذار شفهي</option>
          <option value="written_apology">اعتذار مكتوب</option>
          <option value="group_apology">اعتذار في مجموعة العمل</option>
          <option value="undertaking">تعهد</option>
          <option value="mediation">تسوية</option>
          <option value="follow_up">جلسة متابعة</option>
          <option value="other">أخرى</option>
        </select>
        <select
          className="input"
          aria-label="المطلوب منه التنفيذ"
          value={settlement.fromId}
          onChange={(event) => setSettlement({ ...settlement, fromId: event.target.value })}
        >
          <option value="">المطلوب منه التنفيذ</option>
          {selected.parties.map((party) => (
            <option key={party.id} value={party.employeeId}>
              {party.name}
            </option>
          ))}
        </select>
        <select
          className="input"
          aria-label="المستفيد"
          value={settlement.toId}
          onChange={(event) => setSettlement({ ...settlement, toId: event.target.value })}
        >
          <option value="">المستفيد</option>
          {selected.parties.map((party) => (
            <option key={party.id} value={party.employeeId}>
              {party.name}
            </option>
          ))}
        </select>
        <input
          className="input"
          type="datetime-local"
          aria-label="موعد التنفيذ"
          value={settlement.dueAt}
          onChange={(event) => setSettlement({ ...settlement, dueAt: event.target.value })}
        />
        <textarea
          className="input min-h-20"
          placeholder="نص الاعتذار أو تفاصيل التسوية"
          value={settlement.text}
          onChange={(event) => setSettlement({ ...settlement, text: event.target.value })}
        />
        <input
          className="input"
          placeholder="مكان نشر الاعتذار (إن وجد)"
          value={settlement.place}
          onChange={(event) => setSettlement({ ...settlement, place: event.target.value })}
        />
      </div>
      <button
        className="btn-secondary mt-3"
        disabled={!settlement.fromId || commands.recordSettlement.isPending}
        onClick={() =>
          void run(
            () =>
              commands.recordSettlement.mutateAsync({
                p_case_id: selected.id,
                p_type: settlement.type,
                p_from: settlement.fromId,
                p_to: settlement.toId || null,
                p_text: settlement.text || null,
                p_publication_place: settlement.place || null,
                p_due_at: settlement.dueAt ? new Date(settlement.dueAt).toISOString() : null,
              }),
            'تم تسجيل التسوية وإسناد تنفيذها دون إرسال أي نص تلقائيًا.',
          )
        }
      >
        <Scale className="size-4" aria-hidden="true" />
        تسجيل التسوية
      </button>
    </section>
  );
}
