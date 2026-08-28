import { useState } from 'react';
import { FileText } from 'lucide-react';
import { formatDate } from './DisputeTypes';
import type { DisputeCase, Commands, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: Commands;
  run: RunFn;
}

export function DisputeNotesSection({ selected, commands, run }: Props) {
  const [note, setNote] = useState({ type: 'committee_note', text: '', visibility: 'committee_only' });

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">ملاحظات اللجنة والتوصيات</h3>
      <div className="mt-4 grid gap-3 md:grid-cols-[180px_180px_1fr_auto]">
        <select className="input" aria-label="نوع الملاحظة" value={note.type} onChange={(event) => setNote({ ...note, type: event.target.value })}>
          <option value="committee_note">ملاحظة داخلية</option>
          <option value="recommendation">توصية</option>
          <option value="executive_note">ملاحظة تنفيذية</option>
        </select>
        <select className="input" aria-label="ظهور الملاحظة" value={note.visibility} onChange={(event) => setNote({ ...note, visibility: event.target.value })}>
          <option value="committee_only">اللجنة فقط</option>
          <option value="parties">تظهر للأطراف</option>
          <option value="complainant">لمقدم المشكلة</option>
          <option value="respondent">للطرف الآخر</option>
        </select>
        <input
          className="input"
          value={note.text}
          onChange={(event) => setNote({ ...note, text: event.target.value })}
          placeholder="اكتب الملاحظة أو التوصية…"
        />
        <button
          className="btn-primary"
          disabled={note.text.trim().length < 10 || commands.addStatement.isPending}
          onClick={() =>
            void run(async () => {
              await commands.addStatement.mutateAsync({
                p_case_id: selected.id,
                p_statement_type: note.type,
                p_statement_text: note.text,
                p_visibility: note.visibility,
              });
              setNote({ ...note, text: '' });
            }, 'تم حفظ الملاحظة دون المساس بملاحظات الأعضاء الآخرين.')
          }
        >
          <FileText className="size-4" aria-hidden="true" />
          حفظ
        </button>
      </div>
      <div className="mt-4 space-y-2">
        {selected.statements.map((item) => (
          <article key={item.id} className="rounded-2xl bg-[var(--surface-muted)] p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <strong>
                {item.submittedByName} · {item.type}
              </strong>
              <span className="muted text-xs">{formatDate(item.submittedAt)}</span>
            </div>
            <p className="mt-2 whitespace-pre-wrap text-sm leading-7">{item.text}</p>
            <span className="muted mt-2 block text-xs">الظهور: {item.visibility}</span>
          </article>
        ))}
      </div>
    </section>
  );
}
