import { useState } from 'react';
import { UsersRound } from 'lucide-react';
import type { DisputeCase, Person, RunFn } from './DisputeTypes';
import type { DisputeCommands } from '../useAdvancedOperations';

interface Props {
  selected: DisputeCase;
  people: Person[];
  commands: DisputeCommands;
  run: RunFn;
}

export function DisputeCommitteeForm({ selected, people, commands, run }: Props) {
  const [members, setMembers] = useState(
    selected.members.filter((member) => member.active).map((member) => ({ employeeId: member.employeeId, role: member.role })),
  );

  return (
    <section className="card p-5">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-black">تشكيل اللجنة</h3>
          <p className="muted mt-1 text-sm">لا يجوز اختيار أي طرف في المشكلة عضوًا باللجنة.</p>
        </div>
        <button className="btn-secondary" onClick={() => setMembers((current) => [...current, { employeeId: '', role: current.length ? 'member' : 'chair' }])}>
          <UsersRound className="size-4" aria-hidden="true" />
          إضافة عضو
        </button>
      </div>
      <div className="mt-4 space-y-2">
        {members.map((member, index) => (
          <div key={`${index}-${member.employeeId}`} className="grid gap-2 md:grid-cols-[1fr_160px_auto]">
            <select
              className="input"
              aria-label="عضو اللجنة"
              value={member.employeeId}
              onChange={(event) => setMembers((items) => items.map((item, i) => (i === index ? { ...item, employeeId: event.target.value } : item)))}
            >
              <option value="">اختر الموظف</option>
              {people
                .filter((person) => !selected.parties.some((party) => party.employeeId === person.id))
                .map((person) => (
                  <option key={person.id} value={person.id}>
                    {person.name}
                  </option>
                ))}
            </select>
            <select
              className="input"
              aria-label="دور العضو"
              value={member.role}
              onChange={(event) => setMembers((items) => items.map((item, i) => (i === index ? { ...item, role: event.target.value } : item)))}
            >
              <option value="chair">رئيس</option>
              <option value="secretary">مقرر</option>
              <option value="member">عضو</option>
              <option value="observer">مراقب</option>
              <option value="advisor">مستشار</option>
            </select>
            <button className="btn-secondary" onClick={() => setMembers((items) => items.filter((_, i) => i !== index))}>
              حذف
            </button>
          </div>
        ))}
      </div>
      <button
        className="btn-primary mt-4"
        disabled={members.filter((item) => item.employeeId).length < 2 || !members.some((item) => item.role === 'chair') || commands.setCommittee.isPending}
        onClick={() =>
          void run(
            () => commands.setCommittee.mutateAsync({ p_case_id: selected.id, p_members: members.filter((item) => item.employeeId) }),
            'تم حفظ تشكيل اللجنة وبدء المراجعة.',
          )
        }
      >
        <UsersRound className="size-4" aria-hidden="true" />
        حفظ تشكيل اللجنة
      </button>
    </section>
  );
}
