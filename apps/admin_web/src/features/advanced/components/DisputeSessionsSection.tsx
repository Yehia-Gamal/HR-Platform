import { useState } from 'react';
import { CalendarPlus } from 'lucide-react';
import { formatDate } from './DisputeTypes';
import type { DisputeCase, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: ReturnType<typeof import('../useAdvancedOperations').useDisputeCommands>;
  run: RunFn;
}

export function DisputeSessionsSection({ selected, commands, run }: Props) {
  const [session, setSession] = useState({ type: 'hearing', at: '', endsAt: '', location: '', modality: 'in_person' });

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">الجلسات</h3>
      <div className="mt-4 grid gap-3 lg:grid-cols-3">
        <select className="input" aria-label="نوع الجلسة" value={session.type} onChange={(event) => setSession({ ...session, type: event.target.value })}>
          <option value="hearing">استماع</option>
          <option value="investigation">تحقيق</option>
          <option value="mediation">وساطة</option>
          <option value="follow_up">متابعة</option>
          <option value="decision">قرار</option>
        </select>
        <input
          className="input"
          type="datetime-local"
          aria-label="بداية الجلسة"
          value={session.at}
          onChange={(event) => setSession({ ...session, at: event.target.value })}
        />
        <input
          className="input"
          type="datetime-local"
          aria-label="نهاية الجلسة"
          value={session.endsAt}
          onChange={(event) => setSession({ ...session, endsAt: event.target.value })}
        />
        <select
          className="input"
          aria-label="نمط الجلسة"
          value={session.modality}
          onChange={(event) => setSession({ ...session, modality: event.target.value })}
        >
          <option value="in_person">حضورية</option>
          <option value="remote">عن بُعد</option>
          <option value="hybrid">هجين</option>
        </select>
        <input
          className="input"
          placeholder="المكان أو رابط الاجتماع"
          value={session.location}
          onChange={(event) => setSession({ ...session, location: event.target.value })}
        />
        <button
          className="btn-primary"
          disabled={!session.at || commands.scheduleSession.isPending}
          onClick={() =>
            void run(
              () =>
                commands.scheduleSession.mutateAsync({
                  p_case_id: selected.id,
                  p_type: session.type,
                  p_scheduled_at: new Date(session.at).toISOString(),
                  p_ends_at: session.endsAt ? new Date(session.endsAt).toISOString() : null,
                  p_location: session.location || null,
                  p_modality: session.modality,
                  p_participants: [
                    ...selected.parties.map((party) => ({ employeeId: party.employeeId, role: party.type })),
                    ...selected.members.map((member) => ({ employeeId: member.employeeId, role: 'committee' })),
                  ],
                }),
              'تم تحديد الجلسة وإشعار المشاركين دون كشف تفاصيل سرية.',
            )
          }
        >
          <CalendarPlus className="size-4" aria-hidden="true" />
          تحديد جلسة
        </button>
      </div>
      <div className="mt-5 space-y-2">
        {selected.sessions.map((item) => (
          <div key={item.id} className="w-full rounded-xl border border-[var(--border)] p-3 text-start">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <span>
                {item.type} · {formatDate(item.scheduledAt)} · {item.location ?? 'دون مكان'}
              </span>
              <span className="muted text-xs">{item.status}</span>
            </div>
            {item.minutes ? <p className="muted mt-2 line-clamp-2 text-xs">{item.minutes}</p> : null}
          </div>
        ))}
      </div>
    </section>
  );
}
