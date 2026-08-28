import { useState } from 'react';
import { Send } from 'lucide-react';
import { actionsFor, transitionLabels } from './DisputeTypes';
import type { DisputeCase, RunFn } from './DisputeTypes';

interface Props {
  selected: DisputeCase;
  commands: ReturnType<typeof import('../useAdvancedOperations').useDisputeCommands>;
  run: RunFn;
}

export function DisputeTransitionForm({ selected, commands, run }: Props) {
  const [transition, setTransition] = useState({ action: '', reason: '', targetId: '', summary: '', priority: selected.priority });

  const submitTransition = async () => {
    if (!transition.action) return;
    const metadata: Record<string, unknown> = {};
    if (transition.targetId) metadata.employeeId = transition.targetId;
    if (transition.summary.trim()) metadata.summary = transition.summary.trim();
    if (transition.action === 'change_priority') metadata.priority = transition.priority;
    await run(
      () =>
        commands.transitionCase.mutateAsync({
          p_case_id: selected.id,
          p_action: transition.action,
          p_reason: transition.reason.trim() || null,
          p_metadata: metadata,
        }),
      'تم تنفيذ الإجراء وتسجيله في سجل التدقيق.',
    );
  };

  const availableActions = actionsFor(selected);

  return (
    <section className="card p-5">
      <h3 className="text-lg font-black">إدارة مسار القضية</h3>
      <div className="mt-4 grid gap-3 lg:grid-cols-2">
        <select
          className="input"
          aria-label="إجراء المسار"
          value={transition.action}
          onChange={(event) => setTransition({ ...transition, action: event.target.value })}
        >
          <option value="">اختر الإجراء</option>
          {availableActions.map((action) => (
            <option key={action} value={action}>
              {transitionLabels[action]}
            </option>
          ))}
        </select>
        {['request_respondent_statement', 'request_witness_statement'].includes(transition.action) ? (
          <select
            className="input"
            aria-label="الشخص المطلوبة إفادته"
            value={transition.targetId}
            onChange={(event) => setTransition({ ...transition, targetId: event.target.value })}
          >
            <option value="">اختر الشخص</option>
            {selected.parties
              .filter((party) => (transition.action === 'request_witness_statement' ? party.type === 'witness' : party.type === 'respondent'))
              .map((party) => (
                <option key={party.id} value={party.employeeId}>
                  {party.name}
                </option>
              ))}
          </select>
        ) : null}
        {transition.action === 'change_priority' ? (
          <select
            className="input"
            aria-label="الأولوية"
            value={transition.priority}
            onChange={(event) => setTransition({ ...transition, priority: event.target.value })}
          >
            <option value="normal">عادية</option>
            <option value="urgent">عاجلة</option>
            <option value="critical">حرجة</option>
          </select>
        ) : null}
        {['request_respondent_statement', 'request_witness_statement'].includes(transition.action) ? (
          <input
            className="input"
            placeholder="ملخص مسموح بمشاركته في الإشعار"
            value={transition.summary}
            onChange={(event) => setTransition({ ...transition, summary: event.target.value })}
          />
        ) : null}
        <textarea
          className="input min-h-20 lg:col-span-2"
          placeholder="سبب الإجراء (إلزامي للرفض والتصعيد والتمديد والإغلاق وإعادة الفتح وتغيير الأولوية)"
          value={transition.reason}
          onChange={(event) => setTransition({ ...transition, reason: event.target.value })}
        />
      </div>
      <button
        className="btn-primary mt-3"
        disabled={
          !transition.action ||
          commands.transitionCase.isPending ||
          (['request_respondent_statement', 'request_witness_statement'].includes(transition.action) && !transition.targetId)
        }
        onClick={() => void submitTransition()}
      >
        <Send className="size-4" aria-hidden="true" />
        تنفيذ وتسجيل الإجراء
      </button>
    </section>
  );
}
