import { useState } from 'react';
import { CheckCircle2 } from 'lucide-react';
import { formatDate } from './DisputeTypes';
import type { DisputeCase, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: ReturnType<typeof import('../useAdvancedOperations').useDisputeCommands>;
  run: RunFn;
}

export function DisputeMinutesForm({ selected, commands, run }: Props) {
  const [minutes, setMinutes] = useState({ sessionId: '', text: '', outcome: '', recommendation: '', internalNotes: '' });
  const [attendance, setAttendance] = useState<Record<string, string>>(
    Object.fromEntries(selected.members.filter((member) => member.active).map((member) => [member.id, 'present'])),
  );

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">محضر الجلسة والتحقق من النصاب</h3>
      <div className="mt-4 grid gap-3">
        <select
          className="input"
          aria-label="اختر جلسة مجدولة"
          value={minutes.sessionId}
          onChange={(event) => {
            setMinutes({ ...minutes, sessionId: event.target.value });
            setAttendance(Object.fromEntries(selected.members.filter((member) => member.active).map((member) => [member.id, 'present'])));
          }}
        >
          <option value="">اختر جلسة مجدولة</option>
          {selected.sessions
            .filter((item) => item.status === 'scheduled')
            .map((item) => (
              <option key={item.id} value={item.id}>
                {item.type} — {formatDate(item.scheduledAt)}
              </option>
            ))}
        </select>
        <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
          {selected.members
            .filter((member) => member.active)
            .map((member) => (
              <label key={member.id} className="rounded-xl bg-[var(--surface-muted)] p-3 text-sm font-bold">
                {member.name}
                <select
                  className="input mt-2"
                  aria-label={`حضور ${member.name}`}
                  value={attendance[member.id] ?? 'present'}
                  onChange={(event) => setAttendance({ ...attendance, [member.id]: event.target.value })}
                >
                  <option value="present">حاضر</option>
                  <option value="remote">عن بُعد</option>
                  <option value="absent">غائب</option>
                  <option value="excused">معتذر</option>
                </select>
              </label>
            ))}
        </div>
        <textarea
          className="input min-h-36"
          placeholder="المحضر: أقوال الأطراف والشهود، نقاط الاتفاق والاختلاف، الأدلة والالتزامات…"
          value={minutes.text}
          onChange={(event) => setMinutes({ ...minutes, text: event.target.value })}
        />
        <input
          className="input"
          placeholder="نتيجة الجلسة"
          value={minutes.outcome}
          onChange={(event) => setMinutes({ ...minutes, outcome: event.target.value })}
        />
        <textarea
          className="input min-h-20"
          placeholder="توصية اللجنة"
          value={minutes.recommendation}
          onChange={(event) => setMinutes({ ...minutes, recommendation: event.target.value })}
        />
        <textarea
          className="input min-h-20"
          placeholder="ملاحظات داخلية لا تظهر للأطراف"
          value={minutes.internalNotes}
          onChange={(event) => setMinutes({ ...minutes, internalNotes: event.target.value })}
        />
        <button
          className="btn-primary"
          disabled={!minutes.sessionId || minutes.text.trim().length < 20 || commands.finalizeSession.isPending}
          onClick={() =>
            void run(
              () =>
                commands.finalizeSession.mutateAsync({
                  p_session_id: minutes.sessionId,
                  p_minutes: minutes.text,
                  p_attendance: selected.members
                    .filter((member) => member.active)
                    .map((member) => ({ committeeMemberId: member.id, status: attendance[member.id] ?? 'absent' })),
                  p_outcome: minutes.outcome || null,
                  p_minutes_data: { recommendation: minutes.recommendation, internalNotes: minutes.internalNotes },
                }),
              'تم حفظ المحضر وتأكيد النصاب ونقل القضية للمداولة.',
            )
          }
        >
          <CheckCircle2 className="size-4" aria-hidden="true" />
          اعتماد المحضر
        </button>
      </div>
    </section>
  );
}
